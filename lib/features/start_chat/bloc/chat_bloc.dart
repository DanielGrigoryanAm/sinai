import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/features/chat/models/chat_message_model.dart';

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
      final chatCode = _generateChatCode();

      await _firestore.collection('chats').doc(chatCode).set({
        'code': chatCode,
        'createdAt': FieldValue.serverTimestamp(),
      });

      emit(ChatCreated(chatCode));
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
      final code = event.code.toUpperCase();
      final doc = await _firestore.collection('chats').doc(code).get();

      if (!doc.exists) {
        emit(ChatError('Chat not found'));
        return;
      }

      emit(ChatJoined(code));
    } catch (e) {
      emit(ChatError('Failed to join chat'));
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
      emit(ChatError('Failed to send message'));
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
