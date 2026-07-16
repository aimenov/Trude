@Tags(['integration'])
library;

// End-to-end transport acceptance test: three random-policy bots play a full
// game of Trude over the real Colyseus wire protocol against a locally
// running server. Auto-skips when the server is down.
//
// Start the server first:
//   cd <repo>; $env:PORT='2567'; npx tsx packages/server/src/index.ts
//
// Override the endpoint with --dart-define=TRUDE_SERVER=http://host:port

import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:trude/core/net/trude_client.dart';

const _baseUrl =
    String.fromEnvironment('TRUDE_SERVER', defaultValue: 'http://127.0.0.1:2567');

const _ranks37 = ['6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
const _ranks53 = [
  '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A',
];

Future<bool> _serverUp() async {
  try {
    final res = await http
        .get(Uri.parse('$_baseUrl/health'))
        .timeout(const Duration(seconds: 2));
    return res.statusCode == 200;
  } catch (_) {
    return false;
  }
}

/// A randomized legal-move bot. Randomness matters: deterministic policies
/// livelock this game (e.g. never checking means the joker never surfaces).
class Bot {
  Bot(this.name, this.userId, this.room, this.rng) {
    _subs.add(room.onHand.listen((h) => hand = h.cards));
    _subs.add(room.onError.listen(errors.add));
    _subs.add(room.onProtocolError.listen(protocolErrors.add));
    _subs.add(room.onStateFull.listen((s) {
      for (final p in s.players) {
        if (p.userId == userId) seat = p.seat;
      }
      deckSize = s.config.deckSize;
      retired
        ..clear()
        ..addAll(s.retiredRanks);
      hand = s.hand;
    }));
    _subs.add(room.onEvents.listen(_onBatch));
  }

  final String name;
  final String userId;
  final TrudeRoom room;
  final Random rng;

  int seat = -1;
  int deckSize = 37;
  List<Card> hand = const [];
  final Set<String> retired = {};

  /// Size of the most recent throw — bounds `check.flipIndex`.
  int lastThrowCount = 0;

  final List<GameError> errors = [];
  final List<RoomProtocolError> protocolErrors = [];
  final Completer<GameOverEvent> gameOver = Completer<GameOverEvent>();
  final _subs = <StreamSubscription<dynamic>>[];

  void _onBatch(EventBatch batch) {
    for (final e in batch.events) {
      switch (e) {
        case GameStartedEvent():
          deckSize = e.deckSize;
          retired.clear();
          for (final so in e.seatOrder) {
            if (so.userId == userId) seat = so.seat;
          }
        case CardsThrownEvent():
          lastThrowCount = e.count;
        case FourDiscardedEvent():
          retired.add(e.rank);
        case GameOverEvent():
          if (!gameOver.isCompleted) gameOver.complete(e);
        case TurnStartedEvent()
            when e.seat == seat && !gameOver.isCompleted:
          _act(e);
        default:
          break;
      }
    }
  }

  void _act(TurnStartedEvent turn) {
    // The private 'hand' snapshot always arrives before the events batch on
    // the same socket, so `hand` is current here.
    final wantsCheck =
        turn.phase == 'respond' && (turn.mustCheck || rng.nextInt(3) == 0);
    if (wantsCheck && lastThrowCount > 0) {
      room.check(rng.nextInt(min(lastThrowCount, 3)));
      return;
    }
    if (hand.isEmpty) return; // out players never get turns; safety only

    final picked = ([...hand]..shuffle(rng))
        .take(min(1 + rng.nextInt(3), hand.length))
        .toList();

    String? rank;
    if (turn.phase == 'lead') {
      // Leading requires a claimed rank: the true rank of the first thrown
      // card unless it's the joker or retired, else any live rank.
      final first = picked.first.rank;
      if (first != 'JOKER' && !retired.contains(first)) {
        rank = first;
      } else {
        final live = (deckSize == 53 ? _ranks53 : _ranks37)
            .where((r) => !retired.contains(r))
            .toList();
        rank = live[rng.nextInt(live.length)];
      }
    }
    room.throwCards(picked.map((c) => c.id).toList(), rank: rank);
  }

  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    try {
      await room.leave().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }
}

Future<void> main() async {
  final up = await _serverUp();

  test(
    'three bots play a full game to gameOver over the real transport',
    () async {
      final rng = Random();
      final runTag = rng.nextInt(1 << 30);
      final clients = <TrudeClient>[];
      final bots = <Bot>[];
      try {
        // 1. Three guest users over HTTP.
        final sessions = <GuestSession>[];
        for (var i = 0; i < 3; i++) {
          final client = TrudeClient(_baseUrl);
          clients.add(client);
          sessions.add(await client.guestLogin(
            deviceId: 'it-$runTag-$i',
            nickname: 'Bot${['One', 'Two', 'Three'][i]}',
          ));
        }

        // 2. Admin creates the room; the other two join by roomId.
        final adminRoom = await clients[0].createRoom(name: 'transport-it');
        bots.add(Bot('Bot0', sessions[0].userId, adminRoom, Random(rng.nextInt(1 << 32))));
        final roomId = adminRoom.roomId;
        for (var i = 1; i < 3; i++) {
          final room = await clients[i].joinRoomById(roomId);
          bots.add(Bot('Bot$i', sessions[i].userId, room, Random(rng.nextInt(1 << 32))));
        }
        expect(adminRoom.reconnectionToken, isNotNull);

        // Everyone has their join snapshot before the game starts.
        final states =
            await Future.wait(bots.map((b) => b.room.firstState))
                .timeout(const Duration(seconds: 5));
        expect(states.map((s) => s.phase), everyElement('lobby'));

        // 3. Admin starts the game; 4. bots play random legal moves.
        final stopwatch = Stopwatch()..start();
        adminRoom.startGame();
        final overs = await Future.wait(bots.map((b) => b.gameOver.future))
            .timeout(const Duration(seconds: 30));
        stopwatch.stop();

        // 5. Assertions.
        for (final bot in bots) {
          expect(bot.errors, isEmpty,
              reason: '${bot.name} received error messages: ${bot.errors}');
          expect(bot.protocolErrors, isEmpty,
              reason: '${bot.name} protocol errors: ${bot.protocolErrors}');
        }
        final loserSeats = overs.map((o) => o.loserSeat).toSet();
        expect(loserSeats, hasLength(1),
            reason: 'all clients must agree on loserSeat, got $loserSeats');
        for (final over in overs) {
          expect(over.placements, hasLength(3));
          expect(over.placements.map((p) => p.placement).toSet(), {1, 2, 3});
          expect(over.jokerCard.rank, 'JOKER');
        }
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 30)));
        // ignore: avoid_print
        print('game finished in ${stopwatch.elapsedMilliseconds} ms, '
            'loserSeat=${loserSeats.single}');
      } finally {
        for (final bot in bots) {
          await bot.dispose();
        }
        for (final client in clients) {
          client.close();
        }
      }
    },
    skip: up
        ? false
        : 'Trude server not reachable at $_baseUrl/health — start it and rerun.',
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
