import 'package:flutter/material.dart';

import 'core/config/app_config.dart';
import 'core/routing/app_routes.dart';
import 'core/state/app_controller.dart';
import 'core/state/app_scope.dart';
import 'core/theme/app_theme.dart';

class TeluguVoiceApp extends StatelessWidget {
  const TeluguVoiceApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => MaterialApp(
          title: '${AppConfig.appName} – ${AppConfig.appSubtitle}',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: controller.themeMode,
          initialRoute: AppRoutes.home,
          onGenerateRoute: AppRoutes.onGenerateRoute,
        ),
      ),
    );
  }
}
