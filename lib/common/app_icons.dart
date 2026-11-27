import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Flaticon UIcons (thin rounded, plus a few regular rounded where the thin
/// set has no plain variant). Fonts are subset to the glyphs below.
abstract final class AppIcons {
  static const trash = IconData(0xf32d, fontFamily: 'UiconsThin');
  static const close = IconData(0xf4e6, fontFamily: 'UiconsThin');
  static const edit = IconData(0xeda0, fontFamily: 'UiconsThin');
  static const copy = IconData(0xe53d, fontFamily: 'UiconsThin');
  static const add = IconData(0xe02e, fontFamily: 'UiconsThin');
  static const camera = IconData(0xe330, fontFamily: 'UiconsThin');
  static const logout = IconData(0xf08b, fontFamily: 'UiconsThin');
  static const brokenImage = IconData(0xea37, fontFamily: 'UiconsThin');
  static const shieldCheck = IconData(0xf04f, fontFamily: 'UiconsThin');
  static const share = IconData(0xf046, fontFamily: 'UiconsThin');
  static const reply = IconData(0xe0fd, fontFamily: 'UiconsThin');
  static const addImage = IconData(0xe032, fontFamily: 'UiconsThin');
  static const phone = IconData(0xee13, fontFamily: 'UiconsThin');
  static const userMinus = IconData(0xf3d8, fontFamily: 'UiconsThin');
  static const user = IconData(0xe44b, fontFamily: 'UiconsThin');
  static const chat = IconData(0xe4e5, fontFamily: 'UiconsThin');
  static const arrowRight = IconData(0xe0ec, fontFamily: 'UiconsThin');
  static const arrowLeft = IconData(0xe0e6, fontFamily: 'UiconsThin');
  static const check = IconData(0xe3d7, fontFamily: 'UiconsRegular');
  static const search = IconData(0xf015, fontFamily: 'UiconsRegular');
  static const palette = IconData(0xed5c, fontFamily: 'UiconsRegular');
  static const game = IconData(0xe898, fontFamily: 'UiconsRegular');
  static const refresh = IconData(0xef4b, fontFamily: 'UiconsRegular');
  static const more = IconData(0xec0b, fontFamily: 'UiconsRegular');
  static const play = IconData(0xee6a, fontFamily: 'UiconsRegular');
  static const pause = IconData(0xed86, fontFamily: 'UiconsRegular');
  static const download = IconData(0xe67e, fontFamily: 'UiconsRegular');
  static const lock = IconData(0xeb79, fontFamily: 'UiconsRegular');
  static const forward = IconData(0xe0fe, fontFamily: 'UiconsThin');
  static const arrowDown = IconData(0xe0d8, fontFamily: 'UiconsThin');
  static const images = IconData(0xea38, fontFamily: 'UiconsThin');
  static const link = IconData(0xeb4f, fontFamily: 'UiconsThin');

  // Solid icons for the notch menu.
  static const games = IconData(0xe898, fontFamily: 'UiconsSolid');
  static const chess = IconData(0xe3ea, fontFamily: 'UiconsSolid');
  static const ticTacToe = IconData(0xe983, fontFamily: 'UiconsSolid');
  static const checkers = IconData(0xe437, fontFamily: 'UiconsSolid');
  static const youtube = IconData(0xf4f9, fontFamily: 'UiconsBrands');
}

/// Play or pause icon, centred. In the font both glyphs sit at the left of
/// their box (play 0–244 of 300, pause 0–226), so they are moved right; play
/// a little more, so the triangle looks centred rather than measures so.
class PlayPauseIcon extends StatelessWidget {
  const PlayPauseIcon({
    super.key,
    required this.playing,
    this.size = 18,
    this.color,
    this.semanticLabel,
  });

  final bool playing;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(size * (playing ? 37 : 44) / 300, 0),
      child: Icon(
        playing ? AppIcons.pause : AppIcons.play,
        size: size,
        color: color,
        semanticLabel: semanticLabel,
      ),
    );
  }
}

/// A plain plus, drawn: the icon fonts only have one inside a circle.
class PlusIcon extends StatelessWidget {
  const PlusIcon({super.key, this.size = 24, this.color, this.strokeWidth});

  final double size;
  final Color? color;
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? IconTheme.of(context).color!;
    return CustomPaint(
      size: Size.square(size),
      painter: _LinePainter(color, strokeWidth ?? size / 12, (canvas, s, p) {
        canvas.drawLine(Offset(s / 2, s * .15), Offset(s / 2, s * .85), p);
        canvas.drawLine(Offset(s * .15, s / 2), Offset(s * .85, s / 2), p);
      }),
    );
  }
}

/// A person (head and shoulders) without a circle around it, drawn.
class ProfileIcon extends StatelessWidget {
  const ProfileIcon({super.key, this.size = 24, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? IconTheme.of(context).color!;
    return CustomPaint(
      size: Size.square(size),
      painter: _LinePainter(color, size / 15, (canvas, s, p) {
        canvas.drawCircle(Offset(s / 2, s * .33), s * .18, p);
        canvas.drawArc(
          Rect.fromLTRB(s * .17, s * .62, s * .83, s * 1.18),
          math.pi,
          math.pi,
          false,
          p,
        );
      }),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.color, this.strokeWidth, this.draw);

  final Color color;
  final double strokeWidth;
  final void Function(Canvas canvas, double size, Paint paint) draw;

  @override
  void paint(Canvas canvas, Size size) {
    draw(
      canvas,
      size.width,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_LinePainter old) =>
      old.color != color || old.strokeWidth != strokeWidth;
}
