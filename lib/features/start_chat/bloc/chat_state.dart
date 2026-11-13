part of 'chat_bloc.dart';

sealed class ChatState extends Equatable {
  const ChatState();
  
  @override
  List<Object> get props => [];
}

final class ChatInitial extends ChatState {}

final class ChatLoading extends ChatState {}

final class ChatCreated extends ChatState {
  final String code;
  final String name;

  const ChatCreated(this.code, this.name);

  @override
  List<Object> get props => [code, name];
}

final class ChatJoined extends ChatState {
  final String code;

  const ChatJoined(this.code);

  @override
  List<Object> get props => [code];
}

final class ChatError extends ChatState {
  final String message;

  const ChatError(this.message);

  @override
  List<Object> get props => [message];
}

class MessagesLoaded extends ChatState {
  final List<ChatMessage> messages;

  const MessagesLoaded(this.messages);

  @override
  List<Object> get props => [messages];
}

class ChatsLoaded extends ChatState {
  final List<String> chatCodes;

  /// Chat names by chat code. Chats created before names existed are absent.
  final Map<String, String> chatNames;

  const ChatsLoaded(this.chatCodes, {this.chatNames = const {}});

  @override
  List<Object> get props => [chatCodes, chatNames];
}

class ChatDeleted extends ChatState {
  final String code;

  const ChatDeleted(this.code);

  @override
  List<Object> get props => [code];
}
