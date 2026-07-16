/// Playback-engine contract for the semantic sound layer, plus the pure
/// plugin-free helpers (cue parsing, re-trigger throttle) so they stay
/// unit-testable without any plugin channels.
///
/// Asset naming convention (the backend builds its manifest from
/// `AssetManifest` at runtime, so audio files can be added/removed freely
/// without touching Dart): `assets/audio/<cueName>_<n>.<ext>` where
/// `<cueName>` is exactly the [SfxCue] enum value name, e.g.
/// `assets/audio/cardLand_1.ogg`, `assets/audio/verdictLie_2.wav`.
library;

/// One value per [SfxService] slot method. Enum value names double as the
/// asset file-name prefixes (see library doc).
enum SfxCue {
  shuffle,
  cardThrow,
  cardLand,
  claimStamp,
  revealTension,
  cardSlide,
  flipSnap,
  verdictTruth,
  verdictLie,
  pilePickup,
  quadFanfare,
  jokerReveal,
  yourTurn,
  timerUrgent,
  reactionPop,
  uiTap,
}

/// The playback engine behind [SfxService]. Implementations must be safe to
/// call anywhere: `play` is fire-and-forget and must never throw (silently
/// no-op when plugin channels are missing, e.g. under VM tests).
abstract interface class SfxBackend {
  /// Loads the asset manifest and prepares players. Call once at startup;
  /// must never throw.
  Future<void> warmUp();

  /// Plays one variant of [cue]. Fire-and-forget; must never throw.
  void play(SfxCue cue);
}

/// Silent backend for tests and fallback wiring.
class NoopSfxBackend implements SfxBackend {
  const NoopSfxBackend();

  @override
  Future<void> warmUp() async {}

  @override
  void play(SfxCue cue) {}
}

/// Maps an audio asset file name (no directory, e.g. `cardLand_1.ogg`) to its
/// cue per the naming convention, or null when it doesn't match any cue.
SfxCue? cueForAssetFile(String fileName) {
  final dot = fileName.indexOf('.');
  final base = dot == -1 ? fileName : fileName.substring(0, dot);
  final underscore = base.lastIndexOf('_');
  if (underscore <= 0) return null;
  if (int.tryParse(base.substring(underscore + 1)) == null) return null;
  final cueName = base.substring(0, underscore);
  for (final cue in SfxCue.values) {
    if (cue.name == cueName) return cue;
  }
  return null;
}

/// Per-cue minimum re-trigger interval, kept pure (caller supplies the clock
/// as an elapsed [Duration]) so it can be unit-tested.
class SfxThrottle {
  SfxThrottle({this.minInterval = const Duration(milliseconds: 35)});

  final Duration minInterval;
  final Map<SfxCue, Duration> _lastPlayed = {};

  /// True (and records the trigger) when [cue] may fire at elapsed time
  /// [now]; false while within [minInterval] of that cue's last trigger.
  bool shouldPlay(SfxCue cue, Duration now) {
    final last = _lastPlayed[cue];
    if (last != null && now - last < minInterval) return false;
    _lastPlayed[cue] = now;
    return true;
  }
}
