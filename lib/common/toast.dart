import 'dart:async';

import 'package:flutter/material.dart';

/// What a toast says: it picks the icon and its color.
enum ToastKind { info, success, error }

/// Where toasts are drawn; set once the app's navigator exists.
OverlayState? Function()? toastOverlay;

OverlayEntry? _current;
GlobalKey<_ToastState>? _currentKey;

/// Shows a short message as a pill sliding up at the bottom, above the
/// keyboard and the message field. A new one replaces the one showing.
void showToast(
  String message, {
  ToastKind kind = ToastKind.info,
  Duration duration = const Duration(milliseconds: 2500),
}) {
  final overlay = toastOverlay?.call();
  if (overlay == null) return;
  hideToast(immediately: true);
  final key = GlobalKey<_ToastState>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _Toast(
      key: key,
      message: message,
      kind: kind,
      duration: duration,
      onGone: () {
        entry.remove();
        if (identical(_current, entry)) {
          _current = null;
          _currentKey = null;
        }
      },
    ),
  );
  _current = entry;
  _currentKey = key;
  overlay.insert(entry);
}

/// Takes the showing toast away.
void hideToast({bool immediately = false}) {
  final entry = _current;
  if (entry == null) return;
  if (immediately) {
    _current = null;
    _currentKey = null;
    entry.remove();
  } else {
    _currentKey?.currentState?._leave();
  }
}

class _Toast extends StatefulWidget {
  const _Toast({
    super.key,
    required this.message,
    required this.kind,
    required this.duration,
    required this.onGone,
  });

  final String message;
  final ToastKind kind;
  final Duration duration;
  final VoidCallback onGone;

  @override
  State<_Toast> createState() => _ToastState();
}

class _ToastState extends State<_Toast> with SingleTickerProviderStateMixin {
  late final AnimationController _show = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
    reverseDuration: const Duration(milliseconds: 260),
  )..forward();

  Timer? _timer;

  /// Follows a finger swiping it down.
  double _drag = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, _leave);
  }

  Future<void> _leave() async {
    _timer?.cancel();
    if (!mounted || _show.status == AnimationStatus.reverse) return;
    await _show.reverse();
    if (mounted) widget.onGone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _show.dispose();
    super.dispose();
  }

  static const _text = Color(0xFF1B2030);

  (IconData, Color) get _look => switch (widget.kind) {
        ToastKind.success => (Icons.check_rounded, const Color(0xFF2E9E5B)),
        ToastKind.error => (
            Icons.priority_high_rounded,
            const Color(0xFFE5484D)
          ),
        ToastKind.info => (Icons.info_outline_rounded, const Color(0xFF1D5FA8)),
      };

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    // Above the message field, or above the keyboard while it is open.
    final bottom = (keyboard > 0 ? keyboard : media.padding.bottom) + 84;
    final (icon, color) = _look;
    final enter = CurvedAnimation(
      parent: _show,
      curve: Curves.easeOutBack,
      reverseCurve: Curves.easeInCubic,
    );

    return Positioned(
      left: 16,
      right: 16,
      bottom: bottom,
      child: AnimatedBuilder(
        animation: enter,
        builder: (context, child) {
          final t = enter.value;
          return Opacity(
            opacity: _show.value.clamp(0, 1),
            child: Transform.translate(
              offset: Offset(0, (1 - t) * 60 + _drag),
              child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
            ),
          );
        },
        child: Center(
          child: GestureDetector(
            onTap: _leave,
            onVerticalDragUpdate: (d) =>
                setState(() => _drag = (_drag + d.delta.dy).clamp(0, 120)),
            onVerticalDragEnd: (d) {
              if (_drag > 30 || (d.primaryVelocity ?? 0) > 300) {
                _leave();
              } else {
                setState(() => _drag = 0);
              }
            },
            child: Material(
              color: Colors.white,
              elevation: 8,
              shadowColor: Colors.black26,
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: color.withAlpha(30),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, size: 17, color: color),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        widget.message,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          height: 1.3,
                          color: _text,
                          decoration: TextDecoration.none,
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
    );
  }
}
