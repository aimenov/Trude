import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:trude/core/net/connection_providers.dart';
import 'package:trude/core/net/moderation_providers.dart';
import 'package:trude/core/storage/guest_identity_store.dart';
import 'package:trude/core/storage/identity_providers.dart';

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

/// Fake server: one pre-existing block (u-blocked), POST fails with 500 for
/// 'u-fail', DELETE fails with 500 for 'u-fail-del', everything else happy.
TrudeClient _fakeClient({required List<String> calls}) {
  return TrudeClient(
    'http://fake.test',
    httpClient: MockClient((request) async {
      calls.add('${request.method} ${request.url.path}');
      switch ((request.method, request.url.path)) {
        case ('POST', '/auth/guest'):
          return _json({
            'token': 'fake-token',
            'userId': 'me',
            'nickname': 'Tester',
            'avatar': 'a0',
          });
        case ('GET', '/me/blocks'):
          return _json({
            'blocks': [
              {
                'userId': 'u-blocked',
                'nickname': 'Grim',
                // Real wire format: epoch ms (listBlocks convention).
                'createdAt': DateTime.utc(2026, 7, 19).millisecondsSinceEpoch,
              },
            ],
          });
        case ('POST', '/me/blocks'):
          final body =
              (jsonDecode(request.body) as Map).cast<String, dynamic>();
          if (body['userId'] == 'u-fail') {
            return http.Response('{"error":"BOOM"}', 500);
          }
          return _json({'blocked': true});
        case ('DELETE', '/me/blocks/u-fail-del'):
          return http.Response('{"error":"BOOM"}', 500);
        default:
          if (request.method == 'DELETE' &&
              request.url.path.startsWith('/me/blocks/')) {
            return http.Response('', 204);
          }
          return http.Response('not found', 404);
      }
    }),
  );
}

/// A container with the fake identity store + fake client, with the
/// blockedIdsProvider already built and its seed fetch settled.
Future<ProviderContainer> _seededContainer(List<String> calls) async {
  final client = _fakeClient(calls: calls);
  final container = ProviderContainer(overrides: [
    guestIdentityStoreProvider.overrideWithValue(_FakeStore()),
    trudeClientProvider.overrideWithValue(client),
  ]);
  addTearDown(container.dispose);
  addTearDown(client.close);

  // First read builds the notifier: empty until the seed fetch lands.
  expect(container.read(blockedIdsProvider), isEmpty);
  await pumpEventQueue();
  return container;
}

void main() {
  test('seeds from GET /me/blocks after ensuring the session', () async {
    final calls = <String>[];
    final container = await _seededContainer(calls);

    expect(container.read(blockedIdsProvider), {'u-blocked'});
    expect(calls, contains('POST /auth/guest'));
    expect(calls, contains('GET /me/blocks'));
  });

  test('block() applies optimistically, POSTs once, and is idempotent',
      () async {
    final calls = <String>[];
    final container = await _seededContainer(calls);
    calls.clear();

    final future = container.read(blockedIdsProvider.notifier).block('u2');
    // Optimistic: masked before the server answered.
    expect(container.read(blockedIdsProvider), {'u-blocked', 'u2'});
    await future;
    expect(container.read(blockedIdsProvider), {'u-blocked', 'u2'});
    expect(calls, ['POST /me/blocks']);

    // Re-blocking an already blocked id is a local no-op — no second POST.
    await container.read(blockedIdsProvider.notifier).block('u2');
    expect(calls, ['POST /me/blocks']);
  });

  test('failed block() reverts the optimistic add and rethrows', () async {
    final calls = <String>[];
    final container = await _seededContainer(calls);

    final states = <Set<String>>[];
    container.listen(blockedIdsProvider, (_, next) => states.add(next));

    await expectLater(
      container.read(blockedIdsProvider.notifier).block('u-fail'),
      throwsA(isA<TrudeApiException>()),
    );
    // It went optimistic first, then reverted.
    expect(states.first, contains('u-fail'));
    expect(container.read(blockedIdsProvider), {'u-blocked'});
  });

  test('unblock() applies optimistically and DELETEs; no-op when absent',
      () async {
    final calls = <String>[];
    final container = await _seededContainer(calls);
    calls.clear();

    final future =
        container.read(blockedIdsProvider.notifier).unblock('u-blocked');
    // Optimistic: unmasked before the server answered.
    expect(container.read(blockedIdsProvider), isEmpty);
    await future;
    expect(calls, ['DELETE /me/blocks/u-blocked']);

    // Unblocking someone not blocked never hits the server.
    await container.read(blockedIdsProvider.notifier).unblock('u-nobody');
    expect(calls, ['DELETE /me/blocks/u-blocked']);
  });

  test('failed unblock() reverts the optimistic removal and rethrows',
      () async {
    final calls = <String>[];
    final container = await _seededContainer(calls);
    // Get u-fail-del into the set through a successful block first.
    await container.read(blockedIdsProvider.notifier).block('u-fail-del');

    await expectLater(
      container.read(blockedIdsProvider.notifier).unblock('u-fail-del'),
      throwsA(isA<TrudeApiException>()),
    );
    expect(container.read(blockedIdsProvider),
        containsAll(['u-blocked', 'u-fail-del']));
  });

  test('blockedListProvider exposes full entries for the management screen',
      () async {
    final calls = <String>[];
    final container = await _seededContainer(calls);

    final entries = await container.read(blockedListProvider.future);
    expect(entries, hasLength(1));
    expect(entries.single.userId, 'u-blocked');
    expect(entries.single.nickname, 'Grim');
    expect(entries.single.createdAt, DateTime.utc(2026, 7, 19));
  });
}
