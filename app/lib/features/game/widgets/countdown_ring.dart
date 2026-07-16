/// Depleting countdown ring: full at turn start, empty at the deadline,
/// turning amber then red inside the urgent window.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../anim/motion_spec.dart';

/// Ring color for [remaining] time out of [total].
Color countdownColor(Duration remaining, ColorScheme scheme) {
  if (remaining > MotionSpec.urgentThreshold) return scheme.primary;
  final u = 1 -
      remaining.inMilliseconds / MotionSpec.urgentThreshold.inMilliseconds;
  // amber -> red across the urgent window.
  return Color.lerp(const Color(0xFFFFB300), const Color(0xFFD32F2F), u)!;
}

class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.remaining,
    required this.total,
    this.size = 26,
    this.strokeWidth = 3,
  });

  final Duration remaining;
  final Duration total;
  final double size;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = total.inMilliseconds <= 0
        ? 0.0
        : (remaining.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: CountdownRingPainter(
          fraction: fraction,
          color: countdownColor(remaining, scheme),
          trackColor: scheme.outlineVariant.withValues(alpha: 0.4),
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class CountdownRingPainter extends CustomPainter {
  CountdownRingPainter({
    required this.fraction,
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final double fraction;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(strokeWidth / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawArc(r, 0, 2 * pi, false, track);

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(r, -pi / 2, 2 * pi * fraction, false, arc);
  }

  @override
  bool shouldRepaint(CountdownRingPainter old) =>
      old.fraction != fraction || old.color != color;
}
