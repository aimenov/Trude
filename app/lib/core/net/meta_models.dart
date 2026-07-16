/// Models for the meta HTTP endpoints (GET /me, GET /me/achievements,
/// PATCH /me) in docs/protocol.md.
library;

int _int(dynamic v, [int fallback = 0]) =>
    v == null ? fallback : (v as num).toInt();

/// Lifetime stats block of `GET /me`. Unknown/missing fields default to 0 so
/// server-side additions never break the client.
class LifetimeStats {
  const LifetimeStats({
    this.gamesPlayed = 0,
    this.gamesWon = 0,
    this.gamesLost = 0,
    this.winStreak = 0,
    this.bestWinStreak = 0,
    this.liesSurvived = 0,
    this.liesCaught = 0,
    this.checksWon = 0,
    this.checksLost = 0,
    this.cardsPickedUp = 0,
    this.quadsDiscarded = 0,
    this.jokerPassed = 0,
    this.jokerSmuggles = 0,
    this.truthfulThrows = 0,
    this.lyingThrows = 0,
  });

  factory LifetimeStats.fromJson(Map<String, dynamic> json) => LifetimeStats(
        gamesPlayed: _int(json['gamesPlayed']),
        gamesWon: _int(json['gamesWon']),
        gamesLost: _int(json['gamesLost']),
        winStreak: _int(json['winStreak']),
        bestWinStreak: _int(json['bestWinStreak']),
        liesSurvived: _int(json['liesSurvived']),
        liesCaught: _int(json['liesCaught']),
        checksWon: _int(json['checksWon']),
        checksLost: _int(json['checksLost']),
        cardsPickedUp: _int(json['cardsPickedUp']),
        quadsDiscarded: _int(json['quadsDiscarded']),
        jokerPassed: _int(json['jokerPassed']),
        jokerSmuggles: _int(json['jokerSmuggles']),
        truthfulThrows: _int(json['truthfulThrows']),
        lyingThrows: _int(json['lyingThrows']),
      );

  final int gamesPlayed;
  final int gamesWon;
  final int gamesLost;
  final int winStreak;
  final int bestWinStreak;
  final int liesSurvived;
  final int liesCaught;
  final int checksWon;
  final int checksLost;
  final int cardsPickedUp;
  final int quadsDiscarded;
  final int jokerPassed;
  final int jokerSmuggles;
  final int truthfulThrows;
  final int lyingThrows;
}

/// `GET /me` / `PATCH /me` response (PATCH omits `stats`).
class MeProfile {
  const MeProfile({
    required this.userId,
    required this.nickname,
    required this.avatar,
    this.stats,
  });

  factory MeProfile.fromJson(Map<String, dynamic> json) => MeProfile(
        userId: json['userId'] as String,
        nickname: json['nickname'] as String,
        avatar: json['avatar'] as String,
        stats: json['stats'] == null
            ? null
            : LifetimeStats.fromJson(
                (json['stats'] as Map).cast<String, dynamic>()),
      );

  final String userId;
  final String nickname;
  final String avatar;
  final LifetimeStats? stats;
}

/// One `unlocked` entry of `GET /me/achievements`.
class AchievementUnlock {
  const AchievementUnlock({required this.key, required this.unlockedAt});

  factory AchievementUnlock.fromJson(Map<String, dynamic> json) =>
      AchievementUnlock(
        key: json['key'] as String,
        unlockedAt: _int(json['unlockedAt']),
      );

  final String key;

  /// Epoch ms.
  final int unlockedAt;

  DateTime get unlockedDate =>
      DateTime.fromMillisecondsSinceEpoch(unlockedAt);
}

/// One `catalog` entry of `GET /me/achievements` (server copy is English;
/// the client localizes by [key] and falls back to these).
class AchievementInfo {
  const AchievementInfo({
    required this.key,
    required this.title,
    required this.description,
    this.threshold,
    this.progress,
  });

  factory AchievementInfo.fromJson(Map<String, dynamic> json) =>
      AchievementInfo(
        key: json['key'] as String,
        title: json['title'] as String,
        description: json['description'] as String,
        threshold: json['threshold'] == null ? null : _int(json['threshold']),
        progress: json['progress'] == null ? null : _int(json['progress']),
      );

  final String key;
  final String title;
  final String description;
  final int? threshold;
  final int? progress;
}

/// `GET /me/achievements` response.
class MeAchievements {
  const MeAchievements({required this.unlocked, required this.catalog});

  factory MeAchievements.fromJson(Map<String, dynamic> json) => MeAchievements(
        unlocked: (json['unlocked'] as List? ?? const [])
            .map((e) =>
                AchievementUnlock.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
        catalog: (json['catalog'] as List? ?? const [])
            .map((e) =>
                AchievementInfo.fromJson((e as Map).cast<String, dynamic>()))
            .toList(),
      );

  final List<AchievementUnlock> unlocked;
  final List<AchievementInfo> catalog;

  /// Unlock timestamp by key, for the badge grid.
  Map<String, AchievementUnlock> get unlockedByKey =>
      {for (final u in unlocked) u.key: u};
}
