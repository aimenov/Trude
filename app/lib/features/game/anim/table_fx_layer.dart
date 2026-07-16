/// The choreographer: listens to the AnimationQueue's step-start stream and
/// drives every visual set piece — card flights, claim callouts, the reveal /
/// quad / game-over overlays, and emoji reaction bursts — with matching
/// sfx/haptics hooks. Sits topmost in the table Stack, fully input-transparent.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/sfx_service.dart';
import '../../../core/haptics/haptics_service.dart';
import '../../../core/motion/animation_speed.dart';
import '../../../core/net/connection_providers.dart';
import '../../../core/strings.dart';
import '../widgets/card_widgets.dart';
import 'animation_queue.dart';
import 'card_flight.dart';
import 'claim_callout.dart';
import 'emoji_burst.dart';
import 'event_steps.dart';
import 'game_over_overlay.dart';
import 'motion_spec.dart';
import 'quad_celebration.dart';
import 'rendered_state.dart';
import 'reveal_overlay.dart';
import 'table_anchors.dart';

class _Callout {
  _Callout({required this.id, required this.position, required this.text, this.color});

  final int id;
  final Offset position; // global
  final String text;
  final Color? color;
}

class TableFxLayer extends ConsumerStatefulWidget {
  const TableFxLayer({super.key, required this.anchors});

  final TableAnchors anchors;

  @override
  ConsumerState<TableFxLayer> createState() => _TableFxLayerState();
}

class _TableFxLayerState extends ConsumerState<TableFxLayer> {
  final _flights = CardFlightController();
  final _bursts = EmojiBurstController();
  final _subs = <StreamSubscription<dynamic>>[];
  final List<_Callout> _callouts = [];
  int _calloutIds = 0;

  StartedStep? _reveal;
  StartedStep? _quad;
  StartedStep? _gameOver;

  SfxService get _sfx => ref.read(sfxProvider);
  HapticsService get _haptics => ref.read(hapticsProvider);
  TableAnchors get _anchors => widget.anchors;

  @override
  void initState() {
    super.initState();
    final queue = ref.read(animationQueueProvider);
    _subs.add(queue.onStepStarted.listen(_dispatch));
    _subs.add(queue.onSkipped.listen((_) => _clearAll()));
    final room = ref.read(currentRoomProvider);
    if (room != null) {
      _subs.add(room.onReaction.listen(_onReaction));
    }
    // The lobby navigates here on the TRUE phase flip, so the deal step may
    // already be playing before this layer mounts — pick it up after layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = queue.current;
      if (current != null && mounted) _dispatch(current);
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _flights.dispose();
    _bursts.dispose();
    super.dispose();
  }

  void _clearAll() {
    _flights.clear();
    if (!mounted) return;
    setState(() {
      _callouts.clear();
      _reveal = null;
      _quad = null;
      _gameOver = null;
    });
  }

  // -- Step dispatch ---------------------------------------------------------

  void _dispatch(StartedStep started) {
    if (!mounted) return;
    switch (started.step.kind) {
      case StepKind.deal:
        _runDeal(started);
      case StepKind.throwCards:
        _runThrow(started);
      case StepKind.reveal:
        // The overlay itself fires the beat-synced sfx/haptics.
        setState(() => _reveal = started);
      case StepKind.pickup:
        _runPickup(started);
      case StepKind.quad:
        _sfx.quadFanfare();
        _haptics.success();
        setState(() => _quad = started);
      case StepKind.playerOut:
        _runPlayerOut(started);
      case StepKind.gameOver:
        _sfx.jokerReveal();
        _haptics.heavy();
        setState(() => _gameOver = started);
      case StepKind.instant:
        break;
    }
  }

  /// Fraction-of-step timing scaled to the started step's wall duration.
  Duration _at(StartedStep s, double fraction) =>
      Duration(microseconds: (s.duration.inMicroseconds * fraction).round());

  void _runDeal(StartedStep started) {
    final event = started.step.event;
    if (event is! GameStartedEvent) return;
    final pile = _anchors.pileRect;
    if (pile == null) return;

    _sfx.shuffle();
    _haptics.light();

    final mySeat = started.after.mySeat;
    final order = dealOrder(event.handCounts);
    final schedule = dealSchedule(order.length);
    final stepMs = max(1, started.step.baseDuration.inMilliseconds);
    final specs = <CardFlightSpec>[];
    for (var k = 0; k < order.length; k++) {
      final seat = order[k];
      final target = _anchors.originForSeat(seat, mySeat);
      if (target == null) continue;
      specs.add(CardFlightSpec(
        from: pile,
        to: target,
        // Keep flight visuals in lockstep with the queue's tick schedule.
        delay: _at(started, schedule.launchMs(k) / stepMs),
        duration: _at(started, MotionSpec.dealFlight.inMilliseconds / stepMs),
        width: seat == mySeat ? 42 : 34,
        spinTurns: 0.5,
        onLand: k % 4 == 0 ? _sfx.cardLand : null, // don't machine-gun the sfx
      ));
    }
    _flights.fly(specs);
  }

  void _runThrow(StartedStep started) {
    final event = started.step.event;
    if (event is! CardsThrownEvent) return;
    final pile = _anchors.pileRect;
    final mySeat = started.before.mySeat;
    final from = _anchors.originForSeat(event.seat, mySeat);
    if (pile == null || from == null) return;

    _haptics.light();
    final pileBefore = event.isLead ? 0 : started.before.pileCount;
    final stepMs = max(1, started.step.baseDuration.inMilliseconds);
    final specs = <CardFlightSpec>[];
    for (var i = 0; i < event.count; i++) {
      // Land in the exact pose the pile stack will draw for this card.
      final pose = pileEntryPose(
          min(pileBefore + i, MotionSpec.pileRenderCap - 1));
      specs.add(CardFlightSpec(
        from: from,
        to: pile.shift(pose.offset),
        delay: _at(started,
            MotionSpec.throwStagger.inMilliseconds * i / stepMs),
        duration:
            _at(started, MotionSpec.cardFlight.inMilliseconds / stepMs),
        width: 48,
        spinTurns: MotionSpec.throwSpinTurns,
        endRotation: pose.angle,
        landingJitter: Offset.zero, // the pose already carries the mess
        onLand: () {
          _sfx.cardLand();
          _haptics.light();
        },
      ));
      _sfx.cardThrow();
    }
    _flights.fly(specs);

    _spawnCallout(
      seat: event.seat,
      mySeat: mySeat,
      text: Strings.claimCallout(event.count, event.rank),
    );
    _sfx.claimStamp();
  }

  void _runPickup(StartedStep started) {
    final event = started.step.event;
    if (event is! CheckResultEvent) return;
    final pile = _anchors.pileRect;
    final mySeat = started.before.mySeat;
    final to = _anchors.originForSeat(event.pickerSeat, mySeat);
    if (pile == null || to == null) return;

    _sfx.pilePickup();
    if (event.pickerSeat == mySeat) _haptics.medium();

    final flights = min(event.pickedCount, MotionSpec.pileRenderCap);
    final stepMs = max(1, started.step.baseDuration.inMilliseconds);
    _flights.fly([
      for (var i = 0; i < flights; i++)
        CardFlightSpec(
          from: pile.shift(pileEntryPose(i).offset),
          to: to,
          delay: _at(started,
              MotionSpec.pickupStagger.inMilliseconds * i / stepMs),
          duration:
              _at(started, MotionSpec.pickupBase.inMilliseconds / stepMs),
          width: 44,
          curve: MotionSpec.pickupFlightCurve, // accelerating converge
          spinTurns: 0.25,
        ),
    ]);
  }

  void _runPlayerOut(StartedStep started) {
    final event = started.step.event;
    if (event is! PlayerOutEvent) return;
    _haptics.success();
    _spawnCallout(
      seat: event.seat,
      mySeat: started.before.mySeat,
      text: Strings.safeCallout,
      color: const Color(0xFF2E7D32),
    );
  }

  void _spawnCallout({
    required int seat,
    required int mySeat,
    required String text,
    Color? color,
  }) {
    final rect = _anchors.originForSeat(seat, mySeat);
    if (rect == null || ref.read(animationSpeedProvider).isOff) return;
    final id = _calloutIds++;
    setState(() {
      _callouts.add(_Callout(
        id: id,
        position: rect.bottomCenter + const Offset(0, 4),
        text: text,
        color: color,
      ));
    });
  }

  void _removeCallout(int id) {
    if (!mounted) return;
    setState(() => _callouts.removeWhere((c) => c.id == id));
  }

  void _onReaction(ReactionMessage r) {
    if (ref.read(animationSpeedProvider).isOff) return;
    final mySeat = ref.read(renderedGameStateProvider).mySeat;
    final rect = _anchors.originForSeat(r.seat, mySeat);
    if (rect == null) return;
    _sfx.reactionPop();
    _bursts.burst(
        Strings.reactionEmoji[r.emoji] ?? r.emoji, rect.topCenter);
  }

  // -- Build ------------------------------------------------------------------

  Offset _layerOrigin() {
    final box = context.findRenderObject() as RenderBox?;
    return (box != null && box.attached)
        ? box.localToGlobal(Offset.zero)
        : Offset.zero;
  }

  @override
  Widget build(BuildContext context) {
    final origin = _layerOrigin();
    final reveal = _reveal;
    final quad = _quad;
    final gameOver = _gameOver;

    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        if (reveal != null && reveal.step.event is CheckResultEvent)
          RevealOverlay(
            event: reveal.step.event! as CheckResultEvent,
            cardCount: max(
                reveal.before.lastThrowCount,
                (reveal.step.event! as CheckResultEvent).flipIndex + 1),
            duration: reveal.duration,
            sfx: _sfx,
            haptics: _haptics,
            onVerdict: () {
              final e = reveal.step.event! as CheckResultEvent;
              if (!e.matched) {
                _anchors.shake.value = SeatShake(e.targetSeat);
              }
            },
            onDone: () {
              if (mounted && _reveal == reveal) setState(() => _reveal = null);
            },
          ),
        if (quad != null && quad.step.event is FourDiscardedEvent)
          QuadCelebration(
            event: quad.step.event! as FourDiscardedEvent,
            duration: quad.duration,
            fromRect: _anchors.originForSeat(
                (quad.step.event! as FourDiscardedEvent).seat,
                quad.before.mySeat),
            railRect: _anchors.retiredRect,
            onDone: () {
              if (mounted && _quad == quad) setState(() => _quad = null);
            },
          ),
        if (gameOver != null && gameOver.step.event is GameOverEvent)
          GameOverOverlay(
            event: gameOver.step.event! as GameOverEvent,
            loserName: gameOver.before.nicknameAtSeat(
                (gameOver.step.event! as GameOverEvent).loserSeat),
            duration: gameOver.duration,
            fromRect: _anchors.seatRect(
                (gameOver.step.event! as GameOverEvent).loserSeat),
            onDone: () {
              if (mounted && _gameOver == gameOver) {
                setState(() => _gameOver = null);
              }
            },
          ),
        CardFlightLayer(controller: _flights),
        for (final callout in _callouts)
          Positioned(
            left: callout.position.dx - origin.dx - 70,
            top: callout.position.dy - origin.dy,
            width: 140,
            child: IgnorePointer(
              child: Center(
                child: ClaimCallout(
                  text: callout.text,
                  color: callout.color,
                  speedFactor: max(
                      0.001, ref.watch(animationSpeedProvider).factor),
                  onDone: () => _removeCallout(callout.id),
                ),
              ),
            ),
          ),
        EmojiBurstLayer(controller: _bursts),
      ],
    );
  }
}
