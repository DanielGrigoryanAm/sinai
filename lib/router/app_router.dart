import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:sinai/features/chat/chat_screen.dart';
import 'package:sinai/features/onboarding/onboarding_screen.dart';
import 'package:sinai/features/profile/profile_screen.dart';
import 'package:sinai/features/start_chat/start_chat_screen.dart';

part 'app_router.gr.dart';

@AutoRouterConfig(replaceInRouteName: 'Screen,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
        AutoRoute(
          page: OnboardingRoute.page,
          initial: true,
        ),
        AutoRoute(
          page: StartChatRoute.page,
        ),
        AutoRoute(
          page: ChatRoute.page,
        ),
      ];
}
