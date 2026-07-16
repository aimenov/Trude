// The check-reveal set piece builds and plays through without exceptions for
// a synthetic checkResult event.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/audio/sfx_service.dart';
import 'package:trude/core/haptics/haptics_service.dart';
import 'package:trude/core/net/protocol_models.dart';
import 'package:trude/core/strings.dart';
import 'package:trude/features/game/anim/reveal_overlay.dart';

CheckResultEvent _syntheticCheckResult({required bool matched}) =>
    WireEvent.fromJson({
      'type': 'checkResult',
      'checkerSeat': 0,
      'targetSeat': 1,
      'flipIndex': 1,
      'flipped': {'id': 'c9', 'rank': matched ? '7' : 'K', 'suit': 'S'},
      'matched': matched,
      'pickerSeat': matched ? 0 : 1,
      'pickedCount': 5,
      'nextLeadSeat': 0,
    }) as CheckResultEvent;

void main() {
  testWidgets('reveal set piece plays a synthetic LIAR checkResult',
      (tester) async {
    var verdictFired = false;
    var done = false;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RevealOverlay(
          event: _syntheticCheckResult(matched: false),
          cardCount: 3,
          duration: const Duration(milliseconds: 2700),
          sfx: SfxService(),
          haptics: HapticsService(),
          onVerdict: () => verdictFired = true,
          onDone: () => done = true,
        ),
      ),
    ));

    // Dim + spread + lift + flip.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 700));
    expect(tester.takeException(), isNull);

    // Verdict beat (72 % of 2700 ms) has stamped by 2.1 s.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text(Strings.verdictLiar), findsOneWidget);
    expect(verdictFired, isTrue);

    // Timeline completes.
    await tester.pump(const Duration(milliseconds: 700));
    expect(done, isTrue);
    expect(tester.takeException(), isNull);

    // Tear down cleanly (no lingering tickers/timers).
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('reveal set piece shows TRUTH for a matched check',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RevealOverlay(
          event: _syntheticCheckResult(matched: true),
          cardCount: 2,
          duration: const Duration(milliseconds: 2700),
          sfx: SfxService(),
          haptics: HapticsService(),
        ),
      ),
    ));

    await tester.pump(const Duration(milliseconds: 2200));
    expect(find.text(Strings.verdictTruth), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
