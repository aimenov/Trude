/// Full-screen flight layer: cards are THROWN, not tweened.
///
/// Every flight picks one of two motion modes:
///
/// * [CardFlightMode.ballistic] (the default): the card launches with a real
///   velocity vector (dp/s) and angular velocity (rad/s). A critically-damped
///   spring — evaluated in closed form, so the path is deterministic and
///   skip/rebuild-safe — steers the launch toward a touchdown point at ~85%
///   of the path; its damping term plays the role of light aerodynamic drag.
///   While airborne the card scales up toward the apex and casts a softer,
///   offset shadow; on touchdown it squashes (scaleY ~0.96 for a frame or
///   two) and slides the last stretch with friction into the EXACT target
///   pose. Landing exactness and the step schedule are never sacrificed:
///   the slide is analytic to the target and every flight ends exactly at
///   its (hard-capped) duration.
/// * [CardFlightMode.bezier]: the legacy quadratic-arc tween, kept for
///   choreography that reads better on rails.
///
/// Launch velocities come from three places: an explicit
/// [CardFlightSpec.launchVelocity]; the [FlickLaunch] channel (my own flick
/// gesture — the animation launches with the exact release velocity); or a
/// synthesis from the thrower's seat direction with [MotionJitter] variance,
/// so no two throws ever look identical.
///
/// Touchdowns are broadcast on [CardLandings] so resting widgets (the pile)
/// can react with a physical nudge.
///
/// One [Ticker] drives every active flight; the layer is an [IgnorePointer]
/// so it never eats input. Face-down flights are anonymous card backs — the
/// client never knows those cards' ids (synthetic seat+ordinal identity).
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/trude_theme.dart';
import '../widgets/card_widgets.dart';
import 'motion_jitter.dart';
import 'motion_spec.dart';

/// How a [CardFlightSpec] travels: physically launched or on bezier rails.
enum CardFlightMode { ballistic, bezier }

/// A completed touchdown, broadcast so resting widgets can react (the pile
/// nudges its top cards when a thrown card lands on it).
class CardLanding {
  const CardLanding({
    required this.position,
    required this.direction,
    required this.speed,
  });

  /// Global (screen) landing point.
  final Offset position;

  /// Normalized approach direction of the slide into the pose.
  final Offset direction;

  /// Approximate approach speed, dp/s.
  final double speed;
}

/// App-wide touchdown bus. A fresh [CardLanding] instance per landing, so
/// listeners fire even for identical poses.
class CardLandings {
  CardLandings._();

  static final CardLandings instance = CardLandings._();

  final ValueNotifier<CardLanding?> last = ValueNotifier(null);

  void report(CardLanding landing) => last.value = landing;
}

/// One-shot channel handing a flick-release velocity from the hand gesture
/// to the flight layer, so the launch velocity of my throw IS the flick
/// velocity. MyHandView publishes on release; the next ballistic flights
/// departing from the publishing rect consume it (each card of the same
/// throw shares the flick and adds its own jitter). Entries expire after
/// [MotionSpec.flickHandoffWindow] — no table_screen wiring required.
class FlickLaunch {
  FlickLaunch._();

  static Offset? _velocity;
  static Rect? _source;
  static DateTime? _publishedAt;

  static void publish({required Offset velocity, required Rect source}) {
    _velocity = velocity;
    _source = source;
    _publishedAt = DateTime.now();
  }

  static void clear() {
    _velocity = null;
    _source = null;
    _publishedAt = null;
  }

  /// The pending flick velocity if it is fresh and [from] overlaps the hand
  /// rect that published it; null otherwise. Not consumed on read — several
  /// cards of one throw all share it, and the entry expires by TTL.
  static Offset? peek(Rect from) {
    final at = _publishedAt;
    if (at == null) return null;
    if (DateTime.now().difference(at) > MotionSpec.flickHandoffWindow) {
      clear();
      return null;
    }
    final source = _source;
    if (source == null ||
        !source.inflate(MotionSpec.flickSourceSlop).overlaps(from)) {
      return null;
    }
    return _velocity;
  }
}

Offset _norm(Offset v) {
  final d = v.distance;
  return d < 1e-3 ? const Offset(0, -1) : v / d;
}

Offset _rotate(Offset v, double rad) {
  final c = cos(rad);
  final s = sin(rad);
  return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
}

class CardFlightSpec {
  CardFlightSpec({
    required this.from,
    required this.to,
    required Duration duration,
    this.delay = Duration.zero,
    this.curve = MotionSpec.cardFlightCurve,
    this.width = 48,
    this.child,
    this.spinTurns = 0,
    this.mode = CardFlightMode.ballistic,
    double? endRotation,
    Offset? landingJitter,
    double? arcHeight,
    Offset? launchVelocity,
    double? launchSpin,
    this.startScale = 1.0,
    this.endScale = 1.0,
    this.onLand,
  })  : duration = duration > MotionSpec.ballisticFlightCap
            ? MotionSpec.ballisticFlightCap
            : duration,
        endRotation = endRotation ?? motionJitter.endRotation(),
        landingJitter = landingJitter ?? motionJitter.landingOffset(),
        arcHeight = arcHeight ??
            motionJitter.arcHeight(max(
                MotionSpec.minArcHeight,
                (to.center - from.center).distance *
                    MotionSpec.arcHeightFactor)),
        launchVelocity = launchVelocity ?? _launchFor(from, to, duration),
        launchSpin = launchSpin ?? _spinFor(spinTurns, duration);

  /// Global (screen) rects of departure and destination.
  final Rect from;
  final Rect to;
  final Duration delay;

  /// Hard-capped at [MotionSpec.ballisticFlightCap] so a flight can never
  /// outlive its queue step by much.
  final Duration duration;

  /// Bezier mode only; ballistic flights are shaped by physics.
  final Curve curve;
  final double width;

  /// Defaults to a face-down card back.
  final Widget? child;

  final double spinTurns;
  final CardFlightMode mode;
  final double endRotation;
  final Offset landingJitter;
  final double arcHeight;

  /// Ballistic launch velocity, dp/s. Defaults to the pending [FlickLaunch]
  /// (when departing from its rect) or a jittered synthesis along from→to.
  final Offset launchVelocity;

  /// Ballistic angular velocity, rad/s (synthesized from [spinTurns]).
  final double launchSpin;

  final double startScale;
  final double endScale;
  final VoidCallback? onLand;

  static Offset _launchFor(Rect from, Rect to, Duration duration) {
    final seconds = max(duration.inMicroseconds, 1000) / 1e6;
    final flick = FlickLaunch.peek(from);
    if (flick != null) {
      // My flick: the launch IS the release velocity, fanned per card.
      final aimed = _rotate(
          flick, motionJitter.signed(MotionSpec.flickSpreadDeg) * pi / 180);
      return aimed * motionJitter.vary(1.0, MotionSpec.ballisticSpeedJitter);
    }
    // Opponent / auto throw: synthesize from the thrower seat direction
    // (from → to) with loft and MotionJitter variance.
    final line = to.center - from.center;
    final dir = _norm(line);
    final aim = _rotate(
        _norm(Offset(dir.dx, dir.dy - MotionSpec.ballisticLoft)),
        motionJitter.signed(MotionSpec.ballisticAimJitterDeg) * pi / 180);
    final speed = motionJitter.vary(
        line.distance / seconds * MotionSpec.ballisticLaunchBoost,
        MotionSpec.ballisticSpeedJitter);
    return aim * speed;
  }

  static double _spinFor(double spinTurns, Duration duration) {
    final seconds = max(duration.inMicroseconds, 1000) / 1e6;
    if (spinTurns == 0) {
      return motionJitter.signed(MotionSpec.ballisticIdleSpin) / seconds;
    }
    return motionJitter.vary(
        spinTurns * 2 * pi / seconds, MotionSpec.ballisticSpinJitter);
  }
}

class CardFlightController extends ChangeNotifier {
  final List<_ActiveFlight> _flights = [];
  int _epoch = 0;

  bool get hasFlights => _flights.isNotEmpty;

  void fly(Iterable<CardFlightSpec> specs) {
    _flights.addAll(specs.map(_ActiveFlight.new));
    notifyListeners();
  }

  /// Drops every in-flight card instantly (queue skip).
  void clear() {
    _flights.clear();
    _epoch++;
    notifyListeners();
  }
}

class CardFlightLayer extends StatefulWidget {
  const CardFlightLayer({super.key, required this.controller});

  final CardFlightController controller;

  @override
  State<CardFlightLayer> createState() => _CardFlightLayerState();
}

class _ActiveFlight {
  _ActiveFlight(this.spec);

  final CardFlightSpec spec;

  /// The flight's card widget, built once per flight: an identical instance
  /// across frames lets Element.update short-circuit, so per-frame work is
  /// only the Positioned/Transform churn around it.
  late final Widget card = spec.child ?? TrudeCardBack(width: spec.width);

  /// Elapsed ticker time when this flight was admitted; set by the layer.
  Duration? start;
  bool landed = false;
}

class _CardFlightLayerState extends State<CardFlightLayer>
    with SingleTickerProviderStateMixin {
  // Created in initState: lazy init would run createTicker (an ancestor
  // lookup) during dispose when no flight ever started.
  late final Ticker _ticker;
  Duration _elapsed = Duration.zero;
  int _seenEpoch = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _ticker.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (widget.controller._epoch != _seenEpoch) {
      // clear(): stop everything.
      _seenEpoch = widget.controller._epoch;
      if (_ticker.isActive) _ticker.stop();
      _elapsed = Duration.zero;
      if (mounted) setState(() {});
      return;
    }
    if (widget.controller.hasFlights && !_ticker.isActive) {
      _elapsed = Duration.zero;
      _ticker.start();
    }
    if (mounted) setState(() {});
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed;
    final flights = widget.controller._flights;
    for (final f in flights) {
      f.start ??= elapsed;
      if (!f.landed && _progress(f) >= 1.0) {
        f.landed = true;
        _reportLanding(f.spec);
        f.spec.onLand?.call();
      }
    }
    flights.removeWhere((f) => f.landed);
    if (flights.isEmpty) {
      _ticker.stop();
      _elapsed = Duration.zero;
    }
    setState(() {});
  }

  void _reportLanding(CardFlightSpec spec) {
    final a = spec.from.center;
    final b = spec.to.center + spec.landingJitter;
    final seconds = max(spec.duration.inMicroseconds, 1000) / 1e6;
    CardLandings.instance.report(CardLanding(
      position: b,
      direction: _norm(b - a),
      speed: min(MotionSpec.flickLaunchSpeedMax, (b - a).distance / seconds),
    ));
  }

  double _progress(_ActiveFlight f) {
    final start = f.start;
    if (start == null) return 0;
    final since = _elapsed - start - f.spec.delay;
    if (since <= Duration.zero) return 0;
    return min(1.0, since.inMicroseconds / f.spec.duration.inMicroseconds);
  }

  @override
  Widget build(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    final layerOrigin = (box != null && box.attached)
        ? box.localToGlobal(Offset.zero)
        : Offset.zero;

    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          // Flights still waiting out their delay (progress 0) are skipped
          // entirely — cheaper than building them transparent.
          for (final f in widget.controller._flights)
            if (!f.landed && _progress(f) > 0) _buildFlight(f, layerOrigin),
        ],
      ),
    );
  }

  Widget _buildFlight(_ActiveFlight f, Offset layerOrigin) {
    final spec = f.spec;
    final raw = _progress(f);
    final a = spec.from.center - layerOrigin;
    final b = spec.to.center + spec.landingJitter - layerOrigin;
    return switch (spec.mode) {
      CardFlightMode.bezier => _buildBezier(f, raw, a, b),
      CardFlightMode.ballistic => _buildBallistic(f, raw, a, b),
    };
  }

  Widget _buildBezier(_ActiveFlight f, double raw, Offset a, Offset b) {
    final spec = f.spec;
    final t = spec.curve.transform(raw);

    // Quadratic Bezier with the control point lifted above the midpoint.
    final control =
        Offset((a.dx + b.dx) / 2, min(a.dy, b.dy) - spec.arcHeight);
    final u = 1 - t;
    final pos = a * (u * u) + control * (2 * u * t) + b * (t * t);

    final rotation = spec.spinTurns * 2 * pi * t + spec.endRotation * t;
    final scale = spec.startScale + (spec.endScale - spec.startScale) * t;
    final width = spec.width;
    final height = width * kCardAspect;

    return Positioned(
      left: pos.dx - width / 2,
      top: pos.dy - height / 2,
      width: width,
      height: height,
      child: Transform.rotate(
        angle: rotation,
        child: Transform.scale(
          scale: scale,
          child: f.card,
        ),
      ),
    );
  }

  Widget _buildBallistic(_ActiveFlight f, double raw, Offset a, Offset b) {
    final spec = f.spec;
    final pose = _ballisticPose(spec, raw, a, b);
    final width = spec.width;
    final height = width * kCardAspect;
    final card = f.card;

    return Positioned(
      left: pose.position.dx - width / 2,
      top: pose.position.dy - height / 2,
      width: width,
      height: height,
      child: Transform.rotate(
        angle: pose.angle,
        child: Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(
              pose.scale, pose.scale * pose.squashY, 1),
          child: pose.air > 0.02
              ? Stack(
                  clipBehavior: Clip.none,
                  fit: StackFit.expand,
                  children: [
                    // Softened, offset shadow that grows with height.
                    Transform.translate(
                      offset: Offset(MotionSpec.ballisticShadowDropX,
                              MotionSpec.ballisticShadowDropY) *
                          pose.air,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(
                              width * TrudeDims.cardRadiusFactor),
                          boxShadow: [
                            BoxShadow(
                              color: TrudeColors.midnight.withValues(
                                  alpha: MotionSpec.ballisticShadowAlpha *
                                      pose.air),
                              blurRadius: MotionSpec
                                      .ballisticShadowBlurGround +
                                  (MotionSpec.ballisticShadowBlurAir -
                                          MotionSpec
                                              .ballisticShadowBlurGround) *
                                      pose.air,
                            ),
                          ],
                        ),
                      ),
                    ),
                    card,
                  ],
                )
              : card,
        ),
      ),
    );
  }
}

/// The full ballistic pose at [raw] (0..1) of the flight — pure closed-form
/// math, no per-frame integration state, so it is deterministic under frame
/// drops, rebuilds, and skips, and lands EXACTLY on the target pose at 1.
({Offset position, double angle, double scale, double squashY, double air})
    _ballisticPose(CardFlightSpec spec, double raw, Offset a, Offset b) {
  final seconds = max(spec.duration.inMicroseconds, 1000) / 1e6;
  const touchAt = MotionSpec.ballisticTouchdownAt;
  final airTime = seconds * touchAt;
  final omega = MotionSpec.ballisticSpringOmega / airTime;

  // The spring steers toward the touchdown point at ~85% of the line; the
  // residual (a few dp, direction-dependent) becomes part of the slide.
  final touch = Offset.lerp(a, b, touchAt)!;
  final d0 = a - touch;
  final c1 = spec.launchVelocity + d0 * omega;

  // Critically damped spring, closed form: x(t) = e^{-wt}(x0 + (v0 + w*x0)t).
  Offset positionAt(double t) => touch + (d0 + c1 * t) * exp(-omega * t);
  double angleAt(double t) {
    final e = spec.endRotation;
    return e + (-e + (spec.launchSpin - omega * e) * t) * exp(-omega * t);
  }

  final t = raw * seconds;
  Offset position;
  double angle;
  if (raw <= touchAt) {
    position = positionAt(t);
    angle = angleAt(t);
  } else {
    // Friction slide: decelerate the last stretch into the exact pose.
    final sigma = ((raw - touchAt) / (1 - touchAt)).clamp(0.0, 1.0);
    final s = MotionSpec.ballisticSlideCurve.transform(sigma);
    final touchPos = positionAt(airTime);
    final touchAngle = angleAt(airTime);
    position = Offset.lerp(touchPos, b, s)!;
    angle = touchAngle + (spec.endRotation - touchAngle) * s;
  }

  // Height illusion: apex scale-up + shadow ramp, back to 0 at touchdown.
  final air = raw >= touchAt ? 0.0 : sin(pi * (raw / touchAt));
  final base = spec.startScale + (spec.endScale - spec.startScale) * raw;
  final scale = base * (1 + MotionSpec.ballisticApexScale * air);

  // Touchdown squash: a brief scaleY dip that sells the card's weight.
  var squashY = 1.0;
  final q = (raw - touchAt) / MotionSpec.ballisticSquashSpan;
  if (q > 0 && q < 1) {
    squashY = 1 - (1 - MotionSpec.ballisticSquashScaleY) * sin(pi * q);
  }

  return (
    position: position,
    angle: angle,
    scale: scale,
    squashY: squashY,
    air: air,
  );
}
