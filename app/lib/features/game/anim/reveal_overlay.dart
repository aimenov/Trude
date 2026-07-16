/// The check-reveal set piece: table dims under a vignette, the last throw's
/// cards slide apart center-stage enlarged, the chosen card lifts, pauses,
/// flips with a slow-peel (crawl through 60 degrees, snap through the rest),
/// and a verdict stamps down — cold blue TRUTH or red LIAR! — before the
/// queue flows into the pickup step.
library;

import 'dart:math';

import 'package:flutter/material.dart' hide Card;

import '../../../core/audio/sfx_service.dart';
import '../../../core/haptics/haptics_service.dart';
import '../../../core/net/protocol_models.dart';
import '../../../core/strings.dart';
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
            // ~30 % vignette dim over the whole table.
            IgnorePointer(
              child: Opacity(
                opacity: dim * MotionSpec.revealDimOpacity,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      radius: 1.2,
                      colors: [Colors.black54, Colors.black],
                    ),
                  ),
                ),
              ),
            ),
            Center(child: _cardRow(spread, lift, flip)),
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

    return SizedBox(
      height: cardWidth * kCardAspect * MotionSpec.revealCardScale + 60,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
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

  Widget _verdictStamp(double verdict) {
    final matched = widget.event.matched;
    final color = matched ? const Color(0xFF1565C0) : const Color(0xFFC62828);
    final scale =
        2.2 - 1.2 * MotionSpec.verdictStampCurve.transform(verdict);

    return Transform.translate(
      offset: const Offset(0, -110),
      child: Transform.rotate(
        angle: -6 * pi / 180,
        child: Transform.scale(
          scale: scale,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: color, width: 3),
              borderRadius: BorderRadius.circular(8),
              color: color.withValues(alpha: 0.12),
            ),
            child: Text(
              matched ? Strings.verdictTruth : Strings.verdictLiar,
              style: TextStyle(
                color: color,
                fontSize: 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
