import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/common/custom_button.dart';
import 'package:sinai/common/feature_flags.dart';
import 'package:sinai/common/custom_text_field.dart';
import 'package:sinai/common/gyro_horizontal_background.dart';
import 'package:sinai/features/start_chat/bloc/chat_bloc.dart';
import 'package:sinai/gen/assets.gen.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

@RoutePage()
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ChatBloc(),
      child: OnboardingScreenView(),
    );
  }
}

class OnboardingScreenView extends StatefulWidget {
  const OnboardingScreenView({super.key});

  @override
  State<OnboardingScreenView> createState() => _OnboardingScreenViewState();
}

class _OnboardingScreenViewState extends State<OnboardingScreenView> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = _nameController.text.trim();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'Wellcome to Sinai',
        ),
        backgroundColor: context.colorTheme.backgroundPrimary,
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            children: [
              SizedBox(height: 20),
              Expanded(
                child: GyroHorizontalBackground(
                  borderRadius: BorderRadius.circular(16),
                  imageProvider: Assets.images.bgMountain.provider(),
                  imageAspectRatio: 1536 / 819,
                  showInnerShadow: true,
                  innerShadowColor: Color(0x66000000),
                  innerShadowBlur: 4,
                  innerShadowSpread: 2,
                ),
              ),
              SizedBox(height: 20),
              CustomTextField(
                controller: _nameController,
                hintText: 'Enter your name',
                onChanged: (_) => setState(() {}),
              ),
              SizedBox(height: 20),
              CustomButton.primary(
                text: 'Start',
                onTap: name.isNotEmpty ? () => _onStart(name) : null,
              ),
              if (FeatureFlags.phoneSignIn) ...[
                SizedBox(height: 12),
                TextButton(
                  onPressed: () =>
                      context.router.push(PhoneRoute(restore: true)),
                  child: Text(
                    'Already have an account? Restore it',
                    style: context.textTheme.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.colorTheme.secondary,
                    ),
                  ),
                ),
                SizedBox(height: 36),
              ] else
                SizedBox(height: 60),
            ],
          ),
        ),
      ),
    );
  }

  void _onStart(String name) {
    context.read<ChatBloc>().add(
          SetUserNameEvent(name),
        );

    context.router.replaceAll([const ChatsRoute()]);
  }
}
