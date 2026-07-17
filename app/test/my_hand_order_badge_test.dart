// Throw-order badge locks for MyHandView.
//
// selectedIds is insertion-ordered (iteration order = throw order = laid-row
// slot), so:
//  * selecting in tap order c2, c0, c1 stamps badges 1/2/3 on exactly those
//    cards, and unselected cards carry none;
//  * a single selection shows NO badge (a lone "1" is noise);
//  * deselecting and reselecting a card moves it to the END of the order and
//    the ordinals renumber accordingly.

import 'package:flutter/material.dart' hide Card;
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/motion/animation_speed.dart';
import 'package:trude/core/net/protocol_models.dart';
import 'package:trude/features/game/widgets/card_widgets.dart';
import 'package:trude/features/game/widgets/my_hand.dart';

List<Card> _cards(int n) => [
      for (var i = 0; i < n; i++)
        Card(
            id: 'c$i',
            rank: '${2 + i % 9}',
            suit: const ['S', 'H', 'C', 'D'][i % 4]),
    ];

/// Stateful harness owning the selection as an insertion-ordered set — the
/// same contract the real screen upholds (deselect+reselect appends).
class _SelectionHarness extends StatefulWidget {
  const _SelectionHarness({required this.cards});

  final List<Card> cards;

  @override
  State<_SelectionHarness> createState() => _SelectionHarnessState();
}

class _SelectionHarnessState extends State<_SelectionHarness> {
  // Default Set literal = LinkedHashSet: iteration order = tap order.
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: MyHandView(
            cards: widget.cards,
            selectedIds: _selected,
            selectable: true,
            onToggle: (card, selected) => setState(() {
              if (selected) {
                _selected.add(card.id);
              } else {
                _selected.remove(card.id);
              }
            }),
            shiver: false,
            speed: AnimationSpeed.normal,
            onFlickThrow: () {},
          ),
        ),
      ),
    );
  }
}

void _sizeSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 600);
  addTearDown(tester.view.reset);
}

Finder _card(int index) => find.byType(TrudeCardFace).at(index);

Finder _badge(String cardId) => find.byKey(ValueKey('order-badge-$cardId'));

String _badgeText(WidgetTester tester, String cardId) {
  final text = tester.widget<Text>(
      find.descendant(of: _badge(cardId), matching: find.byType(Text)));
  return text.data!;
}

Future<void> _tapCard(WidgetTester tester, int index) async {
  await tester.tap(_card(index));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('tap order c2, c0, c1 stamps badges 1/2/3 on those cards',
      (tester) async {
    _sizeSurface(tester);
    await tester.pumpWidget(_SelectionHarness(cards: _cards(5)));

    await _tapCard(tester, 2);
    await _tapCard(tester, 0);
    await _tapCard(tester, 1);

    expect(_badgeText(tester, 'c2'), '1');
    expect(_badgeText(tester, 'c0'), '2');
    expect(_badgeText(tester, 'c1'), '3');
    // Unselected cards carry no badge.
    expect(_badge('c3'), findsNothing);
    expect(_badge('c4'), findsNothing);
  });

  testWidgets('a single selection shows no badge', (tester) async {
    _sizeSurface(tester);
    await tester.pumpWidget(_SelectionHarness(cards: _cards(5)));

    await _tapCard(tester, 0);

    for (var i = 0; i < 5; i++) {
      expect(_badge('c$i'), findsNothing);
    }
  });

  testWidgets('deselect+reselect moves the card to the end of the order',
      (tester) async {
    _sizeSurface(tester);
    await tester.pumpWidget(_SelectionHarness(cards: _cards(5)));

    await _tapCard(tester, 2);
    await _tapCard(tester, 0);
    await _tapCard(tester, 1);

    // Deselect c2 (was first): the survivors renumber from 1.
    await _tapCard(tester, 2);
    expect(_badge('c2'), findsNothing);
    expect(_badgeText(tester, 'c0'), '1');
    expect(_badgeText(tester, 'c1'), '2');

    // Reselect c2: it joins at the END of the throw order.
    await _tapCard(tester, 2);
    expect(_badgeText(tester, 'c0'), '1');
    expect(_badgeText(tester, 'c1'), '2');
    expect(_badgeText(tester, 'c2'), '3');
  });
}
