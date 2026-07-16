import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/app.dart';
import 'package:trude/core/storage/guest_identity_store.dart';
import 'package:trude/core/storage/identity_providers.dart';
import 'package:trude/core/strings.dart';

class _FakeStore implements GuestIdentityStore {
  _FakeStore([this._identity]);

  GuestIdentity? _identity;

  @override
  GuestIdentity? load() => _identity;

  @override
  void save(GuestIdentity identity) => _identity = identity;

  @override
  void clear() => _identity = null;
}

void main() {
  testWidgets('redirects to the nickname screen without an identity',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        guestIdentityStoreProvider.overrideWithValue(_FakeStore()),
      ],
      child: const TrudeApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text(Strings.nicknameTitle), findsOneWidget);
    expect(find.text(Strings.play), findsOneWidget);
  });

  testWidgets('shows the home screen when an identity is persisted',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        guestIdentityStoreProvider.overrideWithValue(_FakeStore(
            const GuestIdentity(deviceId: 'test-device', nickname: 'Tester'))),
      ],
      child: const TrudeApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.text(Strings.playingAs('Tester')), findsOneWidget);
    expect(find.text(Strings.createRoom), findsOneWidget);
    expect(find.text(Strings.openRooms), findsOneWidget);
    expect(find.text(Strings.joinByCode), findsOneWidget);
  });
}
