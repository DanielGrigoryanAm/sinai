import 'package:auto_route/auto_route.dart';
import 'package:sinay/pages/home/home_screen.dart';
import 'package:sinay/pages/onboarding/onboarding_screen.dart';
import 'package:sinay/pages/profile/profile_screen.dart';

part 'app_router.gr.dart';


@AutoRouterConfig(replaceInRouteName: 'Screen|Section|Page,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    
  ];
}