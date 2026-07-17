// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Trude';

  @override
  String get nicknameTitle => 'Придумай ник';

  @override
  String get nicknameHint => 'Ник (2–16 символов)';

  @override
  String get nicknameInvalid => 'Ник должен быть от 2 до 16 символов';

  @override
  String get play => 'Играть';

  @override
  String loginFailed(String reason) {
    return 'Не удалось войти: $reason';
  }

  @override
  String get createRoom => 'Создать комнату';

  @override
  String get openRooms => 'Открытые комнаты';

  @override
  String get joinByCode => 'Войти по коду';

  @override
  String get changeNickname => 'Сменить ник';

  @override
  String playingAs(String nickname) {
    return 'Играешь как $nickname';
  }

  @override
  String get joinByCodeTitle => 'Вход по коду';

  @override
  String get roomCodeHint => 'Код комнаты';

  @override
  String get join => 'Войти';

  @override
  String get cancel => 'Отмена';

  @override
  String get roomNotFound => 'Комната не найдена';

  @override
  String get createRoomTitle => 'Новая комната';

  @override
  String get roomNameHint => 'Название комнаты';

  @override
  String get publicRoom => 'Открытая';

  @override
  String get privateRoom => 'Приватная';

  @override
  String get deckLabel => 'Колода';

  @override
  String get create => 'Создать';

  @override
  String deckOption(num size) {
    String _temp0 = intl.Intl.pluralLogic(
      size,
      locale: localeName,
      other: '$size карты',
      many: '$size карт',
      few: '$size карты',
      one: '$size карта',
    );
    return '$_temp0';
  }

  @override
  String get openRoomsTitle => 'Открытые комнаты';

  @override
  String get noRoomsYet => 'Открытых комнат пока нет — создай свою!';

  @override
  String playersOf(int players, int max) {
    return '$players/$max игроков';
  }

  @override
  String joinFailed(String reason) {
    return 'Не удалось подключиться: $reason';
  }

  @override
  String get lobbyTitle => 'Лобби';

  @override
  String get start => 'Начать';

  @override
  String get needTwoPlayers => 'Для старта нужно хотя бы два игрока';

  @override
  String get deckSizeLabel => 'Размер колоды';

  @override
  String get turnTimerLabel => 'Таймер хода';

  @override
  String get maxPlayersLabel => 'Макс. игроков';

  @override
  String get adminBadge => 'Админ';

  @override
  String get youBadge => 'Ты';

  @override
  String roomCodeLabel(String code) {
    return 'Код комнаты: $code';
  }

  @override
  String secondsOption(int s) {
    return '$s с';
  }

  @override
  String swapAsk(String nickname) {
    return 'Предложить $nickname поменяться местами?';
  }

  @override
  String get requestSwap => 'Предложить обмен';

  @override
  String swapIncoming(String nickname) {
    return '$nickname хочет поменяться с тобой местами';
  }

  @override
  String get accept => 'Принять';

  @override
  String get decline => 'Отклонить';

  @override
  String get swapAccepted => 'Обмен местами принят';

  @override
  String get swapDeclined => 'Обмен местами отклонён';

  @override
  String configLine(int deckSize, int turnTimerSec, int maxPlayers) {
    return 'Колода $deckSize · Таймер $turnTimerSec с · До $maxPlayers игроков';
  }

  @override
  String get mustCheckReason =>
      'У соперника кончились карты — придётся проверять';

  @override
  String get throwButton => 'Бросить';

  @override
  String get claimRankLabel => 'Что кладёшь';

  @override
  String get tapCardToFlip => 'Коснись карты, чтобы открыть её';

  @override
  String get yourTurnLead => 'Твой ход — ходи';

  @override
  String get yourTurnRespond => 'Твой ход — открой карту или бросай';

  @override
  String get yourTurnForcedCheck => 'Твой ход — открой карту';

  @override
  String forcedCheckTurn(String nickname) {
    return '$nickname — только проверка';
  }

  @override
  String get respondChoiceHint =>
      'Открой любую карту броска — или бросай свои сверху';

  @override
  String get selectCardsHint => 'Выбери до 3 карт';

  @override
  String pileCount(int n) {
    return 'В стопке: $n';
  }

  @override
  String lastClaimPlaque(String nickname, String claim) {
    return '$nickname: $claim';
  }

  @override
  String retiredRanksLabel(String ranks) {
    return 'Вышли из игры: $ranks';
  }

  @override
  String get noRetiredRanks => 'Вышли из игры: —';

  @override
  String countdown(int seconds) {
    return '$seconds с';
  }

  @override
  String get outBadge => 'ВЫШЕЛ';

  @override
  String get offlineBadge => 'не в сети';

  @override
  String get autoPilotBadge => 'авто';

  @override
  String get waitingForOpponent => 'Ждём…';

  @override
  String seatName(int number) {
    return 'Место $number';
  }

  @override
  String get verdictTruth => 'ПРАВДА';

  @override
  String get verdictLiar => 'ВРАНЬЁ!';

  @override
  String get safeCallout => 'СПАСЁН!';

  @override
  String claimCallout(String rank, String countKey, int count) {
    String _temp0 = intl.Intl.selectLogic(countKey, {
      'one': 'ОДНА ДВОЙКА',
      'two': 'ДВЕ ДВОЙКИ',
      'three': 'ТРИ ДВОЙКИ',
      'four': 'ЧЕТЫРЕ ДВОЙКИ',
      'other': '$count ДВОЕК',
    });
    String _temp1 = intl.Intl.selectLogic(countKey, {
      'one': 'ОДНА ТРОЙКА',
      'two': 'ДВЕ ТРОЙКИ',
      'three': 'ТРИ ТРОЙКИ',
      'four': 'ЧЕТЫРЕ ТРОЙКИ',
      'other': '$count ТРОЕК',
    });
    String _temp2 = intl.Intl.selectLogic(countKey, {
      'one': 'ОДНА ЧЕТВЁРКА',
      'two': 'ДВЕ ЧЕТВЁРКИ',
      'three': 'ТРИ ЧЕТВЁРКИ',
      'four': 'ЧЕТЫРЕ ЧЕТВЁРКИ',
      'other': '$count ЧЕТВЁРОК',
    });
    String _temp3 = intl.Intl.selectLogic(countKey, {
      'one': 'ОДНА ПЯТЁРКА',
      'two': 'ДВЕ ПЯТЁРКИ',
      'three': 'ТРИ ПЯТЁРКИ',
      'four': 'ЧЕТЫРЕ ПЯТЁРКИ',
      'other': '$count ПЯТЁРОК',
    });
    String _temp4 = intl.Intl.selectLogic(countKey, {
      'one': 'ОДНА ШЕСТЁРКА',
      'two': 'ДВЕ ШЕСТЁРКИ',
      'three': 'ТРИ ШЕСТЁРКИ',
      'four': 'ЧЕТЫРЕ ШЕСТЁРКИ',
      'other': '$count ШЕСТЁРОК',
    });
    String _temp5 = intl.Intl.selectLogic(countKey, {
      'one': 'ОДНА СЕМЁРКА',
      'two': 'ДВЕ СЕМЁРКИ',
      'three': 'ТРИ СЕМЁРКИ',
      'four': 'ЧЕТЫРЕ СЕМЁРКИ',
      'other': '$count СЕМЁРОК',
    });
    String _temp6 = intl.Intl.selectLogic(countKey, {
      'one': 'ОДНА ВОСЬМЁРКА',
      'two': 'ДВЕ ВОСЬМЁРКИ',
      'three': 'ТРИ ВОСЬМЁРКИ',
      'four': 'ЧЕТЫРЕ ВОСЬМЁРКИ',
      'other': '$count ВОСЬМЁРОК',
    });
    String _temp7 = intl.Intl.selectLogic(countKey, {
      'one': 'ОДНА ДЕВЯТКА',
      'two': 'ДВЕ ДЕВЯТКИ',
      'three': 'ТРИ ДЕВЯТКИ',
      'four': 'ЧЕТЫРЕ ДЕВЯТКИ',
      'other': '$count ДЕВЯТОК',
    });
    String _temp8 = intl.Intl.selectLogic(countKey, {
      'one': 'ОДНА ДЕСЯТКА',
      'two': 'ДВЕ ДЕСЯТКИ',
      'three': 'ТРИ ДЕСЯТКИ',
      'four': 'ЧЕТЫРЕ ДЕСЯТКИ',
      'other': '$count ДЕСЯТОК',
    });
    String _temp9 = intl.Intl.selectLogic(countKey, {
      'one': 'ОДИН ВАЛЕТ',
      'two': 'ДВА ВАЛЬТА',
      'three': 'ТРИ ВАЛЬТА',
      'four': 'ЧЕТЫРЕ ВАЛЬТА',
      'other': '$count ВАЛЬТОВ',
    });
    String _temp10 = intl.Intl.selectLogic(countKey, {
      'one': 'ОДНА ДАМА',
      'two': 'ДВЕ ДАМЫ',
      'three': 'ТРИ ДАМЫ',
      'four': 'ЧЕТЫРЕ ДАМЫ',
      'other': '$count ДАМ',
    });
    String _temp11 = intl.Intl.selectLogic(countKey, {
      'one': 'ОДИН КОРОЛЬ',
      'two': 'ДВА КОРОЛЯ',
      'three': 'ТРИ КОРОЛЯ',
      'four': 'ЧЕТЫРЕ КОРОЛЯ',
      'other': '$count КОРОЛЕЙ',
    });
    String _temp12 = intl.Intl.selectLogic(countKey, {
      'one': 'ОДИН ТУЗ',
      'two': 'ДВА ТУЗА',
      'three': 'ТРИ ТУЗА',
      'four': 'ЧЕТЫРЕ ТУЗА',
      'other': '$count ТУЗОВ',
    });
    String _temp13 = intl.Intl.selectLogic(countKey, {
      'one': 'ОДИН ДЖОКЕР',
      'other': '$count ДЖОКЕРА',
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
    return '$claim — В СБРОС!';
  }

  @override
  String jokerStaysWith(String nickname) {
    return 'ДЖОКЕР ОСТАЁТСЯ У $nickname';
  }

  @override
  String get resultsTitle => 'Итоги';

  @override
  String get stayForRematch => 'Остаться на реванш';

  @override
  String get leave => 'Выйти';

  @override
  String placementLabel(String placementKey, int placement) {
    String _temp0 = intl.Intl.selectLogic(placementKey, {
      'other': '$placement-е',
    });
    return '$_temp0';
  }

  @override
  String statsLine(int liesSurvived, int liesCaught, int checksWon) {
    return 'Наврал безнаказанно: $liesSurvived · Пойман на вранье: $liesCaught · Разоблачил: $checksWon';
  }

  @override
  String get unlockedThisGame => 'Открыто за эту партию';

  @override
  String rankWord(String rank) {
    String _temp0 = intl.Intl.selectLogic(rank, {
      'r2': 'ДВОЙКА',
      'r3': 'ТРОЙКА',
      'r4': 'ЧЕТВЁРКА',
      'r5': 'ПЯТЁРКА',
      'r6': 'ШЕСТЁРКА',
      'r7': 'СЕМЁРКА',
      'r8': 'ВОСЬМЁРКА',
      'r9': 'ДЕВЯТКА',
      'r10': 'ДЕСЯТКА',
      'jack': 'ВАЛЕТ',
      'queen': 'ДАМА',
      'king': 'КОРОЛЬ',
      'ace': 'ТУЗ',
      'joker': 'ДЖОКЕР',
      'other': '$rank',
    });
    return '$_temp0';
  }

  @override
  String rankShort(String rank) {
    String _temp0 = intl.Intl.selectLogic(rank, {
      'jack': 'В',
      'queen': 'Д',
      'king': 'К',
      'ace': 'Т',
      'other': '$rank',
    });
    return '$_temp0';
  }

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get animationSpeedLabel => 'Скорость анимаций';

  @override
  String get speedNormal => 'Обычная';

  @override
  String get speedFast => 'Быстрая';

  @override
  String get speedOff => 'Выкл';

  @override
  String get soundLabel => 'Звуки';

  @override
  String get hapticsLabel => 'Вибрация';

  @override
  String get languageLabel => 'Язык';

  @override
  String get languageSystem => 'Системный';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageRussian => 'Русский';

  @override
  String get nicknameLabel => 'Ник';

  @override
  String get save => 'Сохранить';

  @override
  String get nicknameSaved => 'Ник обновлён';

  @override
  String saveFailed(String reason) {
    return 'Не удалось сохранить: $reason';
  }

  @override
  String get aboutLabel => 'О приложении';

  @override
  String versionLabel(String version) {
    return 'Trude $version';
  }

  @override
  String statsStrip(int games, int wins, int streak) {
    return 'Игр $games · Побед $wins · Серия $streak';
  }

  @override
  String get achievementsTitle => 'Достижения';

  @override
  String get achievementUnlockedToast => 'Достижение открыто!';

  @override
  String unlockedOn(DateTime date) {
    final intl.DateFormat dateDateFormat = intl.DateFormat.yMMMd(localeName);
    final String dateString = dateDateFormat.format(date);

    return 'Открыто $dateString';
  }

  @override
  String achievementsCount(int unlocked, int total) {
    return 'Открыто $unlocked из $total';
  }

  @override
  String get achievementsLoadFailed =>
      'Не удалось загрузить — потяни, чтобы обновить';

  @override
  String achievementTitle(String key) {
    String _temp0 = intl.Intl.selectLogic(key, {
      'best_liar': 'Лучший лжец',
      'pathological_truther': 'Патологически честный',
      'human_polygraph': 'Ходячий полиграф',
      'gullible': 'Доверчивый',
      'poker_face': 'Покерфейс',
      'smuggler': 'Контрабандист',
      'hot_potato': 'Горячая картошка',
      'jokers_best_friend': 'Лучший друг джокера',
      'demolition_crew': 'Подрывник',
      'comeback_season': 'Камбэк сезона',
      'serial_winner': 'Серийный победитель',
      'it_wasnt_me': 'Это не я',
      'other': '~',
    });
    return '$_temp0';
  }

  @override
  String achievementDescription(String key) {
    String _temp0 = intl.Intl.selectLogic(key, {
      'best_liar': 'Выиграй 10 партий',
      'pathological_truther':
          'Выиграй партию, ни разу не соврав (не меньше 8 честных бросков)',
      'human_polygraph': 'Поймай 25 лжецов',
      'gullible': 'Открой правдивую карту 15 раз',
      'poker_face': 'Соври 50 раз — и пусть никто не заметит',
      'smuggler': 'Подсунь джокера чужому игроку 10 раз',
      'hot_potato': 'Передай джокера дважды за одну партию',
      'jokers_best_friend': 'Проиграй 5 партий — джокер тебя просто любит',
      'demolition_crew': 'Сбрось четыре одинаковых 10 раз',
      'comeback_season': 'Выиграй партию, подержав в руке 20 и больше карт',
      'serial_winner': 'Выиграй 3 партии подряд',
      'it_wasnt_me':
          'Выиграй партию, соврав хотя бы трижды и ни разу не попавшись',
      'other': '~',
    });
    return '$_temp0';
  }
}
