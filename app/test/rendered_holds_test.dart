// Optimistic throw holds on the RENDERED state (plan fix 2):
// * holdCards hides the held ids from rendered.myHand,
// * a hand snapshot without those ids applying self-cleans the hold,
// * releaseHold (rejection rollback) restores the cards,
// * a stateFull resync clears every hold (authoritative rollback).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/net/client_game_state.dart';
import 'package:trude/core/net/protocol_models.dart';
import 'package:trude/features/game/anim/event_steps.dart';
import 'package:trude/features/game/anim/rendered_state.dart';

Card _card(String id, String rank) => Card(id: id, rank: rank, suit: 'H');

final _hand = [
  _card('c1', '7'),
  _card('c2', '7'),
  _card('c3', 'K'),
  _card('c4', 'A'),
];

List<String> _ids(ClientGameState s) => [for (final c in s.myHand) c.id];

StateFull _stateFull(List<Card> hand) => StateFull.fromJson({
      'actionCount': 5,
      'phase': 'playing',
      'config': {'deckSize': 37, 'turnTimerSec': 30, 'maxPlayers': 6},
      'roomCode': 'ABCD',
      'players': <Map<String, dynamic>>[],
      'pile': {'rank': null, 'totalCount': 0, 'groups': <Map<String, dynamic>>[]},
      'lastThrowSeat': null,
      'mustCheck': false,
      'retiredRanks': <String>[],
      'discarded': <Map<String, dynamic>>[],
      'turn': null,
      'hand': [
        for (final c in hand) {'id': c.id, 'rank': c.rank, 'suit': c.suit},
      ],
      'lastResolution': null,
      'loserSeat': null,
    });

void main() {
  late ProviderContainer container;
  late RenderedGameStateNotifier notifier;

  ClientGameState rendered() => container.read(renderedGameStateProvider);

  setUp(() {
    container = ProviderContainer();
    notifier = container.read(renderedGameStateProvider.notifier);
    // Seed a hand through the queue, exactly like a hand snapshot would land.
    notifier.queue
        .enqueue([handSnapshotStep(HandSnapshot(cards: List.of(_hand)))]);
    expect(_ids(rendered()), ['c1', 'c2', 'c3', 'c4']);
  });

  tearDown(() => container.dispose());

  test('holdCards hides the held cards from the rendered hand', () {
    notifier.holdCards(1, ['c1', 'c2']);
    expect(_ids(rendered()), ['c3', 'c4']);

    // Independent holds stack.
    notifier.holdCards(2, ['c4']);
    expect(_ids(rendered()), ['c3']);
  });

  test('a hand snapshot without the held ids self-cleans the hold', () {
    notifier.holdCards(1, ['c1', 'c2']);
    expect(_ids(rendered()), ['c3', 'c4']);

    // Confirmed throw: the server's post-throw hand no longer has c1/c2.
    notifier.queue.enqueue([
      handSnapshotStep(HandSnapshot(cards: [_card('c3', 'K'), _card('c4', 'A')]))
    ]);
    expect(_ids(rendered()), ['c3', 'c4']);

    // The hold is gone, not just masked: if c1 ever comes back (picked up
    // again later), it renders normally.
    notifier.queue.enqueue([
      handSnapshotStep(HandSnapshot(
          cards: [_card('c1', '7'), _card('c3', 'K'), _card('c4', 'A')]))
    ]);
    expect(_ids(rendered()), ['c1', 'c3', 'c4']);
  });

  test('releaseHold restores the held cards (rejection rollback)', () {
    notifier.holdCards(7, ['c1', 'c2']);
    expect(_ids(rendered()), ['c3', 'c4']);

    notifier.releaseHold(7);
    expect(_ids(rendered()), ['c1', 'c2', 'c3', 'c4']);
  });

  test('a stateFull resync clears all holds', () {
    notifier.holdCards(1, ['c1']);
    notifier.holdCards(2, ['c2']);
    expect(_ids(rendered()), ['c3', 'c4']);

    // Authoritative snapshot still contains every card: holds must not
    // survive it, even the ones whose ids are present.
    notifier.debugOnStateFull(_stateFull(_hand));
    expect(_ids(rendered()), ['c1', 'c2', 'c3', 'c4']);

    // And the cleared holds stay cleared for subsequent queue changes.
    notifier.queue
        .enqueue([handSnapshotStep(HandSnapshot(cards: List.of(_hand)))]);
    expect(_ids(rendered()), ['c1', 'c2', 'c3', 'c4']);
  });
}
