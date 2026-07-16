/// Small sampled randomness applied to every motion so no two throws, deals,
/// or pickups ever look identical. One shared instance is used by all
/// animators; tests may inject a seeded [Random].
library;

import 'dart:math';
import 'dart:ui';

/// The app-wide jitter source.
final MotionJitter motionJitter = MotionJitter();

class MotionJitter {
  MotionJitter([Random? random]) : _rng = random ?? Random();

  final Random _rng;

  static const _durationSpread = 0.08; // +-8 %
  static const _arcSpread = 0.15; // +-15 %
  static const _rotationSpreadDeg = 6.0; // +-6 degrees
  static const _landingSpread = 10.0; // +-10 dp

  /// Uniform sample in [-1, 1].
  double _signed() => _rng.nextDouble() * 2 - 1;

  /// [base] +- 8 %.
  Duration duration(Duration base) => Duration(
      microseconds:
          (base.inMicroseconds * (1 + _signed() * _durationSpread)).round());

  /// [base] +- 15 %.
  double arcHeight(double base) => base * (1 + _signed() * _arcSpread);

  /// [baseDeg] +- 6 degrees, in radians.
  double endRotation([double baseDeg = 0]) =>
      (baseDeg + _signed() * _rotationSpreadDeg) * pi / 180;

  /// Random landing offset within +-10 dp on both axes.
  Offset landingOffset() =>
      Offset(_signed() * _landingSpread, _signed() * _landingSpread);

  /// Uniform sample in [min, max] — used for phases/velocities of idle life
  /// and particle bursts.
  double range(double min, double max) => min + _rng.nextDouble() * (max - min);

  int intRange(int min, int maxInclusive) =>
      min + _rng.nextInt(maxInclusive - min + 1);
}
