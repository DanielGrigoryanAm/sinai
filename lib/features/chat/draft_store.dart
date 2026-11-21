import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Unsent text per chat, kept on the device so it survives leaving the
/// chat or closing the app.
class DraftStore {
  DraftStore._();

  static final DraftStore instance = DraftStore._();
  static const _key = 'chat_drafts';

  /// Draft text by chat code.
  final ValueNotifier<Map<String, String>> drafts = ValueNotifier(const {});
  Timer? _saveTimer;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      drafts.value = Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {}
  }

  String get(String chatCode) => drafts.value[chatCode] ?? '';

  void set(String chatCode, String text) {
    final trimmed = text.trim();
    if (trimmed == (drafts.value[chatCode] ?? '').trim()) return;
    final next = Map<String, String>.from(drafts.value);
    if (trimmed.isEmpty) {
      next.remove(chatCode);
    } else {
      next[chatCode] = text;
    }
    drafts.value = next;
    // Typing changes it on every key; write once things settle.
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), _save);
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(drafts.value));
    } catch (_) {}
  }
}
