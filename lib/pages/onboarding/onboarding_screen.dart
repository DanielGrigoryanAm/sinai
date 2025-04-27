import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:sinai/common/custom_app_bar.dart';
import 'package:sinai/common/custom_button.dart';
import 'package:sinai/gen/assets.gen.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/app_typography_extension.dart';
import 'package:sinai/theme/color_theme.dart';

@RoutePage()
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  bool isLoading = false;

  void _onStart() async {
    setState(() {
      isLoading = true;
    });
    await Future.delayed(Duration(seconds: 1));
    if (mounted) {
      context.router.replace(LoginRoute());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
        title: 'Wellcome to Sinai',
      ),
      backgroundColor: context.colorTheme.background,
      body: Padding(
        padding: const EdgeInsets.only(top: 100),
        child: Center(
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: context.colorTheme.green,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Assets.images.mountain.image(height: 200),
              ),
              SizedBox(height: 50),
              Text(
                'Start chatting',
                style: context.textTheme.titleSmall,
              ),
              SizedBox(height: 100),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 80.0),
                child: CustomButton(
                  text: 'Start',
                  onTap: () => _onStart(),
                ),
              ),
              SizedBox(height: 100),
              if (isLoading) CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
