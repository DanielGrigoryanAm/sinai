class ChatMessage {
  final String id;
  final String text;
  final String senderId;
  final String senderName;
  final DateTime? createdAt;

  /// Download URL of the attached picture; null for text messages.
  final String? imageUrl;

  /// Pixel size of the picture, so its bubble can be laid out before the
  /// picture has loaded.
  final int? imageWidth;
  final int? imageHeight;

  ChatMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.createdAt,
    this.imageUrl,
    this.imageWidth,
    this.imageHeight,
  });

  bool get isImage => imageUrl != null && imageUrl!.isNotEmpty;
}
