/// The RENDERED game state: what the table actually draws.
///
/// [GameStateNotifier] (core/net) stays the TRUE state — batches applied
/// instantly, used for input gating and legality. This notifier feeds the
/// same messages through an [AnimationQueue] so the rendered projection
/// advances only as animation steps complete.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
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

  /// Optimistic throw holds: clientSeq -> card ids hidden from the rendered
  /// hand while the throw awaits the server's verdict. Released explicitly on
  /// rejection, self-cleaned when a hand snapshot without those ids applies,
  /// cleared wholesale by an authoritative stateFull resync.
  final Map<int, List<String>> _holds = {};

  AnimationQueue get queue => _queue ??= AnimationQueue(
        speedOf: () => ref.read(animationSpeedProvider),
      )..onChanged = _onQueueChanged;

  @override
  ClientGameState build() {
    _building = true;
    try {
      final q = queue;
      _holds.clear(); // a room change invalidates any pending optimism
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
      return _project(initial);
    } finally {
      _building = false;
    }
  }

  String? get _myUserId => ref.read(sessionProvider)?.userId;

  // -- Optimistic throw holds ---------------------------------------------------

  /// Hides [cardIds] from the rendered hand until the throw keyed by
  /// [clientSeq] is confirmed (the ids vanish from a hand snapshot) or
  /// rejected ([releaseHold]).
  void holdCards(int clientSeq, List<String> cardIds) {
    _holds[clientSeq] = List.of(cardIds);
    _publish();
  }

  /// Rollback: the throw keyed by [clientSeq] was rejected — the held cards
  /// return to the rendered hand.
  void releaseHold(int clientSeq) {
    if (_holds.remove(clientSeq) != null) _publish();
  }

  /// The rendered projection: the queue's state with every held card filtered
  /// out of my hand. Holds whose ids have all left the underlying hand are
  /// stale (the post-throw hand snapshot applied) and self-clean here.
  ClientGameState _project(ClientGameState s) {
    if (_holds.isEmpty) return s;
    bool inHand(String id) => s.myHand.any((c) => c.id == id);
    _holds.removeWhere((_, ids) => !ids.any(inHand));
    if (_holds.isEmpty) return s;
    final held = {for (final ids in _holds.values) ...ids};
    return s.copyWith(
        myHand: [
          for (final c in s.myHand)
            if (!held.contains(c.id)) c
        ]);
  }

  void _publish() {
    if (_building) return;
    state = _project(queue.rendered);
  }

  void _onQueueChanged() {
    if (_building) return;
    state = _project(queue.rendered);
    ref.read(animationBusyProvider.notifier).set(queue.busy);
  }

  void _onStateFull(StateFull s) {
    // An authoritative resync is also the rollback of last resort: whatever
    // the server says my hand is, that is my hand — drop every hold.
    _holds.clear();
    if (queue.busy) {
      // A resync while choreography is playing (e.g. the room snapping back
      // to lobby right after gameOver) must not clobber the running set
      // piece — adopt the snapshot as the final step of the queue instead.
      queue.enqueue([
        AnimStep.instant(
            (prev) => foldStateFull(s, myUserId: _myUserId, previous: prev)),
      ]);
      _publish(); // un-hide held cards now; the snapshot applies at queue end
      return;
    }
    // Authoritative resync: jump.
    queue.syncTo(
        foldStateFull(s, myUserId: _myUserId, previous: queue.rendered));
  }

  /// Test seam: feeds a `stateFull` exactly as the room stream would.
  @visibleForTesting
  void debugOnStateFull(StateFull s) => _onStateFull(s);

  void _onHand(HandSnapshot h) => queue.enqueue([handSnapshotStep(h)]);

  void _onEvents(EventBatch batch) =>
      queue.enqueue(stepsForBatch(batch, myUserId: _myUserId));

  /// Tap-anywhere skip.
  void skipAnimations() => queue.skipToEnd();
}
