import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/widgets.dart';
import 'package:sinai/api/api_config.dart';
import 'package:sinai/api/live_socket.dart';
import 'package:sinai/features/presence/realtime_db.dart';

/// Tells the other participants of a chat that the user is typing: over
/// the live socket on the backend, via `typing/{chatId}/{uid}` in the
/// Realtime Database on Firebase.
///
/// The mark is refreshed while the message field has text and removed
/// when the field is cleared, after a pause in typing, when the chat is
/// left, or by the server if the app disconnects.
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

  DatabaseReference? get _ref {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return uid == null ? null : RealtimeDb.typing(chatCode).child(uid);
  }

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
    _mark();
  }

  Future<void> _mark() async {
    // On the backend the mark goes over the socket and fades on its own
    // on the other phones after a few seconds without a new one.
    if (ApiConfig.useBackend) {
      _marked = true;
      LiveSocket.instance.sendTyping(chatCode);
      return;
    }
    final ref = _ref;
    if (ref == null) return;
    final name = FirebaseAuth.instance.currentUser?.displayName?.trim();
    try {
      if (!_marked) await ref.onDisconnect().remove();
      _marked = true;
      await ref.set({
        'name': name == null || name.isEmpty ? 'Someone' : name,
        'at': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('Typing mark failed: $e');
    }
  }

  Future<void> _clear() async {
    _idleTimer?.cancel();
    _lastSent = null;
    if (!_marked) return;
    _marked = false;
    if (ApiConfig.useBackend) {
      LiveSocket.instance.sendTypingStopped(chatCode);
      return;
    }
    final ref = _ref;
    if (ref == null) return;
    try {
      await ref.remove();
      await ref.onDisconnect().cancel();
    } catch (e) {
      debugPrint('Clearing the typing mark failed: $e');
    }
  }

  void dispose() {
    controller.removeListener(_onTextChanged);
    _clear();
  }
}
