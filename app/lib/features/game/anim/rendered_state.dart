/// The RENDERED game state: what the table actually draws.
///
/// [GameStateNotifier] (core/net) stays the TRUE state — batches applied
/// instantly, used for input gating and legality. This notifier feeds the
/// same messages through an [AnimationQueue] so the rendered projection
/// advances only as animation steps complete.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/motion/animation_speed.dart';
import '../../../core/net/connection_providers.dart';
import '../../../core/net/state_folding.dart';
import 'animation_queue.dart';
import 'event_steps.dart';

final renderedGameStateProvider =
    NotifierProvider<RenderedGameStateNotifier, ClientGameState>(
        RenderedGameStateNotifier.new);

/// True while the queue is playing steps — the table locks inputs and treats
/// any tap as skip-to-end during this window.
final animationBusyProvider =
    NotifierProvider<AnimationBusyNotifier, bool>(AnimationBusyNotifier.new);

class AnimationBusyNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) {
    if (state != value) state = value;
  }
}

/// The queue itself, for the visual layer (step-start stream, skip).
final animationQueueProvider = Provider<AnimationQueue>(
    (ref) => ref.watch(renderedGameStateProvider.notifier).queue);

class RenderedGameStateNotifier extends Notifier<ClientGameState> {
  AnimationQueue? _queue;
  bool _building = false;

  AnimationQueue get queue => _queue ??= AnimationQueue(
        speedOf: () => ref.read(animationSpeedProvider),
      )..onChanged = _onQueueChanged;

  @override
  ClientGameState build() {
    _building = true;
    try {
      final q = queue;
      final room = ref.watch(currentRoomProvider);
      if (room == null) {
        q.syncTo(ClientGameState.empty);
        return ClientGameState.empty;
      }

      final subs = <StreamSubscription<dynamic>>[
        room.onStateFull.listen(_onStateFull),
        room.onHand.listen(_onHand),
        room.onEvents.listen(_onEvents),
      ];
      ref.onDispose(() {
        for (final s in subs) {
          s.cancel();
        }
      });

      final snapshot = room.lastState;
      final initial = snapshot == null
          ? ClientGameState.empty
          : foldStateFull(snapshot, myUserId: _myUserId, previous: q.rendered);
      q.syncTo(initial);
      return initial;
    } finally {
      _building = false;
    }
  }

  String? get _myUserId => ref.read(sessionProvider)?.userId;

  void _onQueueChanged() {
    if (_building) return;
    state = queue.rendered;
    ref.read(animationBusyProvider.notifier).set(queue.busy);
  }

  void _onStateFull(StateFull s) {
    if (queue.busy) {
      // A resync while choreography is playing (e.g. the room snapping back
      // to lobby right after gameOver) must not clobber the running set
      // piece — adopt the snapshot as the final step of the queue instead.
      queue.enqueue([
        AnimStep.instant(
            (prev) => foldStateFull(s, myUserId: _myUserId, previous: prev)),
      ]);
      return;
    }
    // Authoritative resync: jump.
    queue.syncTo(
        foldStateFull(s, myUserId: _myUserId, previous: queue.rendered));
  }

  void _onHand(HandSnapshot h) => queue.enqueue([handSnapshotStep(h)]);

  void _onEvents(EventBatch batch) =>
      queue.enqueue(stepsForBatch(batch, myUserId: _myUserId));

  /// Tap-anywhere skip.
  void skipAnimations() => queue.skipToEnd();
}
