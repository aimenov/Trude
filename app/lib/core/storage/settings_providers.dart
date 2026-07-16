import 'dart:ui' show Locale;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_store.dart';

export 'settings_store.dart' show AppSettings, SettingsStore;

/// The one settings store instance for the app (overridable in tests).
final settingsStoreProvider =
    Provider<SettingsStore>((ref) => createSettingsStore());

/// The persisted user settings; every write is saved through the store.
final settingsProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() =>
      ref.watch(settingsStoreProvider).load() ?? const AppSettings();

  void _update(AppSettings next) {
    ref.read(settingsStoreProvider).save(next);
    state = next;
  }

  /// [name] is AnimationSpeed.name: 'normal' | 'fast' | 'off'.
  void setAnimationSpeed(String name) =>
      _update(state.copyWith(animationSpeed: name));

  void setSoundOn(bool on) => _update(state.copyWith(soundOn: on));

  void setHapticsOn(bool on) => _update(state.copyWith(hapticsOn: on));

  /// [code] is 'system' | 'en' | 'ru'.
  void setLocaleCode(String code) => _update(state.copyWith(localeCode: code));
}

/// The app-wide locale override; null means "follow the system".
final localeOverrideProvider = Provider<Locale?>((ref) {
  final code = ref.watch(settingsProvider.select((s) => s.localeCode));
  return code == 'system' ? null : Locale(code);
});
