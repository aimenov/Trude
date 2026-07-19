/// google_mobile_ads-backed [AdsBackend].
///
/// THE ONLY FILE in the app allowed to import `google_mobile_ads` — the
/// plugin has no web implementation, so any other import site breaks
/// `flutter build web`. Reached exclusively through the conditional import in
/// `ads_backend_factory.dart`.
///
/// Safety discipline (copied from `PlayersSfxBackend.warmUp`): the factory's
/// runtime platform gate is NOT enough — VM widget tests report
/// `defaultTargetPlatform == android`, so this class does get constructed
/// under `flutter test`. The real safety is the try/catch probe in [init]:
/// a raw method-channel call (the SDK's idempotent `_init`) throws a
/// catchable `MissingPluginException` when the channels are missing, and we
/// mark the backend broken forever — without ever constructing the
/// `MobileAds.instance` singleton, whose unawaited `_init` invoke would
/// otherwise surface an uncatchable async error. Construction itself must
/// never touch a plugin channel.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_config.dart';
import 'ads_backend.dart';

class GoogleAdsBackend implements AdsBackend {
  GoogleAdsBackend();

  /// Load retries are capped: initial attempt + retries up to this total.
  static const _maxLoadAttempts = 3;

  bool _initialized = false;

  /// Set when plugin channels are unavailable (VM tests) or init failed;
  /// keeps every later call a cheap no-op, forever.
  bool _broken = false;

  RewardedAd? _rewarded;
  final ValueNotifier<bool> _ready = ValueNotifier<bool>(false);
  bool _loading = false;
  bool _showing = false;
  int _loadAttempts = 0;
  Timer? _retryTimer;
  bool _disposed = false;

  @override
  bool get supported => _initialized && !_broken;

  @override
  ValueListenable<bool> get rewardedReady => _ready;

  String get _rewardedUnitId => defaultTargetPlatform == TargetPlatform.iOS
      ? AdConfig.iosRewardedUnitId
      : AdConfig.androidRewardedUnitId;

  @override
  Future<void> init() async {
    if (_initialized || _broken || _disposed) return;
    try {
      // Probe the plugin's method channel RAW before touching
      // `MobileAds.instance`: the singleton's constructor fires an unawaited
      // `_init` invoke whose MissingPluginException would surface as an
      // uncatchable async error under VM tests. `_init` is the SDK's own
      // idempotent hot-restart cleanup call (safe pre-initialize on device);
      // when the channels are missing it throws HERE, catchably, and the
      // singleton is never constructed. Same discipline as
      // PlayersSfxBackend.warmUp's raw-channel probe.
      await const MethodChannel('plugins.flutter.io/google_mobile_ads')
          .invokeMethod<void>('_init');
      await MobileAds.instance.initialize();
      _initialized = true;
    } catch (e) {
      _broken = true;
      if (kDebugMode) debugPrint('GoogleAdsBackend: plugin unavailable: $e');
      return;
    }
    await preloadRewarded();
  }

  @override
  Future<void> preloadRewarded() async {
    if (!supported || _disposed || _loading || _rewarded != null) return;
    // An explicit preload (screen entry) gets a fresh retry budget unless a
    // backoff retry is already pending.
    if (_retryTimer == null) _loadAttempts = 0;
    await _load();
  }

  Future<void> _load() async {
    if (!supported || _disposed || _loading || _rewarded != null) return;
    _loading = true;
    _loadAttempts++;
    try {
      await RewardedAd.load(
        adUnitId: _rewardedUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            _loading = false;
            _loadAttempts = 0;
            _retryTimer?.cancel();
            _retryTimer = null;
            if (_disposed) {
              ad.dispose();
              return;
            }
            _rewarded = ad;
            _ready.value = true;
          },
          onAdFailedToLoad: (error) {
            _loading = false;
            if (kDebugMode) {
              debugPrint('GoogleAdsBackend: rewarded load failed: $error');
            }
            _scheduleRetry();
          },
        ),
      );
    } catch (e) {
      // A throw here (vs the failure callback) means broken plumbing.
      _loading = false;
      _broken = true;
      if (kDebugMode) debugPrint('GoogleAdsBackend: load threw: $e');
    }
  }

  /// Exponential backoff, capped at [_maxLoadAttempts] total attempts. After
  /// the cap the "watch ad" buttons simply stay absent (never an error);
  /// the next explicit [preloadRewarded] resets the budget.
  void _scheduleRetry() {
    if (_disposed || _loadAttempts >= _maxLoadAttempts) {
      _retryTimer = null;
      return;
    }
    final delay = Duration(seconds: 2 << (_loadAttempts - 1)); // 2s, 4s
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(_load());
    });
  }

  @override
  Future<AdReward?> showRewarded() async {
    final ad = _rewarded;
    if (!supported || _disposed || _showing || ad == null) return null;
    _showing = true;
    _rewarded = null;
    _ready.value = false;

    final done = Completer<AdReward?>();
    AdReward? earned;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!done.isCompleted) done.complete(earned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        if (kDebugMode) debugPrint('GoogleAdsBackend: show failed: $error');
        ad.dispose();
        if (!done.isCompleted) done.complete(null);
      },
    );
    try {
      // onUserEarnedReward fires before the dismiss callback; the completer
      // resolves on dismiss so the caller sees the final outcome.
      await ad.show(onUserEarnedReward: (_, reward) {
        earned = AdReward(amount: reward.amount, type: reward.type);
      });
    } catch (e) {
      if (kDebugMode) debugPrint('GoogleAdsBackend: show threw: $e');
      try {
        await ad.dispose();
      } catch (_) {}
      if (!done.isCompleted) done.complete(null);
    }
    final result = await done.future;
    _showing = false;
    // Re-preload after dismiss so the next placement is instant.
    unawaited(preloadRewarded());
    return result;
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    final ad = _rewarded;
    _rewarded = null;
    if (ad != null) {
      try {
        await ad.dispose();
      } catch (_) {}
    }
    _ready.dispose();
  }
}
