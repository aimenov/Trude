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

  /// No description provided for @roomFull.
  ///
  /// In en, this message translates to:
  /// **'Room is full'**
  String get roomFull;

  /// No description provided for @joinFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t join. Check the code and try again.'**
  String get joinFailedGeneric;

  /// No description provided for @joinCodeDialogHint.
  ///
  /// In en, this message translates to:
  /// **'The room creator has the code — shown in their lobby and at the table'**
  String get joinCodeDialogHint;

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

  /// No description provided for @createFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t create the room. Try again.'**
  String get createFailedGeneric;

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

  /// No description provided for @shareCodeHint.
  ///
  /// In en, this message translates to:
  /// **'Share this code — friends join with it'**
  String get shareCodeHint;

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
  /// **'Your turn — flip a card or throw'**
  String get yourTurnRespond;

  /// No description provided for @yourTurnForcedCheck.
  ///
  /// In en, this message translates to:
  /// **'Your turn — flip a card'**
  String get yourTurnForcedCheck;

  /// No description provided for @forcedCheckTurn.
  ///
  /// In en, this message translates to:
  /// **'{nickname} must check'**
  String forcedCheckTurn(String nickname);

  /// No description provided for @respondChoiceHint.
  ///
  /// In en, this message translates to:
  /// **'Flip one of their cards to call the bluff — or throw your own on top'**
  String get respondChoiceHint;

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

  /// No description provided for @lastClaimPlaque.
  ///
  /// In en, this message translates to:
  /// **'{nickname}: {claim}'**
  String lastClaimPlaque(String nickname, String claim);

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

  /// No description provided for @leaveGameTitle.
  ///
  /// In en, this message translates to:
  /// **'Leave the game?'**
  String get leaveGameTitle;

  /// No description provided for @leaveGameBody.
  ///
  /// In en, this message translates to:
  /// **'A bot will take your seat.'**
  String get leaveGameBody;

  /// No description provided for @leaveGameConfirm.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get leaveGameConfirm;

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

  /// No description provided for @tierName.
  ///
  /// In en, this message translates to:
  /// **'{tier, select, novice{Novice} cardplayer{Card Player} rogue{Rogue} sharp{Card Sharp} hustler{Hustler} legend{Parlor Legend} other{{tier}}}'**
  String tierName(String tier);

  /// No description provided for @rankUpToast.
  ///
  /// In en, this message translates to:
  /// **'New rank!'**
  String get rankUpToast;

  /// No description provided for @leaderboardTitle.
  ///
  /// In en, this message translates to:
  /// **'Roll of Honor'**
  String get leaderboardTitle;

  /// No description provided for @leaderboardWeekly.
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get leaderboardWeekly;

  /// No description provided for @leaderboardAlltime.
  ///
  /// In en, this message translates to:
  /// **'All Time'**
  String get leaderboardAlltime;

  /// No description provided for @leaderboardEmpty.
  ///
  /// In en, this message translates to:
  /// **'No names on the board yet — play a public game'**
  String get leaderboardEmpty;

  /// No description provided for @leaderboardLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load the board — pull to retry'**
  String get leaderboardLoadFailed;

  /// No description provided for @leaderboardMyRank.
  ///
  /// In en, this message translates to:
  /// **'Your place: {rank}'**
  String leaderboardMyRank(int rank);

  /// No description provided for @gamesRatedLabel.
  ///
  /// In en, this message translates to:
  /// **'{games, plural, =1{{games} rated game} other{{games} rated games}}'**
  String gamesRatedLabel(num games);

  /// No description provided for @shopTitle.
  ///
  /// In en, this message translates to:
  /// **'The Shop'**
  String get shopTitle;

  /// No description provided for @shopCardBacksSection.
  ///
  /// In en, this message translates to:
  /// **'Card Backs'**
  String get shopCardBacksSection;

  /// No description provided for @shopFeltsSection.
  ///
  /// In en, this message translates to:
  /// **'Table Felts'**
  String get shopFeltsSection;

  /// No description provided for @shopCoinsSection.
  ///
  /// In en, this message translates to:
  /// **'Coins'**
  String get shopCoinsSection;

  /// No description provided for @shopPremiumSection.
  ///
  /// In en, this message translates to:
  /// **'Patronage'**
  String get shopPremiumSection;

  /// No description provided for @shopWatchAd.
  ///
  /// In en, this message translates to:
  /// **'+{coins} for a word from our patron'**
  String shopWatchAd(int coins);

  /// No description provided for @shopOwned.
  ///
  /// In en, this message translates to:
  /// **'Owned'**
  String get shopOwned;

  /// No description provided for @shopEquipped.
  ///
  /// In en, this message translates to:
  /// **'Equipped'**
  String get shopEquipped;

  /// No description provided for @shopPremiumLock.
  ///
  /// In en, this message translates to:
  /// **'Patrons only'**
  String get shopPremiumLock;

  /// No description provided for @shopBuyConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'A purchase'**
  String get shopBuyConfirmTitle;

  /// No description provided for @shopBuyConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Buy “{item}” for {coins, plural, =1{{coins} coin} other{{coins} coins}}?'**
  String shopBuyConfirmBody(String item, num coins);

  /// No description provided for @shopInsufficientFunds.
  ///
  /// In en, this message translates to:
  /// **'Not enough coins in your purse'**
  String get shopInsufficientFunds;

  /// No description provided for @shopBillingUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This shelf is open in the mobile parlor'**
  String get shopBillingUnavailable;

  /// No description provided for @shopPurchaseWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Before you buy'**
  String get shopPurchaseWarningTitle;

  /// No description provided for @shopPurchaseWarningBody.
  ///
  /// In en, this message translates to:
  /// **'Purchases are tied to the guest account on this device. Deleting the app or switching devices may lose them — proper sign-in arrives later.'**
  String get shopPurchaseWarningBody;

  /// No description provided for @restorePurchases.
  ///
  /// In en, this message translates to:
  /// **'Restore purchases'**
  String get restorePurchases;

  /// No description provided for @restoreDone.
  ///
  /// In en, this message translates to:
  /// **'Purchases restored'**
  String get restoreDone;

  /// No description provided for @premiumTitle.
  ///
  /// In en, this message translates to:
  /// **'Patron of the Parlor'**
  String get premiumTitle;

  /// No description provided for @premiumPitch.
  ///
  /// In en, this message translates to:
  /// **'The gilded card back, a patron\'s mark — and no ads, ever.'**
  String get premiumPitch;

  /// No description provided for @premiumOwned.
  ///
  /// In en, this message translates to:
  /// **'You are a patron of the parlor'**
  String get premiumOwned;

  /// No description provided for @coinPackLabel.
  ///
  /// In en, this message translates to:
  /// **'{coins, plural, =1{{coins} coin} other{{coins} coins}}'**
  String coinPackLabel(num coins);

  /// No description provided for @buy.
  ///
  /// In en, this message translates to:
  /// **'Buy'**
  String get buy;

  /// No description provided for @cosmeticName.
  ///
  /// In en, this message translates to:
  /// **'{key, select, cb_classic{Classic} cb_crimson{Crimson} cb_noir{Noir} cb_royal{Royal} cb_imperial{Imperial} cb_gilded{Gilded} felt_classic{Classic Felt} felt_burgundy{Burgundy} felt_navy{Navy} felt_midnight{Midnight} other{{key}}}'**
  String cosmeticName(String key);

  /// No description provided for @dailyBonusTitle.
  ///
  /// In en, this message translates to:
  /// **'The house honors its regulars'**
  String get dailyBonusTitle;

  /// No description provided for @dailyBonusSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Come back tomorrow — the streak grows'**
  String get dailyBonusSubtitle;

  /// No description provided for @dailyBonusDay.
  ///
  /// In en, this message translates to:
  /// **'Day {day}'**
  String dailyBonusDay(int day);

  /// No description provided for @dailyBonusClaim.
  ///
  /// In en, this message translates to:
  /// **'Claim {coins}'**
  String dailyBonusClaim(int coins);

  /// No description provided for @questsTitle.
  ///
  /// In en, this message translates to:
  /// **'Tonight\'s Errands'**
  String get questsTitle;

  /// No description provided for @questRewardChip.
  ///
  /// In en, this message translates to:
  /// **'+{coins}'**
  String questRewardChip(int coins);

  /// No description provided for @questTitle.
  ///
  /// In en, this message translates to:
  /// **'{key, select, q_play_3{Table Regular} q_win_1{Take the Pot} q_catch_3{Sharp Eye} q_survive_5{Smooth Talker} q_truth_15{Honest Evening} q_quad_1{Clean Sweep} q_pass_joker{Hot Hands} q_pickup_20{Take Your Lumps} q_smuggle_1{Sleight of Hand} other{{key}}}'**
  String questTitle(String key);

  /// No description provided for @questDescription.
  ///
  /// In en, this message translates to:
  /// **'{key, select, q_play_3{Play 3 games} q_win_1{Win a game} q_catch_3{Catch 3 liars} q_survive_5{Get away with 5 lies} q_truth_15{Make 15 truthful throws} q_quad_1{Discard a four-of-a-kind} q_pass_joker{Pass the joker on} q_pickup_20{Pick up 20 cards} q_smuggle_1{Smuggle the joker into a throw} other{{key}}}'**
  String questDescription(String key);

  /// No description provided for @rewardsPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'The evening\'s take'**
  String get rewardsPanelTitle;

  /// No description provided for @doubleWinnings.
  ///
  /// In en, this message translates to:
  /// **'Double your winnings'**
  String get doubleWinnings;

  /// No description provided for @doubledLabel.
  ///
  /// In en, this message translates to:
  /// **'Doubled'**
  String get doubledLabel;

  /// No description provided for @unratedGame.
  ///
  /// In en, this message translates to:
  /// **'Friendly game — unrated'**
  String get unratedGame;

  /// No description provided for @deleteAccount.
  ///
  /// In en, this message translates to:
  /// **'Delete account'**
  String get deleteAccount;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete your account?'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountBody.
  ///
  /// In en, this message translates to:
  /// **'Coins, rating, purchases, and progress will be gone for good.'**
  String get deleteAccountBody;

  /// No description provided for @deleteAccountSecondTitle.
  ///
  /// In en, this message translates to:
  /// **'No way back'**
  String get deleteAccountSecondTitle;

  /// No description provided for @deleteAccountSecondBody.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone. Delete the account?'**
  String get deleteAccountSecondBody;

  /// No description provided for @deleteAccountConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get deleteAccountConfirm;

  /// No description provided for @deleteAccountFailed.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete the account: {reason}'**
  String deleteAccountFailed(String reason);

  /// No description provided for @reportPlayer.
  ///
  /// In en, this message translates to:
  /// **'Report'**
  String get reportPlayer;

  /// No description provided for @reportReasonNickname.
  ///
  /// In en, this message translates to:
  /// **'Offensive nickname'**
  String get reportReasonNickname;

  /// No description provided for @reportReasonCheating.
  ///
  /// In en, this message translates to:
  /// **'Cheating'**
  String get reportReasonCheating;

  /// No description provided for @reportReasonAbuse.
  ///
  /// In en, this message translates to:
  /// **'Abusive behavior'**
  String get reportReasonAbuse;

  /// No description provided for @reportReasonOther.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get reportReasonOther;

  /// No description provided for @reportSent.
  ///
  /// In en, this message translates to:
  /// **'Report sent'**
  String get reportSent;

  /// No description provided for @blockPlayer.
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get blockPlayer;

  /// No description provided for @unblockPlayer.
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblockPlayer;

  /// No description provided for @playerBlocked.
  ///
  /// In en, this message translates to:
  /// **'Player blocked'**
  String get playerBlocked;

  /// No description provided for @blockedPlayerName.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get blockedPlayerName;

  /// No description provided for @blockedPlayersTitle.
  ///
  /// In en, this message translates to:
  /// **'Blocked players'**
  String get blockedPlayersTitle;

  /// No description provided for @blockedEmpty.
  ///
  /// In en, this message translates to:
  /// **'No one here — and just as well'**
  String get blockedEmpty;

  /// No description provided for @joinBlocked.
  ///
  /// In en, this message translates to:
  /// **'You can\'t join this room'**
  String get joinBlocked;

  /// No description provided for @leftGameBadge.
  ///
  /// In en, this message translates to:
  /// **'Left the game'**
  String get leftGameBadge;

  /// No description provided for @supportLabel.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get supportLabel;

  /// No description provided for @emailCopied.
  ///
  /// In en, this message translates to:
  /// **'Address copied'**
  String get emailCopied;

  /// No description provided for @kickPlayer.
  ///
  /// In en, this message translates to:
  /// **'Kick'**
  String get kickPlayer;
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
