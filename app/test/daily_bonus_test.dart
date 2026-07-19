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
import 'package:trude/features/home/home_screen.dart';
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

/// Profile with an unclaimed daily bonus at streak 2 (next claim = day 3,
/// 20 coins). POST /me/daily/claim answers idempotently per §S3.
TrudeClient _fakeClient({required List<String> claimCalls}) {
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
        case ('GET', '/me'):
          return _json({
            'userId': 'u1',
            'nickname': 'Tester',
            'avatar': 'a0',
            'coins': 100,
            'rating': 1000,
            'premium': false,
            'dailyStreak': 2,
            'dailyClaimedToday': false,
            'selected': {'cardBack': 'cb_classic', 'felt': 'felt_classic'},
            'stats': {'gamesPlayed': 3, 'gamesWon': 1, 'bestWinStreak': 1},
          });
        case ('POST', '/me/daily/claim'):
          claimCalls.add(request.url.path);
          return _json({
            'claimed': true,
            'day': '2026-07-19',
            'streak': 3,
            'coins': 20,
            'balance': 120,
            'nextBonus': 30,
          });
        default:
          return http.Response('not found', 404);
      }
    }),
  );
}

void main() {
  testWidgets(
      'daily bonus sheet auto-opens once per session, shows the day-3 bonus, '
      'and claims through the provider', (tester) async {
    final claimCalls = <String>[];
    final client = _fakeClient(claimCalls: claimCalls);
    addTearDown(client.close);

    late ProviderContainer container;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        guestIdentityStoreProvider.overrideWithValue(_FakeStore()),
        trudeClientProvider.overrideWithValue(client),
      ],
      child: Consumer(builder: (context, ref, child) {
        container = ProviderScope.containerOf(context);
        return const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomeScreen(),
        );
      }),
    ));
    await tester.pumpAndSettle();

    // The sheet auto-opened with the streak ribbon and the day-3 claim.
    expect(find.text(Strings.dailyBonusTitle), findsOneWidget);
    expect(find.text(Strings.dailyBonusClaim(20)), findsOneWidget);
    expect(container.read(dailySheetShownProvider), isTrue);

    // Claim: POSTs exactly once and the sheet closes.
    await tester.tap(find.text(Strings.dailyBonusClaim(20)));
    await tester.pumpAndSettle();
    expect(claimCalls, hasLength(1));
    expect(find.text(Strings.dailyBonusTitle), findsNothing);

    // Once per session: the flag stays set, so nothing re-opens on rebuild.
    await tester.pump(const Duration(seconds: 1));
    expect(find.text(Strings.dailyBonusTitle), findsNothing);
    expect(container.read(dailySheetShownProvider), isTrue);
  });
}
