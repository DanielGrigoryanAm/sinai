part of 'chat_bloc.dart';

sealed class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object> get props => [];
}

class CreateChatEvent extends ChatEvent {
  final String name;

  const CreateChatEvent(this.name);

  @override
  List<Object> get props => [name];
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

  /// Message being replied to, if any.
  final ReplyPreview? replyTo;

  const SendMessageEvent({
    required this.chatCode,
    required this.text,
    this.replyTo,
  });

  @override
  List<Object> get props => [chatCode, text];
}

/// Uploads a picture and posts it to the chat as a message.
class SendImageEvent extends ChatEvent {
  final String chatCode;
  final Uint8List bytes;
  final String contentType;
  final ReplyPreview? replyTo;

  /// Text shown under the photo.
  final String caption;

  const SendImageEvent({
    required this.chatCode,
    required this.bytes,
    this.contentType = 'image/jpeg',
    this.replyTo,
    this.caption = '',
  });

  @override
  List<Object> get props => [chatCode, bytes, contentType];
}

/// Uploads a recorded voice message and posts it to the chat.
class SendVoiceEvent extends ChatEvent {
  final String chatCode;

  /// Local path of the recording; deleted once it has been sent.
  final String filePath;
  final Duration duration;
  final ReplyPreview? replyTo;

  const SendVoiceEvent({
    required this.chatCode,
    required this.filePath,
    required this.duration,
    this.replyTo,
  });

  @override
  List<Object> get props => [chatCode, filePath, duration];
}

/// Replaces the text of the user's own message.
class EditMessageEvent extends ChatEvent {
  final String chatCode;
  final String messageId;
  final String text;

  const EditMessageEvent({
    required this.chatCode,
    required this.messageId,
    required this.text,
  });

  @override
  List<Object> get props => [chatCode, messageId, text];
}

/// Deletes the user's own message for everyone.
class DeleteMessageEvent extends ChatEvent {
  final String chatCode;
  final String messageId;

  const DeleteMessageEvent({required this.chatCode, required this.messageId});

  @override
  List<Object> get props => [chatCode, messageId];
}

/// Leaves, changes or removes the user's reaction on a message.
class ToggleReactionEvent extends ChatEvent {
  final String chatCode;
  final String messageId;
  final String reaction;

  const ToggleReactionEvent({
    required this.chatCode,
    required this.messageId,
    required this.reaction,
  });

  @override
  List<Object> get props => [chatCode, messageId, reaction];
}

class MessagesSubscribeEvent extends ChatEvent {
  final String chatCode;

  const MessagesSubscribeEvent(this.chatCode);

  @override
  List<Object> get props => [chatCode];
}

/// Asks for one more page of older messages in the open chat.
class LoadMoreMessagesEvent extends ChatEvent {
  const LoadMoreMessagesEvent();
}

class SetUserNameEvent extends ChatEvent {
  final String name;

  const SetUserNameEvent(this.name);

  @override
  List<Object> get props => [name];
}

class GetChatsEvent extends ChatEvent {
  const GetChatsEvent();
}

class DeleteChatEvent extends ChatEvent {
  final String code;

  const DeleteChatEvent(this.code);

  @override
  List<Object> get props => [code];
}

/// internal event
class _MessagesUpdatedInternal extends ChatEvent {
  final List<ChatMessage> messages;

  const _MessagesUpdatedInternal(this.messages);

  @override
  List<Object> get props => [messages];
}

/// internal event
class _ChatsSnapshotInternal extends ChatEvent {
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  const _ChatsSnapshotInternal(this.docs);

  @override
  List<Object> get props => [docs];
}

/// internal event
class _ChatsFailedInternal extends ChatEvent {
  final String message;

  const _ChatsFailedInternal(this.message);

  @override
  List<Object> get props => [message];
}

/// internal event
class _ChatsChangedInternal extends ChatEvent {
  const _ChatsChangedInternal();
}

/// internal event
class _ReadMarksUpdatedInternal extends ChatEvent {
  const _ReadMarksUpdatedInternal();
}
