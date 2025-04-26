import 'package:flutter/material.dart';

class ColorTheme {
  final Color background;
  final Color primary;
  final Color secondary;
  final Color textPrimary;
  final Color textSecondary;

  const ColorTheme({
    required this.background,
    required this.primary,
    required this.secondary,
    required this.textPrimary,
    required this.textSecondary,
  });
}

const lightColorTheme = ColorTheme(
  background: Color.fromARGB(255, 244, 241, 225),
  primary: Color.fromARGB(255, 0, 0, 0),
  secondary: Color.fromARGB(255, 209, 210, 212),
  textPrimary: Colors.black,
  textSecondary: Color.fromARGB(255, 138, 138, 138),
);

const darkColorTheme = ColorTheme(
  background: Colors.black,
  primary: Colors.blue,
  secondary: Colors.blueAccent,
  textPrimary: Colors.white,
  textSecondary: Colors.grey,
);

extension ColorThemeExtension on BuildContext {
  ColorTheme get colorTheme {
    final brightness = Theme.of(this).brightness;
    return brightness == Brightness.dark ? darkColorTheme : lightColorTheme;
  }
}
