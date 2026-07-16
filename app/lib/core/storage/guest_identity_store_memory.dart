/// In-memory fallback [GuestIdentityStore] for non-web platforms.
///
/// TODO(mobile): replace with flutter_secure_storage when Developer Mode /
/// mobile toolchains are available (native plugins are currently unbuildable
/// on this machine).
library;

import 'guest_identity_store.dart';

GuestIdentityStore createStore() => _MemoryGuestIdentityStore();

class _MemoryGuestIdentityStore implements GuestIdentityStore {
  GuestIdentity? _identity;

  @override
  GuestIdentity? load() => _identity;

  @override
  void save(GuestIdentity identity) => _identity = identity;

  @override
  void clear() => _identity = null;
}
