// The four-of-a-kind set piece ends fully invisible (no stray mini-square
// parked at the rail before onDone unmounts it), and back-to-back quads with
// distinct ObjectKeys replay from scratch instead of reusing a finished State.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/net/protocol_models.dart';
import 'package:trude/features/game/anim/motion_spec.dart';
import 'package:trude/features/game/anim/quad_celebration.dart';
import 'package:trude/features/game/widgets/card_widgets.dart';

FourDiscardedEvent _syntheticQuad() => WireEvent.fromJson({
      'type': 'fourDiscarded',
      'seat': 1,
      'rank': '7',
      'cards': [
        {'id': 'q1', 'rank': '7', 'suit': 'S'},
        {'id': 'q2', 'rank': '7', 'suit': 'H'},
        {'id': 'q3', 'rank': '7', 'suit': 'D'},
        {'id': 'q4', 'rank': '7', 'suit': 'C'},
      ],
    }) as FourDiscardedEvent;

Widget _harness(FourDiscardedEvent quad, VoidCallback onDone) => MaterialApp(
      home: Scaffold(
        body: QuadCelebration(
          // Mirrors table_fx_layer.dart: per-step identity via ObjectKey.
          key: ObjectKey(quad),
          event: quad,
          duration: MotionSpec.quadTotal,
          fromRect: const Rect.fromLTWH(20, 400, 60, 80),
          railRect: const Rect.fromLTWH(160, 40, 120, 30),
          onDone: onDone,
        ),
      ),
    );

/// The fade [Opacity] wrapping the framed 2x2 square — the nearest Opacity
/// ancestor of a card face (the plaque's Opacity is never an ancestor of the
/// cards).
Opacity _squareOpacity(WidgetTester tester) => tester.widget<Opacity>(
      find
          .ancestor(
            of: find.byType(TrudeCardFace).first,
            matching: find.byType(Opacity),
          )
          .first,
    );

void main() {
  testWidgets('quad square fades to fully invisible before unmount',
      (tester) async {
    var done = false;
    await tester.pumpWidget(_harness(_syntheticQuad(), () => done = true));

    // Assemble + shine frames play clean.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);

    // ~99% through (1199 of 1200 ms): deep into the shrink's fade tail —
    // the square has all but vanished, but the step has not completed yet.
    await tester.pump(const Duration(milliseconds: 399));
    expect(_squareOpacity(tester).opacity, lessThan(0.1));
    expect(done, isFalse);

    // Completion frame: exactly invisible. This is the last frame the user
    // can ever see before the parent unmounts the piece.
    await tester.pump(const Duration(milliseconds: 1));
    expect(_squareOpacity(tester).opacity, 0.0);

    // onDone fires on the first tick past the duration (AnimationController
    // reports completed strictly after the last in-duration frame), with the
    // square already invisible.
    expect(done, isFalse);
    await tester.pump(const Duration(milliseconds: 16));
    expect(done, isTrue);
    expect(tester.takeException(), isNull);

    // Tear down cleanly (no lingering tickers).
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('back-to-back quads replay under fresh ObjectKeys',
      (tester) async {
    final a = _syntheticQuad();
    final b = _syntheticQuad();
    var doneA = false;
    var doneB = false;

    // First quad runs to completion (one extra frame past the duration so
    // the controller reports completed and onDone fires).
    await tester.pumpWidget(_harness(a, () => doneA = true));
    await tester.pump(MotionSpec.quadTotal);
    await tester.pump(const Duration(milliseconds: 16));
    expect(doneA, isTrue);
    expect(_squareOpacity(tester).opacity, 0.0);

    // Second quad re-issued as the same widget type. Without the per-step
    // ObjectKey the old State (controller stuck at 1.0) would be reused:
    // nothing would replay and the second onDone would never fire.
    await tester.pumpWidget(_harness(b, () => doneB = true));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_squareOpacity(tester).opacity, 1.0);
    expect(doneB, isFalse);

    // And the second run completes on its own full timeline.
    await tester.pump(MotionSpec.quadTotal);
    expect(doneB, isTrue);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
