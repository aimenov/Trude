/// The check-reveal set piece: the parlor falls into a deep midnight dim, the
/// last throw's cards slide apart center-stage enlarged under a candle-spot,
/// the chosen card lifts, pauses, flips with a slow-peel (crawl through 60
/// degrees, snap through the rest), and a verdict stamps down as an inked
/// rubber stamp — green TRUTH or red LIAR with an ink-splat flash — before the
/// queue flows into the pickup step. All beats keep their MotionSpec fractions.
library;

import 'dart:math';

import 'package:flutter/material.dart' hide Card;

import '../../../core/audio/sfx_service.dart';
import '../../../core/haptics/haptics_service.dart';
import '../../../core/net/protocol_models.dart';
import '../../../core/strings.dart';
import '../../../core/theme/trude_theme.dart';
import '../widgets/card_widgets.dart';
import 'motion_spec.dart';

class RevealOverlay extends StatefulWidget {
  const RevealOverlay({
    super.key,
    required this.event,
    required this.cardCount,
    required this.duration,
    required this.sfx,
    required this.haptics,
    this.onVerdict,
    this.onDone,
  });

  final CheckResultEvent event;

  /// Cards in the throw being checked (>= flipIndex + 1).
  final int cardCount;

  /// Speed-scaled total duration — matches the queue's reveal step.
  final Duration duration;
  final SfxService sfx;
  final HapticsService haptics;

  /// Fired at the verdict beat (the liar's avatar shakes off this).
  final VoidCallback? onVerdict;
  final VoidCallback? onDone;

  @override
  State<RevealOverlay> createState() => _RevealOverlayState();
}

class _RevealOverlayState extends State<RevealOverlay>
    with SingleTickerProviderStateMixin {
  static const _peel = SlowPeelCurve();

  late final AnimationController _controller;

  // sfx/haptics beats, fired once as the timeline crosses each fraction.
  late final List<({double at, VoidCallback fire})> _beats;
  int _nextBeat = 0;

  @override
  void initState() {
    super.initState();
    final flipSnapAt = MotionSpec.revealFlipStart +
        MotionSpec.peelBreakTime *
            (MotionSpec.revealFlipEnd - MotionSpec.revealFlipStart);
    _beats = [
      (at: 0.0, fire: widget.sfx.revealTension),
      (at: MotionSpec.revealDimFraction, fire: widget.sfx.cardSlide),
      (at: MotionSpec.revealLiftEnd, fire: widget.haptics.heartbeat),
      (at: flipSnapAt, fire: widget.sfx.flipSnap),
      (
        at: MotionSpec.revealVerdictIn,
        fire: () {
          if (widget.event.matched) {
            widget.sfx.verdictTruth();
          } else {
            widget.sfx.verdictLie();
          }
          widget.haptics.heavy();
          widget.onVerdict?.call();
        }
      ),
    ];

    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..addListener(_fireBeats)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone?.call();
      })
      ..forward();
  }

  void _fireBeats() {
    while (_nextBeat < _beats.length &&
        _controller.value >= _beats[_nextBeat].at) {
      _beats[_nextBeat].fire();
      _nextBeat++;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Progress of the sub-phase [from]..[to] at timeline position [t].
  double _phase(double t, double from, double to) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final dim = _phase(t, 0, MotionSpec.revealDimFraction);
        final spread = MotionSpec.revealSpreadCurve.transform(
            _phase(t, MotionSpec.revealDimFraction, MotionSpec.revealSpreadEnd));
        final lift =
            _phase(t, MotionSpec.revealSpreadEnd, MotionSpec.revealLiftEnd);
        final flip = _peel.transform(
            _phase(t, MotionSpec.revealFlipStart, MotionSpec.revealFlipEnd));
        final verdict = _phase(t, MotionSpec.revealVerdictIn, 1.0);

        return Stack(
          fit: StackFit.expand,
          children: [
            // Deep midnight dim: the parlor recedes, the check takes the stage.
            IgnorePointer(
              child: Opacity(
                opacity: dim * TableMotionSpec.revealDimDeep,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 1.2,
                      colors: [
                        TrudeColors.midnight.withValues(alpha: 0.82),
                        TrudeColors.midnight,
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Center(child: _cardRow(spread, lift, flip)),
            if (verdict > 0 && !widget.event.matched)
              Center(child: _inkSplat(verdict)),
            if (verdict > 0) Center(child: _verdictStamp(verdict)),
          ],
        );
      },
    );
  }

  Widget _cardRow(double spread, double lift, double flip) {
    const cardWidth = 52.0;
    final n = max(widget.cardCount, widget.event.flipIndex + 1);
    final scale = 1 + (MotionSpec.revealCardScale - 1) * spread;
    final spacing = cardWidth * 1.35 * scale;
    final flipX =
        (widget.event.flipIndex - (n - 1) / 2) * spacing * spread;
    final spotAlpha =
        TableMotionSpec.revealSpotMaxAlpha * (0.35 * spread + 0.65 * lift);
    final spotSize = cardWidth * scale * 3.2;

    return SizedBox(
      height: cardWidth * kCardAspect * MotionSpec.revealCardScale + 60,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Candle-spot pooling on the card under scrutiny.
          Transform.translate(
            offset: Offset(flipX, MotionSpec.revealLiftDy * lift * 0.5),
            child: IgnorePointer(
              child: Container(
                width: spotSize,
                height: spotSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      TrudeColors.brassBright.withValues(alpha: spotAlpha),
                      TrudeColors.brassBright.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          for (var i = 0; i < n; i++)
            Transform.translate(
              // Cards start clustered and slide apart into an enlarged row.
              offset: Offset(
                (i - (n - 1) / 2) * spacing * spread,
                i == widget.event.flipIndex
                    ? MotionSpec.revealLiftDy * lift
                    : 0,
              ),
              child: Transform.scale(
                scale: scale,
                child: i == widget.event.flipIndex
                    ? _flippingCard(cardWidth, flip)
                    : const TrudeCardBack(width: cardWidth),
              ),
            ),
        ],
      ),
    );
  }

  Widget _flippingCard(double width, double flip) {
    final angle = pi * flip;
    final showFace = flip >= 0.5;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0015) // slight perspective for the Y flip
        ..rotateY(angle),
      child: showFace
          // Counter-rotate so the face isn't mirrored after passing 90 deg.
          ? Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..rotateY(pi),
              child: TrudeCardFace(
                rank: widget.event.flipped.rank,
                suit: widget.event.flipped.suit,
                width: width,
              ),
            )
          : TrudeCardBack(width: width),
    );
  }

  /// The verdict as an inked rubber stamp: double-ring border with distressed
  /// edges, serif stamp lettering, slammed in with the elastic stamp curve.
  Widget _verdictStamp(double verdict) {
    final matched = widget.event.matched;
    final color = matched ? TrudeColors.truth : TrudeColors.lie;
    final scale =
        2.2 - 1.2 * MotionSpec.verdictStampCurve.transform(verdict);

    return Transform.translate(
      offset: const Offset(0, -110),
      child: Transform.rotate(
        angle: (matched ? -5 : -8) * pi / 180,
        child: Transform.scale(
          scale: scale,
          child: CustomPaint(
            painter: _StampFramePainter(
              color: color,
              seed: matched ? 11 : 47,
            ),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
              child: Text(
                matched ? Strings.verdictTruth : Strings.verdictLiar,
                style: TrudeType.stamp.copyWith(
                  color: color.withValues(alpha: 0.92),
                  fontSize: 28,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Red ink thrown against the felt behind the LIAR stamp: flashes in over
  /// the first part of the verdict phase, then dries down.
  Widget _inkSplat(double verdict) {
    final inT = (verdict / TableMotionSpec.inkSplatIn).clamp(0.0, 1.0);
    final growth = Curves.easeOutCubic.transform(inT);
    final settle = verdict <= TableMotionSpec.inkSplatIn
        ? 1.0
        : 1 -
            0.65 *
                (verdict - TableMotionSpec.inkSplatIn) /
                (1 - TableMotionSpec.inkSplatIn);

    return Transform.translate(
      offset: const Offset(0, -110),
      child: IgnorePointer(
        child: CustomPaint(
          size: const Size(280, 190),
          painter: _InkSplatPainter(growth: growth, intensity: settle),
        ),
      ),
    );
  }
}

/// Double-ring rubber-stamp frame with a distressed (broken-ink) edge and a
/// few stray ink speckles. Deterministic per [seed].
class _StampFramePainter extends CustomPainter {
  _StampFramePainter({required this.color, required this.seed});

  final Color color;
  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = (Offset.zero & size).inflate(12);
    final rng = Random(seed);
    canvas.saveLayer(bounds, Paint());

    final outer = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(2), const Radius.circular(9));
    final inner = outer.deflate(5.5);

    final thick = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..color = color;
    final thin = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..color = color.withValues(alpha: 0.9);
    canvas.drawRRect(outer, thick);
    canvas.drawRRect(inner, thin);

    // Stray ink speckles just outside the frame.
    final speckle = Paint()..color = color.withValues(alpha: 0.5);
    for (var i = 0; i < 9; i++) {
      final angle = rng.nextDouble() * 2 * pi;
      final pos = outer.center +
          Offset(cos(angle) * (size.width / 2 + rng.nextDouble() * 8),
              sin(angle) * (size.height / 2 + rng.nextDouble() * 6));
      canvas.drawCircle(pos, 0.5 + rng.nextDouble() * 1.1, speckle);
    }

    // Distress: punch worn gaps out of the inked border.
    final punch = Paint()..blendMode = BlendMode.clear;
    final borderPath = Path()..addRRect(outer);
    for (final metric in borderPath.computeMetrics()) {
      final holes = (metric.length / 11).floor();
      for (var i = 0; i < holes; i++) {
        if (rng.nextDouble() < 0.45) continue;
        final tangent =
            metric.getTangentForOffset(rng.nextDouble() * metric.length);
        if (tangent == null) continue;
        final jitter = Offset(
            (rng.nextDouble() - 0.5) * 3, (rng.nextDouble() - 0.5) * 3);
        canvas.drawCircle(
            tangent.position + jitter, 0.5 + rng.nextDouble() * 1.5, punch);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(_StampFramePainter old) =>
      old.color != color || old.seed != seed;
}

/// A seeded ink splat: an irregular central blob with satellite droplets
/// thrown outward, scaled by [growth] and fading with [intensity].
class _InkSplatPainter extends CustomPainter {
  _InkSplatPainter({required this.growth, required this.intensity});

  final double growth;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (growth <= 0) return;
    final rng = Random(1913);
    final center = size.center(Offset.zero);
    final ink = Paint()
      ..color = TrudeColors.lie.withValues(alpha: 0.40 * intensity);

    // Irregular core: overlapping circles around the center.
    canvas.drawCircle(center, 30 * growth, ink);
    for (var i = 0; i < 8; i++) {
      final angle = rng.nextDouble() * 2 * pi;
      final dist = (8 + rng.nextDouble() * 20) * growth;
      canvas.drawCircle(
          center + Offset(cos(angle), sin(angle)) * dist,
          (7 + rng.nextDouble() * 12) * growth,
          ink);
    }

    // Satellite droplets flung further out, with little tails.
    final droplet = Paint()
      ..color = TrudeColors.lie.withValues(alpha: 0.5 * intensity);
    for (var i = 0; i < 14; i++) {
      final angle = rng.nextDouble() * 2 * pi;
      final dist = (46 + rng.nextDouble() * 78) * growth;
      final pos = center + Offset(cos(angle), sin(angle)) * dist;
      final r = 1.4 + rng.nextDouble() * 3.6;
      canvas.drawCircle(pos, r, droplet);
      // Tail pointing back toward the center — reads as thrown ink.
      canvas.drawLine(
          pos,
          pos - Offset(cos(angle), sin(angle)) * r * 3,
          Paint()
            ..strokeWidth = r * 0.8
            ..strokeCap = StrokeCap.round
            ..color = TrudeColors.lie.withValues(alpha: 0.35 * intensity));
    }
  }

  @override
  bool shouldRepaint(_InkSplatPainter old) =>
      old.growth != growth || old.intensity != intensity;
}
