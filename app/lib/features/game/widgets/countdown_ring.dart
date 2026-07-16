/// Depleting countdown ring: full at turn start, empty at the deadline. Brass
/// while there is time, ramping from bright brass to [TrudeColors.lie] across
/// the urgent window. A glowing brass comet head rides the arc tip; inside the
/// urgent window the arc gains a soft under-glow and a gentle stroke pulse
/// (suppressed when animations are off).
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/theme/trude_theme.dart';
import '../anim/motion_spec.dart';

/// Ring color for [remaining] time out of the turn total. Brass outside the
/// urgent window, then a brassBright -> lie ramp as the deadline closes in.
Color countdownColor(Duration remaining, ColorScheme scheme) {
  if (remaining > MotionSpec.urgentThreshold) return scheme.primary;
  final u = 1 -
      remaining.inMilliseconds / MotionSpec.urgentThreshold.inMilliseconds;
  return Color.lerp(TrudeColors.brassBright, TrudeColors.lie, u)!;
}

class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.remaining,
    required this.total,
    this.size = 34,
    this.strokeWidth = 4.5,
    this.animate = true,
  });

  final Duration remaining;
  final Duration total;
  final double size;
  final double strokeWidth;

  /// Whether the urgent-window stroke pulse may run. Callers pass false when
  /// animations are reduced/off; the ring stays fully legible without it.
  final bool animate;

  /// Gentle "heartbeat" of the stroke inside the urgent window: amplitude as
  /// a fraction of the stroke width, at [_pulsePeriod] (~1 Hz). Sampled from
  /// wall-clock time on each repaint — the ring already repaints every
  /// countdown tick, so no ticker of its own is needed.
  static const _pulseStrokeDelta = 0.15;
  static const _pulsePeriod = Duration(seconds: 1);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fraction = total.inMilliseconds <= 0
        ? 0.0
        : (remaining.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
    final urgent =
        remaining > Duration.zero && remaining < MotionSpec.urgentThreshold;
    var stroke = strokeWidth;
    if (urgent && animate) {
      final t = DateTime.now().millisecondsSinceEpoch /
          _pulsePeriod.inMilliseconds;
      stroke = strokeWidth * (1 + _pulseStrokeDelta * sin(t * 2 * pi));
    }
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: CountdownRingPainter(
          fraction: fraction,
          color: countdownColor(remaining, scheme),
          trackColor: TrudeColors.brassBright.withValues(alpha: 0.14),
          strokeWidth: stroke,
          glow: urgent,
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
    this.glow = false,
  });

  final double fraction;
  final Color color;
  final Color trackColor;
  final double strokeWidth;

  /// Soft under-glow beneath the arc (the urgent-window treatment).
  final bool glow;

  /// Comet head at the arc tip: halo radius as a multiple of the stroke
  /// width, crisp core radius likewise, and the halo's blur/alpha.
  static const _cometHaloFactor = 1.6;
  static const _cometCoreFactor = 0.8;
  static const _cometHaloAlpha = 0.55;
  static const _underGlowWidthFactor = 2.2;
  static const _underGlowAlpha = 0.35;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(strokeWidth / 2);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = trackColor;
    canvas.drawArc(r, 0, 2 * pi, false, track);

    final sweep = 2 * pi * fraction;
    if (glow && fraction > 0) {
      final under = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * _underGlowWidthFactor
        ..strokeCap = StrokeCap.round
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeWidth)
        ..color = color.withValues(alpha: _underGlowAlpha);
      canvas.drawArc(r, -pi / 2, sweep, false, under);
    }

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(r, -pi / 2, sweep, false, arc);

    if (fraction > 0) {
      // Glowing brass comet head riding the tip of the arc.
      final tipAngle = -pi / 2 + sweep;
      final tip = r.center +
          Offset(cos(tipAngle), sin(tipAngle)) * (r.shortestSide / 2);
      final halo = Paint()
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, strokeWidth * 0.9)
        ..color = color.withValues(alpha: _cometHaloAlpha);
      canvas.drawCircle(tip, strokeWidth * _cometHaloFactor, halo);
      final core = Paint()..color = TrudeColors.brassBright;
      canvas.drawCircle(tip, strokeWidth * _cometCoreFactor, core);
    }
  }

  @override
  bool shouldRepaint(CountdownRingPainter old) =>
      old.fraction != fraction ||
      old.color != color ||
      old.strokeWidth != strokeWidth ||
      old.glow != glow;
}
