import 'package:flutter/material.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// Emoji reactions. A reaction is stored in Firestore as the emoji itself.
abstract final class Reactions {
  /// Shown in the message menu, in this order.
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

/// Text style for emoji. No font family, so the platform emoji font draws
/// them rather than the app's text font.
const _emojiStyle = TextStyle(fontFamily: null, height: 1.15);

/// Opens the full emoji list. Resolves to the picked emoji, or null.
Future<String?> showEmojiPicker(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colorTheme.backgroundSecondary,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      final colors = context.colorTheme;

      return SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.55,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: SafeArea(
                top: false,
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 48,
                  ),
                  itemCount: Reactions.all.length,
                  itemBuilder: (context, index) {
                    final emoji = Reactions.all[index];
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.of(context).pop(emoji),
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
    },
  );
}

/// One emoji in the quick row of the message menu.
class QuickReactionButton extends StatelessWidget {
  const QuickReactionButton({
    super.key,
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

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
        child: SizedBox.square(
          dimension: 36,
          child: Center(
            child: Text(emoji, style: _emojiStyle.copyWith(fontSize: 22)),
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
