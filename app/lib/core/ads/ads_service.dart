/// Rewarded-ads facade: server ad-tokens + SDK show flow in one place.
///
/// UI contract (shop "+25" button, results "double your winnings" button):
/// - call [AdsService.prepare] on screen/panel mount (preloads an ad and
///   pre-fetches a single-use server token);
/// - show the button only while [AdsService.canOffer] is true (backed by
///   [AdsService.rewardedReady] for reactivity);
/// - on tap, await [AdsService.earn] — it returns the server-granted coins,
///   or null on ANY failure. This facade never throws to the UI; a missing
///   ad/cap/network hiccup just means the button is absent or the tap is a
///   silent no-op.
///
/// Wallet/meProvider updates are the caller's job (the results panel does an
/// animated count-up with the returned coins; see plan §C-C) — [earn] only
/// reports what the server granted.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../net/connection_providers.dart';
import 'ads_backend.dart';
import 'ads_backend_factory.dart';

/// Single-use server ad token (GET /ads/token).
class AdsTokenInfo {
  const AdsTokenInfo({required this.token, required this.remainingToday});

  final String token;
  final int remainingToday;
}

/// Server grant for a completed rewarded ad (POST /ads/reward).
class AdEarnResult {
  const AdEarnResult({
    required this.coins,
    required this.balance,
    required this.remainingToday,
  });

  /// Coins granted by this ad.
  final int coins;

  /// Wallet balance after the grant.
  final int balance;

  /// How many more ads of this kind the server will pay for today.
  final int remainingToday;
}

typedef AdsTokenFetch = Future<AdsTokenInfo> Function(String kind,
    {String? gameId});
typedef AdsRewardPost = Future<AdEarnResult> Function(String token);

/// App-wide rewarded-ads service. On web/desktop the factory hands out
/// [NoopAdsBackend] ⇒ [AdsService.supported] is false and every UI entry
/// point stays hidden.
final adsProvider = Provider<AdsService>((ref) {
  final client = ref.watch(trudeClientProvider);
  final service = AdsService(
    backend: createAdsBackend(),
    fetchToken: (kind, {gameId}) async {
      final dynamic res = await client.getAdsToken(kind, gameId: gameId);
      return AdsTokenInfo(
        token: _field(res, 'token') as String,
        remainingToday: _asInt(_field(res, 'remainingToday')),
      );
    },
    postReward: (token) async {
      final dynamic res = await client.postAdReward(token);
      return AdEarnResult(
        coins: _asInt(_field(res, 'coins')),
        balance: _asInt(_field(res, 'balance')),
        remainingToday: _asInt(_field(res, 'remainingToday')),
      );
    },
  );
  unawaited(service.init());
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

/// Reads [name] off either a decoded JSON map or a typed model whose field
/// names follow the wire contract (lane C-B owns the model classes; this
/// seam works with both shapes).
dynamic _field(dynamic o, String name) {
  if (o is Map) return o[name];
  final dynamic d = o;
  switch (name) {
    case 'token':
      return d.token;
    case 'remainingToday':
      return d.remainingToday;
    case 'coins':
      return d.coins;
    case 'balance':
      return d.balance;
  }
  return null;
}

int _asInt(dynamic v) => v == null ? 0 : (v as num).toInt();

class AdsService {
  AdsService({
    required this._backend,
    required this._fetchToken,
    required this._postReward,
    this._retryBaseDelay = const Duration(milliseconds: 500),
  });

  /// Total POST /ads/reward attempts per earned ad (1 initial + retries).
  static const _maxPostAttempts = 3;

  final AdsBackend _backend;
  final AdsTokenFetch _fetchToken;
  final AdsRewardPost _postReward;
  final Duration _retryBaseDelay;

  /// Pre-fetched tokens by placement slot ("kind" / "kind:gameId").
  final Map<String, AdsTokenInfo> _tokens = {};

  /// Last-known server headroom by kind; null until a token was fetched.
  final Map<String, int> _remaining = {};

  bool _earning = false;

  /// False on web/desktop (no-op backend) and when plugin channels turned
  /// out to be missing — hide every ad entry point.
  bool get supported => _backend.supported;

  /// True while a rewarded ad is loaded; listen for button visibility.
  ValueListenable<bool> get rewardedReady => _backend.rewardedReady;

  /// Server headroom for [kind] as of the last token fetch; null = unknown.
  int? remainingToday(String kind) => _remaining[kind];

  /// Whether an ad button for [kind] should be visible right now.
  bool canOffer(String kind) =>
      supported && rewardedReady.value && (_remaining[kind] ?? 1) > 0;

  /// One-time startup (backend probe + first preload). Never throws.
  Future<void> init() => _backend.init();

  /// Preloads an ad and pre-fetches a token for [kind]. Call on shop entry
  /// and results-panel mount. Never throws; on token failure the cap count
  /// stays unknown and [earn] fetches a fresh token itself.
  Future<void> prepare(String kind, {String? gameId}) async {
    if (!supported) return;
    unawaited(_backend.preloadRewarded());
    try {
      final token = await _fetchToken(kind, gameId: gameId);
      _tokens[_slot(kind, gameId)] = token;
      _remaining[kind] = token.remainingToday;
    } catch (_) {
      // Silent: the button just won't show / earn() will retry the fetch.
    }
  }

  /// Full earn flow: token → show ad → (user earned) → POST /ads/reward.
  /// Returns the server grant, or null on any failure — never throws.
  /// Exactly one successful POST per watched ad.
  Future<AdEarnResult?> earn(String kind, {String? gameId}) async {
    if (!supported || !_backend.rewardedReady.value || _earning) return null;
    _earning = true;
    try {
      final slot = _slot(kind, gameId);
      var token = _tokens.remove(slot);
      if (token == null) {
        try {
          token = await _fetchToken(kind, gameId: gameId);
        } catch (_) {
          return null;
        }
      }
      _remaining[kind] = token.remainingToday;
      if (token.remainingToday <= 0) return null;

      final reward = await _backend.showRewarded();
      if (reward == null) {
        // Dismissed before earning / show failed: token unused, keep it for
        // the next tap (it expires server-side in ~5 min anyway).
        _tokens[slot] = token;
        return null;
      }

      final result = await _postRewardWithRetry(kind, token.token);
      if (result != null) _remaining[kind] = result.remainingToday;
      // Line up the next placement (fresh ad + fresh token).
      unawaited(prepare(kind, gameId: gameId));
      return result;
    } catch (_) {
      return null; // Belt and braces: never throw to UI.
    } finally {
      _earning = false;
    }
  }

  Future<AdEarnResult?> _postRewardWithRetry(String kind, String token) async {
    var delay = _retryBaseDelay;
    for (var attempt = 1; attempt <= _maxPostAttempts; attempt++) {
      try {
        return await _postReward(token);
      } catch (e) {
        // 4xx (BAD_TOKEN / TOKEN_USED / DAILY_CAP) can never succeed on
        // retry; only retry transient failures (network, 5xx).
        if (e is TrudeApiException &&
            e.statusCode >= 400 &&
            e.statusCode < 500) {
          if (e.statusCode == 429) _remaining[kind] = 0;
          return null;
        }
        if (attempt < _maxPostAttempts) {
          await Future<void>.delayed(delay);
          delay *= 2;
        }
      }
    }
    return null;
  }

  String _slot(String kind, String? gameId) =>
      gameId == null ? kind : '$kind:$gameId';

  Future<void> dispose() => _backend.dispose();
}
