import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:trude/core/net/connection_providers.dart';
import 'package:trude/core/storage/guest_identity_store.dart';
import 'package:trude/core/storage/identity_providers.dart';
import 'package:trude/core/strings.dart';
import 'package:trude/features/moderation/blocked_players_screen.dart';
import 'package:trude/l10n/app_localizations.dart';

class _FakeStore implements GuestIdentityStore {
  GuestIdentity? _identity =
      const GuestIdentity(deviceId: 'test-device-12345', nickname: 'Tester');

  @override
  GuestIdentity? load() => _identity;

  @override
  void save(GuestIdentity identity) => _identity = identity;

  @override
  void clear() => _identity = null;
}

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

/// Serves /me/blocks from the (mutable) [blocks] list; DELETE removes the
/// matching row like the real server would.
TrudeClient _fakeClient(List<Map<String, Object>> blocks, List<String> log) {
  return TrudeClient(
    'http://fake.test',
    httpClient: MockClient((request) async {
      log.add('${request.method} ${request.url.path}');
      final path = request.url.path;
      if (request.method == 'POST' && path == '/auth/guest') {
        return _json({
          'token': 'fake-token',
          'userId': 'me1',
          'nickname': 'Tester',
          'avatar': 'a0',
        });
      }
      if (request.method == 'GET' && path == '/me/blocks') {
        return _json({'blocks': blocks});
      }
      if (request.method == 'DELETE' && path.startsWith('/me/blocks/')) {
        final userId = path.substring('/me/blocks/'.length);
        blocks.removeWhere((b) => b['userId'] == userId);
        return http.Response('', 204);
      }
      return http.Response('not found', 404);
    }),
  );
}

Widget _app(TrudeClient client) => ProviderScope(
      overrides: [
        guestIdentityStoreProvider.overrideWithValue(_FakeStore()),
        trudeClientProvider.overrideWithValue(client),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BlockedPlayersScreen(),
      ),
    );

void main() {
  testWidgets('lists blocked players and unblocks one', (tester) async {
    final blocks = <Map<String, Object>>[
      {
        'userId': 'u2',
        'nickname': 'Plut',
        'createdAt': '2026-07-01T00:00:00.000Z',
      },
      {
        'userId': 'u3',
        'nickname': 'Katala',
        'createdAt': '2026-07-02T00:00:00.000Z',
      },
    ];
    final log = <String>[];
    final client = _fakeClient(blocks, log);
    addTearDown(client.close);

    await tester.pumpWidget(_app(client));
    await tester.pumpAndSettle();

    expect(find.text(Strings.blockedPlayersTitle), findsOneWidget);
    expect(find.text('Plut'), findsOneWidget);
    expect(find.text('Katala'), findsOneWidget);
    expect(find.text(Strings.unblockPlayer), findsNWidgets(2));

    // Unblock the first row: it disappears and the server saw the DELETE.
    await tester.tap(find.text(Strings.unblockPlayer).first);
    await tester.pumpAndSettle();

    expect(log, contains('DELETE /me/blocks/u2'));
    expect(find.text('Plut'), findsNothing);
    expect(find.text('Katala'), findsOneWidget);

    // Unblocking the last row leaves the parlor-voiced empty state.
    await tester.tap(find.text(Strings.unblockPlayer));
    await tester.pumpAndSettle();

    expect(log, contains('DELETE /me/blocks/u3'));
    expect(find.text(Strings.blockedEmpty), findsOneWidget);
  });

  testWidgets('empty list shows «Никого — и славно»', (tester) async {
    final log = <String>[];
    final client = _fakeClient([], log);
    addTearDown(client.close);

    await tester.pumpWidget(_app(client));
    await tester.pumpAndSettle();

    expect(find.text(Strings.blockedEmpty), findsOneWidget);
    expect(find.text(Strings.unblockPlayer), findsNothing);
  });
}
