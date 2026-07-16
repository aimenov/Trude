// AnimationQueue behavior: sequential timed steps with cosmetic ticks,
// tap-to-skip, and reduce-motion collapsing everything to instant.

import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/motion/animation_speed.dart';
import 'package:trude/core/net/client_game_state.dart';
import 'package:trude/core/net/protocol_models.dart';
import 'package:trude/features/game/anim/animation_queue.dart';
import 'package:trude/features/game/anim/event_steps.dart';
import 'package:trude/features/game/anim/motion_jitter.dart';

/// Makes MotionJitter deterministic: every signed sample is 0 (no jitter).
class _CenteredRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0.5;

  @override
  int nextInt(int max) => max ~/ 2;
}

PlayerView _player(int seat, {int count = 5}) => PlayerView(
      userId: 'u$seat',
      nickname: 'P$seat',
      avatar: '',
      seat: seat,
      cardCount: count,
      connected: true,
      autoPilot: false,
      isOut: false,
      isAdmin: seat == 0,
    );

ClientGameState _twoPlayerState() => ClientGameState(
      roomPhase: 'playing',
      players: [_player(0), _player(1)],
      mySeat: 0,
    );

EventBatch _throwBatch() => EventBatch.fromJson({
      'actionCount': 1,
      'events': [
        {
          'type': 'cardsThrown',
          'seat': 1,
          'count': 2,
          'rank': '7',
          'isLead': true,
        },
        {
          'type': 'turnStarted',
          'seat': 0,
          'phase': 'respond',
          'mustCheck': false,
          'deadlineTs': 99999,
        },
      ],
    });

List<AnimStep> _steps(EventBatch batch) => stepsForBatch(
      batch,
      myUserId: 'u0',
      jitter: MotionJitter(_CenteredRandom()),
    );

void main() {
  group('AnimationQueue', () {
    test('orders and completes steps for a synthetic batch', () {
      fakeAsync((async) {
        final queue = AnimationQueue(
          speedOf: () => AnimationSpeed.normal,
          initial: _twoPlayerState(),
        );
        final startedKinds = <StepKind>[];
        queue.onStepStarted.listen((s) => startedKinds.add(s.step.kind));

        queue.enqueue(_steps(_throwBatch()));
        async.flushMicrotasks();

        // Timed step running; nothing has landed yet.
        expect(queue.busy, isTrue);
        expect(queue.rendered.pileCount, 0);
        expect(queue.rendered.playerAtSeat(1)!.cardCount, 5);
        // The trailing turnStarted must NOT have applied out of order.
        expect(queue.rendered.turn, isNull);

        // First card lands (flight 380 ms): chip ticks down, pile ticks up.
        async.elapse(const Duration(milliseconds: 400));
        expect(queue.rendered.pileCount, 1);
        expect(queue.rendered.playerAtSeat(1)!.cardCount, 4);
        expect(queue.rendered.pileRank, '7');

        // Second card lands at 450 ms.
        async.elapse(const Duration(milliseconds: 80));
        expect(queue.rendered.pileCount, 2);
        expect(queue.rendered.playerAtSeat(1)!.cardCount, 3);

        // Step completes at 570 ms; the instant turnStarted then applies.
        async.elapse(const Duration(milliseconds: 120));
        expect(queue.busy, isFalse);
        expect(queue.rendered.pileCount, 2);
        expect(queue.rendered.playerAtSeat(1)!.cardCount, 3);
        expect(queue.rendered.turn, isNotNull);
        expect(queue.rendered.turn!.seat, 0);
        expect(startedKinds, [StepKind.throwCards]);

        queue.dispose();
      });
    });

    test('skip-to-end completes everything instantly', () {
      fakeAsync((async) {
        final queue = AnimationQueue(
          speedOf: () => AnimationSpeed.normal,
          initial: _twoPlayerState(),
        );
        var skipped = false;
        queue.onSkipped.listen((_) => skipped = true);

        queue.enqueue(_steps(_throwBatch()));
        async.flushMicrotasks();
        expect(queue.busy, isTrue);

        queue.skipToEnd(); // the tap-anywhere handler

        expect(queue.busy, isFalse);
        expect(queue.rendered.pileCount, 2);
        expect(queue.rendered.playerAtSeat(1)!.cardCount, 3);
        expect(queue.rendered.turn!.seat, 0);
        async.flushMicrotasks();
        expect(skipped, isTrue);

        // No timers left running.
        async.elapse(const Duration(seconds: 10));
        expect(queue.rendered.pileCount, 2);

        queue.dispose();
      });
    });

    test('reveal + pickup steps run sequentially and converge', () {
      fakeAsync((async) {
        final initial = _twoPlayerState().copyWith(
          pileRank: '7',
          pileCount: 6,
          lastThrowCount: 2,
          lastThrowSeat: 1,
        );
        final queue = AnimationQueue(
          speedOf: () => AnimationSpeed.normal,
          initial: initial,
        );
        final batch = EventBatch.fromJson({
          'actionCount': 2,
          'events': [
            {
              'type': 'checkResult',
              'checkerSeat': 0,
              'targetSeat': 1,
              'flipIndex': 1,
              'flipped': {'id': 'c9', 'rank': 'K', 'suit': 'S'},
              'matched': false,
              'pickerSeat': 1,
              'pickedCount': 6,
              'nextLeadSeat': 0,
            },
          ],
        });
        queue.enqueue(stepsForBatch(batch,
            myUserId: 'u0', jitter: MotionJitter(_CenteredRandom())));
        async.flushMicrotasks();

        // During the reveal the pile stays put.
        async.elapse(const Duration(milliseconds: 1000));
        expect(queue.rendered.pileCount, 6);
        expect(queue.rendered.playerAtSeat(1)!.cardCount, 5);

        // Let reveal (2700 ms) and pickup drain fully.
        async.elapse(const Duration(seconds: 5));
        expect(queue.busy, isFalse);
        expect(queue.rendered.pileCount, 0);
        expect(queue.rendered.playerAtSeat(1)!.cardCount, 11);
        expect(queue.rendered.pileRank, isNull);

        queue.dispose();
      });
    });

    test('reduce motion (speed off) collapses every duration to zero', () {
      expect(AnimationSpeed.off.scale(const Duration(seconds: 3)),
          Duration.zero);
      expect(
          AnimationSpeed.fast
              .scale(const Duration(milliseconds: 1000))
              .inMilliseconds,
          600);

      fakeAsync((async) {
        final queue = AnimationQueue(
          speedOf: () => AnimationSpeed.off,
          initial: _twoPlayerState(),
        );
        queue.enqueue(_steps(_throwBatch()));

        // Applied synchronously — no time elapsed, no busy window.
        expect(queue.busy, isFalse);
        expect(queue.rendered.pileCount, 2);
        expect(queue.rendered.playerAtSeat(1)!.cardCount, 3);
        expect(queue.rendered.turn!.seat, 0);

        queue.dispose();
      });
    });
  });
}
