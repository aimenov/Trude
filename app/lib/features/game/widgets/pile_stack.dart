/// The center pile: a messy stack of face-down card backs (each with a
/// deterministic thrown pose so flights land exactly where the stack draws),
/// capped at [MotionSpec.pileRenderCap] renders plus a count badge. Idle
/// life: the top card "settles" a pixel every ~10 s and the top backs carry
/// the gloss shimmer.
///
/// Physics reaction: the stack listens to [CardLandings] — when a flight
/// touches down inside its bounds, the top few resting cards take a damped
/// translation+rotation impulse along the landing direction, decaying over
/// [MotionSpec.pileNudge]. [PileStackState.nudge] is also public, so an
/// integrator can trigger the impulse directly via a GlobalKey.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/motion/animation_speed.dart';
import '../../../core/strings.dart';
import '../../../core/theme/trude_theme.dart';
import '../anim/card_flight.dart';
import '../anim/motion_spec.dart';
import 'card_widgets.dart';

class PileStack extends StatefulWidget {
  const PileStack({
    super.key,
    required this.count,
    required this.rank,
    required this.speed,
    this.cardWidth = 52,
    this.reactToLandings = true,
  });

  final int count;
  final String? rank;
  final AnimationSpeed speed;
  final double cardWidth;

  /// Whether the stack nudges itself when a [CardLandings] touchdown falls
  /// inside its bounds.
  final bool reactToLandings;

  @override
  State<PileStack> createState() => PileStackState();
}

/// Public so integrators can call [nudge] via a `GlobalKey<PileStackState>`.
class PileStackState extends State<PileStack>
    with SingleTickerProviderStateMixin {
  Timer? _settleTimer;
  double _settleDy = 0;

  late final AnimationController _nudge = AnimationController(
    vsync: this,
    duration: MotionSpec.pileNudge,
  )..addListener(() {
      if (mounted) setState(() {});
    });
  Offset _nudgeDir = const Offset(0, 1);

  @override
  void initState() {
    super.initState();
    _syncSettle();
    CardLandings.instance.last.addListener(_onLanding);
  }

  @override
  void didUpdateWidget(PileStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speed != widget.speed) _syncSettle();
  }

  void _syncSettle() {
    _settleTimer?.cancel();
    _settleTimer = null;
    if (widget.speed.isOff) {
      _settleDy = 0;
      return;
    }
    _settleTimer = Timer.periodic(MotionSpec.pileSettlePeriod, (_) {
      if (!mounted) return;
      setState(() => _settleDy = _settleDy == 0 ? 1 : 0);
    });
  }

  @override
  void dispose() {
    CardLandings.instance.last.removeListener(_onLanding);
    _settleTimer?.cancel();
    _nudge.dispose();
    super.dispose();
  }

  void _onLanding() {
    if (!widget.reactToLandings || widget.count <= 0) return;
    final landing = CardLandings.instance.last.value;
    if (landing == null) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    // Global bounds (transform-aware: the pile sits inside a FittedBox).
    final rect = MatrixUtils.transformRect(
            box.getTransformTo(null), Offset.zero & box.size)
        .inflate(widget.cardWidth * 0.4);
    if (!rect.contains(landing.position)) return;
    nudge(landing.direction);
  }

  /// Physically nudge the top resting cards: a damped translation (up to
  /// [MotionSpec.pileNudgeMaxOffset] dp) + rotation impulse along
  /// [impulseDirection], decaying over [MotionSpec.pileNudge].
  void nudge(Offset impulseDirection) {
    if (!mounted || widget.speed.isOff) return;
    final d = impulseDirection.distance;
    _nudgeDir = d < 1e-3 ? const Offset(0, 1) : impulseDirection / d;
    final duration = widget.speed.scale(MotionSpec.pileNudge);
    if (duration == Duration.zero) return;
    _nudge.duration = duration;
    _nudge.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rendered = widget.count.clamp(0, MotionSpec.pileRenderCap);
    final overflow = widget.count - rendered;
    final w = widget.cardWidth;
    final area = Size(w * 2.2, w * kCardAspect * 1.7);

    return SizedBox(
      width: area.width,
      height: area.height,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (widget.count == 0)
            Container(
              width: w,
              height: w * kCardAspect,
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(w * TrudeDims.cardRadiusFactor),
                border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.7)),
              ),
              child: Icon(Icons.style_outlined,
                  color: scheme.outlineVariant, size: w * 0.5),
            ),
          for (var i = 0; i < rendered; i++) _pileCard(i, rendered, w),
          if (overflow > 0)
            Positioned(
              right: 0,
              bottom: 0,
              child: Chip(
                label: Text('+$overflow'),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
          if (widget.rank != null)
            Positioned(
              top: -6,
              child: Chip(
                label: Text(Strings.rankWordPlural(widget.rank!),
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700)),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              ),
            ),
        ],
      ),
    );
  }

  Widget _pileCard(int i, int rendered, double w) {
    final pose = pileEntryPose(i);
    final isTop = i == rendered - 1;
    var offset = pose.offset + Offset(0, isTop ? _settleDy : 0);
    var angle = pose.angle;

    // Landing impulse: the top cards shift and twist, damped back to rest.
    final depth = rendered - 1 - i;
    if (_nudge.isAnimating && depth < MotionSpec.pileNudgeCards) {
      final t = _nudge.value;
      final falloff = pow(MotionSpec.pileNudgeFalloff, depth).toDouble();
      final wiggle =
          cos(t * pi * MotionSpec.pileNudgeWiggle) * (1 - t) * (1 - t);
      offset += _nudgeDir * (MotionSpec.pileNudgeMaxOffset * falloff * wiggle);
      angle += (i.isEven ? 1 : -1) *
          MotionSpec.pileNudgeMaxAngleDeg *
          pi /
          180 *
          falloff *
          wiggle;
    }

    // Shimmer only near the top of the stack — cheap and where the eye is.
    final shimmer = !widget.speed.isOff && i >= rendered - 2;
    return Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: angle,
        child: TrudeCardBack(width: w, shimmer: shimmer),
      ),
    );
  }
}
