/// Four-of-a-kind set piece: the four cards fly from the discarder's seat to
/// center forming a face-up 2x2 square, a golden shine sweeps across under a
/// "FOUR SEVENS OUT!" banner, then the square shrinks into the retired rail.
library;

import 'dart:math';

import 'package:flutter/material.dart' hide Card;

import '../../../core/net/protocol_models.dart';
import '../../../core/strings.dart';
import '../widgets/card_widgets.dart';
import 'motion_spec.dart';

class QuadCelebration extends StatefulWidget {
  const QuadCelebration({
    super.key,
    required this.event,
    required this.duration,
    required this.fromRect,
    required this.railRect,
    this.onDone,
  });

  final FourDiscardedEvent event;
  final Duration duration;

  /// Global rect of the discarder's seat (cards fly out of it).
  final Rect? fromRect;

  /// Global rect of the retired-ranks rail (the square shrinks into it).
  final Rect? railRect;
  final VoidCallback? onDone;

  @override
  State<QuadCelebration> createState() => _QuadCelebrationState();
}

class _QuadCelebrationState extends State<QuadCelebration>
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

  double _phase(double t, double from, double to) =>
      ((t - from) / (to - from)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    const cardWidth = 44.0;
    const gap = 6.0;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        final assemble = Curves.easeOutCubic
            .transform(_phase(t, 0, MotionSpec.quadAssembleEnd));
        final shine =
            _phase(t, MotionSpec.quadAssembleEnd, MotionSpec.quadShineEnd);
        final shrink = Curves.easeInCubic
            .transform(_phase(t, MotionSpec.quadShrinkStart, 1.0));

        final box = context.findRenderObject() as RenderBox?;
        final size = box?.size ?? MediaQuery.sizeOf(context);
        final layerOrigin = (box != null && box.attached)
            ? box.localToGlobal(Offset.zero)
            : Offset.zero;
        final center = Offset(size.width / 2, size.height / 2);
        final from = (widget.fromRect?.center ?? center + const Offset(0, -120)) -
            layerOrigin;
        final rail =
            (widget.railRect?.center ?? center + const Offset(0, -160)) -
                layerOrigin;

        // Square center: seat -> screen center while assembling, then
        // center -> retired rail while shrinking.
        final squareCenter = shrink > 0
            ? Offset.lerp(center, rail, shrink)!
            : Offset.lerp(from, center, assemble)!;
        final squareScale = shrink > 0 ? 1 - 0.85 * shrink : assemble;

        return IgnorePointer(
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              Positioned(
                left: squareCenter.dx,
                top: squareCenter.dy,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: Transform.scale(
                    scale: max(0.05, squareScale),
                    child: _goldenSquare(cardWidth, gap, shine),
                  ),
                ),
              ),
              if (assemble >= 1 && shrink < 0.5)
                Positioned(
                  left: 0,
                  right: 0,
                  top: center.dy - cardWidth * kCardAspect - gap - 56,
                  child: Center(child: _banner(shrink)),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _goldenSquare(double cardWidth, double gap, double shine) {
    final cards = widget.event.cards;
    final square = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var row = 0; row < 2; row++)
          Padding(
            padding: EdgeInsets.only(top: row == 0 ? 0 : gap),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var col = 0; col < 2; col++)
                  Padding(
                    padding: EdgeInsets.only(left: col == 0 ? 0 : gap),
                    child: _card(cards, row * 2 + col, cardWidth),
                  ),
              ],
            ),
          ),
      ],
    );
    if (shine <= 0 || shine >= 1) return square;
    // Golden gloss sweeping across the assembled square once.
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          const Color(0xFFFFD54F).withValues(alpha: 0.75),
          Colors.transparent,
        ],
        stops: const [0.3, 0.5, 0.7],
        transform: _SweepTransform(shine),
      ).createShader(bounds),
      child: square,
    );
  }

  Widget _card(List<Card> cards, int i, double width) {
    if (i >= cards.length) return SizedBox(width: width);
    final c = cards[i];
    return TrudeCardFace(rank: c.rank, suit: c.suit, width: width, golden: true);
  }

  Widget _banner(double shrink) {
    return Opacity(
      opacity: (1 - shrink * 2).clamp(0.0, 1.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFB300), Color(0xFFFFD54F), Color(0xFFFFB300)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          Strings.quadBanner(widget.event.rank),
          style: const TextStyle(
            color: Color(0xFF4E342E),
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: 1,
          ),
        ),
      ),
    );
  }
}

class _SweepTransform extends GradientTransform {
  const _SweepTransform(this.t);

  final double t;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2.4 - 1.2), 0, 0);
}
