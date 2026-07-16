/// My hand rendered as real card faces: tap to select (selected cards rise),
/// newly received cards pop in with a stagger (the hand visibly bloats after
/// a pickup), and the whole fan micro-shivers in the last urgent seconds of
/// my turn.
///
/// FLICK-TO-THROW: with cards selected and a throw armed
/// ([MyHandView.onFlickThrow] non-null), dragging upward ANYWHERE on the
/// hand strip — a selected card, an unselected card, a gap, empty flank
/// space; diagonals toward the pile included — makes the whole selection
/// follow the finger — with per-card lag and a tilt toward the drag
/// direction — and releasing with total speed ≥
/// [MotionSpec.flickThrowSpeed] and an upward component ≥
/// [MotionSpec.flickThrowUpComponent] (per the SDK estimate OR a
/// self-tracked one immune to the SDK's mouse-settle zeroing), OR after an
/// upward-dominant carry of ≥ [MotionSpec.flickThrowDistance], fires the
/// same throw callback as the THROW button while publishing the release
/// velocity to [FlickLaunch], so the flight animation launches with the
/// exact flick velocity (clamped). A sub-threshold release springs the
/// cards back into the fan.
///
/// The flick is ONE strip-level recognizer ([_UpFlickRecognizer]) with
/// direction-gated acceptance: it claims the pointer only once the movement
/// crosses hit slop AND reads as upward-dominant, so it may cover the whole
/// strip (a multi-card selection is throwable from anywhere — selected cards
/// lift and shift their hitboxes, so per-card surfaces left dead zones)
/// while horizontal drags still reach the overflow ListView's scroll and
/// stationary taps still select. When the fan fits the window it renders as
/// a centered non-scrollable Row; only an overflowing hand falls back to the
/// horizontal ListView. Tap-to-select and the urgency shiver are untouched.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
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

  /// Recent (timestamp, delta) drag samples, trimmed to the last
  /// [MotionSpec.flickRecentWindowMs] — a self-tracked release velocity.
  /// The SDK's VelocityTracker reports [DragEndDetails.velocity] as ZERO
  /// whenever >40ms pass between the last pointer move and the release,
  /// the norm for a mouse (it settles before button-up), so relying on it
  /// alone made mouse flicks spring back. See [_recentVelocity].
  final List<(Duration, Offset)> _flickSamples = [];

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
      _flickSamples.clear();
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
    _flickSamples.clear();
    setState(() {
      _dragging = true;
      _rawDrag = Offset.zero;
    });
  }

  void _onFlickUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    // Sample for the self-tracked release velocity. Event timestamps when
    // the engine provides them (they also track the fake test clock); the
    // wall clock is the fallback — both are monotonic within one gesture.
    final now = details.sourceTimeStamp ??
        Duration(microseconds: DateTime.now().microsecondsSinceEpoch);
    _flickSamples.add((now, details.delta));
    final cutoff =
        now - const Duration(milliseconds: MotionSpec.flickRecentWindowMs);
    _flickSamples.removeWhere((s) => s.$1 < cutoff);
    setState(() => _rawDrag += details.delta);
  }

  /// Release velocity (dp/s) computed from the sampled window: the window's
  /// travel over its time span. Unlike the SDK estimate, this stays
  /// meaningful when the pointer is genuinely moving as the button lifts.
  Offset get _recentVelocity {
    if (_flickSamples.length < 2) return Offset.zero;
    final span = _flickSamples.last.$1 - _flickSamples.first.$1;
    if (span <= Duration.zero) return Offset.zero;
    var travel = Offset.zero;
    // The first sample's delta accrued before the window opened: skip it.
    for (var i = 1; i < _flickSamples.length; i++) {
      travel += _flickSamples[i].$2;
    }
    return travel * (Duration.microsecondsPerSecond / span.inMicroseconds);
  }

  void _onFlickEnd(DragEndDetails details) {
    if (!_dragging) return;
    final sdkVelocity = details.velocity.pixelsPerSecond;
    final recentVelocity = _recentVelocity;
    // Direction-tolerant velocity gate: enough TOTAL release speed and an
    // upward component that merely reads as "up" — so diagonal flicks from
    // the fan's edge cards throw just like vertical ones.
    bool qualifies(Offset v) =>
        v.distance >= MotionSpec.flickThrowSpeed &&
        v.dy <= -MotionSpec.flickThrowUpComponent;
    // Deliberate carry: the cards were dragged well up toward the table,
    // upward-dominant — a pause before release must NOT cancel the throw
    // (the SDK zeroes the release velocity after a 40ms still, the norm for
    // a mouse; "drag-and-drop onto the table" also throws).
    final carried = _rawDrag.dy <= -MotionSpec.flickThrowDistance &&
        _rawDrag.dy.abs() >= MotionSpec.flickUpDominance * _rawDrag.dx.abs();
    // Accept: net upward travel AND (a qualifying release velocity — SDK or
    // self-tracked — OR the deliberate carry).
    final thrown = _flickEnabled &&
        _rawDrag.dy <= -MotionSpec.flickMinDrag &&
        (qualifies(sdkVelocity) || qualifies(recentVelocity) || carried);
    if (thrown) {
      // Launch with the truest velocity available: the SDK estimate when it
      // qualified, else the self-tracked one when meaningful, else a synth
      // along the drag direction (_publishFlick clamps and steers the rest).
      final launch = qualifies(sdkVelocity)
          ? sdkVelocity
          : recentVelocity.distance >= MotionSpec.flickSynthesizeFloor
              ? recentVelocity
              : _rawDrag / _rawDrag.distance * MotionSpec.flickLaunchSpeedMin;
      _publishFlick(launch);
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
    // Keep the true (diagonal) direction whenever it reads as upward at all;
    // the ballistic flight steers to the pile anyway, so this is cosmetic.
    if (dir.dy > -0.15) dir = const Offset(0, -1);
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
    // ONE strip-level flick recognizer covers the WHOLE hand — cards
    // (selected or not), the gaps between them, and the empty flanks. With
    // several cards selected the natural upward swipe rarely begins exactly
    // on a lifted selected card, so the flick surface must not care where
    // the finger lands; [_UpFlickRecognizer]'s direction gate keeps taps and
    // the overflow scroll working (see its doc). The RawGestureDetector is
    // ALWAYS mounted (an empty gesture map while the flick is disarmed) so
    // arming/disarming never restructures the subtree — the overflow
    // ListView keeps its element, state, and scroll position.
    return SizedBox(
      height: w * kCardAspect + 14,
      child: RawGestureDetector(
        // Hit the strip's empty space too, not only the card children.
        behavior: HitTestBehavior.translucent,
        gestures: _flickEnabled
            ? <Type, GestureRecognizerFactory>{
                _UpFlickRecognizer:
                    GestureRecognizerFactoryWithHandlers<_UpFlickRecognizer>(
                  _UpFlickRecognizer.new,
                  (r) => r
                    ..onStart = _onFlickStart
                    ..onUpdate = _onFlickUpdate
                    ..onEnd = _onFlickEnd
                    ..onCancel = _onFlickCancel,
                ),
              }
            : const <Type, GestureRecognizerFactory>{},
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Natural width of the fan: per-card footprint (card + 3+3 dp of
            // padding) plus the strip's 10+10 dp edge padding.
            final naturalWidth = widget.cards.length * (w + 6) + 20;
            if (naturalWidth <= constraints.maxWidth) {
              // The fan fits: render a centered, non-scrollable Row — no
              // horizontal drag recognizer exists at all, so nothing competes
              // with the flick pan, and the fan is centered on wide windows.
              // crossAxisAlignment.stretch reproduces the ListView's tight
              // cross-axis constraints, so per-card geometry is identical on
              // both paths. Row never clips, so the selection lift/glow may
              // ride above the strip exactly as with Clip.none.
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < widget.cards.length; i++)
                    _handCard(widget.cards[i], i, w),
                ],
              );
            }
            // Overflow: fall back to the scrollable strip.
            return ListView.builder(
              scrollDirection: Axis.horizontal,
              // Dragged cards may ride above the hand strip.
              clipBehavior: Clip.none,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: widget.cards.length,
              itemBuilder: (context, i) => _handCard(widget.cards[i], i, w),
            );
          },
        ),
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

    // Selection is a plain tap; the flick pan lives at strip level (see
    // [build]) and claims only upward-dominant drags, so nothing here can
    // eat or delay a selection tap. The drag state is shared across the
    // whole widget: a flick started anywhere moves the entire selection
    // together (the per-card visuals above).
    return GestureDetector(
      onTap: widget.selectable ? () => widget.onToggle(card, !selected) : null,
      child: child,
    );
  }
}

/// The strip-level flick recognizer: a [PanGestureRecognizer] that accepts on
/// the tighter axis (hit-test) slop instead of [computePanSlop] (2x), and
/// ONLY when the movement so far reads as upward-dominant.
///
/// HIT SLOP — with the stock pan slop, the hand ListView's horizontal
/// recognizer reaches ITS slop first for any drag shallower than ~60 degrees
/// from horizontal and swallows the flick (the old "side cards can't be
/// thrown" bug). With hit slop, the pan's cumulative TOTAL distance crosses
/// the shared threshold strictly before the scroll's horizontal projection
/// of the same movement, so an upward flick wins the arena.
///
/// DIRECTION GATE — this recognizer covers the WHOLE strip, so accepting any
/// direction at hit slop would also swallow the overflow ListView's
/// horizontal scroll drags. [hasSufficientGlobalDistanceToAccept] therefore
/// claims the arena only while the accumulated pre-acceptance movement
/// ([_pendingMove], tracked in [handleEvent] — the SDK's own equivalent,
/// `_pendingDragOffset`, is private) is upward-dominant: dy < 0 and
/// |dy| >= [MotionSpec.flickUpDominance] * |dx|. Anything else is simply
/// never accepted, which resolves to a REAL arena rejection: a horizontal
/// drag lets the ListView's recognizer win at its own slop (sweeping this
/// one rejected), and a stationary tap wins on pointer-up exactly as before
/// (this recognizer gives its pointer up as rejected).
class _UpFlickRecognizer extends PanGestureRecognizer {
  /// Cumulative finger movement of the gesture, tracked from the first
  /// event after the pointer went down (reset per gesture).
  Offset _pendingMove = Offset.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _pendingMove = Offset.zero;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _pendingMove += event.delta;
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
          PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) =>
      _pendingMove.dy < 0 &&
      _pendingMove.dy.abs() >=
          MotionSpec.flickUpDominance * _pendingMove.dx.abs() &&
      globalDistanceMoved.abs() >
          computeHitSlop(pointerDeviceKind, gestureSettings);
}
