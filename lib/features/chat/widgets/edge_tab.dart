import 'package:flutter/material.dart';
import 'package:sinai/theme/color_theme.dart';

/// Which screen edge an [EdgeTab] grows out of.
enum EdgeSide { left, right }

/// A button shaped as a tab attached to the screen edge. A concave curve
/// flows it into the edge: above the left tab, below the right one.
class EdgeTab extends StatelessWidget {
  const EdgeTab({
    super.key,
    required this.side,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  static const width = 53.0;
  static const tabHeight = 45.0;
  static const fillet = 16.0;

  final EdgeSide side;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final shape = EdgeTabShape(side);
    final isLeft = side == EdgeSide.left;

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: width,
        height: tabHeight + fillet,
        child: CustomPaint(
          painter: ClipShadowPainter(shape),
          child: ClipPath(
            clipper: shape,
            child: Material(
              color: Colors.white,
              child: InkWell(
                onTap: onTap,
                child: Padding(
                  // The icon sits in the tab, not in the curve.
                  padding: EdgeInsets.only(
                    top: isLeft ? fillet : 0,
                    bottom: isLeft ? 0 : fillet,
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

class EdgeTabShape extends CustomClipper<Path> {
  const EdgeTabShape(this.side);

  final EdgeSide side;

  static const _radius = 18.0;

  @override
  Path getClip(Size size) {
    const f = EdgeTab.fillet;
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

    if (side == EdgeSide.left) return path;
    return path.transform(
      (Matrix4.identity()
            ..translateByDouble(w, h, 0, 1)
            ..rotateZ(3.141592653589793))
          .storage,
    );
  }

  @override
  bool shouldReclip(EdgeTabShape oldClipper) => oldClipper.side != side;
}

/// Draws the shadow of a clipped shape under it.
class ClipShadowPainter extends CustomPainter {
  const ClipShadowPainter(this.shape);

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
  bool shouldRepaint(ClipShadowPainter oldDelegate) =>
      oldDelegate.shape != shape;
}
