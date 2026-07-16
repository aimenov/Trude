@Tags(['integration'])
library;

// UI smoke acceptance: the real app plays a full game against two random-
// policy bots over the live server, with the animated table rendering every
// set piece (deal, throws, reveals, pickups, game over) along the way. The
// test drives the home/lobby screens through widget taps, then submits the
// local player's moves through the room while the table animates.
//
// Auto-skips when the server is down (same as transport_integration_test).

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:trude/app.dart';
import 'package:trude/core/net/connection_providers.dart';
import 'package:trude/core/storage/guest_identity_store.dart';
import 'package:trude/core/storage/identity_providers.dart';
import 'package:trude/core/strings.dart';
import 'package:trude/features/game/anim/rendered_state.dart';

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

class _FakeStore implements GuestIdentityStore {
  _FakeStore(this._identity);

  GuestIdentity? _identity;

  @override
  GuestIdentity? load() => _identity;

  @override
  void save(GuestIdentity identity) => _identity = identity;

  @override
  void clear() => _identity = null;
}

/// Compact random-legal-move bot (see transport_integration_test for the
/// annotated original).
class _Bot {
  _Bot(this.userId, this.room, this.rng) {
    _subs.add(room.onHand.listen((h) => hand = h.cards));
    _subs.add(room.onEvents.listen(_onBatch));
    _subs.add(room.onStateFull.listen((s) {
      for (final p in s.players) {
        if (p.userId == userId) seat = p.seat;
      }
      deckSize = s.config.deckSize;
      hand = s.hand;
    }));
  }

  final String userId;
  final TrudeRoom room;
  final Random rng;
  int seat = -1;
  int deckSize = 37;
  int lastThrowCount = 0;
  List<Card> hand = const [];
  final Set<String> retired = {};
  bool over = false;
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
          over = true;
        case TurnStartedEvent() when e.seat == seat && !over:
          _act(e);
        default:
          break;
      }
    }
  }

  void _act(TurnStartedEvent turn) {
    final wantsCheck =
        turn.phase == 'respond' && (turn.mustCheck || rng.nextInt(3) == 0);
    if (wantsCheck && lastThrowCount > 0) {
      room.check(rng.nextInt(min(lastThrowCount, 3)));
      return;
    }
    if (hand.isEmpty) return;
    final picked = ([...hand]..shuffle(rng))
        .take(min(1 + rng.nextInt(3), hand.length))
        .toList();
    String? rank;
    if (turn.phase == 'lead') {
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

  // TestWidgetsFlutterBinding stubs out HttpClient (every request 400s);
  // this suite intentionally talks to the real local server.
  setUpAll(() => HttpOverrides.global = null);

  testWidgets(
    'the app plays a full game through the animated table',
    (tester) async {
      final rng = Random();
      final runTag = rng.nextInt(1 << 30);
      final container = ProviderContainer(overrides: [
        guestIdentityStoreProvider.overrideWithValue(_FakeStore(
            GuestIdentity(deviceId: 'ui-smoke-$runTag', nickname: 'Smokey'))),
      ]);
      addTearDown(container.dispose);

      final clients = <TrudeClient>[];
      final bots = <_Bot>[];

      // Real network progress only happens inside runAsync; UI/animation
      // clocks only advance on pump. Interleave both.
      void log(String msg) {
        // ignore: avoid_print
        print('[smoke] $msg');
      }

      Future<void> spin(
        String what,
        bool Function() done, {
        Duration budget = const Duration(seconds: 20),
      }) async {
        log('waiting for $what');
        final sw = Stopwatch()..start();
        while (!done()) {
          if (sw.elapsed > budget) {
            final queue =
                container.read(renderedGameStateProvider.notifier).queue;
            fail('timed out waiting for: $what — '
                'rendered.phase=${container.read(renderedGameStateProvider).roomPhase} '
                'true.phase=${container.read(gameStateProvider).roomPhase} '
                'queue.busy=${queue.busy} '
                'current=${queue.current?.step.kind}');
          }
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 40)));
          await tester.pump(const Duration(milliseconds: 120));
          final e = tester.takeException();
          if (e != null) fail('exception while $what: $e');
        }
      }

      // Diagnostics: dump full error details (with stacks) as they happen.
      final oldOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        // ignore: avoid_print
        print('=== FLUTTER ERROR ===\n$details');
        oldOnError?.call(details);
      };

      try {
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: const TrudeApp(),
        ));
        await tester.pumpAndSettle();
        log('home screen up');
        expect(find.text(Strings.createRoom), findsOneWidget);

        // Create a room through the real dialog.
        await tester.tap(find.text(Strings.createRoom));
        await tester.pumpAndSettle();
        log('create dialog open');
        await tester.tap(find.text(Strings.create));
        await spin('room creation',
            () => container.read(currentRoomProvider) != null);
        await spin('lobby state',
            () => container.read(gameStateProvider).roomPhase == 'lobby');

        // Two bots join over their own sockets.
        await tester.runAsync(() async {
          final roomId = container.read(currentRoomProvider)!.roomId;
          for (var i = 0; i < 2; i++) {
            final client = TrudeClient(_baseUrl);
            clients.add(client);
            final session = await client.guestLogin(
                deviceId: 'ui-smoke-$runTag-bot$i', nickname: 'Bot$i');
            final room = await client.joinRoomById(roomId);
            bots.add(_Bot(session.userId, room, Random(rng.nextInt(1 << 32))));
          }
        });
        await spin('all players seated',
            () => container.read(gameStateProvider).players.length == 3);

        // Start the game from the lobby UI.
        log('starting game');
        await tester.ensureVisible(find.text(Strings.start));
        await tester.pump(); // ensureVisible jumps the scroll offset; lay out before tapping
        await tester.tap(find.text(Strings.start));
        await spin('game start',
            () => container.read(gameStateProvider).roomPhase == 'playing');
        log('game started');

        // Regression lock (empty-hands-at-start): the RENDERED hand must be
        // dealt even though the game-start batch fires while the lobby is
        // still mounted — the app-root subscription catches it. Fails on the
        // pre-fix code where the rendered state stayed empty forever.
        await spin('rendered hand dealt',
            () => container.read(renderedGameStateProvider).myHand.isNotEmpty);

        // My random-legal-move policy, submitted through the room while the
        // table animates. One action per turn (keyed by deadline).
        int? actedDeadline;
        void maybeAct() {
          final s = container.read(gameStateProvider);
          final turn = s.turn;
          if (!s.isMyTurn || turn == null) return;
          if (actedDeadline == turn.deadlineTs) return;
          actedDeadline = turn.deadlineTs;
          final room = container.read(currentRoomProvider)!;
          final wantsCheck = turn.phase == 'respond' &&
              (s.mustCheck || rng.nextInt(3) == 0);
          if (wantsCheck && s.lastThrowCount > 0) {
            room.check(rng.nextInt(min(s.lastThrowCount, 3)));
            return;
          }
          if (s.myHand.isEmpty) return;
          final picked = ([...s.myHand]..shuffle(rng))
              .take(min(1 + rng.nextInt(3), s.myHand.length))
              .toList();
          String? rank;
          if (turn.phase == 'lead') {
            final first = picked.first.rank;
            if (first != 'JOKER' && !s.retiredRanks.contains(first)) {
              rank = first;
            } else {
              final live = (s.deckSize == 53 ? _ranks53 : _ranks37)
                  .where((r) => !s.retiredRanks.contains(r))
                  .toList();
              rank = live[rng.nextInt(live.length)];
            }
          }
          room.throwCards(picked.map((c) => c.id).toList(), rank: rank);
        }

        // lastResults persists even after the server snaps the room back to
        // lobby right after gameOver (roomPhase 'finished' is transient).
        log('playing');
        final sw = Stopwatch()..start();
        while (container.read(gameStateProvider).lastResults == null) {
          if (sw.elapsed > const Duration(seconds: 90)) {
            fail('game did not finish within 90 s of wall time');
          }
          maybeAct();
          await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 40)));
          await tester.pump(const Duration(milliseconds: 150));
          final e = tester.takeException();
          if (e != null) fail('exception during play: $e');
        }

        // The game-over set piece must complete before /results shows.
        await spin('results screen after the joker sequence',
            () => find.text(Strings.resultsTitle).evaluate().isNotEmpty,
            budget: const Duration(seconds: 45));
        expect(container.read(gameStateProvider).lastResults, isNotNull);

        log('results screen shown; leaving');
        // Leave cleanly so the room can dispose. The websocket close
        // handshake may never resolve under the test binding — best effort.
        await tester.runAsync(() => container
            .read(currentRoomProvider.notifier)
            .leaveRoom()
            .timeout(const Duration(seconds: 5), onTimeout: () {}));
        await tester.pump(const Duration(milliseconds: 300));
        log('left room');
      } finally {
        log('cleanup');
        for (final bot in bots) {
          await tester.runAsync(bot.dispose);
        }
        for (final client in clients) {
          client.close();
        }
      }
    },
    // testWidgets only takes a bool skip; the transport test prints the hint.
    skip: !up,
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
