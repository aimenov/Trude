/// Rewarded-ads engine contract, plugin-free.
///
/// Mirrors the `SfxBackend` split: this file is pure Dart/foundation (safe on
/// every platform incl. web), while the google_mobile_ads-backed
/// implementation lives in `ads_backend_google.dart` — the ONLY file allowed
/// to import the plugin. Callers obtain a backend via
/// `ads_backend_factory.dart`, never by constructing one directly.
library;

import 'package:flutter/foundation.dart';

/// SDK-side receipt that the user watched a rewarded ad to completion.
///
/// [amount]/[type] are AdMob metadata only — the coins actually granted are
/// always decided by the server (POST /ads/reward).
class AdReward {
  const AdReward({this.amount = 0, this.type = ''});

  final num amount;
  final String type;
}

/// The rewarded-ads engine behind `AdsService`. Implementations must be safe
/// to call anywhere: every method must never throw (silently no-op when the
/// plugin channels are missing, e.g. under VM tests or on web/desktop).
abstract interface class AdsBackend {
  /// False for the no-op/broken backend; the UI hides every ad entry point.
  /// Only meaningful after [init] completed.
  bool get supported;

  /// True while a rewarded ad is loaded and ready to show.
  ValueListenable<bool> get rewardedReady;

  /// One-time startup: SDK init probe + first preload. Must never throw;
  /// marks the backend broken forever when plugin channels are unavailable.
  Future<void> init();

  /// (Re)loads a rewarded ad when none is ready. Must never throw.
  Future<void> preloadRewarded();

  /// Shows the loaded rewarded ad; resolves once the ad flow is over
  /// (dismissed). Null when nothing was shown or the user bailed before
  /// earning the reward. Must never throw.
  Future<AdReward?> showRewarded();

  /// Best-effort teardown. Must never throw.
  Future<void> dispose();
}

/// Const [ValueListenable] that is always `false` and never notifies.
class AlwaysFalseListenable implements ValueListenable<bool> {
  const AlwaysFalseListenable();

  @override
  bool get value => false;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}

/// Inert backend for web/desktop/tests: nothing is ever supported, ready, or
/// shown.
class NoopAdsBackend implements AdsBackend {
  const NoopAdsBackend();

  @override
  bool get supported => false;

  @override
  ValueListenable<bool> get rewardedReady => const AlwaysFalseListenable();

  @override
  Future<void> init() async {}

  @override
  Future<void> preloadRewarded() async {}

  @override
  Future<AdReward?> showRewarded() async => null;

  @override
  Future<void> dispose() async {}
}
