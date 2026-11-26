import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:sinai/features/account/account_options.dart';
import 'package:sinai/features/chat/chat_screen.dart';
import 'package:sinai/features/chats/chats_screen.dart';
import 'package:sinai/features/onboarding/onboarding_screen.dart';
import 'package:sinai/features/phone/phone_screen.dart';
import 'package:sinai/features/profile/profile_screen.dart';
import 'package:sinai/features/start_chat/chat_ready_screen.dart';
import 'package:sinai/features/start_chat/create_chat_screen.dart';
import 'package:sinai/features/start_chat/start_chat_screen.dart';

part 'app_router.gr.dart';

@AutoRouterConfig(replaceInRouteName: 'Screen,Route')
class AppRouter extends RootStackRouter {
  AppRouter({required this.showOnboarding});

  /// Onboarding is shown only until the user confirms their name.
  final bool showOnboarding;

  @override
  List<AutoRoute> get routes => [
        AutoRoute(
          page: OnboardingRoute.page,
          initial: showOnboarding,
        ),
        AutoRoute(
          page: ChatsRoute.page,
          initial: !showOnboarding,
        ),
        AutoRoute(
          page: StartChatRoute.page,
        ),
        AutoRoute(
          page: CreateChatRoute.page,
        ),
        AutoRoute(
          page: ChatReadyRoute.page,
        ),
        AutoRoute(
          page: ChatRoute.page,
        ),
        AutoRoute(
          page: ProfileRoute.page,
        ),
        AutoRoute(
          page: PhoneRoute.page,
        ),
        AutoRoute(
          page: RestoreRoute.page,
        ),
      ];
}
