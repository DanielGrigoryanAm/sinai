import 'package:flutter/material.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    required this.text,
    required this.onTap,
    this.isLoading = false,
  });

  final String text;
  final VoidCallback onTap;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 65,
        decoration: BoxDecoration(
          color: context.colorTheme.secondary,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Center(
          child: isLoading
              ? CircularProgressIndicator()
              : Text(
                  text,
                  style: context.textTheme.titleSmall
                      .copyWith(color: context.colorTheme.backgroundPrimary),
                ),
        ),
      ),
    );
  }
}
