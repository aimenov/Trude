/// Game-over set piece: a tragicomic theater bow. A spotlight iris closes on
/// the joker as it rises from the loser's seat and flips face-up; the card
/// then tilts forward into a little bow under the serif title "THE JOKER
/// STAYS WITH ..." — navigation to /results waits for this step to finish
/// (or be tapped through).
library;

import 'dart:math';

import 'package:flutter/material.dart' hide Card;

import '../../../core/net/protocol_models.dart';
import '../../../core/strings.dart';
import '../../../core/theme/trude_theme.dart';
import '../widgets/card_widgets.dart';
import 'motion_spec.dart';

class GameOverOverlay extends StatefulWidget {
  const GameOverOverlay({
    super.key,
    required this.event,
    required this.loserName,
    required this.duration,
    required this.fromRect,
    this.onDone,
  });

  final GameOverEvent event;
  final String loserName;
  final Duration duration;

  /// Global rect of the loser's seat (the joker rises from it).
  final Rect? fromRect;
  final VoidCallback? onDone;

  @override
  State<GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<GameOverOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
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
    const cardWidth = 76.0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final travel = MotionSpec.gameOverZoomCurve
            .transform((t / MotionSpec.gameOverFlipEnd).clamp(0.0, 1.0));
        final flip = const SlowPeelCurve()
            .transform((t / MotionSpec.gameOverFlipEnd).clamp(0.0, 1.0));
        // Slow zoom continues for the rest of the sequence.
        final zoom = 1 +
            0.35 *
                ((t - MotionSpec.gameOverFlipEnd) /
                        (1 - MotionSpec.gameOverFlipEnd))
                    .clamp(0.0, 1.0);
        final bannerIn = Curves.easeOutBack.transform(
            ((t - MotionSpec.gameOverFlipEnd) / 0.18).clamp(0.0, 1.0));

        // The bow: dip forward, then rise back to a lingering slight tilt.
        final bowT = Curves.easeInOutCubic.transform(
            ((t - TableMotionSpec.gameOverBowStart) /
                    (TableMotionSpec.gameOverBowEnd -
                        TableMotionSpec.gameOverBowStart))
                .clamp(0.0, 1.0));
        final dip = sin(bowT * pi);
        final bowAngle = -TableMotionSpec.gameOverBowRest * bowT -
            (TableMotionSpec.gameOverBowDip -
                    TableMotionSpec.gameOverBowRest) *
                dip;
        final bowDy = 10.0 * dip;

        final box = context.findRenderObject() as RenderBox?;
        final size = box?.size ?? MediaQuery.sizeOf(context);
        final layerOrigin = (box != null && box.attached)
            ? box.localToGlobal(Offset.zero)
            : Offset.zero;
        final center = Offset(size.width / 2, size.height / 2 - 30);
        final from =
            (widget.fromRect?.center ?? center + const Offset(0, 180)) -
                layerOrigin;
        final pos = Offset.lerp(from, center, travel)! + Offset(0, bowDy);

        // The spotlight iris closes from the whole stage down to the card.
        final maxDim = size.longestSide * 1.1;
        final spotRadius = cardWidth * kCardAspect * zoom * 1.4;
        final irisRadius = maxDim + (spotRadius - maxDim) * travel;

        return IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Doom, staged: midnight closes in except for the spotlight.
              CustomPaint(
                painter: _SpotlightIrisPainter(
                  center: pos,
                  radius: irisRadius,
                  darkness: 0.82 * travel,
                ),
              ),
              Positioned(
                left: pos.dx,
                top: pos.dy,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: Transform.rotate(
                    angle: bowAngle,
                    child: Transform.scale(
                      scale: (0.6 + 1.0 * travel) * zoom,
                      child: _flippingJoker(cardWidth, flip),
                    ),
                  ),
                ),
              ),
              if (bannerIn > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  top: center.dy + cardWidth * kCardAspect * zoom / 2 + 34,
                  child: Center(
                    child: Transform.scale(
                      scale: bannerIn,
                      child: _title(context),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _flippingJoker(double width, double flip) {
    final showFace = flip >= 0.5;
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateY(pi * flip),
      child: showFace
          ? Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()..rotateY(pi),
              child: TrudeCardFace(
                rank: widget.event.jokerCard.rank,
                suit: widget.event.jokerCard.suit,
                width: width,
              ),
            )
          : TrudeCardBack(width: width),
    );
  }

  /// The serif playbill title under the bowing joker.
  Widget _title(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: TrudeColors.surfacePanel,
        borderRadius: BorderRadius.circular(TrudeDims.panelRadius),
        border: Border.all(color: TrudeColors.jokerPurple, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: TrudeColors.midnight.withValues(alpha: 0.7),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            Strings.jokerStaysWith(widget.loserName),
            textAlign: TextAlign.center,
            style: TrudeType.display.copyWith(
              fontSize: 18,
              height: 1.25,
              color: TrudeColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          // A little curtain-rule flourish under the title.
          Container(
            width: 72,
            height: TrudeDims.hairlineWidth,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  TrudeColors.brass,
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fullscreen midnight with a soft-edged spotlight hole at [center]:
/// transparent inside [radius], fading to [darkness] beyond it.
class _SpotlightIrisPainter extends CustomPainter {
  _SpotlightIrisPainter({
    required this.center,
    required this.radius,
    required this.darkness,
  });

  final Offset center;
  final double radius;
  final double darkness;

  @override
  void paint(Canvas canvas, Size size) {
    if (darkness <= 0) return;
    final rect = Offset.zero & size;
    // The gradient spans 1.6x the hole radius, giving a soft penumbra.
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          TrudeColors.midnight.withValues(alpha: 0.0),
          TrudeColors.midnight.withValues(alpha: 0.0),
          TrudeColors.midnight.withValues(alpha: darkness),
        ],
        stops: const [0.0, 0.62, 1.0],
      ).createShader(
          Rect.fromCircle(center: center, radius: max(1, radius * 1.6)));
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(_SpotlightIrisPainter old) =>
      old.center != center || old.radius != radius || old.darkness != darkness;
}
