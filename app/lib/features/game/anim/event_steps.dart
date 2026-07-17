/// Maps server event batches to [AnimStep]s for the [AnimationQueue].
///
/// Each step's final `apply` delegates to the shared fold (state_folding.dart)
/// so the rendered state always converges with the true state; the ticks in
/// between are the cosmetic part — count chips ticking as each flying card
/// lands rather than on batch arrival.
library;

import 'dart:math';

import '../../../core/net/client_game_state.dart';
import '../../../core/net/protocol_models.dart';
import '../../../core/net/state_folding.dart';
import 'animation_queue.dart';
import 'motion_jitter.dart';
import 'motion_spec.dart';

/// Ticks scheduled at exactly 1.0 would race the step-end timer; land them
/// just inside the step instead (the final apply overwrites them anyway).
const _maxTickAt = 0.98;

List<AnimStep> stepsForBatch(
  EventBatch batch, {
  required String? myUserId,
  MotionJitter? jitter,
}) {
  final j = jitter ?? motionJitter;
  final steps = <AnimStep>[];
  for (final event in batch.events) {
    steps.addAll(_stepsForEvent(event, myUserId: myUserId, jitter: j));
  }
  return steps;
}

/// A hand snapshot rides the queue as an instant step so my rendered hand
/// updates after the animations that explain it (deal, pickup), not before.
AnimStep handSnapshotStep(HandSnapshot h) =>
    AnimStep.instant((s) => s.copyWith(myHand: h.cards));

List<AnimStep> _stepsForEvent(
  WireEvent event, {
  required String? myUserId,
  required MotionJitter jitter,
}) {
  ClientGameState fold(ClientGameState s) =>
      applyEventTo(s, event, myUserId: myUserId);

  switch (event) {
    case GameStartedEvent():
      return [_dealStep(event, fold, jitter)];
    case CardsThrownEvent():
      return [_throwStep(event, fold, jitter)];
    case CheckResultEvent():
      return _checkResultSteps(event, fold, jitter);
    case FourDiscardedEvent():
      return [
        AnimStep(
          kind: StepKind.quad,
          event: event,
          baseDuration: jitter.duration(MotionSpec.quadTotal),
          apply: fold,
          // The four cards leave the hand as the square assembles.
          ticks: [
            StepTick(
                MotionSpec.quadAssembleEnd / 2,
                (s) => s.copyWith(
                    players: updateSeat(
                        s.players,
                        event.seat,
                        (p) => p.copyWith(
                            cardCount:
                                max(0, p.cardCount - event.cards.length))))),
          ],
        ),
      ];
    case PlayerOutEvent():
      return [
        AnimStep(
          kind: StepKind.playerOut,
          event: event,
          baseDuration: MotionSpec.playerOutStep,
          apply: fold,
        ),
      ];
    case GameOverEvent():
      return [
        AnimStep(
          kind: StepKind.gameOver,
          event: event,
          baseDuration: MotionSpec.gameOverTotal,
          apply: fold,
        ),
      ];
    // turnStarted and all lobby/meta events render instantly.
    case TurnStartedEvent():
    case GenericEvent():
      return [AnimStep.instant(fold, event: event)];
  }
}

// -- Deal ---------------------------------------------------------------------

AnimStep _dealStep(
  GameStartedEvent event,
  ClientGameState Function(ClientGameState) fold,
  MotionJitter jitter,
) {
  final order = dealOrder(event.handCounts);
  final total = order.length;
  final schedule = dealSchedule(total);

  // Card counts start from zero and tick up per landing card.
  ClientGameState zeroCounts(ClientGameState s) {
    final started = fold(s);
    return started.copyWith(
        players: [for (final p in started.players) p.copyWith(cardCount: 0)]);
  }

  ClientGameState addOne(ClientGameState s, int seat) => s.copyWith(
      players:
          updateSeat(s.players, seat, (p) => p.copyWith(cardCount: p.cardCount + 1)));

  return AnimStep(
    kind: StepKind.deal,
    event: event,
    baseDuration: schedule.total,
    apply: fold,
    ticks: [
      StepTick(0, zeroCounts),
      for (var k = 0; k < total; k++)
        StepTick(
          min(_maxTickAt,
              schedule.landingMs(k) / schedule.total.inMilliseconds),
          (s) => addOne(s, order[k]),
        ),
    ],
  );
}

/// Deal order: cards leave the deck round-robin across seats until every
/// seat has its dealt count.
List<int> dealOrder(List<int> handCounts) {
  final order = <int>[];
  var round = 0;
  var remaining = handCounts.fold(0, (a, b) => a + b);
  while (remaining > 0 && round < 64) {
    for (var seat = 0; seat < handCounts.length; seat++) {
      if (handCounts[seat] > round) {
        order.add(seat);
        remaining--;
      }
    }
    round++;
  }
  return order;
}

/// Accelerating launch schedule of the deal spray, capped to fit
/// [MotionSpec.dealTotalCap].
class DealSchedule {
  DealSchedule(this.total, this._sprayMs, this._count);

  final Duration total;
  final double _sprayMs;
  final int _count;

  double launchMs(int k) => _count <= 1
      ? 0
      : _sprayMs * pow(k / (_count - 1), MotionSpec.dealAccel).toDouble();

  double landingMs(int k) =>
      launchMs(k) + MotionSpec.dealFlight.inMilliseconds;
}

DealSchedule dealSchedule(int cardCount) {
  final sprayMs = min(
    (MotionSpec.dealTotalCap - MotionSpec.dealFlight).inMilliseconds,
    MotionSpec.dealStagger.inMilliseconds * cardCount,
  ).toDouble();
  final total = Duration(
      milliseconds:
          (sprayMs + MotionSpec.dealFlight.inMilliseconds).round());
  return DealSchedule(total, sprayMs, cardCount);
}

// -- Throw ------------------------------------------------------------------

AnimStep _throwStep(
  CardsThrownEvent event,
  ClientGameState Function(ClientGameState) fold,
  MotionJitter jitter,
) {
  final n = event.count;
  final totalMs = MotionSpec.cardFlight.inMilliseconds +
      MotionSpec.throwStagger.inMilliseconds * (n - 1) +
      MotionSpec.throwSettle.inMilliseconds;

  ClientGameState landOne(ClientGameState s, int landedSoFar) => s.copyWith(
        players: updateSeat(s.players, event.seat,
            (p) => p.copyWith(cardCount: max(0, p.cardCount - 1))),
        pileRank: event.rank,
        pileCount: (event.isLead && landedSoFar == 0 ? 0 : s.pileCount) + 1,
        lastThrowSeat: event.seat,
        lastThrowCount: landedSoFar + 1,
      );

  return AnimStep(
    kind: StepKind.throwCards,
    event: event,
    baseDuration: jitter.duration(Duration(milliseconds: totalMs)),
    apply: fold,
    ticks: [
      for (var i = 0; i < n; i++)
        StepTick(
          min(
              _maxTickAt,
              (MotionSpec.cardFlight.inMilliseconds +
                      MotionSpec.throwStagger.inMilliseconds * i) /
                  totalMs),
          (s) => landOne(s, i),
        ),
    ],
  );
}

// -- Check result: reveal, then pickup -----------------------------------------

List<AnimStep> _checkResultSteps(
  CheckResultEvent event,
  ClientGameState Function(ClientGameState) fold,
  MotionJitter jitter,
) {
  // Reveal is a pure timing step: pile/counts stay put while the flip plays
  // center-stage. The pickup step then applies the full fold, so
  // reveal+pickup compose to exactly the shared fold.
  final revealStep = AnimStep(
    kind: StepKind.reveal,
    event: event,
    baseDuration: MotionSpec.revealTotal,
    // The verdict set piece must always play out — a stray tap can't skip it.
    skippable: false,
    apply: (s) => s,
  );

  final flights = min(event.pickedCount, MotionSpec.pileRenderCap);
  final baseMs = MotionSpec.pickupBase.inMilliseconds +
      MotionSpec.pickupStagger.inMilliseconds * pickupStaggeredCount(event.pickedCount);
  final totalMs = min(baseMs, MotionSpec.pickupCap.inMilliseconds);

  // Split pickedCount across the rendered flights so the chip ramps to the
  // exact total even when the pile exceeds the render cap.
  final shares = _splitEvenly(event.pickedCount, max(1, flights));

  ClientGameState transfer(ClientGameState s, int amount) => s.copyWith(
        pileCount: max(0, s.pileCount - amount),
        players: updateSeat(s.players, event.pickerSeat,
            (p) => p.copyWith(cardCount: p.cardCount + amount)),
      );

  final pickupStep = AnimStep(
    kind: StepKind.pickup,
    event: event,
    baseDuration: jitter.duration(Duration(milliseconds: totalMs)),
    apply: fold,
    ticks: [
      for (var i = 0; i < shares.length; i++)
        StepTick(
          min(
              _maxTickAt,
              (MotionSpec.pickupBase.inMilliseconds +
                      MotionSpec.pickupStagger.inMilliseconds * i) /
                  totalMs),
          (s) => transfer(s, shares[i]),
        ),
    ],
  );

  // Identity pause after the pickup so the next turn never renders on its
  // heels. The pickup itself stays skippable (escape hatch during up to
  // 1600 ms of flights); the skip drain stops here, so the pause always plays.
  final holdStep = AnimStep(
    kind: StepKind.hold,
    event: event,
    baseDuration: MotionSpec.checkHold,
    apply: (s) => s,
    skippable: false,
  );

  return [revealStep, pickupStep, holdStep];
}

/// Sub-linear stagger count: piles bigger than twice the render cap don't
/// stretch the pickup any further.
int pickupStaggeredCount(int pileCount) =>
    min(pileCount, MotionSpec.pileRenderCap * 2);

List<int> _splitEvenly(int total, int parts) {
  final base = total ~/ parts;
  final extra = total % parts;
  return [for (var i = 0; i < parts; i++) base + (i < extra ? 1 : 0)];
}
