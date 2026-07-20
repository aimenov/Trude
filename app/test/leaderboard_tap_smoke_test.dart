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
import 'package:trude/features/leaderboard/leaderboard_screen.dart';
import 'package:trude/l10n/app_localizations.dart';

class _FakeStore implements GuestIdentityStore {
  GuestIdentity? _identity =
      const GuestIdentity(deviceId: 'test-device-12345', nickname: 'Tester');

  @override
  GuestIdentity? load() => _identity;

  @override
  void save(GuestIdentity identity) => _identity = identity;

  @override
  void clear() => _identity = null;
}

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

/// Weekly board with three players; the viewer (u1) is off the page and has
/// blocked u4 — whose row must render masked.
TrudeClient _fakeClient() {
  return TrudeClient(
    'http://fake.test',
    httpClient: MockClient((request) async {
      switch ((request.method, request.url.path)) {
        case ('POST', '/auth/guest'):
          return _json({
            'token': 'fake-token',
            'userId': 'u1',
            'nickname': 'Tester',
            'avatar': 'a0',
          });
        case ('GET', '/me/blocks'):
          return _json({
            'blocks': [
              {
                'userId': 'u4',
                'nickname': 'Katala',
                'createdAt': '2026-07-01T00:00:00.000Z',
              },
            ],
          });
        case ('GET', '/leaderboard'):
          return _json({
            'scope': 'weekly',
            'seasonKey': '2026-W29',
            'entries': [
              {
                'rank': 1,
                'userId': 'u2',
                'nickname': 'Sharpy',
                'avatar': 'a1',
                'value': 55,
                'gamesRated': 6,
              },
              {
                'rank': 2,
                'userId': 'u3',
                'nickname': 'Plut',
                'avatar': 'a2',
                'value': 30,
                'gamesRated': 4,
              },
              {
                'rank': 3,
                'userId': 'u4',
                'nickname': 'Katala',
                'avatar': 'a3',
                'value': 12,
                'gamesRated': 3,
              },
            ],
            'me': {'rank': 12, 'value': 8, 'gamesRated': 4},
          });
        default:
          return http.Response('not found', 404);
      }
    }),
  );
}

void main() {
  testWidgets(
      'leaderboard: blocked row is masked, tapping a row opens the actions '
      'sheet', (tester) async {
    final client = _fakeClient();
    addTearDown(client.close);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        guestIdentityStoreProvider.overrideWithValue(_FakeStore()),
        trudeClientProvider.overrideWithValue(client),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LeaderboardScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    // u4 is blocked: their row shows the masked stand-in, not «Katala».
    expect(find.text('Katala'), findsNothing);
    expect(find.text(Strings.blockedPlayerName), findsOneWidget);

    // Tap an opponent's row: the report/block sheet opens.
    await tester.tap(find.text('Sharpy'));
    await tester.pumpAndSettle();
    expect(find.text(Strings.reportPlayer), findsOneWidget);
    expect(find.text(Strings.blockPlayer), findsOneWidget);
  });
}
