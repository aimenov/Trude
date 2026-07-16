/// Game-over set piece: the joker flips up center-screen from the loser's
/// seat with a slow zoom under "THE JOKER STAYS WITH ..." — navigation to
/// /results waits for this step to finish (or be tapped through).
library;

import 'dart:math';

import 'package:flutter/material.dart' hide Card;

import '../../../core/net/protocol_models.dart';
import '../../../core/strings.dart';
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

        final box = context.findRenderObject() as RenderBox?;
        final size = box?.size ?? MediaQuery.sizeOf(context);
        final layerOrigin = (box != null && box.attached)
            ? box.localToGlobal(Offset.zero)
            : Offset.zero;
        final center = Offset(size.width / 2, size.height / 2 - 30);
        final from =
            (widget.fromRect?.center ?? center + const Offset(0, 180)) -
                layerOrigin;
        final pos = Offset.lerp(from, center, travel)!;

        return IgnorePointer(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Darken hard: this is the doom moment.
              Opacity(
                opacity: 0.55 * travel,
                child: const ColoredBox(color: Colors.black),
              ),
              Positioned(
                left: pos.dx,
                top: pos.dy,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: Transform.scale(
                    scale: (0.6 + 1.0 * travel) * zoom,
                    child: _flippingJoker(cardWidth, flip),
                  ),
                ),
              ),
              if (bannerIn > 0)
                Positioned(
                  left: 0,
                  right: 0,
                  top: center.dy + cardWidth * kCardAspect * zoom / 2 + 28,
                  child: Center(
                    child: Transform.scale(
                      scale: bannerIn,
                      child: _banner(context),
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

  Widget _banner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepPurple.shade300),
      ),
      child: Text(
        Strings.jokerStaysWith(widget.loserName),
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 18,
          letterSpacing: 1,
        ),
      ),
    );
  }
}
