/// `audioplayers`-backed [SfxBackend].
///
/// Design notes (verified against audioplayers 6.8.1 sources in the pub
/// cache):
/// - `AudioPool` was considered and rejected: each pool is bound to a single
///   `Source` (we have per-cue *variant lists*) and `AudioPool.start()` only
///   exposes `volume` — no per-play `playbackRate`, which the ±5% jitter
///   needs. It is web-safe (pure Dart over `AudioPlayer`), just too rigid.
/// - Instead: a small rotating pool of preloaded `AudioPlayer`s with
///   `ReleaseMode.stop`; every play picks the next player (steals the oldest
///   voice when all are busy — cheap polyphony), a random variant, and a
///   jittered rate.
/// - `AudioCache.loadAll` pre-fetches every variant in `warmUp` (temp-file
///   copies on mobile/desktop, browser-cache-priming GETs on web), so the
///   `setSource` at play time resolves from cache.
/// - Every plugin call is wrapped in try/catch, but that alone is not
///   enough under VM tests: constructing the first `AudioPlayer` touches the
///   lazy `GlobalAudioScope`, whose constructor subscribes to the
///   `xyz.luan/audioplayers.global/events` `EventChannel`; a missing channel
///   there is routed straight to `FlutterError.reportError` (uncatchable by
///   user code — see `EventChannel.receiveBroadcastStream`'s onListen), which
///   fails widget tests. So `warmUp` first probes the plugin's global
///   *method* channel (whose `MissingPluginException` IS catchable) and
///   marks the backend broken — never constructing a player — when the
///   plugin isn't registered. The probe is skipped on web, where the plugin
///   is implemented in pure Dart (no method channels; always present).
/// - Web autoplay policy: nothing special needed — audioplayers' web
///   implementation unlocks on the first user-gesture-triggered play, and
///   our first sounds always follow taps.
library;

import 'dart:async';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'sfx_backend.dart';

class PlayersSfxBackend implements SfxBackend {
  PlayersSfxBackend({int poolSize = 6, Random? random})
      : _poolSize = poolSize, // ignore: prefer_initializing_formals
        _random = random ?? Random();

  static const _assetDir = 'assets/audio/';

  /// `AudioCache`'s default prefix — asset paths handed to [AssetSource]
  /// must be relative to it (i.e. `audio/<file>`).
  static const _cachePrefix = 'assets/';

  final int _poolSize;
  final Random _random;

  /// Cue -> asset paths relative to [_cachePrefix].
  final Map<SfxCue, List<String>> _variants = {};
  final List<AudioPlayer> _pool = [];
  int _nextVoice = 0;

  final SfxThrottle _throttle = SfxThrottle();
  final Stopwatch _clock = Stopwatch()..start();

  /// Set when plugin channels are unavailable (VM tests, platform quirks);
  /// keeps every later [play] a cheap no-op.
  bool _broken = false;

  @override
  Future<void> warmUp() async {
    // 1. Manifest: list assets/audio/ and bucket variants by cue name.
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      for (final asset in manifest.listAssets()) {
        if (!asset.startsWith(_assetDir)) continue;
        final cue = cueForAssetFile(asset.substring(_assetDir.length));
        if (cue == null) continue;
        _variants
            .putIfAbsent(cue, () => [])
            .add(asset.substring(_cachePrefix.length));
      }
    } catch (e) {
      if (kDebugMode) debugPrint('SfxBackend: asset manifest unavailable: $e');
      return; // Nothing to play; keep the backend inert.
    }
    if (_variants.isEmpty) return;

    // 2. Plugin availability probe (see library doc): never construct an
    // AudioPlayer when the channels are missing, or the global EventChannel
    // subscription reports an uncatchable error to FlutterError.
    if (!kIsWeb) {
      try {
        // Same call GlobalAudioScope.ensureInitialized makes first; harmless
        // to invoke before any player exists.
        await const MethodChannel('xyz.luan/audioplayers.global')
            .invokeMethod<void>('init');
      } catch (e) {
        _broken = true;
        if (kDebugMode) debugPrint('SfxBackend: plugin unavailable: $e');
        return;
      }
    }

    // 3. Player pool. The first awaited call per player surfaces any
    // remaining creation failure right here.
    try {
      for (var i = 0; i < _poolSize; i++) {
        final player = AudioPlayer();
        await player.setReleaseMode(ReleaseMode.stop);
        _pool.add(player);
      }
    } catch (e) {
      _broken = true;
      if (kDebugMode) debugPrint('SfxBackend: init failed, muting: $e');
      return;
    }

    // 4. Pre-fetch every variant so play-time setSource hits the cache.
    // Non-fatal: players fall back to fetching on demand.
    try {
      await AudioCache.instance
          .loadAll(_variants.values.expand((v) => v).toList());
    } catch (_) {}
  }

  @override
  void play(SfxCue cue) {
    if (_broken || _pool.isEmpty) return;
    final variants = _variants[cue];
    if (variants == null || variants.isEmpty) return;
    if (!_throttle.shouldPlay(cue, _clock.elapsed)) return;

    final path = variants[_random.nextInt(variants.length)];
    final player = _pool[_nextVoice];
    _nextVoice = (_nextVoice + 1) % _pool.length;
    // ±5% playback-rate jitter (never-identical rule).
    final rate = 0.95 + _random.nextDouble() * 0.10;
    unawaited(_playOn(player, path, rate).catchError((_) {}));
  }

  Future<void> _playOn(AudioPlayer player, String path, double rate) async {
    try {
      await player.stop();
      await player.setSource(AssetSource(path));
      try {
        // Where supported; some platforms reject rate changes — not fatal.
        await player.setPlaybackRate(rate);
      } catch (_) {}
      await player.resume();
    } catch (_) {
      // Silently degrade on any plugin/platform quirk.
    }
  }

  /// Best-effort teardown (provider disposal, hot restart).
  Future<void> dispose() async {
    final players = List.of(_pool);
    _pool.clear();
    for (final player in players) {
      try {
        await player.dispose();
      } catch (_) {}
    }
  }
}
