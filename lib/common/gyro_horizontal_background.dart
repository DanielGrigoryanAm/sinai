import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

class GyroHorizontalBackground extends StatefulWidget {
  const GyroHorizontalBackground({
    super.key,
    required this.imageProvider,
    this.borderRadius = BorderRadius.zero,
    this.imageWidthFactor = 1.65,
    this.imageAspectRatio,
    this.maxYawRadians = 0.82,
    this.yawGain = 3.6,
    this.rateSmoothing = 0.24,
    this.yawSmoothingTime = 0.005,
    this.maxDtSeconds = 0.08,
    this.deadZone = 0.006,
    this.invertDirection = true,
    this.animationDuration = const Duration(milliseconds: 900),
    this.animationCurve = Curves.easeOutCubic,
    this.fit = BoxFit.cover,
  });

  final ImageProvider imageProvider;
  final BorderRadius borderRadius;
  final double imageWidthFactor;
  final double? imageAspectRatio;
  final double maxYawRadians;
  final double yawGain;
  final double rateSmoothing;
  final double yawSmoothingTime;
  final double maxDtSeconds;
  final double deadZone;
  final bool invertDirection;
  final Duration animationDuration;
  final Curve animationCurve;
  final BoxFit fit;

  @override
  State<GyroHorizontalBackground> createState() =>
      _GyroHorizontalBackgroundState();
}

class _GyroHorizontalBackgroundState extends State<GyroHorizontalBackground> {
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  DateTime? _lastSampleAt;
  double _smoothedYawRate = 0;
  double _rawYaw = 0;
  double _smoothedYaw = 0;

  @override
  void initState() {
    super.initState();
    _gyroscopeSubscription = gyroscopeEventStream().listen(_onGyroscopeEvent);
  }

  @override
  void dispose() {
    _gyroscopeSubscription?.cancel();
    super.dispose();
  }

  void _onGyroscopeEvent(GyroscopeEvent event) {
    final now = DateTime.now();
    final lastSampleAt = _lastSampleAt;
    _lastSampleAt = now;
    if (lastSampleAt == null) {
      return;
    }

    final dtSeconds = now.difference(lastSampleAt).inMicroseconds /
        Duration.microsecondsPerSecond;
    if (dtSeconds <= 0) {
      return;
    }
    final safeDtSeconds = dtSeconds.clamp(0.0, widget.maxDtSeconds);

    final orientation = MediaQuery.orientationOf(context);
    final yawRate = orientation == Orientation.portrait ? event.y : event.x;

    _smoothedYawRate = _smoothedYawRate +
        ((yawRate - _smoothedYawRate) * widget.rateSmoothing);

    _rawYaw = (_rawYaw + (_smoothedYawRate * widget.yawGain * safeDtSeconds))
        .clamp(-widget.maxYawRadians, widget.maxYawRadians);

    final yawAlpha = 1 - math.exp(-safeDtSeconds / widget.yawSmoothingTime);
    _smoothedYaw = _smoothedYaw + ((_rawYaw - _smoothedYaw) * yawAlpha);

    if (_smoothedYaw.abs() < widget.deadZone) {
      _smoothedYaw = 0;
    }

    if (!mounted) {
      return;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final imageWidthByFactor = width * widget.imageWidthFactor;
          final imageWidthByAspect = widget.imageAspectRatio == null
              ? imageWidthByFactor
              : constraints.maxHeight * widget.imageAspectRatio!;
          final imageWidth = math.max(imageWidthByFactor, imageWidthByAspect);
          final maxHorizontalShift = (imageWidth - width) / 2;
          final normalizedYaw =
              (_smoothedYaw / widget.maxYawRadians).clamp(-1.0, 1.0);
          final direction = widget.invertDirection ? -1.0 : 1.0;
          final dx = direction * normalizedYaw * maxHorizontalShift;

          return SizedBox.expand(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: dx),
              duration: widget.animationDuration,
              curve: widget.animationCurve,
              builder: (context, animatedDx, child) {
                return Transform.translate(
                  offset: Offset(-animatedDx, 0),
                  child: child,
                );
              },
              child: OverflowBox(
                minWidth: imageWidth,
                maxWidth: imageWidth,
                alignment: Alignment.center,
                child: Image(
                  image: widget.imageProvider,
                  fit: widget.fit,
                  width: imageWidth,
                  height: constraints.maxHeight,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
