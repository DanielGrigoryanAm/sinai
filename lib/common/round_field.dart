import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sinai/common/app_icons.dart';
import 'package:sinai/features/chat/widgets/edge_tab.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// The top of a screen that is mostly one field (search, a code): the
/// chat's back tab growing out of the left edge, and [field] beside it,
/// lined up with the tab's body.
class EdgeFieldBar extends StatelessWidget {
  const EdgeFieldBar({super.key, required this.field, this.onBack});

  final Widget field;

  /// Pops the screen when null.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          EdgeTab(
            side: EdgeSide.left,
            icon: AppIcons.arrowLeft,
            tooltip: 'Back',
            onTap: onBack ?? () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          Expanded(child: field),
          const SizedBox(width: 16),
        ],
      ),
    );
  }
}

/// A white rounded field as tall as the back tab, with an icon in front
/// and a clear button once something is typed. [emptyTrailing] (say, a
/// Paste button) takes the clear button's place while it is empty.
class RoundField extends StatefulWidget {
  const RoundField({
    super.key,
    required this.controller,
    required this.hintText,
    this.focusNode,
    this.icon = AppIcons.search,
    this.autofocus = false,
    this.onChanged,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.textInputAction = TextInputAction.search,
    this.emptyTrailing,
  });

  final TextEditingController controller;
  final String hintText;
  final FocusNode? focusNode;
  final IconData icon;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final TextInputAction textInputAction;
  final Widget? emptyTrailing;

  @override
  State<RoundField> createState() => _RoundFieldState();
}

class _RoundFieldState extends State<RoundField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(RoundField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  /// Shows or hides the clear button.
  void _changed() => setState(() {});

  void _clear() {
    widget.controller.clear();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    final empty = widget.controller.text.isEmpty;

    return Container(
      height: EdgeTab.tabHeight,
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
      child: Row(
        children: [
          const SizedBox(width: 14),
          Icon(widget.icon, size: 18, color: colors.textSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              autofocus: widget.autofocus,
              cursorColor: colors.secondary,
              textInputAction: widget.textInputAction,
              textCapitalization: widget.textCapitalization,
              inputFormatters: widget.inputFormatters,
              style: text.bodyLarge,
              onChanged: widget.onChanged,
              decoration: InputDecoration(
                isDense: true,
                hintText: widget.hintText,
                hintStyle: text.bodyLarge.copyWith(color: colors.textSecondary),
                border: InputBorder.none,
              ),
            ),
          ),
          if (!empty)
            IconButton(
              tooltip: 'Clear',
              icon: Icon(AppIcons.close, size: 18, color: colors.textSecondary),
              onPressed: _clear,
            )
          else
            widget.emptyTrailing ?? const SizedBox(width: 14),
        ],
      ),
    );
  }
}
