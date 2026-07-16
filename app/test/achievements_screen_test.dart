import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:trude/core/net/connection_providers.dart';
import 'package:trude/core/storage/guest_identity_store.dart';
import 'package:trude/core/storage/identity_providers.dart';
import 'package:trude/features/achievements/achievements_screen.dart';
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

/// Serves /auth/guest and /me/achievements from canned JSON.
TrudeClient _fakeClient() {
  final unlockedAt =
      DateTime.utc(2026, 3, 14).millisecondsSinceEpoch;
  return TrudeClient(
    'http://fake.test',
    httpClient: MockClient((request) async {
      switch ((request.method, request.url.path)) {
        case ('POST', '/auth/guest'):
          return http.Response(
            jsonEncode({
              'token': 'fake-token',
              'userId': 'u1',
              'nickname': 'Tester',
              'avatar': 'a0',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        case ('GET', '/me/achievements'):
          final auth = request.headers['Authorization'] ??
              request.headers['authorization'];
          if (auth != 'Bearer fake-token') {
            return http.Response('unauthorized', 401);
          }
          return http.Response(
            jsonEncode({
              'unlocked': [
                {'key': 'best_liar', 'unlockedAt': unlockedAt},
              ],
              'catalog': [
                {
                  'key': 'best_liar',
                  'title': 'The Best Liar',
                  'description': 'Win 10 games',
                },
                {
                  'key': 'hot_potato',
                  'title': 'Hot Potato',
                  'description': 'Pass the joker on twice in a single game',
                },
                {
                  'key': 'brand_new_badge',
                  'title': 'Brand New Badge',
                  'description': 'Server-only achievement',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        default:
          return http.Response('not found', 404);
      }
    }),
  );
}

void main() {
  testWidgets('achievements screen renders the catalog from the client',
      (tester) async {
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
        home: AchievementsScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    // Unlocked badge: localized title + unlock date.
    expect(find.text('The Best Liar'), findsOneWidget);
    expect(find.textContaining('Unlocked'), findsOneWidget);
    expect(find.textContaining('2026'), findsOneWidget);

    // Locked badge: localized title + description as hint.
    expect(find.text('Hot Potato'), findsOneWidget);
    expect(
        find.text('Pass the joker on twice in a single game'), findsOneWidget);

    // Unknown key falls back to the server-provided copy.
    expect(find.text('Brand New Badge'), findsOneWidget);
    expect(find.text('Server-only achievement'), findsOneWidget);

    // Header counts unlocked vs catalog.
    expect(find.text('1 of 3 unlocked'), findsOneWidget);
  });
}
