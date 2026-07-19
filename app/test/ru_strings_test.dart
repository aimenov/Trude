import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/strings.dart';
import 'package:trude/l10n/app_localizations.dart';

void main() {
  tearDown(() {
    // Widget tests share the static Strings binding; restore English.
    Strings.use(lookupAppLocalizations(const Locale('en')));
  });

  testWidgets('RU locale renders pluralized claim callouts', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        // What StringsSync does in the real app builder.
        Strings.use(AppLocalizations.of(context));
        // Scrollable (not a lazy ListView, which would skip offscreen rows):
        // the long respond hint wraps and a bare Column would overflow.
        return SingleChildScrollView(
            child: Column(children: [
          Text(Strings.claimCallout(3, '7')),
          Text(Strings.claimCallout(1, 'J')),
          Text(Strings.claimCallout(2, 'Q')),
          Text(Strings.claimCallout(1, '10')),
          Text(Strings.quadBanner('7')),
          Text(Strings.yourTurnForcedCheck),
          Text(Strings.forcedCheckTurn('Вася')),
          Text(Strings.respondChoiceHint),
          Text(Strings.lastClaimPlaque('Вася', Strings.claimBody(3, '7'))),
          Text(Strings.roomFull),
          Text(Strings.joinFailedGeneric),
          Text(Strings.leaveGameTitle),
          Text(Strings.shareCodeHint),
          Text(Strings.achievementDescription('smuggler', '~fallback~')),
        ]));
      }),
    ));

    // Numeral + noun agreement: feminine and masculine rank words.
    expect(find.text('ТРИ СЕМЁРКИ!'), findsOneWidget);
    expect(find.text('ОДИН ВАЛЕТ!'), findsOneWidget);
    expect(find.text('ДВЕ ДАМЫ!'), findsOneWidget);
    expect(find.text('ОДНА ДЕСЯТКА!'), findsOneWidget);

    // Quad banner reuses the count-4 paucal form.
    expect(find.text('ЧЕТЫРЕ СЕМЁРКИ — В СБРОС!'), findsOneWidget);

    // Forced-check turn lines (thrower emptied their hand).
    expect(find.text('Твой ход — открой карту'), findsOneWidget);
    expect(find.text('Вася — только проверка'), findsOneWidget);

    // The buttonless respond turn: both choices in one hint.
    expect(find.text('Открой любую карту броска — или бросай свои сверху'),
        findsOneWidget);

    // Claim plaque keeps the paucal agreement through claimBody.
    expect(find.text('Вася: ТРИ СЕМЁРКИ'), findsOneWidget);

    // Friendly join errors and the room-code hints.
    expect(find.text('Комната заполнена'), findsOneWidget);
    expect(find.text('Не удалось подключиться. Проверь код и попробуй ещё раз.'),
        findsOneWidget);
    expect(find.text('Покинуть игру?'), findsOneWidget);
    expect(find.text('Поделись кодом — по нему заходят друзья'),
        findsOneWidget);

    // «Контрабандист» dropped the «чужому игроку» clause.
    expect(Strings.achievementDescription('smuggler', '~fallback~'),
        'Подсунь джокера 10 раз');
  });

  testWidgets('EN locale keeps the original callouts', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        Strings.use(AppLocalizations.of(context));
        return Column(children: [
          Text(Strings.claimCallout(3, '7')),
          Text(Strings.quadBanner('7')),
        ]);
      }),
    ));

    expect(find.text('THREE SEVENS!'), findsOneWidget);
    expect(find.text('FOUR SEVENS OUT!'), findsOneWidget);
  });
}
