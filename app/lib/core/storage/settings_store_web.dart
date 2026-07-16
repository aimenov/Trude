/// Web [SettingsStore] backed by `window.localStorage` (package:web,
/// pure Dart — no plugin needed). One JSON blob under `trude.settings`.
library;

import 'dart:convert';

import 'package:web/web.dart' as web;

import 'settings_store.dart';

SettingsStore createStore() => _WebSettingsStore();

const _settingsKey = 'trude.settings';

class _WebSettingsStore implements SettingsStore {
  @override
  AppSettings? load() {
    final raw = web.window.localStorage.getItem(_settingsKey);
    if (raw == null) return null;
    try {
      return AppSettings.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>());
    } catch (_) {
      return null; // Corrupt blob: fall back to defaults.
    }
  }

  @override
  void save(AppSettings settings) =>
      web.window.localStorage.setItem(_settingsKey, jsonEncode(settings.toJson()));

  @override
  void clear() => web.window.localStorage.removeItem(_settingsKey);
}
