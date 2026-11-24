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

  /// Bubbles of the user's own messages.
  final Color myBubble;

  const ColorTheme({
    required this.primary,
    required this.secondary,
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.myBubble,
  });

  ColorTheme copyWith({
    Color? secondary,
    Color? backgroundPrimary,
    Color? backgroundSecondary,
    Color? textPrimary,
    Color? myBubble,
  }) =>
      ColorTheme(
        primary: primary,
        secondary: secondary ?? this.secondary,
        backgroundPrimary: backgroundPrimary ?? this.backgroundPrimary,
        backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
        textPrimary: textPrimary ?? this.textPrimary,
        textSecondary: textSecondary,
        border: border,
        myBubble: myBubble ?? this.myBubble,
      );

  @override
  bool operator ==(Object other) =>
      other is ColorTheme &&
      other.primary == primary &&
      other.secondary == secondary &&
      other.backgroundPrimary == backgroundPrimary &&
      other.backgroundSecondary == backgroundSecondary &&
      other.textPrimary == textPrimary &&
      other.textSecondary == textSecondary &&
      other.border == border &&
      other.myBubble == myBubble;

  @override
  int get hashCode => Object.hash(primary, secondary, backgroundPrimary,
      backgroundSecondary, textPrimary, textSecondary, border, myBubble);
}

/// Carries the user's colors in the theme, so screens rebuild when they
/// change.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors(this.colors);

  final ColorTheme colors;

  @override
  AppColors copyWith({ColorTheme? colors}) => AppColors(colors ?? this.colors);

  @override
  AppColors lerp(AppColors? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

const lightColorTheme = ColorTheme(
  primary: Color(0xFF000000),
  secondary: Color(0xFFE1B866),
  backgroundPrimary: Color(0xFFFDF7E9),
  backgroundSecondary: Color(0xFFFFFFFF),
  textPrimary: Colors.black,
  textSecondary: Color(0xFF8A8A8A),
  border: Color(0xFFDCDCDC),
  myBubble: Color(0xFF9CC4F0),
);

const darkColorTheme = ColorTheme(
  primary: Colors.blue,
  secondary: Colors.blueAccent,
  backgroundPrimary: Colors.black,
  backgroundSecondary: Color(0xFFFFEDC7),
  textPrimary: Colors.white,
  textSecondary: Colors.grey,
  border: Color(0xFFDCDCDC),
  myBubble: Color(0xFF9CC4F0),
);

extension ColorThemeExtension on BuildContext {
  ColorTheme get colorTheme {
    return Theme.of(this).extension<AppColors>()?.colors ?? lightColorTheme;
  }
}
