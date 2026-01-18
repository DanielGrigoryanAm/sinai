part of 'chat_bloc.dart';

sealed class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object> get props => [];
}

class CreateChatEvent extends ChatEvent {
  const CreateChatEvent();
}

class JoinChatEvent extends ChatEvent {
  final String code;

  const JoinChatEvent(this.code);

  @override
  List<Object> get props => [code];
}

class SendMessageEvent extends ChatEvent {
  final String chatCode;
  final String text;

  const SendMessageEvent({
    required this.chatCode,
    required this.text,
  });

  @override
  List<Object> get props => [chatCode, text];
}

class MessagesSubscribeEvent extends ChatEvent {
  final String chatCode;

  const MessagesSubscribeEvent(this.chatCode);

  @override
  List<Object> get props => [chatCode];
}

class SetUserNameEvent extends ChatEvent {
  final String name;

  const SetUserNameEvent(this.name);

  @override
  List<Object> get props => [name];
}

/// internal event
class _MessagesUpdatedInternal extends ChatEvent {
  final List<ChatMessage> messages;

  const _MessagesUpdatedInternal(this.messages);

  @override
  List<Object> get props => [messages];
}