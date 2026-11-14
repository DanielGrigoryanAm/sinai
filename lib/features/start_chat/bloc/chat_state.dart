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

  /// Latest time another participant read the chat; the user's own messages
  /// sent up to this moment have been seen. Null when nobody else has.
  final DateTime? seenAt;

  /// Whether older messages exist beyond the loaded ones.
  final bool hasMore;
  final bool isLoadingMore;

  /// A picture picked on this device is still uploading.
  final bool isSendingImage;

  const MessagesLoaded(
    this.messages, {
    this.seenAt,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.isSendingImage = false,
  });

  @override
  List<Object> get props => [
        messages,
        seenAt ?? 0,
        hasMore,
        isLoadingMore,
        isSendingImage,
      ];
}

class UserNameSaved extends ChatState {
  final String name;

  const UserNameSaved(this.name);

  @override
  List<Object> get props => [name];
}

class ChatsLoaded extends ChatState {
  final List<ChatSummary> chats;

  const ChatsLoaded(this.chats);

  @override
  List<Object> get props => [chats];
}

class ChatDeleted extends ChatState {
  final String code;

  const ChatDeleted(this.code);

  @override
  List<Object> get props => [code];
}
