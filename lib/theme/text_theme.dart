import 'package:flutter/material.dart';

class AppTypography extends ThemeExtension<AppTypography> {
  final TextStyle titleLarge;
  final TextStyle titleSmall;
  final TextStyle bodyLarge;
  final TextStyle bodySmall;

  const AppTypography({
    required this.titleLarge,
    required this.titleSmall,
    required this.bodyLarge,
    required this.bodySmall,
  });

  factory AppTypography.defaultTypography() {
    return AppTypography(
      titleLarge: const TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.bold,
        color: Color.fromARGB(255, 6, 8, 49),
      ),
      titleSmall: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: Color.fromARGB(221, 21, 29, 60),
      ),
      bodyLarge: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.normal,
        color: Colors.black87,
      ),
      bodySmall: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.normal,
        color: Color.fromARGB(255, 69, 69, 69),
      ),
    );
  }

  @override
  AppTypography copyWith({
    TextStyle? titleLarge,
    TextStyle? titleSmall,
    TextStyle? bodyLarge,
    TextStyle? bodySmall,
  }) {
    return AppTypography(
      titleLarge: titleLarge ?? this.titleLarge,
      titleSmall: titleSmall ?? this.titleSmall,
      bodyLarge: bodyLarge ?? this.bodyLarge,
      bodySmall: bodySmall ?? this.bodySmall,
    );
  }

  @override
  AppTypography lerp(ThemeExtension<AppTypography>? other, double t) {
    if (other is! AppTypography) return this;
    return AppTypography(
      titleLarge: TextStyle.lerp(titleLarge, other.titleLarge, t)!,
      titleSmall: TextStyle.lerp(titleSmall, other.titleSmall, t)!,
      bodyLarge: TextStyle.lerp(bodyLarge, other.bodyLarge, t)!,
      bodySmall: TextStyle.lerp(bodySmall, other.bodySmall, t)!,
    );
  }
}
