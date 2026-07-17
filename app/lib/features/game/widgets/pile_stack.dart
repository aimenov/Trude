/// The center pile: a messy stack of face-down card backs (each with a
/// deterministic thrown pose so flights land exactly where the stack draws),
/// capped at [MotionSpec.pileRenderCap] renders plus a count badge, and — when
/// [PileStack.lastThrowCount] > 0 — the last throw laid out as a neat row
/// below the heap. Row cards become directly tappable when
/// [PileStack.onRowCardTap] is set (the responder checks by flipping one).
/// Idle life: the top card "settles" a pixel every ~10 s and the top backs
/// carry the gloss shimmer; a tappable row breathes.
///
/// Physics reaction: the stack listens to [CardLandings] — when a flight
/// touches down inside its bounds, the top few resting cards take a damped
/// translation+rotation impulse along the landing direction, decaying over
/// [MotionSpec.pileNudge]. [PileStackState.nudge] is also public, so an
/// integrator can trigger the impulse directly via a GlobalKey.
library;

import 'dart:async';
import 'dart:math';
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import '../../../core/motion/animation_speed.dart';
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
    this.lastThrowCount = 0,
    this.onRowCardTap,
    this.reactToLandings = true,
  });

  final int count;
  final String? rank;
  final AnimationSpeed speed;
  final double cardWidth;

  /// Size of the current laid-down row (the most recent throw); these cards
  /// render at [lastThrowRowPose] instead of joining the messy heap.
  final int lastThrowCount;

  /// When set, the row cards are directly tappable — tapping card [slot]
  /// checks it. Null renders the row inert (no glow, no cursor, no taps).
  final void Function(int slot)? onRowCardTap;

  /// Whether the stack nudges itself when a [CardLandings] touchdown falls
  /// inside its bounds.
  final bool reactToLandings;

  @override
  State<PileStack> createState() => PileStackState();
}

/// Public so integrators can call [nudge] via a `GlobalKey<PileStackState>`.
class PileStackState extends State<PileStack> with TickerProviderStateMixin {
  Timer? _settleTimer;
  double _settleDy = 0;

  late final AnimationController _nudge = AnimationController(
    vsync: this,
    duration: MotionSpec.pileNudge,
  )..addListener(() {
      if (mounted) setState(() {});
    });
  Offset _nudgeDir = const Offset(0, 1);

  /// The previous row lerping from its row poses into the messy heap:
  /// render indices [_tuckFirst, _tuckFirst + _tuckN) come from
  /// [lastThrowRowPose] slots of a [_tuckRow]-card row.
  late final AnimationController _tuck = AnimationController(
    vsync: this,
    duration: MotionSpec.pileTuck,
  )..addListener(() {
      if (mounted) setState(() {});
    });
  int _tuckFirst = 0;
  int _tuckN = 0;
  int _tuckRow = 0;

  /// Breathing scale of a tappable row (shared phase across the row).
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: MotionSpec.breathingPeriod,
  );

  int get _messyCount => max(0, widget.count - widget.lastThrowCount);

  @override
  void initState() {
    super.initState();
    _syncSettle();
    _syncBreathe();
    CardLandings.instance.last.addListener(_onLanding);
  }

  @override
  void didUpdateWidget(PileStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.speed != widget.speed) _syncSettle();
    _syncBreathe();
    _maybeTuck(oldWidget);
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

  void _syncBreathe() {
    final wants = widget.onRowCardTap != null &&
        widget.lastThrowCount > 0 &&
        !widget.speed.isOff;
    if (wants && !_breathe.isAnimating) {
      _breathe.repeat();
    } else if (!wants && _breathe.isAnimating) {
      _breathe.stop();
      _breathe.value = 0;
    }
  }

  /// When the messy heap grew, the old row just got buried: lerp the newly
  /// messy cards from their old row poses into their heap poses.
  void _maybeTuck(PileStack oldWidget) {
    final oldMessy = max(0, oldWidget.count - oldWidget.lastThrowCount);
    final newMessy = _messyCount;
    if (newMessy <= oldMessy ||
        oldWidget.lastThrowCount <= 0 ||
        widget.speed.isOff) {
      return;
    }
    final rendered = min(newMessy, MotionSpec.pileRenderCap);
    _tuckRow = oldWidget.lastThrowCount;
    _tuckN = min(min(newMessy - oldMessy, _tuckRow), rendered);
    _tuckFirst = rendered - _tuckN;
    final duration = widget.speed.scale(MotionSpec.pileTuck);
    if (_tuckN <= 0 || duration == Duration.zero) return;
    _tuck.duration = duration;
    _tuck.forward(from: 0);
  }

  @override
  void dispose() {
    CardLandings.instance.last.removeListener(_onLanding);
    _settleTimer?.cancel();
    _nudge.dispose();
    _tuck.dispose();
    _breathe.dispose();
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
    final messyCount = _messyCount;
    final rendered = messyCount.clamp(0, MotionSpec.pileRenderCap);
    final overflow = messyCount - rendered;
    final rowCount = min(widget.lastThrowCount, widget.count).clamp(0, 3);
    final w = widget.cardWidth;
    // CONSTANT box regardless of contents: flights aim at the box center, so
    // the anchor must never drift, and the layout must never jump.
    final area = Size(max(w * 2.2, 3 * w + 2 * 8), w * kCardAspect * 1.7);

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
          for (var slot = 0; slot < rowCount; slot++)
            _rowCard(slot, rowCount, w),
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
        ],
      ),
    );
  }

  Widget _pileCard(int i, int rendered, double w) {
    var pose = pileEntryPose(i);
    // Freshly buried row cards slide from their old row pose into the heap.
    if (_tuck.isAnimating && i >= _tuckFirst && i < _tuckFirst + _tuckN) {
      final from = lastThrowRowPose(i - _tuckFirst, _tuckRow, cardWidth: w);
      final t = MotionSpec.pileTuckCurve.transform(_tuck.value);
      pose = (
        offset: Offset.lerp(from.offset, pose.offset, t)!,
        angle: lerpDouble(from.angle, pose.angle, t)!,
      );
    }
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

  /// One card of the laid-down last throw. Tappable rows glow (selected
  /// treatment), breathe, and carry a click cursor; inert rows just lie there.
  Widget _rowCard(int slot, int rowCount, double w) {
    final pose = lastThrowRowPose(slot, rowCount, cardWidth: w);
    final tappable = widget.onRowCardTap != null;

    Widget card = TrudeCardBack(width: w, selected: tappable);
    if (tappable) {
      if (!widget.speed.isOff) {
        card = AnimatedBuilder(
          animation: _breathe,
          child: card,
          builder: (context, child) => Transform.scale(
            scale: 1 +
                MotionSpec.breathingScaleDelta *
                    0.5 *
                    (1 - cos(2 * pi * _breathe.value)),
            child: child,
          ),
        );
      }
      card = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          key: ValueKey('pile-row-$slot'),
          behavior: HitTestBehavior.opaque,
          onTap: () => widget.onRowCardTap!(slot),
          child: card,
        ),
      );
    }
    return Transform.translate(
      offset: pose.offset,
      child: Transform.rotate(angle: pose.angle, child: card),
    );
  }
}
