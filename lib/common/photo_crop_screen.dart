import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:sinai/common/photo_compress.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// Picks a photo from the gallery and lets the user fit it into the
/// circle; returns it ready to upload (a square JPEG, at most 600 px), or
/// null when they change their mind.
Future<({Uint8List bytes, String type})?> pickRoundPhoto(
  BuildContext context,
) async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    maxWidth: 2000,
    maxHeight: 2000,
    imageQuality: 95,
  );
  if (picked == null) return null;
  // Turned the right way up first: the editor shows the pixels as stored.
  final upright = await compressPhoto(
    await picked.readAsBytes(),
    picked.mimeType ?? 'image/jpeg',
    maxSide: 2000,
    quality: 92,
  );
  if (!context.mounted) return null;
  final cropped = await cropToCircle(context, upright.bytes);
  if (cropped == null) return null;
  return compressPhoto(cropped, 'image/png', maxSide: 600, quality: 85);
}

/// Lets the user place [bytes] in a circle (move with a finger, pinch to
/// zoom) and returns the square around that circle as PNG, or null when
/// they cancel. Used for profile and chat photos, which show as circles.
Future<Uint8List?> cropToCircle(BuildContext context, Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  if (!context.mounted) return null;
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PhotoCropScreen(image: image),
    ),
  );
}

class PhotoCropScreen extends StatefulWidget {
  const PhotoCropScreen({super.key, required this.image});

  final ui.Image image;

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  /// How much bigger than "just covers the circle" the photo is; 1 is the
  /// smallest allowed, so the circle never shows an edge of the photo.
  double _zoom = 1;
  static const _maxZoom = 6.0;

  /// Where the photo's centre is, from the circle's centre, in screen
  /// points.
  Offset _offset = Offset.zero;

  // The gesture as it started.
  double _startZoom = 1;
  Offset _startOffset = Offset.zero;
  Offset _startFocal = Offset.zero;

  /// The circle's diameter and centre for the current screen, set while
  /// laying out.
  double _circle = 0;
  Offset _centre = Offset.zero;

  bool _saving = false;

  ui.Image get _image => widget.image;

  /// Screen points per photo pixel at zoom 1: the shorter side fills the
  /// circle.
  double get _baseScale =>
      _circle / math.min(_image.width, _image.height).toDouble();

  double get _scale => _baseScale * _zoom;

  /// Keeps the photo over the whole circle at [scale].
  Offset _clamp(Offset offset, double scale) {
    final maxX = math.max(0.0, (_image.width * scale - _circle) / 2);
    final maxY = math.max(0.0, (_image.height * scale - _circle) / 2);
    return Offset(
      offset.dx.clamp(-maxX, maxX),
      offset.dy.clamp(-maxY, maxY),
    );
  }

  void _onScaleStart(ScaleStartDetails d) {
    _startZoom = _zoom;
    _startOffset = _offset;
    _startFocal = d.localFocalPoint - _centre;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final zoom = (_startZoom * d.scale).clamp(1.0, _maxZoom);
    final focal = d.localFocalPoint - _centre;
    // Zooms around the fingers and follows them as they move.
    final offset = focal + (_startOffset - _startFocal) * (zoom / _startZoom);
    setState(() {
      _zoom = zoom;
      _offset = _clamp(offset, _baseScale * zoom);
    });
  }

  /// Double tap: back to the whole photo, or in to twice the size.
  void _onDoubleTap() {
    setState(() {
      _zoom = _zoom > 1.01 ? 1 : 2;
      _offset = _clamp(_offset, _scale);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final scale = _scale;
      // The circle's square, in photo pixels.
      final side = _circle / scale;
      final centre = Offset(
        _image.width / 2 - _offset.dx / scale,
        _image.height / 2 - _offset.dy / scale,
      );
      final src = Rect.fromCenter(center: centre, width: side, height: side);
      // Never bigger than the part of the photo it comes from.
      final out = side.round().clamp(64, 800).toDouble();

      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        _image,
        src,
        Rect.fromLTWH(0, 0, out, out),
        Paint()..filterQuality = FilterQuality.high,
      );
      final cropped =
          await recorder.endRecording().toImage(out.toInt(), out.toInt());
      final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      Navigator.of(context).pop(data?.buffer.asUint8List());
    } catch (e) {
      debugPrint('Cropping the photo failed: $e');
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final size = box.biggest;
                  final circle = math.min(size.width, size.height) - 48;
                  if (circle != _circle) {
                    // First layout, or the screen changed: start (again)
                    // from the whole photo filling the circle.
                    _circle = circle;
                    _zoom = 1;
                    _offset = Offset.zero;
                  }
                  _centre = size.center(Offset.zero);
                  final w = _image.width * _scale;
                  final h = _image.height * _scale;

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onDoubleTap: _onDoubleTap,
                    child: Stack(
                      clipBehavior: Clip.hardEdge,
                      children: [
                        Positioned(
                          left: _centre.dx + _offset.dx - w / 2,
                          top: _centre.dy + _offset.dy - h / 2,
                          width: w,
                          height: h,
                          child: RawImage(
                            image: _image,
                            fit: BoxFit.fill,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            child: CustomPaint(
                              painter: _CircleMask(
                                centre: _centre,
                                diameter: _circle,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Move and pinch to fit the circle',
                      style: text.bodyLarge.copyWith(
                        fontSize: 14,
                        color: Colors.white70,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(),
                          child: Text(
                            'Cancel',
                            style: text.bodyLarge.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const Spacer(),
                        FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: colors.secondary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 28,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: _saving
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Save',
                                  style: text.bodyLarge.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Darkens everything but the circle, which stays clear, with a thin
/// light ring around it.
class _CircleMask extends CustomPainter {
  const _CircleMask({required this.centre, required this.diameter});

  final Offset centre;
  final double diameter;

  @override
  void paint(Canvas canvas, Size size) {
    final circle = Rect.fromCircle(center: centre, radius: diameter / 2);
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addOval(circle);
    canvas.drawPath(shade, Paint()..color = const Color(0xA6000000));
    canvas.drawOval(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xB3FFFFFF),
    );
  }

  @override
  bool shouldRepaint(_CircleMask old) =>
      old.centre != centre || old.diameter != diameter;
}
