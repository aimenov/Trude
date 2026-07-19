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
import 'package:trude/features/shop/shop_screen.dart';
import 'package:trude/features/shop/shop_widgets.dart';
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

/// Serves the §S3 meta endpoints the shop needs: profile with coins,
/// cosmetics catalog, and ownership (cb_crimson owned but not equipped).
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
        case ('GET', '/me'):
          return _json({
            'userId': 'u1',
            'nickname': 'Tester',
            'avatar': 'a0',
            'coins': 500,
            'rating': 1000,
            'premium': false,
            'dailyStreak': 0,
            'dailyClaimedToday': true,
            'selected': {'cardBack': 'cb_classic', 'felt': 'felt_classic'},
            'stats': {'gamesPlayed': 3, 'gamesWon': 1, 'bestWinStreak': 1},
          });
        case ('GET', '/catalog/cosmetics'):
          return _json({
            'items': [
              {
                'key': 'cb_classic',
                'kind': 'cardBack',
                'price': 0,
                'premiumOnly': false,
              },
              {
                'key': 'cb_crimson',
                'kind': 'cardBack',
                'price': 300,
                'premiumOnly': false,
              },
              {
                'key': 'cb_noir',
                'kind': 'cardBack',
                'price': 300,
                'premiumOnly': false,
              },
              {
                'key': 'cb_gilded',
                'kind': 'cardBack',
                'price': 0,
                'premiumOnly': true,
              },
              {
                'key': 'felt_classic',
                'kind': 'felt',
                'price': 0,
                'premiumOnly': false,
              },
              {
                'key': 'felt_burgundy',
                'kind': 'felt',
                'price': 400,
                'premiumOnly': false,
              },
            ],
          });
        case ('GET', '/me/cosmetics'):
          return _json({
            'owned': ['cb_classic', 'cb_crimson', 'felt_classic'],
            'selected': {'cardBack': 'cb_classic', 'felt': 'felt_classic'},
          });
        default:
          return http.Response('not found', 404);
      }
    }),
  );
}

void main() {
  testWidgets(
      'shop renders the state matrix: equipped, owned, priced, premium-locked, '
      'no ad button when not ready, billing note on unsupported platforms',
      (tester) async {
    // The shop is a lazy ListView: sections below the default 800x600 test
    // viewport (felt grid, billing note, premium card) would never build.
    // A tall viewport keeps every section's finders in the element tree.
    tester.view.physicalSize = const Size(800, 2800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final client = _fakeClient();
    addTearDown(client.close);
    final adReady = ValueNotifier<bool>(false);
    addTearDown(adReady.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        guestIdentityStoreProvider.overrideWithValue(_FakeStore()),
        trudeClientProvider.overrideWithValue(client),
        rewardedAdReadyProvider.overrideWithValue(adReady),
        adPrepareProvider.overrideWithValue((kind, {gameId}) async {}),
        billingSupportedProvider.overrideWithValue(false),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ShopScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    // Wallet header counted up to the profile's balance.
    expect(find.text('500'), findsOneWidget);

    // No rewarded ad loaded -> no watch-ad button.
    expect(find.textContaining('25'), findsNothing);

    // Equipped chips on the classic back AND the classic felt.
    expect(find.text(Strings.shopEquipped), findsNWidgets(2));

    // Owned-but-not-equipped card back.
    expect(find.text(Strings.shopOwned), findsOneWidget);

    // Priced items show coin chips (cb_noir 300, felt_burgundy 400).
    expect(find.text('300'), findsOneWidget);
    expect(find.text('400'), findsOneWidget);

    // cb_gilded is premium-locked for a non-premium player.
    expect(find.text(Strings.shopPremiumLock), findsOneWidget);

    // Billing unsupported: coin packs replaced by the mobile-parlor note,
    // and no Premium buy button.
    expect(find.text(Strings.shopBillingUnavailable), findsOneWidget);
    expect(find.text(Strings.premiumTitle), findsOneWidget);
    expect(find.textContaining(Strings.buy), findsNothing);

    // The ad becoming ready surfaces the watch-ad button without a rebuild
    // from above.
    adReady.value = true;
    await tester.pumpAndSettle();
    expect(find.text(Strings.shopWatchAd(kShopAdCoins)), findsOneWidget);
  });
}
