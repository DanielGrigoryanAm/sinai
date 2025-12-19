import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:sinai/auth/bloc/auth_bloc.dart';
import 'package:sinai/auth/repository/auth_repository.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/text_theme.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

final appRouter = AppRouter();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  if (FirebaseAuth.instance.currentUser == null) {
    await FirebaseAuth.instance.signInAnonymously();
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => AuthBloc(authRepository: AuthRepository()),
        ),
      ],
      child: MaterialApp.router(
        darkTheme: ThemeData.dark(),
        themeMode: ThemeMode.system,
        routerConfig: appRouter.config(),
        theme: ThemeData(
          extensions: <ThemeExtension<dynamic>>[
            AppTypography.defaultTypography(),
          ],
        ),
      ),
    );
  }
}
