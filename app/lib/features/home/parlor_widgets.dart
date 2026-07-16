/// Shared "Midnight Parlor" scaffolding for the meta screens (nickname, home,
/// rooms, lobby, results, achievements, settings): the backdrop gradient,
/// raised panels with hairline borders, brass plaques/buttons, etched
/// ornaments, and small decorative card arrangements.
///
/// Lives under `features/home/` because home is the hub screen; every other
/// meta screen imports it from here. All colors name tokens from
/// `TrudeColors`/`TrudeGradients` — no inline hex anywhere.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/audio/sfx_service.dart';
import '../../core/theme/trude_theme.dart';
import '../game/widgets/card_widgets.dart';

/// The standard meta-screen background: the backdrop gradient with a soft
/// vignette so edges fall into midnight. Wrap the whole [Scaffold] in this
/// (with a transparent scaffold background) so the app bar sits on it too.
class ParlorBackdrop extends StatelessWidget {
  const ParlorBackdrop({super.key, required this.child});

  final Widget child;

  static final _vignette = RadialGradient(
    center: const Alignment(0, -0.25),
    radius: 1.35,
    colors: [
      TrudeColors.midnight.withValues(alpha: 0),
      TrudeColors.midnight.withValues(alpha: 0.55),
    ],
    stops: const [0.55, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: TrudeGradients.backdrop),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: _vignette),
        child: child,
      ),
    );
  }
}

/// A raised parlor panel: `surfaceRaised` with a brass hairline border and a
/// soft drop into the midnight behind it.
class ParlorPanel extends StatelessWidget {
  const ParlorPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: TrudeColors.surfaceRaised,
        borderRadius: BorderRadius.circular(TrudeDims.panelRadius),
        border: Border.all(
          color: TrudeColors.hairline,
          width: TrudeDims.hairlineWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: TrudeColors.midnight.withValues(alpha: 0.5),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

/// Scales down slightly while pressed and up a hair on hover — the standard
/// "parlor door plaque" interaction. Purely decorative; hit behavior is a
/// plain [GestureDetector]. A Consumer so the tap-down can click ([uiTap])
/// via [sfxProvider] — every parlor button clicks for free.
class PressableScale extends ConsumerStatefulWidget {
  const PressableScale({super.key, this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  ConsumerState<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends ConsumerState<PressableScale> {
  bool _pressed = false;
  bool _hovered = false;

  bool get _enabled => widget.onTap != null;

  void _handleTapDown(TapDownDetails _) {
    ref.read(sfxProvider).uiTap();
    setState(() => _pressed = true);
  }

  @override
  Widget build(BuildContext context) {
    final scale = !_enabled
        ? 1.0
        : _pressed
            ? 0.965
            : _hovered
                ? 1.02
                : 1.0;
    return MouseRegion(
      cursor: _enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: _enabled ? _handleTapDown : null,
        onTapUp: _enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

/// The big brass call-to-action: a brushed-brass slab with an engraved serif
/// label. Disabled state falls back to a sunken plate.
class BrassButton extends StatelessWidget {
  const BrassButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.height = 56,
  });

  final VoidCallback? onPressed;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return PressableScale(
      onTap: onPressed,
      child: Container(
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: enabled ? TrudeGradients.brass : null,
          color: enabled ? null : TrudeColors.surfaceSunken,
          borderRadius: BorderRadius.circular(TrudeDims.chipRadius + 2),
          border: Border.all(
            color: enabled ? TrudeColors.brassDark : TrudeColors.hairline,
          ),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: TrudeColors.midnight.withValues(alpha: 0.45),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: IconTheme(
          data: IconThemeData(
            color: enabled ? TrudeColors.textOnBrass : TrudeColors.textMuted,
            size: 20,
          ),
          child: DefaultTextStyle(
            style: TrudeType.cardIndex.copyWith(
              fontSize: 17,
              letterSpacing: 1.4,
              color: enabled ? TrudeColors.textOnBrass : TrudeColors.textMuted,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Ornamental divider: two hairlines meeting a small brass diamond. Stands in
/// for textual section headers (no l10n strings exist for those).
class EtchedDivider extends StatelessWidget {
  const EtchedDivider({super.key, this.padding = const EdgeInsets.symmetric(vertical: 14)});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          const Expanded(child: SizedBox(height: 1, child: ColoredBox(color: TrudeColors.hairline))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Transform.rotate(
              angle: pi / 4,
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: TrudeColors.brassDark,
                  border: Border.all(color: TrudeColors.brass, width: 0.8),
                ),
              ),
            ),
          ),
          const Expanded(child: SizedBox(height: 1, child: ColoredBox(color: TrudeColors.hairline))),
        ],
      ),
    );
  }
}

/// The brass underline flourish under the "TRUDE" marquee: tapering rules,
/// end curls, and a center diamond — all painter-drawn.
class BrassFlourish extends StatelessWidget {
  const BrassFlourish({super.key, this.width = 220});

  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 18,
      child: const CustomPaint(painter: _FlourishPainter()),
    );
  }
}

class _FlourishPainter extends CustomPainter {
  const _FlourishPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final w = size.width;
    final line = Paint()
      ..color = TrudeColors.brass
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final bright = Paint()
      ..color = TrudeColors.brassBright
      ..style = PaintingStyle.fill;
    final dark = Paint()
      ..color = TrudeColors.brassDark
      ..style = PaintingStyle.fill;

    // Tapering rules either side of the center diamond.
    canvas.drawLine(Offset(w * 0.06, y), Offset(w * 0.42, y), line);
    canvas.drawLine(Offset(w * 0.58, y), Offset(w * 0.94, y), line);
    // Thin echo rules just below, shorter.
    final echo = Paint()
      ..color = TrudeColors.brassDark
      ..strokeWidth = 0.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(w * 0.16, y + 3.5), Offset(w * 0.40, y + 3.5), echo);
    canvas.drawLine(Offset(w * 0.60, y + 3.5), Offset(w * 0.84, y + 3.5), echo);

    // End curls: small open arcs.
    final curlL = Rect.fromCircle(center: Offset(w * 0.055, y - 2.5), radius: 2.8);
    final curlR = Rect.fromCircle(center: Offset(w * 0.945, y - 2.5), radius: 2.8);
    canvas.drawArc(curlL, pi * 0.25, pi * 1.35, false, line);
    canvas.drawArc(curlR, pi * 1.4, pi * 1.35, false, line);

    // Center diamond with two small side diamonds.
    void diamond(Offset c, double r, Paint p) {
      final path = Path()
        ..moveTo(c.dx, c.dy - r)
        ..lineTo(c.dx + r, c.dy)
        ..lineTo(c.dx, c.dy + r)
        ..lineTo(c.dx - r, c.dy)
        ..close();
      canvas.drawPath(path, p);
    }

    diamond(Offset(w * 0.5, y), 4.5, bright);
    diamond(Offset(w * 0.455, y), 2.2, dark);
    diamond(Offset(w * 0.545, y), 2.2, dark);
  }

  @override
  bool shouldRepaint(covariant _FlourishPainter oldDelegate) => false;
}

/// A decorative fanned hand of face-down cards (splash/nickname marquee).
/// Backs stay anonymous — pure decoration, no shimmer ticker.
class FannedCardBacks extends StatelessWidget {
  const FannedCardBacks({super.key, this.cardWidth = 60, this.count = 5});

  final double cardWidth;
  final int count;

  @override
  Widget build(BuildContext context) {
    final h = cardWidth * kCardAspect;
    return SizedBox(
      width: cardWidth * 3.4,
      height: h * 1.3,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomCenter,
        children: [
          for (var i = 0; i < count; i++) _card(i, h),
        ],
      ),
    );
  }

  Widget _card(int i, double h) {
    final t = count == 1 ? 0.0 : i / (count - 1) - 0.5;
    return Positioned(
      bottom: 0,
      child: Transform.translate(
        offset: Offset(t * cardWidth * 1.7, t.abs() * cardWidth * 0.55),
        child: Transform.rotate(
          angle: t * 0.95,
          alignment: Alignment.bottomCenter,
          child: TrudeCardBack(width: cardWidth),
        ),
      ),
    );
  }
}

/// A small sunken plate with brass-etched content — used for the home stats
/// plaques and similar small readouts.
class EtchedPlaque extends StatelessWidget {
  const EtchedPlaque({super.key, required this.child, this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: TrudeColors.surfaceSunken,
        borderRadius: BorderRadius.circular(TrudeDims.chipRadius),
        border: Border.all(color: TrudeColors.hairline),
      ),
      child: child,
    );
  }
}
