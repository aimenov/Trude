import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:trude/core/net/connection_providers.dart';
import 'package:trude/core/storage/guest_identity_store.dart';
import 'package:trude/core/storage/identity_providers.dart';
import 'package:trude/core/strings.dart';
import 'package:trude/features/results/results_screen.dart';
import 'package:trude/l10n/app_localizations.dart';

class _FakeStore implements GuestIdentityStore {
  GuestIdentity? _identity =
      const GuestIdentity(deviceId: 'test-device-12345', nickname: 'Vasya');

  @override
  GuestIdentity? load() => _identity;

  @override
  void save(GuestIdentity identity) => _identity = identity;

  @override
  void clear() => _identity = null;
}

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

TrudeClient _fakeClient() {
  return TrudeClient(
    'http://fake.test',
    httpClient: MockClient((request) async {
      switch ((request.method, request.url.path)) {
        case ('POST', '/auth/guest'):
          return _json({
            'token': 'fake-token',
            'userId': 'u1',
            'nickname': 'Vasya',
            'avatar': 'a0',
          });
        case ('GET', '/me/blocks'):
          return _json({'blocks': <Object>[]});
        default:
          return http.Response('not found', 404);
      }
    }),
  );
}

PlayerView _player(String userId, String nickname, int seat) => PlayerView(
      userId: userId,
      nickname: nickname,
      avatar: 'a0',
      seat: seat,
      cardCount: 0,
      connected: true,
      autoPilot: false,
      isOut: true,
      isAdmin: seat == 0,
    );

/// A finished 3-player game where Petya (u2) left mid-game — the server
/// re-ranked them last with `left: true` on the wire; Lera (u3) holds the
/// joker as the engine loser.
ClientGameState _finishedState() {
  final gameOver = GameOverEvent.fromJson({
    'type': 'gameOver',
    'loserSeat': 2,
    'loserUserId': 'u3',
    'jokerCard': {'id': 'c-joker', 'rank': 'JOKER'},
    'placements': [
      {'userId': 'u1', 'seat': 0, 'placement': 1},
      {'userId': 'u3', 'seat': 2, 'placement': 2},
      {'userId': 'u2', 'seat': 1, 'placement': 3, 'left': true},
    ],
    'stats': <String, dynamic>{},
  });
  return ClientGameState.empty.copyWith(
    roomPhase: 'finished',
    players: [
      _player('u1', 'Vasya', 0),
      _player('u2', 'Petya', 1),
      _player('u3', 'Lera', 2),
    ],
    mySeat: 0,
    lastResults: gameOver,
  );
}

class _StubGameStateNotifier extends GameStateNotifier {
  _StubGameStateNotifier(this._state);

  final ClientGameState _state;

  @override
  ClientGameState build() => _state;
}

void main() {
  testWidgets(
      'results: leaver row wears the etched «Покинул игру» badge and rows '
      'open the actions sheet (not for self)', (tester) async {
    final client = _fakeClient();
    addTearDown(client.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        guestIdentityStoreProvider.overrideWithValue(_FakeStore()),
        trudeClientProvider.overrideWithValue(client),
        gameStateProvider
            .overrideWith(() => _StubGameStateNotifier(_finishedState())),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ResultsScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    // All three rows render; only the leaver carries the badge.
    expect(find.text('Vasya'), findsOneWidget);
    expect(find.text('Petya'), findsOneWidget);
    expect(find.text('Lera'), findsOneWidget);
    expect(
        find.text(Strings.leftGameBadge.toUpperCase()), findsOneWidget);

    // Tapping an opponent's plaque opens the actions sheet.
    await tester.tap(find.text('Petya'));
    await tester.pumpAndSettle();
    expect(find.text(Strings.reportPlayer), findsOneWidget);
  });
}
