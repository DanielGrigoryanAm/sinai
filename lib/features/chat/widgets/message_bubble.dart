import 'package:flutter/material.dart';
import 'package:sinai/features/chat/models/chat_message_model.dart';
import 'package:sinai/features/chat/widgets/image_viewer_screen.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// A single chat message: bubble with the time inside and, for other
/// people's messages, the sender name above the first one of a run.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.startsGroup,
    this.isSeen = false,
  });

  static const _myBubbleColor = Color(0xFF9CC4F0);
  static const _radius = Radius.circular(15);
  static const _tailRadius = Radius.circular(6);

  final ChatMessage message;
  final bool isMe;

  /// First message in a run from the same sender (or of a new day); only
  /// this one gets the sharp top corner.
  final bool startsGroup;

  /// Whether another participant has read this message. Only shown on the
  /// user's own messages.
  final bool isSeen;

  String _time(BuildContext context) {
    final time = message.createdAt;
    // The server timestamp is not known yet while the message is being sent.
    if (time == null) return 'Sending…';
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(time),
      alwaysUse24HourFormat: true,
    );
  }

  static const _shadow = [
    BoxShadow(
      color: Color(0x14000000),
      blurRadius: 6,
      offset: Offset(0, 2),
    ),
  ];

  /// Time plus, on the user's own messages, the sent/seen checks.
  Widget _buildMeta(
    BuildContext context, {
    required Color color,
    required Color seenColor,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 3,
      children: [
        Text(
          _time(context),
          style: context.textTheme.bodySmall.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
        // One check: sent. Two checks: seen.
        if (isMe && message.createdAt != null)
          Icon(
            isSeen ? Icons.done_all : Icons.check,
            size: 15,
            color: isSeen ? seenColor : color,
            semanticLabel: isSeen ? 'Seen' : 'Sent',
          ),
      ],
    );
  }

  /// Picture message: the photo fills the bubble and the time sits on a
  /// dark pill over its corner. Tapping opens it full screen.
  Widget _buildImage(BuildContext context, BorderRadius radius) {
    final colors = context.colorTheme;
    final imageUrl = message.imageUrl!;

    final width = message.imageWidth;
    final height = message.imageHeight;
    // Very tall or very wide pictures are cropped in the bubble.
    final aspectRatio = width != null && height != null && height > 0
        ? (width / height).clamp(0.6, 1.8)
        : 1.0;

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ImageViewerScreen(imageUrl: imageUrl),
        ),
      ),
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: colors.backgroundSecondary,
          borderRadius: radius,
          boxShadow: _shadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Center(
                    child: SizedBox.square(
                      dimension: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: colors.secondary,
                      ),
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: colors.textSecondary,
                    size: 32,
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0x8C000000),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _buildMeta(
                    context,
                    color: Colors.white,
                    seenColor: const Color(0xFF8EC5FF),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.76;
    final metaColor = isMe
        ? const Color(0xFF1B2030).withAlpha(140)
        : colors.textSecondary.withAlpha(190);

    final bubbleRadius = BorderRadius.only(
      topLeft: !isMe && startsGroup ? _tailRadius : _radius,
      topRight: isMe && startsGroup ? _tailRadius : _radius,
      bottomLeft: _radius,
      bottomRight: _radius,
    );

    return Padding(
      // Messages of one sender sit close together; a new sender gets air.
      padding: EdgeInsets.only(top: startsGroup ? 12 : 4),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (startsGroup && !isMe)
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 4),
                  child: Text(
                    message.senderName,
                    style: text.bodySmall.copyWith(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              if (message.isImage)
                _buildImage(context, bubbleRadius)
              else
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
                  decoration: BoxDecoration(
                    color: isMe ? _myBubbleColor : colors.backgroundSecondary,
                    borderRadius: bubbleRadius,
                    boxShadow: _shadow,
                  ),
                  // The time sits on the last line when it fits next to the
                  // text and drops to its own line otherwise.
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    spacing: 10,
                    runSpacing: 2,
                    children: [
                      Text(
                        message.text,
                        style: text.bodyLarge.copyWith(
                          height: 1.4,
                          color: const Color(0xFF1B2030),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: _buildMeta(
                          context,
                          color: metaColor,
                          seenColor: const Color(0xFF1D5FA8),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Centered pill separating messages of different days.
class MessageDatePill extends StatelessWidget {
  const MessageDatePill({super.key, required this.date});

  final DateTime date;

  String _label(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final now = DateTime.now();
    final daysAgo = DateTime(now.year, now.month, now.day)
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;

    if (daysAgo <= 0) return 'Today';
    if (daysAgo == 1) return 'Yesterday';
    if (date.year == now.year) return localizations.formatShortMonthDay(date);
    return localizations.formatShortDate(date);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: colors.textSecondary.withAlpha(24),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            _label(context),
            style: context.textTheme.bodySmall.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
