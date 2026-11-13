import 'package:flutter/material.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// Asks the user to confirm an action. Resolves to `true` only when they
/// tapped the confirm button.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) {
      final colors = context.colorTheme;
      final text = context.textTheme;

      return AlertDialog(
        backgroundColor: colors.backgroundSecondary,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(title, style: text.titleLarge),
        content: Text(
          message,
          style: text.bodyLarge.copyWith(color: colors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancel',
              style: text.bodyLarge.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              confirmLabel,
              style: text.bodyLarge.copyWith(
                color: destructive ? const Color(0xFFDC2626) : colors.secondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
    },
  );
  return result ?? false;
}

/// Confirms removing a chat: deleting it for everyone when [isOwner], or
/// just leaving it otherwise.
Future<bool> confirmRemoveChat(
  BuildContext context, {
  required String chatTitle,
  required bool isOwner,
}) {
  return showConfirmDialog(
    context,
    title: isOwner ? 'Delete chat?' : 'Leave chat?',
    message: isOwner
        ? '"$chatTitle" and all its messages will be deleted for everyone. '
            'This can\'t be undone.'
        : 'You will leave "$chatTitle". You can join again with its code.',
    confirmLabel: isOwner ? 'Delete' : 'Leave',
    destructive: true,
  );
}
