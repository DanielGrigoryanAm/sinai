import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinai/theme/color_theme.dart';
import 'package:sinai/theme/theme_store.dart';

/// Colors set for one chat only (chat → Chat colors): the user's message
/// bubbles and the text. Other chats keep the app's. Saved on the device.
class ChatColorsStore
    extends ValueNotifier<Map<String, Map<ColorSlot, Color>>> {
  ChatColorsStore._() : super(const {});

  static final instance = ChatColorsStore._();

  static const _key = 'chat_colors';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      value = {
        for (final chat in json.entries)
          chat.key: {
            for (final slot in (chat.value as Map<String, dynamic>).entries)
              if (ColorSlot.values.asNameMap()[slot.key] case final s?)
                s: Color(slot.value as int),
          },
      };
    } catch (e) {
      debugPrint('Chat colors: could not load: $e');
    }
  }

  /// The app's colors with [chat]'s own laid over them.
  ColorTheme themeFor(String chat, ColorTheme app) {
    var theme = app;
    for (final e in (value[chat.toUpperCase()] ?? const {}).entries) {
      theme = e.key.apply(theme, e.value);
    }
    return theme;
  }

  Future<void> set(String chat, ColorSlot slot, Color color) async {
    final code = chat.toUpperCase();
    value = {
      ...value,
      code: {...?value[code], slot: color},
    };
    await _save();
  }

  /// Back to the app's colors in [chat].
  Future<void> reset(String chat) async {
    value = {...value}..remove(chat.toUpperCase());
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _key,
        jsonEncode({
          for (final chat in value.entries)
            chat.key: {
              for (final slot in chat.value.entries)
                slot.key.name: slot.value.toARGB32(),
            },
        }));
  }
}

/// Gives [child] (a chat's screens) the app's colors with the chat's own
/// over them, and rebuilds it when either changes.
class ChatColorsScope extends StatelessWidget {
  const ChatColorsScope({
    super.key,
    required this.chatCode,
    required this.child,
  });

  final String chatCode;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: ChatColorsStore.instance,
      builder: (context, _, __) {
        final theme = Theme.of(context);
        final colors =
            ChatColorsStore.instance.themeFor(chatCode, context.colorTheme);
        return Theme(
          data: theme.copyWith(extensions: [
            for (final e in theme.extensions.values)
              if (e is! AppColors) e,
            AppColors(colors),
          ]),
          child: child,
        );
      },
    );
  }
}
