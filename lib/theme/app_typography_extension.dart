import 'package:flutter/material.dart';
import 'package:sinay/theme/text_theme.dart';

extension AppTypographyExtension on BuildContext {
  AppTypography get textTheme {
    final typography = Theme.of(this).extension<AppTypography>();
    assert(typography != null, 'AppTypography not found in ThemeData.extensions.');
    return typography!;
  }
}