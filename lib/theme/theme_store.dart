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

  Future<void> reset() async {
    value = lightColorTheme;
    final prefs = await SharedPreferences.getInstance();
    for (final slot in ColorSlot.values) {
      await prefs.remove('$_prefix${slot.name}');
    }
  }
}

/// The colors the user can pick.
enum ColorSlot {
  accent('Accent', 'Buttons, highlights, online status'),
  background('Background', 'Behind chats and messages'),
  surface('Cards', 'Bubbles, fields and sheets'),
  myBubble('My messages', 'Bubbles of your own messages'),
  text('Text', 'Titles and message text');

  const ColorSlot(this.label, this.hint);

  final String label;
  final String hint;

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
