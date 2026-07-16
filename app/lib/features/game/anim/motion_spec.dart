/// Every duration, curve, and choreography constant of the game-feel pass.
/// No animation code may carry inline magic numbers — it names them here.
library;

import 'package:flutter/animation.dart';

abstract final class MotionSpec {
  // -- Card flights (shared) --------------------------------------------------

  /// Base flight time of a single card between two table anchors.
  static const cardFlight = Duration(milliseconds: 380);
  static const cardFlightCurve = Curves.easeInOutCubic;

  /// Height of the Bezier arc as a fraction of the flight distance.
  static const arcHeightFactor = 0.35;
  static const minArcHeight = 24.0;

  // -- Deal set piece ---------------------------------------------------------

  /// Whole deal (spray + landings) must stay under this.
  static const dealTotalCap = Duration(milliseconds: 2400);
  static const dealFlight = Duration(milliseconds: 420);

  /// Nominal inter-card gap of the spray (the accelerating schedule averages
  /// out near this).
  static const dealStagger = Duration(milliseconds: 40);

  /// Exponent shaping the accelerating spray: launch time of card k is
  /// sprayWindow * (k/n)^dealAccel — < 1 makes later gaps shorter, so the
  /// deal starts deliberate and speeds up.
  static const dealAccel = 0.75;

  // -- Throw set piece --------------------------------------------------------

  static const throwStagger = Duration(milliseconds: 70);

  /// Small tail after the last card lands before the step completes.
  static const throwSettle = Duration(milliseconds: 120);
  static const throwSpinTurns = 0.75;

  // -- Claim callout ("THREE SEVENS!") ----------------------------------------

  static const calloutIn = Duration(milliseconds: 220);
  static const calloutHold = Duration(milliseconds: 1200);
  static const calloutFade = Duration(milliseconds: 300);
  static const calloutInCurve = Curves.easeOutBack;

  // -- Check reveal set piece ---------------------------------------------------
  // Beats are fractions of [revealTotal] so speed scaling keeps them in sync.

  static const revealTotal = Duration(milliseconds: 2700);
  static const revealDimFraction = 0.09; // vignette fades in
  static const revealSpreadEnd = 0.26; // cards slid apart center-stage
  static const revealLiftEnd = 0.35; // chosen card lifted
  static const revealFlipStart = 0.44; // after the 250 ms-ish pause
  static const revealFlipEnd = 0.65; // flip done (slow-peel curve inside)
  static const revealVerdictIn = 0.72; // stamp lands
  static const revealDimOpacity = 0.30;
  static const revealCardScale = 1.9;
  static const revealLiftDy = -26.0;
  static const revealSpreadCurve = Curves.easeOutCubic;
  static const verdictStampCurve = Curves.elasticOut;

  /// Slow-peel flip: crawl through the first [peelBreakFraction] of the
  /// rotation, then snap through the rest. 60/180 degrees.
  static const peelBreakFraction = 60.0 / 180.0;

  /// Portion of the flip time spent on the slow crawl.
  static const peelBreakTime = 0.62;

  // -- Pickup set piece ---------------------------------------------------------

  static const pickupBase = Duration(milliseconds: 550);
  static const pickupStagger = Duration(milliseconds: 25);
  static const pickupCap = Duration(milliseconds: 1600);
  static const pickupFlightCurve = Curves.easeInCubic; // accelerating converge

  // -- Four-of-a-kind ------------------------------------------------------------

  static const quadTotal = Duration(milliseconds: 1200);
  static const quadAssembleEnd = 0.35; // cards form the 2x2 square
  static const quadShineEnd = 0.75; // golden sweep across
  static const quadShrinkStart = 0.78; // collapse into the retired rail

  // -- Game over -------------------------------------------------------------

  static const gameOverTotal = Duration(milliseconds: 2800);
  static const gameOverFlipEnd = 0.45;
  static const gameOverZoomCurve = Curves.easeOutCubic;

  // -- Minor steps -------------------------------------------------------------

  static const playerOutStep = Duration(milliseconds: 600);

  // -- Turn indicator / countdown ----------------------------------------------

  static const turnRingRotation = Duration(milliseconds: 2400);
  static const breathingPeriod = Duration(milliseconds: 1800);
  static const breathingScaleDelta = 0.03;
  static const actionBarSlideIn = Duration(milliseconds: 420);
  static const actionBarCurve = Curves.easeOutBack;

  /// Countdown turns amber -> red and the hand starts shivering below this.
  static const urgentThreshold = Duration(seconds: 5);
  static const handShiverAmplitude = 1.4; // dp
  static const handShiverPeriod = Duration(milliseconds: 90);

  // -- Idle life ------------------------------------------------------------------

  static const shimmerPeriod = Duration(milliseconds: 3200);
  static const pileSettlePeriod = Duration(seconds: 10);
  static const avatarBobPeriod = Duration(milliseconds: 2600);
  static const avatarBobAmplitude = 1.6; // dp

  // -- Reactions ---------------------------------------------------------------

  static const reactionBurstLife = Duration(milliseconds: 1200);
  static const reactionMinCount = 5;
  static const reactionMaxCount = 9;
  static const reactionGravity = 950.0; // dp/s^2
  static const reactionLaunchSpeed = 320.0; // dp/s, +- spread

  // -- Pile rendering -------------------------------------------------------------

  /// Card backs actually rendered in the messy stack; the rest is a badge.
  static const pileRenderCap = 12;

  // -- Shared entrance -----------------------------------------------------------

  static const handCardEnter = Duration(milliseconds: 260);
  static const handCardEnterCurve = Curves.easeOutBack;
}

/// The reveal flip's "slow peel" curve: linger over the first
/// [MotionSpec.peelBreakFraction] of the rotation, then snap through.
class SlowPeelCurve extends Curve {
  const SlowPeelCurve();

  @override
  double transformInternal(double t) {
    const breakT = MotionSpec.peelBreakTime;
    const breakV = MotionSpec.peelBreakFraction;
    if (t < breakT) {
      // Ease-out crawl to the 60-degree break point.
      final u = t / breakT;
      return breakV * (1 - (1 - u) * (1 - u));
    }
    // Ease-in snap through the remaining 120 degrees.
    final u = (t - breakT) / (1 - breakT);
    return breakV + (1 - breakV) * (u * u * (3 - 2 * u));
  }
}
