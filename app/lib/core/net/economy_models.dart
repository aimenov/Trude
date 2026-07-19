/// Models for the economy HTTP endpoints (leaderboard, quests, daily bonus,
/// cosmetics shop, rewarded ads, IAP) and the room's `rewards` message.
///
/// Field names mirror the wire contracts in docs/protocol.md EXACTLY; all
/// parsers are null-safe (missing fields default) so older servers and
/// server-side additions never break the client.
library;

import 'meta_models.dart' show SelectedCosmetics;

export 'meta_models.dart'
    show SelectedCosmetics, kDefaultCardBack, kDefaultFelt;

int _int(dynamic v, [int fallback = 0]) =>
    v == null ? fallback : (v as num).toInt();
int? _intOrNull(dynamic v) => v == null ? null : (v as num).toInt();
bool _bool(dynamic v, [bool fallback = false]) => v is bool ? v : fallback;
Map<String, dynamic> _map(dynamic v) => (v as Map).cast<String, dynamic>();
List<Map<String, dynamic>> _mapList(dynamic v) =>
    (v as List? ?? const []).map(_map).toList();

/// Leaderboard tab / query scope (`GET /leaderboard?scope=weekly|alltime`).
enum LeaderboardScope { weekly, alltime }

/// Which cosmetic slot an item occupies. The wire `kind` string is kept raw
/// on [CosmeticListing]; this enum is derived from the key namespace
/// (`cb_*` / `felt_*`), which is the frozen contract.
enum CosmeticKind { cardBack, felt }

/// One row of `GET /leaderboard`.
class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.nickname,
    required this.avatar,
    required this.value,
    required this.gamesRated,
  });

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        rank: _int(json['rank']),
        userId: json['userId'] as String? ?? '',
        nickname: json['nickname'] as String? ?? '',
        avatar: json['avatar'] as String? ?? '',
        value: _int(json['value']),
        gamesRated: _int(json['gamesRated']),
      );

  final int rank;
  final String userId;
  final String nickname;
  final String avatar;

  /// Rating (alltime) or season points (weekly).
  final int value;
  final int gamesRated;
}

/// The caller's own standing (`me` block); null when the user is unrated.
class LeaderboardMe {
  const LeaderboardMe({
    required this.rank,
    required this.value,
    required this.gamesRated,
  });

  factory LeaderboardMe.fromJson(Map<String, dynamic> json) => LeaderboardMe(
        rank: _int(json['rank']),
        value: _int(json['value']),
        gamesRated: _int(json['gamesRated']),
      );

  final int rank;
  final int value;
  final int gamesRated;
}

/// `GET /leaderboard?scope=...` response.
class LeaderboardPage {
  const LeaderboardPage({
    required this.scope,
    this.seasonKey,
    this.entries = const [],
    this.me,
  });

  factory LeaderboardPage.fromJson(Map<String, dynamic> json) =>
      LeaderboardPage(
        scope: json['scope'] as String? ?? 'alltime',
        seasonKey: json['seasonKey'] as String?,
        entries:
            _mapList(json['entries']).map(LeaderboardEntry.fromJson).toList(),
        me: json['me'] == null ? null : LeaderboardMe.fromJson(_map(json['me'])),
      );

  /// `'weekly'` or `'alltime'`, echoed by the server.
  final String scope;

  /// ISO week key (e.g. `"2026-W29"`); only present for the weekly scope.
  final String? seasonKey;
  final List<LeaderboardEntry> entries;
  final LeaderboardMe? me;

  LeaderboardScope get scopeEnum =>
      scope == 'weekly' ? LeaderboardScope.weekly : LeaderboardScope.alltime;
}

/// One quest of `GET /me/quests`.
class QuestInfo {
  const QuestInfo({
    required this.key,
    required this.target,
    required this.reward,
    required this.progress,
    required this.completed,
  });

  factory QuestInfo.fromJson(Map<String, dynamic> json) => QuestInfo(
        key: json['key'] as String? ?? '',
        target: _int(json['target']),
        reward: _int(json['reward']),
        progress: _int(json['progress']),
        completed: _bool(json['completed']),
      );

  final String key;
  final int target;
  final int reward;
  final int progress;
  final bool completed;
}

/// `GET /me/quests` response.
class DailyQuests {
  const DailyQuests({required this.day, this.quests = const []});

  factory DailyQuests.fromJson(Map<String, dynamic> json) => DailyQuests(
        day: json['day'] as String? ?? '',
        quests: _mapList(json['quests']).map(QuestInfo.fromJson).toList(),
      );

  /// UTC day key, e.g. `"2026-07-19"`.
  final String day;
  final List<QuestInfo> quests;
}

/// `POST /me/daily/claim` response (idempotent, always 200).
class DailyClaimResult {
  const DailyClaimResult({
    required this.claimed,
    required this.day,
    required this.streak,
    required this.coins,
    required this.balance,
    required this.nextBonus,
  });

  factory DailyClaimResult.fromJson(Map<String, dynamic> json) =>
      DailyClaimResult(
        claimed: _bool(json['claimed']),
        day: json['day'] as String? ?? '',
        streak: _int(json['streak']),
        coins: _int(json['coins']),
        balance: _int(json['balance']),
        nextBonus: _int(json['nextBonus']),
      );

  /// False when today was already claimed (replay); [coins] is then 0.
  final bool claimed;
  final String day;
  final int streak;
  final int coins;
  final int balance;
  final int nextBonus;
}

/// One item of `GET /catalog/cosmetics`.
class CosmeticListing {
  const CosmeticListing({
    required this.key,
    required this.kind,
    required this.price,
    required this.premiumOnly,
  });

  factory CosmeticListing.fromJson(Map<String, dynamic> json) =>
      CosmeticListing(
        key: json['key'] as String? ?? '',
        kind: json['kind'] as String? ?? '',
        price: _int(json['price']),
        premiumOnly: _bool(json['premiumOnly']),
      );

  /// Namespaced key: `cb_*` (card back) or `felt_*` (felt).
  final String key;

  /// Raw wire kind string (informational; [kindEnum] is derived from [key]).
  final String kind;
  final int price;
  final bool premiumOnly;

  /// Slot derived from the frozen key namespace, immune to `kind` spelling.
  CosmeticKind get kindEnum =>
      key.startsWith('felt_') ? CosmeticKind.felt : CosmeticKind.cardBack;
}

/// `GET /catalog/cosmetics` response.
class CosmeticsCatalog {
  const CosmeticsCatalog({this.items = const []});

  factory CosmeticsCatalog.fromJson(Map<String, dynamic> json) =>
      CosmeticsCatalog(
        items: _mapList(json['items']).map(CosmeticListing.fromJson).toList(),
      );

  final List<CosmeticListing> items;

  Map<String, CosmeticListing> get byKey => {for (final i in items) i.key: i};

  List<CosmeticListing> get cardBacks =>
      items.where((i) => i.kindEnum == CosmeticKind.cardBack).toList();
  List<CosmeticListing> get felts =>
      items.where((i) => i.kindEnum == CosmeticKind.felt).toList();
}

/// `GET /me/cosmetics` response.
class OwnedCosmetics {
  const OwnedCosmetics({
    this.owned = const [],
    this.selected = const SelectedCosmetics(),
  });

  factory OwnedCosmetics.fromJson(Map<String, dynamic> json) => OwnedCosmetics(
        owned: (json['owned'] as List? ?? const [])
            .map((e) => e.toString())
            .toList(),
        selected: SelectedCosmetics.fromJson(json['selected'] == null
            ? null
            : _map(json['selected'])),
      );

  final List<String> owned;
  final SelectedCosmetics selected;
}

/// `POST /shop/buy` success response.
class ShopPurchaseResult {
  const ShopPurchaseResult({required this.itemKey, required this.balance});

  factory ShopPurchaseResult.fromJson(Map<String, dynamic> json) =>
      ShopPurchaseResult(
        itemKey: json['itemKey'] as String? ?? '',
        balance: _int(json['balance']),
      );

  final String itemKey;
  final int balance;
}

/// `GET /ads/token` response.
class AdTokenGrant {
  const AdTokenGrant({required this.token, required this.remainingToday});

  factory AdTokenGrant.fromJson(Map<String, dynamic> json) => AdTokenGrant(
        token: json['token'] as String? ?? '',
        remainingToday: _int(json['remainingToday']),
      );

  final String token;
  final int remainingToday;
}

/// `POST /ads/reward` success response.
class AdRewardResult {
  const AdRewardResult({
    required this.coins,
    required this.balance,
    required this.remainingToday,
  });

  factory AdRewardResult.fromJson(Map<String, dynamic> json) => AdRewardResult(
        coins: _int(json['coins']),
        balance: _int(json['balance']),
        remainingToday: _int(json['remainingToday']),
      );

  final int coins;
  final int balance;
  final int remainingToday;
}

/// The `granted` block of an IAP response.
class IapGrant {
  const IapGrant({this.coins = 0, this.premium = false});

  factory IapGrant.fromJson(Map<String, dynamic> json) => IapGrant(
        coins: _int(json['coins']),
        premium: _bool(json['premium']),
      );

  final int coins;
  final bool premium;
}

/// `POST /iap/google` / `POST /iap/apple` success response.
/// Replays return 200 with [alreadyProcessed] true and a zero grant.
class IapResult {
  const IapResult({
    required this.productId,
    required this.granted,
    required this.balance,
    required this.premium,
    required this.alreadyProcessed,
  });

  factory IapResult.fromJson(Map<String, dynamic> json) => IapResult(
        productId: json['productId'] as String? ?? '',
        granted: json['granted'] == null
            ? const IapGrant()
            : IapGrant.fromJson(_map(json['granted'])),
        balance: _int(json['balance']),
        premium: _bool(json['premium']),
        alreadyProcessed: _bool(json['alreadyProcessed']),
      );

  final String productId;
  final IapGrant granted;
  final int balance;
  final bool premium;
  final bool alreadyProcessed;
}

/// One quest delta of the room `rewards` message.
class QuestDelta {
  const QuestDelta({
    required this.key,
    required this.progress,
    required this.target,
    required this.completed,
    required this.coins,
  });

  factory QuestDelta.fromJson(Map<String, dynamic> json) => QuestDelta(
        key: json['key'] as String? ?? '',
        progress: _int(json['progress']),
        target: _int(json['target']),
        completed: _bool(json['completed']),
        coins: _int(json['coins']),
      );

  final String key;
  final int progress;
  final int target;
  final bool completed;

  /// Coins granted by this quest in THIS game (0 unless it just completed).
  final int coins;
}

/// The per-seat room `rewards` message sent after `gameOver` (only to seats
/// that joined with `supportsRewards: true`).
class RewardsMessage {
  const RewardsMessage({
    this.coins = 0,
    this.balance = 0,
    this.rated = false,
    this.ratingDelta = 0,
    this.newRating,
    this.quests = const [],
    this.gameId,
  });

  factory RewardsMessage.fromJson(Map<String, dynamic> json) => RewardsMessage(
        coins: _int(json['coins']),
        balance: _int(json['balance']),
        rated: _bool(json['rated']),
        ratingDelta: _int(json['ratingDelta']),
        newRating: _intOrNull(json['newRating']),
        quests: _mapList(json['quests']).map(QuestDelta.fromJson).toList(),
        gameId: json['gameId'] as String?,
      );

  /// Total coins earned this game (placement + quest rewards).
  final int coins;

  /// Post-award wallet balance (server-authoritative).
  final int balance;
  final bool rated;
  final int ratingDelta;

  /// Absent when the game was not rated.
  final int? newRating;
  final List<QuestDelta> quests;

  /// GameResult id — pass to `GET /ads/token?kind=double&gameId=` to double.
  final String? gameId;
}
