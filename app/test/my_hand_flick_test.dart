// Flick-to-throw gesture regression locks for MyHandView.
//
// Locks the "throw from any card, in any natural direction" fix:
//  * a DIAGONAL fling on an edge selected card throws and publishes a
//    FlickLaunch that keeps the horizontal component;
//  * a horizontal fling never throws;
//  * tap-to-select still toggles (with and without an active selection);
//  * an overflowing hand still scrolls its ListView from unselected cards,
//    while a diagonal flick on a selected card still wins the arena.
//
// FlickLaunch.peek is non-consuming (TTL expiry only), so the published
// velocity is asserted directly through the production read path.

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/motion/animation_speed.dart';
import 'package:trude/core/net/protocol_models.dart';
import 'package:trude/features/game/anim/card_flight.dart';
import 'package:trude/features/game/widgets/card_widgets.dart';
import 'package:trude/features/game/widgets/my_hand.dart';

List<Card> _cards(int n) => [
      for (var i = 0; i < n; i++)
        Card(id: 'c$i', rank: '${2 + i % 9}', suit: const ['S', 'H', 'C', 'D'][i % 4]),
    ];

Widget _harness({
  required List<Card> cards,
  required Set<String> selectedIds,
  void Function(Card card, bool selected)? onToggle,
  VoidCallback? onFlickThrow,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: MyHandView(
          cards: cards,
          selectedIds: selectedIds,
          selectable: true,
          onToggle: onToggle ?? (_, _) {},
          shiver: false,
          speed: AnimationSpeed.normal,
          onFlickThrow: onFlickThrow,
        ),
      ),
    ),
  );
}

void _sizeSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 600);
  addTearDown(tester.view.reset);
}

Finder _card(int index) => find.byType(TrudeCardFace).at(index);

void main() {
  setUp(FlickLaunch.clear);
  tearDown(FlickLaunch.clear);

  testWidgets('diagonal fling on an edge selected card throws and keeps dx',
      (tester) async {
    _sizeSurface(tester);
    var throws = 0;
    // 5 cards fit 800 dp: the non-scrollable centered Row path.
    await tester.pumpWidget(_harness(
      cards: _cards(5),
      selectedIds: const {'c0'}, // the leftmost (edge) card
      onFlickThrow: () => throws++,
    ));
    expect(find.byType(Scrollable), findsNothing,
        reason: 'a fitting fan must not mount a scrollable');

    // Diagonal up-left flick, like throwing an edge card toward the pile.
    await tester.fling(_card(0), const Offset(-120, -160), 1500);
    expect(throws, 1);

    final handRect = tester.getRect(find.byType(MyHandView));
    final launch = FlickLaunch.peek(handRect);
    expect(launch, isNotNull,
        reason: 'the throw must publish its release velocity');
    expect(launch!.dy, lessThan(0));
    expect(launch.dx, lessThan(0),
        reason: 'a diagonal flick keeps its true (leftward) direction');

    await tester.pumpAndSettle();
  });

  testWidgets('horizontal fling on a selected card does not throw',
      (tester) async {
    _sizeSurface(tester);
    var throws = 0;
    await tester.pumpWidget(_harness(
      cards: _cards(5),
      selectedIds: const {'c0'},
      onFlickThrow: () => throws++,
    ));

    await tester.fling(_card(0), const Offset(-200, 0), 1500);
    expect(throws, 0);
    expect(FlickLaunch.peek(tester.getRect(find.byType(MyHandView))), isNull);

    // Sub-threshold release springs back without throwing.
    await tester.pumpAndSettle();
    expect(throws, 0);
  });

  testWidgets('tap toggles selection with and without other cards selected',
      (tester) async {
    _sizeSurface(tester);
    final toggles = <(String, bool)>[];
    void onToggle(Card card, bool selected) => toggles.add((card.id, selected));

    // Nothing selected: tapping selects.
    await tester.pumpWidget(_harness(
      cards: _cards(5),
      selectedIds: const {},
      onToggle: onToggle,
      onFlickThrow: () {},
    ));
    await tester.tap(_card(1));
    expect(toggles, [('c1', true)]);

    // With an active selection (flick armed on 'c0'): tapping the selected
    // card deselects, tapping another selects — the pan recognizer on the
    // selected card must not eat stationary taps.
    toggles.clear();
    await tester.pumpWidget(_harness(
      cards: _cards(5),
      selectedIds: const {'c0'},
      onToggle: onToggle,
      onFlickThrow: () {},
    ));
    await tester.pumpAndSettle();
    await tester.tap(_card(0));
    await tester.tap(_card(2));
    expect(toggles, [('c0', false), ('c2', true)]);
  });

  testWidgets('overflowing hand still scrolls from an unselected card',
      (tester) async {
    _sizeSurface(tester);
    var throws = 0;
    // 20 cards x 52 dp footprint overflow 800 dp: the ListView path.
    await tester.pumpWidget(_harness(
      cards: _cards(20),
      selectedIds: const {'c0'},
      onFlickThrow: () => throws++,
    ));
    expect(find.byType(ListView), findsOneWidget);

    final position =
        tester.state<ScrollableState>(find.byType(Scrollable)).position;
    expect(position.pixels, 0);

    // Horizontal drag from an unselected card scrolls the strip.
    await tester.drag(_card(3), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(0));
    expect(throws, 0);
  });

  testWidgets('overflowing hand: diagonal flick on a selected card still wins',
      (tester) async {
    _sizeSurface(tester);
    var throws = 0;
    await tester.pumpWidget(_harness(
      cards: _cards(20),
      selectedIds: const {'c0'},
      onFlickThrow: () => throws++,
    ));
    expect(find.byType(ListView), findsOneWidget);

    // The pan recognizer's total-distance slop beats the ListView's
    // horizontal recognizer for a diagonal drag, so the flick still fires
    // on the scrollable path.
    await tester.fling(_card(0), const Offset(-120, -160), 1500);
    expect(throws, 1);

    final launch = FlickLaunch.peek(tester.getRect(find.byType(MyHandView)));
    expect(launch, isNotNull);
    expect(launch!.dx, lessThan(0));

    await tester.pumpAndSettle();
  });
}
