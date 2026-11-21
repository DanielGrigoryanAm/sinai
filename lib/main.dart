import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sinai/common/onboarding_prefs.dart';
import 'package:sinai/features/presence/presence_service.dart';
import 'package:sinai/notifications/notification_service.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/text_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

late final AppRouter appRouter;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }

  PresenceService.instance.start();

  final nameConfirmed = await OnboardingPrefs.isNameConfirmed();
  appRouter = AppRouter(showOnboarding: !nameConfirmed);

  NotificationService.instance.onOpenChat = (chatCode, chatName) {
    appRouter.push(ChatRoute(chatCode: chatCode, chatName: chatName));
  };

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      // The app only has a light design so far; a system dark theme would
      // lack the typography extension every screen relies on.
      themeMode: ThemeMode.light,
      routerConfig: appRouter.config(),
      theme: ThemeData(
        textTheme: GoogleFonts.interTextTheme(),
        extensions: <ThemeExtension<dynamic>>[
          AppTypography.defaultTypography(),
        ],
      ),
    );
  }
}
