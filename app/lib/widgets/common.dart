import 'package:flutter/material.dart';

import '../core/feature_status.dart';
import '../core/state/app_controller.dart';
import '../core/state/app_scope.dart';
import '../core/theme/app_colors.dart';

/// Centers content and caps its width so screens look right on phones,
/// tablets and desktop browsers.
class ResponsiveBody extends StatelessWidget {
  const ResponsiveBody({super.key, required this.child, this.maxWidth = 920, this.padding});

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 600;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: padding ?? EdgeInsets.symmetric(horizontal: wide ? 24 : 16),
          child: child,
        ),
      ),
    );
  }
}

/// Rounded white card with an optional title row.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.title, this.icon, this.trailing, this.padding});

  final Widget child;
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Row(
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(title!, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 14),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// Small coloured pill showing a feature's availability.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status, this.dense = false});

  final FeatureStatus status;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = status.color(Theme.of(context).colorScheme);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 10, vertical: dense ? 3 : 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(status.icon, size: dense ? 13 : 15, color: color),
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(fontSize: dense ? 11 : 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}

/// Explains why a feature is not usable yet. Hidden when the feature is ready.
class FeatureStatusBanner extends StatelessWidget {
  const FeatureStatusBanner({super.key, required this.feature});

  final Feature feature;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final status = FeatureStatus.of(app, feature);
    if (status.ready) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final color = status.color(scheme);
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(status.icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status.label, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
                const SizedBox(height: 2),
                Text(status.message, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          if (app.connection != ServerConnection.checking)
            IconButton(
              tooltip: 'Check again',
              onPressed: () => AppScope.read(context).refreshServer(),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
    );
  }
}

/// Marks a control that arrives in a later build stage (shown disabled).
class StageTag extends StatelessWidget {
  const StageTag(this.stage, {super.key});

  final int stage;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Arrives in Stage $stage of the build',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.goldSoft,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          'Stage $stage',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.onGold),
        ),
      ),
    );
  }
}

/// Bilingual screen heading: Telugu title with an English subtitle.
class ScreenHeading extends StatelessWidget {
  const ScreenHeading({super.key, required this.telugu, required this.english, this.trailing});

  final String telugu;
  final String english;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(telugu, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(english, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

String formatDuration(double seconds) {
  final total = seconds.round();
  final m = total ~/ 60;
  final s = total % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.hideCurrentSnackBar();
  messenger?.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: error ? AppColors.danger : null,
    ),
  );
}
