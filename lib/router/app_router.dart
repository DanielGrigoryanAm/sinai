import 'package:auto_route/auto_route.dart';
import 'package:sinai/pages/home/home_screen.dart';
import 'package:sinai/pages/onboarding/onboarding_screen.dart';
import 'package:sinai/pages/profile/profile_screen.dart';

part 'app_router.gr.dart';


@AutoRouterConfig(replaceInRouteName: 'Screen|Section|Page,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: OnboardingRoute.page, initial: true),
    AutoRoute(page: HomeRoute.page),
  ];
}