import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Microphone illustration with softly pulsing gold rings.
class MicHero extends StatefulWidget {
  const MicHero({super.key, this.size = 120});

  final double size;

  @override
  State<MicHero> createState() => _MicHeroState();
}

class _MicHeroState extends State<MicHero> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          final t = _pulse.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              for (final offset in const [0.0, 0.5])
                _Ring(progress: (t + offset) % 1.0, size: s),
              child!,
            ],
          );
        },
        child: Container(
          width: s * 0.58,
          height: s * 0.58,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFF1D77A), AppColors.gold, Color(0xFFA9861F)],
            ),
            boxShadow: [
              BoxShadow(color: AppColors.gold.withValues(alpha: 0.45), blurRadius: 24, spreadRadius: 2),
            ],
          ),
          child: Icon(Icons.mic_rounded, size: s * 0.32, color: AppColors.navyDeep),
        ),
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.progress, required this.size});

  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final d = size * (0.58 + 0.42 * progress);
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.gold.withValues(alpha: (1 - progress) * 0.7), width: 2),
      ),
    );
  }
}
