import 'package:flutter/material.dart';
import 'package:sinay/router/app_router.dart';
import 'package:sinay/theme/text_theme.dart';

final appRouter = AppRouter();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      theme: ThemeData(
        extensions: <ThemeExtension<dynamic>>[
          AppTypography.defaultTypography(),
          
        ],
      ),
      darkTheme: ThemeData.dark(),
      themeMode: ThemeMode.system,
      routerConfig: appRouter.config(),
    );
  }
}
