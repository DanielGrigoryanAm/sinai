import 'package:flutter/material.dart';
import 'package:sinai/common/app_icons.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';
import 'package:sinai/theme/theme_store.dart';

/// Lets the user pick the app's main colors. Changes apply right away.
class AppColorsScreen extends StatelessWidget {
  const AppColorsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: colors.backgroundPrimary,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(AppIcons.arrowLeft, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'App colors',
          style: context.textTheme.titleLarge.copyWith(
            color: colors.textPrimary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: ThemeStore.instance.reset,
            child: Text('Reset', style: TextStyle(color: colors.secondary)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          for (final slot in ColorSlot.values) ...[
            _SlotPicker(slot: slot),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}

class _SlotPicker extends StatelessWidget {
  const _SlotPicker({required this.slot});

  final ColorSlot slot;

  static const _swatches = {
    ColorSlot.accent: [
      Color(0xFFE1B866),
      Color(0xFFE57373),
      Color(0xFFF06292),
      Color(0xFFBA68C8),
      Color(0xFF7986CB),
      Color(0xFF4FC3F7),
      Color(0xFF4DB6AC),
      Color(0xFF81C784),
      Color(0xFFFF8A65),
      Color(0xFF90A4AE),
    ],
    ColorSlot.background: [
      Color(0xFFFDF7E9),
      Color(0xFFFFFFFF),
      Color(0xFFF3F4F6),
      Color(0xFFEAF2FB),
      Color(0xFFEFF7F1),
      Color(0xFFFCEEF2),
      Color(0xFFF3EEFB),
      Color(0xFFFFF1E6),
      Color(0xFFE8E6E1),
      Color(0xFFE6F4F4),
    ],
    ColorSlot.surface: [
      Color(0xFFFFFFFF),
      Color(0xFFFFFBF2),
      Color(0xFFF7F7F8),
      Color(0xFFF5F9FF),
      Color(0xFFF6FBF7),
      Color(0xFFFFF7F9),
      Color(0xFFFAF7FF),
      Color(0xFFFFFAF5),
    ],
    ColorSlot.myBubble: [
      Color(0xFF9CC4F0),
      Color(0xFFF3D9A4),
      Color(0xFFB9E4C9),
      Color(0xFFF7C1CF),
      Color(0xFFD4C4F3),
      Color(0xFFA8E0E6),
      Color(0xFFFFCFAE),
      Color(0xFFDADDE3),
      Color(0xFFC8E6A0),
      Color(0xFFB5C7F7),
    ],
    ColorSlot.text: [
      Color(0xFF000000),
      Color(0xFF1B2030),
      Color(0xFF2E2A24),
      Color(0xFF1F3A5F),
      Color(0xFF233D2E),
      Color(0xFF4A2338),
      Color(0xFF3B2F5C),
      Color(0xFF444444),
    ],
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final current = slot.of(colors);
    final swatches = _swatches[slot]!;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            slot.label,
            style: context.textTheme.bodyLarge.copyWith(
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          Text(
            slot.hint,
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
          if (slot == ColorSlot.myBubble || slot == ColorSlot.text) ...[
            const SizedBox(height: 14),
            const _ChatPreview(),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final swatch in swatches)
                _Swatch(
                  color: swatch,
                  selected: swatch.toARGB32() == current.toARGB32(),
                  onTap: () => ThemeStore.instance.set(slot, swatch),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = color.computeLuminance() < 0.4;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? context.colorTheme.textPrimary
                : Colors.black.withAlpha(25),
            width: selected ? 2.5 : 1,
          ),
        ),
        child: selected
            ? Icon(
                AppIcons.check,
                size: 18,
                color: dark ? Colors.white : Colors.black,
              )
            : null,
      ),
    );
  }
}

/// A tiny chat showing the current message and text colors.
class _ChatPreview extends StatelessWidget {
  const _ChatPreview();

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    Widget bubble(String text, Color color, {required bool mine}) => Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(15),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              text,
              style: TextStyle(fontSize: 15, color: colors.textPrimary),
            ),
          ),
        );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      decoration: BoxDecoration(
        color: colors.backgroundPrimary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          bubble('Hi! How are you?', colors.backgroundSecondary, mine: false),
          bubble('Great, thanks! 😊', colors.myBubble, mine: true),
        ],
      ),
    );
  }
}
