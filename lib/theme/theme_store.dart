import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sinai/theme/color_theme.dart';

/// The app's colors, which the user can change. Saved on the device.
class ThemeStore extends ValueNotifier<ColorTheme> {
  ThemeStore._() : super(lightColorTheme);

  static final instance = ThemeStore._();

  static const _prefix = 'theme_color_';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    var theme = lightColorTheme;
    for (final slot in ColorSlot.values) {
      final saved = prefs.getInt('$_prefix${slot.name}');
      if (saved != null) theme = slot.apply(theme, Color(saved));
    }
    value = theme;
  }

  Future<void> set(ColorSlot slot, Color color) async {
    value = slot.apply(value, color);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_prefix${slot.name}', color.toARGB32());
  }

  /// Back to the app's own colors. Chats keep the colors set in them.
  Future<void> reset() async {
    value = lightColorTheme;
    final prefs = await SharedPreferences.getInstance();
    for (final slot in ColorSlot.values) {
      await prefs.remove('$_prefix${slot.name}');
    }
  }
}

/// The colors the user can pick: the app's own (profile → App colors)
/// and a chat's (chat → Chat colors), see [isChat].
enum ColorSlot {
  accent('Accent', 'Buttons, highlights, online status'),
  background('Background', 'Behind chats and messages'),
  surface('Cards', 'Bubbles, fields and sheets'),
  myBubble('My messages', 'Bubbles of your own messages'),
  text('Text', 'Message text and titles in this chat');

  const ColorSlot(this.label, this.hint);

  final String label;
  final String hint;

  /// Set per chat, in that chat only (see ChatColorsStore); the others
  /// are the app's, everywhere.
  bool get isChat => this == myBubble || this == text;

  static List<ColorSlot> get app => [
        for (final s in values)
          if (!s.isChat) s
      ];
  static List<ColorSlot> get chat => [
        for (final s in values)
          if (s.isChat) s
      ];

  Color of(ColorTheme t) => switch (this) {
        accent => t.secondary,
        background => t.backgroundPrimary,
        surface => t.backgroundSecondary,
        myBubble => t.myBubble,
        text => t.textPrimary,
      };

  ColorTheme apply(ColorTheme t, Color c) => switch (this) {
        accent => t.copyWith(secondary: c),
        background => t.copyWith(backgroundPrimary: c),
        surface => t.copyWith(backgroundSecondary: c),
        myBubble => t.copyWith(myBubble: c),
        text => t.copyWith(textPrimary: c),
      };
}
