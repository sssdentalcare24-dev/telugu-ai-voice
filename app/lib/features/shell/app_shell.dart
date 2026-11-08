import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_colors.dart';
import '../cloning/cloning_screen.dart';
import '../history/history_screen.dart';
import '../home/home_screen.dart';
import '../settings/settings_screen.dart';

enum ShellTab { home, cloning, history, settings }

/// Top-level layout: bottom navigation on phones, a side rail on wide screens.
class AppShell extends StatefulWidget {
  const AppShell({super.key, this.initialTab = ShellTab.home});

  final ShellTab initialTab;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late ShellTab _tab = widget.initialTab;

  static const _destinations = [
    (ShellTab.home, Icons.home_outlined, Icons.home_rounded, 'హోమ్', 'Home'),
    (ShellTab.cloning, Icons.record_voice_over_outlined, Icons.record_voice_over_rounded, 'క్లోనింగ్', 'AI Voice Cloning'),
    (ShellTab.history, Icons.library_music_outlined, Icons.library_music_rounded, 'చరిత్ర', 'History'),
    (ShellTab.settings, Icons.settings_outlined, Icons.settings_rounded, 'సెట్టింగ్స్', 'Settings'),
  ];

  Widget _page() => switch (_tab) {
        ShellTab.home => HomeScreen(
            onOpenHistory: () => setState(() => _tab = ShellTab.history),
            onOpenCloning: () => setState(() => _tab = ShellTab.cloning),
          ),
        ShellTab.cloning => const CloningScreen(),
        ShellTab.history => const HistoryScreen(),
        ShellTab.settings => const SettingsScreen(),
      };

  void _select(int index) => setState(() => _tab = _destinations[index].$1);

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final index = _destinations.indexWhere((d) => d.$1 == _tab);
    final app = AppScope.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final appBar = AppBar(
      titleSpacing: wide ? 24 : 16,
      title: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(gradient: AppColors.heroGradient, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.graphic_eq_rounded, color: AppColors.gold, size: 20),
          ),
          const SizedBox(width: 10),
          const Flexible(
            child: Text(AppConfig.appName, style: TextStyle(fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: isDark ? 'Light mode' : 'Dark mode',
          onPressed: () => app.setThemeMode(isDark ? ThemeMode.light : ThemeMode.dark),
          icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
        ),
        const SizedBox(width: 4),
      ],
    );

    if (wide) {
      return Scaffold(
        appBar: appBar,
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: index,
              onDestinationSelected: _select,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(icon: Icon(d.$2), selectedIcon: Icon(d.$3), label: Text('${d.$4}\n${d.$5}', textAlign: TextAlign.center)),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: _page()),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: appBar,
      body: _page(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: _select,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(icon: Icon(d.$2), selectedIcon: Icon(d.$3), label: d.$4, tooltip: d.$5),
        ],
      ),
    );
  }
}
