/// Semantic sound-effect interface. Every game-feel beat calls one of these
/// methods; each forwards its [SfxCue] to the pluggable [SfxBackend]
/// (audioplayers in the app, a recording fake in tests, [NoopSfxBackend] by
/// default).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/settings_providers.dart';
import 'sfx_backend.dart';
import 'sfx_backend_players.dart';

final sfxProvider = Provider<SfxService>((ref) {
  final backend = PlayersSfxBackend();
  // Fire-and-forget: warmUp never throws (degrades silently without plugin
  // channels) and the first taps land well after startup anyway.
  unawaited(backend.warmUp());
  ref.onDispose(() => unawaited(backend.dispose()));
  return SfxService(
    enabledOf: () => ref.read(settingsProvider).soundOn,
    backend: backend,
  );
});

class SfxService {
  SfxService({bool Function()? enabledOf, SfxBackend? backend})
      : _enabledOf = enabledOf, // ignore: prefer_initializing_formals
        _backend = backend ?? const NoopSfxBackend();

  final bool Function()? _enabledOf;
  final SfxBackend _backend;

  /// The user's sound toggle. Checked at the top of every play method; the
  /// backend is never touched while disabled.
  bool get enabled => _enabledOf?.call() ?? true;

  /// Deck riffle at the start of the deal set piece.
  void shuffle() {
    if (!enabled) return;
    _backend.play(SfxCue.shuffle);
  }

  /// One card leaving a hand/seat (deal spray, throw).
  void cardThrow() {
    if (!enabled) return;
    _backend.play(SfxCue.cardThrow);
  }

  /// One card landing on the pile / in a hand.
  void cardLand() {
    if (!enabled) return;
    _backend.play(SfxCue.cardLand);
  }

  /// Claim callout bubble stamping in ("THREE SEVENS!").
  void claimStamp() {
    if (!enabled) return;
    _backend.play(SfxCue.claimStamp);
  }

  /// Reveal set piece: tension bed as the table dims.
  void revealTension() {
    if (!enabled) return;
    _backend.play(SfxCue.revealTension);
  }

  /// Reveal set piece: the throw's cards sliding apart center-stage.
  void cardSlide() {
    if (!enabled) return;
    _backend.play(SfxCue.cardSlide);
  }

  /// The chosen card snapping through its Y-flip.
  void flipSnap() {
    if (!enabled) return;
    _backend.play(SfxCue.flipSnap);
  }

  /// Verdict stamp: the claim was true.
  void verdictTruth() {
    if (!enabled) return;
    _backend.play(SfxCue.verdictTruth);
  }

  /// Verdict stamp: caught lying.
  void verdictLie() {
    if (!enabled) return;
    _backend.play(SfxCue.verdictLie);
  }

  /// Pile swarming to the loser's seat.
  void pilePickup() {
    if (!enabled) return;
    _backend.play(SfxCue.pilePickup);
  }

  /// Four-of-a-kind golden celebration.
  void quadFanfare() {
    if (!enabled) return;
    _backend.play(SfxCue.quadFanfare);
  }

  /// Game over: the joker turns up.
  void jokerReveal() {
    if (!enabled) return;
    _backend.play(SfxCue.jokerReveal);
  }

  /// It became my turn.
  void yourTurn() {
    if (!enabled) return;
    _backend.play(SfxCue.yourTurn);
  }

  /// Countdown entered the urgent (last 5 s) window.
  void timerUrgent() {
    if (!enabled) return;
    _backend.play(SfxCue.timerUrgent);
  }

  /// An emoji reaction burst fired.
  void reactionPop() {
    if (!enabled) return;
    _backend.play(SfxCue.reactionPop);
  }

  /// A parlor button / hand card was pressed.
  void uiTap() {
    if (!enabled) return;
    _backend.play(SfxCue.uiTap);
  }
}
