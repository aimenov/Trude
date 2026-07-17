/// Every user-visible string in the app, in one place.
///
/// Backed by Flutter gen-l10n (`lib/l10n/app_en.arb` / `app_ru.arb`). This
/// facade keeps the pre-l10n static API so widgets and core code (event feed
/// folding, callouts) don't need a BuildContext; [StringsSync] in the app
/// builder rebinds it whenever the ambient locale changes.
library;

import 'package:flutter/widgets.dart';

import '../l10n/app_localizations.dart';

/// Rebinds [Strings] to the enclosing [Localizations] locale. Mounted once in
/// the MaterialApp builder (above the Navigator), so it runs before any
/// screen builds and re-runs on locale change.
class StringsSync extends StatelessWidget {
  const StringsSync({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final l10n =
        Localizations.of<AppLocalizations>(context, AppLocalizations);
    if (l10n != null) Strings.use(l10n);
    return child;
  }
}

abstract final class Strings {
  static AppLocalizations _l = lookupAppLocalizations(const Locale('en'));

  /// The active translation bundle; swapped by [StringsSync] (or tests).
  static void use(AppLocalizations l10n) => _l = l10n;

  // App
  static String get appTitle => _l.appTitle;

  // Nickname screen
  static String get nicknameTitle => _l.nicknameTitle;
  static String get nicknameHint => _l.nicknameHint;
  static String get nicknameInvalid => _l.nicknameInvalid;
  static String get play => _l.play;
  static String loginFailed(String reason) => _l.loginFailed(reason);

  // Home screen
  static String get createRoom => _l.createRoom;
  static String get openRooms => _l.openRooms;
  static String get joinByCode => _l.joinByCode;
  static String get changeNickname => _l.changeNickname;
  static String playingAs(String nickname) => _l.playingAs(nickname);
  static String statsStrip(int games, int wins, int streak) =>
      _l.statsStrip(games, wins, streak);

  // Join-by-code dialog
  static String get joinByCodeTitle => _l.joinByCodeTitle;
  static String get roomCodeHint => _l.roomCodeHint;
  static String get join => _l.join;
  static String get cancel => _l.cancel;
  static String get roomNotFound => _l.roomNotFound;

  // Create-room dialog
  static String get createRoomTitle => _l.createRoomTitle;
  static String get roomNameHint => _l.roomNameHint;
  static String get publicRoom => _l.publicRoom;
  static String get privateRoom => _l.privateRoom;
  static String get deckLabel => _l.deckLabel;
  static String get create => _l.create;
  static String deckOption(int size) => _l.deckOption(size);

  // Open rooms screen
  static String get openRoomsTitle => _l.openRoomsTitle;
  static String get noRoomsYet => _l.noRoomsYet;
  static String playersOf(int players, int max) => _l.playersOf(players, max);
  static String deckBadge(int size) => '$size';
  static String joinFailed(String reason) => _l.joinFailed(reason);

  // Lobby screen
  static String get lobbyTitle => _l.lobbyTitle;
  static String get start => _l.start;
  static String get needTwoPlayers => _l.needTwoPlayers;
  static String get deckSizeLabel => _l.deckSizeLabel;
  static String get turnTimerLabel => _l.turnTimerLabel;
  static String get maxPlayersLabel => _l.maxPlayersLabel;
  static String get adminBadge => _l.adminBadge;
  static String get youBadge => _l.youBadge;
  static String roomCodeLabel(String code) => _l.roomCodeLabel(code);
  static String secondsOption(int s) => _l.secondsOption(s);
  static String swapAsk(String nickname) => _l.swapAsk(nickname);
  static String get requestSwap => _l.requestSwap;
  static String swapIncoming(String nickname) => _l.swapIncoming(nickname);
  static String get accept => _l.accept;
  static String get decline => _l.decline;
  static String get swapAccepted => _l.swapAccepted;
  static String get swapDeclined => _l.swapDeclined;
  static String configLine(int deckSize, int turnTimerSec, int maxPlayers) =>
      _l.configLine(deckSize, turnTimerSec, maxPlayers);

  // Game table
  static String get mustCheckReason => _l.mustCheckReason;
  static String get throwButton => _l.throwButton;
  static String get claimRankLabel => _l.claimRankLabel;
  static String get tapCardToFlip => _l.tapCardToFlip;
  static String get yourTurnLead => _l.yourTurnLead;
  static String get yourTurnRespond => _l.yourTurnRespond;
  static String get yourTurnForcedCheck => _l.yourTurnForcedCheck;
  static String forcedCheckTurn(String nickname) =>
      _l.forcedCheckTurn(nickname);
  static String get respondChoiceHint => _l.respondChoiceHint;
  static String get selectCardsHint => _l.selectCardsHint;
  static String pileCount(int n) => _l.pileCount(n);

  /// «Вася: ТРИ СЕМЁРКИ» — the standing claim engraved under the laid-down
  /// row; [claim] comes from [claimBody].
  static String lastClaimPlaque(String nickname, String claim) =>
      _l.lastClaimPlaque(nickname, claim);
  static String retiredRanksLabel(String ranks) => _l.retiredRanksLabel(ranks);
  static String get noRetiredRanks => _l.noRetiredRanks;
  static String countdown(int seconds) => _l.countdown(seconds);
  static String get outBadge => _l.outBadge;
  static String get offlineBadge => _l.offlineBadge;
  static String get autoPilotBadge => _l.autoPilotBadge;
  static String get waitingForOpponent => _l.waitingForOpponent;

  // Seats
  static String seatName(int seat) => _l.seatName(seat + 1);

  // Set pieces (animation pass)
  static String get verdictTruth => _l.verdictTruth;
  static String get verdictLiar => _l.verdictLiar;
  static String get safeCallout => _l.safeCallout;

  /// "THREE SEVENS!" / "ТРИ СЕМЁРКИ!" — the claim callout stamped next to the
  /// thrower, with correct numeral+noun agreement per locale (ICU select in
  /// the ARB; [_countKey] carries the spelled 1–4 counts).
  static String claimCallout(int count, String rank) =>
      _l.claimCallout(_rankKey(rank), _countKey(count), count);

  /// "FOUR SEVENS OUT!" / "ЧЕТЫРЕ СЕМЁРКИ — В СБРОС!"
  static String quadBanner(String rank) =>
      _l.quadBannerWrap(claimBody(4, rank));

  static String jokerStaysWith(String nickname) => _l.jokerStaysWith(nickname);

  // Results screen
  static String get resultsTitle => _l.resultsTitle;
  static String get stayForRematch => _l.stayForRematch;
  static String get leave => _l.leave;
  static const loserMark = '\u{1F0CF}'; // 🃏
  static String placementLabel(int placement) => _l.placementLabel(
      switch (placement) {
        1 => 'first',
        2 => 'second',
        3 => 'third',
        _ => 'other',
      },
      placement);
  static String statsLine(int liesSurvived, int liesCaught, int checksWon) =>
      _l.statsLine(liesSurvived, liesCaught, checksWon);
  static String get unlockedThisGame => _l.unlockedThisGame;

  // Settings screen
  static String get settingsTitle => _l.settingsTitle;
  static String get animationSpeedLabel => _l.animationSpeedLabel;
  static String get speedNormal => _l.speedNormal;
  static String get speedFast => _l.speedFast;
  static String get speedOff => _l.speedOff;
  static String get soundLabel => _l.soundLabel;
  static String get hapticsLabel => _l.hapticsLabel;
  static String get languageLabel => _l.languageLabel;
  static String get languageSystem => _l.languageSystem;
  static String get languageEnglish => _l.languageEnglish;
  static String get languageRussian => _l.languageRussian;
  static String get nicknameLabel => _l.nicknameLabel;
  static String get save => _l.save;
  static String get nicknameSaved => _l.nicknameSaved;
  static String saveFailed(String reason) => _l.saveFailed(reason);
  static String get aboutLabel => _l.aboutLabel;
  static String versionLabel(String version) => _l.versionLabel(version);

  // Achievements
  static String get achievementsTitle => _l.achievementsTitle;
  static String get achievementUnlockedToast => _l.achievementUnlockedToast;
  static String unlockedOn(DateTime date) => _l.unlockedOn(date);
  static String achievementsCount(int unlocked, int total) =>
      _l.achievementsCount(unlocked, total);
  static String get achievementsLoadFailed => _l.achievementsLoadFailed;

  /// Localized achievement title by catalog key; unknown keys fall back to
  /// the server-provided (English) text.
  static String achievementTitle(String key, String fallback) {
    final v = _l.achievementTitle(key);
    return v == '~' ? fallback : v;
  }

  static String achievementDescription(String key, String fallback) {
    final v = _l.achievementDescription(key);
    return v == '~' ? fallback : v;
  }

  // Errors
  static String serverError(String code, String message) =>
      message.isEmpty ? code : '$code: $message';

  // Reactions (allowlist key -> displayed emoji)
  static const reactionEmoji = <String, String>{
    'joy': '\u{1F602}',
    'sob': '\u{1F62D}',
    'angry': '\u{1F621}',
    'monocle': '\u{1F9D0}',
    'clown': '\u{1F921}',
    'fire': '\u{1F525}',
    'thumbsup': '\u{1F44D}',
    'scream': '\u{1F631}',
  };

  // Cards
  static const jokerShort = '\u{1F0CF}';
  static const suitSymbols = <String, String>{
    'C': '♣',
    'D': '♦',
    'H': '♥',
    'S': '♠',
  };

  /// Card-corner rank glyph: numerals pass through, courts localize
  /// (J Q K A / В Д К Т).
  static String rankShort(String rank) {
    final key = _rankKey(rank);
    // Numeric ranks map to ICU keys like 'r7' which the ARB select falls
    // through to `other{{rank}}` — that would render the raw key. Numerals
    // are locale-independent, so pass them straight through.
    if (key.startsWith('r')) return rank;
    return _l.rankShort(key);
  }

  /// "7" -> "SEVEN" / "СЕМЁРКА" (dropdowns, pile label).
  static String rankWord(String rank) => _l.rankWord(_rankKey(rank));

  /// Claim text without the trailing "!" ("FOUR SEVENS" / "ЧЕТЫРЕ СЕМЁРКИ").
  /// Reuses the [claimCallout] ICU, so RU numeral+noun agreement holds.
  static String claimBody(int count, String rank) {
    final claim = claimCallout(count, rank);
    return claim.endsWith('!') ? claim.substring(0, claim.length - 1) : claim;
  }

  static String _countKey(int n) => switch (n) {
        1 => 'one',
        2 => 'two',
        3 => 'three',
        4 => 'four',
        _ => 'other',
      };

  /// Wire rank -> ICU select key ("7" -> "r7", "J" -> "jack").
  static String _rankKey(String rank) => switch (rank) {
        'J' => 'jack',
        'Q' => 'queen',
        'K' => 'king',
        'A' => 'ace',
        'JOKER' => 'joker',
        _ => 'r$rank',
      };
}
