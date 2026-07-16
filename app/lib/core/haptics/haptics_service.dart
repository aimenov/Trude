/// Semantic haptics interface. Same contract as SfxService: every moment that
/// should buzz calls a semantic method here; each forwards to the pluggable
/// [HapticsPrimitives] layer (SDK `HapticFeedback` + the `vibration` plugin in
/// the app, a recording fake in tests).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vibration/vibration.dart';

import '../storage/settings_providers.dart';

final hapticsProvider = Provider<HapticsService>((ref) =>
    HapticsService(enabledOf: () => ref.read(settingsProvider).hapticsOn));

/// Low-level haptic primitives — the seam between [HapticsService]'s semantic
/// vocabulary and the platform. The default [RealHapticsPrimitives] talks to
/// the SDK and the `vibration` plugin; tests inject a recording fake.
abstract class HapticsPrimitives {
  const HapticsPrimitives();

  void lightImpact();
  void mediumImpact();
  void heavyImpact();
  void selectionClick();
  void successNotification();
  void warningNotification();

  /// Whether the device can play a timed, amplitude-shaped vibration pattern.
  /// Probed once (lazily) by [HapticsService.heartbeat]; must never throw.
  Future<bool> canVibratePattern();

  /// Play a wait/vibrate [pattern] (ms) with per-segment [intensities]
  /// (0-255). Only called after [canVibratePattern] returned true; must
  /// swallow its own platform errors.
  Future<void> vibratePattern(List<int> pattern, List<int> intensities);
}

/// Production primitives: the six discrete effects map straight onto the
/// flutter/services [HapticFeedback] statics (which silently no-op on web and
/// in VM tests); patterns go through the `vibration` plugin.
class RealHapticsPrimitives extends HapticsPrimitives {
  const RealHapticsPrimitives();

  @override
  void lightImpact() => unawaited(HapticFeedback.lightImpact());
  @override
  void mediumImpact() => unawaited(HapticFeedback.mediumImpact());
  @override
  void heavyImpact() => unawaited(HapticFeedback.heavyImpact());
  @override
  void selectionClick() => unawaited(HapticFeedback.selectionClick());
  @override
  void successNotification() => unawaited(HapticFeedback.successNotification());
  @override
  void warningNotification() => unawaited(HapticFeedback.warningNotification());

  @override
  Future<bool> canVibratePattern() async {
    // The plugin ships a web endpoint (navigator.vibrate) but desktop browsers
    // ignore it — skip the plugin entirely on web and use the SDK fallback.
    if (kIsWeb) return false;
    try {
      // On non-mobile VMs (Windows dev box, `flutter test`) hasVibrator()
      // returns false without touching a platform channel;
      // hasCustomVibrationsSupport() catches its own MissingPluginException.
      // The try/catch is belt-and-braces for other plugin failure modes.
      return await Vibration.hasVibrator() &&
          await Vibration.hasCustomVibrationsSupport();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> vibratePattern(List<int> pattern, List<int> intensities) async {
    try {
      await Vibration.vibrate(pattern: pattern, intensities: intensities);
    } catch (_) {
      // Missing channel / platform error: haptics degrade silently.
    }
  }
}

class HapticsService {
  HapticsService({bool Function()? enabledOf, HapticsPrimitives? primitives})
      : _enabledOf = enabledOf, // ignore: prefer_initializing_formals
        _primitives = primitives ?? const RealHapticsPrimitives();

  final bool Function()? _enabledOf;
  final HapticsPrimitives _primitives;

  /// Lazily-probed pattern capability, cached for the service's lifetime.
  Future<bool>? _patternCapable;

  /// Heartbeat: two beats — a firmer thump then a softer echo.
  /// wait 0ms, buzz 60ms @160/255, wait 90ms, buzz 90ms @96/255.
  static const List<int> _heartbeatPattern = [0, 60, 90, 90];
  static const List<int> _heartbeatIntensities = [0, 160, 0, 96];

  /// Gap between the two SDK pulses of the fallback heartbeat.
  static const Duration _heartbeatFallbackGap = Duration(milliseconds: 140);

  /// The user's haptics toggle. Checked at the top of every buzz method; the
  /// primitives layer is never touched while disabled.
  bool get enabled => _enabledOf?.call() ?? true;

  /// Subtle tick — card selection, a card landing.
  void light() {
    if (!enabled) return;
    _primitives.lightImpact();
  }

  /// Medium thud — throw committed, pile pickup starts.
  void medium() {
    if (!enabled) return;
    _primitives.mediumImpact();
  }

  /// Heavy hit — verdict stamp, joker reveal.
  void heavy() {
    if (!enabled) return;
    _primitives.heavyImpact();
  }

  /// Selection blip for toggles/choices.
  void selection() {
    if (!enabled) return;
    _primitives.selectionClick();
  }

  /// Slow double-pulse during the pre-flip pause of the reveal.
  void heartbeat() {
    if (!enabled) return;
    unawaited(_heartbeat());
  }

  Future<void> _heartbeat() async {
    var capable = false;
    try {
      capable = await (_patternCapable ??= _primitives.canVibratePattern());
    } catch (_) {
      _patternCapable = Future.value(false);
    }
    if (capable) {
      try {
        await _primitives.vibratePattern(
            _heartbeatPattern, _heartbeatIntensities);
        return;
      } catch (_) {
        // Pattern path broke after a positive probe: don't retry it.
        _patternCapable = Future.value(false);
      }
    }
    // Fallback: approximate the two beats with SDK impacts.
    _primitives.mediumImpact();
    await Future<void>.delayed(_heartbeatFallbackGap);
    _primitives.lightImpact();
  }

  /// Positive pattern — four-of-a-kind, going out safe.
  void success() {
    if (!enabled) return;
    _primitives.successNotification();
  }

  /// Warning pattern — countdown entering the urgent window.
  void warning() {
    if (!enabled) return;
    _primitives.warningNotification();
  }
}
