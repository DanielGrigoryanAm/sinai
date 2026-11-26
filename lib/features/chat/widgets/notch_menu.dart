import 'package:flutter/material.dart';
import 'package:sinai/common/app_icons.dart';
import 'package:sinai/features/chat/widgets/chat_games.dart';
import 'package:sinai/theme/color_theme.dart';

/// A row of small icons the notch shows when pulled down: games and
/// YouTube. Games opens its own row (chess, tic-tac-toe, checkers) sliding
/// in from the side while the rest slide away; a game starts when picked.
class NotchMenu extends StatefulWidget {
  const NotchMenu({super.key, required this.onGame, required this.onYoutube});

  /// A game was picked.
  final ValueChanged<ChatGameType> onGame;

  /// YouTube was picked: watch a video together.
  final VoidCallback onYoutube;

  @override
  State<NotchMenu> createState() => _NotchMenuState();
}

class _NotchMenuState extends State<NotchMenu> {
  bool _games = false;

  static const _duration = Duration(milliseconds: 260);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 6,
        children: [
          // Stays put; tapping it again goes back.
          _MenuIcon(
            icon: AppIcons.games,
            label: 'Games',
            color: const Color(0xFF7C4DFF),
            selected: _games,
            onTap: () => setState(() => _games = !_games),
          ),
          // The rest of the row swaps: the other menu items slide out and
          // the games slide in from the side.
          AnimatedSize(
            duration: _duration,
            curve: Curves.easeOutCubic,
            child: AnimatedSwitcher(
              duration: _duration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final entering = child.key == ValueKey(_games);
                return ClipRect(
                  child: SlideTransition(
                    position: Tween(
                      begin: Offset(entering ? 0.6 : -0.6, 0),
                      end: Offset.zero,
                    ).animate(animation),
                    child: FadeTransition(opacity: animation, child: child),
                  ),
                );
              },
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.centerLeft,
                children: [...previous, if (current != null) current],
              ),
              child: _games
                  ? Row(
                      key: const ValueKey(true),
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        const _Divider(),
                        _MenuIcon(
                          icon: AppIcons.chess,
                          label: 'Chess',
                          color: const Color(0xFF8D5524),
                          onTap: () => widget.onGame(ChatGameType.chess),
                        ),
                        _MenuIcon(
                          icon: AppIcons.ticTacToe,
                          label: 'Tic-tac-toe',
                          color: const Color(0xFF1E88E5),
                          onTap: () => widget.onGame(ChatGameType.ticTacToe),
                        ),
                        _MenuIcon(
                          icon: AppIcons.checkers,
                          label: 'Checkers',
                          color: const Color(0xFFE53935),
                          onTap: () => widget.onGame(ChatGameType.checkers),
                        ),
                      ],
                    )
                  : Row(
                      key: const ValueKey(false),
                      mainAxisSize: MainAxisSize.min,
                      spacing: 6,
                      children: [
                        _MenuIcon(
                          icon: AppIcons.youtube,
                          label: 'YouTube',
                          color: const Color(0xFFFF0000),
                          onTap: widget.onYoutube,
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuIcon extends StatelessWidget {
  const _MenuIcon({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;

  /// The icon's own color; its circle is a light tint of it.
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withAlpha(selected ? 70 : 32),
            border: selected ? Border.all(color: color, width: 1.5) : null,
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        color: context.colorTheme.border,
      );
}
