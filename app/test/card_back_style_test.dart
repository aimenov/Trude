// Cosmetic style catalog + CardBackPainter repaint contract:
// - classic styles are bit-identical to the TrudeColors tokens (the frozen
//   goldens depend on this),
// - unknown catalog ids fall back to classic,
// - CardBackPainter repaints exactly when the style id changes.

import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/theme/trude_theme.dart';
import 'package:trude/features/game/widgets/card_painters.dart';
import 'package:trude/features/game/widgets/cosmetic_styles.dart';

void main() {
  group('cosmetic catalog', () {
    test('classic card back references the theme tokens bit-identically', () {
      const c = CardBackStyle.classic;
      expect(c.id, 'cb_classic');
      expect(c.field, TrudeColors.cardBackTeal);
      expect(c.lattice, TrudeColors.brass);
      expect(c.frame, TrudeColors.ivory);
      expect(c.frameShade, TrudeColors.ivoryShade);
      expect(c.medallionInk, TrudeColors.brassBright);
    });

    test('classic felt references the theme tokens bit-identically', () {
      const f = FeltStyle.classic;
      expect(f.id, 'felt_classic');
      expect(f.lit, TrudeColors.feltLit);
      expect(f.base, TrudeColors.felt);
      expect(f.deep, TrudeColors.feltDeep);
      expect(f.warmth, TrudeColors.brassBright);
    });

    test('card-back catalog carries the full v1 key set, ids consistent', () {
      expect(
        cardBackStyles.keys,
        containsAll(<String>[
          'cb_classic',
          'cb_crimson',
          'cb_noir',
          'cb_royal',
          'cb_imperial',
          'cb_gilded',
        ]),
      );
      for (final entry in cardBackStyles.entries) {
        expect(entry.value.id, entry.key);
      }
    });

    test('felt catalog carries the full v1 key set, ids consistent', () {
      expect(
        feltStyles.keys,
        containsAll(<String>[
          'felt_classic',
          'felt_burgundy',
          'felt_navy',
          'felt_midnight',
        ]),
      );
      for (final entry in feltStyles.entries) {
        expect(entry.value.id, entry.key);
      }
    });

    test('known ids resolve to their style', () {
      expect(cardBackStyleFor('cb_royal').id, 'cb_royal');
      expect(feltStyleFor('felt_navy').id, 'felt_navy');
    });

    test('unknown ids fall back to classic', () {
      expect(cardBackStyleFor('cb_who_dis'), same(CardBackStyle.classic));
      expect(cardBackStyleFor(''), same(CardBackStyle.classic));
      expect(feltStyleFor('felt_neon_laser'), same(FeltStyle.classic));
      expect(feltStyleFor(''), same(FeltStyle.classic));
    });
  });

  group('CardBackPainter.shouldRepaint', () {
    test('default (classic) painters never repaint against each other', () {
      const a = CardBackPainter();
      const b = CardBackPainter();
      expect(b.shouldRepaint(a), isFalse);
    });

    test('same non-classic style id does not repaint', () {
      final a = CardBackPainter(style: cardBackStyleFor('cb_royal'));
      final b = CardBackPainter(style: cardBackStyleFor('cb_royal'));
      expect(b.shouldRepaint(a), isFalse);
    });

    test('different style ids repaint, both directions', () {
      const classic = CardBackPainter();
      final royal = CardBackPainter(style: cardBackStyleFor('cb_royal'));
      expect(royal.shouldRepaint(classic), isTrue);
      expect(classic.shouldRepaint(royal), isTrue);
    });
  });
}
