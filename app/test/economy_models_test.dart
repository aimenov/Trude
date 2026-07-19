// Parse tests for the economy wire models: full payloads round-trip, and
// absent/legacy fields default null-safely (a pre-economy server response
// must never break the client).

import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/net/trude_client.dart';

void main() {
  group('MeProfile', () {
    test('parses the full economy payload', () {
      final me = MeProfile.fromJson({
        'userId': 'u1',
        'nickname': 'Tester',
        'avatar': 'a3',
        'coins': 275,
        'rating': 1042,
        'premium': true,
        'dailyStreak': 4,
        'dailyClaimedToday': true,
        'selected': {'cardBack': 'cb_noir', 'felt': 'felt_navy'},
        'stats': {'gamesPlayed': 7, 'gamesWon': 2},
      });
      expect(me.coins, 275);
      expect(me.rating, 1042);
      expect(me.premium, isTrue);
      expect(me.dailyStreak, 4);
      expect(me.dailyClaimedToday, isTrue);
      expect(me.selected.cardBack, 'cb_noir');
      expect(me.selected.felt, 'felt_navy');
      expect(me.stats?.gamesPlayed, 7);
    });

    test('legacy payload without economy fields defaults safely', () {
      final me = MeProfile.fromJson({
        'userId': 'u1',
        'nickname': 'Tester',
        'avatar': 'a0',
      });
      expect(me.coins, 0);
      expect(me.rating, 1000);
      expect(me.premium, isFalse);
      expect(me.dailyStreak, 0);
      expect(me.dailyClaimedToday, isFalse);
      expect(me.selected.cardBack, kDefaultCardBack);
      expect(me.selected.felt, kDefaultFelt);
      expect(me.stats, isNull);
    });

    test('coerces num (web double) values to int', () {
      final me = MeProfile.fromJson({
        'userId': 'u1',
        'nickname': 'T',
        'avatar': 'a0',
        'coins': 42.0,
        'rating': 1015.0,
      });
      expect(me.coins, 42);
      expect(me.rating, 1015);
    });
  });

  group('SelectedCosmetics', () {
    test('partial/absent selection falls back to classics', () {
      expect(SelectedCosmetics.fromJson(null).cardBack, 'cb_classic');
      expect(SelectedCosmetics.fromJson(null).felt, 'felt_classic');
      final partial = SelectedCosmetics.fromJson({'cardBack': 'cb_royal'});
      expect(partial.cardBack, 'cb_royal');
      expect(partial.felt, 'felt_classic');
    });

    test('value equality and copyWith', () {
      const a = SelectedCosmetics(cardBack: 'cb_noir');
      expect(a, const SelectedCosmetics(cardBack: 'cb_noir'));
      expect(a.copyWith(felt: 'felt_navy').felt, 'felt_navy');
      expect(a.copyWith(felt: 'felt_navy').cardBack, 'cb_noir');
    });
  });

  group('RewardsMessage', () {
    test('parses the full rewards payload', () {
      final r = RewardsMessage.fromJson({
        'coins': 25,
        'balance': 300,
        'rated': true,
        'ratingDelta': -8,
        'newRating': 992,
        'gameId': 'gr_42',
        'quests': [
          {
            'key': 'q_checks',
            'progress': 3,
            'target': 3,
            'completed': true,
            'coins': 20,
          },
        ],
      });
      expect(r.coins, 25);
      expect(r.balance, 300);
      expect(r.rated, isTrue);
      expect(r.ratingDelta, -8);
      expect(r.newRating, 992);
      expect(r.gameId, 'gr_42');
      expect(r.quests, hasLength(1));
      expect(r.quests.single.key, 'q_checks');
      expect(r.quests.single.completed, isTrue);
      expect(r.quests.single.coins, 20);
    });

    test('empty payload defaults safely (unrated, no quests)', () {
      final r = RewardsMessage.fromJson(const {});
      expect(r.coins, 0);
      expect(r.balance, 0);
      expect(r.rated, isFalse);
      expect(r.ratingDelta, 0);
      expect(r.newRating, isNull);
      expect(r.quests, isEmpty);
      expect(r.gameId, isNull);
    });
  });

  group('LeaderboardPage', () {
    test('parses entries, seasonKey and me', () {
      final page = LeaderboardPage.fromJson({
        'scope': 'weekly',
        'seasonKey': '2026-W29',
        'entries': [
          {
            'rank': 1,
            'userId': 'u9',
            'nickname': 'Top',
            'avatar': 'a1',
            'value': 84,
            'gamesRated': 12,
          },
        ],
        'me': {'rank': 17, 'value': 3, 'gamesRated': 2},
      });
      expect(page.scopeEnum, LeaderboardScope.weekly);
      expect(page.seasonKey, '2026-W29');
      expect(page.entries.single.rank, 1);
      expect(page.entries.single.nickname, 'Top');
      expect(page.entries.single.value, 84);
      expect(page.me?.rank, 17);
    });

    test('alltime page with null me and no seasonKey', () {
      final page = LeaderboardPage.fromJson({
        'scope': 'alltime',
        'entries': [],
        'me': null,
      });
      expect(page.scopeEnum, LeaderboardScope.alltime);
      expect(page.seasonKey, isNull);
      expect(page.entries, isEmpty);
      expect(page.me, isNull);
    });
  });

  group('quests + daily claim', () {
    test('DailyQuests parses', () {
      final q = DailyQuests.fromJson({
        'day': '2026-07-19',
        'quests': [
          {
            'key': 'q_win',
            'target': 1,
            'reward': 30,
            'progress': 0,
            'completed': false,
          },
        ],
      });
      expect(q.day, '2026-07-19');
      expect(q.quests.single.key, 'q_win');
      expect(q.quests.single.reward, 30);
      expect(q.quests.single.completed, isFalse);
    });

    test('DailyClaimResult parses both fresh and replayed claims', () {
      final fresh = DailyClaimResult.fromJson({
        'claimed': true,
        'day': '2026-07-19',
        'streak': 3,
        'coins': 20,
        'balance': 120,
        'nextBonus': 30,
      });
      expect(fresh.claimed, isTrue);
      expect(fresh.coins, 20);
      expect(fresh.nextBonus, 30);

      final replay = DailyClaimResult.fromJson({
        'claimed': false,
        'day': '2026-07-19',
        'streak': 3,
        'coins': 0,
        'balance': 120,
        'nextBonus': 30,
      });
      expect(replay.claimed, isFalse);
      expect(replay.coins, 0);
    });
  });

  group('cosmetics', () {
    test('catalog parses; kindEnum derives from the key namespace', () {
      final catalog = CosmeticsCatalog.fromJson({
        'items': [
          {'key': 'cb_noir', 'kind': 'cardBack', 'price': 300,
            'premiumOnly': false},
          {'key': 'cb_gilded', 'kind': 'cardBack', 'price': 0,
            'premiumOnly': true},
          {'key': 'felt_navy', 'kind': 'felt', 'price': 400,
            'premiumOnly': false},
        ],
      });
      expect(catalog.items, hasLength(3));
      expect(catalog.byKey['cb_noir']?.price, 300);
      expect(catalog.byKey['cb_gilded']?.premiumOnly, isTrue);
      expect(catalog.cardBacks.map((i) => i.key), ['cb_noir', 'cb_gilded']);
      expect(catalog.felts.single.key, 'felt_navy');
      expect(catalog.byKey['felt_navy']?.kindEnum, CosmeticKind.felt);
      expect(catalog.byKey['cb_noir']?.kindEnum, CosmeticKind.cardBack);
    });

    test('OwnedCosmetics parses; empty payload defaults to classics', () {
      final owned = OwnedCosmetics.fromJson({
        'owned': ['cb_noir', 'felt_navy'],
        'selected': {'cardBack': 'cb_noir', 'felt': 'felt_classic'},
      });
      expect(owned.owned, ['cb_noir', 'felt_navy']);
      expect(owned.selected.cardBack, 'cb_noir');

      final empty = OwnedCosmetics.fromJson(const {});
      expect(empty.owned, isEmpty);
      expect(empty.selected, const SelectedCosmetics());
    });

    test('ShopPurchaseResult parses', () {
      final buy =
          ShopPurchaseResult.fromJson({'itemKey': 'cb_noir', 'balance': 12});
      expect(buy.itemKey, 'cb_noir');
      expect(buy.balance, 12);
    });
  });

  group('ads + IAP', () {
    test('AdTokenGrant and AdRewardResult parse', () {
      final grant =
          AdTokenGrant.fromJson({'token': 'jwt.x.y', 'remainingToday': 4});
      expect(grant.token, 'jwt.x.y');
      expect(grant.remainingToday, 4);

      final reward = AdRewardResult.fromJson(
          {'coins': 25, 'balance': 145, 'remainingToday': 3});
      expect(reward.coins, 25);
      expect(reward.balance, 145);
      expect(reward.remainingToday, 3);
    });

    test('IapResult parses grants and replays', () {
      final first = IapResult.fromJson({
        'productId': 'coins_small',
        'granted': {'coins': 500, 'premium': false},
        'balance': 620,
        'premium': false,
        'alreadyProcessed': false,
      });
      expect(first.productId, 'coins_small');
      expect(first.granted.coins, 500);
      expect(first.alreadyProcessed, isFalse);

      final replay = IapResult.fromJson({
        'productId': 'premium_upgrade',
        'granted': {'coins': 0, 'premium': false},
        'balance': 620,
        'premium': true,
        'alreadyProcessed': true,
      });
      expect(replay.alreadyProcessed, isTrue);
      expect(replay.premium, isTrue);
      expect(replay.granted.coins, 0);
    });
  });

  group('TrudeApiException.errorCode', () {
    test('extracts the {error: CODE} body', () {
      final e = TrudeApiException(402, '{"error":"INSUFFICIENT_FUNDS"}');
      expect(e.errorCode, 'INSUFFICIENT_FUNDS');
    });

    test('is null for non-JSON or differently shaped bodies', () {
      expect(TrudeApiException(500, 'internal').errorCode, isNull);
      expect(TrudeApiException(404, '{"message":"nope"}').errorCode, isNull);
      expect(TrudeApiException(204, '').errorCode, isNull);
    });
  });
}
