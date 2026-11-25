part of 'chat_bloc.dart';

/// The chats list and the open chat, served by the app's own backend
/// instead of Firebase. Same events and states as the Firebase version, so
/// screens don't notice which one runs.
///
/// Lists and messages are loaded over HTTP; the live socket says when
/// something changed, so nothing polls.
mixin _BackendChats on Bloc<ChatEvent, ChatState> {
  final _chatsApi = ChatsApi.instance;

  StreamSubscription<LiveEvent>? _liveSubscription;
  Timer? _chatsReload;

  // Chats list
  List<ChatSummary> _summaries = const [];
  final Map<String, String> _typingInList = {};
  final Map<String, Timer> _typingTimers = {};
  bool _watchingList = false;

  // Open chat
  String? _openCode;
  List<ChatMessage> _openMessages = const [];
  final Map<String, DateTime> _othersRead = {};
  bool _more = false;
  bool _loadingMore = false;
  int _uploads = 0;
  String? _lastReadId;
  int _localIds = 0;

  void _registerBackend() {
    on<CreateChatEvent>(_beCreate);
    on<JoinChatEvent>(_beJoin);
    on<GetChatsEvent>(_beGetChats);
    on<DeleteChatEvent>(_beDeleteChat);
    on<MessagesSubscribeEvent>(_beOpen);
    on<LoadMoreMessagesEvent>(_beLoadMore);
    on<SendMessageEvent>(_beSend);
    on<SendImageEvent>(_beSendImage, transformer: sequential());
    on<SendVoiceEvent>(_beSendVoice);
    on<EditMessageEvent>(_beEdit);
    on<DeleteMessageEvent>(_beDelete);
    on<ToggleReactionEvent>(_beReact);
    on<_BackendLiveInternal>(_beLive);
    on<_BackendChatsReloadInternal>(_beReloadChats);

    _liveSubscription = LiveSocket.instance.events
        .listen((event) => add(_BackendLiveInternal(event)));
  }

  void _emitOpen(Emitter<ChatState> emit) {
    final me = currentUserId();
    DateTime? seen;
    _othersRead.forEach((id, at) {
      if (id != me && (seen == null || at.isAfter(seen!))) seen = at;
    });
    emit(MessagesLoaded(
      _openMessages,
      seenAt: seen,
      hasMore: _more,
      isLoadingMore: _loadingMore,
      isSendingImage: _uploads > 0,
    ));
  }

  /// Shows a failure, then puts the open chat back on screen.
  void _fail(Emitter<ChatState> emit, String message, Object error) {
    debugPrint('$message: $error');
    emit(ChatError(message));
    if (_openCode != null) _emitOpen(emit);
  }

  // Chats list

  Future<void> _beCreate(CreateChatEvent event, Emitter<ChatState> emit) async {
    emit(ChatLoading());
    try {
      final name = event.name.trim();
      emit(ChatCreated(await _chatsApi.create(name), name));
    } catch (e) {
      debugPrint('Creating the chat failed: $e');
      emit(ChatError('Failed to create chat'));
    }
  }

  Future<void> _beJoin(JoinChatEvent event, Emitter<ChatState> emit) async {
    emit(ChatLoading());
    final code = event.code.toUpperCase();
    try {
      await _chatsApi.join(code);
      emit(ChatJoined(code));
    } on ApiException catch (e) {
      emit(ChatError(e.isNotFound ? 'Chat not found' : e.message));
    } catch (e) {
      emit(ChatError(e.toString()));
    }
  }

  Future<void> _beGetChats(GetChatsEvent event, Emitter<ChatState> emit) async {
    if (state is! ChatsLoaded) emit(ChatLoading());
    _watchingList = true;
    await _beReloadChats(const _BackendChatsReloadInternal(), emit);
  }

  Future<void> _beReloadChats(
    _BackendChatsReloadInternal event,
    Emitter<ChatState> emit,
  ) async {
    try {
      _summaries = await _chatsApi.chats();
      _emitChatsList(emit);
    } catch (e) {
      debugPrint('Loading chats failed: $e');
      if (state is! ChatsLoaded) emit(ChatError('Could not load chats'));
    }
  }

  void _emitChatsList(Emitter<ChatState> emit) {
    if (!_watchingList || _openCode != null) return;
    emit(ChatsLoaded([
      for (final chat in _summaries)
        _typingInList[chat.code] == null
            ? chat
            : ChatSummary(
                code: chat.code,
                name: chat.name,
                lastMessage: chat.lastMessage,
                lastSenderId: chat.lastSenderId,
                lastSenderName: chat.lastSenderName,
                lastActivityAt: chat.lastActivityAt,
                hasUnread: chat.hasUnread,
                isOwner: chat.isOwner,
                typingName: _typingInList[chat.code],
                unreadCount: chat.unreadCount,
                photoUrl: chat.photoUrl,
              ),
    ]));
  }

  /// Several changes in a row reload the list once.
  void _reloadChatsSoon() {
    if (!_watchingList) return;
    _chatsReload?.cancel();
    _chatsReload = Timer(const Duration(milliseconds: 300), () {
      if (!isClosed) add(const _BackendChatsReloadInternal());
    });
  }

  Future<void> _beDeleteChat(
    DeleteChatEvent event,
    Emitter<ChatState> emit,
  ) async {
    emit(ChatLoading());
    final code = event.code.toUpperCase();
    try {
      final chat = await _chatsApi.chat(code);
      await _chatsApi.deleteOrLeave(
        code,
        isOwner: chat['ownerId'] == currentUserId(),
      );
      emit(ChatDeleted(code));
    } on ApiException catch (e) {
      emit(ChatError(e.isNotFound ? 'Chat not found' : e.message));
    } catch (e) {
      emit(ChatError(e.toString()));
    }
  }

  // Open chat

  Future<void> _beOpen(
    MessagesSubscribeEvent event,
    Emitter<ChatState> emit,
  ) async {
    emit(ChatLoading());
    _openCode = event.chatCode.toUpperCase();
    _openMessages = const [];
    _othersRead.clear();
    _more = false;
    _loadingMore = false;
    _lastReadId = null;
    await _loadLatest(emit);
  }

  /// Loads the newest page and the read marks; also after reconnecting,
  /// when events may have been missed.
  Future<void> _loadLatest(Emitter<ChatState> emit) async {
    final code = _openCode;
    if (code == null) return;
    try {
      final results = await Future.wait([
        _chatsApi.messages(code, limit: _pageSize),
        _chatsApi.chat(code),
      ]);
      if (_openCode != code) return;
      final latest = results[0] as List<ChatMessage>;
      final chat = results[1] as Map<String, dynamic>;

      // Keep older pages already loaded; the newest page replaces the rest.
      final latestIds = {for (final m in latest) m.id};
      final oldestLatest = latest.isEmpty ? null : latest.first.createdAt;
      final older = _openMessages.where((m) =>
          !latestIds.contains(m.id) &&
          m.createdAt != null &&
          oldestLatest != null &&
          m.createdAt!.isBefore(oldestLatest));
      _openMessages = [...older, ...latest];
      _more = _more || latest.length >= _pageSize;

      _othersRead.clear();
      for (final member in (chat['members'] as List? ?? const [])) {
        final at = DateTime.tryParse('${member['readAt']}');
        if (at != null) _othersRead[member['userId'] as String] = at.toLocal();
      }
      _markRead();
      _emitOpen(emit);
    } catch (e) {
      debugPrint('Loading messages failed: $e');
      emit(ChatError('Could not load messages'));
    }
  }

  static const _pageSize = 30;

  Future<void> _beLoadMore(
    LoadMoreMessagesEvent event,
    Emitter<ChatState> emit,
  ) async {
    final code = _openCode;
    if (code == null || !_more || _loadingMore || _openMessages.isEmpty) {
      return;
    }
    _loadingMore = true;
    _emitOpen(emit);
    try {
      final older = await _chatsApi.messages(
        code,
        before: _openMessages.first.id,
        limit: _pageSize,
      );
      if (_openCode != code) return;
      _openMessages = [...older, ..._openMessages];
      _more = older.length >= _pageSize;
    } catch (e) {
      debugPrint('Loading older messages failed: $e');
    }
    _loadingMore = false;
    _emitOpen(emit);
  }

  /// Tells the backend the user has read the chat, once per new last
  /// message.
  void _markRead() {
    final code = _openCode;
    if (code == null || _openMessages.isEmpty) return;
    final last = _openMessages.last;
    if (last.createdAt == null || last.id == _lastReadId) return;
    _lastReadId = last.id;
    _chatsApi.markRead(code).catchError((Object _) {});
  }

  /// Puts or replaces a message, kept in time order.
  void _upsert(ChatMessage message, {String? replacing}) {
    final list = [
      for (final m in _openMessages)
        if (m.id != message.id && m.id != replacing) m,
    ];
    list.add(message);
    list.sort((a, b) {
      // Messages still sending go last.
      final at = a.createdAt, bt = b.createdAt;
      if (at == null || bt == null) return at == bt ? 0 : (at == null ? 1 : -1);
      return at.compareTo(bt);
    });
    _openMessages = list;
  }

  /// Shows the user's message at once, as "sending", until the backend
  /// confirms it.
  String _showPending(String text, ReplyPreview? replyTo) {
    final id = 'local-${_localIds++}';
    _upsert(ChatMessage(
      id: id,
      text: text,
      senderId: currentUserId() ?? '',
      senderName: '',
      createdAt: null,
      replyTo: replyTo,
    ));
    return id;
  }

  Future<void> _beSend(SendMessageEvent event, Emitter<ChatState> emit) async {
    final code = event.chatCode.toUpperCase();
    final pending = _showPending(event.text, event.replyTo);
    if (_openCode == code) _emitOpen(emit);
    try {
      final sent = await _chatsApi.send(
        code,
        text: event.text,
        replyTo: event.replyTo?.messageId,
      );
      if (_openCode == code) {
        // The socket may have put it in already; this settles it either way.
        _upsert(sent, replacing: pending);
        _markRead();
        _emitOpen(emit);
      }
    } catch (e) {
      _openMessages = [for (final m in _openMessages) if (m.id != pending) m];
      _fail(emit, 'Could not send the message', e);
    }
  }

  Future<void> _beSendImage(
    SendImageEvent event,
    Emitter<ChatState> emit,
  ) async {
    final code = event.chatCode.toUpperCase();
    _uploads++;
    if (state is MessagesLoaded) _emitOpen(emit);
    try {
      // Decoded only for the size, so every client reserves the right
      // space before the picture loads.
      final codec = await ui.instantiateImageCodec(event.bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width, height = frame.image.height;
      frame.image.dispose();

      final key = await _chatsApi.upload(code,
          kind: 'image', contentType: event.contentType, bytes: event.bytes);
      final sent = await _chatsApi.send(code,
          text: event.caption,
          imageKey: key,
          imageWidth: width,
          imageHeight: height,
          replyTo: event.replyTo?.messageId);
      _uploads--;
      if (_openCode == code) {
        _upsert(sent);
        _emitOpen(emit);
      }
    } catch (e) {
      _uploads--;
      _fail(emit, 'Failed to send the photo', e);
    }
  }

  Future<void> _beSendVoice(
    SendVoiceEvent event,
    Emitter<ChatState> emit,
  ) async {
    final code = event.chatCode.toUpperCase();
    final recording = File(event.filePath);
    _uploads++;
    if (state is MessagesLoaded) _emitOpen(emit);
    try {
      final key = await _chatsApi.upload(code,
          kind: 'voice',
          contentType: 'audio/mp4',
          bytes: await recording.readAsBytes());
      final sent = await _chatsApi.send(code,
          audioKey: key,
          audioMs: event.duration.inMilliseconds,
          replyTo: event.replyTo?.messageId);
      _uploads--;
      if (_openCode == code) {
        _upsert(sent);
        _emitOpen(emit);
      }
    } catch (e) {
      _uploads--;
      _fail(emit, 'Failed to send the voice message', e);
    } finally {
      try {
        if (await recording.exists()) await recording.delete();
      } catch (_) {}
    }
  }

  Future<void> _beEdit(EditMessageEvent event, Emitter<ChatState> emit) async {
    try {
      await _chatsApi.edit(event.chatCode, event.messageId, event.text);
    } catch (e) {
      _fail(emit, 'Could not edit the message', e);
    }
  }

  Future<void> _beDelete(
    DeleteMessageEvent event,
    Emitter<ChatState> emit,
  ) async {
    try {
      await _chatsApi.deleteMessage(event.chatCode, event.messageId);
    } catch (e) {
      _fail(emit, 'Could not delete the message', e);
    }
  }

  /// Choosing the reaction the user already left removes it.
  Future<void> _beReact(
    ToggleReactionEvent event,
    Emitter<ChatState> emit,
  ) async {
    final me = currentUserId();
    final message =
        _openMessages.where((m) => m.id == event.messageId).firstOrNull;
    final current = message?.reactions[me];
    final isSame = current != null &&
        Reactions.emojiOf(current) == Reactions.emojiOf(event.reaction);
    try {
      await _chatsApi.react(
        event.chatCode,
        event.messageId,
        isSame ? null : Reactions.emojiOf(event.reaction),
      );
    } catch (e) {
      _fail(emit, 'Could not add the reaction', e);
    }
  }

  // Live events

  Future<void> _beLive(
    _BackendLiveInternal event,
    Emitter<ChatState> emit,
  ) async {
    final e = event.event;
    final me = currentUserId();

    if (e.type == LiveEvent.reconnected) {
      _reloadChatsSoon();
      if (_openCode != null) await _loadLatest(emit);
      return;
    }

    if (e.type == 'typing' && e.chat != null) {
      _showTyping(e.chat!, e.data);
      _emitChatsList(emit);
      return;
    }

    // The list follows anything that changes a chat's row.
    if (e.type.startsWith('message.') ||
        e.type.startsWith('chat.')) {
      _reloadChatsSoon();
    }

    if (e.chat == null || e.chat != _openCode) return;
    switch (e.type) {
      case 'message.created' || 'message.updated':
        final message = ChatsApi.message(e.data as Map<String, dynamic>);
        // The user's own message is already shown as it was sent.
        final isNew = !_openMessages.any((m) => m.id == message.id);
        if (e.type == 'message.updated' && isNew) return;
        // The socket can beat the reply to the send itself: the user's own
        // new message then takes the place of its "sending" copy.
        String? pending;
        if (isNew && message.senderId == me) {
          pending = _openMessages
              .where((m) => m.id.startsWith('local-') && m.text == message.text)
              .firstOrNull
              ?.id;
        }
        _upsert(message, replacing: pending);
        if (message.senderId != me) _markRead();
        _emitOpen(emit);
      case 'message.deleted':
        final id = (e.data as Map)['id'];
        _openMessages = [for (final m in _openMessages) if (m.id != id) m];
        _emitOpen(emit);
      case 'chat.read':
        final data = e.data as Map;
        final at = DateTime.tryParse('${data['readAt']}');
        if (at != null) _othersRead[data['userId'] as String] = at.toLocal();
        _emitOpen(emit);
    }
  }

  /// Someone typing in a chat shows in its row for a few seconds after
  /// their last keystroke mark.
  void _showTyping(String code, Object? data) {
    final name = data is Map ? (data['name'] as String?) : null;
    _typingInList[code] = (name == null || name.isEmpty) ? 'Someone' : name;
    _typingTimers[code]?.cancel();
    _typingTimers[code] = Timer(const Duration(seconds: 6), () {
      _typingInList.remove(code);
      if (!isClosed) add(const _BackendChatsReloadInternal());
    });
  }

  Future<void> _closeBackend() async {
    await _liveSubscription?.cancel();
    _chatsReload?.cancel();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
  }
}

class _BackendLiveInternal extends ChatEvent {
  const _BackendLiveInternal(this.event);
  final LiveEvent event;
}

class _BackendChatsReloadInternal extends ChatEvent {
  const _BackendChatsReloadInternal();
}
