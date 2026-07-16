import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/audio/sfx_backend.dart';
import 'package:trude/core/audio/sfx_service.dart';
import 'package:trude/features/home/parlor_widgets.dart';

class _RecordingBackend implements SfxBackend {
  final List<SfxCue> played = [];
  int warmUps = 0;

  @override
  Future<void> warmUp() async {
    warmUps++;
  }

  @override
  void play(SfxCue cue) => played.add(cue);
}

void main() {
  group('SfxService slots', () {
    test('every slot forwards its distinct cue to the backend', () {
      final backend = _RecordingBackend();
      final sfx = SfxService(backend: backend);

      final slots = <SfxCue, void Function()>{
        SfxCue.shuffle: sfx.shuffle,
        SfxCue.cardThrow: sfx.cardThrow,
        SfxCue.cardLand: sfx.cardLand,
        SfxCue.claimStamp: sfx.claimStamp,
        SfxCue.revealTension: sfx.revealTension,
        SfxCue.cardSlide: sfx.cardSlide,
        SfxCue.flipSnap: sfx.flipSnap,
        SfxCue.verdictTruth: sfx.verdictTruth,
        SfxCue.verdictLie: sfx.verdictLie,
        SfxCue.pilePickup: sfx.pilePickup,
        SfxCue.quadFanfare: sfx.quadFanfare,
        SfxCue.jokerReveal: sfx.jokerReveal,
        SfxCue.yourTurn: sfx.yourTurn,
        SfxCue.timerUrgent: sfx.timerUrgent,
        SfxCue.reactionPop: sfx.reactionPop,
        SfxCue.uiTap: sfx.uiTap,
      };

      // One slot per cue — nothing missing, nothing doubled.
      expect(slots.keys.toSet(), SfxCue.values.toSet());

      slots.forEach((cue, slot) {
        backend.played.clear();
        slot();
        expect(backend.played, [cue], reason: 'slot for $cue');
      });
    });

    test('disabled gate blocks every backend call', () {
      final backend = _RecordingBackend();
      final sfx = SfxService(enabledOf: () => false, backend: backend);

      sfx.shuffle();
      sfx.cardThrow();
      sfx.cardLand();
      sfx.claimStamp();
      sfx.revealTension();
      sfx.cardSlide();
      sfx.flipSnap();
      sfx.verdictTruth();
      sfx.verdictLie();
      sfx.pilePickup();
      sfx.quadFanfare();
      sfx.jokerReveal();
      sfx.yourTurn();
      sfx.timerUrgent();
      sfx.reactionPop();
      sfx.uiTap();

      expect(backend.played, isEmpty);
      expect(sfx.enabled, isFalse);
    });

    test('gate re-reads the toggle on every call', () {
      final backend = _RecordingBackend();
      var on = true;
      final sfx = SfxService(enabledOf: () => on, backend: backend);

      sfx.uiTap();
      on = false;
      sfx.uiTap();
      on = true;
      sfx.uiTap();

      expect(backend.played, [SfxCue.uiTap, SfxCue.uiTap]);
    });

    test('defaults to enabled with a no-op backend', () {
      final sfx = SfxService();
      expect(sfx.enabled, isTrue);
      sfx.uiTap(); // Must not throw.
    });
  });

  group('SfxThrottle', () {
    test('blocks re-triggers inside the min interval, allows after', () {
      final throttle = SfxThrottle(minInterval: const Duration(milliseconds: 35));

      expect(throttle.shouldPlay(SfxCue.cardLand, Duration.zero), isTrue);
      expect(
          throttle.shouldPlay(
              SfxCue.cardLand, const Duration(milliseconds: 10)),
          isFalse);
      expect(
          throttle.shouldPlay(
              SfxCue.cardLand, const Duration(milliseconds: 34)),
          isFalse);
      expect(
          throttle.shouldPlay(
              SfxCue.cardLand, const Duration(milliseconds: 35)),
          isTrue);
    });

    test('blocked attempts do not extend the window', () {
      final throttle = SfxThrottle(minInterval: const Duration(milliseconds: 35));

      expect(throttle.shouldPlay(SfxCue.uiTap, Duration.zero), isTrue);
      // A blocked attempt at 30ms must not push the next allowance to 65ms.
      expect(
          throttle.shouldPlay(SfxCue.uiTap, const Duration(milliseconds: 30)),
          isFalse);
      expect(
          throttle.shouldPlay(SfxCue.uiTap, const Duration(milliseconds: 40)),
          isTrue);
    });

    test('cues are throttled independently', () {
      final throttle = SfxThrottle(minInterval: const Duration(milliseconds: 35));

      expect(throttle.shouldPlay(SfxCue.cardLand, Duration.zero), isTrue);
      expect(throttle.shouldPlay(SfxCue.cardThrow, Duration.zero), isTrue);
      expect(
          throttle.shouldPlay(
              SfxCue.cardThrow, const Duration(milliseconds: 5)),
          isFalse);
      expect(
          throttle.shouldPlay(SfxCue.uiTap, const Duration(milliseconds: 5)),
          isTrue);
    });
  });

  group('real backend degradation (VM, no plugin channels)', () {
    testWidgets('tapping a PressableScale plays uiTap through the real '
        'provider without surfacing any error', (tester) async {
      var taps = 0;
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          home: Center(
            child: PressableScale(
              onTap: () => taps++,
              child: const SizedBox(width: 80, height: 40),
            ),
          ),
        ),
      ));

      // First tap constructs the real PlayersSfxBackend (unawaited warmUp)
      // and fires uiTap; the second fires after warmUp settles.
      await tester.tap(find.byType(PressableScale));
      await tester.pumpAndSettle();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.tap(find.byType(PressableScale));
      await tester.pumpAndSettle();

      expect(taps, 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('cueForAssetFile', () {
    test('parses the naming convention', () {
      expect(cueForAssetFile('cardLand_1.ogg'), SfxCue.cardLand);
      expect(cueForAssetFile('verdictLie_2.wav'), SfxCue.verdictLie);
      expect(cueForAssetFile('uiTap_3.mp3'), SfxCue.uiTap);
    });

    test('rejects non-conforming files', () {
      expect(cueForAssetFile('README.md'), isNull);
      expect(cueForAssetFile('cardLand.ogg'), isNull); // No variant index.
      expect(cueForAssetFile('cardLand_x.ogg'), isNull); // Non-numeric index.
      expect(cueForAssetFile('notACue_1.ogg'), isNull);
    });
  });
}
