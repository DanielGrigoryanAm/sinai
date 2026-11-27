import 'package:flutter/material.dart';
import 'package:sinai/common/app_icons.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// One choice of [NewChatMenu]: a small round button with a label.
class NewChatAction {
  const NewChatAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

/// The + button of the chats list. A tap lifts small buttons up out of it,
/// each with its label; the + turns into ×. [animation] runs 0 (shut) to
/// 1 (open) and is driven by the screen, which also dims the list behind.
class NewChatMenu extends StatelessWidget {
  const NewChatMenu({
    super.key,
    required this.animation,
    required this.actions,
    required this.onToggle,
  });

  final Animation<double> animation;

  /// Nearest to the + button first.
  final List<NewChatAction> actions;
  final VoidCallback onToggle;

  static const _size = 56.0;
  static const _miniSize = 44.0;
  static const _gap = 14.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final (i, action) in actions.indexed.toList().reversed)
          _Item(
            action: action,
            // The one nearest the + comes out first, the next follows.
            animation: CurvedAnimation(
              parent: animation,
              curve:
                  Interval(i * 0.15, 0.7 + i * 0.15, curve: Curves.easeOutBack),
              reverseCurve:
                  Interval(i * 0.1, 0.6 + i * 0.1, curve: Curves.easeIn),
            ),
            // Rises from the + button's centre to its own place.
            rise: (_size - _miniSize) / 2 + (i + 1) * (_miniSize + _gap),
          ),
        SizedBox.square(
          dimension: _size,
          child: FloatingActionButton(
            heroTag: null,
            onPressed: onToggle,
            backgroundColor: colors.secondary,
            foregroundColor: Colors.white,
            elevation: 4,
            shape: const CircleBorder(),
            child: RotationTransition(
              // A quarter of a half turn: + becomes ×.
              turns: Tween(begin: 0.0, end: 0.125).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOut),
              ),
              child: const PlusIcon(size: 26, strokeWidth: 2.2),
            ),
          ),
        ),
      ],
    );
  }
}

class _Item extends StatelessWidget {
  const _Item({
    required this.action,
    required this.animation,
    required this.rise,
  });

  final NewChatAction action;
  final Animation<double> animation;
  final double rise;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        return IgnorePointer(
          ignoring: t < 0.5,
          child: Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(
              // Starts inside the + button and climbs to its place.
              offset: Offset(0, (1 - t) * rise),
              child: Transform.scale(
                scale: 0.4 + 0.6 * t.clamp(0.0, 1.0),
                alignment: Alignment.centerRight,
                child: child,
              ),
            ),
          ),
        );
      },
      child: Padding(
        padding: EdgeInsets.only(
          bottom: NewChatMenu._gap,
          right: (NewChatMenu._size - NewChatMenu._miniSize) / 2,
        ),
        child: GestureDetector(
          onTap: action.onTap,
          behavior: HitTestBehavior.opaque,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x1F000000),
                      blurRadius: 10,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Text(
                  action.label,
                  style: text.bodyLarge.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: NewChatMenu._miniSize,
                height: NewChatMenu._miniSize,
                decoration: BoxDecoration(
                  color: colors.backgroundSecondary,
                  shape: BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x29000000),
                      blurRadius: 8,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(action.icon, size: 20, color: colors.secondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
