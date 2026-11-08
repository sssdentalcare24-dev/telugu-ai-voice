import 'package:flutter/material.dart';

import '../../features/convert/convert_screen.dart';
import '../../features/live/live_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/tts/tts_screen.dart';

/// Named routes. On the web these appear in the address bar
/// (e.g. /#/tts), so every screen can be bookmarked.
abstract final class AppRoutes {
  static const String home = '/';
  static const String history = '/history';
  static const String settings = '/settings';
  static const String tts = '/tts';
  static const String maleToFemale = '/convert/male-to-female';
  static const String femaleToMale = '/convert/female-to-male';
  static const String live = '/live';
  static const String cloning = '/cloning';

  static Route<dynamic> onGenerateRoute(RouteSettings routeSettings) {
    final Widget page = switch (routeSettings.name) {
      AppRoutes.tts => const TtsScreen(),
      AppRoutes.maleToFemale => const ConvertScreen(direction: ConversionDirection.maleToFemale),
      AppRoutes.femaleToMale => const ConvertScreen(direction: ConversionDirection.femaleToMale),
      AppRoutes.live => const LiveScreen(),
      AppRoutes.history => const AppShell(initialTab: ShellTab.history),
      AppRoutes.settings => const AppShell(initialTab: ShellTab.settings),
      AppRoutes.cloning => const AppShell(initialTab: ShellTab.cloning),
      _ => const AppShell(initialTab: ShellTab.home),
    };
    return MaterialPageRoute<void>(builder: (_) => page, settings: routeSettings);
  }
}
