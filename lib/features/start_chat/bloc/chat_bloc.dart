import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/api/api_client.dart';
import 'package:sinai/api/api_config.dart';
import 'package:sinai/api/auth_api.dart';
import 'package:sinai/api/chats_api.dart';
import 'package:sinai/api/current_user.dart';
import 'package:sinai/api/live_socket.dart';
import 'package:sinai/common/onboarding_prefs.dart';
import 'package:sinai/features/chat/models/chat_message_model.dart';
import 'package:sinai/features/chat/widgets/reactions.dart';
import 'package:sinai/features/chats/models/chat_summary.dart';
import 'package:sinai/features/presence/presence_service.dart';
import 'package:sinai/features/presence/realtime_db.dart';

part 'chat_event.dart';
part 'chat_state.dart';
part 'chat_bloc_backend.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> with _BackendChats {
  // Only touched on the Firebase path.
  late final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  ChatBloc() : super(ChatInitial()) {
    on<SetUserNameEvent>(_onSetUserName);
    if (ApiConfig.useBackend) {
      _registerBackend();
      return;
    }
    on<CreateChatEvent>(_onCreateChat);
    on<JoinChatEvent>(_onJoinChat);
    on<SendMessageEvent>(_onSendMessage);
    // One at a time, so several photos arrive in the order they were picked.
    on<SendImageEvent>(_onSendImage, transformer: sequential());
    on<SendVoiceEvent>(_onSendVoice);
    on<ToggleReactionEvent>(_onToggleReaction);
    on<EditMessageEvent>(_onEditMessage);
    on<DeleteMessageEvent>(_onDeleteMessage);
    on<MessagesSubscribeEvent>(_onMessagesSubscribe);
    on<GetChatsEvent>(_onGetChats);
    on<DeleteChatEvent>(_onDeleteChat);
    on<_ChatsSnapshotInternal>(_onChatsSnapshot);
    on<_ChatsChangedInternal>((event, emit) => _emitChats(emit));
    on<_ChatsFailedInternal>((event, emit) => emit(ChatError(event.message)));
    on<LoadMoreMessagesEvent>(_onLoadMoreMessages);
    on<_MessagesUpdatedInternal>((event, emit) {
      _messages = event.messages;
      // A full window means there may be older messages beyond it.
      _hasMoreMessages = _messages.length >= _messagesLimit;
      _loadingMoreMessages = false;
      _markChatRead();
      _emitMessages(emit);
    });
    on<_ReadMarksUpdatedInternal>((event, emit) {
      // Messages not loaded yet; the mark is emitted together with them.
      if (state is! MessagesLoaded) return;
      _emitMessages(emit);
    });
  }

  Future<void> _onSetUserName(
    SetUserNameEvent event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        emit(ChatError('User not authenticated'));
        return;
      }

      await user.updateDisplayName(event.name);
      // Kept in step on the backend while both are in use.
      if (ApiConfig.useBackend) await AuthApi.instance.rename(event.name);
      await OnboardingPrefs.setNameConfirmed();
      await PresenceService.instance.refreshName();
      emit(UserNameSaved(event.name));
    } catch (e) {
      emit(ChatError('Failed to save user name'));
    }
  }

  String _generateChatCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<void> _onCreateChat(
    CreateChatEvent event,
    Emitter<ChatState> emit,
  ) async {
    emit(ChatLoading());

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        emit(ChatError('User not authenticated'));
        return;
      }

      final name = event.name.trim();

      // A random code can collide with an existing chat, and writing over
      // it would wipe that chat, so claim the code only if it is free.
      String? chatCode;
      for (var attempt = 0; attempt < 5 && chatCode == null; attempt++) {
        final candidate = _generateChatCode();
        final chatRef = _firestore.collection('chats').doc(candidate);

        final created = await _firestore.runTransaction<bool>((tx) async {
          final existing = await tx.get(chatRef);
          if (existing.exists) return false;

          tx.set(chatRef, {
            'code': candidate,
            'name': name,
            'ownerId': user.uid,
            'participantIds': [user.uid],
            'createdAt': FieldValue.serverTimestamp(),
          });
          return true;
        });

        if (created) chatCode = candidate;
      }

      if (chatCode == null) {
        emit(ChatError('Failed to create chat'));
        return;
      }

      emit(ChatCreated(chatCode, name));
    } catch (e) {
      emit(ChatError('Failed to create chat'));
    }
  }

  Future<void> _onJoinChat(
    JoinChatEvent event,
    Emitter<ChatState> emit,
  ) async {
    emit(ChatLoading());

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        emit(ChatError('User not authenticated'));
        return;
      }

      final code = event.code.toUpperCase();
      final doc = await _firestore.collection('chats').doc(code).get();

      if (!doc.exists) {
        emit(ChatError('Chat not found'));
        return;
      }

      await _firestore.collection('chats').doc(code).update({
        'participantIds': FieldValue.arrayUnion([user.uid]),
      });

      emit(ChatJoined(code));
    } catch (e) {
      emit(ChatError(e.toString()));
    }
  }

  StreamSubscription? _chatsSubscription;

  /// One listener per chat for its latest message, keyed by chat document id.
  final Map<String, StreamSubscription> _lastMessageSubscriptions = {};

  /// One Realtime Database listener per chat for who is typing in it.
  final Map<String, StreamSubscription> _typingSubscriptions = {};

  /// Name of someone else typing, by chat document id.
  final Map<String, String> _typingNames = {};

  /// Unread message count by chat document id, and what it was counted
  /// for (last message and read mark), to count again only on change.
  final Map<String, int> _unreadCounts = {};
  final Map<String, String> _unreadCountedFor = {};

  /// Latest message data per chat document id; a null value means the chat
  /// has no messages (or its preview could not be loaded).
  final Map<String, Map<String, dynamic>?> _lastMessages = {};

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _chatDocs = const [];

  /// Subscribes to the user's chats and to the latest message of each, so
  /// the list follows new chats and new messages without a manual refresh.
  Future<void> _onGetChats(
    GetChatsEvent event,
    Emitter<ChatState> emit,
  ) async {
    // Keep showing the current list while a refresh is re-subscribing.
    if (state is! ChatsLoaded) emit(ChatLoading());

    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      emit(ChatError('User not authenticated'));
      return;
    }

    await _cancelChatsSubscriptions();

    _chatsSubscription = _firestore
        .collection('chats')
        .where('participantIds', arrayContains: user.uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
          (snapshot) => add(_ChatsSnapshotInternal(snapshot.docs)),
          onError: (Object e) => add(_ChatsFailedInternal(e.toString())),
        );
  }

  Future<void> _cancelChatsSubscriptions() async {
    await _chatsSubscription?.cancel();
    _chatsSubscription = null;
    for (final subscription in _lastMessageSubscriptions.values) {
      await subscription.cancel();
    }
    _lastMessageSubscriptions.clear();
    _lastMessages.clear();
    for (final subscription in _typingSubscriptions.values) {
      await subscription.cancel();
    }
    _typingSubscriptions.clear();
    _typingNames.clear();
    _unreadCounts.clear();
    _unreadCountedFor.clear();
    _chatDocs = const [];
  }

  void _onChatsSnapshot(
    _ChatsSnapshotInternal event,
    Emitter<ChatState> emit,
  ) {
    _chatDocs = event.docs;
    final ids = {for (final doc in event.docs) doc.id};

    // Stop listening to chats the user is no longer in.
    for (final id in _lastMessageSubscriptions.keys.toList()) {
      if (ids.contains(id)) continue;
      _lastMessageSubscriptions.remove(id)?.cancel();
      _lastMessages.remove(id);
      _typingSubscriptions.remove(id)?.cancel();
      _typingNames.remove(id);
    }

    for (final doc in event.docs) {
      final id = doc.id;
      if (_lastMessageSubscriptions.containsKey(id)) continue;

      _typingSubscriptions[id] = RealtimeDb.typing(id).onValue.listen(
        (event) {
          final name = _typingNameIn(event.snapshot.value);
          if (name == _typingNames[id]) return;
          if (name == null) {
            _typingNames.remove(id);
          } else {
            _typingNames[id] = name;
          }
          add(const _ChatsChangedInternal());
        },
        onError: (Object _) {},
      );

      _lastMessageSubscriptions[id] = doc.reference
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots()
          .listen(
        (snapshot) {
          _lastMessages[id] =
              snapshot.docs.isEmpty ? null : snapshot.docs.first.data();
          add(const _ChatsChangedInternal());
        },
        onError: (Object _) {
          // The list is still useful without this chat's preview.
          _lastMessages[id] = null;
          add(const _ChatsChangedInternal());
        },
      );
    }

    _emitChats(emit);
  }

  void _emitChats(Emitter<ChatState> emit) {
    // On first load wait for every chat's preview, so rows don't flash
    // "No messages yet" before their last message arrives.
    final previewsReady = _chatDocs.every(
      (doc) => _lastMessages.containsKey(doc.id),
    );
    if (!previewsReady && state is! ChatsLoaded) return;

    final chats = _chatDocs.map(_buildChatSummary).toList();

    // Most recently active chats first.
    chats.sort((a, b) {
      final aTime = a.lastActivityAt;
      final bTime = b.lastActivityAt;
      if (aTime == null || bTime == null) {
        return aTime == bTime ? 0 : (aTime == null ? 1 : -1);
      }
      return bTime.compareTo(aTime);
    });

    emit(ChatsLoaded(chats));
  }

  ChatSummary _buildChatSummary(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final name = (data['name'] as String?)?.trim() ?? '';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final last = _lastMessages[doc.id];
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final lastAt = last == null
        ? null
        // The server timestamp is still pending right after sending.
        : (last['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
    final myReadAt = uid == null ? null : _readMarks(data)[uid];
    final hasUnread = lastAt != null &&
        last?['senderId'] != uid &&
        (myReadAt == null || lastAt.isAfter(myReadAt));
    _countUnread(doc, hasUnread: hasUnread, lastAt: lastAt, readAt: myReadAt);

    return ChatSummary(
      isOwner: uid != null && data['ownerId'] == uid,
      code: (data['code'] as String?) ?? doc.id,
      name: name.isEmpty ? null : name,
      lastMessage: _previewText(last),
      lastSenderId: last?['senderId'] as String?,
      lastSenderName: last?['senderName'] as String?,
      lastActivityAt: lastAt ?? createdAt,
      hasUnread: hasUnread,
      typingName: _typingNames[doc.id],
      photoUrl: data['photoUrl'] as String?,
      unreadCount: hasUnread ? _unreadCounts[doc.id] : 0,
    );
  }

  /// Counts messages newer than the user's read mark with a server-side
  /// count query (one read per 1000 messages). Runs again only when the
  /// chat's last message or read mark changes; the result arrives later
  /// and refreshes the list.
  void _countUnread(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required bool hasUnread,
    required DateTime? lastAt,
    required DateTime? readAt,
  }) {
    final id = doc.id;
    if (!hasUnread) {
      _unreadCounts[id] = 0;
      _unreadCountedFor.remove(id);
      return;
    }

    final key = '${lastAt?.millisecondsSinceEpoch}|'
        '${readAt?.millisecondsSinceEpoch}';
    if (_unreadCountedFor[id] == key) return;
    _unreadCountedFor[id] = key;

    Query<Map<String, dynamic>> query = doc.reference.collection('messages');
    if (readAt != null) {
      query = query.where(
        'createdAt',
        isGreaterThan: Timestamp.fromDate(readAt),
      );
    }

    query.count().get().then((result) {
      // A newer count may have started meanwhile.
      if (_unreadCountedFor[id] != key || isClosed) return;
      _unreadCounts[id] = result.count ?? 0;
      add(const _ChatsChangedInternal());
    }).catchError((Object e) {
      debugPrint('Counting unread messages failed: $e');
    });
  }

  /// Name of someone other than the user in a chat's typing marks.
  String? _typingNameIn(Object? typing) {
    if (typing is! Map) return null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    for (final entry in typing.entries) {
      if (entry.key == uid || entry.value is! Map) continue;
      return ((entry.value as Map)['name'] as String?) ?? 'Someone';
    }
    return null;
  }

  /// Text shown for a message in the chats list; pictures have no text of
  /// their own.
  String? _previewText(Map<String, dynamic>? message) {
    if (message == null) return null;
    final text = (message['text'] as String?) ?? '';
    if (text.isEmpty && message['imageUrl'] != null) return 'Photo';
    if (text.isEmpty && message['audioUrl'] != null) return 'Voice message';
    return text;
  }

  /// When each participant last read the chat, by user id.
  Map<String, DateTime> _readMarks(Map<String, dynamic>? chatData) {
    final raw = chatData?['readAt'];
    if (raw is! Map) return const {};

    return {
      for (final entry in raw.entries)
        // A null value is a server timestamp that is still being written.
        entry.key as String:
            (entry.value as Timestamp?)?.toDate() ?? DateTime.now(),
    };
  }

  Future<void> _onDeleteChat(
    DeleteChatEvent event,
    Emitter<ChatState> emit,
  ) async {
    emit(ChatLoading());

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        emit(ChatError('User not authenticated'));
        return;
      }

      final code = event.code.toUpperCase();
      final chatRef = _firestore.collection('chats').doc(code);
      final chatDoc = await chatRef.get();

      if (!chatDoc.exists) {
        emit(ChatError('Chat not found'));
        return;
      }

      final data = chatDoc.data() ?? <String, dynamic>{};
      final participants =
          (data['participantIds'] as List<dynamic>? ?? const []).cast<String>();

      if (!participants.contains(user.uid)) {
        emit(ChatError('No permission to delete this chat'));
        return;
      }

      final ownerId = data['ownerId'] as String?;

      if (ownerId == user.uid) {
        // Messages and their files are removed by the cleanUpDeletedChat
        // Cloud Function. Users may delete only their own messages, so the
        // owner cannot clear other people's messages from here.
        await chatRef.delete();
      } else {
        await chatRef.update({
          'participantIds': FieldValue.arrayRemove([user.uid]),
        });
      }

      emit(ChatDeleted(code));
    } catch (e) {
      emit(ChatError(e.toString()));
    }
  }

  StreamSubscription? _messagesSubscription;

  Future<void> _onSendMessage(
    SendMessageEvent event,
    Emitter<ChatState> emit,
  ) async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        emit(ChatError('User not authenticated'));
        return;
      }

      final senderName =
          user.displayName?.isNotEmpty == true ? user.displayName! : 'Guest';

      await _firestore
          .collection('chats')
          .doc(event.chatCode)
          .collection('messages')
          .add({
        'text': event.text,
        'senderId': user.uid,
        'senderName': senderName,
        'createdAt': FieldValue.serverTimestamp(),
        if (event.replyTo != null) 'replyTo': event.replyTo!.toMap(),
      });
    } catch (e) {
      emit(ChatError(e.toString()));
      // Put the messages back; the error state replaced them on screen.
      if (_openChatCode != null) _emitMessages(emit);
    }
  }

  Future<void> _onEditMessage(
    EditMessageEvent event,
    Emitter<ChatState> emit,
  ) async {
    try {
      await _firestore
          .collection('chats')
          .doc(event.chatCode)
          .collection('messages')
          .doc(event.messageId)
          .update({
        'text': event.text,
        'editedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Editing the message failed: $e');
      emit(ChatError('Could not edit the message'));
      if (_openChatCode != null) _emitMessages(emit);
    }
  }

  /// Its photo or voice file is removed from Storage by the
  /// cleanUpDeletedMessage Cloud Function.
  Future<void> _onDeleteMessage(
    DeleteMessageEvent event,
    Emitter<ChatState> emit,
  ) async {
    try {
      await _firestore
          .collection('chats')
          .doc(event.chatCode)
          .collection('messages')
          .doc(event.messageId)
          .delete();
    } catch (e) {
      debugPrint('Deleting the message failed: $e');
      emit(ChatError('Could not delete the message'));
      if (_openChatCode != null) _emitMessages(emit);
    }
  }

  /// Sets the user's reaction on a message; choosing the reaction they
  /// already left removes it.
  Future<void> _onToggleReaction(
    ToggleReactionEvent event,
    Emitter<ChatState> emit,
  ) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    ChatMessage? message;
    for (final candidate in _messages) {
      if (candidate.id == event.messageId) message = candidate;
    }
    // Old reactions were stored as words like "love"; compare as emoji.
    final current = message?.reactions[uid];
    final isSame = current != null &&
        Reactions.emojiOf(current) == Reactions.emojiOf(event.reaction);

    try {
      await _firestore
          .collection('chats')
          .doc(event.chatCode)
          .collection('messages')
          .doc(event.messageId)
          .update({
        'reactions.$uid': isSame ? FieldValue.delete() : event.reaction,
      });
    } catch (e) {
      debugPrint('Reacting failed: $e');
      emit(ChatError('Could not add the reaction'));
      if (_openChatCode != null) _emitMessages(emit);
    }
  }

  /// Pictures and voice messages currently being uploaded from this device.
  int _uploadingImages = 0;

  Future<void> _onSendImage(
    SendImageEvent event,
    Emitter<ChatState> emit,
  ) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      emit(ChatError('User not authenticated'));
      return;
    }

    _uploadingImages++;
    if (state is MessagesLoaded) _emitMessages(emit);

    try {
      // Decoded only to learn the size, which lets every client reserve
      // the right space for the picture before it has loaded.
      final codec = await ui.instantiateImageCodec(event.bytes);
      final frame = await codec.getNextFrame();
      final width = frame.image.width;
      final height = frame.image.height;
      frame.image.dispose();

      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${user.uid}.jpg';
      final ref = FirebaseStorage.instance
          .ref('chats/${event.chatCode}/images/$fileName');

      await ref.putData(
        event.bytes,
        SettableMetadata(contentType: event.contentType),
      );
      final imageUrl = await ref.getDownloadURL();

      final senderName =
          user.displayName?.isNotEmpty == true ? user.displayName! : 'Guest';

      await _firestore
          .collection('chats')
          .doc(event.chatCode)
          .collection('messages')
          .add({
        'text': event.caption,
        'imageUrl': imageUrl,
        'imageWidth': width,
        'imageHeight': height,
        'senderId': user.uid,
        'senderName': senderName,
        'createdAt': FieldValue.serverTimestamp(),
        if (event.replyTo != null) 'replyTo': event.replyTo!.toMap(),
      });

      _uploadingImages--;
      if (state is MessagesLoaded) _emitMessages(emit);
    } catch (e) {
      _uploadingImages--;
      debugPrint('Sending the photo failed: $e');
      emit(ChatError('Failed to send the photo'));
      if (_openChatCode != null) _emitMessages(emit);
    }
  }

  Future<void> _onSendVoice(
    SendVoiceEvent event,
    Emitter<ChatState> emit,
  ) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      emit(ChatError('User not authenticated'));
      return;
    }

    _uploadingImages++;
    if (state is MessagesLoaded) _emitMessages(emit);

    final recording = File(event.filePath);

    try {
      final fileName =
          '${DateTime.now().millisecondsSinceEpoch}_${user.uid}.m4a';
      final ref = FirebaseStorage.instance
          .ref('chats/${event.chatCode}/audio/$fileName');

      await ref.putFile(recording, SettableMetadata(contentType: 'audio/mp4'));
      final audioUrl = await ref.getDownloadURL();

      final senderName =
          user.displayName?.isNotEmpty == true ? user.displayName! : 'Guest';

      await _firestore
          .collection('chats')
          .doc(event.chatCode)
          .collection('messages')
          .add({
        'text': '',
        'audioUrl': audioUrl,
        'audioDurationMs': event.duration.inMilliseconds,
        'senderId': user.uid,
        'senderName': senderName,
        'createdAt': FieldValue.serverTimestamp(),
        if (event.replyTo != null) 'replyTo': event.replyTo!.toMap(),
      });

      _uploadingImages--;
      if (state is MessagesLoaded) _emitMessages(emit);
    } catch (e) {
      _uploadingImages--;
      debugPrint('Sending the voice message failed: $e');
      emit(ChatError('Failed to send the voice message'));
      if (_openChatCode != null) _emitMessages(emit);
    } finally {
      // The temporary recording is no longer needed either way.
      try {
        if (await recording.exists()) await recording.delete();
      } catch (_) {}
    }
  }

  StreamSubscription? _chatDocSubscription;
  String? _openChatCode;
  List<ChatMessage> _messages = const [];

  /// Latest time any other participant read the open chat.
  DateTime? _othersReadAt;

  /// Id of the last incoming message already reported as read.
  String? _lastMarkedMessageId;

  Future<void> _onMessagesSubscribe(
    MessagesSubscribeEvent event,
    Emitter<ChatState> emit,
  ) async {
    emit(ChatLoading());

    await _messagesSubscription?.cancel();
    await _chatDocSubscription?.cancel();

    _openChatCode = event.chatCode;
    _messages = const [];
    _othersReadAt = null;
    _lastMarkedMessageId = null;

    final chatRef = _firestore.collection('chats').doc(event.chatCode);

    // Read marks live on the chat document, so "seen" shows up without a
    // refresh as soon as someone else opens the chat.
    _chatDocSubscription = chatRef.snapshots().listen(
      (snapshot) {
        final uid = FirebaseAuth.instance.currentUser?.uid;
        DateTime? latest;
        _readMarks(snapshot.data()).forEach((id, readAt) {
          if (id == uid) return;
          if (latest == null || readAt.isAfter(latest!)) latest = readAt;
        });
        if (latest == _othersReadAt) return;
        _othersReadAt = latest;
        add(const _ReadMarksUpdatedInternal());
      },
      onError: (Object _) {},
    );

    _messagesLimit = _messagesPageSize;
    _hasMoreMessages = false;
    _loadingMoreMessages = false;
    _subscribeToMessages();
  }

  static const _messagesPageSize = 30;

  /// How many of the latest messages the open chat currently listens to.
  int _messagesLimit = _messagesPageSize;
  bool _hasMoreMessages = false;
  bool _loadingMoreMessages = false;

  void _emitMessages(Emitter<ChatState> emit) {
    emit(
      MessagesLoaded(
        _messages,
        seenAt: _othersReadAt,
        hasMore: _hasMoreMessages,
        isLoadingMore: _loadingMoreMessages,
        isSendingImage: _uploadingImages > 0,
      ),
    );
  }

  /// Widens the live window by one page of older messages.
  Future<void> _onLoadMoreMessages(
    LoadMoreMessagesEvent event,
    Emitter<ChatState> emit,
  ) async {
    if (state is! MessagesLoaded) return;
    if (!_hasMoreMessages || _loadingMoreMessages) return;

    _loadingMoreMessages = true;
    _messagesLimit += _messagesPageSize;
    _emitMessages(emit);

    await _messagesSubscription?.cancel();
    _subscribeToMessages();
  }

  /// Listens to the latest [_messagesLimit] messages of the open chat.
  void _subscribeToMessages() {
    final chatCode = _openChatCode;
    if (chatCode == null) return;

    _messagesSubscription = _firestore
        .collection('chats')
        .doc(chatCode)
        .collection('messages')
        .orderBy('createdAt')
        .limitToLast(_messagesLimit)
        .snapshots()
        .listen((snapshot) {
      final messages = snapshot.docs.map((doc) {
        final data = doc.data();
        return ChatMessage(
          id: doc.id,
          text: data['text'] ?? '',
          senderId: data['senderId'] ?? '',
          senderName: data['senderName'] ?? 'Guest',
          createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
          imageUrl: data['imageUrl'] as String?,
          imageWidth: (data['imageWidth'] as num?)?.toInt(),
          imageHeight: (data['imageHeight'] as num?)?.toInt(),
          audioUrl: data['audioUrl'] as String?,
          audioDurationMs: (data['audioDurationMs'] as num?)?.toInt(),
          reactions: {
            if (data['reactions'] case final Map reactions)
              for (final entry in reactions.entries)
                if (entry.value is String)
                  entry.key as String: entry.value as String,
          },
          replyTo: ReplyPreview.fromMap(data['replyTo']),
          isEdited: data.containsKey('editedAt'),
          forwardedFrom: data['forwardedFrom'] as String?,
        );
      }).toList();

      add(_MessagesUpdatedInternal(messages));
    });
  }

  /// Records that the current user has read the open chat, once per new
  /// last message.
  void _markChatRead() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final chatCode = _openChatCode;
    if (uid == null || chatCode == null || _messages.isEmpty) return;

    // Also after the user's own message, so it never counts as unread.
    final last = _messages.last;
    if (last.id == _lastMarkedMessageId) return;
    _lastMarkedMessageId = last.id;

    _firestore
        .collection('chats')
        .doc(chatCode)
        .update({'readAt.$uid': FieldValue.serverTimestamp()})
        // Read marks are best effort; the chat itself keeps working.
        .catchError((Object _) {});
  }

  @override
  Future<void> close() {
    _closeBackend();
    _messagesSubscription?.cancel();
    _chatDocSubscription?.cancel();
    _cancelChatsSubscriptions();
    return super.close();
  }
}
