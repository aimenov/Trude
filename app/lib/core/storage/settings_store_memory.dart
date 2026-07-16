/// In-memory fallback [SettingsStore] for non-web platforms.
library;

import 'settings_store.dart';

SettingsStore createStore() => _MemorySettingsStore();

class _MemorySettingsStore implements SettingsStore {
  AppSettings? _settings;

  @override
  AppSettings? load() => _settings;

  @override
  void save(AppSettings settings) => _settings = settings;

  @override
  void clear() => _settings = null;
}
