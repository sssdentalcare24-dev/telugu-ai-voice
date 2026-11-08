import 'package:flutter/material.dart';

import '../../core/config/app_config.dart';
import '../../core/feature_status.dart';
import '../../core/routing/app_routes.dart';
import '../../core/state/app_controller.dart';
import '../../core/state/app_scope.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/common.dart';
import '../../widgets/feature_card.dart';
import '../../widgets/mic_hero.dart';
import '../../widgets/waveform.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, this.onOpenHistory});

  /// Lets the shell switch to its History tab instead of pushing a new page.
  final VoidCallback? onOpenHistory;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final cards = <Widget>[
      FeatureCard(
        icon: Icons.text_fields_rounded,
        titleTe: 'తెలుగు టెక్స్ట్ → వాయిస్',
        titleEn: 'Telugu Text to Voice',
        description: 'Type Telugu and hear it in a natural female or male voice. Save and share it.',
        status: FeatureStatus.of(app, Feature.tts),
        onTap: () => Navigator.pushNamed(context, AppRoutes.tts),
      ),
      FeatureCard(
        icon: Icons.woman_rounded,
        titleTe: 'పురుష → స్త్రీ స్వరం',
        titleEn: 'Male to Female Voice',
        description: 'Record or upload male speech and convert it to a female voice.',
        status: FeatureStatus.of(app, Feature.maleToFemale),
        onTap: () => Navigator.pushNamed(context, AppRoutes.maleToFemale),
      ),
      FeatureCard(
        icon: Icons.man_rounded,
        titleTe: 'స్త్రీ → పురుష స్వరం',
        titleEn: 'Female to Male Voice',
        description: 'Record or upload female speech and convert it to a male voice.',
        status: FeatureStatus.of(app, Feature.femaleToMale),
        onTap: () => Navigator.pushNamed(context, AppRoutes.femaleToMale),
      ),
      FeatureCard(
        icon: Icons.settings_voice_rounded,
        titleTe: 'లైవ్ వాయిస్ ఛేంజర్',
        titleEn: 'Live Voice Changer',
        description: 'Real-time two-way voice conversion with headphone monitoring.',
        status: FeatureStatus.of(app, Feature.live),
        onTap: () => Navigator.pushNamed(context, AppRoutes.live),
        accent: true,
      ),
    ];

    return RefreshIndicator(
      onRefresh: () => AppScope.read(context).refreshServer(),
      child: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          ResponsiveBody(
            maxWidth: 1100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Hero(connection: app.connection),
                const SizedBox(height: 24),
                Text(
                  'ఏం చేద్దాం?',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  'What would you like to do?',
                  style: TextStyle(color: Theme.of(context).colorScheme.outline),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    const spacing = 12.0;
                    final w = constraints.maxWidth;
                    final cols = w >= 960 ? 4 : (w >= 340 ? 2 : 1);
                    final itemWidth = (w - spacing * (cols - 1)) / cols;
                    return Wrap(
                      spacing: spacing,
                      runSpacing: spacing,
                      children: [for (final c in cards) SizedBox(width: itemWidth, child: c)],
                    );
                  },
                ),
                const SizedBox(height: 20),
                _HistoryShortcut(
                  onTap: onOpenHistory ??
                      () {
                        Navigator.pushNamed(context, AppRoutes.history);
                      },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.connection});

  final ServerConnection connection;

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 420;
    final (IconData icon, String label, Color color) = switch (connection) {
      ServerConnection.checking => (Icons.sync_rounded, 'Connecting…', Colors.white70),
      ServerConnection.online => (Icons.cloud_done_rounded, 'Server online', const Color(0xFF7BE0AE)),
      ServerConnection.offline => (Icons.auto_awesome_rounded, 'Free online AI voices', const Color(0xFF7BE0AE)),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(color: AppColors.navy.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 10)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              MicHero(size: narrow ? 92 : 116),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppConfig.appName,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: narrow ? 24 : 30,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    const Text(
                      AppConfig.appSubtitle,
                      style: TextStyle(color: AppColors.gold, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 16, color: color),
                        const SizedBox(width: 6),
                        Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          AnimatedWaveform(
            height: 44,
            bars: narrow ? 32 : 56,
            color: AppColors.gold,
            secondaryColor: Colors.white.withValues(alpha: 0.75),
          ),
          const SizedBox(height: 10),
          Text(
            'సహజమైన తెలుగు స్వరాలు · Natural Telugu voices',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _HistoryShortcut extends StatelessWidget {
  const _HistoryShortcut({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.1),
          child: Icon(Icons.library_music_rounded, color: scheme.primary),
        ),
        title: const Text('ఆడియో చరిత్ర · Audio history', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: const Text('Voices and conversions saved on this phone'),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
