/// Card visuals: face-down backs (with the idle gloss shimmer) and faces.
/// The art itself is painter-drawn ("Midnight Parlor" deck, see
/// card_painters.dart): engraved pips, court medallions, the joker, and a
/// brass guilloche back — no image assets, crisp at any width.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/strings.dart';
import '../../../core/theme/trude_theme.dart';
import '../anim/motion_jitter.dart';
import '../anim/motion_spec.dart';
import 'card_painters.dart';
import 'cosmetic_styles.dart';

const kCardAspect = 68 / 48; // height / width of every card widget

class TrudeCardBack extends ConsumerWidget {
  const TrudeCardBack({
    super.key,
    this.width = 48,
    this.shimmer = false,
    this.selected = false,
    this.style,
  });

  final double width;

  /// Idle gloss sweep; only enabled where a shared ticker is cheap to run.
  final bool shimmer;

  /// Brass outer glow + a slightly stronger lift shadow (geometry unchanged),
  /// mirroring [TrudeCardFace.selected].
  final bool selected;

  /// Explicit cosmetic style (shop previews). When null — every in-game
  /// render site — the equipped style from [selectedCardBackStyleProvider]
  /// is used, so call sites never pass it.
  final CardBackStyle? style;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Explicit annotation: with a nullable left operand of `??`, Dart would
    // otherwise infer `ref.watch<CardBackStyle?>` from the context type.
    final CardBackStyle resolved =
        style ?? ref.watch(selectedCardBackStyleProvider);
    final radius = BorderRadius.circular(width * TrudeDims.cardRadiusFactor);
    final card = Container(
      width: width,
      height: width * kCardAspect,
      decoration: BoxDecoration(
        color: resolved.frame,
        borderRadius: radius,
        boxShadow: [
          if (selected)
            BoxShadow(
              color: TrudeColors.brass.withValues(alpha: 0.55),
              blurRadius: width * 0.30,
              spreadRadius: 1,
            ),
          BoxShadow(
            color: Colors.black.withValues(alpha: selected ? 0.32 : 0.25),
            blurRadius: selected ? 6 : 3,
            offset: Offset(0, selected ? 2.5 : 1.5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: CustomPaint(
          painter: CardBackPainter(style: resolved),
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
///
/// Perf: an overlay streak instead of a ShaderMask — no per-frame saveLayer
/// and no gradient/shader rebuilds. The gradient child is const-built once;
/// per frame only the FractionalTranslation offset changes, clipped to the
/// card's rounded corners.
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

  /// The diagonal gloss streak (white at alpha 0.18), built exactly once.
  static const _streak = DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          Color(0x2EFFFFFF), // white, alpha 0.18
          Colors.transparent,
        ],
        stops: [0.35, 0.5, 0.65],
      ),
    ),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius =
        BorderRadius.circular(widget.width * TrudeDims.cardRadiusFactor);
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: radius,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => FractionalTranslation(
                  // Sweep from off-left to off-right over one period.
                  translation: Offset(_controller.value * 3 - 1.5, 0),
                  child: _streak,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
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

/// The resting pose of card [slot] in the laid-down last-throw row: a neat
/// centered row just below the messy heap, with a whisper of seeded jitter so
/// the cards read as placed by hand. Deterministic per (slot, rowCount) so
/// flights land exactly where the stack will draw the card.
({Offset offset, double angle}) lastThrowRowPose(
  int slot,
  int rowCount, {
  double cardWidth = 52,
}) {
  final rng = Random(slot * 5471 + rowCount * 131);
  double signed() => rng.nextDouble() * 2 - 1;
  final dx = (slot - (rowCount - 1) / 2) * (cardWidth + 8);
  final dy = cardWidth * kCardAspect * 0.33;
  return (
    offset: Offset(dx + signed() * 1.5, dy + signed() * 1.5),
    angle: signed() * 4 * pi / 180,
  );
}
