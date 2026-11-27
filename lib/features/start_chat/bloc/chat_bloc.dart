import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:equatable/equatable.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/api/api_client.dart';
import 'package:sinai/api/auth_api.dart';
import 'package:sinai/api/chats_api.dart';
import 'package:sinai/api/current_user.dart';
import 'package:sinai/api/live_socket.dart';
import 'package:sinai/features/chat/models/chat_message_model.dart';
import 'package:sinai/features/chat/widgets/reactions.dart';
import 'package:sinai/features/chats/models/chat_summary.dart';

part 'chat_event.dart';
part 'chat_state.dart';
part 'chat_bloc_backend.dart';

/// Chats, the open chat and the user's name, served by the app's backend
/// (see chat_bloc_backend.dart).
class ChatBloc extends Bloc<ChatEvent, ChatState> with _BackendChats {
  ChatBloc() : super(ChatInitial()) {
    on<SetUserNameEvent>(_onSetUserName);
    _registerBackend();
  }

  /// The name lives on the backend profile, and on the Firebase account,
  /// which is how a phone sign-in finds it again.
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
      await AuthApi.instance.rename(event.name);
      emit(UserNameSaved(event.name));
    } catch (e) {
      emit(ChatError('Failed to save user name'));
    }
  }

  @override
  Future<void> close() {
    _closeBackend();
    return super.close();
  }
}
