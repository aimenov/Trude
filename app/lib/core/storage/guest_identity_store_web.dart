/// Web [GuestIdentityStore] backed by `window.localStorage` (package:web,
/// pure Dart — no plugin needed).
library;

import 'package:web/web.dart' as web;

import 'guest_identity_store.dart';

GuestIdentityStore createStore() => _WebGuestIdentityStore();

const _deviceIdKey = 'trude.deviceId';
const _nicknameKey = 'trude.nickname';

class _WebGuestIdentityStore implements GuestIdentityStore {
  @override
  GuestIdentity? load() {
    final deviceId = web.window.localStorage.getItem(_deviceIdKey);
    final nickname = web.window.localStorage.getItem(_nicknameKey);
    if (deviceId == null || nickname == null) return null;
    return GuestIdentity(deviceId: deviceId, nickname: nickname);
  }

  @override
  void save(GuestIdentity identity) {
    web.window.localStorage.setItem(_deviceIdKey, identity.deviceId);
    web.window.localStorage.setItem(_nicknameKey, identity.nickname);
  }

  @override
  void clear() {
    web.window.localStorage.removeItem(_deviceIdKey);
    web.window.localStorage.removeItem(_nicknameKey);
  }
}
