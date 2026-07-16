/// Card visuals: face-down backs (with the idle gloss shimmer) and faces.
/// The art itself is painter-drawn ("Midnight Parlor" deck, see
/// card_painters.dart): engraved pips, court medallions, the joker, and a
/// brass guilloche back — no image assets, crisp at any width.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/strings.dart';
import '../../../core/theme/trude_theme.dart';
import '../anim/motion_jitter.dart';
import '../anim/motion_spec.dart';
import 'card_painters.dart';

const kCardAspect = 68 / 48; // height / width of every card widget

class TrudeCardBack extends StatelessWidget {
  const TrudeCardBack({super.key, this.width = 48, this.shimmer = false});

  final double width;

  /// Idle gloss sweep; only enabled where a shared ticker is cheap to run.
  final bool shimmer;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(width * TrudeDims.cardRadiusFactor);
    final card = Container(
      width: width,
      height: width * kCardAspect,
      decoration: BoxDecoration(
        color: TrudeColors.ivory,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 3,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: const CustomPaint(
          painter: CardBackPainter(),
          isComplex: true,
          willChange: false,
        ),
      ),
    );
    if (!shimmer) return card;
    return _Shimmer(width: width, child: card);
  }
}

/// Sweeping gloss highlight across a card back, randomized phase per card so
/// the pile glitters rather than blinks.
class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.width, required this.child});

  final double width;
  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: MotionSpec.shimmerPeriod,
    value: motionJitter.range(0, 1),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final t = _controller.value;
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: 0.18),
              Colors.transparent,
            ],
            stops: const [0.35, 0.5, 0.65],
            transform: _SlideGradient(t),
          ).createShader(bounds),
          child: child,
        );
      },
    );
  }
}

class _SlideGradient extends GradientTransform {
  const _SlideGradient(this.t);

  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      // Sweep from off-left to off-right over one period.
      Matrix4.translationValues(bounds.width * (t * 3 - 1.5), 0, 0);
}

class TrudeCardFace extends StatelessWidget {
  const TrudeCardFace({
    super.key,
    required this.rank,
    this.suit,
    this.width = 48,
    this.selected = false,
    this.golden = false,
  });

  final String rank;
  final String? suit;
  final double width;

  /// Brass outer glow + a slightly stronger lift shadow (geometry unchanged).
  final bool selected;

  /// Four-of-a-kind celebration styling.
  final bool golden;

  bool get _isJoker => rank == 'JOKER';

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(width * TrudeDims.cardRadiusFactor);
    return Container(
      width: width,
      height: width * kCardAspect,
      decoration: BoxDecoration(
        color: TrudeColors.ivory,
        borderRadius: radius,
        boxShadow: [
          if (selected)
            BoxShadow(
              color: TrudeColors.brass.withValues(alpha: 0.55),
              blurRadius: width * 0.30,
              spreadRadius: 1,
            ),
          BoxShadow(
            color: Colors.black.withValues(alpha: selected ? 0.32 : 0.18),
            blurRadius: selected ? 6 : 3,
            offset: Offset(0, selected ? 2.5 : 1.5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: CustomPaint(
          painter: CardFacePainter(
            rank: rank,
            suit: suit,
            indexLabel: _isJoker ? '' : Strings.rankShort(rank),
            jokerWord: _isJoker ? Strings.rankWord(rank) : '',
            golden: golden,
          ),
          isComplex: true,
          willChange: false,
        ),
      ),
    );
  }
}

/// The resting pose of pile card [index]: a deterministic messy offset and
/// tilt so the stack looks thrown, is stable across rebuilds, and flights can
/// land exactly where the stack will draw the card.
({Offset offset, double angle}) pileEntryPose(int index) {
  final rng = Random(index * 7919 + 31);
  double signed() => rng.nextDouble() * 2 - 1;
  return (
    offset: Offset(signed() * 10, signed() * 10),
    angle: signed() * 14 * pi / 180,
  );
}
