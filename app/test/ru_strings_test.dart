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
        return Column(children: [
          Text(Strings.claimCallout(3, '7')),
          Text(Strings.claimCallout(1, 'J')),
          Text(Strings.claimCallout(2, 'Q')),
          Text(Strings.claimCallout(1, '10')),
          Text(Strings.quadBanner('7')),
          Text(Strings.playingRank('A')),
          Text(Strings.threwEvent('Вася', 2, '7')),
          Text(Strings.trust),
          Text(Strings.check),
        ]);
      }),
    ));

    // Numeral + noun agreement: feminine and masculine rank words.
    expect(find.text('ТРИ СЕМЁРКИ!'), findsOneWidget);
    expect(find.text('ОДИН ВАЛЕТ!'), findsOneWidget);
    expect(find.text('ДВЕ ДАМЫ!'), findsOneWidget);
    expect(find.text('ОДНА ДЕСЯТКА!'), findsOneWidget);

    // Quad banner reuses the count-4 paucal form.
    expect(find.text('ЧЕТЫРЕ СЕМЁРКИ — В СБРОС!'), findsOneWidget);

    // Nominative plural for the pile label.
    expect(find.text('В игре: ТУЗЫ'), findsOneWidget);

    // Event feed reuses the lowercased claim.
    expect(find.text('Вася бросает две семёрки'), findsOneWidget);

    // The classic verbs of the game family.
    expect(find.text('ВЕРЮ'), findsOneWidget);
    expect(find.text('НЕ ВЕРЮ'), findsOneWidget);
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
