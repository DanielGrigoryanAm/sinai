import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';
import 'package:sinai/common/app_icons.dart';

class CustomAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool showBackButton;
  final String? title;
  final VoidCallback? onBackPressed;
  final List<Widget>? actions;

  /// Small line under the title, e.g. "online" or "typing…".
  final Widget? subtitle;

  const CustomAppBar({
    super.key,
    this.showBackButton = false,
    this.title,
    this.onBackPressed,
    this.actions,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: context.colorTheme.backgroundPrimary,
      leading: showBackButton
          ? IconButton(
              icon: const Icon(AppIcons.arrowLeft),
              onPressed: onBackPressed ?? () => context.router.pop(),
            )
          : null,
      title: title == null
          ? null
          : subtitle == null
              ? Text(
                  title!,
                  style: context.textTheme.titleLarge,
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.titleLarge.copyWith(
                        fontSize: 19,
                      ),
                    ),
                    subtitle!,
                  ],
                ),
      centerTitle: true,
      actions: actions,
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
