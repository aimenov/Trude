/// Full-screen flight layer: flies card widgets between measured table rects
/// along quadratic Bezier arcs with spin, scale, and per-flight jitter.
///
/// One [Ticker] drives every active flight; the layer is an [IgnorePointer]
/// so it never eats input. Face-down flights are anonymous card backs — the
/// client never knows those cards' ids (synthetic seat+ordinal identity).
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../widgets/card_widgets.dart';
import 'motion_jitter.dart';
import 'motion_spec.dart';

class CardFlightSpec {
  CardFlightSpec({
    required this.from,
    required this.to,
    required this.duration,
    this.delay = Duration.zero,
    this.curve = MotionSpec.cardFlightCurve,
    this.width = 48,
    this.child,
    this.spinTurns = 0,
    double? endRotation,
    Offset? landingJitter,
    double? arcHeight,
    this.startScale = 1.0,
    this.endScale = 1.0,
    this.onLand,
  })  : endRotation = endRotation ?? motionJitter.endRotation(),
        landingJitter = landingJitter ?? motionJitter.landingOffset(),
        arcHeight = arcHeight ??
            motionJitter.arcHeight(max(
                MotionSpec.minArcHeight,
                (to.center - from.center).distance *
                    MotionSpec.arcHeightFactor));

  /// Global (screen) rects of departure and destination.
  final Rect from;
  final Rect to;
  final Duration delay;
  final Duration duration;
  final Curve curve;
  final double width;

  /// Defaults to a face-down card back.
  final Widget? child;

  final double spinTurns;
  final double endRotation;
  final Offset landingJitter;
  final double arcHeight;
  final double startScale;
  final double endScale;
  final VoidCallback? onLand;
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
    final layerOrigin =
        (box != null && box.attached) ? box.localToGlobal(Offset.zero) : Offset.zero;

    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          for (final f in widget.controller._flights)
            if (!f.landed) _buildFlight(f, layerOrigin),
        ],
      ),
    );
  }

  Widget _buildFlight(_ActiveFlight f, Offset layerOrigin) {
    final spec = f.spec;
    final raw = _progress(f);
    final t = spec.curve.transform(raw);

    final a = spec.from.center - layerOrigin;
    final b = spec.to.center + spec.landingJitter - layerOrigin;
    // Quadratic Bezier with the control point lifted above the midpoint.
    final control = Offset((a.dx + b.dx) / 2, min(a.dy, b.dy) - spec.arcHeight);
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
      child: Opacity(
        opacity: raw <= 0 ? 0 : 1, // invisible while waiting out the delay
        child: Transform.rotate(
          angle: rotation,
          child: Transform.scale(
            scale: scale,
            child: spec.child ?? TrudeCardBack(width: width),
          ),
        ),
      ),
    );
  }
}
