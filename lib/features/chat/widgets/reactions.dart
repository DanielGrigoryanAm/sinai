import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sinai/common/emoji_text.dart';
import 'package:flutter/services.dart';
import 'package:sinai/features/chat/quick_reactions_store.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// Emoji reactions. A reaction is stored in Firestore as the emoji itself.
abstract final class Reactions {
  /// Default quick reactions; each user can change theirs, see
  /// QuickReactionsStore.
  static const quick = ['❤️', '👍', '😂', '😮', '😢', '🔥'];

  /// The reaction a double tap leaves.
  static const like = '❤️';

  /// Reactions saved before they were emoji, by their old id.
  static const _legacy = {
    'love': '❤️',
    'like': '👍',
    'laugh': '😂',
    'sad': '😢',
    'fire': '🔥',
    'dislike': '👎',
  };

  /// The emoji to show for a stored reaction.
  static String emojiOf(String reaction) => _legacy[reaction] ?? reaction;

  static const _all =
      '😀😃😄😁😆😅🤣😂🙂🙃🫠😉😊😇🥰😍🤩😘😗☺️😚😙🥲😋😛😜🤪😝🤑🤗🤭🫢🫣🤫🤔🫡🤐'
      '🤨😐😑😶🫥😶‍🌫️😏😒🙄😬😮‍💨🤥🫨🙂‍↔️🙂‍↕️😌😔😪🤤😴🫩😷🤒🤕🤢🤮🤧🥵🥶🥴😵😵‍💫🤯'
      '🤠🥳🥸😎🤓🧐😕🫤😟🙁☹️😮😯😲😳🫪🥺🥹😦😧😨😰😥😢😭😱😖😣😞😓😩😫🥱😤😡😠🤬😈'
      '👿💀☠️💩🤡👹👺👻👽👾🤖😺😸😹😻😼😽🙀😿😾🙈🙉🙊💋💯💢🫯💥💫💦💨🕳️💤👋🤚🖐️✋🖖'
      '🫱🫲🫳🫴🫷🫸👌🤌🤏✌️🤞🫰🤟🤘🤙👈👉👆🖕👇☝️🫵👍👎✊👊🤛🤜👏🙌🫶👐🤲🤝🙏✍️💅🤳💪'
      '🦾🦿🦵🦶👂🦻👃🧠🫀🫁🦷🦴👀👁️👅👄🫦💌💘💝💖💗💓💞💕💟❣️💔❤️‍🔥❤️‍🩹❤️🩷🧡💛💚'
      '💙🩵💜🤎🖤🩶🤍';

  /// Every emoji offered by the "+" picker.
  static final List<String> all = _all.characters.toList(growable: false);
}

/// Text style for emoji: the platform's colour emoji font, not the app's
/// text font, which has some of them as black symbols.
final _emojiStyle = emojiStyle.copyWith(height: 1.15);

/// Opens the full emoji list. Resolves to the emoji picked to react with,
/// or null.
///
/// The top row shows the user's quick reactions with an Edit button: in
/// edit mode, tapping a slot and then an emoji replaces that slot. With
/// [editSlot] the sheet opens straight in edit mode on that slot and closes
/// once it is replaced.
Future<String?> showEmojiPicker(BuildContext context, {int? editSlot}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colorTheme.backgroundSecondary,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => _EmojiPickerSheet(editSlot: editSlot),
  );
}

class _EmojiPickerSheet extends StatefulWidget {
  const _EmojiPickerSheet({this.editSlot});

  final int? editSlot;

  @override
  State<_EmojiPickerSheet> createState() => _EmojiPickerSheetState();
}

class _EmojiPickerSheetState extends State<_EmojiPickerSheet> {
  late bool _editing = widget.editSlot != null;
  late int _slot = widget.editSlot ?? 0;

  QuickReactionsStore get _store => QuickReactionsStore.instance;

  void _onEmojiTap(String emoji) {
    if (!_editing) {
      Navigator.of(context).pop(emoji);
      return;
    }
    HapticFeedback.selectionClick();
    _store.setSlot(_slot, emoji);
    // Opened for one slot from the message menu: that was the whole job.
    if (widget.editSlot != null) {
      Navigator.of(context).pop();
      return;
    }
    // Otherwise move on, so the whole row can be filled in a few taps.
    setState(() => _slot = (_slot + 1) % Reactions.quick.length);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _editing ? 'Pick a slot, then an emoji' : 'Quick reactions',
                    style: text.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                if (_editing)
                  TextButton(
                    onPressed: _store.reset,
                    child: Text(
                      'Reset',
                      style: text.bodySmall.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: () => setState(() => _editing = !_editing),
                  child: Text(
                    _editing ? 'Done' : 'Edit',
                    style: text.bodyLarge.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          ValueListenableBuilder<List<String>>(
            valueListenable: _store.reactions,
            builder: (context, quick, _) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (var i = 0; i < quick.length; i++)
                    QuickReactionButton(
                      emoji: quick[i],
                      selected: _editing && i == _slot,
                      size: 44,
                      onTap: _editing
                          ? () => setState(() => _slot = i)
                          : () => Navigator.of(context).pop(quick[i]),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Divider(height: 1, color: colors.border),
          Expanded(
            child: SafeArea(
              top: false,
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 48,
                ),
                itemCount: Reactions.all.length,
                itemBuilder: (context, index) {
                  final emoji = Reactions.all[index];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _onEmojiTap(emoji),
                    child: Center(
                      child: Text(
                        emoji,
                        style: _emojiStyle.copyWith(fontSize: 28),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One emoji in the quick row of the message menu.
class QuickReactionButton extends StatelessWidget {
  const QuickReactionButton({
    super.key,
    required this.emoji,
    required this.selected,
    required this.onTap,
    this.onLongPress,
    this.size = 36,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? context.colorTheme.secondary.withAlpha(50)
          : Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox.square(
          dimension: size,
          child: Center(
            child: Text(
              emoji,
              style: _emojiStyle.copyWith(fontSize: size * 0.6),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reactions left on a message, one chip per emoji with its count.
class ReactionChips extends StatelessWidget {
  const ReactionChips({
    super.key,
    required this.reactions,
    required this.myId,
    required this.onTap,
  });

  /// Reaction by user id.
  final Map<String, String> reactions;
  final String? myId;

  /// Called with the emoji of the tapped chip.
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final mine =
        reactions[myId] == null ? null : Reactions.emojiOf(reactions[myId]!);

    // Counted in the order they were first left; most popular first.
    final counts = <String, int>{};
    for (final reaction in reactions.values) {
      final emoji = Reactions.emojiOf(reaction);
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    }
    final emojis = counts.keys.toList()
      ..sort((a, b) => counts[b]!.compareTo(counts[a]!));

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final emoji in emojis)
          Material(
            color: emoji == mine
                ? colors.secondary.withAlpha(45)
                : colors.backgroundSecondary,
            shape: StadiumBorder(
              side: BorderSide(
                color: emoji == mine ? colors.secondary : colors.border,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onTap(emoji),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: 4,
                  children: [
                    Text(emoji, style: _emojiStyle.copyWith(fontSize: 15)),
                    Text(
                      '${counts[emoji]}',
                      style: context.textTheme.bodySmall.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Small pill showing three of the quick reactions at a time, scrolled by
/// dragging after a long press. The emoji in the middle is the one picked
/// on release.
class ReactionScrubber extends StatelessWidget {
  const ReactionScrubber({
    super.key,
    required this.emojis,
    required this.position,
  });

  final List<String> emojis;

  /// Fractional index into [emojis] of the emoji in the middle.
  final ValueListenable<double> position;

  static const slot = 52.0;
  static const width = slot * 3 + 16;
  static const height = 60.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;

    return Material(
      color: colors.backgroundSecondary,
      elevation: 10,
      shadowColor: const Color(0x55000000),
      shape: const StadiumBorder(),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Marks the middle slot, the one that will be picked.
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: colors.secondary.withAlpha(45),
                shape: BoxShape.circle,
              ),
            ),
            ClipRect(
              child: SizedBox(
                width: slot * 3,
                height: height,
                child: ValueListenableBuilder<double>(
                  valueListenable: position,
                  builder: (context, value, _) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (var i = 0; i < emojis.length; i++)
                          _emojiAt(i, value),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emojiAt(int index, double value) {
    // Distance from the middle slot, in slots.
    final distance = (index - value).abs();
    if (distance > 2) return const SizedBox.shrink();

    final closeness = (1 - distance).clamp(0.0, 1.0);
    return Positioned(
      left: (index - value + 1) * slot,
      top: 0,
      bottom: 0,
      width: slot,
      child: Center(
        child: Opacity(
          opacity: (1 - distance * 0.35).clamp(0.3, 1.0),
          child: Transform.scale(
            scale: 0.85 + 0.45 * closeness,
            child: Text(
              emojis[index],
              style: _emojiStyle.copyWith(fontSize: 26),
            ),
          ),
        ),
      ),
    );
  }
}
