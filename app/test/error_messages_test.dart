import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/net/error_messages.dart';
import 'package:trude/core/net/trude_client.dart';
import 'package:trude/core/strings.dart';
import 'package:trude/l10n/app_localizations.dart';

void main() {
  tearDown(() {
    // Widget tests share the static Strings binding; restore English.
    Strings.use(lookupAppLocalizations(const Locale('en')));
  });

  /// Binds [Strings] to a real localization bundle the way ru_strings_test
  /// does (what StringsSync does in the real app builder).
  Future<void> bindLocale(WidgetTester tester, Locale locale) async {
    await tester.pumpWidget(MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(builder: (context) {
        Strings.use(AppLocalizations.of(context));
        return const SizedBox.shrink();
      }),
    ));
  }

  testWidgets('404 by-code lookup maps to roomNotFound', (tester) async {
    await bindLocale(tester, const Locale('en'));
    expect(
      friendlyRoomError(TrudeApiException(404, 'no such code'),
          creating: false),
      Strings.roomNotFound,
    );
  });

  testWidgets('locked/full room maps to roomFull', (tester) async {
    await bindLocale(tester, const Locale('en'));
    // Colyseus joinById on a locked (auto-locked = full) room.
    expect(
      friendlyRoomError(
          MatchmakeException('room "abc" is locked', code: 4212),
          creating: false),
      Strings.roomFull,
    );
    // The server's own onJoin guard.
    expect(
      friendlyRoomError(MatchmakeException('Room is full'), creating: false),
      Strings.roomFull,
    );
  });

  testWidgets('unknown exceptions map to the generic line per mode',
      (tester) async {
    await bindLocale(tester, const Locale('en'));
    final boom = Exception('socket boom');
    expect(friendlyRoomError(boom, creating: false),
        Strings.joinFailedGeneric);
    expect(friendlyRoomError(boom, creating: true),
        Strings.createFailedGeneric);
    // Non-404 API errors stay generic too.
    expect(friendlyRoomError(TrudeApiException(500, 'oops'), creating: true),
        Strings.createFailedGeneric);
  });

  testWidgets('output never leaks raw exception text', (tester) async {
    await bindLocale(tester, const Locale('en'));
    final inputs = <Object>[
      Exception('socket boom'),
      TrudeApiException(404, 'body text'),
      TrudeApiException(503, 'unavailable'),
      MatchmakeException('room "abc" is locked', code: 4212),
      MatchmakeException('weird failure', code: 4213, httpStatus: 500),
      StateError('Call guestLogin() before joining rooms'),
    ];
    for (final e in inputs) {
      for (final creating in const [false, true]) {
        final out = friendlyRoomError(e, creating: creating);
        expect(out, isNot(contains('Exception(')),
            reason: 'leaked for $e (creating: $creating)');
        expect(out, isNot(contains('MatchmakeException')));
        expect(out, isNot(contains('TrudeApiException')));
      }
    }
  });
}
