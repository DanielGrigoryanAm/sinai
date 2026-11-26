import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sinai/api/auth_api.dart';
import 'package:sinai/api/live_socket.dart';
import 'package:sinai/common/onboarding_prefs.dart';
import 'package:sinai/features/chat/draft_store.dart';
import 'package:sinai/notifications/notification_service.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/color_theme.dart';
import 'package:sinai/theme/text_theme.dart';
import 'package:sinai/theme/theme_store.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

late final AppRouter appRouter;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Portrait only; the watch-together player turns to landscape itself.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }

  // The backend session comes from the Firebase account, so people keep
  // their chats when the app moves over.
  // Offline at start: keep trying in the background; the socket connects
  // as soon as there is a session.
  if (!await _signIn()) {
    unawaited(() async {
      while (!await _signIn()) {
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }());
  }
  // Being online is having the live socket open.
  LiveSocket.instance
    ..start()
    ..followAppLifecycle();

  await DraftStore.instance.load();
  await ThemeStore.instance.load();

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
    return ValueListenableBuilder<ColorTheme>(
      valueListenable: ThemeStore.instance,
      builder: (context, colors, _) => MaterialApp.router(
        // The app only has a light design so far; a system dark theme would
        // lack the typography extension every screen relies on.
        themeMode: ThemeMode.light,
        routerConfig: appRouter.config(),
        theme: ThemeData(
          textTheme: GoogleFonts.interTextTheme(),
          extensions: <ThemeExtension<dynamic>>[
            AppTypography.defaultTypography(),
            AppColors(colors),
          ],
        ),
      ),
    );
  }
}

Future<bool> _signIn() async {
  try {
    await AuthApi.instance.ensureSignedIn();
    return true;
  } catch (e) {
    debugPrint('Backend sign-in failed: $e');
    return false;
  }
}
