// Golden legality-mirror test: replays the engine's fixture views
// (packages/engine/fixtures/legality/fixtures.json) through the Dart
// rules_view functions and asserts every expected field matches.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:trude/features/game/logic/rules_view.dart';

void main() {
  // `flutter test` runs with the app directory as cwd.
  final file = File('../packages/engine/fixtures/legality/fixtures.json');
  final entries = (jsonDecode(file.readAsStringSync()) as List)
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList();

  test('fixtures file is non-empty', () {
    expect(entries, isNotEmpty);
  });

  for (final entry in entries) {
    final name = entry['name'] as String;
    test('legality mirror reproduces $name', () {
      final view = GameViewLite.fromJson(
          (entry['view'] as Map).cast<String, dynamic>());
      final expected = (entry['expected'] as Map).cast<String, dynamic>();

      expect(phaseOf(view), expected['phase'], reason: 'phase');
      expect(mustCheck(view), expected['mustCheck'], reason: 'mustCheck');
      expect(canTrust(view), expected['canTrust'], reason: 'canTrust');
      expect(
        nameableRanks(view.deckSize, view.retiredRanks),
        (expected['nameableRanks'] as List).cast<String>(),
        reason: 'nameableRanks',
      );
      expect(maxThrowCount(view.hand.length), expected['maxThrowCount'],
          reason: 'maxThrowCount');
      expect(lastThrowCount(view), expected['lastThrowCount'],
          reason: 'lastThrowCount');
    });
  }
}
