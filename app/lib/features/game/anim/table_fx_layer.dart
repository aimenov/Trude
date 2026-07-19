/// The choreographer: listens to the AnimationQueue's step-start stream and
/// drives every visual set piece — card flights, claim callouts, the reveal /
/// quad / game-over overlays, and emoji reaction bursts — with matching
/// sfx/haptics hooks. Sits topmost in the table Stack, fully input-transparent.
library;

import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/audio/sfx_service.dart';
import '../../../core/theme/trude_theme.dart';
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
      case StepKind.hold:
        break;
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
    final stepMs = max(1, started.step.baseDuration.inMilliseconds);
    final specs = <CardFlightSpec>[];
    for (var i = 0; i < event.count; i++) {
      // Land in the exact laid-down row pose the pile stack will draw.
      final pose = lastThrowRowPose(i, event.count);
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

    // The laid-down row lifts off first, then cards from the messy heap.
    final lastN = started.before.lastThrowCount;
    final flights = min(event.pickedCount, MotionSpec.pileRenderCap);
    final stepMs = max(1, started.step.baseDuration.inMilliseconds);
    _flights.fly([
      for (var i = 0; i < flights; i++)
        CardFlightSpec(
          from: pile.shift((i < lastN
                  ? lastThrowRowPose(i, lastN)
                  : pileEntryPose(i - lastN))
              .offset),
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
      color: TrudeColors.truth,
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
            // Per-step identity: back-to-back reveals must get a fresh State
            // (a reused Element would never re-run initState/forward()).
            key: ObjectKey(reveal),
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
            // Per-step identity: without it, back-to-back quads reuse the
            // State, the controller stays at 1.0 and the square parks forever.
            key: ObjectKey(quad),
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
            // Per-step identity, same latent bug class as the quad above.
            key: ObjectKey(gameOver),
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
        RepaintBoundary(child: CardFlightLayer(controller: _flights)),
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
        RepaintBoundary(child: EmojiBurstLayer(controller: _bursts)),
      ],
    );
  }
}

// =============================================================================
// The parlor environment: full-bleed candle-lit felt behind the whole table.
// =============================================================================

/// Full-bleed felt with candlelight idle life: the warm light pool's center
/// drifts and its radius breathes (±2 %, ~7 s period, [TableMotionSpec]).
/// Everything static — procedural felt grain, the vignette to midnight, the
/// mahogany rail framing the play area, and the etched TRUDE monogram — is
/// recorded once per size into a [ui.Picture] and replayed each frame, so the
/// flicker only repaints two gradients.
class TableFeltBackground extends StatefulWidget {
  const TableFeltBackground({super.key, required this.speed});

  final AnimationSpeed speed;

  @override
  State<TableFeltBackground> createState() => _TableFeltBackgroundState();
}

class _TableFeltBackgroundState extends State<TableFeltBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flicker = AnimationController(
      vsync: this, duration: TableMotionSpec.feltFlickerPeriod);
  final _layers = _FeltStaticLayers();

  @override
  void initState() {
    super.initState();
    _syncTicker();
  }

  @override
  void didUpdateWidget(TableFeltBackground old) {
    super.didUpdateWidget(old);
    if (old.speed != widget.speed) _syncTicker();
  }

  void _syncTicker() {
    if (widget.speed.isOff) {
      _flicker.stop();
    } else if (!_flicker.isAnimating) {
      _flicker.repeat();
    }
  }

  @override
  void dispose() {
    _flicker.dispose();
    _layers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _flicker,
        builder: (context, _) => CustomPaint(
          isComplex: true,
          painter: _FeltPainter(
            // Quantized to feltFlickerSteps so shouldRepaint rejects frames
            // between steps — the two full-screen gradients repaint at
            // period/steps (~10 Hz) instead of every vsync.
            phase: (_flicker.value * TableMotionSpec.feltFlickerSteps)
                    .floor() /
                TableMotionSpec.feltFlickerSteps,
            layers: _layers,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

/// One-time recording of the felt's static layers (grain, monogram, vignette,
/// rail), invalidated only when the canvas size changes.
class _FeltStaticLayers {
  ui.Picture? _picture;
  Size? _size;

  ui.Picture layersFor(Size size) {
    final cached = _picture;
    if (cached != null && _size == size) return cached;
    _picture?.dispose();
    final recorder = ui.PictureRecorder();
    _record(Canvas(recorder), size);
    final picture = recorder.endRecording();
    _picture = picture;
    _size = size;
    return picture;
  }

  void dispose() {
    _picture?.dispose();
    _picture = null;
  }

  void _record(Canvas canvas, Size size) {
    _paintGrain(canvas, size);
    _paintMonogram(canvas, size);
    _paintVignette(canvas, size);
    _paintRail(canvas, size);
  }

  /// Cheap seeded felt texture: dark specks and pale fibers, sparse enough to
  /// read as nap rather than noise.
  void _paintGrain(Canvas canvas, Size size) {
    final rng = Random(1907); // deterministic — recorded once
    final count = min(1800, (size.width * size.height) ~/ 420);
    for (var i = 0; i < count; i++) {
      final pos = Offset(
          rng.nextDouble() * size.width, rng.nextDouble() * size.height);
      if (rng.nextDouble() < 0.6) {
        final speck = Paint()
          ..color = TrudeColors.midnight
              .withValues(alpha: 0.03 + rng.nextDouble() * 0.04);
        canvas.drawCircle(pos, 0.4 + rng.nextDouble() * 0.8, speck);
      } else {
        // A short fiber lying in a random direction.
        final angle = rng.nextDouble() * pi;
        final len = 2.5 + rng.nextDouble() * 4;
        final fiber = Paint()
          ..strokeWidth = 0.6
          ..color = TrudeColors.ivory
              .withValues(alpha: 0.015 + rng.nextDouble() * 0.02);
        canvas.drawLine(
            pos, pos + Offset(cos(angle), sin(angle)) * len, fiber);
      }
    }
  }

  /// A faint "TRUDE" etched into the felt under the pile, ringed like an
  /// engraving on the cloth.
  void _paintMonogram(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.42);
    final fontSize = size.width * 0.15;

    // Recess shadow first, then the brass etch on top.
    for (final (color, dy) in [
      (TrudeColors.midnight.withValues(alpha: 0.10), 1.5),
      (TrudeColors.brass.withValues(alpha: 0.06), 0.0),
    ]) {
      final tp = TextPainter(
        text: TextSpan(
          text: 'TRUDE',
          style: TrudeType.display.copyWith(
            fontSize: fontSize,
            color: color,
            letterSpacing: size.width * 0.02,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
          canvas,
          center -
              Offset(tp.width / 2 - size.width * 0.01, tp.height / 2 - dy));
    }

    // Etched halo ellipse around the word.
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = TrudeColors.brass.withValues(alpha: 0.045);
    canvas.drawOval(
        Rect.fromCenter(
            center: center,
            width: size.width * 0.78,
            height: fontSize * 2.4),
        halo);
  }

  void _paintVignette(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final vignette = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.15),
        radius: 1.25,
        colors: [
          TrudeColors.midnight.withValues(alpha: 0.0),
          TrudeColors.midnight.withValues(alpha: 0.0),
          TrudeColors.midnight.withValues(alpha: 0.65),
        ],
        stops: const [0.0, 0.58, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  /// The mahogany rail hugging the screen edge, with a brass beading hairline
  /// and an inner contact shadow onto the felt.
  void _paintRail(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rail = RRect.fromRectAndRadius(
        rect.deflate(5), const Radius.circular(26));

    // Contact shadow the rail casts onto the felt.
    final contact = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4)
      ..color = TrudeColors.midnight.withValues(alpha: 0.45);
    canvas.drawRRect(rail.deflate(2), contact);

    final wood = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          TrudeColors.railWoodLit,
          TrudeColors.railWood,
          TrudeColors.railWoodLit,
        ],
        stops: [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRRect(rail, wood);

    // Lit top edge of the rail and the brass beading on its inner lip.
    final edgeLight = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = TrudeColors.railWoodLit.withValues(alpha: 0.8);
    canvas.drawRRect(rail.inflate(4.5), edgeLight);
    final beading = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = TrudeDims.hairlineWidth
      ..color = TrudeColors.brass.withValues(alpha: 0.22);
    canvas.drawRRect(rail.deflate(5), beading);
  }
}

class _FeltPainter extends CustomPainter {
  _FeltPainter({required this.phase, required this.layers});

  /// 0..1 through one flicker period.
  final double phase;
  final _FeltStaticLayers layers;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final a = phase * 2 * pi;

    // Candlelight: layered sinusoids so the drift never reads as a loop.
    const drift = TableMotionSpec.feltFlickerDriftAmp;
    final cx = sin(a) * drift + sin(a * 3 + 1.3) * drift * 0.4;
    final cy = -0.15 + cos(a * 2 + 0.7) * drift * 0.6;
    final radius = 1.15 *
        (1 +
            TableMotionSpec.feltFlickerRadiusDelta *
                (sin(a * 3 + 0.5) * 0.7 + sin(a * 7 + 2.1) * 0.3));

    // The felt light pool — TrudeGradients.feltLight with an animated
    // center/radius (same colors and stops).
    final felt = Paint()
      ..shader = RadialGradient(
        center: Alignment(cx, cy),
        radius: radius,
        colors: const [
          TrudeColors.feltLit,
          TrudeColors.felt,
          TrudeColors.feltDeep,
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, felt);

    // A whisper of candle warmth pooled at the light center.
    final warmth = Paint()
      ..shader = RadialGradient(
        center: Alignment(cx, cy),
        radius: radius * 0.5,
        colors: [
          TrudeColors.brassBright
              .withValues(alpha: 0.045 + 0.015 * sin(a * 5 + 0.9)),
          TrudeColors.brassBright.withValues(alpha: 0.0),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, warmth);

    canvas.drawPicture(layers.layersFor(size));
  }

  @override
  bool shouldRepaint(_FeltPainter old) => old.phase != phase;
}
