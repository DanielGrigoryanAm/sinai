import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:sinai/api/live_socket.dart';

/// Tells the other participants of a chat that the user is typing, over
/// the live socket.
///
/// The mark is sent again every few seconds while the message field has
/// text, and fades on the other phones without one. Clearing the field,
/// a pause in typing or leaving the chat sends "stopped" so it goes at
/// once.
class TypingReporter {
  TypingReporter({required this.chatCode, required this.controller}) {
    controller.addListener(_onTextChanged);
  }

  /// How often the typing mark is refreshed while typing continues.
  static const refresh = Duration(seconds: 4);

  final String chatCode;
  final TextEditingController controller;

  DateTime? _lastSent;
  bool _marked = false;
  Timer? _idleTimer;

  void _onTextChanged() {
    if (controller.text.trim().isEmpty) {
      _clear();
      return;
    }

    // Stopped typing without sending: drop the mark after a pause.
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(seconds: 6), _clear);

    final now = DateTime.now();
    if (_lastSent != null && now.difference(_lastSent!) < refresh) return;
    _lastSent = now;
    _marked = true;
    LiveSocket.instance.sendTyping(chatCode);
  }

  void _clear() {
    _idleTimer?.cancel();
    _lastSent = null;
    if (!_marked) return;
    _marked = false;
    LiveSocket.instance.sendTypingStopped(chatCode);
  }

  void dispose() {
    controller.removeListener(_onTextChanged);
    _clear();
  }
}
