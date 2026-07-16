import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'guest_identity_store.dart';

/// The one store instance for the app (overridable in tests).
final guestIdentityStoreProvider =
    Provider<GuestIdentityStore>((ref) => createGuestIdentityStore());

/// The persisted guest identity, or null before the nickname screen ran.
final identityProvider =
    NotifierProvider<IdentityController, GuestIdentity?>(IdentityController.new);

class IdentityController extends Notifier<GuestIdentity?> {
  @override
  GuestIdentity? build() => ref.watch(guestIdentityStoreProvider).load();

  /// Sets (or renames) the identity, keeping an existing deviceId.
  GuestIdentity setNickname(String nickname) {
    final identity = GuestIdentity(
      deviceId: state?.deviceId ?? generateDeviceId(),
      nickname: nickname,
    );
    ref.read(guestIdentityStoreProvider).save(identity);
    state = identity;
    return identity;
  }
}
