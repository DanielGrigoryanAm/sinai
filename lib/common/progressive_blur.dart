import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Blurs whatever is behind it, from sharp at the top to fully blurred and
/// tinted with [color] at the bottom.
///
/// Flutter can't fade a single blur, so stacked bands blur progressively
/// more of the area towards the bottom, under a color gradient that hides
/// the band edges.
class ProgressiveBlur extends StatelessWidget {
  const ProgressiveBlur({
    super.key,
    required this.color,
    this.maxSigma = 10,
    this.steps = 12,
  });

  final Color color;
  final double maxSigma;
  final int steps;

  double _sigma(int band) {
    final t = band / steps;
    return maxSigma * t * t;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 1; i <= steps; i++)
            // Band i covers the lower part of the area and blurs a bit more
            // than the band above it. The blur grows quadratically, so the
            // top bands differ by a barely visible amount and leave no edge.
            FractionallySizedBox(
              alignment: Alignment.bottomCenter,
              heightFactor: 1 - (i - 1) / steps,
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: _sigma(i),
                    sigmaY: _sigma(i),
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // Eases in, so the tint starts as softly as the blur.
                colors: [
                  color.withAlpha(0),
                  color.withAlpha(25),
                  color.withAlpha(90),
                  color.withAlpha(180),
                  color.withAlpha(240),
                ],
                stops: const [0, 0.25, 0.5, 0.75, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reports its child's size whenever it changes.
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({super.key, required this.onChange, super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMeasureSize(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderObject renderObject,
  ) {
    (renderObject as _RenderMeasureSize).onChange = onChange;
  }
}

class _RenderMeasureSize extends RenderProxyBox {
  _RenderMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _lastSize;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _lastSize) return;
    _lastSize = size;
    // Reported after layout, as the listener usually calls setState.
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(size));
  }
}
