/// Global animation-speed setting: every animated duration in the app is
/// multiplied through [AnimationSpeed.factor]. `off` collapses everything to
/// zero (instant), which is also forced when the platform requests reduced
/// motion ([MediaQuery.disableAnimations]).
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/settings_providers.dart';

enum AnimationSpeed {
  normal(1.0),
  fast(0.6),
  off(0.0);

  const AnimationSpeed(this.factor);

  final double factor;

  bool get isOff => factor == 0.0;

  /// Scales [base] by this speed. `off` returns [Duration.zero].
  Duration scale(Duration base) =>
      Duration(microseconds: (base.inMicroseconds * factor).round());
}

/// The user's animation-speed preference, persisted via the settings store
/// and editable from the Settings screen.
final animationSpeedChoiceProvider =
    NotifierProvider<AnimationSpeedChoice, AnimationSpeed>(
        AnimationSpeedChoice.new);

class AnimationSpeedChoice extends Notifier<AnimationSpeed> {
  @override
  AnimationSpeed build() {
    final name =
        ref.watch(settingsProvider.select((s) => s.animationSpeed));
    return AnimationSpeed.values.asNameMap()[name] ?? AnimationSpeed.normal;
  }

  void set(AnimationSpeed speed) =>
      ref.read(settingsProvider.notifier).setAnimationSpeed(speed.name);
}

/// Whether the platform asked for reduced motion; synced from
/// [MediaQuery.disableAnimations] by [ReduceMotionSync].
final platformReduceMotionProvider =
    NotifierProvider<PlatformReduceMotion, bool>(PlatformReduceMotion.new);

class PlatformReduceMotion extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

/// The speed every animator actually uses: the user's choice, forced to
/// `off` when the platform disables animations.
final animationSpeedProvider = Provider<AnimationSpeed>((ref) {
  if (ref.watch(platformReduceMotionProvider)) return AnimationSpeed.off;
  return ref.watch(animationSpeedChoiceProvider);
});

/// Invisible widget that mirrors [MediaQuery.disableAnimations] into
/// [platformReduceMotionProvider]. Mounted once in the app builder.
class ReduceMotionSync extends ConsumerWidget {
  const ReduceMotionSync({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disable = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (ref.read(platformReduceMotionProvider) != disable) {
      // Providers must not be written during build; defer one microtask.
      scheduleMicrotask(() {
        ref.read(platformReduceMotionProvider.notifier).set(disable);
      });
    }
    return child;
  }
}
