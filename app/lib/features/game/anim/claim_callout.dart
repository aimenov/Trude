/// Claim callout bubble: "THREE SEVENS!" stamping in from the thrower with a
/// scale overshoot, holding, then fading. Also reused for the "SAFE!" cheer.
library;

import 'package:flutter/material.dart';

import 'motion_spec.dart';

class ClaimCallout extends StatefulWidget {
  const ClaimCallout({
    super.key,
    required this.text,
    required this.speedFactor,
    this.color,
    this.onDone,
  });

  final String text;

  /// Current animation-speed factor; the callout is never shown at 0.
  final double speedFactor;
  final Color? color;
  final VoidCallback? onDone;

  @override
  State<ClaimCallout> createState() => _ClaimCalloutState();
}

class _ClaimCalloutState extends State<ClaimCallout>
    with SingleTickerProviderStateMixin {
  static final _baseTotal =
      MotionSpec.calloutIn + MotionSpec.calloutHold + MotionSpec.calloutFade;

  // Phase boundaries as fractions of the total — speed scaling preserves them.
  static final _inEnd =
      MotionSpec.calloutIn.inMilliseconds / _baseTotal.inMilliseconds;
  static final _fadeStart =
      1 - MotionSpec.calloutFade.inMilliseconds / _baseTotal.inMilliseconds;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final totalMs =
        (_baseTotal.inMilliseconds * widget.speedFactor).round().clamp(1, 1 << 30);
    _controller = AnimationController(
        vsync: this, duration: Duration(milliseconds: totalMs))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) widget.onDone?.call();
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.color ?? scheme.inverseSurface;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final scale = t < _inEnd
            ? MotionSpec.calloutInCurve.transform(t / _inEnd)
            : 1.0;
        final opacity = t > _fadeStart
            ? 1 - (t - _fadeStart) / (1 - _fadeStart)
            : 1.0;
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          widget.text,
          style: TextStyle(
            color: scheme.onInverseSurface,
            fontWeight: FontWeight.w900,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}
