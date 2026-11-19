import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

enum MessageMenuAction { reply, copy, edit, delete }

class MessageMenuActionResult extends MessageMenuResult {
  const MessageMenuActionResult(this.action);

  final MessageMenuAction action;
}

const _deleteColor = Color(0xFFDC2626);

/// Small popup next to a message with a row of reactions and the actions
/// that apply to it. [anchor] is the context of the message bubble.
Future<MessageMenuResult?> showMessageMenu(
  BuildContext anchor, {
  required String? currentReaction,
  required bool canReply,
  required bool canCopy,
  required bool canEdit,
  required bool canDelete,
}) {
  final box = anchor.findRenderObject()! as RenderBox;
  final overlay =
      Navigator.of(anchor).overlay!.context.findRenderObject()! as RenderBox;
  final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
  final bubble = topLeft & box.size;

  HapticFeedback.mediumImpact();

  return showMenu<MessageMenuResult>(
    context: anchor,
    // Opens just under the bubble; Flutter moves it above when there is no
    // room below.
    position: RelativeRect.fromRect(
      Rect.fromLTWH(bubble.left, bubble.bottom + 4, bubble.width, 0),
      Offset.zero & overlay.size,
    ),
    color: anchor.colorTheme.backgroundSecondary,
    surfaceTintColor: Colors.transparent,
    elevation: 8,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    constraints: const BoxConstraints(minWidth: 264, maxWidth: 264),
    items: [
      _ReactionsEntry(current: currentReaction),
      const PopupMenuDivider(height: 1),
      if (canReply)
        _actionItem(anchor, MessageMenuAction.reply, 'Reply', Icons.reply),
      if (canCopy)
        _actionItem(
          anchor,
          MessageMenuAction.copy,
          'Copy',
          Icons.copy_rounded,
        ),
      if (canEdit)
        _actionItem(
          anchor,
          MessageMenuAction.edit,
          'Edit',
          Icons.edit_outlined,
        ),
      if (canDelete)
        _actionItem(
          anchor,
          MessageMenuAction.delete,
          'Delete',
          Icons.delete_outline,
          color: _deleteColor,
        ),
    ],
  );
}

PopupMenuItem<MessageMenuResult> _actionItem(
  BuildContext context,
  MessageMenuAction action,
  String label,
  IconData icon, {
  Color? color,
}) {
  final textColor = color ?? context.colorTheme.textPrimary;

  return PopupMenuItem<MessageMenuResult>(
    value: MessageMenuActionResult(action),
    height: 46,
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: context.textTheme.bodyLarge.copyWith(color: textColor),
          ),
        ),
        Icon(icon, size: 20, color: color ?? context.colorTheme.textSecondary),
      ],
    ),
  );
}

/// Row of reactions at the top of the menu.
class _ReactionsEntry extends PopupMenuEntry<MessageMenuResult> {
  const _ReactionsEntry({required this.current});

  final String? current;

  @override
  double get height => 52;

  @override
  bool represents(MessageMenuResult? value) => false;

  @override
  State<_ReactionsEntry> createState() => _ReactionsEntryState();
}

class _ReactionsEntryState extends State<_ReactionsEntry> {
  @override
  Widget build(BuildContext context) {
    final current =
        widget.current == null ? null : Reactions.emojiOf(widget.current!);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final emoji in Reactions.quick)
            QuickReactionButton(
              emoji: emoji,
              selected: emoji == current,
              onTap: () => Navigator.of(context).pop(MessageMenuReact(emoji)),
            ),
          Material(
            color: context.colorTheme.backgroundPrimary,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(
                const MessageMenuMoreReactions(),
              ),
              child: SizedBox.square(
                dimension: 32,
                child: Icon(
                  Icons.add,
                  size: 20,
                  color: context.colorTheme.textSecondary,
                  semanticLabel: 'More reactions',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
