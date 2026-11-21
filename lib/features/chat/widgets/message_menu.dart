import 'dart:async';
import 'package:sinai/common/app_icons.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sinai/features/chat/quick_reactions_store.dart';
import 'package:sinai/features/chat/widgets/reactions.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// What the user picked in the message menu.
sealed class MessageMenuResult {
  const MessageMenuResult();
}

class MessageMenuReact extends MessageMenuResult {
  const MessageMenuReact(this.reaction);

  final String reaction;
}

/// The "+" in the reactions row: open the full emoji list.
class MessageMenuMoreReactions extends MessageMenuResult {
  const MessageMenuMoreReactions();
}

/// Long press on a quick reaction: replace the emoji in that slot.
class MessageMenuEditQuick extends MessageMenuResult {
  const MessageMenuEditQuick(this.slot);

  final int slot;
}

enum MessageMenuAction { reply, copy, edit, delete }

class MessageMenuActionResult extends MessageMenuResult {
  const MessageMenuActionResult(this.action);

  final MessageMenuAction action;
}

const _deleteColor = Color(0xFFDC2626);
const _menuWidth = 284.0;
const _reactionsRowHeight = 52.0;
const _actionHeight = 46.0;

OverlayEntry? _openMenu;
Completer<MessageMenuResult?>? _openMenuResult;

/// Closes the open message menu, if any, completing it with [result].
void closeMessageMenu([MessageMenuResult? result]) {
  final completer = _openMenuResult;
  _openMenu?.remove();
  _openMenu = null;
  _openMenuResult = null;
  if (completer != null && !completer.isCompleted) completer.complete(result);
}

/// Small popup next to a message with a row of reactions and the actions
/// that apply to it. [anchor] is the context of the message bubble.
///
/// Drawn in the overlay rather than pushed as a route: pushing a route
/// cancels the finger that is still on the message, which would end the
/// long press and with it the drag-to-react gesture.
Future<MessageMenuResult?> showMessageMenu(
  BuildContext anchor, {
  required String? currentReaction,
  required bool canReply,
  required bool canCopy,
  required bool canEdit,
  required bool canDelete,
}) {
  closeMessageMenu();

  final overlay = Overlay.of(anchor, rootOverlay: true);
  final overlayBox = overlay.context.findRenderObject()! as RenderBox;
  final box = anchor.findRenderObject()! as RenderBox;
  final bubble =
      box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
  final screen = overlayBox.size;
  final padding = MediaQuery.paddingOf(anchor);

  final actions = [
    if (canReply) (MessageMenuAction.reply, 'Reply', AppIcons.reply, null),
    if (canCopy) (MessageMenuAction.copy, 'Copy', AppIcons.copy, null),
    if (canEdit) (MessageMenuAction.edit, 'Edit', AppIcons.edit, null),
    if (canDelete)
      (MessageMenuAction.delete, 'Delete', AppIcons.trash, _deleteColor),
  ];
  final menuHeight = _reactionsRowHeight +
      (actions.isEmpty ? 0 : 1 + actions.length * _actionHeight) +
      8;

  // Under the bubble when it fits, otherwise above it, otherwise as low as
  // the screen allows.
  const gap = 6.0;
  final bottomLimit = screen.height - padding.bottom - 8;
  var top = bubble.bottom + gap;
  if (top + menuHeight > bottomLimit) {
    top = bubble.top - gap - menuHeight;
    if (top < padding.top + 8) top = bottomLimit - menuHeight;
  }

  // Lined up with the side of the screen the bubble is on.
  final onRight = bubble.center.dx > screen.width / 2;
  final left = (onRight ? bubble.right - _menuWidth : bubble.left)
      .clamp(12.0, screen.width - _menuWidth - 12);

  final completer = Completer<MessageMenuResult?>();
  final entry = OverlayEntry(
    builder: (context) => Stack(
      children: [
        // Tapping anywhere else closes the menu.
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: closeMessageMenu,
            child: const ColoredBox(color: Color(0x14000000)),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: _menuWidth,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(
                scale: 0.92 + 0.08 * t,
                alignment: onRight ? Alignment.topRight : Alignment.topLeft,
                child: child,
              ),
            ),
            child: _MenuCard(
              currentReaction: currentReaction,
              actions: actions,
            ),
          ),
        ),
      ],
    ),
  );

  _openMenu = entry;
  _openMenuResult = completer;
  overlay.insert(entry);
  HapticFeedback.mediumImpact();
  return completer.future;
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.currentReaction, required this.actions});

  final String? currentReaction;
  final List<(MessageMenuAction, String, IconData, Color?)> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final current =
        currentReaction == null ? null : Reactions.emojiOf(currentReaction!);

    return Material(
      color: colors.backgroundSecondary,
      elevation: 8,
      shadowColor: const Color(0x55000000),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: _reactionsRowHeight,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final (slot, emoji)
                        in QuickReactionsStore.instance.reactions.value.indexed)
                      QuickReactionButton(
                        emoji: emoji,
                        selected: emoji == current,
                        onTap: () => closeMessageMenu(MessageMenuReact(emoji)),
                        // Long press replaces this emoji in the user's set.
                        onLongPress: () =>
                            closeMessageMenu(MessageMenuEditQuick(slot)),
                      ),
                    Material(
                      color: colors.backgroundPrimary,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => closeMessageMenu(
                          const MessageMenuMoreReactions(),
                        ),
                        child: SizedBox.square(
                          dimension: 32,
                          child: Icon(
                            AppIcons.add,
                            size: 20,
                            color: colors.textSecondary,
                            semanticLabel: 'More reactions',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (actions.isNotEmpty) Divider(height: 1, color: colors.border),
            for (final (action, label, icon, color) in actions)
              InkWell(
                onTap: () => closeMessageMenu(MessageMenuActionResult(action)),
                child: SizedBox(
                  height: _actionHeight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: context.textTheme.bodyLarge.copyWith(
                              color: color ?? colors.textPrimary,
                            ),
                          ),
                        ),
                        Icon(
                          icon,
                          size: 20,
                          color: color ?? colors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
