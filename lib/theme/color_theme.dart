import 'package:flutter/material.dart';

@immutable
class ColorTheme {
  final Color primary;
  final Color secondary;
  final Color backgroundPrimary;
  final Color backgroundSecondary;
  final Color textPrimary;
  final Color textSecondary;

  const ColorTheme({
    required this.primary,
    required this.secondary,
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.textPrimary,
    required this.textSecondary,
  });
}

const lightColorTheme = ColorTheme(
  primary: Color(0xFF000000),
  secondary: Color(0xFFE1B253),
  backgroundPrimary: Color(0xFFFFFFFF),
  backgroundSecondary: Color.fromARGB(255, 255, 250, 240),
  textPrimary: Colors.black,
  textSecondary: Color(0xFF8A8A8A),
);

const darkColorTheme = ColorTheme(
  primary: Colors.blue,
  secondary: Colors.blueAccent,
  backgroundPrimary: Colors.black,
  backgroundSecondary: Color(0xFFFFEDC7),
  textPrimary: Colors.white,
  textSecondary: Colors.grey,
);

extension ColorThemeExtension on BuildContext {
  ColorTheme get colorTheme {
    final brightness = Theme.of(this).brightness;
    return brightness == Brightness.dark ? darkColorTheme : lightColorTheme;
  }
}
