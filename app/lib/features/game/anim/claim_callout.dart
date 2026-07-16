/// Claim callout plaque: "THREE SEVENS!" as an engraved brass plaque slamming
/// down beside the thrower with a scale overshoot, holding, then fading.
/// Also reused for the "SAFE!" cheer (which arrives tinted, e.g. truth green).
library;

import 'package:flutter/material.dart';

import '../../../core/theme/trude_theme.dart';
import '../table_scale.dart';
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
    final tint = widget.color;

    // Brass plaque by default; a tinted solid plaque when a color is given
    // (e.g. truth-green for "SAFE!").
    final decoration = BoxDecoration(
      gradient: tint == null ? TrudeGradients.brass : null,
      color: tint,
      borderRadius: BorderRadius.circular(TrudeDims.chipRadius),
      border: Border.all(
          color: tint == null ? TrudeColors.brassDark : TrudeColors.midnight),
      boxShadow: [
        BoxShadow(
          color: TrudeColors.midnight.withValues(alpha: 0.55),
          blurRadius: 6,
          offset: const Offset(0, 3),
        ),
      ],
    );
    final textStyle = TrudeType.stamp.copyWith(
      color: tint == null ? TrudeColors.textOnBrass : TrudeColors.textPrimary,
      // Scaled with the center-table typography: 16 on phones, up to 24 on
      // large desktop windows.
      fontSize: 16 * tableScale(context),
      letterSpacing: 1.4,
      shadows: tint == null
          ? [
              Shadow(
                color: TrudeColors.brassBright.withValues(alpha: 0.55),
                offset: const Offset(0, 0.8),
              ),
            ]
          : null,
    );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        // Slam: the plaque drops from oversized onto the table with overshoot.
        final inT = t < _inEnd
            ? MotionSpec.calloutInCurve.transform(t / _inEnd)
            : 1.0;
        final scale = TableMotionSpec.calloutSlamScale +
            (1 - TableMotionSpec.calloutSlamScale) * inT;
        final opacity = t > _fadeStart
            ? 1 - (t - _fadeStart) / (1 - _fadeStart)
            : (t < _inEnd ? (t / _inEnd).clamp(0.0, 1.0) : 1.0);
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(scale: scale, child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: decoration,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            // Inner engraved hairline of the plaque.
            border: Border.all(
              color: (tint == null
                      ? TrudeColors.textOnBrass
                      : TrudeColors.midnight)
                  .withValues(alpha: 0.35),
              width: TrudeDims.hairlineWidth,
            ),
            borderRadius: BorderRadius.circular(TrudeDims.chipRadius - 4),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(widget.text, style: textStyle),
          ),
        ),
      ),
    );
  }
}
