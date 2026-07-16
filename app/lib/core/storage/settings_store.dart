/// Persistence for user settings (animation speed, sound, haptics, locale).
///
/// Same pattern as [GuestIdentityStore]: web is backed by `localStorage`
/// (package:web, pure Dart), other platforms fall back to memory until a
/// plugin-backed store is possible.
library;

import 'settings_store_memory.dart'
    if (dart.library.js_interop) 'settings_store_web.dart' as impl;

/// Plain persisted values; enum mapping lives at the provider layer so the
/// storage layer stays dependency-free.
class AppSettings {
  const AppSettings({
    this.animationSpeed = 'normal',
    this.soundOn = true,
    this.hapticsOn = true,
    this.localeCode = 'system',
  });

  /// 'normal' | 'fast' | 'off' (AnimationSpeed.name).
  final String animationSpeed;
  final bool soundOn;
  final bool hapticsOn;

  /// 'system' | 'en' | 'ru'.
  final String localeCode;

  AppSettings copyWith({
    String? animationSpeed,
    bool? soundOn,
    bool? hapticsOn,
    String? localeCode,
  }) =>
      AppSettings(
        animationSpeed: animationSpeed ?? this.animationSpeed,
        soundOn: soundOn ?? this.soundOn,
        hapticsOn: hapticsOn ?? this.hapticsOn,
        localeCode: localeCode ?? this.localeCode,
      );

  Map<String, dynamic> toJson() => {
        'animationSpeed': animationSpeed,
        'soundOn': soundOn,
        'hapticsOn': hapticsOn,
        'localeCode': localeCode,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        animationSpeed: json['animationSpeed'] as String? ?? 'normal',
        soundOn: json['soundOn'] as bool? ?? true,
        hapticsOn: json['hapticsOn'] as bool? ?? true,
        localeCode: json['localeCode'] as String? ?? 'system',
      );
}

/// Synchronous on purpose, like [GuestIdentityStore] — both backends are
/// synchronous, which keeps app bootstrap trivial.
abstract interface class SettingsStore {
  AppSettings? load();
  void save(AppSettings settings);
  void clear();
}

SettingsStore createSettingsStore() => impl.createStore();
