// SeatAvatar: the countdown arc drains off the avatar's own internal timer
// (deadlineTs prop, no parent rebuild), and the badges row survives the
// table's 86px seat width — an out player drops the count chip ("0" chip is
// noise next to the RU out badge) while an in-game autopilot keeps his.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/motion/animation_speed.dart';
import 'package:trude/core/net/client_game_state.dart';
import 'package:trude/core/strings.dart';
import 'package:trude/core/theme/trude_theme.dart';
import 'package:trude/features/game/anim/table_anchors.dart';
import 'package:trude/features/game/widgets/countdown_ring.dart';
import 'package:trude/features/game/widgets/seat_avatar.dart';
import 'package:trude/l10n/app_localizations.dart';

PlayerView _player({
  int cardCount = 5,
  bool connected = true,
  bool autoPilot = false,
  bool isOut = false,
}) =>
    PlayerView(
      userId: 'u1',
      nickname: 'Вася',
      avatar: '',
      seat: 1,
      cardCount: cardCount,
      connected: connected,
      autoPilot: autoPilot,
      isOut: isOut,
      isAdmin: false,
    );

Widget _stage(Widget child) => MaterialApp(
      theme: buildTrudeTheme(),
      home: Scaffold(body: Center(child: child)),
    );

double _arcFraction(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is CountdownRingPainter));
  return (paint.painter as CountdownRingPainter).fraction;
}

/// The avatar computes remaining time from the REAL wall clock while
/// widget-test timers run on the fake clock: spin the wall clock forward a
/// few real milliseconds so a timer tick observably drains the arc.
void _spinWallClock([Duration d = const Duration(milliseconds: 20)]) {
  final t0 = DateTime.now();
  while (DateTime.now().difference(t0) < d) {}
}

void main() {
  tearDown(() {
    // Widget tests share the static Strings binding; restore English.
    Strings.use(lookupAppLocalizations(const Locale('en')));
  });

  testWidgets('countdown arc drains from the avatar\'s own timer',
      (tester) async {
    await tester.pumpWidget(_stage(SeatAvatar(
      player: _player(),
      isTurn: true,
      deadlineTs: DateTime.now().millisecondsSinceEpoch + 5000,
      turnTotal: const Duration(seconds: 10),
      speed: AnimationSpeed.off,
      anchors: TableAnchors(),
    )));

    final before = _arcFraction(tester);
    expect(before, greaterThan(0));

    // No pumpWidget — the parent never rebuilds; only the avatar's internal
    // 250ms timer can produce the smaller fraction.
    _spinWallClock();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_arcFraction(tester), lessThan(before));

    await tester.pumpWidget(const SizedBox()); // dispose cancels the timer
  });

  testWidgets(
      'RU out+disconnected seat at 86px: no overflow, no "0" chip, out badge',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildTrudeTheme(),
      home: Builder(builder: (context) {
        // What StringsSync does in the real app builder.
        Strings.use(AppLocalizations.of(context));
        return Scaffold(
          body: Center(
            child: SeatAvatar(
              player: _player(cardCount: 0, isOut: true, connected: false),
              isTurn: false,
              deadlineTs: null,
              turnTotal: const Duration(seconds: 10),
              speed: AnimationSpeed.off,
              anchors: TableAnchors(),
            ),
          ),
        );
      }),
    ));

    // A RenderFlex overflow inside the avatar's own 86px-wide box reports
    // through FlutterError and auto-fails the test; assert explicitly too.
    expect(tester.takeException(), isNull);
    expect(find.text('0'), findsNothing);
    expect(find.text(Strings.outBadge), findsOneWidget);
    expect(find.byIcon(Icons.power_off), findsOneWidget);
  });

  testWidgets('in-game autopilot player still shows the count chip',
      (tester) async {
    await tester.pumpWidget(_stage(SeatAvatar(
      player: _player(cardCount: 5, autoPilot: true),
      isTurn: false,
      deadlineTs: null,
      turnTotal: const Duration(seconds: 10),
      speed: AnimationSpeed.off,
      anchors: TableAnchors(),
    )));

    expect(tester.takeException(), isNull);
    expect(find.text('5'), findsOneWidget);
    expect(find.byIcon(Icons.smart_toy), findsOneWidget);
  });
}
