import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/audio/sfx_service.dart';
import 'package:trude/core/haptics/haptics_service.dart';
import 'package:trude/core/motion/animation_speed.dart';
import 'package:trude/core/storage/settings_providers.dart';

class _FakeSettingsStore implements SettingsStore {
  AppSettings? _settings;
  int saves = 0;

  @override
  AppSettings? load() => _settings;

  @override
  void save(AppSettings settings) {
    _settings = settings;
    saves++;
  }

  @override
  void clear() => _settings = null;
}

void main() {
  test('settings round-trip through the store across app restarts', () {
    final store = _FakeSettingsStore();

    // First "run": change every setting from its default.
    final first = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(store)]);
    expect(first.read(settingsProvider).soundOn, isTrue);
    expect(first.read(animationSpeedChoiceProvider), AnimationSpeed.normal);

    first.read(animationSpeedChoiceProvider.notifier).set(AnimationSpeed.fast);
    first.read(settingsProvider.notifier).setSoundOn(false);
    first.read(settingsProvider.notifier).setHapticsOn(false);
    first.read(settingsProvider.notifier).setLocaleCode('ru');
    expect(store.saves, 4);
    first.dispose();

    // Second "run" on the same store: everything came back.
    final second = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(store)]);
    final settings = second.read(settingsProvider);
    expect(settings.animationSpeed, 'fast');
    expect(settings.soundOn, isFalse);
    expect(settings.hapticsOn, isFalse);
    expect(settings.localeCode, 'ru');

    // Derived providers pick the persisted values up.
    expect(second.read(animationSpeedChoiceProvider), AnimationSpeed.fast);
    expect(second.read(localeOverrideProvider)?.languageCode, 'ru');
    second.dispose();
  });

  test('sound/haptics toggles gate the services', () {
    final store = _FakeSettingsStore();
    final container = ProviderContainer(
        overrides: [settingsStoreProvider.overrideWithValue(store)]);
    addTearDown(container.dispose);

    final sfx = container.read(sfxProvider);
    final haptics = container.read(hapticsProvider);
    expect(sfx.enabled, isTrue);
    expect(haptics.enabled, isTrue);

    container.read(settingsProvider.notifier).setSoundOn(false);
    container.read(settingsProvider.notifier).setHapticsOn(false);

    // Same service instances observe the flip through their enabledOf gate.
    expect(sfx.enabled, isFalse);
    expect(haptics.enabled, isFalse);
  });
}
