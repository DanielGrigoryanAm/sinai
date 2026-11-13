import 'package:flutter/material.dart';
import 'package:sinai/features/chat/models/chat_message_model.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// A single chat message: bubble with the time underneath and, for other
/// people's messages, an optional sender name above.
class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.showName,
  });

  static const _myBubbleColor = Color(0xFF9CC4F0);
  static const _radius = Radius.circular(20);
  static const _tailRadius = Radius.circular(6);

  final ChatMessage message;
  final bool isMe;
  final bool showName;

  String _time(BuildContext context) {
    final time = message.createdAt;
    // The server timestamp is not known yet while the message is being sent.
    if (time == null) return 'Sending…';
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(time),
      alwaysUse24HourFormat: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    final maxWidth = MediaQuery.sizeOf(context).width * 0.76;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (showName && !isMe)
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                decoration: BoxDecoration(
                  color: isMe ? _myBubbleColor : colors.backgroundSecondary,
                  borderRadius: BorderRadius.only(
                    topLeft: _radius,
                    topRight: _radius,
                    bottomLeft: isMe ? _radius : _tailRadius,
                    bottomRight: isMe ? _tailRadius : _radius,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  message.text,
                  style: text.bodyLarge.copyWith(
                    height: 1.4,
                    color: const Color(0xFF1B2030),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                child: Text(
                  _time(context),
                  style: text.bodySmall.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: colors.textSecondary.withAlpha(150),
                  ),
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
      padding: const EdgeInsets.only(top: 6, bottom: 20),
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
