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

  // -- Ballistic flight (thrown, not tweened) -----------------------------------

  /// Fraction of the flight (in time AND straight-line distance) at which the
  /// card touches down; the remainder is the friction slide into the exact
  /// target pose, so physics feel never sacrifices landing exactness.
  static const ballisticTouchdownAt = 0.85;

  /// Normalized stiffness of the critically-damped steering spring:
  /// omega = ballisticSpringOmega / airborne-time. The spring's damping term
  /// doubles as the light aerodynamic drag on the launch velocity.
  static const ballisticSpringOmega = 5.0;

  /// Hard wall cap per flight — a flight can never outlive its AnimationQueue
  /// step schedule, so the queue never stalls on a runaway flight.
  static const ballisticFlightCap = Duration(milliseconds: 900);

  /// Synthesized launch speed relative to the straight-line pace (>1 = thrown
  /// hard; the spring bleeds off the excess like drag).
  static const ballisticLaunchBoost = 1.55;

  /// Upward bias mixed into synthesized launch directions (toss arc).
  static const ballisticLoft = 0.38;

  /// MotionJitter variance of synthesized launches: aim (degrees) and speed
  /// (fraction) — no two throws are ever identical.
  static const ballisticAimJitterDeg = 7.0;
  static const ballisticSpeedJitter = 0.16;

  /// Angular-velocity variance (fraction) and the residual tumble (radians
  /// over one flight) given to flights that request no spin.
  static const ballisticSpinJitter = 0.35;
  static const ballisticIdleSpin = 0.5;

  /// Airborne scale-up at the apex (height illusion).
  static const ballisticApexScale = 0.08;

  /// Touchdown squash: the scaleY dip and the fraction of the flight it lasts
  /// (~1-2 frames at normal speed).
  static const ballisticSquashScaleY = 0.96;
  static const ballisticSquashSpan = 0.07;

  /// Friction slide over the last stretch: decelerating into the pose.
  static const ballisticSlideCurve = Curves.easeOutCubic;

  /// Airborne soft shadow: max offset (dp), alpha, and blur ramp with height.
  static const ballisticShadowDropX = 3.0;
  static const ballisticShadowDropY = 8.0;
  static const ballisticShadowAlpha = 0.30;
  static const ballisticShadowBlurGround = 3.0;
  static const ballisticShadowBlurAir = 12.0;

  // -- Flick-to-throw -------------------------------------------------------------

  /// Upward release speed (dp/s) at/above which a hand drag becomes a throw.
  static const flickThrowSpeed = 700.0;

  /// Minimum upward velocity COMPONENT (dp/s) of an accepted flick release.
  /// The total-speed gate is [flickThrowSpeed]; this only rejects releases
  /// that do not read as upward at all, so diagonal flicks (natural from the
  /// fan's edge cards toward the pile) still throw.
  static const flickThrowUpComponent = 250.0;

  /// Minimum upward travel (dp) before a release may throw.
  static const flickMinDrag = 24.0;

  /// Upward-dominance gate of the strip-level flick recognizer's ACCEPTANCE:
  /// the pointer is claimed only while its cumulative movement has dy < 0
  /// and |dy| >= this fraction of |dx|. Shallower (scroll-like) drags are
  /// never accepted, leaving the arena to the hand ListView and card taps.
  static const flickUpDominance = 0.6;

  /// Clamp of the handed-off flick launch speed (dp/s).
  static const flickLaunchSpeedMin = 900.0;
  static const flickLaunchSpeedMax = 2600.0;

  /// Per-card aim spread (degrees) when several cards share one flick.
  static const flickSpreadDeg = 4.0;

  /// How long a published flick velocity stays valid while the throw makes
  /// its server roundtrip.
  static const flickHandoffWindow = Duration(milliseconds: 3500);

  /// Slop (dp) around the hand rect when matching a departing flight to the
  /// pending flick.
  static const flickSourceSlop = 32.0;

  /// Drag-follow feel: lead-card follow fraction, per-card lag among the
  /// selection (and its floor), horizontal follow, downward rubber-band,
  /// tilt toward the drag direction, and the airborne lift scale.
  static const flickFollow = 0.9;
  static const flickFollowLagPerCard = 0.11;
  static const flickFollowFloor = 0.4;
  static const flickFollowDx = 0.6;
  static const flickDownRubberBand = 0.25;
  static const flickMaxDown = 14.0; // dp below the fan
  static const flickTiltPerDx = 0.004; // rad per dp of horizontal drift
  static const flickTiltLagBoost = 0.3; // trailing cards tilt a touch more
  static const flickMaxTilt = 0.24; // rad
  static const flickLiftScale = 0.05;
  static const flickLiftDistance = 70.0; // dp of upward drag for full lift

  /// Spring-back to the fan after a sub-threshold release.
  static const flickSpringBack = Duration(milliseconds: 240);
  static const flickSpringBackCurve = Curves.easeOutBack;

  // -- Pile nudge (landing impulse) -------------------------------------------------

  /// A landing card physically nudges the top resting pile cards.
  static const pileNudge = Duration(milliseconds: 250);
  static const pileNudgeCards = 3;
  static const pileNudgeMaxOffset = 2.6; // dp, top card
  static const pileNudgeMaxAngleDeg = 1.2; // degrees, top card
  /// Amplitude falloff per card deeper in the stack.
  static const pileNudgeFalloff = 0.55;
  /// Cosine cycles of the damped wiggle across the nudge window.
  static const pileNudgeWiggle = 1.4;
}

/// Table-lane motion constants (environment + set-piece restage). A separate
/// namespace so concurrent additions to [MotionSpec] can never collide.
abstract final class TableMotionSpec {
  // -- Felt candlelight (idle life of the table light pool) --------------------

  /// One full warm-flicker cycle of the light pool.
  static const feltFlickerPeriod = Duration(seconds: 7);

  /// Radius modulation of the light pool (fraction of the base radius).
  static const feltFlickerRadiusDelta = 0.02;

  /// Center drift of the light pool, in alignment units.
  static const feltFlickerDriftAmp = 0.03;

  // -- Reveal restage -----------------------------------------------------------

  /// Peak opacity of the deepened reveal dim (was a lighter vignette).
  static const revealDimDeep = 0.55;

  /// Peak alpha of the candle-spot behind the flipped card.
  static const revealSpotMaxAlpha = 0.22;

  /// Portion of the verdict phase spent flashing the ink splat in.
  static const inkSplatIn = 0.30;

  // -- Claim plaque slam ----------------------------------------------------------

  /// The plaque starts this much larger and slams down to 1.0.
  static const calloutSlamScale = 1.45;

  // -- Quad celebration -------------------------------------------------------------

  /// Brass glint particles twinkling around the framed square.
  static const quadGlintCount = 14;

  // -- Game-over theater bow ----------------------------------------------------

  static const gameOverBowStart = 0.55; // fraction of the step
  static const gameOverBowEnd = 0.88;
  static const gameOverBowDip = 0.26; // rad, deepest tilt of the bow
  static const gameOverBowRest = 0.10; // rad, the tilt it settles into

  // -- Emoji burst ring pop --------------------------------------------------------

  static const emojiRingPopLife = Duration(milliseconds: 380);
  static const emojiRingPopRadius = 30.0; // dp, final ring radius
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
