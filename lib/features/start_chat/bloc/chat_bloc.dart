import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/common/onboarding_prefs.dart';
import 'package:sinai/features/chat/models/chat_message_model.dart';
import 'package:sinai/features/chats/models/chat_summary.dart';

part 'chat_event.dart';
part 'chat_state.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  ChatBloc() : super(ChatInitial()) {
    on<CreateChatEvent>(_onCreateChat);
    on<JoinChatEvent>(_onJoinChat);
    on<SendMessageEvent>(_onSendMessage);
    on<MessagesSubscribeEvent>(_onMessagesSubscribe);
    on<SetUserNameEvent>(_onSetUserName);
    on<GetChatsEvent>(_onGetChats);
    on<DeleteChatEvent>(_onDeleteChat);
    on<_ChatsSnapshotInternal>(_onChatsSnapshot);
    on<_ChatsChangedInternal>((event, emit) => _emitChats(emit));
    on<_ChatsFailedInternal>((event, emit) => emit(ChatError(event.message)));
    on<_MessagesUpdatedInternal>((event, emit) {
      _messages = event.messages;
      _markChatRead();
      emit(MessagesLoaded(_messages, seenAt: _othersReadAt));
    });
    on<_ReadMarksUpdatedInternal>((event, emit) {
      // Messages not loaded yet; the mark is emitted together with them.
      if (state is! MessagesLoaded) return;
      emit(MessagesLoaded(_messages, seenAt: _othersReadAt));
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
      await OnboardingPrefs.setNameConfirmed();
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

      final chatCode = _generateChatCode();

      final name = event.name.trim();

      await _firestore.collection('chats').doc(chatCode).set({
        'code': chatCode,
        'name': name,
        'ownerId': user.uid,
        'participantIds': [user.uid],
        'createdAt': FieldValue.serverTimestamp(),
      });

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
    }

    for (final doc in event.docs) {
      final id = doc.id;
      if (_lastMessageSubscriptions.containsKey(id)) continue;

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

    return ChatSummary(
      code: (data['code'] as String?) ?? doc.id,
      name: name.isEmpty ? null : name,
      lastMessage: last?['text'] as String?,
      lastSenderId: last?['senderId'] as String?,
      lastSenderName: last?['senderName'] as String?,
      lastActivityAt: lastAt ?? createdAt,
      hasUnread: hasUnread,
    );
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
        final messagesRef =
            _firestore.collection('chats').doc(code).collection('messages');

        while (true) {
          final batchSnapshot = await messagesRef.limit(200).get();
          if (batchSnapshot.docs.isEmpty) break;

          final batch = _firestore.batch();
          for (final doc in batchSnapshot.docs) {
            batch.delete(doc.reference);
          }
          await batch.commit();
        }

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
      });
    } catch (e) {
      emit(ChatError(e.toString()));
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

    _messagesSubscription = chatRef
        .collection('messages')
        .orderBy('createdAt')
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
        );
      }).toList();

      add(_MessagesUpdatedInternal(messages));
    });
  }

  /// Records that the current user has read the open chat, once per new
  /// incoming message.
  void _markChatRead() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final chatCode = _openChatCode;
    if (uid == null || chatCode == null || _messages.isEmpty) return;

    final last = _messages.last;
    if (last.senderId == uid || last.id == _lastMarkedMessageId) return;
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
    _messagesSubscription?.cancel();
    _chatDocSubscription?.cancel();
    _cancelChatsSubscriptions();
    return super.close();
  }
}
