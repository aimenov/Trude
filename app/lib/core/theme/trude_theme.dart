/// The Trude design system: "Midnight Parlor" — a moody premium card-parlor.
/// Deep green felt under a warm pool of light, brass fittings, ivory cards
/// with classic pip layouts, and a serif display voice (Playfair Display).
///
/// EVERY color, gradient, radius, and text style in the app names a token
/// here. No screen or painter may carry inline hex colors.
library;

import 'package:flutter/material.dart';

abstract final class TrudeColors {
  // -- Table & environment ----------------------------------------------------
  /// Outermost darkness at screen edges.
  static const midnight = Color(0xFF0A130E);

  /// Felt at the vignette edge.
  static const feltDeep = Color(0xFF0E2B20);

  /// Felt base tone.
  static const felt = Color(0xFF14503A);

  /// Felt under the center light pool.
  static const feltLit = Color(0xFF1E6B4C);

  /// Mahogany table rail.
  static const railWood = Color(0xFF332014);
  static const railWoodLit = Color(0xFF4E3120);

  // -- Brass (the accent metal) ------------------------------------------------
  static const brass = Color(0xFFC9A227);
  static const brassBright = Color(0xFFEBCD6F);
  static const brassDark = Color(0xFF77621B);

  // -- Cards -------------------------------------------------------------------
  static const ivory = Color(0xFFFBF7EC);
  static const ivoryShade = Color(0xFFEEE4CF);
  static const inkBlack = Color(0xFF22262E);
  static const inkRed = Color(0xFFAE2239);
  static const jokerPurple = Color(0xFF5B2A86);
  static const cardBackTeal = Color(0xFF0F3A2D);

  // -- UI surfaces (panels, sheets, chips) --------------------------------------
  static const surfacePanel = Color(0xFF102A1F);
  static const surfaceRaised = Color(0xFF17382A);
  static const surfaceSunken = Color(0xFF0C2018);
  static const hairline = Color(0x33EBCD6F); // brassBright at 20%

  // -- Text ---------------------------------------------------------------------
  static const textPrimary = Color(0xFFF3EFE3);
  static const textMuted = Color(0xFF9DB3A4);
  static const textOnBrass = Color(0xFF241D08);

  // -- Semantic ------------------------------------------------------------------
  static const truth = Color(0xFF43B072); // verdict: truth / success
  static const lie = Color(0xFFD6404F); // verdict: liar / danger / urgent
  static const info = Color(0xFF4E8FB8);
}

abstract final class TrudeGradients {
  /// The table felt: warm pool of light falling on the center, falling off to
  /// [TrudeColors.feltDeep] at the edges. Paint radially from table center.
  static const feltLight = RadialGradient(
    center: Alignment(0, -0.15),
    radius: 1.15,
    colors: [TrudeColors.feltLit, TrudeColors.felt, TrudeColors.feltDeep],
    stops: [0.0, 0.55, 1.0],
  );

  /// Brushed brass for chips, frames, and stamps.
  static const brass = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      TrudeColors.brassBright,
      TrudeColors.brass,
      TrudeColors.brassDark,
      TrudeColors.brass,
    ],
    stops: [0.0, 0.4, 0.75, 1.0],
  );

  /// Screen background outside the table (menus, panels).
  static const backdrop = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [TrudeColors.surfaceRaised, TrudeColors.midnight],
  );
}

abstract final class TrudeDims {
  static const cardRadiusFactor = 0.11; // of card width
  static const panelRadius = 18.0;
  static const chipRadius = 12.0;
  static const hairlineWidth = 1.0;
}

/// Display (serif) text styles. Body text stays on the default sans.
abstract final class TrudeType {
  static const _serif = 'PlayfairDisplay';

  /// Screen titles: "TRUDE", room names.
  static const display = TextStyle(
    fontFamily: _serif,
    fontWeight: FontWeight.w900,
    color: TrudeColors.textPrimary,
    letterSpacing: 1.2,
  );

  /// Claim callouts and verdict stamps ("THREE SEVENS!", "LIAR!").
  static const stamp = TextStyle(
    fontFamily: _serif,
    fontWeight: FontWeight.w900,
    letterSpacing: 2.0,
    height: 1.0,
  );

  /// Card corner indices and rank letters.
  static const cardIndex = TextStyle(
    fontFamily: _serif,
    fontWeight: FontWeight.w700,
    height: 1.0,
  );

  /// Small brass-etched labels (section headers, badges).
  static const etched = TextStyle(
    fontFamily: _serif,
    fontWeight: FontWeight.w700,
    color: TrudeColors.brass,
    letterSpacing: 3.0,
  );
}

/// The app-wide [ThemeData]. Dark, green-felt surfaces with brass accents.
ThemeData buildTrudeTheme() {
  const scheme = ColorScheme.dark(
    primary: TrudeColors.brass,
    onPrimary: TrudeColors.textOnBrass,
    primaryContainer: TrudeColors.brassDark,
    onPrimaryContainer: TrudeColors.brassBright,
    secondary: TrudeColors.feltLit,
    onSecondary: TrudeColors.textPrimary,
    surface: TrudeColors.surfacePanel,
    onSurface: TrudeColors.textPrimary,
    surfaceContainerHighest: TrudeColors.surfaceRaised,
    onSurfaceVariant: TrudeColors.textMuted,
    error: TrudeColors.lie,
    onError: TrudeColors.textPrimary,
    outline: TrudeColors.hairline,
  );

  final base = ThemeData(colorScheme: scheme, useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: TrudeColors.midnight,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
      titleTextStyle: TrudeType.display.copyWith(fontSize: 22),
      foregroundColor: TrudeColors.textPrimary,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: TrudeColors.brass,
        foregroundColor: TrudeColors.textOnBrass,
        textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TrudeDims.chipRadius),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: TrudeColors.brassBright,
        side: const BorderSide(color: TrudeColors.brassDark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TrudeDims.chipRadius),
        ),
      ),
    ),
    cardTheme: base.cardTheme.copyWith(
      color: TrudeColors.surfaceRaised,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TrudeDims.panelRadius),
        side: const BorderSide(color: TrudeColors.hairline),
      ),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: TrudeColors.surfacePanel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TrudeDims.panelRadius),
        side: const BorderSide(color: TrudeColors.hairline),
      ),
      titleTextStyle: TrudeType.display.copyWith(fontSize: 20),
    ),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      filled: true,
      fillColor: TrudeColors.surfaceSunken,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TrudeDims.chipRadius),
        borderSide: const BorderSide(color: TrudeColors.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TrudeDims.chipRadius),
        borderSide: const BorderSide(color: TrudeColors.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(TrudeDims.chipRadius),
        borderSide: const BorderSide(color: TrudeColors.brass, width: 1.5),
      ),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      backgroundColor: TrudeColors.surfaceRaised,
      contentTextStyle: const TextStyle(color: TrudeColors.textPrimary),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(color: TrudeColors.hairline, thickness: 1),
  );
}
