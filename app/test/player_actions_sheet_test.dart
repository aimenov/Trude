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
import 'package:trude/features/moderation/player_actions_sheet.dart';
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

/// Serves auth + moderation endpoints from canned JSON, logging every call
/// as `"METHOD /path"` into [log].
TrudeClient _fakeClient(List<String> log) {
  return TrudeClient(
    'http://fake.test',
    httpClient: MockClient((request) async {
      log.add('${request.method} ${request.url.path}');
      switch ((request.method, request.url.path)) {
        case ('POST', '/auth/guest'):
          return _json({
            'token': 'fake-token',
            'userId': 'me1',
            'nickname': 'Tester',
            'avatar': 'a0',
          });
        case ('GET', '/me/blocks'):
          return _json({'blocks': <Object>[]});
        case ('POST', '/reports'):
          return _json({'received': true});
        case ('POST', '/me/blocks'):
          return _json({'blocked': true});
        default:
          return http.Response('not found', 404);
      }
    }),
  );
}

/// A button that opens the sheet for [userId], with optional lobby extras.
class _Host extends ConsumerWidget {
  const _Host({required this.userId, this.extras});

  final String userId;
  final PlayerActionsExtras? extras;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () => showPlayerActionsSheet(context, ref,
              userId: userId, nickname: 'Plut', extras: extras),
          child: const Text('open'),
        ),
      ),
    );
  }
}

Widget _app(TrudeClient client, Widget home) => ProviderScope(
      overrides: [
        guestIdentityStoreProvider.overrideWithValue(_FakeStore()),
        trudeClientProvider.overrideWithValue(client),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

void main() {
  testWidgets('report flow: reason dialog -> POST /reports -> snackbar',
      (tester) async {
    final log = <String>[];
    final client = _fakeClient(log);
    addTearDown(client.close);

    await tester.pumpWidget(_app(client, const _Host(userId: 'u2')));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The sheet shows the (unblocked) nickname and the report row.
    expect(find.text('Plut'), findsOneWidget);
    await tester.tap(find.text(Strings.reportPlayer));
    await tester.pumpAndSettle();

    // All four reasons are offered.
    expect(find.text(Strings.reportReasonNickname), findsOneWidget);
    expect(find.text(Strings.reportReasonCheating), findsOneWidget);
    expect(find.text(Strings.reportReasonAbuse), findsOneWidget);
    expect(find.text(Strings.reportReasonOther), findsOneWidget);

    await tester.tap(find.text(Strings.reportReasonCheating));
    await tester.pumpAndSettle();

    expect(log, contains('POST /reports'));
    expect(find.text(Strings.reportSent), findsOneWidget);
    // The sheet closed itself after reporting.
    expect(find.text(Strings.reportPlayer), findsNothing);
  });

  testWidgets('block: POST /me/blocks, sheet closes with a snackbar',
      (tester) async {
    final log = <String>[];
    final client = _fakeClient(log);
    addTearDown(client.close);

    await tester.pumpWidget(_app(client, const _Host(userId: 'u2')));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(Strings.blockPlayer));
    await tester.pumpAndSettle();

    expect(log, contains('POST /me/blocks'));
    expect(find.text(Strings.playerBlocked), findsOneWidget);
    expect(find.text(Strings.reportPlayer), findsNothing);
  });

  testWidgets('never shown for self', (tester) async {
    final log = <String>[];
    final client = _fakeClient(log);
    addTearDown(client.close);

    // The host asks to open the sheet for the signed-in user's own id.
    await tester.pumpWidget(_app(client, const _Host(userId: 'me1')));
    final container = ProviderScope.containerOf(
        tester.element(find.byType(_Host)),
        listen: false);
    await container.read(sessionProvider.notifier).ensure();
    await tester.pump();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(Strings.reportPlayer), findsNothing);
    expect(find.text(Strings.blockPlayer), findsNothing);
  });

  testWidgets('lobby extras: swap and kick rows close the sheet and fire',
      (tester) async {
    final log = <String>[];
    final client = _fakeClient(log);
    addTearDown(client.close);
    var swaps = 0;
    var kicks = 0;

    await tester.pumpWidget(_app(
      client,
      _Host(
        userId: 'u2',
        extras: PlayerActionsExtras(
          onRequestSwap: () => swaps++,
          onKick: () => kicks++,
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text(Strings.requestSwap), findsOneWidget);
    await tester.tap(find.text(Strings.kickPlayer));
    await tester.pumpAndSettle();

    expect(kicks, 1);
    expect(swaps, 0);
    expect(find.text(Strings.reportPlayer), findsNothing);
  });
}
