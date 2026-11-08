import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Rounded vertical bars drawn from amplitudes in the range 0..1.
class WaveformPainter extends CustomPainter {
  WaveformPainter({required this.amplitudes, required this.color, this.secondaryColor});

  final List<double> amplitudes;
  final Color color;
  final Color? secondaryColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (amplitudes.isEmpty) return;
    final n = amplitudes.length;
    final slot = size.width / n;
    final barWidth = math.max(2.0, slot * 0.55);
    final mid = size.height / 2;
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < n; i++) {
      final double a = amplitudes[i].clamp(0.04, 1.0).toDouble();
      final h = a * size.height;
      final x = slot * i + slot / 2;
      paint.color = (secondaryColor != null && i.isOdd) ? secondaryColor! : color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, mid), width: barWidth, height: h),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WaveformPainter old) =>
      old.amplitudes != amplitudes || old.color != color || old.secondaryColor != secondaryColor;
}

/// A decorative waveform. When [animate] is true it gently moves; when false
/// it is drawn flat, so the UI never pretends to be listening.
class AnimatedWaveform extends StatefulWidget {
  const AnimatedWaveform({
    super.key,
    this.animate = true,
    this.bars = 36,
    this.height = 56,
    this.color,
    this.secondaryColor,
    this.flatWhenIdle = false,
  });

  final bool animate;
  final int bars;
  final double height;
  final Color? color;
  final Color? secondaryColor;
  final bool flatWhenIdle;

  @override
  State<AnimatedWaveform> createState() => _AnimatedWaveformState();
}

class _AnimatedWaveformState extends State<AnimatedWaveform> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(AnimatedWaveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.animate && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<double> _amplitudes(double t) {
    final n = widget.bars;
    if (!widget.animate && widget.flatWhenIdle) {
      return List<double>.filled(n, 0.06);
    }
    return List<double>.generate(n, (i) {
      final x = i / n;
      final envelope = math.sin(math.pi * x); // taller in the middle
      final wave = 0.55 +
          0.3 * math.sin(2 * math.pi * (x * 2.0 + t)) +
          0.15 * math.sin(2 * math.pi * (x * 5.0 - t * 2));
      return (0.12 + 0.88 * envelope * wave).clamp(0.06, 1.0).toDouble();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: WaveformPainter(
            amplitudes: _amplitudes(_controller.value),
            color: widget.color ?? scheme.primary,
            secondaryColor: widget.secondaryColor,
          ),
        ),
      ),
    );
  }
}
