/// My hand rendered as real card faces: tap to select (selected cards rise),
/// newly received cards pop in with a stagger (the hand visibly bloats after
/// a pickup), and the whole fan micro-shivers in the last urgent seconds of
/// my turn.
///
/// FLICK-TO-THROW: with cards selected and a throw armed
/// ([MyHandView.onFlickThrow] non-null), dragging a SELECTED card upward
/// makes the whole selection follow the finger — with per-card lag and a
/// tilt toward the drag direction — and releasing with upward velocity ≥
/// [MotionSpec.flickThrowSpeed] fires the same throw callback as the THROW
/// button while publishing the release velocity to [FlickLaunch], so the
/// flight animation launches with the exact flick velocity (clamped). A
/// sub-threshold release springs the cards back into the fan.
///
/// The drag recognizer lives ONLY on selected cards: taps on unselected
/// cards never compete with a drag arena, so slightly-draggy taps select
/// reliably. Tap-to-select, the fan scroll, and the urgency shiver are
/// untouched.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart' hide Card;

import '../../../core/motion/animation_speed.dart';
import '../../../core/net/protocol_models.dart';
import '../anim/card_flight.dart';
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
    this.onFlickThrow,
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

  /// Fired by a successful upward flick — wire it to the SAME action as the
  /// THROW button (it must itself guard legality, e.g. a chosen rank when
  /// leading). Null disables the flick gesture entirely. The release
  /// velocity is handed to the flight layer via [FlickLaunch] just before
  /// this fires.
  final VoidCallback? onFlickThrow;

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

  // -- Flick state -------------------------------------------------------------

  /// Raw accumulated finger offset of the active vertical drag.
  Offset _rawDrag = Offset.zero;
  bool _dragging = false;

  /// Where the spring-back started from after a sub-threshold release.
  Offset _springFrom = Offset.zero;
  late final AnimationController _spring = AnimationController(
    vsync: this,
    duration: MotionSpec.flickSpringBack,
  )..addListener(() {
      if (mounted) setState(() {});
    });

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
    // The turn ended or the selection vanished mid-drag: drop the gesture.
    if (_dragging && !_flickEnabled) {
      _dragging = false;
      _rawDrag = Offset.zero;
      _springFrom = Offset.zero;
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
    _spring.dispose();
    super.dispose();
  }

  // -- Flick gesture -------------------------------------------------------------

  bool get _flickEnabled =>
      widget.onFlickThrow != null &&
      widget.selectable &&
      widget.selectedIds.isNotEmpty;

  /// The current visual displacement of the dragged selection: the live
  /// (rubber-banded) finger offset while dragging, the settling spring
  /// afterwards, zero at rest.
  Offset get _displayDrag {
    if (_dragging) {
      final dy = _rawDrag.dy;
      return Offset(
        _rawDrag.dx * MotionSpec.flickFollowDx,
        dy <= 0
            ? dy
            : min(MotionSpec.flickMaxDown, dy * MotionSpec.flickDownRubberBand),
      );
    }
    if (_spring.isAnimating) {
      // easeOutBack overshoots past 1: the fan dips a touch below rest and
      // settles — the spring feel.
      final t = MotionSpec.flickSpringBackCurve.transform(_spring.value);
      return _springFrom * (1 - t);
    }
    return Offset.zero;
  }

  void _onFlickStart(DragStartDetails details) {
    if (!_flickEnabled) return;
    _spring.stop();
    setState(() {
      _dragging = true;
      _rawDrag = Offset.zero;
    });
  }

  void _onFlickUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    setState(() => _rawDrag += details.delta);
  }

  void _onFlickEnd(DragEndDetails details) {
    if (!_dragging) return;
    final velocity = details.velocity.pixelsPerSecond;
    final thrown = _flickEnabled &&
        _rawDrag.dy <= -MotionSpec.flickMinDrag &&
        velocity.dy <= -MotionSpec.flickThrowSpeed;
    if (thrown) {
      _publishFlick(velocity);
      widget.onFlickThrow?.call();
    }
    _settleBack();
  }

  void _onFlickCancel() {
    if (_dragging) _settleBack();
  }

  void _settleBack() {
    _springFrom = _displayDrag;
    _dragging = false;
    _rawDrag = Offset.zero;
    final duration = widget.speed.scale(MotionSpec.flickSpringBack);
    if (duration == Duration.zero || _springFrom == Offset.zero) {
      // Reduce motion (or nothing to settle): snap back instantly.
      setState(() => _springFrom = Offset.zero);
      return;
    }
    _spring.duration = duration;
    _spring.forward(from: 0);
  }

  /// Hands the clamped release velocity to the flight layer: the launch
  /// velocity of my throw's flight IS this flick.
  void _publishFlick(Offset velocity) {
    final speed = velocity.distance.clamp(
        MotionSpec.flickLaunchSpeedMin, MotionSpec.flickLaunchSpeedMax);
    var dir = velocity.distance < 1
        ? const Offset(0, -1)
        : velocity / velocity.distance;
    if (dir.dy > -0.2) dir = const Offset(0, -1); // must read as upward
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final rect = MatrixUtils.transformRect(
        box.getTransformTo(null), Offset.zero & box.size);
    FlickLaunch.publish(velocity: dir * speed, source: rect);
  }

  // -- Build ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final w = widget.cardWidth;
    // No whole-hand drag detector: the flick recognizer is attached per-card
    // (selected cards only) in [_handCard], so taps never lose a gesture
    // arena to a drag.
    return SizedBox(
      height: w * kCardAspect + 14,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        // Dragged cards may ride above the hand strip.
        clipBehavior: Clip.none,
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
      final dy =
          (((h ~/ 100) % 100) / 100 - 0.5) * MotionSpec.handShiverAmplitude;
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

    // The dragged (or spring-settling) selection follows the finger with
    // per-card lag, a tilt toward the drag direction, and a slight lift.
    final drag = _displayDrag;
    if (selected && drag != Offset.zero && !widget.speed.isOff) {
      var lagIndex = 0;
      for (var k = 0; k < index; k++) {
        if (widget.selectedIds.contains(widget.cards[k].id)) lagIndex++;
      }
      final follow = max(
          MotionSpec.flickFollowFloor,
          MotionSpec.flickFollow -
              lagIndex * MotionSpec.flickFollowLagPerCard);
      final tilt = (drag.dx *
              MotionSpec.flickTiltPerDx *
              (1 + lagIndex * MotionSpec.flickTiltLagBoost))
          .clamp(-MotionSpec.flickMaxTilt, MotionSpec.flickMaxTilt);
      final lift = (-min(0.0, drag.dy) / MotionSpec.flickLiftDistance)
          .clamp(0.0, 1.0);
      child = Transform.translate(
        offset: drag * follow,
        child: Transform.rotate(
          angle: tilt,
          child: Transform.scale(
            scale: 1 + MotionSpec.flickLiftScale * lift,
            child: child,
          ),
        ),
      );
    }

    // The vertical-drag (flick) recognizer exists only on SELECTED cards
    // while a flick is armed. The drag state is shared across the whole
    // widget, so dragging any selected card moves the entire selection
    // together; unselected cards carry a lone tap recognizer — nothing
    // competes with (or delays) selection taps.
    final flickHere = _flickEnabled && selected;
    return GestureDetector(
      onTap: widget.selectable ? () => widget.onToggle(card, !selected) : null,
      onVerticalDragStart: flickHere ? _onFlickStart : null,
      onVerticalDragUpdate: flickHere ? _onFlickUpdate : null,
      onVerticalDragEnd: flickHere ? _onFlickEnd : null,
      onVerticalDragCancel: flickHere ? _onFlickCancel : null,
      child: child,
    );
  }
}
