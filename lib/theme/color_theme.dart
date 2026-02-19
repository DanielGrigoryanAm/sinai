import 'package:flutter/material.dart';

@immutable
class ColorTheme {
  final Color primary;
  final Color secondary;
  final Color backgroundPrimary;
  final Color backgroundSecondary;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;

  const ColorTheme({
    required this.primary,
    required this.secondary,
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
  });
}

const lightColorTheme = ColorTheme(
  primary: Color(0xFF000000),
  secondary: Color(0xFFE1B866),
  backgroundPrimary: Color(0xFFFDF7E9),
  backgroundSecondary: Color(0xFFFFFFFF),
  textPrimary: Colors.black,
  textSecondary: Color(0xFF8A8A8A),
  border: Color(0xFFDCDCDC),
);

const darkColorTheme = ColorTheme(
  primary: Colors.blue,
  secondary: Colors.blueAccent,
  backgroundPrimary: Colors.black,
  backgroundSecondary: Color(0xFFFFEDC7),
  textPrimary: Colors.white,
  textSecondary: Colors.grey,
  border: Color(0xFFDCDCDC),
);

extension ColorThemeExtension on BuildContext {
  ColorTheme get colorTheme {
    final brightness = Theme.of(this).brightness;
    return brightness == Brightness.dark ? darkColorTheme : lightColorTheme;
  }
}
