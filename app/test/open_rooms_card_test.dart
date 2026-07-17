// Layout regression locks for RoomCard: the worst-case listing — 8/8 seats,
// deck 53, an over-long room name — must lay out at a narrow phone width
// without RenderFlex overflow (the test framework fails on overflow
// automatically), and stay sane on a wide layout.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/features/rooms/open_rooms_screen.dart';

const _room = RoomListing(
  roomId: 'r1',
  name: 'The Extraordinarily Long Parlor Name That Never Ends',
  players: 8,
  maxPlayers: 8,
  deckSize: 53,
);

Widget _harness({required double width}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: const RoomCard(room: _room),
          ),
        ),
      ),
    );

void main() {
  testWidgets('narrow card (280dp) with 8/8 seats, deck 53, long name lays out',
      (tester) async {
    await tester.pumpWidget(_harness(width: 280));

    expect(find.byType(RoomCard), findsOneWidget);
    expect(find.text('53'), findsOneWidget); // the deck badge under the fan
  });

  testWidgets('wide layout sanity', (tester) async {
    await tester.pumpWidget(_harness(width: 600));

    expect(find.byType(RoomCard), findsOneWidget);
  });
}
