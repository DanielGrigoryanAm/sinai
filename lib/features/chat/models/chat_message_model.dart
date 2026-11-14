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

  /// Download URL of the voice recording; null for other messages.
  final String? audioUrl;
  final int? audioDurationMs;

  ChatMessage({
    required this.id,
    required this.text,
    required this.senderId,
    required this.senderName,
    required this.createdAt,
    this.imageUrl,
    this.imageWidth,
    this.imageHeight,
    this.audioUrl,
    this.audioDurationMs,
  });

  bool get isVoice => audioUrl != null && audioUrl!.isNotEmpty;

  bool get isImage => imageUrl != null && imageUrl!.isNotEmpty;
}
