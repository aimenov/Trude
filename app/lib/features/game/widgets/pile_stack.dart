/// The center pile: a messy stack of face-down card backs (each with a
/// deterministic thrown pose so flights land exactly where the stack draws),
/// capped at [MotionSpec.pileRenderCap] renders plus a count badge. Idle
/// life: the top card "settles" a pixel every ~10 s and the top backs carry
/// the gloss shimmer.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/motion/animation_speed.dart';
import '../../../core/strings.dart';
import '../anim/motion_spec.dart';
import 'card_widgets.dart';

class PileStack extends StatefulWidget {
  const PileStack({
    super.key,
    required this.count,
    required this.rank,
    required this.speed,
    this.cardWidth = 52,
  });

  final int count;
  final String? rank;
  final AnimationSpeed speed;
  final double cardWidth;

  @override
  State<PileStack> createState() => _PileStackState();
}

class _PileStackState extends State<PileStack> {
  Timer? _settleTimer;
  double _settleDy = 0;

  @override
  void initState() {
    super.initState();
    _syncSettle();
  }

  @override
  void didUpdateWidget(PileStack old) {
    super.didUpdateWidget(old);
    if (old.speed != widget.speed) _syncSettle();
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
    _settleTimer?.cancel();
    super.dispose();
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
                borderRadius: BorderRadius.circular(w * 0.13),
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
    // Shimmer only near the top of the stack — cheap and where the eye is.
    final shimmer = !widget.speed.isOff && i >= rendered - 2;
    return Transform.translate(
      offset: pose.offset + Offset(0, isTop ? _settleDy : 0),
      child: Transform.rotate(
        angle: pose.angle,
        child: TrudeCardBack(width: w, shimmer: shimmer),
      ),
    );
  }
}
