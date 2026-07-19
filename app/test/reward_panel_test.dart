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
import 'package:trude/features/economy/rewards_providers.dart';
import 'package:trude/features/results/results_screen.dart';
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

/// Pins the rewards state without a live room.
class _FakeRewards extends RewardsThisGameController {
  _FakeRewards(this.msg);

  final RewardsMessage? msg;

  @override
  RewardsMessage? build() => msg;
}

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

TrudeClient _fakeClient({required bool premium}) {
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
            'rating': 1012,
            'premium': premium,
            'dailyStreak': 1,
            'dailyClaimedToday': true,
            'selected': {'cardBack': 'cb_classic', 'felt': 'felt_classic'},
            'stats': {'gamesPlayed': 3, 'gamesWon': 1, 'bestWinStreak': 1},
          });
        default:
          return http.Response('not found', 404);
      }
    }),
  );
}

RewardsMessage _rewards({int coins = 25}) => RewardsMessage.fromJson({
      'coins': coins,
      'balance': 100 + coins,
      'rated': true,
      'ratingDelta': 12,
      'newRating': 1012,
      'quests': [
        {
          'key': 'q_win_1',
          'progress': 1,
          'target': 1,
          'completed': true,
          'coins': 20,
        },
      ],
      'gameId': 'g1',
    });

Future<void> _pump(
  WidgetTester tester, {
  required RewardsMessage? rewards,
  required bool adsReady,
  bool premium = false,
  AdEarn? earn,
}) async {
  final client = _fakeClient(premium: premium);
  addTearDown(client.close);
  final ready = ValueNotifier<bool>(adsReady);
  addTearDown(ready.dispose);

  await tester.pumpWidget(ProviderScope(
    overrides: [
      guestIdentityStoreProvider.overrideWithValue(_FakeStore()),
      trudeClientProvider.overrideWithValue(client),
      rewardsThisGameProvider.overrideWith(() => _FakeRewards(rewards)),
      rewardedAdReadyProvider.overrideWithValue(ready),
      adPrepareProvider.overrideWithValue((kind, {gameId}) async {}),
      if (earn != null) adEarnProvider.overrideWithValue(earn),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SingleChildScrollView(child: RewardPanel())),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('counts the coins up, shows the rating chip with tier, '
      'and offers the double button when all four conditions hold',
      (tester) async {
    await _pump(tester, rewards: _rewards(), adsReady: true);

    // Count-up settled at +25.
    expect(find.text('+25'), findsOneWidget);

    // Rating chip: delta, new total, tier name.
    expect(find.text('+12'), findsOneWidget);
    expect(
        find.text('1012 · ${Strings.tierName('novice')}'), findsOneWidget);

    // Completed quest row with its reward chip.
    expect(find.text(Strings.questTitle('q_win_1')), findsOneWidget);
    expect(find.text(Strings.questRewardChip(20)), findsOneWidget);

    // adsReady && !premium && coins>0 && !doubled -> the button shows.
    expect(find.text(Strings.doubleWinnings), findsOneWidget);
  });

  testWidgets('no rewards message -> the panel collapses', (tester) async {
    await _pump(tester, rewards: null, adsReady: true);
    expect(find.text(Strings.rewardsPanelTitle.toUpperCase()), findsNothing);
  });

  testWidgets('double button hidden when the ad is not ready',
      (tester) async {
    await _pump(tester, rewards: _rewards(), adsReady: false);
    expect(find.text('+25'), findsOneWidget);
    expect(find.text(Strings.doubleWinnings), findsNothing);
  });

  testWidgets('double button hidden for premium players', (tester) async {
    await _pump(tester, rewards: _rewards(), adsReady: true, premium: true);
    expect(find.text(Strings.doubleWinnings), findsNothing);
  });

  testWidgets('double button hidden when the game paid nothing',
      (tester) async {
    await _pump(tester, rewards: _rewards(coins: 0), adsReady: true);
    expect(find.text(Strings.doubleWinnings), findsNothing);
  });

  testWidgets('doubling earns once, re-counts to 2N, and etches «Удвоено»',
      (tester) async {
    final earnCalls = <(String, String?)>[];
    await _pump(
      tester,
      rewards: _rewards(),
      adsReady: true,
      earn: (kind, {gameId}) async {
        earnCalls.add((kind, gameId));
        return 25;
      },
    );

    await tester.tap(find.text(Strings.doubleWinnings));
    await tester.pumpAndSettle();

    expect(earnCalls, [('double', 'g1')]);
    expect(find.text(Strings.doubledLabel.toUpperCase()), findsOneWidget);
    expect(find.text(Strings.doubleWinnings), findsNothing);
    // Count-up settled at the doubled total.
    expect(find.text('+50'), findsOneWidget);
  });
}
