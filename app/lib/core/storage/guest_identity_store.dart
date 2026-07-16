/// Persistence for the guest identity (deviceId + nickname).
///
/// On web this is backed by `localStorage` (package:web, pure Dart). On other
/// platforms it is an in-memory fallback for now.
///
/// TODO(mobile): switch the io implementation to flutter_secure_storage once
/// Windows Developer Mode / the mobile toolchains are available (plugin
/// packages currently break the build because symlink support is off).
library;

import 'dart:math';

import 'guest_identity_store_memory.dart'
    if (dart.library.js_interop) 'guest_identity_store_web.dart' as impl;

class GuestIdentity {
  const GuestIdentity({required this.deviceId, required this.nickname});

  final String deviceId;
  final String nickname;
}

/// Synchronous on purpose: both current backends are synchronous, which keeps
/// app bootstrap and the router redirect trivial. May become async when a
/// secure-storage backend lands.
abstract interface class GuestIdentityStore {
  GuestIdentity? load();
  void save(GuestIdentity identity);
  void clear();
}

GuestIdentityStore createGuestIdentityStore() => impl.createStore();

/// Random UUID v4, used as the persistent guest deviceId.
String generateDeviceId() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
  final hex =
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
