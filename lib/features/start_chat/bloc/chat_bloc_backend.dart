part of 'chat_bloc.dart';

/// The chats list and the open chat, served by the app's own backend
/// instead of Firebase. Same events and states as the Firebase version, so
/// screens don't notice which one runs.
///
/// Lists and messages are loaded over HTTP; the live socket says when
/// something changed, so nothing polls.
mixin _BackendChats on Bloc<ChatEvent, ChatState> {
  final _chatsApi = ChatsApi.instance;
  final _outbox = Outbox.instance;

  StreamSubscription<LiveEvent>? _liveSubscription;
  StreamSubscription<OutboxResult>? _outboxSubscription;
  Timer? _cacheSoon;
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
  String? _lastReadId;

  /// What the open chat shows came from the cache: the backend's first
  /// page replaces all of it, not just the newest part.
  bool _fromCache = false;

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
    on<_OutboxResultInternal>(_beOutboxResult);

    _liveSubscription = LiveSocket.instance.events
        .listen((event) => add(_BackendLiveInternal(event)));
    _outboxSubscription =
        _outbox.results.listen((r) => add(_OutboxResultInternal(r)));
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
      isSendingImage:
          _openCode != null && _outbox.pendingUploads(_openCode!) > 0,
    ));
    _cacheOpenSoon();
  }

  /// Keeps what the open chat shows for its next opening, once things
  /// settle.
  void _cacheOpenSoon() {
    final code = _openCode;
    if (code == null) return;
    _cacheSoon?.cancel();
    _cacheSoon = Timer(const Duration(milliseconds: 800), () {
      if (_openCode == code) _chatsApi.cacheMessages(code, _openMessages);
    });
  }

  /// What the user did here that the backend doesn't know yet, laid over
  /// what it sent: their deletions, edits and reactions, and their
  /// messages still waiting to go.
  List<ChatMessage> _withPending(String code, List<ChatMessage> messages) {
    final me = currentUserId() ?? '';
    final ops = _outbox.forChat(code);
    final deleted = {
      for (final op in ops)
        if (op.type == Outbox.deleteMessage) op.data['id'],
    };
    var list = [
      for (final m in messages)
        if (!deleted.contains(m.id)) m,
    ];
    for (final op in ops) {
      final id = op.data['id'];
      if (op.type == Outbox.edit) {
        list = [
          for (final m in list)
            m.id == id
                ? m.copyWith(text: op.data['text'] as String, isEdited: true)
                : m,
        ];
      } else if (op.type == Outbox.react) {
        list = [
          for (final m in list)
            m.id == id ? _reacted(m, me, op.data['emoji'] as String?) : m,
        ];
      }
    }
    final shown = {for (final m in list) m.id};
    return [
      ...list,
      for (final m in _outbox.pendingMessages(code, me))
        if (!shown.contains(m.id)) m,
    ];
  }

  static ChatMessage _reacted(ChatMessage m, String me, String? emoji) {
    final reactions = Map<String, String>.from(m.reactions);
    if (emoji == null) {
      reactions.remove(me);
    } else {
      reactions[me] = emoji;
    }
    return m.copyWith(reactions: reactions);
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
    _watchingList = true;
    if (state is! ChatsLoaded) {
      // What was here last time shows at once; the backend's list follows.
      final cached = await _chatsApi.cachedChats();
      if (cached != null) {
        _summaries = cached;
        _emitChatsList(emit);
      } else {
        emit(ChatLoading());
      }
    }
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
      // With a list on screen, stale is better than an error.
      if (state is! ChatsLoaded) {
        emit(ChatError('No connection'));
        _summaries = const [];
        _emitChatsList(emit);
      }
    }
  }

  void _emitChatsList(Emitter<ChatState> emit) {
    if (!_watchingList || _openCode != null) return;
    // Chats deleted here stay gone even before the backend has heard.
    final deleted = _outbox.deletedChats;
    final me = currentUserId();
    final rows = <ChatSummary>[];
    for (final chat in _summaries) {
      if (deleted.contains(chat.code)) continue;
      // The user's newest message still waiting to go shows as the last.
      final waiting = _outbox.pendingMessages(chat.code, me ?? '').lastOrNull;
      final typing = _typingInList[chat.code];
      rows.add(waiting == null && typing == null
          ? chat
          : ChatSummary(
              code: chat.code,
              name: chat.name,
              lastMessage: waiting?.text ?? chat.lastMessage,
              lastSenderId: waiting == null ? chat.lastSenderId : me,
              lastSenderName: chat.lastSenderName,
              lastActivityAt:
                  waiting == null ? chat.lastActivityAt : DateTime.now(),
              hasUnread: chat.hasUnread,
              isOwner: chat.isOwner,
              typingName: typing,
              unreadCount: chat.unreadCount,
              photoUrl: chat.photoUrl,
              direct: chat.direct,
            ));
    }
    emit(ChatsLoaded(rows));
  }

  /// Several changes in a row reload the list once.
  void _reloadChatsSoon() {
    if (!_watchingList) return;
    _chatsReload?.cancel();
    _chatsReload = Timer(const Duration(milliseconds: 300), () {
      if (!isClosed) add(const _BackendChatsReloadInternal());
    });
  }

  /// Gone from the list at once; the backend hears of it when it can.
  Future<void> _beDeleteChat(
    DeleteChatEvent event,
    Emitter<ChatState> emit,
  ) async {
    final code = event.code.toUpperCase();
    final summary = _summaries.where((c) => c.code == code).firstOrNull;
    await _outbox.add(OutboxOp(
      id: _outbox.newLocalId(),
      type: Outbox.deleteChat,
      chat: code,
      // Unknown in the open chat: the outbox asks the backend.
      data: {'isOwner': summary?.isOwner},
    ));
    _summaries = [for (final c in _summaries) if (c.code != code) c];
    unawaited(_chatsApi.forgetCachedChat(code));
    emit(ChatDeleted(code));
    _emitChatsList(emit);
  }

  // Open chat

  Future<void> _beOpen(
    MessagesSubscribeEvent event,
    Emitter<ChatState> emit,
  ) async {
    final code = event.chatCode.toUpperCase();
    _openCode = code;
    _openMessages = const [];
    _othersRead.clear();
    _more = false;
    _loadingMore = false;
    _lastReadId = null;
    // The messages seen last time show at once, with what is waiting to
    // go; the backend's newest page replaces them when it arrives.
    final cached = await _chatsApi.cachedMessages(code);
    if (_openCode != code) return;
    _openMessages = _withPending(code, cached ?? const []);
    _fromCache = true;
    if (cached != null || _openMessages.isNotEmpty) {
      _emitOpen(emit);
    } else {
      emit(ChatLoading());
    }
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
          !_fromCache &&
          !latestIds.contains(m.id) &&
          m.createdAt != null &&
          oldestLatest != null &&
          m.createdAt!.isBefore(oldestLatest));
      final keptOlder = older.toList();
      _openMessages = _withPending(code, [...keptOlder, ...latest]);
      _more = latest.length >= _pageSize || keptOlder.isNotEmpty || _more;
      _fromCache = false;

      _othersRead.clear();
      for (final member in (chat['members'] as List? ?? const [])) {
        final at = DateTime.tryParse('${member['readAt']}');
        if (at != null) _othersRead[member['userId'] as String] = at.toLocal();
      }
      _markRead();
      _emitOpen(emit);
    } catch (e) {
      debugPrint('Loading messages failed: $e');
      if (_openCode != code) return;
      // Offline: what is on screen stays; it reloads on reconnecting.
      if (state is! MessagesLoaded) {
        emit(ChatError('No connection'));
        _emitOpen(emit);
      }
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
      final oldest = _openMessages.firstWhere((m) => !m.isLocal,
          orElse: () => _openMessages.first);
      if (oldest.isLocal) throw StateError('Nothing sent to page from');
      final older = await _chatsApi.messages(
        code,
        before: oldest.id,
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
    final last = _openMessages.lastWhere((m) => !m.isLocal,
        orElse: () => _openMessages.last);
    if (last.isLocal || last.id == _lastReadId) return;
    _lastReadId = last.id;
    // Offline: tried again on the next change or reconnect.
    _chatsApi.markRead(code).catchError((Object _) => _lastReadId = null);
  }

  /// Puts or replaces a message, kept in time order.
  void _upsert(ChatMessage message, {String? replacing}) {
    final list = [
      for (final m in _openMessages)
        if (m.id != message.id && m.id != replacing) m,
    ];
    list.add(message);
    list.sort((a, b) {
      // Messages still sending go last, in the order they were written
      // (their ids grow).
      final at = a.createdAt, bt = b.createdAt;
      if (at == null && bt == null) return a.id.compareTo(b.id);
      if (at == null || bt == null) return at == null ? 1 : -1;
      return at.compareTo(bt);
    });
    _openMessages = list;
  }

  /// The user's message shows at once, as "sending", and goes out through
  /// the outbox: now, or when the internet is back.
  Future<void> _beSend(SendMessageEvent event, Emitter<ChatState> emit) async {
    final code = event.chatCode.toUpperCase();
    final localId = _outbox.newLocalId();
    await _outbox.add(OutboxOp(
      id: localId,
      type: Outbox.sendText,
      chat: code,
      data: {
        'localId': localId,
        'text': event.text,
        if (event.replyTo != null) 'replyTo': event.replyTo!.toMap(),
      },
    ));
    if (_openCode == code) {
      _openMessages = _withPending(code, _openMessages);
      _emitOpen(emit);
    }
  }

  /// A photo waits in the outbox, kept in a file, until it is uploaded.
  Future<void> _beSendImage(
    SendImageEvent event,
    Emitter<ChatState> emit,
  ) async {
    final code = event.chatCode.toUpperCase();
    try {
      // Decoded only for the size, so every client reserves the right
      // space before the picture loads.
      final codec = await ui.instantiateImageCodec(event.bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width, height = frame.image.height;
      frame.image.dispose();
      final ext = event.contentType == 'image/png' ? '.png' : '.jpg';
      final localId = _outbox.newLocalId();
      await _outbox.add(OutboxOp(
        id: localId,
        type: Outbox.sendImage,
        chat: code,
        data: {
          'localId': localId,
          'path': await _outbox.keepFile(event.bytes, ext),
          'contentType': event.contentType,
          'caption': event.caption,
          'width': width,
          'height': height,
          if (event.replyTo != null) 'replyTo': event.replyTo!.toMap(),
        },
      ));
      if (_openCode == code) _emitOpen(emit);
    } catch (e) {
      _fail(emit, 'Failed to send the photo', e);
    }
  }

  Future<void> _beSendVoice(
    SendVoiceEvent event,
    Emitter<ChatState> emit,
  ) async {
    final code = event.chatCode.toUpperCase();
    final recording = File(event.filePath);
    try {
      final localId = _outbox.newLocalId();
      await _outbox.add(OutboxOp(
        id: localId,
        type: Outbox.sendVoice,
        chat: code,
        data: {
          'localId': localId,
          'path': await _outbox.keepFile(await recording.readAsBytes(), '.m4a'),
          'ms': event.duration.inMilliseconds,
          if (event.replyTo != null) 'replyTo': event.replyTo!.toMap(),
        },
      ));
      if (_openCode == code) _emitOpen(emit);
    } catch (e) {
      _fail(emit, 'Failed to send the voice message', e);
    } finally {
      try {
        if (await recording.exists()) await recording.delete();
      } catch (_) {}
    }
  }

  /// A send, edit or deletion went through, or the backend refused it.
  Future<void> _beOutboxResult(
    _OutboxResultInternal event,
    Emitter<ChatState> emit,
  ) async {
    final result = event.result;
    final op = result.op;
    final error = result.error;

    if (op.type == Outbox.deleteChat) {
      // Refused (say, the owner can't leave): it comes back.
      if (error != null && _watchingList) {
        emit(ChatError(error));
        _reloadChatsSoon();
      }
      return;
    }
    if (_openCode == op.chat) {
      final localId = op.data['localId'] as String?;
      final sent = result.sent;
      if (sent != null) {
        // The socket may have put it in already; this settles it either way.
        _upsert(sent, replacing: localId);
        _markRead();
      } else if (error != null) {
        if (localId != null) {
          _openMessages = [for (final m in _openMessages) if (m.id != localId) m];
        }
        emit(ChatError(error));
        // What the backend has is the truth again.
        unawaited(_loadLatest(emit));
      }
      _emitOpen(emit);
    }
    if (_watchingList && (result.sent != null || error != null)) {
      _reloadChatsSoon();
    }
  }

  /// The new text shows at once; the backend hears when it can.
  Future<void> _beEdit(EditMessageEvent event, Emitter<ChatState> emit) async {
    final code = event.chatCode.toUpperCase();
    final id = event.messageId;
    final isLocal = id.startsWith('local-');
    if (!isLocal || !await _outbox.editPending(id, event.text)) {
      if (isLocal) {
        // Already on its way: edited once it has an id.
        return _fail(emit, 'Wait a moment, it is still sending', id);
      }
      await _outbox.add(OutboxOp(
        id: _outbox.newLocalId(),
        type: Outbox.edit,
        chat: code,
        data: {'id': id, 'text': event.text},
      ));
    }
    if (_openCode == code) {
      _openMessages = [
        for (final m in _openMessages)
          m.id == id ? m.copyWith(text: event.text, isEdited: !isLocal) : m,
      ];
      _emitOpen(emit);
    }
  }

  /// Gone at once; a message not sent yet simply never goes.
  Future<void> _beDelete(
    DeleteMessageEvent event,
    Emitter<ChatState> emit,
  ) async {
    final code = event.chatCode.toUpperCase();
    final id = event.messageId;
    if (id.startsWith('local-')) {
      if (!await _outbox.cancelSend(id)) {
        return _fail(emit, 'Wait a moment, it is still sending', id);
      }
    } else {
      await _outbox.add(OutboxOp(
        id: _outbox.newLocalId(),
        type: Outbox.deleteMessage,
        chat: code,
        data: {'id': id},
      ));
    }
    if (_openCode == code) {
      _openMessages = [for (final m in _openMessages) if (m.id != id) m];
      _emitOpen(emit);
    }
  }

  /// Choosing the reaction the user already left removes it. Shows at
  /// once.
  Future<void> _beReact(
    ToggleReactionEvent event,
    Emitter<ChatState> emit,
  ) async {
    final code = event.chatCode.toUpperCase();
    final me = currentUserId() ?? '';
    final message =
        _openMessages.where((m) => m.id == event.messageId).firstOrNull;
    if (message == null || message.isLocal) return;
    final current = message.reactions[me];
    final isSame = current != null &&
        Reactions.emojiOf(current) == Reactions.emojiOf(event.reaction);
    // Kept as the backend keeps it, the emoji itself.
    final emoji = isSame ? null : Reactions.emojiOf(event.reaction);
    await _outbox.add(OutboxOp(
      id: _outbox.newLocalId(),
      type: Outbox.react,
      chat: code,
      data: {'id': message.id, 'emoji': emoji},
    ));
    if (_openCode == code) {
      _openMessages = [
        for (final m in _openMessages)
          m.id == message.id ? _reacted(m, me, emoji) : m,
      ];
      _emitOpen(emit);
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
    // Stopped typing, or sent the message: the row shows it at once.
    if ((e.type == 'typing.stop' || e.type == 'message.created') &&
        e.chat != null &&
        _typingInList.remove(e.chat) != null) {
      _typingTimers.remove(e.chat)?.cancel();
      _emitChatsList(emit);
    }
    if (e.type == 'typing.stop') return;

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
    await _outboxSubscription?.cancel();
    _chatsReload?.cancel();
    _cacheSoon?.cancel();
    final code = _openCode;
    if (code != null) unawaited(_chatsApi.cacheMessages(code, _openMessages));
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

class _OutboxResultInternal extends ChatEvent {
  const _OutboxResultInternal(this.result);
  final OutboxResult result;
}
