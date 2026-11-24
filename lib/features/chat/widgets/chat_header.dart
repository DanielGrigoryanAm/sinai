import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sinai/common/app_icons.dart';
import 'package:sinai/features/chat/chat_status.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// Chat header: the back and menu buttons are tabs growing out of the
/// screen edges, with the chat name and status between them. Messages
/// scroll underneath and fade out behind it.
class ChatHeader extends StatefulWidget implements PreferredSizeWidget {
  const ChatHeader({
    super.key,
    required this.title,
    required this.status,
    required this.onBack,
    required this.onInfo,
    required this.onSearch,
  });

  static const height = 88.0;

  final String title;
  final ValueListenable<ChatStatus?> status;
  final VoidCallback onBack;
  final VoidCallback onInfo;
  final VoidCallback onSearch;

  @override
  Size get preferredSize => const Size.fromHeight(height);

  @override
  State<ChatHeader> createState() => _ChatHeaderState();
}

class _ChatHeaderState extends State<ChatHeader>
    with SingleTickerProviderStateMixin {
  // The tabs slide in from the sides and the notch drops from the top,
  // all at once, when the chat opens.
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  )..forward();

  Animation<Offset> _slide(Offset from) => Tween(
        begin: from,
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _entrance,
        curve: Curves.easeOutBack,
      ));

  late final _left = _slide(const Offset(-1.2, 0));
  late final _notch = _slide(const Offset(0, -1.2));
  late final _right = _slide(const Offset(1.2, 0));

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  String get title => widget.title;
  ValueListenable<ChatStatus?> get status => widget.status;
  VoidCallback get onBack => widget.onBack;
  VoidCallback get onInfo => widget.onInfo;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final top = MediaQuery.paddingOf(context).top;

    return Stack(
      // The fade reaches below the header; clipping would cut it as a line.
      clipBehavior: Clip.none,
      children: [
        // Fades the messages scrolling under the header.
        Positioned.fill(
          bottom: -24,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    colors.backgroundPrimary.withAlpha(190),
                    colors.backgroundPrimary.withAlpha(120),
                    colors.backgroundPrimary.withAlpha(0),
                  ],
                  stops: const [0, 0.6, 1],
                ),
              ),
            ),
          ),
        ),
        Padding(
          // Raised so the tabs' bottom lines up with the notch's: the notch is
          // 6 + 38.5 (title and status) + 10 tall below the status bar, a tab
          // is curve + body tall.
          padding: EdgeInsets.only(
            top: (top + 54.5 - _EdgeTab._tabHeight - _EdgeTab._fillet)
                .clamp(0, double.infinity),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SlideTransition(
                position: _left,
                child: _EdgeTab(
                  side: _Side.left,
                  icon: AppIcons.arrowLeft,
                  tooltip: 'Back',
                  onTap: onBack,
                ),
              ),
              const Spacer(),
              // The left tab's curve is above it and this one's below, so
              // this one moves down by the curve to line up with it.
              SlideTransition(
                position: _right,
                child: Padding(
                  padding: const EdgeInsets.only(top: _EdgeTab._fillet),
                  child: _EdgeTab(
                    side: _Side.right,
                    icon: AppIcons.search,
                    tooltip: 'Search',
                    onTap: widget.onSearch,
                  ),
                ),
              ),
            ],
          ),
        ),
        // The name and status hang from the top edge like a notch.
        Align(
          alignment: Alignment.topCenter,
          child: SlideTransition(
            position: _notch,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width -
                    2 * (_EdgeTab._width + 6),
              ),
              child: _Notch(
                top: 0,
                onTap: onInfo,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(18, top + 6, 18, 10),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.titleLarge.copyWith(
                          fontSize: 18,
                          height: 1.2,
                        ),
                      ),
                      ValueListenableBuilder<ChatStatus?>(
                        valueListenable: status,
                        builder: (context, status, _) => AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(
                            status?.text ?? '',
                            key: ValueKey(status?.text),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.3,
                              fontWeight: status?.active ?? false
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: status?.active ?? false
                                  ? colors.secondary
                                  : colors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

enum _Side { left, right }

/// White container hanging from the top edge, flowing into it with
/// concave curves on both sides, like a laptop's camera notch.
class _Notch extends StatelessWidget {
  const _Notch({
    required this.child,
    required this.onTap,
    required this.top,
  });

  /// Where the curves start; 0 hangs it from the very top.
  final double top;
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = _NotchShape(top);
    return CustomPaint(
      painter: _ShadowPainter(shape),
      child: ClipPath(
        clipper: shape,
        child: Material(
          color: Colors.white,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _NotchShape.fillet,
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _NotchShape extends CustomClipper<Path> {
  const _NotchShape(this.top);

  final double top;

  static const fillet = 16.0;
  static const _radius = 22.0;

  @override
  Path getClip(Size size) {
    const f = fillet;
    const r = _radius;
    final w = size.width;
    final h = size.height;
    final t = top;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(0, t)
      ..quadraticBezierTo(f, t, f, t + f)
      ..lineTo(f, h - r)
      ..quadraticBezierTo(f, h, f + r, h)
      ..lineTo(w - f - r, h)
      ..quadraticBezierTo(w - f, h, w - f, h - r)
      ..lineTo(w - f, t + f)
      ..quadraticBezierTo(w - f, t, w, t)
      ..lineTo(w, 0)
      ..close();
  }

  @override
  bool shouldReclip(_NotchShape oldClipper) => oldClipper.top != top;
}

/// A button shaped as a tab attached to the screen edge. A concave curve
/// flows it into the edge: above the left tab, below the right one.
class _EdgeTab extends StatelessWidget {
  const _EdgeTab({
    required this.side,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  static const _width = 58.0;
  static const _tabHeight = 50.0;
  static const _fillet = 16.0;

  final _Side side;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = _EdgeTabShape(side);
    final isLeft = side == _Side.left;

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: _width,
        height: _tabHeight + _fillet,
        child: CustomPaint(
          painter: _ShadowPainter(shape),
          child: ClipPath(
            clipper: shape,
            child: Material(
              color: Colors.white,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  // The icon sits in the tab, not in the curve.
                  padding: EdgeInsets.only(
                    top: isLeft ? _fillet : 0,
                    bottom: isLeft ? 0 : _fillet,
                    left: isLeft ? 0 : 6,
                    right: isLeft ? 6 : 0,
                  ),
                  child: Center(
                    child: Icon(
                      icon,
                      size: 20,
                      color: context.colorTheme.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgeTabShape extends CustomClipper<Path> {
  const _EdgeTabShape(this.side);

  final _Side side;

  static const _radius = 18.0;

  @override
  Path getClip(Size size) {
    const f = _EdgeTab._fillet;
    const r = _radius;
    final w = size.width;
    final h = size.height;

    // Drawn for the left side, with the curve on top; the right tab is
    // the same shape turned half a turn.
    final path = Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(0, f, f, f)
      ..lineTo(w - r, f)
      ..quadraticBezierTo(w, f, w, f + r)
      ..lineTo(w, h - r)
      ..quadraticBezierTo(w, h, w - r, h)
      ..lineTo(0, h)
      ..close();

    if (side == _Side.left) return path;
    return path.transform(
      (Matrix4.identity()
            ..translateByDouble(w, h, 0, 1)
            ..rotateZ(3.141592653589793))
          .storage,
    );
  }

  @override
  bool shouldReclip(_EdgeTabShape oldClipper) => oldClipper.side != side;
}

class _ShadowPainter extends CustomPainter {
  const _ShadowPainter(this.shape);

  final CustomClipper<Path> shape;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawShadow(
      shape.getClip(size),
      const Color(0x55000000),
      5,
      false,
    );
  }

  @override
  bool shouldRepaint(_ShadowPainter oldDelegate) => oldDelegate.shape != shape;
}
