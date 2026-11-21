import 'package:equatable/equatable.dart';

/// A chat as shown in the chats list.
class ChatSummary extends Equatable {
  const ChatSummary({
    required this.code,
    this.name,
    this.lastMessage,
    this.lastSenderId,
    this.lastSenderName,
    this.lastActivityAt,
    this.hasUnread = false,
    this.isOwner = false,
    this.typingName,
  });

  final String code;

  /// Null for chats created before chats had names.
  final String? name;

  /// Null when the chat has no messages yet.
  final String? lastMessage;
  final String? lastSenderId;
  final String? lastSenderName;

  /// Time of the last message, or of chat creation when there are none.
  final DateTime? lastActivityAt;

  /// The last message is from someone else and newer than the user's last
  /// visit to the chat.
  final bool hasUnread;

  /// Owners delete the chat for everyone; other participants only leave.
  final bool isOwner;

  /// Someone else typing in the chat right now, by name.
  final String? typingName;

  String get title => name ?? code;

  @override
  List<Object?> get props => [
        code,
        name,
        lastMessage,
        lastSenderId,
        lastSenderName,
        lastActivityAt,
        hasUnread,
        isOwner,
        typingName,
      ];
}
