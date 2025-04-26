import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:sinay/theme/colot_theme.dart';

@RoutePage()
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colorTheme.background,
      body: Container(),
    );
  }
}
