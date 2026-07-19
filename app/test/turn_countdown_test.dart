// SelfTickingCountdownRing: the leaf drains itself off its OWN 250ms timer
// (no ancestor rebuild involved), re-arms when the deadline changes, and
// leaves no pending timers past the deadline or after teardown.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/theme/trude_theme.dart';
import 'package:trude/features/game/widgets/countdown_ring.dart';
import 'package:trude/features/game/widgets/turn_countdown.dart';

double _fraction(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is CountdownRingPainter));
  return (paint.painter as CountdownRingPainter).fraction;
}

/// The ring computes remaining time from the REAL wall clock while widget-test
/// timers run on the fake clock: spin the wall clock forward a few real
/// milliseconds so a timer-driven rebuild observably drains the ring.
void _spinWallClock([Duration d = const Duration(milliseconds: 20)]) {
  final t0 = DateTime.now();
  while (DateTime.now().difference(t0) < d) {}
}

Widget _stage(Widget child) => MaterialApp(
      theme: buildTrudeTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('ring drains from its own timer, no parent rebuild',
      (tester) async {
    final deadline = DateTime.now().millisecondsSinceEpoch + 5000;
    await tester.pumpWidget(_stage(SelfTickingCountdownRing(
      deadlineTs: deadline,
      totalMs: 10000,
      animate: false,
    )));

    final before = _fraction(tester);
    expect(before, greaterThan(0));

    // No pumpWidget here — nothing above the leaf rebuilds. Only the leaf's
    // internal timer can produce the new, smaller fraction.
    _spinWallClock();
    await tester.pump(const Duration(milliseconds: 500));
    expect(_fraction(tester), lessThan(before));
  });

  testWidgets('re-arms on deadline change; no pending timers past deadline',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await tester.pumpWidget(_stage(SelfTickingCountdownRing(
      deadlineTs: now + 5000,
      totalMs: 10000,
      animate: false,
    )));
    await tester.pump(const Duration(milliseconds: 250));
    expect(_fraction(tester), greaterThan(0));

    // Deadline flips into the past (deadline change re-arms the timer, and
    // the re-arm immediately cancels it: nothing left to count down).
    await tester.pumpWidget(_stage(SelfTickingCountdownRing(
      deadlineTs: now - 1000,
      totalMs: 10000,
      animate: false,
    )));
    expect(_fraction(tester), 0.0);
    // Nothing may still be ticking; a live periodic timer would keep
    // rebuilding a dead ring forever.
    await tester.pump(const Duration(seconds: 5));
    expect(_fraction(tester), 0.0);

    // A fresh future deadline re-arms again.
    await tester.pumpWidget(_stage(SelfTickingCountdownRing(
      deadlineTs: DateTime.now().millisecondsSinceEpoch + 5000,
      totalMs: 10000,
      animate: false,
    )));
    expect(_fraction(tester), greaterThan(0));

    // Teardown: dispose must cancel the armed timer — testWidgets fails the
    // test on any timer still pending after the tree is disposed.
    await tester.pumpWidget(const SizedBox());
  });
}
