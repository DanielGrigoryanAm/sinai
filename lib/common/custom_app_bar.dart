import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sinai/common/app_icons.dart';
import 'package:sinai/features/chat/widgets/edge_tab.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// The app's screen header: the title in the middle and, on screens one
/// can leave, the chat's back tab growing out of the left edge (see
/// [EdgeTab]), the same on every screen.
class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showBackButton;
  final String? title;
  final VoidCallback? onBackPressed;
  final List<Widget>? actions;

  /// Small line under the title, e.g. "online" or "typing…".
  final Widget? subtitle;

  /// Shown under the bar, e.g. tabs.
  final PreferredSizeWidget? bottom;

  const CustomAppBar({
    super.key,
    this.showBackButton = false,
    this.title,
    this.onBackPressed,
    this.actions,
    this.subtitle,
    this.bottom,
  });

  /// The back tab with a little room above and below.
  static const _barHeight = EdgeTab.tabHeight + EdgeTab.fillet + 12;

  @override
  Size get preferredSize => Size.fromHeight(
        (showBackButton ? _barHeight : kToolbarHeight) +
            (bottom?.preferredSize.height ?? 0),
      );

  Widget? _title(BuildContext context) {
    if (title == null) return null;
    final text = Text(
      title!,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: subtitle == null
          ? context.textTheme.titleLarge
          : context.textTheme.titleLarge.copyWith(fontSize: 19),
    );
    if (subtitle == null) return text;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [text, subtitle!],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    if (!showBackButton) {
      return AppBar(
        backgroundColor: colors.backgroundPrimary,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: _title(context),
        centerTitle: true,
        actions: actions,
        bottom: bottom,
      );
    }

    final title = _title(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Material(
        color: colors.backgroundPrimary,
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: _barHeight,
                child: Stack(
                  children: [
                    // Title and actions line up with the tab's body, under
                    // its curve.
                    if (title != null)
                      Positioned(
                        left: EdgeTab.width + 12,
                        right: EdgeTab.width + 12,
                        bottom: 6,
                        height: EdgeTab.tabHeight,
                        child: Center(child: title),
                      ),
                    Positioned(
                      left: 0,
                      bottom: 6,
                      child: EdgeTab(
                        side: EdgeSide.left,
                        icon: AppIcons.arrowLeft,
                        tooltip: 'Back',
                        // Also leaves screens opened with Navigator.push.
                        onTap: onBackPressed ??
                            () => Navigator.of(context).maybePop(),
                      ),
                    ),
                    if (actions != null)
                      Positioned(
                        right: 8,
                        bottom: 6,
                        height: EdgeTab.tabHeight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: actions!,
                        ),
                      ),
                  ],
                ),
              ),
              if (bottom != null) bottom!,
            ],
          ),
        ),
      ),
    );
  }
}
