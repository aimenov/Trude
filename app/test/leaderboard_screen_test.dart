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

/// Serves /auth/guest and /leaderboard from canned JSON per §S3.
/// Weekly: viewer (u1) NOT on the page, me = rank 12. All-time: viewer on
/// the page at rank 2 with rating 1120 (Card Player tier).
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
        case ('GET', '/leaderboard'):
          final scope = request.url.queryParameters['scope'];
          if (scope == 'alltime') {
            return _json({
              'scope': 'alltime',
              'entries': [
                {
                  'rank': 1,
                  'userId': 'u2',
                  'nickname': 'Sharpy',
                  'avatar': 'a1',
                  'value': 1500,
                  'gamesRated': 40,
                },
                {
                  'rank': 2,
                  'userId': 'u1',
                  'nickname': 'Tester',
                  'avatar': 'a0',
                  'value': 1120,
                  'gamesRated': 30,
                },
              ],
              'me': {'rank': 2, 'value': 1120, 'gamesRated': 30},
            });
          }
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
      'leaderboard: weekly pins my rank as a footer when I am off the page, '
      'alltime shows my row inline with a tier name', (tester) async {
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

    // Weekly tab (default): the three ranked players render.
    expect(find.text('Sharpy'), findsOneWidget);
    expect(find.text('Plut'), findsOneWidget);
    expect(find.text('Katala'), findsOneWidget);

    // I'm rank 12 (not on the page) — the pinned footer shows my rank.
    expect(find.text(Strings.leaderboardMyRank(12)), findsOneWidget);

    // Switch to the all-time tab.
    await tester.tap(find.text(Strings.leaderboardAlltime));
    await tester.pumpAndSettle();

    // My row is on the page now — highlighted inline, no pinned footer.
    expect(find.text('Tester'), findsOneWidget);
    expect(find.text(Strings.leaderboardMyRank(2)), findsNothing);

    // All-time shows tier names under ratings (1120 → Card Player,
    // 1500 → Card Sharp).
    expect(find.text(Strings.tierName('cardplayer')), findsOneWidget);
    expect(find.text(Strings.tierName('sharp')), findsOneWidget);
  });
}
