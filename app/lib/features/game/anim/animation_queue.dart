/// The pacing layer between the TRUE game state and the RENDERED game state.
///
/// Server event batches mutate the true state instantly (input gating and
/// legality read that). The same events are also mapped to timed [AnimStep]s
/// and enqueued here; the RENDERED state only advances as steps complete, so
/// a check reveal plays out over seconds even though the client already knows
/// the outcome.
///
/// Contract:
/// * Steps run strictly sequentially, in enqueue order.
/// * A step's [AnimStep.apply] is its FULL effect, always computed from the
///   state as it was when the step started. Optional [AnimStep.ticks] are
///   cosmetic interpolations (a count chip ticking per landing card); the
///   final apply overwrites them, so rendered state provably converges with
///   the true fold no matter what ticks did.
/// * [skipToEnd] applies every remaining effect instantly (tap-anywhere skip).
/// * When the speed factor is 0 (reduce motion), every step is instant.
library;

import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../core/motion/animation_speed.dart';
import '../../../core/net/client_game_state.dart';
import '../../../core/net/protocol_models.dart';

/// What kind of choreography a step drives; the visual layer dispatches on it.
enum StepKind {
  deal,
  throwCards,
  reveal,
  pickup,
  quad,
  playerOut,
  gameOver,
  instant,
}

/// A cosmetic sub-mutation inside a step, at fraction [at] (0..1) of the
/// step's scaled duration.
class StepTick {
  const StepTick(this.at, this.apply);

  final double at;
  final ClientGameState Function(ClientGameState) apply;
}

/// One unit of choreography in the queue.
class AnimStep {
  AnimStep({
    required this.kind,
    required this.baseDuration,
    required this.apply,
    this.event,
    this.ticks = const [],
  });

  /// A 0 ms step: full effect, no choreography. Unknown events map to this.
  AnimStep.instant(this.apply, {this.event})
      : kind = StepKind.instant,
        baseDuration = Duration.zero,
        ticks = const [];

  final StepKind kind;

  /// The wire event that produced this step, for the visual layer.
  final WireEvent? event;

  /// Un-scaled duration; the queue multiplies through the current speed.
  final Duration baseDuration;

  /// Full effect of the step (from its start state).
  final ClientGameState Function(ClientGameState) apply;

  /// Cosmetic interpolation ticks, sorted ascending by [StepTick.at].
  final List<StepTick> ticks;
}

/// Snapshot handed to the visual layer when a step begins.
class StartedStep {
  StartedStep({
    required this.step,
    required this.before,
    required this.after,
    required this.duration,
  });

  final AnimStep step;

  /// Rendered state at step start / after full application.
  final ClientGameState before;
  final ClientGameState after;

  /// Speed-scaled wall duration of the step.
  final Duration duration;
}

class AnimationQueue {
  AnimationQueue({
    required AnimationSpeed Function() speedOf,
    ClientGameState initial = ClientGameState.empty,
  })  : _speedOf = speedOf, // ignore: prefer_initializing_formals
        _rendered = initial;

  final AnimationSpeed Function() _speedOf;

  ClientGameState _rendered;
  final Queue<AnimStep> _pending = Queue();

  AnimStep? _current;
  StartedStep? _currentStarted;
  ClientGameState? _stepBefore;
  final List<Timer> _timers = [];

  final _startedCtrl = StreamController<StartedStep>.broadcast();
  final _skippedCtrl = StreamController<void>.broadcast();

  /// Fired when a timed step begins — the visual layer starts flights and
  /// overlays off this, matching [StartedStep.duration].
  Stream<StartedStep> get onStepStarted => _startedCtrl.stream;

  /// Fired on [skipToEnd] so in-flight visuals can be dismissed.
  Stream<void> get onSkipped => _skippedCtrl.stream;

  /// Called after every rendered-state change (and busy-flag change).
  VoidCallback? onChanged;

  ClientGameState get rendered => _rendered;
  bool get busy => _current != null || _pending.isNotEmpty;

  /// The step currently playing, if any — lets a late-mounting visual layer
  /// pick up an in-progress set piece.
  StartedStep? get current => _currentStarted;

  void enqueue(Iterable<AnimStep> steps) {
    _pending.addAll(steps);
    _pump();
  }

  /// Authoritative jump (stateFull resync): drop everything, render [state].
  void syncTo(ClientGameState state) {
    _cancelTimers();
    _pending.clear();
    _current = null;
    _currentStarted = null;
    _stepBefore = null;
    _rendered = state;
    _notify();
  }

  /// Tap-anywhere skip: complete the current step and drain the queue
  /// instantly. Rendered state lands exactly where it would have.
  void skipToEnd() {
    if (!busy) return;
    _cancelTimers();
    final current = _current;
    if (current != null) {
      _rendered = current.apply(_stepBefore!);
      _current = null;
      _currentStarted = null;
      _stepBefore = null;
    }
    while (_pending.isNotEmpty) {
      _rendered = _pending.removeFirst().apply(_rendered);
    }
    _skippedCtrl.add(null);
    _notify();
  }

  void dispose() {
    _cancelTimers();
    _startedCtrl.close();
    _skippedCtrl.close();
  }

  /// Catch-up valve: if the true game races far ahead (burst of batches on
  /// reconnect, several instant opponents), pending choreography must not pile
  /// up unboundedly. Steps play at half speed budget behind this backlog...
  static const fastForwardBacklog = 4;

  /// ...and are snapped instantly behind this one.
  static const snapBacklog = 10;

  Duration _catchUpScale(Duration d) {
    if (_pending.length >= snapBacklog) return Duration.zero;
    if (_pending.length >= fastForwardBacklog) return d * 0.5;
    return d;
  }

  void _pump() {
    // Drain instant (and reduce-motion-collapsed) steps synchronously.
    while (_current == null && _pending.isNotEmpty) {
      final step = _pending.removeFirst();
      final duration = _catchUpScale(_speedOf().scale(step.baseDuration));
      if (duration <= Duration.zero) {
        _rendered = step.apply(_rendered);
        _notify();
        continue;
      }
      _start(step, duration);
    }
  }

  void _start(AnimStep step, Duration duration) {
    final before = _rendered;
    _current = step;
    _stepBefore = before;
    final started = StartedStep(
      step: step,
      before: before,
      after: step.apply(before),
      duration: duration,
    );
    _currentStarted = started;

    for (final tick in step.ticks) {
      _timers.add(Timer(duration * tick.at, () {
        _rendered = tick.apply(_rendered);
        _notify();
      }));
    }
    _timers.add(Timer(duration, () {
      _cancelTimers();
      // Final apply is from the step-start state: ticks are cosmetic only.
      _rendered = step.apply(before);
      _current = null;
      _currentStarted = null;
      _stepBefore = null;
      _notify();
      _pump();
    }));

    _startedCtrl.add(started);
    _notify(); // busy flag flipped
  }

  void _cancelTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  void _notify() => onChanged?.call();
}
