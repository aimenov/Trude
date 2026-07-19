// The laid-down last-throw row of the center pile: tappable slots, inert
// rendering when no callback is wired, and messy/row render-cap accounting.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/motion/animation_speed.dart';
import 'package:trude/core/theme/trude_theme.dart';
import 'package:trude/features/game/anim/motion_spec.dart';
import 'package:trude/features/game/widgets/card_widgets.dart';
import 'package:trude/features/game/widgets/cosmetic_styles.dart';
import 'package:trude/features/game/widgets/pile_stack.dart';

// Card backs resolve their cosmetic style from a provider now; pin classic so
// the test stays hermetic (no economy net layer).
Widget _stage(Widget child) => ProviderScope(
      overrides: [
        selectedCardBackStyleProvider.overrideWithValue(CardBackStyle.classic),
      ],
      child: MaterialApp(
        theme: buildTrudeTheme(),
        home: Scaffold(body: Center(child: child)),
      ),
    );

void main() {
  testWidgets('tapping row cards reports their slots', (tester) async {
    final taps = <int>[];
    await tester.pumpWidget(_stage(PileStack(
      count: 5,
      lastThrowCount: 2,
      rank: '7',
      speed: AnimationSpeed.off,
      onRowCardTap: taps.add,
    )));

    await tester.tap(find.byKey(const ValueKey('pile-row-0')));
    await tester.tap(find.byKey(const ValueKey('pile-row-1')));
    expect(taps, [0, 1]);
  });

  testWidgets('null onRowCardTap renders the row inert (no taps, no glow)',
      (tester) async {
    await tester.pumpWidget(_stage(const PileStack(
      count: 5,
      lastThrowCount: 2,
      rank: '7',
      speed: AnimationSpeed.off,
    )));

    expect(find.byKey(const ValueKey('pile-row-0')), findsNothing);
    expect(find.byKey(const ValueKey('pile-row-1')), findsNothing);
    final backs = tester.widgetList<TrudeCardBack>(find.byType(TrudeCardBack));
    expect(backs, isNotEmpty);
    expect(backs.every((b) => !b.selected), isTrue);
  });

  testWidgets('render cap counts the messy heap only', (tester) async {
    // 20 cards, last throw 3 -> 17 messy: pileRenderCap (12) rendered messy
    // backs + 3 row backs, and the +N chip counts the hidden messy (5).
    await tester.pumpWidget(_stage(PileStack(
      count: 20,
      lastThrowCount: 3,
      rank: '7',
      speed: AnimationSpeed.off,
      onRowCardTap: (_) {},
    )));

    expect(find.byType(TrudeCardBack),
        findsNWidgets(MotionSpec.pileRenderCap + 3));
    expect(find.text('+5'), findsOneWidget);
    final selected = tester
        .widgetList<TrudeCardBack>(find.byType(TrudeCardBack))
        .where((b) => b.selected);
    expect(selected.length, 3);
  });
}
