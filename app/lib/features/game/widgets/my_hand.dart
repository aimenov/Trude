/// My hand rendered as real card faces: tap to select (selected cards rise),
/// newly received cards pop in with a stagger (the hand visibly bloats after
/// a pickup), and the whole fan micro-shivers in the last urgent seconds of
/// my turn.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart' hide Card;

import '../../../core/motion/animation_speed.dart';
import '../../../core/net/protocol_models.dart';
import '../anim/motion_spec.dart';
import 'card_widgets.dart';

class MyHandView extends StatefulWidget {
  const MyHandView({
    super.key,
    required this.cards,
    required this.selectedIds,
    required this.selectable,
    required this.onToggle,
    required this.shiver,
    required this.speed,
    this.cardWidth = 46,
  });

  final List<Card> cards;
  final Set<String> selectedIds;

  /// Whether taps select cards right now (my throw UI is open).
  final bool selectable;
  final void Function(Card card, bool selected) onToggle;

  /// Nervous micro-shiver (urgent countdown on my turn).
  final bool shiver;
  final AnimationSpeed speed;
  final double cardWidth;

  @override
  State<MyHandView> createState() => _MyHandViewState();
}

class _MyHandViewState extends State<MyHandView>
    with SingleTickerProviderStateMixin {
  /// Ids already seen — new ones get an entrance pop with a stagger.
  final Set<String> _known = {};
  final Map<String, int> _enterOrder = {};

  Timer? _shiverTimer;
  final _rng = Random();
  double _shiverSeed = 0;

  @override
  void initState() {
    super.initState();
    for (final c in widget.cards) {
      _known.add(c.id);
    }
    _syncShiver();
  }

  @override
  void didUpdateWidget(MyHandView old) {
    super.didUpdateWidget(old);
    var order = 0;
    for (final c in widget.cards) {
      if (_known.add(c.id)) _enterOrder[c.id] = order++;
    }
    _known.removeWhere((id) => !widget.cards.any((c) => c.id == id));
    if (old.shiver != widget.shiver || old.speed != widget.speed) {
      _syncShiver();
    }
  }

  void _syncShiver() {
    _shiverTimer?.cancel();
    _shiverTimer = null;
    if (!widget.shiver || widget.speed.isOff) return;
    _shiverTimer = Timer.periodic(MotionSpec.handShiverPeriod, (_) {
      if (mounted) setState(() => _shiverSeed = _rng.nextDouble() * 1000);
    });
  }

  @override
  void dispose() {
    _shiverTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.cardWidth;
    return SizedBox(
      height: w * kCardAspect + 14,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: widget.cards.length,
        itemBuilder: (context, i) => _handCard(widget.cards[i], i, w),
      ),
    );
  }

  Widget _handCard(Card card, int index, double w) {
    final selected = widget.selectedIds.contains(card.id);
    final enterIndex = _enterOrder[card.id];

    Widget child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: AnimatedSlide(
        offset: selected ? const Offset(0, -0.12) : Offset.zero,
        duration: widget.speed.scale(const Duration(milliseconds: 140)),
        curve: Curves.easeOut,
        child: TrudeCardFace(
          rank: card.rank,
          suit: card.suit,
          width: w,
          selected: selected,
        ),
      ),
    );

    if (widget.shiver && !widget.speed.isOff) {
      // Per-card pseudo-random nervous offset, refreshed by the shiver timer.
      final h = (card.id.hashCode ^ _shiverSeed.toInt()) & 0xffff;
      final dx = ((h % 100) / 100 - 0.5) * MotionSpec.handShiverAmplitude;
      final dy = (((h ~/ 100) % 100) / 100 - 0.5) *
          MotionSpec.handShiverAmplitude;
      child = Transform.translate(offset: Offset(dx, dy), child: child);
    }

    if (enterIndex != null) {
      final duration = widget.speed.scale(MotionSpec.handCardEnter);
      child = TweenAnimationBuilder<double>(
        key: ValueKey('enter-${card.id}'),
        tween: Tween(begin: 0.0, end: 1.0),
        duration: duration +
            widget.speed.scale(Duration(milliseconds: 45 * enterIndex)),
        curve: Interval(
            // Staggered entrance: later cards start later within one tween.
            min(0.9, 0.15 * enterIndex),
            1,
            curve: MotionSpec.handCardEnterCurve),
        onEnd: () => _enterOrder.remove(card.id),
        builder: (context, t, c) => Transform.scale(
          scale: 0.4 + 0.6 * t,
          child: Opacity(opacity: t.clamp(0.0, 1.0), child: c),
        ),
        child: child,
      );
    }

    return GestureDetector(
      onTap: widget.selectable
          ? () => widget.onToggle(card, !selected)
          : null,
      child: child,
    );
  }
}
