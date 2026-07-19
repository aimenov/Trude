// rewardsThisGameProvider fold test over a fake transport: a fake
// RoomConnection (the seam under TrudeRoom) pushes synthetic 'rewards' and
// 'events' messages; the provider must hold the latest rewards, credit the
// wallet/rating mirrors, and clear on gameStarted.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/net/colyseus_lite/room_connection.dart';
import 'package:trude/core/net/connection_providers.dart';
import 'package:trude/core/net/economy_providers.dart';
import 'package:trude/features/economy/rewards_providers.dart';

/// In-memory RoomConnection: tests push messages, nothing touches a socket.
class _FakeConn implements RoomConnection {
  final _messages = StreamController<RoomMessage>.broadcast();
  final _errors = StreamController<RoomProtocolError>.broadcast();
  final _closed = Completer<void>();

  @override
  String get roomId => 'room-1';

  @override
  String get sessionId => 'sess-1';

  @override
  String? reconnectionToken = 'room-1:tok';

  @override
  String? serializerId;

  @override
  bool get isJoined => !_closed.isCompleted;

  @override
  Stream<RoomMessage> get messages => _messages.stream;

  @override
  Stream<RoomProtocolError> get protocolErrors => _errors.stream;

  @override
  Future<void> get onClose => _closed.future;

  @override
  void send(String type, [Object? payload]) {}

  @override
  Future<void> leave({bool consented = true}) async {
    if (!_closed.isCompleted) _closed.complete();
  }

  void push(String type, Map<String, dynamic> data) =>
      _messages.add(RoomMessage(type, data));
}

/// currentRoomProvider pinned to a pre-built room.
class _FixedRoomController extends CurrentRoomController {
  _FixedRoomController(this.room);

  final TrudeRoom room;

  @override
  TrudeRoom? build() => room;
}

const _me = MeProfile(
  userId: 'u1',
  nickname: 'Tester',
  avatar: 'a0',
  coins: 100,
  rating: 1000,
);

void main() {
  late _FakeConn conn;
  late TrudeRoom room;
  late ProviderContainer container;

  setUp(() {
    conn = _FakeConn();
    room = TrudeRoom.forTest(conn);
    container = ProviderContainer(overrides: [
      meProvider.overrideWith((ref) async => _me),
      currentRoomProvider.overrideWith(() => _FixedRoomController(room)),
    ]);
    // Eager-bind exactly like app.dart: the room's broadcast streams do not
    // replay, so the accumulator must subscribe before messages arrive.
    container.listen(rewardsThisGameProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await room.leave();
  });

  test('rewards message is held, wallet snaps to balance, rating updates',
      () async {
    await container.read(meProvider.future);
    await pumpEventQueue();
    expect(container.read(walletProvider), 100);
    expect(container.read(ratingProvider), 1000);
    expect(container.read(rewardsThisGameProvider), isNull);

    conn.push('rewards', {
      'coins': 25,
      'balance': 125,
      'rated': true,
      'ratingDelta': 12,
      'newRating': 1012,
      'gameId': 'gr_7',
      'quests': [
        {
          'key': 'q_checks',
          'progress': 2,
          'target': 3,
          'completed': false,
          'coins': 0,
        },
      ],
    });
    await pumpEventQueue();

    final held = container.read(rewardsThisGameProvider);
    expect(held, isNotNull);
    expect(held!.coins, 25);
    expect(held.balance, 125);
    expect(held.ratingDelta, 12);
    expect(held.gameId, 'gr_7');
    expect(held.quests.single.key, 'q_checks');
    expect(container.read(walletProvider), 125);
    expect(container.read(ratingProvider), 1012);
  });

  test('gameStarted clears the held rewards but not the wallet', () async {
    await container.read(meProvider.future);
    await pumpEventQueue();

    conn.push('rewards', {
      'coins': 10,
      'balance': 110,
      'rated': false,
      'ratingDelta': 0,
      'quests': <Map<String, dynamic>>[],
    });
    await pumpEventQueue();
    expect(container.read(rewardsThisGameProvider)?.coins, 10);
    expect(container.read(walletProvider), 110);
    // Unrated game: the rating mirror is untouched.
    expect(container.read(ratingProvider), 1000);

    conn.push('events', {
      'actionCount': 0,
      'events': [
        {
          'type': 'gameStarted',
          'deckSize': 37,
          'seatOrder': [
            {'seat': 0, 'userId': 'u1'},
            {'seat': 1, 'userId': 'u2'},
            {'seat': 2, 'userId': 'u3'},
          ],
          'handCounts': [12, 12, 12],
        },
      ],
    });
    await pumpEventQueue();

    expect(container.read(rewardsThisGameProvider), isNull);
    expect(container.read(walletProvider), 110);
  });

  test('a later rewards message replaces the held one', () async {
    await container.read(meProvider.future);
    await pumpEventQueue();

    conn.push('rewards',
        {'coins': 5, 'balance': 105, 'rated': false, 'quests': <Map<String, dynamic>>[]});
    await pumpEventQueue();
    conn.push('rewards', {
      'coins': 30,
      'balance': 135,
      'rated': true,
      'ratingDelta': -4,
      'newRating': 996,
      'quests': <Map<String, dynamic>>[],
    });
    await pumpEventQueue();

    expect(container.read(rewardsThisGameProvider)?.coins, 30);
    expect(container.read(walletProvider), 135);
    expect(container.read(ratingProvider), 996);
  });

  test('wallet credit() bumps locally on top of the mirror', () async {
    await container.read(meProvider.future);
    await pumpEventQueue();

    container.read(walletProvider.notifier).credit(25);
    expect(container.read(walletProvider), 125);
    container.read(walletProvider.notifier).set(200);
    expect(container.read(walletProvider), 200);
  });
}
