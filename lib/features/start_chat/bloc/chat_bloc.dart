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
    on<_MessagesUpdatedInternal>((event, emit) {
      emit(MessagesLoaded(event.messages));
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

  Future<void> _onGetChats(
    GetChatsEvent event,
    Emitter<ChatState> emit,
  ) async {
    emit(ChatLoading());

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        emit(ChatError('User not authenticated'));
        return;
      }

      final snapshot = await _firestore
          .collection('chats')
          .where('participantIds', arrayContains: user.uid)
          .orderBy('createdAt', descending: true)
          .get();

      final chats = await Future.wait(snapshot.docs.map(_loadChatSummary));

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
    } catch (e) {
      emit(ChatError(e.toString()));
    }
  }

  Future<ChatSummary> _loadChatSummary(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final name = (data['name'] as String?)?.trim() ?? '';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();

    Map<String, dynamic>? last;
    try {
      final messages = await doc.reference
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (messages.docs.isNotEmpty) last = messages.docs.first.data();
    } catch (_) {
      // The list is still useful without the message preview.
    }

    return ChatSummary(
      code: (data['code'] as String?) ?? doc.id,
      name: name.isEmpty ? null : name,
      lastMessage: last?['text'] as String?,
      lastSenderId: last?['senderId'] as String?,
      lastSenderName: last?['senderName'] as String?,
      lastActivityAt: (last?['createdAt'] as Timestamp?)?.toDate() ?? createdAt,
    );
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

  Future<void> _onMessagesSubscribe(
    MessagesSubscribeEvent event,
    Emitter<ChatState> emit,
  ) async {
    emit(ChatLoading());

    await _messagesSubscription?.cancel();

    _messagesSubscription = _firestore
        .collection('chats')
        .doc(event.chatCode)
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

  @override
  Future<void> close() {
    _messagesSubscription?.cancel();
    return super.close();
  }
}
