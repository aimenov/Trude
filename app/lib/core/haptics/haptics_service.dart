/// Semantic haptics interface. Same contract as SfxService: every moment that
/// should buzz calls a semantic method here; all are no-ops until the mobile
/// milestone swaps in a plugin-backed implementation.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/settings_providers.dart';

final hapticsProvider = Provider<HapticsService>((ref) =>
    HapticsService(enabledOf: () => ref.read(settingsProvider).hapticsOn));

class HapticsService {
  HapticsService({bool Function()? enabledOf})
      : _enabledOf = enabledOf; // ignore: prefer_initializing_formals

  final bool Function()? _enabledOf;

  /// The user's haptics toggle. Real (plugin-backed) implementations inherit
  /// this gate: check it at the top of every buzz method.
  bool get enabled => _enabledOf?.call() ?? true;

  /// Subtle tick — card selection, a card landing.
  void light() {
    if (!enabled) return;
    // TODO(mobile): HapticFeedback.lightImpact or platform equivalent.
  }

  /// Medium thud — throw committed, pile pickup starts.
  void medium() {
    if (!enabled) return;
    // TODO(mobile): medium impact.
  }

  /// Heavy hit — verdict stamp, joker reveal.
  void heavy() {
    if (!enabled) return;
    // TODO(mobile): heavy impact.
  }

  /// Selection blip for toggles/choices.
  void selection() {
    if (!enabled) return;
    // TODO(mobile): selection click.
  }

  /// Slow double-pulse during the pre-flip pause of the reveal.
  void heartbeat() {
    if (!enabled) return;
    // TODO(mobile): custom heartbeat pattern (two soft pulses).
  }

  /// Positive pattern — four-of-a-kind, going out safe.
  void success() {
    if (!enabled) return;
    // TODO(mobile): success notification pattern.
  }

  /// Warning pattern — countdown entering the urgent window.
  void warning() {
    if (!enabled) return;
    // TODO(mobile): warning notification pattern.
  }
}
