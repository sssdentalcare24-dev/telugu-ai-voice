import 'package:flutter/material.dart';

import '../core/feature_status.dart';
import 'common.dart';

class FeatureCard extends StatelessWidget {
  const FeatureCard({
    super.key,
    required this.icon,
    required this.titleTe,
    required this.titleEn,
    required this.description,
    required this.status,
    required this.onTap,
    this.accent = false,
  });

  final IconData icon;
  final String titleTe;
  final String titleEn;
  final String description;
  final FeatureStatus status;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final iconBg = accent ? scheme.secondary : scheme.primary;
    final iconFg = accent ? scheme.onSecondary : scheme.onPrimary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 188),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(14)),
                      child: Icon(icon, color: iconFg, size: 26),
                    ),
                    const Spacer(),
                    Icon(Icons.arrow_forward_rounded, color: scheme.outline, size: 20),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  titleTe,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, height: 1.35),
                ),
                Text(titleEn, style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
                const SizedBox(height: 8),
                Text(description, style: theme.textTheme.bodySmall, maxLines: 3, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 12),
                StatusPill(status: status, dense: true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
