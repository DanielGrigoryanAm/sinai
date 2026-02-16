import 'package:flutter/material.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

enum _CustomButtonType { primary, outline }

class CustomButton extends StatelessWidget {
  const CustomButton._({
    super.key,
    required this.text,
    required _CustomButtonType type,
    this.onTap,
    this.isLoading = false,
    this.leadingIcon,
    this.trailingIcon,
  }) : _type = type;

  factory CustomButton.primary({
    Key? key,
    required String text,
    VoidCallback? onTap,
    bool isLoading = false,
    IconData? leadingIcon,
    IconData? trailingIcon,
  }) {
    return CustomButton._(
      key: key,
      text: text,
      onTap: onTap,
      type: _CustomButtonType.primary,
      isLoading: isLoading,
      leadingIcon: leadingIcon,
      trailingIcon: trailingIcon,
    );
  }

  factory CustomButton.outline({
    Key? key,
    required String text,
    VoidCallback? onTap,
    bool isLoading = false,
    IconData? leadingIcon,
    IconData? trailingIcon,
  }) {
    return CustomButton._(
      key: key,
      text: text,
      onTap: onTap,
      type: _CustomButtonType.outline,
      isLoading: isLoading,
      leadingIcon: leadingIcon,
      trailingIcon: trailingIcon,
    );
  }

  final String text;
  final VoidCallback? onTap;
  final bool isLoading;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final _CustomButtonType _type;

  @override
  Widget build(BuildContext context) {
    final isPrimary = _type == _CustomButtonType.primary;
    final backgroundColor =
        isPrimary ? context.colorTheme.secondary : Colors.transparent;
    final textColor = isPrimary
        ? context.colorTheme.backgroundPrimary
        : context.colorTheme.secondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 65,
        decoration: BoxDecoration(
          color:
              onTap != null ? backgroundColor : backgroundColor.withAlpha(120),
          borderRadius: BorderRadius.circular(16),
          border: isPrimary
              ? null
              : Border.all(
                  color: context.colorTheme.secondary,
                  width: 2,
                ),
        ),
        child: Center(
          child: isLoading
              ? CircularProgressIndicator(
                  color: textColor,
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leadingIcon != null) ...[
                      Icon(leadingIcon, color: textColor),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      text,
                      style: context.textTheme.titleLarge.copyWith(
                        color: textColor,
                      ),
                    ),
                    if (trailingIcon != null) ...[
                      const SizedBox(width: 8),
                      Icon(trailingIcon, color: textColor),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
