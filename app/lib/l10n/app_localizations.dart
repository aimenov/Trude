import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('ru'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Trude'**
  String get appTitle;

  /// No description provided for @nicknameTitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a nickname'**
  String get nicknameTitle;

  /// No description provided for @nicknameHint.
  ///
  /// In en, this message translates to:
  /// **'Nickname (2–16 characters)'**
  String get nicknameHint;

  /// No description provided for @nicknameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Nickname must be 2–16 characters'**
  String get nicknameInvalid;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @loginFailed.
  ///
  /// In en, this message translates to:
  /// **'Login failed: {reason}'**
  String loginFailed(String reason);

  /// No description provided for @createRoom.
  ///
  /// In en, this message translates to:
  /// **'Create Room'**
  String get createRoom;

  /// No description provided for @openRooms.
  ///
  /// In en, this message translates to:
  /// **'Open Rooms'**
  String get openRooms;

  /// No description provided for @joinByCode.
  ///
  /// In en, this message translates to:
  /// **'Join by Code'**
  String get joinByCode;

  /// No description provided for @changeNickname.
  ///
  /// In en, this message translates to:
  /// **'Change nickname'**
  String get changeNickname;

  /// No description provided for @playingAs.
  ///
  /// In en, this message translates to:
  /// **'Playing as {nickname}'**
  String playingAs(String nickname);

  /// No description provided for @joinByCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Join by code'**
  String get joinByCodeTitle;

  /// No description provided for @roomCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Room code'**
  String get roomCodeHint;

  /// No description provided for @join.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @roomNotFound.
  ///
  /// In en, this message translates to:
  /// **'Room not found'**
  String get roomNotFound;

  /// No description provided for @createRoomTitle.
  ///
  /// In en, this message translates to:
  /// **'Create a room'**
  String get createRoomTitle;

  /// No description provided for @roomNameHint.
  ///
  /// In en, this message translates to:
  /// **'Room name'**
  String get roomNameHint;

  /// No description provided for @publicRoom.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get publicRoom;

  /// No description provided for @privateRoom.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get privateRoom;

  /// No description provided for @deckLabel.
  ///
  /// In en, this message translates to:
  /// **'Deck'**
  String get deckLabel;

  /// No description provided for @create.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// No description provided for @deckOption.
  ///
  /// In en, this message translates to:
  /// **'{size, plural, =1{{size} card} other{{size} cards}}'**
  String deckOption(num size);

  /// No description provided for @openRoomsTitle.
  ///
  /// In en, this message translates to:
  /// **'Open rooms'**
  String get openRoomsTitle;

  /// No description provided for @noRoomsYet.
  ///
  /// In en, this message translates to:
  /// **'No open rooms yet — create one!'**
  String get noRoomsYet;

  /// No description provided for @playersOf.
  ///
  /// In en, this message translates to:
  /// **'{players}/{max} players'**
  String playersOf(int players, int max);

  /// No description provided for @joinFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not join: {reason}'**
  String joinFailed(String reason);

  /// No description provided for @lobbyTitle.
  ///
  /// In en, this message translates to:
  /// **'Lobby'**
  String get lobbyTitle;

  /// No description provided for @start.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get start;

  /// No description provided for @needTwoPlayers.
  ///
  /// In en, this message translates to:
  /// **'Need at least 2 players to start'**
  String get needTwoPlayers;

  /// No description provided for @deckSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Deck size'**
  String get deckSizeLabel;

  /// No description provided for @turnTimerLabel.
  ///
  /// In en, this message translates to:
  /// **'Turn timer'**
  String get turnTimerLabel;

  /// No description provided for @maxPlayersLabel.
  ///
  /// In en, this message translates to:
  /// **'Max players'**
  String get maxPlayersLabel;

  /// No description provided for @adminBadge.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get adminBadge;

  /// No description provided for @youBadge.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get youBadge;

  /// No description provided for @roomCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Room code: {code}'**
  String roomCodeLabel(String code);

  /// No description provided for @secondsOption.
  ///
  /// In en, this message translates to:
  /// **'{s}s'**
  String secondsOption(int s);

  /// No description provided for @swapAsk.
  ///
  /// In en, this message translates to:
  /// **'Request a seat swap with {nickname}?'**
  String swapAsk(String nickname);

  /// No description provided for @requestSwap.
  ///
  /// In en, this message translates to:
  /// **'Request swap'**
  String get requestSwap;

  /// No description provided for @swapIncoming.
  ///
  /// In en, this message translates to:
  /// **'{nickname} wants to swap seats with you'**
  String swapIncoming(String nickname);

  /// No description provided for @accept.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// No description provided for @decline.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get decline;

  /// No description provided for @swapAccepted.
  ///
  /// In en, this message translates to:
  /// **'Seat swap accepted'**
  String get swapAccepted;

  /// No description provided for @swapDeclined.
  ///
  /// In en, this message translates to:
  /// **'Seat swap declined'**
  String get swapDeclined;

  /// No description provided for @configLine.
  ///
  /// In en, this message translates to:
  /// **'Deck {deckSize} · Timer {turnTimerSec}s · Max {maxPlayers} players'**
  String configLine(int deckSize, int turnTimerSec, int maxPlayers);

  /// No description provided for @playingRankLabel.
  ///
  /// In en, this message translates to:
  /// **'Playing: {word}'**
  String playingRankLabel(String word);

  /// No description provided for @freshPile.
  ///
  /// In en, this message translates to:
  /// **'New pile — leader names a rank'**
  String get freshPile;

  /// No description provided for @trust.
  ///
  /// In en, this message translates to:
  /// **'TRUST'**
  String get trust;

  /// No description provided for @check.
  ///
  /// In en, this message translates to:
  /// **'CHECK'**
  String get check;

  /// No description provided for @mustCheckReason.
  ///
  /// In en, this message translates to:
  /// **'Previous player has no cards left — you must check'**
  String get mustCheckReason;

  /// No description provided for @throwButton.
  ///
  /// In en, this message translates to:
  /// **'Throw'**
  String get throwButton;

  /// No description provided for @claimRankLabel.
  ///
  /// In en, this message translates to:
  /// **'Claim rank'**
  String get claimRankLabel;

  /// No description provided for @tapCardToFlip.
  ///
  /// In en, this message translates to:
  /// **'Tap a card to flip it'**
  String get tapCardToFlip;

  /// No description provided for @yourTurnLead.
  ///
  /// In en, this message translates to:
  /// **'Your turn — lead the pile'**
  String get yourTurnLead;

  /// No description provided for @yourTurnRespond.
  ///
  /// In en, this message translates to:
  /// **'Your turn — trust or check'**
  String get yourTurnRespond;

  /// No description provided for @selectCardsHint.
  ///
  /// In en, this message translates to:
  /// **'Select up to 3 cards'**
  String get selectCardsHint;

  /// No description provided for @pileCount.
  ///
  /// In en, this message translates to:
  /// **'Pile: {n}'**
  String pileCount(int n);

  /// No description provided for @lastThrowLabel.
  ///
  /// In en, this message translates to:
  /// **'Last throw: {n}'**
  String lastThrowLabel(int n);

  /// No description provided for @retiredRanksLabel.
  ///
  /// In en, this message translates to:
  /// **'Retired: {ranks}'**
  String retiredRanksLabel(String ranks);

  /// No description provided for @noRetiredRanks.
  ///
  /// In en, this message translates to:
  /// **'Retired: —'**
  String get noRetiredRanks;

  /// No description provided for @countdown.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String countdown(int seconds);

  /// No description provided for @outBadge.
  ///
  /// In en, this message translates to:
  /// **'OUT'**
  String get outBadge;

  /// No description provided for @offlineBadge.
  ///
  /// In en, this message translates to:
  /// **'offline'**
  String get offlineBadge;

  /// No description provided for @autoPilotBadge.
  ///
  /// In en, this message translates to:
  /// **'auto'**
  String get autoPilotBadge;

  /// No description provided for @waitingForOpponent.
  ///
  /// In en, this message translates to:
  /// **'Waiting…'**
  String get waitingForOpponent;

  /// No description provided for @threwEvent.
  ///
  /// In en, this message translates to:
  /// **'{nickname} threw {claim}'**
  String threwEvent(String nickname, String claim);

  /// No description provided for @liarEvent.
  ///
  /// In en, this message translates to:
  /// **'LIAR! {nickname} picks up {count, plural, =1{1 card} other{{count} cards}}'**
  String liarEvent(String nickname, num count);

  /// No description provided for @truthEvent.
  ///
  /// In en, this message translates to:
  /// **'It was true — {nickname} picks up {count, plural, =1{1 card} other{{count} cards}}'**
  String truthEvent(String nickname, num count);

  /// No description provided for @fourDiscardedEvent.
  ///
  /// In en, this message translates to:
  /// **'{nickname} discarded {claim}'**
  String fourDiscardedEvent(String nickname, String claim);

  /// No description provided for @playerOutEvent.
  ///
  /// In en, this message translates to:
  /// **'{nickname} is out — safe!'**
  String playerOutEvent(String nickname);

  /// No description provided for @autoActedEvent.
  ///
  /// In en, this message translates to:
  /// **'{nickname} acted on timeout'**
  String autoActedEvent(String nickname);

  /// No description provided for @playerJoinedEvent.
  ///
  /// In en, this message translates to:
  /// **'{nickname} joined'**
  String playerJoinedEvent(String nickname);

  /// No description provided for @playerLeftEvent.
  ///
  /// In en, this message translates to:
  /// **'{nickname} left'**
  String playerLeftEvent(String nickname);

  /// No description provided for @gameStartedEvent.
  ///
  /// In en, this message translates to:
  /// **'Game started!'**
  String get gameStartedEvent;

  /// No description provided for @gameOverEventText.
  ///
  /// In en, this message translates to:
  /// **'Game over'**
  String get gameOverEventText;

  /// No description provided for @seatName.
  ///
  /// In en, this message translates to:
  /// **'Seat {number}'**
  String seatName(int number);

  /// No description provided for @verdictTruth.
  ///
  /// In en, this message translates to:
  /// **'TRUTH'**
  String get verdictTruth;

  /// No description provided for @verdictLiar.
  ///
  /// In en, this message translates to:
  /// **'LIAR!'**
  String get verdictLiar;

  /// No description provided for @safeCallout.
  ///
  /// In en, this message translates to:
  /// **'SAFE!'**
  String get safeCallout;

  /// No description provided for @claimCallout.
  ///
  /// In en, this message translates to:
  /// **'{rank, select, r2{{countKey, select, one{ONE TWO} two{TWO TWOS} three{THREE TWOS} four{FOUR TWOS} other{{count} TWOS}}} r3{{countKey, select, one{ONE THREE} two{TWO THREES} three{THREE THREES} four{FOUR THREES} other{{count} THREES}}} r4{{countKey, select, one{ONE FOUR} two{TWO FOURS} three{THREE FOURS} four{FOUR FOURS} other{{count} FOURS}}} r5{{countKey, select, one{ONE FIVE} two{TWO FIVES} three{THREE FIVES} four{FOUR FIVES} other{{count} FIVES}}} r6{{countKey, select, one{ONE SIX} two{TWO SIXES} three{THREE SIXES} four{FOUR SIXES} other{{count} SIXES}}} r7{{countKey, select, one{ONE SEVEN} two{TWO SEVENS} three{THREE SEVENS} four{FOUR SEVENS} other{{count} SEVENS}}} r8{{countKey, select, one{ONE EIGHT} two{TWO EIGHTS} three{THREE EIGHTS} four{FOUR EIGHTS} other{{count} EIGHTS}}} r9{{countKey, select, one{ONE NINE} two{TWO NINES} three{THREE NINES} four{FOUR NINES} other{{count} NINES}}} r10{{countKey, select, one{ONE TEN} two{TWO TENS} three{THREE TENS} four{FOUR TENS} other{{count} TENS}}} jack{{countKey, select, one{ONE JACK} two{TWO JACKS} three{THREE JACKS} four{FOUR JACKS} other{{count} JACKS}}} queen{{countKey, select, one{ONE QUEEN} two{TWO QUEENS} three{THREE QUEENS} four{FOUR QUEENS} other{{count} QUEENS}}} king{{countKey, select, one{ONE KING} two{TWO KINGS} three{THREE KINGS} four{FOUR KINGS} other{{count} KINGS}}} ace{{countKey, select, one{ONE ACE} two{TWO ACES} three{THREE ACES} four{FOUR ACES} other{{count} ACES}}} joker{{countKey, select, one{ONE JOKER} other{{count} JOKERS}}} other{{count} × {rank}}}!'**
  String claimCallout(String rank, String countKey, int count);

  /// No description provided for @quadBannerWrap.
  ///
  /// In en, this message translates to:
  /// **'{claim} OUT!'**
  String quadBannerWrap(String claim);

  /// No description provided for @jokerStaysWith.
  ///
  /// In en, this message translates to:
  /// **'THE JOKER STAYS WITH {nickname}'**
  String jokerStaysWith(String nickname);

  /// No description provided for @resultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get resultsTitle;

  /// No description provided for @stayForRematch.
  ///
  /// In en, this message translates to:
  /// **'Stay for rematch'**
  String get stayForRematch;

  /// No description provided for @leave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get leave;

  /// No description provided for @placementLabel.
  ///
  /// In en, this message translates to:
  /// **'{placementKey, select, first{1st} second{2nd} third{3rd} other{{placement}th}}'**
  String placementLabel(String placementKey, int placement);

  /// No description provided for @statsLine.
  ///
  /// In en, this message translates to:
  /// **'Lies survived: {liesSurvived} · Lies caught: {liesCaught} · Checks won: {checksWon}'**
  String statsLine(int liesSurvived, int liesCaught, int checksWon);

  /// No description provided for @unlockedThisGame.
  ///
  /// In en, this message translates to:
  /// **'Unlocked this game'**
  String get unlockedThisGame;

  /// No description provided for @rankWord.
  ///
  /// In en, this message translates to:
  /// **'{rank, select, r2{TWO} r3{THREE} r4{FOUR} r5{FIVE} r6{SIX} r7{SEVEN} r8{EIGHT} r9{NINE} r10{TEN} jack{JACK} queen{QUEEN} king{KING} ace{ACE} joker{JOKER} other{{rank}}}'**
  String rankWord(String rank);

  /// No description provided for @rankPlural.
  ///
  /// In en, this message translates to:
  /// **'{rank, select, r2{TWOS} r3{THREES} r4{FOURS} r5{FIVES} r6{SIXES} r7{SEVENS} r8{EIGHTS} r9{NINES} r10{TENS} jack{JACKS} queen{QUEENS} king{KINGS} ace{ACES} joker{JOKERS} other{{rank}}}'**
  String rankPlural(String rank);

  /// No description provided for @rankShort.
  ///
  /// In en, this message translates to:
  /// **'{rank, select, jack{J} queen{Q} king{K} ace{A} other{{rank}}}'**
  String rankShort(String rank);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @animationSpeedLabel.
  ///
  /// In en, this message translates to:
  /// **'Animation speed'**
  String get animationSpeedLabel;

  /// No description provided for @speedNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get speedNormal;

  /// No description provided for @speedFast.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get speedFast;

  /// No description provided for @speedOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get speedOff;

  /// No description provided for @soundLabel.
  ///
  /// In en, this message translates to:
  /// **'Sound effects'**
  String get soundLabel;

  /// No description provided for @hapticsLabel.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get hapticsLabel;

  /// No description provided for @languageLabel.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageLabel;

  /// No description provided for @languageSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// No description provided for @languageEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageRussian.
  ///
  /// In en, this message translates to:
  /// **'Русский'**
  String get languageRussian;

  /// No description provided for @nicknameLabel.
  ///
  /// In en, this message translates to:
  /// **'Nickname'**
  String get nicknameLabel;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @nicknameSaved.
  ///
  /// In en, this message translates to:
  /// **'Nickname updated'**
  String get nicknameSaved;

  /// No description provided for @saveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save: {reason}'**
  String saveFailed(String reason);

  /// No description provided for @aboutLabel.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aboutLabel;

  /// No description provided for @versionLabel.
  ///
  /// In en, this message translates to:
  /// **'Trude {version}'**
  String versionLabel(String version);

  /// No description provided for @statsStrip.
  ///
  /// In en, this message translates to:
  /// **'Games {games} · Wins {wins} · Best streak {streak}'**
  String statsStrip(int games, int wins, int streak);

  /// No description provided for @achievementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get achievementsTitle;

  /// No description provided for @achievementUnlockedToast.
  ///
  /// In en, this message translates to:
  /// **'Achievement unlocked!'**
  String get achievementUnlockedToast;

  /// No description provided for @unlockedOn.
  ///
  /// In en, this message translates to:
  /// **'Unlocked {date}'**
  String unlockedOn(DateTime date);

  /// No description provided for @achievementsCount.
  ///
  /// In en, this message translates to:
  /// **'{unlocked} of {total} unlocked'**
  String achievementsCount(int unlocked, int total);

  /// No description provided for @achievementsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load achievements — pull to retry'**
  String get achievementsLoadFailed;

  /// No description provided for @achievementTitle.
  ///
  /// In en, this message translates to:
  /// **'{key, select, best_liar{The Best Liar} pathological_truther{Pathological Truther} human_polygraph{Human Polygraph} gullible{Gullible} poker_face{Poker Face} smuggler{Smuggler} hot_potato{Hot Potato} jokers_best_friend{Joker\'s Best Friend} demolition_crew{Demolition Crew} comeback_season{Comeback Season} serial_winner{Serial Winner} it_wasnt_me{It Wasn\'t Me} other{~}}'**
  String achievementTitle(String key);

  /// No description provided for @achievementDescription.
  ///
  /// In en, this message translates to:
  /// **'{key, select, best_liar{Win 10 games} pathological_truther{Win a game without a single lie (at least 8 truthful throws)} human_polygraph{Catch 25 liars} gullible{Flip a truthful card 15 times} poker_face{Get away with 50 lies} smuggler{Sneak the joker into someone else\'s hand 10 times} hot_potato{Pass the joker on twice in a single game} jokers_best_friend{Lose 5 games — the joker just likes you} demolition_crew{Discard 10 four-of-a-kinds} comeback_season{Win a game after holding 20 or more cards} serial_winner{Win 3 games in a row} it_wasnt_me{Win a game where you lied at least 3 times and were never caught} other{~}}'**
  String achievementDescription(String key);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'ru'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
