import 'package:flutter/material.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// A reaction a user can leave on a message. Stored in Firestore by [id].
class Reaction {
  const Reaction(this.id, this.label, this.icon, this.color);

  final String id;
  final String label;
  final IconData icon;
  final Color color;

  /// Shown in this order in the picker and under messages.
  static const all = [
    Reaction('love', 'Love', Icons.favorite_rounded, Color(0xFFE5484D)),
    Reaction('like', 'Like', Icons.thumb_up_alt_rounded, Color(0xFF3B82F6)),
    Reaction(
      'laugh',
      'Haha',
      Icons.sentiment_very_satisfied_rounded,
      Color(0xFFF59E0B),
    ),
    Reaction(
      'sad',
      'Sad',
      Icons.sentiment_dissatisfied_rounded,
      Color(0xFF6B7FD7),
    ),
    Reaction(
      'fire',
      'Fire',
      Icons.local_fire_department_rounded,
      Color(0xFFF97316),
    ),
    Reaction(
        'dislike', 'Dislike', Icons.thumb_down_alt_rounded, Color(0xFF8A8A8A)),
  ];

  /// The quick reaction used for a double tap.
  static const quick = 'love';
}

/// Lets the user pick a reaction. Resolves to the chosen reaction id, or
/// null when dismissed. Picking [current] again removes it.
Future<String?> showReactionPicker(BuildContext context, {String? current}) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      final colors = context.colorTheme;

      return SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            color: colors.backgroundSecondary,
            borderRadius: BorderRadius.circular(32),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (final reaction in Reaction.all)
                Material(
                  color: reaction.id == current
                      ? reaction.color.withAlpha(36)
                      : Colors.transparent,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    tooltip: reaction.label,
                    iconSize: 30,
                    icon: Icon(reaction.icon, color: reaction.color),
                    onPressed: () => Navigator.of(context).pop(reaction.id),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Reactions left on a message, one chip per reaction with its count.
class ReactionChips extends StatelessWidget {
  const ReactionChips({
    super.key,
    required this.reactions,
    required this.myId,
    required this.onTap,
  });

  /// Reaction id by user id.
  final Map<String, String> reactions;
  final String? myId;

  /// Called with the reaction id of the tapped chip.
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final mine = reactions[myId];

    final counts = <String, int>{};
    for (final id in reactions.values) {
      counts[id] = (counts[id] ?? 0) + 1;
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final reaction in Reaction.all)
          if (counts[reaction.id] case final count?)
            Material(
              color: reaction.id == mine
                  ? reaction.color.withAlpha(34)
                  : colors.backgroundSecondary,
              shape: StadiumBorder(
                side: BorderSide(
                  color: reaction.id == mine
                      ? reaction.color.withAlpha(140)
                      : colors.border,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onTap(reaction.id),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    spacing: 4,
                    children: [
                      Icon(
                        reaction.icon,
                        size: 16,
                        color: reaction.color,
                        semanticLabel: reaction.label,
                      ),
                      Text(
                        '$count',
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
