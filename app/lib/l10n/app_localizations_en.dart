// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Trude';

  @override
  String get nicknameTitle => 'Choose a nickname';

  @override
  String get nicknameHint => 'Nickname (2–16 characters)';

  @override
  String get nicknameInvalid => 'Nickname must be 2–16 characters';

  @override
  String get play => 'Play';

  @override
  String loginFailed(String reason) {
    return 'Login failed: $reason';
  }

  @override
  String get createRoom => 'Create Room';

  @override
  String get openRooms => 'Open Rooms';

  @override
  String get joinByCode => 'Join by Code';

  @override
  String get changeNickname => 'Change nickname';

  @override
  String playingAs(String nickname) {
    return 'Playing as $nickname';
  }

  @override
  String get joinByCodeTitle => 'Join by code';

  @override
  String get roomCodeHint => 'Room code';

  @override
  String get join => 'Join';

  @override
  String get cancel => 'Cancel';

  @override
  String get roomNotFound => 'Room not found';

  @override
  String get roomFull => 'Room is full';

  @override
  String get joinFailedGeneric =>
      'Couldn\'t join. Check the code and try again.';

  @override
  String get joinCodeDialogHint =>
      'The room creator has the code — shown in their lobby and at the table';

  @override
  String get createRoomTitle => 'Create a room';

  @override
  String get roomNameHint => 'Room name';

  @override
  String get publicRoom => 'Public';

  @override
  String get privateRoom => 'Private';

  @override
  String get deckLabel => 'Deck';

  @override
  String get create => 'Create';

  @override
  String deckOption(num size) {
    String _temp0 = intl.Intl.pluralLogic(
      size,
      locale: localeName,
      other: '$size cards',
      one: '$size card',
    );
    return '$_temp0';
  }

  @override
  String get createFailedGeneric => 'Couldn\'t create the room. Try again.';

  @override
  String get openRoomsTitle => 'Open rooms';

  @override
  String get noRoomsYet => 'No open rooms yet — create one!';

  @override
  String playersOf(int players, int max) {
    return '$players/$max players';
  }

  @override
  String get lobbyTitle => 'Lobby';

  @override
  String get start => 'Start';

  @override
  String get needTwoPlayers => 'Need at least 2 players to start';

  @override
  String get deckSizeLabel => 'Deck size';

  @override
  String get turnTimerLabel => 'Turn timer';

  @override
  String get maxPlayersLabel => 'Max players';

  @override
  String get adminBadge => 'Admin';

  @override
  String get youBadge => 'You';

  @override
  String roomCodeLabel(String code) {
    return 'Room code: $code';
  }

  @override
  String get shareCodeHint => 'Share this code — friends join with it';

  @override
  String secondsOption(int s) {
    return '${s}s';
  }

  @override
  String swapAsk(String nickname) {
    return 'Request a seat swap with $nickname?';
  }

  @override
  String get requestSwap => 'Request swap';

  @override
  String swapIncoming(String nickname) {
    return '$nickname wants to swap seats with you';
  }

  @override
  String get accept => 'Accept';

  @override
  String get decline => 'Decline';

  @override
  String get swapAccepted => 'Seat swap accepted';

  @override
  String get swapDeclined => 'Seat swap declined';

  @override
  String configLine(int deckSize, int turnTimerSec, int maxPlayers) {
    return 'Deck $deckSize · Timer ${turnTimerSec}s · Max $maxPlayers players';
  }

  @override
  String get mustCheckReason =>
      'Previous player has no cards left — you must check';

  @override
  String get throwButton => 'Throw';

  @override
  String get claimRankLabel => 'Claim rank';

  @override
  String get tapCardToFlip => 'Tap a card to flip it';

  @override
  String get yourTurnLead => 'Your turn — lead the pile';

  @override
  String get yourTurnRespond => 'Your turn — flip a card or throw';

  @override
  String get yourTurnForcedCheck => 'Your turn — flip a card';

  @override
  String forcedCheckTurn(String nickname) {
    return '$nickname must check';
  }

  @override
  String get respondChoiceHint =>
      'Flip one of their cards to call the bluff — or throw your own on top';

  @override
  String get selectCardsHint => 'Select up to 3 cards';

  @override
  String pileCount(int n) {
    return 'Pile: $n';
  }

  @override
  String lastClaimPlaque(String nickname, String claim) {
    return '$nickname: $claim';
  }

  @override
  String retiredRanksLabel(String ranks) {
    return 'Retired: $ranks';
  }

  @override
  String get noRetiredRanks => 'Retired: —';

  @override
  String countdown(int seconds) {
    return '${seconds}s';
  }

  @override
  String get outBadge => 'OUT';

  @override
  String get offlineBadge => 'offline';

  @override
  String get autoPilotBadge => 'auto';

  @override
  String get waitingForOpponent => 'Waiting…';

  @override
  String get leaveGameTitle => 'Leave the game?';

  @override
  String get leaveGameBody => 'A bot will take your seat.';

  @override
  String get leaveGameConfirm => 'Leave';

  @override
  String seatName(int number) {
    return 'Seat $number';
  }

  @override
  String get verdictTruth => 'TRUTH';

  @override
  String get verdictLiar => 'LIAR!';

  @override
  String get safeCallout => 'SAFE!';

  @override
  String claimCallout(String rank, String countKey, int count) {
    String _temp0 = intl.Intl.selectLogic(countKey, {
      'one': 'ONE TWO',
      'two': 'TWO TWOS',
      'three': 'THREE TWOS',
      'four': 'FOUR TWOS',
      'other': '$count TWOS',
    });
    String _temp1 = intl.Intl.selectLogic(countKey, {
      'one': 'ONE THREE',
      'two': 'TWO THREES',
      'three': 'THREE THREES',
      'four': 'FOUR THREES',
      'other': '$count THREES',
    });
    String _temp2 = intl.Intl.selectLogic(countKey, {
      'one': 'ONE FOUR',
      'two': 'TWO FOURS',
      'three': 'THREE FOURS',
      'four': 'FOUR FOURS',
      'other': '$count FOURS',
    });
    String _temp3 = intl.Intl.selectLogic(countKey, {
      'one': 'ONE FIVE',
      'two': 'TWO FIVES',
      'three': 'THREE FIVES',
      'four': 'FOUR FIVES',
      'other': '$count FIVES',
    });
    String _temp4 = intl.Intl.selectLogic(countKey, {
      'one': 'ONE SIX',
      'two': 'TWO SIXES',
      'three': 'THREE SIXES',
      'four': 'FOUR SIXES',
      'other': '$count SIXES',
    });
    String _temp5 = intl.Intl.selectLogic(countKey, {
      'one': 'ONE SEVEN',
      'two': 'TWO SEVENS',
      'three': 'THREE SEVENS',
      'four': 'FOUR SEVENS',
      'other': '$count SEVENS',
    });
    String _temp6 = intl.Intl.selectLogic(countKey, {
      'one': 'ONE EIGHT',
      'two': 'TWO EIGHTS',
      'three': 'THREE EIGHTS',
      'four': 'FOUR EIGHTS',
      'other': '$count EIGHTS',
    });
    String _temp7 = intl.Intl.selectLogic(countKey, {
      'one': 'ONE NINE',
      'two': 'TWO NINES',
      'three': 'THREE NINES',
      'four': 'FOUR NINES',
      'other': '$count NINES',
    });
    String _temp8 = intl.Intl.selectLogic(countKey, {
      'one': 'ONE TEN',
      'two': 'TWO TENS',
      'three': 'THREE TENS',
      'four': 'FOUR TENS',
      'other': '$count TENS',
    });
    String _temp9 = intl.Intl.selectLogic(countKey, {
      'one': 'ONE JACK',
      'two': 'TWO JACKS',
      'three': 'THREE JACKS',
      'four': 'FOUR JACKS',
      'other': '$count JACKS',
    });
    String _temp10 = intl.Intl.selectLogic(countKey, {
      'one': 'ONE QUEEN',
      'two': 'TWO QUEENS',
      'three': 'THREE QUEENS',
      'four': 'FOUR QUEENS',
      'other': '$count QUEENS',
    });
    String _temp11 = intl.Intl.selectLogic(countKey, {
      'one': 'ONE KING',
      'two': 'TWO KINGS',
      'three': 'THREE KINGS',
      'four': 'FOUR KINGS',
      'other': '$count KINGS',
    });
    String _temp12 = intl.Intl.selectLogic(countKey, {
      'one': 'ONE ACE',
      'two': 'TWO ACES',
      'three': 'THREE ACES',
      'four': 'FOUR ACES',
      'other': '$count ACES',
    });
    String _temp13 = intl.Intl.selectLogic(countKey, {
      'one': 'ONE JOKER',
      'other': '$count JOKERS',
    });
    String _temp14 = intl.Intl.selectLogic(rank, {
      'r2': '$_temp0',
      'r3': '$_temp1',
      'r4': '$_temp2',
      'r5': '$_temp3',
      'r6': '$_temp4',
      'r7': '$_temp5',
      'r8': '$_temp6',
      'r9': '$_temp7',
      'r10': '$_temp8',
      'jack': '$_temp9',
      'queen': '$_temp10',
      'king': '$_temp11',
      'ace': '$_temp12',
      'joker': '$_temp13',
      'other': '$count × $rank',
    });
    return '$_temp14!';
  }

  @override
  String quadBannerWrap(String claim) {
    return '$claim OUT!';
  }

  @override
  String jokerStaysWith(String nickname) {
    return 'THE JOKER STAYS WITH $nickname';
  }

  @override
  String get resultsTitle => 'Results';

  @override
  String get stayForRematch => 'Stay for rematch';

  @override
  String get leave => 'Leave';

  @override
  String placementLabel(String placementKey, int placement) {
    String _temp0 = intl.Intl.selectLogic(placementKey, {
      'first': '1st',
      'second': '2nd',
      'third': '3rd',
      'other': '${placement}th',
    });
    return '$_temp0';
  }

  @override
  String statsLine(int liesSurvived, int liesCaught, int checksWon) {
    return 'Lies survived: $liesSurvived · Lies caught: $liesCaught · Checks won: $checksWon';
  }

  @override
  String get unlockedThisGame => 'Unlocked this game';

  @override
  String rankWord(String rank) {
    String _temp0 = intl.Intl.selectLogic(rank, {
      'r2': 'TWO',
      'r3': 'THREE',
      'r4': 'FOUR',
      'r5': 'FIVE',
      'r6': 'SIX',
      'r7': 'SEVEN',
      'r8': 'EIGHT',
      'r9': 'NINE',
      'r10': 'TEN',
      'jack': 'JACK',
      'queen': 'QUEEN',
      'king': 'KING',
      'ace': 'ACE',
      'joker': 'JOKER',
      'other': '$rank',
    });
    return '$_temp0';
  }

  @override
  String rankShort(String rank) {
    String _temp0 = intl.Intl.selectLogic(rank, {
      'jack': 'J',
      'queen': 'Q',
      'king': 'K',
      'ace': 'A',
      'other': '$rank',
    });
    return '$_temp0';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get animationSpeedLabel => 'Animation speed';

  @override
  String get speedNormal => 'Normal';

  @override
  String get speedFast => 'Fast';

  @override
  String get speedOff => 'Off';

  @override
  String get soundLabel => 'Sound effects';

  @override
  String get hapticsLabel => 'Vibration';

  @override
  String get languageLabel => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageRussian => 'Русский';

  @override
  String get nicknameLabel => 'Nickname';

  @override
  String get save => 'Save';

  @override
  String get nicknameSaved => 'Nickname updated';

  @override
  String saveFailed(String reason) {
    return 'Could not save: $reason';
  }

  @override
  String get aboutLabel => 'About';

  @override
  String versionLabel(String version) {
    return 'Trude $version';
  }

  @override
  String statsStrip(int games, int wins, int streak) {
    return 'Games $games · Wins $wins · Best streak $streak';
  }

  @override
  String get achievementsTitle => 'Achievements';

  @override
  String get achievementUnlockedToast => 'Achievement unlocked!';

  @override
  String unlockedOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Unlocked $dateString';
  }

  @override
  String achievementsCount(int unlocked, int total) {
    return '$unlocked of $total unlocked';
  }

  @override
  String get achievementsLoadFailed =>
      'Couldn\'t load achievements — pull to retry';

  @override
  String achievementTitle(String key) {
    String _temp0 = intl.Intl.selectLogic(key, {
      'best_liar': 'The Best Liar',
      'pathological_truther': 'Pathological Truther',
      'human_polygraph': 'Human Polygraph',
      'gullible': 'Gullible',
      'poker_face': 'Poker Face',
      'smuggler': 'Smuggler',
      'hot_potato': 'Hot Potato',
      'jokers_best_friend': 'Joker\'s Best Friend',
      'demolition_crew': 'Demolition Crew',
      'comeback_season': 'Comeback Season',
      'serial_winner': 'Serial Winner',
      'it_wasnt_me': 'It Wasn\'t Me',
      'other': '~',
    });
    return '$_temp0';
  }

  @override
  String achievementDescription(String key) {
    String _temp0 = intl.Intl.selectLogic(key, {
      'best_liar': 'Win 10 games',
      'pathological_truther':
          'Win a game without a single lie (at least 8 truthful throws)',
      'human_polygraph': 'Catch 25 liars',
      'gullible': 'Flip a truthful card 15 times',
      'poker_face': 'Get away with 50 lies',
      'smuggler': 'Sneak the joker into someone else\'s hand 10 times',
      'hot_potato': 'Pass the joker on twice in a single game',
      'jokers_best_friend': 'Lose 5 games — the joker just likes you',
      'demolition_crew': 'Discard 10 four-of-a-kinds',
      'comeback_season': 'Win a game after holding 20 or more cards',
      'serial_winner': 'Win 3 games in a row',
      'it_wasnt_me':
          'Win a game where you lied at least 3 times and were never caught',
      'other': '~',
    });
    return '$_temp0';
  }

  @override
  String tierName(String tier) {
    String _temp0 = intl.Intl.selectLogic(tier, {
      'novice': 'Novice',
      'cardplayer': 'Card Player',
      'rogue': 'Rogue',
      'sharp': 'Card Sharp',
      'hustler': 'Hustler',
      'legend': 'Parlor Legend',
      'other': '$tier',
    });
    return '$_temp0';
  }

  @override
  String get rankUpToast => 'New rank!';

  @override
  String get leaderboardTitle => 'Roll of Honor';

  @override
  String get leaderboardWeekly => 'This Week';

  @override
  String get leaderboardAlltime => 'All Time';

  @override
  String get leaderboardEmpty =>
      'No names on the board yet — play a public game';

  @override
  String get leaderboardLoadFailed =>
      'Couldn\'t load the board — pull to retry';

  @override
  String leaderboardMyRank(int rank) {
    return 'Your place: $rank';
  }

  @override
  String gamesRatedLabel(num games) {
    String _temp0 = intl.Intl.pluralLogic(
      games,
      locale: localeName,
      other: '$games rated games',
      one: '$games rated game',
    );
    return '$_temp0';
  }

  @override
  String get shopTitle => 'The Shop';

  @override
  String get shopCardBacksSection => 'Card Backs';

  @override
  String get shopFeltsSection => 'Table Felts';

  @override
  String get shopCoinsSection => 'Coins';

  @override
  String get shopPremiumSection => 'Patronage';

  @override
  String shopWatchAd(int coins) {
    return '+$coins for a word from our patron';
  }

  @override
  String get shopOwned => 'Owned';

  @override
  String get shopEquipped => 'Equipped';

  @override
  String get shopPremiumLock => 'Patrons only';

  @override
  String get shopBuyConfirmTitle => 'A purchase';

  @override
  String shopBuyConfirmBody(String item, num coins) {
    String _temp0 = intl.Intl.pluralLogic(
      coins,
      locale: localeName,
      other: '$coins coins',
      one: '$coins coin',
    );
    return 'Buy “$item” for $_temp0?';
  }

  @override
  String get shopInsufficientFunds => 'Not enough coins in your purse';

  @override
  String get shopBillingUnavailable =>
      'This shelf is open in the mobile parlor';

  @override
  String get shopPurchaseWarningTitle => 'Before you buy';

  @override
  String get shopPurchaseWarningBody =>
      'Purchases are tied to the guest account on this device. Deleting the app or switching devices may lose them — proper sign-in arrives later.';

  @override
  String get restorePurchases => 'Restore purchases';

  @override
  String get restoreDone => 'Purchases restored';

  @override
  String get premiumTitle => 'Patron of the Parlor';

  @override
  String get premiumPitch =>
      'The gilded card back, a patron\'s mark — and no ads, ever.';

  @override
  String get premiumOwned => 'You are a patron of the parlor';

  @override
  String coinPackLabel(num coins) {
    String _temp0 = intl.Intl.pluralLogic(
      coins,
      locale: localeName,
      other: '$coins coins',
      one: '$coins coin',
    );
    return '$_temp0';
  }

  @override
  String get buy => 'Buy';

  @override
  String cosmeticName(String key) {
    String _temp0 = intl.Intl.selectLogic(key, {
      'cb_classic': 'Classic',
      'cb_crimson': 'Crimson',
      'cb_noir': 'Noir',
      'cb_royal': 'Royal',
      'cb_imperial': 'Imperial',
      'cb_gilded': 'Gilded',
      'felt_classic': 'Classic Felt',
      'felt_burgundy': 'Burgundy',
      'felt_navy': 'Navy',
      'felt_midnight': 'Midnight',
      'other': '$key',
    });
    return '$_temp0';
  }

  @override
  String get dailyBonusTitle => 'The house honors its regulars';

  @override
  String get dailyBonusSubtitle => 'Come back tomorrow — the streak grows';

  @override
  String dailyBonusDay(int day) {
    return 'Day $day';
  }

  @override
  String dailyBonusClaim(int coins) {
    return 'Claim $coins';
  }

  @override
  String get questsTitle => 'Tonight\'s Errands';

  @override
  String questRewardChip(int coins) {
    return '+$coins';
  }

  @override
  String questTitle(String key) {
    String _temp0 = intl.Intl.selectLogic(key, {
      'q_play_3': 'Table Regular',
      'q_win_1': 'Take the Pot',
      'q_catch_3': 'Sharp Eye',
      'q_survive_5': 'Smooth Talker',
      'q_truth_15': 'Honest Evening',
      'q_quad_1': 'Clean Sweep',
      'q_pass_joker': 'Hot Hands',
      'q_pickup_20': 'Take Your Lumps',
      'q_smuggle_1': 'Sleight of Hand',
      'other': '$key',
    });
    return '$_temp0';
  }

  @override
  String questDescription(String key) {
    String _temp0 = intl.Intl.selectLogic(key, {
      'q_play_3': 'Play 3 games',
      'q_win_1': 'Win a game',
      'q_catch_3': 'Catch 3 liars',
      'q_survive_5': 'Get away with 5 lies',
      'q_truth_15': 'Make 15 truthful throws',
      'q_quad_1': 'Discard a four-of-a-kind',
      'q_pass_joker': 'Pass the joker on',
      'q_pickup_20': 'Pick up 20 cards',
      'q_smuggle_1': 'Smuggle the joker into a throw',
      'other': '$key',
    });
    return '$_temp0';
  }

  @override
  String get rewardsPanelTitle => 'The evening\'s take';

  @override
  String get doubleWinnings => 'Double your winnings';

  @override
  String get doubledLabel => 'Doubled';

  @override
  String get unratedGame => 'Friendly game — unrated';

  @override
  String get deleteAccount => 'Delete account';

  @override
  String get deleteAccountTitle => 'Delete your account?';

  @override
  String get deleteAccountBody =>
      'Coins, rating, purchases, and progress will be gone for good.';

  @override
  String get deleteAccountSecondTitle => 'No way back';

  @override
  String get deleteAccountSecondBody =>
      'This cannot be undone. Delete the account?';

  @override
  String get deleteAccountConfirm => 'Delete';

  @override
  String deleteAccountFailed(String reason) {
    return 'Couldn\'t delete the account: $reason';
  }
}
