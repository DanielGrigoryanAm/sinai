import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/common/custom_button.dart';
import 'package:sinai/features/account/account_options.dart';
import 'package:sinai/gen/assets.gen.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

/// First start: the only way in is signing in. Google makes a Sinai
/// account the first time and brings the same one back after that.
@RoutePage()
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool _busy = false;

  Future<void> _google() async {
    setState(() => _busy = true);
    // On success this replaces the screen with the chats list.
    await signInWithGoogle(context);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colorTheme;
    final text = context.textTheme;
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Welcome to Sinai',
      ),
      backgroundColor: colors.backgroundPrimary,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30),
        child: Column(
          children: [
            SizedBox(height: 20),
            Expanded(
              child: Center(
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    image: DecorationImage(
                      image: Assets.images.bgMountain.provider(),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Sign in to start. Your name and chats stay with your '
              'account, on any phone.',
              textAlign: TextAlign.center,
              style: text.bodyLarge.copyWith(color: colors.textSecondary),
            ),
            SizedBox(height: 20),
            CustomButton.primary(
              text: 'Continue with Google',
              isLoading: _busy,
              onTap: _busy ? null : _google,
            ),
            SizedBox(height: 60),
          ],
        ),
      ),
    );
  }
}
