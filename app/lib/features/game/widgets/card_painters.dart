/// The "Midnight Parlor" deck painters: engraved suit pips, classic per-rank
/// pip layouts, court medallions, the ace halo, the joker, and the guilloche
/// card back.
///
/// Every stroke, inset, and font size derives from the painted [Size], so a
/// card is crisp both at 12dp pile scale and at 120dp reveal scale. Hot
/// geometry ([Path]s, laid-out [TextPainter]s) is cached per quantized size;
/// `shouldRepaint` compares only real inputs.
library;

import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/theme/trude_theme.dart';

// ---------------------------------------------------------------------------
// Suit pips
// ---------------------------------------------------------------------------

/// Unit suit shapes are authored once in a 100x100 box centred on the origin
/// (y grows downward) with smooth cubic outlines, then scaled per use.
final Map<String, Path> _suitUnits = {
  'S': _buildSpade(),
  'H': _buildHeart(),
  'D': _buildDiamond(),
  'C': _buildClub(),
};

Path _buildSpade() => Path()
  ..moveTo(0, -50)
  ..cubicTo(8, -34, 32, -16, 38, -2) // right shoulder
  ..cubicTo(44, 13, 36, 26, 23, 26) // around the right lobe
  ..cubicTo(13, 26, 6, 20, 4, 10) // lobe inner edge up to the cusp
  ..cubicTo(5, 24, 10, 38, 19, 47) // stem flares down-right
  ..lineTo(-19, 47)
  ..cubicTo(-10, 38, -5, 24, -4, 10)
  ..cubicTo(-6, 20, -13, 26, -23, 26)
  ..cubicTo(-36, 26, -44, 13, -38, -2)
  ..cubicTo(-32, -16, -8, -34, 0, -50)
  ..close();

Path _buildHeart() => Path()
  ..moveTo(0, 46)
  ..cubicTo(-6, 32, -20, 18, -30, 7)
  ..cubicTo(-42, -6, -42, -30, -22, -33)
  ..cubicTo(-9, -35, -2, -25, 0, -17)
  ..cubicTo(2, -25, 9, -35, 22, -33)
  ..cubicTo(42, -30, 42, -6, 30, 7)
  ..cubicTo(20, 18, 6, 32, 0, 46)
  ..close();

Path _buildDiamond() => Path()
  ..moveTo(0, -50)
  ..cubicTo(5, -22, 18, -8, 31, 0)
  ..cubicTo(18, 8, 5, 22, 0, 50)
  ..cubicTo(-5, 22, -18, 8, -31, 0)
  ..cubicTo(-18, -8, -5, -22, 0, -50)
  ..close();

Path _buildClub() {
  final p = Path()
    ..addOval(Rect.fromCircle(center: const Offset(0, -27), radius: 21))
    ..addOval(Rect.fromCircle(center: const Offset(-21, 9), radius: 21))
    ..addOval(Rect.fromCircle(center: const Offset(21, 9), radius: 21))
    // Stem flares out of the junction of the three lobes.
    ..moveTo(3, 4)
    ..cubicTo(3, 24, 8, 38, 17, 47)
    ..lineTo(-17, 47)
    ..cubicTo(-8, 38, -3, 24, -3, 4)
    ..close();
  p.fillType = PathFillType.nonZero;
  return p;
}

/// The jester-cap silhouette (three curved horns, bell dots), authored in a
/// ~114x88 box centred on the origin.
final Path _jesterCapUnit = _buildJesterCap();

Path _buildJesterCap() {
  final p = Path()
    // Left horn: arches up and out, the tip drooping back down — floppy,
    // unmistakably a fool's cap rather than a crown point.
    ..moveTo(-34, 27)
    ..quadraticBezierTo(-52, -24, -60, 10) // outer edge over the arch to the tip
    ..quadraticBezierTo(-34, 0, -10, 17) // inner edge back to the band
    ..close()
    // Middle horn, straight up with gently concave sides.
    ..moveTo(-16, 20)
    ..quadraticBezierTo(-9, -14, 0, -46)
    ..quadraticBezierTo(9, -14, 16, 20)
    ..close()
    // Right horn (mirror of the left).
    ..moveTo(34, 27)
    ..quadraticBezierTo(52, -24, 60, 10)
    ..quadraticBezierTo(34, 0, 10, 17)
    ..close()
    // The rolled band the horns rise from.
    ..addRRect(RRect.fromLTRBR(-37, 21, 37, 32, const Radius.circular(5.5)))
    // Bells hover just past each tip.
    ..addOval(Rect.fromCircle(center: const Offset(-62, 17), radius: 4.5))
    ..addOval(Rect.fromCircle(center: const Offset(0, -53), radius: 4.5))
    ..addOval(Rect.fromCircle(center: const Offset(62, 17), radius: 4.5));
  p.fillType = PathFillType.nonZero;
  return p;
}

// -- Path / text caches -------------------------------------------------------

int _q(double v) => (v * 10).round(); // quantize a dimension for cache keys

final _scaledPathCache = <(String, int), Path>{};

Path _scaledPath(String kind, Path unit, double size) {
  if (_scaledPathCache.length > 96) _scaledPathCache.clear();
  return _scaledPathCache.putIfAbsent((kind, _q(size)), () {
    final s = size / 100;
    return unit.transform(Matrix4.diagonal3Values(s, s, 1).storage);
  });
}

/// A filled suit-pip [Path] for wire suit [suit] ('S','H','D','C'), [size]
/// units tall, centred on the origin. Cached per (suit, size).
Path suitPipPath(String suit, double size) =>
    _scaledPath('pip$suit', _suitUnits[suit] ?? _suitUnits['S']!, size);

/// The jester cap, [width] units wide, centred on the origin.
Path jesterCapPath(double width) =>
    _scaledPath('cap', _jesterCapUnit, width * 100 / 133);

final _sizedPathCache = <(String, int, int), Path>{};

Path _sizedPath(String kind, Size size, Path Function() build) {
  if (_sizedPathCache.length > 64) _sizedPathCache.clear();
  return _sizedPathCache.putIfAbsent(
      (kind, _q(size.width), _q(size.height)), build);
}

final _tpCache = <(String, int, Color, FontWeight, int), TextPainter>{};

/// A laid-out serif [TextPainter] in [TrudeType.cardIndex] voice; cached so
/// repeated card paints don't re-shape text.
TextPainter cardTextPainter(
  String text,
  double fontSize,
  Color color, {
  FontWeight weight = FontWeight.w700,
  double letterSpacing = 0,
}) {
  if (_tpCache.length > 128) _tpCache.clear();
  return _tpCache.putIfAbsent(
      (text, _q(fontSize), color, weight, _q(letterSpacing)), () {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TrudeType.cardIndex.copyWith(
          fontSize: fontSize,
          color: color,
          fontWeight: weight,
          letterSpacing: letterSpacing,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return tp;
  });
}

// ---------------------------------------------------------------------------
// Classic pip layouts
// ---------------------------------------------------------------------------

/// One pip position in the classic layout grid. [dx] is -1/0/1 across the two
/// pip columns (0 = card centreline); [dy] runs -1 (top row) to 1 (bottom
/// row). Pips with [rotated] are drawn upside down (the bottom half of the
/// card), and [scale] enlarges special pips (the ace).
class PipSpot {
  const PipSpot(this.dx, this.dy, {this.rotated = false, this.scale = 1});

  final double dx;
  final double dy;
  final bool rotated;
  final double scale;
}

/// The standard playing-card pip arrangements for A and 2-10.
const Map<String, List<PipSpot>> pipLayouts = {
  'A': [PipSpot(0, 0, scale: 2.3)],
  '2': [PipSpot(0, -1), PipSpot(0, 1, rotated: true)],
  '3': [PipSpot(0, -1), PipSpot(0, 0), PipSpot(0, 1, rotated: true)],
  '4': [
    PipSpot(-1, -1), PipSpot(1, -1),
    PipSpot(-1, 1, rotated: true), PipSpot(1, 1, rotated: true),
  ],
  '5': [
    PipSpot(-1, -1), PipSpot(1, -1), PipSpot(0, 0),
    PipSpot(-1, 1, rotated: true), PipSpot(1, 1, rotated: true),
  ],
  '6': [
    PipSpot(-1, -1), PipSpot(1, -1), PipSpot(-1, 0), PipSpot(1, 0),
    PipSpot(-1, 1, rotated: true), PipSpot(1, 1, rotated: true),
  ],
  '7': [
    PipSpot(-1, -1), PipSpot(1, -1), PipSpot(0, -0.5),
    PipSpot(-1, 0), PipSpot(1, 0),
    PipSpot(-1, 1, rotated: true), PipSpot(1, 1, rotated: true),
  ],
  '8': [
    PipSpot(-1, -1), PipSpot(1, -1), PipSpot(0, -0.5),
    PipSpot(-1, 0), PipSpot(1, 0),
    PipSpot(0, 0.5, rotated: true),
    PipSpot(-1, 1, rotated: true), PipSpot(1, 1, rotated: true),
  ],
  '9': [
    PipSpot(-1, -1), PipSpot(1, -1),
    PipSpot(-1, -1 / 3), PipSpot(1, -1 / 3),
    PipSpot(0, 0),
    PipSpot(-1, 1 / 3, rotated: true), PipSpot(1, 1 / 3, rotated: true),
    PipSpot(-1, 1, rotated: true), PipSpot(1, 1, rotated: true),
  ],
  '10': [
    PipSpot(-1, -1), PipSpot(1, -1),
    PipSpot(0, -2 / 3),
    PipSpot(-1, -1 / 3), PipSpot(1, -1 / 3),
    PipSpot(-1, 1 / 3, rotated: true), PipSpot(1, 1 / 3, rotated: true),
    PipSpot(0, 2 / 3, rotated: true),
    PipSpot(-1, 1, rotated: true), PipSpot(1, 1, rotated: true),
  ],
};

// ---------------------------------------------------------------------------
// Card face
// ---------------------------------------------------------------------------

/// Paints a full card face: ivory base with edge bevel and hairline frame,
/// mirrored corner indices, then classic pips / court medallion / ace halo /
/// joker art by rank; an optional golden (quad) wash goes on last.
class CardFacePainter extends CustomPainter {
  const CardFacePainter({
    required this.rank,
    required this.suit,
    required this.indexLabel,
    this.jokerWord = '',
    this.golden = false,
  });

  /// Wire rank: '2'..'10', 'J', 'Q', 'K', 'A', or 'JOKER'.
  final String rank;

  /// Wire suit 'S','H','D','C', or null (joker).
  final String? suit;

  /// Localized corner rank glyph (e.g. 'Q' / 'Д'); empty for the joker.
  final String indexLabel;

  /// Localized word for the joker banner (e.g. 'JOKER' / 'ДЖОКЕР').
  final String jokerWord;

  /// Four-of-a-kind celebration styling: warm wash + brass frame.
  final bool golden;

  bool get _isJoker => rank == 'JOKER';

  Color get _ink => _isJoker
      ? TrudeColors.jokerPurple
      : (suit == 'H' || suit == 'D')
          ? TrudeColors.inkRed
          : TrudeColors.inkBlack;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    _paintBase(canvas, size);

    switch (rank) {
      case 'JOKER':
        _paintJoker(canvas, size);
      case 'J' || 'Q' || 'K':
        _paintCourtMedallion(canvas, size);
      case 'A':
        _paintAceHalo(canvas, size);
        _paintPips(canvas, size);
      default:
        _paintPips(canvas, size);
    }

    // Corner indices: top-left, and bottom-right mirrored by a half turn.
    _paintCornerIndex(canvas, size);
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(pi);
    canvas.translate(-w / 2, -h / 2);
    _paintCornerIndex(canvas, size);
    canvas.restore();

    if (golden) _paintGoldenWash(canvas, size);
  }

  // -- Base: ivory, bevel, hairline frame -------------------------------------

  void _paintBase(Canvas canvas, Size size) {
    final w = size.width;
    final rect = Offset.zero & size;
    final radius = Radius.circular(w * TrudeDims.cardRadiusFactor);

    // Ivory base with a whisper of shading toward the bottom-right.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            TrudeColors.ivory,
            TrudeColors.ivory,
            TrudeColors.ivoryShade.withValues(alpha: 0.9),
          ],
          stops: const [0.0, 0.62, 1.0],
        ).createShader(rect),
    );

    // Edge bevel: a soft ivoryShade rim hugging the rounded edge.
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(w * 0.015), radius),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.035
        ..color = TrudeColors.ivoryShade,
    );

    // Thin inner hairline frame, inset ~4% of width (brass when golden).
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          rect.deflate(w * 0.045), Radius.circular(w * 0.06)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.5, w * 0.008)
        ..color = golden
            ? TrudeColors.brass
            : TrudeColors.inkBlack.withValues(alpha: 0.16),
    );
  }

  // -- Corner index: serif rank over a small pip -------------------------------

  void _paintCornerIndex(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w * 0.12;

    if (_isJoker) {
      // No letter (JOKER wouldn't fit); a tiny cap is the corner mark.
      canvas.save();
      canvas.translate(cx, h * 0.075);
      final cap = jesterCapPath(w * 0.17);
      canvas.drawPath(cap, Paint()..color = _ink);
      canvas.restore();
      return;
    }

    final fs = w * (indexLabel.length > 1 ? 0.15 : 0.17);
    final tp = cardTextPainter(indexLabel, fs, _ink);
    // Clamp so wide labels ('10') stay on the card instead of bleeding off.
    final left = max(w * 0.045, cx - tp.width / 2);
    tp.paint(canvas, Offset(left, h * 0.03));

    final s = suit;
    if (s == null) return;
    final pipSize = w * 0.105;
    canvas.save();
    canvas.translate(left + tp.width / 2, h * 0.03 + tp.height + pipSize * 0.62);
    canvas.drawPath(suitPipPath(s, pipSize), Paint()..color = _ink);
    canvas.restore();
  }

  // -- Number cards: classic pip grid ------------------------------------------

  void _paintPips(Canvas canvas, Size size) {
    final s = suit;
    final layout = pipLayouts[rank];
    if (s == null || layout == null) return;

    final w = size.width;
    final h = size.height;
    final ink = Paint()..color = _ink;
    final colX = w * 0.21; // pip columns at 0.29w / 0.71w
    final rowY = h * 0.33; // outer rows at 0.17h / 0.83h
    final pipSize = w * 0.20;

    for (final spot in layout) {
      canvas.save();
      canvas.translate(w / 2 + spot.dx * colX, h / 2 + spot.dy * rowY);
      if (spot.rotated) canvas.rotate(pi);
      canvas.drawPath(suitPipPath(s, pipSize * spot.scale), ink);
      canvas.restore();
    }
  }

  // -- Ace: engraved halo ring around one grand pip -----------------------------

  void _paintAceHalo(Canvas canvas, Size size) {
    final w = size.width;
    final center = Offset(w / 2, size.height / 2);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.4, w * 0.009)
      ..color = _ink.withValues(alpha: 0.38);

    canvas.drawCircle(center, w * 0.30, ring);
    canvas.drawCircle(
      center,
      w * 0.345,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.3, w * 0.006)
        ..color = _ink.withValues(alpha: 0.22),
    );

    // Radial engraving ticks between the two rings.
    final ticks = _sizedPath('aceTicks', size, () {
      final p = Path();
      const n = 24;
      for (var i = 0; i < n; i++) {
        final a = i * 2 * pi / n;
        final dir = Offset(cos(a), sin(a));
        p.moveTo(center.dx + dir.dx * w * 0.308, center.dy + dir.dy * w * 0.308);
        p.lineTo(center.dx + dir.dx * w * 0.337, center.dy + dir.dy * w * 0.337);
      }
      return p;
    });
    canvas.drawPath(
      ticks,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.3, w * 0.006)
        ..color = _ink.withValues(alpha: 0.30),
    );
  }

  // -- Courts: ornate letter in a double-ring brass medallion -------------------

  void _paintCourtMedallion(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);
    final s = suit;

    // Double brass ring with a dark keyline just outside.
    canvas.drawCircle(
      center,
      w * 0.325,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.3, w * 0.006)
        ..color = TrudeColors.brassDark.withValues(alpha: 0.8),
    );
    canvas.drawCircle(
      center,
      w * 0.30,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.5, w * 0.020)
        ..color = TrudeColors.brass,
    );
    canvas.drawCircle(
      center,
      w * 0.255,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.3, w * 0.007)
        ..color = TrudeColors.brassDark,
    );

    // The grand serif letter, in suit ink.
    final tp = cardTextPainter(indexLabel, w * 0.40, _ink,
        weight: FontWeight.w900);
    tp.paint(
        canvas, center - Offset(tp.width / 2, tp.height * 0.53));

    // Small suit pips above and below the medallion (bottom one rotated).
    if (s != null) {
      final pipSize = w * 0.13;
      final dy = w * 0.30 + pipSize * 0.75;
      canvas.save();
      canvas.translate(center.dx, center.dy - dy);
      canvas.drawPath(suitPipPath(s, pipSize), Paint()..color = _ink);
      canvas.restore();
      canvas.save();
      canvas.translate(center.dx, center.dy + dy);
      canvas.rotate(pi);
      canvas.drawPath(suitPipPath(s, pipSize), Paint()..color = _ink);
      canvas.restore();
    }

    // Corner flourishes just inside the hairline frame, mirrored 4 ways.
    final flourish = _sizedPath('flourish', size, () {
      final a = w * 0.085;
      final q = w * 0.15;
      return Path()
        ..moveTo(a, a + q)
        ..quadraticBezierTo(a, a, a + q, a)
        ..moveTo(a + w * 0.025, a + q * 0.62)
        ..quadraticBezierTo(
            a + w * 0.025, a + w * 0.025, a + q * 0.62, a + w * 0.025)
        // A tiny diamond bead in the crook of the curls.
        ..addPath(suitPipPath('D', w * 0.045), Offset(a + q * 0.42, a + q * 0.42));
    });
    final flourishInk = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.4, w * 0.010)
      ..color = TrudeColors.brass.withValues(alpha: 0.85);
    for (final (sx, sy) in const [(1.0, 1.0), (-1.0, 1.0), (1.0, -1.0), (-1.0, -1.0)]) {
      canvas.save();
      canvas.translate(w / 2, h / 2);
      canvas.scale(sx, sy);
      canvas.translate(-w / 2, -h / 2);
      canvas.drawPath(flourish, flourishInk);
      canvas.restore();
    }
  }

  // -- Joker: jester cap over the word, on a faint harlequin field --------------

  void _paintJoker(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Faint diagonal harlequin diamonds, kept inside the hairline frame.
    final field = _sizedPath('harlequin', size, () {
      final p = Path();
      final cw = max(w * 0.16, 6.0);
      final ch = cw * 1.6;
      final cols = (w / cw).ceil() + 1;
      final rows = (h / ch).ceil() + 1;
      for (var j = 0; j <= rows; j++) {
        for (var i = 0; i <= cols; i++) {
          if ((i + j).isOdd) continue;
          final cx = i * cw;
          final cy = j * ch;
          p
            ..moveTo(cx, cy - ch / 2)
            ..lineTo(cx + cw / 2, cy)
            ..lineTo(cx, cy + ch / 2)
            ..lineTo(cx - cw / 2, cy)
            ..close();
        }
      }
      return p;
    });
    canvas.save();
    canvas.clipRRect(RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(w * 0.055), Radius.circular(w * 0.05)));
    canvas.drawPath(
        field, Paint()..color = TrudeColors.jokerPurple.withValues(alpha: 0.06));
    canvas.restore();

    // The cap, slightly mischievous, never scary.
    final ink = Paint()..color = TrudeColors.jokerPurple;
    canvas.save();
    canvas.translate(w / 2, h * 0.395);
    canvas.drawPath(jesterCapPath(w * 0.62), ink);
    canvas.restore();

    // Serif JOKER word beneath, shrunk to fit if the locale runs long.
    if (jokerWord.isNotEmpty) {
      var fs = w * 0.135;
      var tp = cardTextPainter(jokerWord, fs, TrudeColors.jokerPurple,
          weight: FontWeight.w900, letterSpacing: w * 0.02);
      if (tp.width > w * 0.76) {
        fs *= w * 0.76 / tp.width;
        tp = cardTextPainter(jokerWord, fs, TrudeColors.jokerPurple,
            weight: FontWeight.w900, letterSpacing: w * 0.012);
      }
      tp.paint(canvas, Offset(w / 2 - tp.width / 2, h * 0.60));
    }
  }

  // -- Golden (quad) variant -----------------------------------------------------

  void _paintGoldenWash(Canvas canvas, Size size) {
    final w = size.width;
    final rect = Offset.zero & size;
    canvas.drawRect(
        rect, Paint()..color = TrudeColors.brassBright.withValues(alpha: 0.20));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          rect.deflate(w * 0.025), Radius.circular(w * 0.08)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.0, w * 0.035)
        ..shader = TrudeGradients.brass.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(CardFacePainter oldDelegate) =>
      oldDelegate.rank != rank ||
      oldDelegate.suit != suit ||
      oldDelegate.indexLabel != indexLabel ||
      oldDelegate.jokerWord != jokerWord ||
      oldDelegate.golden != golden;
}

// ---------------------------------------------------------------------------
// Card back
// ---------------------------------------------------------------------------

/// The card back: a symmetric brass guilloche lattice on [TrudeColors
/// .cardBackTeal] inside an ivory frame, with a small central brass "T"
/// medallion. Reveals nothing about the card — every back is identical.
class CardBackPainter extends CustomPainter {
  const CardBackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final center = rect.center;

    // Ivory frame with the same edge bevel as the face.
    canvas.drawRect(rect, Paint()..color = TrudeColors.ivory);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect.deflate(w * 0.015),
          Radius.circular(w * TrudeDims.cardRadiusFactor)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.035
        ..color = TrudeColors.ivoryShade,
    );

    // Teal field.
    final inner = RRect.fromRectAndRadius(
        rect.deflate(w * 0.075), Radius.circular(w * 0.055));
    canvas.drawRRect(inner, Paint()..color = TrudeColors.cardBackTeal);

    // Guilloche lattice: one cached wave-cable path, drawn along both
    // diagonals so the crossings weave a diamond field.
    final diag = sqrt(w * w + h * h);
    final lattice = _sizedPath('guilloche', size, () {
      final p = Path();
      final cell = max(w * 0.15, 5.0);
      final amp = cell * 0.32;
      // Cubic controls at y +- amp/0.75 make each bump peak at exactly amp.
      final c = amp / 0.75;
      for (var y = -diag / 2; y <= diag / 2; y += cell * 1.25) {
        for (final phase in const [1.0, -1.0]) {
          p.moveTo(-diag / 2, y);
          var x = -diag / 2;
          var sign = phase;
          while (x < diag / 2) {
            p.cubicTo(x + cell / 3, y - sign * c, x + 2 * cell / 3,
                y - sign * c, x + cell, y);
            x += cell;
            sign = -sign;
          }
        }
      }
      return p;
    });
    final thread = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(0.4, w * 0.012)
      ..color = TrudeColors.brass.withValues(alpha: 0.50);
    canvas.save();
    canvas.clipRRect(inner);
    canvas.translate(center.dx, center.dy);
    canvas.rotate(pi / 4);
    canvas.drawPath(lattice, thread);
    canvas.rotate(-pi / 2);
    canvas.drawPath(lattice, thread);
    canvas.restore();

    // Brass keyline around the teal field.
    canvas.drawRRect(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.4, w * 0.012)
        ..color = TrudeColors.brass.withValues(alpha: 0.75),
    );

    // Central medallion: teal blank, double brass ring, serif "T".
    final r = w * 0.17;
    canvas.drawCircle(
        center, r + w * 0.03, Paint()..color = TrudeColors.cardBackTeal);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.5, w * 0.016)
        ..color = TrudeColors.brass,
    );
    canvas.drawCircle(
      center,
      r * 0.80,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(0.3, w * 0.007)
        ..color = TrudeColors.brassDark,
    );
    final tp = cardTextPainter('T', w * 0.19, TrudeColors.brassBright,
        weight: FontWeight.w900);
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height * 0.53));
  }

  @override
  bool shouldRepaint(CardBackPainter oldDelegate) => false;
}
