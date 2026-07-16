/// Semantic sound-effect interface. Every game-feel beat calls one of these
/// methods; each is a deliberate no-op until the mobile milestone swaps in a
/// real implementation (a plugin-backed player). Keeping the call sites in
/// place now means audio lands by replacing this one class.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/settings_providers.dart';

final sfxProvider = Provider<SfxService>((ref) =>
    SfxService(enabledOf: () => ref.read(settingsProvider).soundOn));

class SfxService {
  SfxService({bool Function()? enabledOf})
      : _enabledOf = enabledOf; // ignore: prefer_initializing_formals

  final bool Function()? _enabledOf;

  /// The user's sound toggle. Real (plugin-backed) implementations inherit
  /// this gate: check it at the top of every play method.
  bool get enabled => _enabledOf?.call() ?? true;

  /// Deck riffle at the start of the deal set piece.
  void shuffle() {
    if (!enabled) return;
    // TODO(mobile): play deck shuffle/riffle sample.
  }

  /// One card leaving a hand/seat (deal spray, throw).
  void cardThrow() {
    if (!enabled) return;
    // TODO(mobile): play short card whoosh sample.
  }

  /// One card landing on the pile / in a hand.
  void cardLand() {
    if (!enabled) return;
    // TODO(mobile): play soft card-on-felt tap sample.
  }

  /// Claim callout bubble stamping in ("THREE SEVENS!").
  void claimStamp() {
    if (!enabled) return;
    // TODO(mobile): play rubber-stamp thud sample.
  }

  /// Reveal set piece: tension bed as the table dims.
  void revealTension() {
    if (!enabled) return;
    // TODO(mobile): play low tension drone/drumroll sample.
  }

  /// Reveal set piece: the throw's cards sliding apart center-stage.
  void cardSlide() {
    if (!enabled) return;
    // TODO(mobile): play card-slide-on-felt sample.
  }

  /// The chosen card snapping through its Y-flip.
  void flipSnap() {
    if (!enabled) return;
    // TODO(mobile): play crisp card-flip snap sample.
  }

  /// Verdict stamp: the claim was true.
  void verdictTruth() {
    if (!enabled) return;
    // TODO(mobile): play cold/clean confirmation hit sample.
  }

  /// Verdict stamp: caught lying.
  void verdictLie() {
    if (!enabled) return;
    // TODO(mobile): play harsh brass/impact hit sample.
  }

  /// Pile swarming to the loser's seat.
  void pilePickup() {
    if (!enabled) return;
    // TODO(mobile): play multi-card sweep sample.
  }

  /// Four-of-a-kind golden celebration.
  void quadFanfare() {
    if (!enabled) return;
    // TODO(mobile): play short golden fanfare sample.
  }

  /// Game over: the joker turns up.
  void jokerReveal() {
    if (!enabled) return;
    // TODO(mobile): play ominous sting sample.
  }

  /// It became my turn.
  void yourTurn() {
    if (!enabled) return;
    // TODO(mobile): play gentle attention chime sample.
  }

  /// Countdown entered the urgent (last 5 s) window.
  void timerUrgent() {
    if (!enabled) return;
    // TODO(mobile): play accelerating tick/heartbeat sample.
  }

  /// An emoji reaction burst fired.
  void reactionPop() {
    if (!enabled) return;
    // TODO(mobile): play bubbly pop sample.
  }
}
