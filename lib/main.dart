import 'package:flutter/material.dart';
import 'package:sinai/router/app_router.dart';
import 'package:sinai/theme/text_theme.dart';

final appRouter = AppRouter();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter.config(),
      theme: ThemeData(
        extensions: <ThemeExtension<dynamic>>[
          AppTypography.defaultTypography(),
        ],
      ),
    );
  }
}
