/// Cosmetic styles for the "Parlor Economy" round: the card-back and felt
/// palettes, keyed by the server catalog ids (`cb_*` / `felt_*`).
///
/// This file is the ONE place besides `core/theme/trude_theme.dart` allowed
/// to carry literal [Color] values — every non-classic cosmetic palette lives
/// here (see docs/design-system.md, "Cosmetics ownership"). All palettes stay
/// in the desaturated candle-lit Midnight-Parlor voice: aged metals, wine,
/// deep night blues — never neon.
///
/// The `classic` styles reference [TrudeColors] tokens directly, so classic
/// rendering is bit-identical to the pre-cosmetics art (classic goldens are
/// frozen and must not move). Unknown ids always fall back to classic.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/net/economy_providers.dart';
import '../../../core/theme/trude_theme.dart';

// ---------------------------------------------------------------------------
// Card backs
// ---------------------------------------------------------------------------

/// Palette of the guilloche card back (see `CardBackPainter`).
@immutable
class CardBackStyle {
  const CardBackStyle({
    required this.id,
    required this.field,
    required this.lattice,
    required this.frame,
    required this.frameShade,
    required this.medallionInk,
  });

  /// Server catalog key (`cb_*`).
  final String id;

  /// The colored field inside the frame (classic: teal).
  final Color field;

  /// The guilloche thread, keyline, and medallion-ring metal (drawn at the
  /// painter's own alphas).
  final Color lattice;

  /// The outer card border (classic: ivory).
  final Color frame;

  /// The edge bevel hugging the frame (classic: ivoryShade).
  final Color frameShade;

  /// Ink of the central "T" monogram.
  final Color medallionInk;

  /// The default teal-and-brass back — token-for-token the original art.
  static const classic = CardBackStyle(
    id: 'cb_classic',
    field: TrudeColors.cardBackTeal,
    lattice: TrudeColors.brass,
    frame: TrudeColors.ivory,
    frameShade: TrudeColors.ivoryShade,
    medallionInk: TrudeColors.brassBright,
  );
}

/// Every purchasable card back, keyed by server catalog id.
const Map<String, CardBackStyle> cardBackStyles = {
  'cb_classic': CardBackStyle.classic,

  /// Dried-wine red under old gold.
  'cb_crimson': CardBackStyle(
    id: 'cb_crimson',
    field: Color(0xFF471821),
    lattice: Color(0xFFB9973F),
    frame: TrudeColors.ivory,
    frameShade: TrudeColors.ivoryShade,
    medallionInk: Color(0xFFE0C87A),
  ),

  /// Lamp-black field threaded with tarnished pewter.
  'cb_noir': CardBackStyle(
    id: 'cb_noir',
    field: Color(0xFF16181D),
    lattice: Color(0xFF8E96A3),
    frame: Color(0xFFDCD9D2),
    frameShade: Color(0xFFBEBBB1),
    medallionInk: Color(0xFFCBD2DC),
  ),

  /// Muted plum velvet with antique gold.
  'cb_royal': CardBackStyle(
    id: 'cb_royal',
    field: Color(0xFF33204A),
    lattice: Color(0xFFC4A14E),
    frame: TrudeColors.ivory,
    frameShade: TrudeColors.ivoryShade,
    medallionInk: Color(0xFFE6C878),
  ),

  /// Deep prussian blue under bright gilt, parchment frame.
  'cb_imperial': CardBackStyle(
    id: 'cb_imperial',
    field: Color(0xFF20304F),
    lattice: Color(0xFFD3B04A),
    frame: Color(0xFFF6EFDD),
    frameShade: Color(0xFFE3D5B7),
    medallionInk: Color(0xFFF0D98A),
  ),

  /// Patron-only: gold on dark bronze, candle-warm.
  'cb_gilded': CardBackStyle(
    id: 'cb_gilded',
    field: Color(0xFF3A2B12),
    lattice: Color(0xFFD9B84F),
    frame: Color(0xFFF3E7C8),
    frameShade: Color(0xFFDDC894),
    medallionInk: Color(0xFFF5E3A0),
  ),
};

/// Catalog lookup; unknown ids fall back to [CardBackStyle.classic].
CardBackStyle cardBackStyleFor(String id) =>
    cardBackStyles[id] ?? CardBackStyle.classic;

// ---------------------------------------------------------------------------
// Felts
// ---------------------------------------------------------------------------

/// Palette of the table felt (see `TableFeltBackground` / `_FeltPainter`).
@immutable
class FeltStyle {
  const FeltStyle({
    required this.id,
    required this.lit,
    required this.base,
    required this.deep,
    required this.warmth,
  });

  /// Server catalog key (`felt_*`).
  final String id;

  /// Felt under the center light pool.
  final Color lit;

  /// Felt base tone.
  final Color base;

  /// Felt at the vignette edge.
  final Color deep;

  /// The candle-warmth tint pooled at the light center (drawn at the
  /// painter's own animated alphas).
  final Color warmth;

  /// The default green felt — token-for-token the original art.
  static const classic = FeltStyle(
    id: 'felt_classic',
    lit: TrudeColors.feltLit,
    base: TrudeColors.felt,
    deep: TrudeColors.feltDeep,
    warmth: TrudeColors.brassBright,
  );
}

/// Every purchasable felt, keyed by server catalog id.
const Map<String, FeltStyle> feltStyles = {
  'felt_classic': FeltStyle.classic,

  /// Old burgundy cloth, candle-gold warmth.
  'felt_burgundy': FeltStyle(
    id: 'felt_burgundy',
    lit: Color(0xFF6B3444),
    base: Color(0xFF4A2230),
    deep: Color(0xFF291218),
    warmth: TrudeColors.brassBright,
  ),

  /// Dusty admiralty navy with a paler parchment glow.
  'felt_navy': FeltStyle(
    id: 'felt_navy',
    lit: Color(0xFF2E4C6B),
    base: Color(0xFF1F344E),
    deep: Color(0xFF101D2E),
    warmth: Color(0xFFE3D08A),
  ),

  /// Near-black slate blue lit like moonlight through smoke.
  'felt_midnight': FeltStyle(
    id: 'felt_midnight',
    lit: Color(0xFF2B3440),
    base: Color(0xFF1A212B),
    deep: Color(0xFF0C1015),
    warmth: Color(0xFFB9C4D6),
  ),
};

/// Catalog lookup; unknown ids fall back to [FeltStyle.classic].
FeltStyle feltStyleFor(String id) => feltStyles[id] ?? FeltStyle.classic;

// ---------------------------------------------------------------------------
// Selected-cosmetic providers
// ---------------------------------------------------------------------------

/// The card-back style the player currently has equipped (server-selected key
/// resolved through the catalog; unknown/legacy keys degrade to classic).
final selectedCardBackStyleProvider = Provider<CardBackStyle>(
  (ref) => cardBackStyleFor(ref.watch(selectedCosmeticsProvider).cardBack),
);

/// The felt style the player currently has equipped.
final selectedFeltStyleProvider = Provider<FeltStyle>(
  (ref) => feltStyleFor(ref.watch(selectedCosmeticsProvider).felt),
);
