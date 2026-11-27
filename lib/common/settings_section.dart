import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// One block of a settings-like screen: a small label, a white rounded
/// card of [rows] (the same look as the app's search fields), and an
/// optional softer line under it.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    this.label,
    required this.rows,
    this.caption,
  });

  final String? label;
  final List<Widget> rows;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (label != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Text(
              label!.toUpperCase(),
              style: text.bodySmall.copyWith(
                fontSize: 12,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
                color: colors.textSecondary,
              ),
            ),
          ),
        Container(
          decoration: BoxDecoration(
            color: colors.backgroundSecondary,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (final (i, row) in rows.indexed) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 16,
                    endIndent: 16,
                    color: colors.border,
                  ),
                row,
              ],
            ],
          ),
        ),
        if (caption != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              caption!,
              style: text.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ),
      ],
    );
  }
}

/// A row of a [SettingsSection]: an icon or mark, its text, and something
/// on the right. All rows are the same height.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    this.leading,
    required this.child,
    this.trailing,
    this.onTap,
    this.color,
  });

  static const height = 52.0;

  final Widget? leading;

  /// Usually a [Text]; a field for rows one types into.
  final Widget child;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Text and icon colour, e.g. red for signing out.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    final tint = color ?? colors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IconTheme.merge(
            data: IconThemeData(size: 20, color: color ?? colors.secondary),
            child: DefaultTextStyle.merge(
              style: text.bodyLarge.copyWith(
                fontWeight: FontWeight.w500,
                color: tint,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              child: Row(
                children: [
                  if (leading != null) ...[
                    SizedBox.square(
                      dimension: 24,
                      child: Center(child: leading),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(child: child),
                  if (trailing != null) ...[
                    const SizedBox(width: 12),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A word on the right of a [SettingsRow] that does the row's thing
/// ("Save", "Join"), or a small spinner while it is busy.
class SettingsRowAction extends StatelessWidget {
  const SettingsRowAction({
    super.key,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  final String label;

  /// Null greys it out.
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    if (busy) {
      return SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colors.secondary,
        ),
      );
    }
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          label,
          style: context.textTheme.bodyLarge.copyWith(
            fontWeight: FontWeight.w700,
            color: onTap == null
                ? colors.textSecondary.withAlpha(120)
                : colors.secondary,
          ),
        ),
      ),
    );
  }
}

/// A text field filling a [SettingsRow], without a frame of its own.
class SettingsField extends StatelessWidget {
  const SettingsField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
    this.onSubmitted,
    this.autofocus = false,
    this.textCapitalization = TextCapitalization.none,
    this.inputFormatters,
    this.letterSpacing,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final bool autofocus;
  final TextCapitalization textCapitalization;
  final List<TextInputFormatter>? inputFormatters;

  /// Spaces out codes.
  final double? letterSpacing;

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      cursorColor: colors.secondary,
      textCapitalization: textCapitalization,
      textInputAction: TextInputAction.done,
      inputFormatters: inputFormatters,
      style: text.bodyLarge.copyWith(
        fontWeight: FontWeight.w500,
        letterSpacing: letterSpacing,
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: text.bodyLarge.copyWith(
          color: colors.textSecondary,
          letterSpacing: 0,
        ),
        border: InputBorder.none,
      ),
    );
  }
}
