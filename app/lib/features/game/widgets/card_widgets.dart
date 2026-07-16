/// Card visuals: face-down backs (with the idle gloss shimmer) and faces.
/// Pure widgets — real card art is a later asset milestone; these render a
/// patterned back and rank/suit typography that the art can drop into.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/strings.dart';
import '../anim/motion_jitter.dart';
import '../anim/motion_spec.dart';

const kCardAspect = 68 / 48; // height / width of every card widget

class TrudeCardBack extends StatelessWidget {
  const TrudeCardBack({super.key, this.width = 48, this.shimmer = false});

  final double width;

  /// Idle gloss sweep; only enabled where a shared ticker is cheap to run.
  final bool shimmer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = Container(
      width: width,
      height: width * kCardAspect,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.primaryContainer],
        ),
        borderRadius: BorderRadius.circular(width * 0.13),
        border: Border.all(color: scheme.onPrimary.withValues(alpha: 0.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 3,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Center(
        child: Icon(Icons.filter_vintage,
            size: width * 0.45,
            color: scheme.onPrimary.withValues(alpha: 0.6)),
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
  final bool selected;

  /// Four-of-a-kind celebration styling.
  final bool golden;

  bool get _isJoker => rank == 'JOKER';
  bool get _isRed => suit == 'H' || suit == 'D';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = _isJoker
        ? Colors.deepPurple
        : (_isRed ? const Color(0xFFC62828) : const Color(0xFF263238));
    final label = _isJoker ? Strings.jokerShort : Strings.rankShort(rank);
    final suitSymbol = Strings.suitSymbols[suit] ?? '';
    return Container(
      width: width,
      height: width * kCardAspect,
      decoration: BoxDecoration(
        color: golden ? const Color(0xFFFFF8E1) : Colors.white,
        borderRadius: BorderRadius.circular(width * 0.13),
        border: Border.all(
          color: selected
              ? scheme.primary
              : (golden ? const Color(0xFFFFB300) : Colors.black26),
          width: selected || golden ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: selected ? 0.3 : 0.18),
            blurRadius: selected ? 5 : 3,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: TextStyle(
              color: ink,
              fontSize: width * (_isJoker ? 0.42 : 0.34),
              fontWeight: FontWeight.w800,
              height: 1.0,
            ),
          ),
          if (suitSymbol.isNotEmpty)
            Text(
              suitSymbol,
              style: TextStyle(color: ink, fontSize: width * 0.30, height: 1.1),
            ),
        ],
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
