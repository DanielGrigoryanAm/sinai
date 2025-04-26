import 'package:flutter/material.dart';

@immutable
class ColorTheme {
  final Color background;
  final Color primary;
  final Color green;
  final Color textPrimary;
  final Color textSecondary;

  const ColorTheme({
    required this.background,
    required this.primary,
    required this.green,
    required this.textPrimary,
    required this.textSecondary,
  });
}

const lightColorTheme = ColorTheme(
  background: Color.fromARGB(255, 255, 255, 255),
  primary: Color.fromARGB(255, 0, 0, 0),
  green: Color.fromARGB(255, 26, 46, 118),
  textPrimary: Colors.black,
  textSecondary: Color.fromARGB(255, 138, 138, 138),
);

const darkColorTheme = ColorTheme(
  background: Colors.black,
  primary: Colors.blue,
  green: Colors.blueAccent,
  textPrimary: Colors.white,
  textSecondary: Colors.grey,
);

extension ColorThemeExtension on BuildContext {
  ColorTheme get colorTheme {
    final brightness = Theme.of(this).brightness;
    return brightness == Brightness.dark ? darkColorTheme : lightColorTheme;
  }
}
