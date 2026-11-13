class ChatMessage {
  final String id;
  final String text;
  final String senderId;
  final String senderName;
  final DateTime? createdAt;

  ChatMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.createdAt,
  });
}
