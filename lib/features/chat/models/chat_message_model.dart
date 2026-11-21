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

  /// Reaction id by the id of the user who left it; one per user.
  final Map<String, String> reactions;

  /// The message this one replies to; null when it is not a reply.
  final ReplyPreview? replyTo;

  /// The sender changed the text after sending.
  final bool isEdited;

  /// Name of the original author when this message was forwarded.
  final String? forwardedFrom;

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
    this.reactions = const {},
    this.replyTo,
    this.isEdited = false,
    this.forwardedFrom,
  });

  bool get isVoice => audioUrl != null && audioUrl!.isNotEmpty;

  bool get isImage => imageUrl != null && imageUrl!.isNotEmpty;

  /// Short text describing the message, for reply quotes.
  String get previewText {
    if (isImage) return text.trim().isNotEmpty ? '📷 $text' : 'Photo';
    if (isVoice) return 'Voice message';
    return text;
  }
}

/// What a reply shows of the message it answers. Copied into the reply when
/// it is sent, so the quote stays readable even if the original is gone.
class ReplyPreview {
  const ReplyPreview({
    required this.messageId,
    required this.senderName,
    required this.text,
  });

  factory ReplyPreview.of(ChatMessage message) => ReplyPreview(
        messageId: message.id,
        senderName: message.senderName,
        text: message.previewText,
      );

  final String messageId;
  final String senderName;
  final String text;

  Map<String, dynamic> toMap() => {
        'messageId': messageId,
        'senderName': senderName,
        // Long texts are cut; the quote shows a single line anyway.
        'text': text.length > 200 ? text.substring(0, 200) : text,
      };

  static ReplyPreview? fromMap(Object? data) {
    if (data is! Map) return null;
    final messageId = data['messageId'];
    if (messageId is! String) return null;
    return ReplyPreview(
      messageId: messageId,
      senderName: (data['senderName'] as String?) ?? '',
      text: (data['text'] as String?) ?? '',
    );
  }
}
