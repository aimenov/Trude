import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/features/home/parlor_widgets.dart';

void main() {
  testWidgets(
      'ListTile inside ParlorPanel splashes ink without the '
      '"background may be invisible" debug error', (tester) async {
    var tapped = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ParlorPanel(
          child: ListTile(
            title: const Text('Nickname'),
            onTap: () => tapped = true,
          ),
        ),
      ),
    ));

    // The ink splash is what walks up looking for a visible Material ancestor
    // (_debugCheckBackgroundIsHidden fires via FlutterError.reportError,
    // which fails widget tests) — so actually tap the tile.
    await tester.tap(find.byType(ListTile));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });
}
