/// Four-of-a-kind set piece: the four cards fly from the discarder's seat to
/// center forming a face-up 2x2 square inside a brass frame, a golden shine
/// sweeps across while brass glints twinkle around it under a "FOUR SEVENS
/// OUT!" plaque, then the framed square shrinks into the retired rail.
library;

import 'dart:math';

import 'package:flutter/material.dart' hide Card;

import '../../../core/net/protocol_models.dart';
import '../../../core/strings.dart';
import '../../../core/theme/trude_theme.dart';
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
        final squareScale = shrink > 0 ? (1 - shrink) : assemble;
        // Fade over the tail of the shrink so the last frame is fully
        // invisible — nothing left parked at the rail before onDone unmounts.
        final fade = _phase(shrink, TableMotionSpec.quadFadeFrom, 1.0);

        return IgnorePointer(
          child: Stack(
            clipBehavior: Clip.none,
            fit: StackFit.expand,
            children: [
              // Brass glints twinkling around the framed square.
              if (shine > 0 && shine < 1 && shrink <= 0)
                Positioned(
                  left: squareCenter.dx,
                  top: squareCenter.dy,
                  child: FractionalTranslation(
                    translation: const Offset(-0.5, -0.5),
                    child: CustomPaint(
                      size: const Size.square(240),
                      painter: _GlintPainter(progress: shine),
                    ),
                  ),
                ),
              Positioned(
                left: squareCenter.dx,
                top: squareCenter.dy,
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: Opacity(
                    opacity: 1 - fade,
                    child: Transform.scale(
                      scale: max(0.05, squareScale),
                      child: _framedSquare(cardWidth, gap, shine),
                    ),
                  ),
                ),
              ),
              if (assemble >= 1 && shrink < 0.5)
                Positioned(
                  left: 0,
                  right: 0,
                  top: center.dy - cardWidth * kCardAspect - gap - 56,
                  child: Center(child: _plaque(shrink)),
                ),
            ],
          ),
        );
      },
    );
  }

  /// The 2x2 golden square inside a double brass frame with a soft glow.
  Widget _framedSquare(double cardWidth, double gap, double shine) {
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

    final framed = Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TrudeColors.brass, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: TrudeColors.brassBright.withValues(alpha: 0.35),
            blurRadius: 16,
          ),
          BoxShadow(
            color: TrudeColors.midnight.withValues(alpha: 0.5),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
              color: TrudeColors.brassDark, width: TrudeDims.hairlineWidth),
        ),
        child: square,
      ),
    );

    if (shine <= 0 || shine >= 1) return framed;
    // Golden gloss sweeping across the assembled square once.
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.transparent,
          TrudeColors.brassBright.withValues(alpha: 0.75),
          Colors.transparent,
        ],
        stops: const [0.3, 0.5, 0.7],
        transform: _SweepTransform(shine),
      ).createShader(bounds),
      child: framed,
    );
  }

  Widget _card(List<Card> cards, int i, double width) {
    if (i >= cards.length) return SizedBox(width: width);
    final c = cards[i];
    return TrudeCardFace(rank: c.rank, suit: c.suit, width: width, golden: true);
  }

  Widget _plaque(double shrink) {
    return Opacity(
      opacity: (1 - shrink * 2).clamp(0.0, 1.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          gradient: TrudeGradients.brass,
          borderRadius: BorderRadius.circular(TrudeDims.chipRadius),
          border: Border.all(color: TrudeColors.brassDark),
          boxShadow: [
            BoxShadow(
              color: TrudeColors.midnight.withValues(alpha: 0.55),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          Strings.quadBanner(widget.event.rank),
          style: TrudeType.stamp.copyWith(
            color: TrudeColors.textOnBrass,
            fontSize: 16,
            letterSpacing: 1.6,
            shadows: [
              Shadow(
                color: TrudeColors.brassBright.withValues(alpha: 0.55),
                offset: const Offset(0, 0.8),
              ),
            ],
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

/// Brass glint particles: 4-point star sparkles twinkling in a loose ring
/// around the framed square, each on its own seeded delay.
class _GlintPainter extends CustomPainter {
  _GlintPainter({required this.progress});

  /// 0..1 through the shine phase.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(4444); // deterministic layout per set piece
    final center = size.center(Offset.zero);

    for (var i = 0; i < TableMotionSpec.quadGlintCount; i++) {
      final angle = rng.nextDouble() * 2 * pi;
      final dist = 46 + rng.nextDouble() * 68;
      final pos = center + Offset(cos(angle), sin(angle)) * dist;
      final glintSize = 2.5 + rng.nextDouble() * 4.5;
      final delay = rng.nextDouble() * 0.55;

      // Each glint rises and dies inside its own window of the shine phase.
      final local = ((progress - delay) / 0.45).clamp(0.0, 1.0);
      if (local <= 0 || local >= 1) continue;
      final twinkle = sin(local * pi);

      final color = Color.lerp(
          TrudeColors.brass, TrudeColors.brassBright, rng.nextDouble())!;
      final ray = Paint()
        ..strokeWidth = 1.1
        ..strokeCap = StrokeCap.round
        ..color = color.withValues(alpha: 0.9 * twinkle);
      final r = glintSize * twinkle;
      canvas.drawLine(pos - Offset(r, 0), pos + Offset(r, 0), ray);
      canvas.drawLine(pos - Offset(0, r), pos + Offset(0, r), ray);
      canvas.drawCircle(
          pos,
          glintSize * 0.28 * twinkle,
          Paint()
            ..color = TrudeColors.brassBright.withValues(alpha: twinkle));
    }
  }

  @override
  bool shouldRepaint(_GlintPainter old) => old.progress != progress;
}
