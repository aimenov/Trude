import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/net/error_messages.dart';
import 'package:trude/core/net/moderation_providers.dart';
import 'package:trude/core/net/trude_client.dart';
import 'package:trude/core/strings.dart';
import 'package:trude/l10n/app_localizations.dart';

void main() {
  setUp(() {
    // Bind the English bundle explicitly (tests share the static binding).
    Strings.use(lookupAppLocalizations(const Locale('en')));
  });

  group('maskedNickname', () {
    test('returns the real nickname for unblocked players', () {
      expect(maskedNickname(const {}, 'u1', 'Wes'), 'Wes');
      expect(maskedNickname(const {'u2'}, 'u1', 'Wes'), 'Wes');
    });

    test('masks blocked players to Strings.blockedPlayerName', () {
      expect(maskedNickname(const {'u1'}, 'u1', 'Wes'),
          Strings.blockedPlayerName);
      expect(maskedNickname(const {'u1', 'u2'}, 'u2', 'Grim'),
          Strings.blockedPlayerName);
    });
  });

  group('maskedInitial', () {
    test('uppercased first letter for unblocked players', () {
      expect(maskedInitial(const {}, 'u1', 'wes'), 'W');
      expect(maskedInitial(const {'u2'}, 'u1', 'Вася'), 'В');
    });

    test('"?" for an empty nickname', () {
      expect(maskedInitial(const {}, 'u1', ''), '?');
    });

    test('"?" for blocked players — the initial must not leak the name', () {
      expect(maskedInitial(const {'u1'}, 'u1', 'Wes'), '?');
    });
  });

  group('PlacementEntry.left', () {
    test('defaults to false when absent on the wire', () {
      final entry = PlacementEntry.fromJson(
          const {'userId': 'u1', 'seat': 0, 'placement': 1});
      expect(entry.left, isFalse);
    });

    test('parses left: true for mid-game leavers', () {
      final entry = PlacementEntry.fromJson(
          const {'userId': 'u1', 'seat': 2, 'placement': 4, 'left': true});
      expect(entry.left, isTrue);
      expect(entry.placement, 4);
    });
  });

  group('friendlyRoomError BLOCKED mapping', () {
    test(
        'the real surface — RoomProtocolError(4216, BLOCKED) from the WS '
        'join stage — maps to Strings.joinBlocked', () {
      // Matchmake HTTP succeeds for a blocked pair; the room's onJoin throws
      // 'BLOCKED', which arrives as a transport ERROR frame (code 4216).
      expect(
        friendlyRoomError(RoomProtocolError(4216, 'BLOCKED'), creating: false),
        Strings.joinBlocked,
      );
    });

    test('a BLOCKED MatchmakeException also maps to Strings.joinBlocked', () {
      expect(
        friendlyRoomError(MatchmakeException('BLOCKED'), creating: false),
        Strings.joinBlocked,
      );
    });

    test('BLOCKED wins over the locked-room heuristic', () {
      // 'blocked' CONTAINS 'locked' as a substring — the blocked branch must
      // run first or every block rejection would read as "room full".
      expect(
        friendlyRoomError(
            MatchmakeException('onJoin: BLOCKED', httpStatus: 403),
            creating: false),
        Strings.joinBlocked,
      );
    });

    test('locked/full rooms still map to roomFull', () {
      expect(
        friendlyRoomError(
            MatchmakeException('room "abc" is locked', code: 4212),
            creating: false),
        Strings.roomFull,
      );
    });
  });
}
