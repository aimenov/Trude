import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/haptics/haptics_service.dart';

/// Records every primitive invocation; pattern capability and failure modes
/// are configurable per test.
class _RecordingPrimitives extends HapticsPrimitives {
  _RecordingPrimitives({
    this.patternCapable = false,
    this.probeThrows = false,
    this.vibrateThrows = false,
  });

  bool patternCapable;
  bool probeThrows;
  bool vibrateThrows;
  int probes = 0;
  final List<String> calls = [];
  final List<(List<int>, List<int>)> patterns = [];

  @override
  void lightImpact() => calls.add('lightImpact');
  @override
  void mediumImpact() => calls.add('mediumImpact');
  @override
  void heavyImpact() => calls.add('heavyImpact');
  @override
  void selectionClick() => calls.add('selectionClick');
  @override
  void successNotification() => calls.add('successNotification');
  @override
  void warningNotification() => calls.add('warningNotification');

  @override
  Future<bool> canVibratePattern() async {
    probes++;
    if (probeThrows) throw StateError('probe boom');
    return patternCapable;
  }

  @override
  Future<void> vibratePattern(List<int> pattern, List<int> intensities) async {
    if (vibrateThrows) throw StateError('vibrate boom');
    calls.add('vibratePattern');
    patterns.add((pattern, intensities));
  }
}

void main() {
  group('HapticsService gate', () {
    test('disabled gate blocks every primitive, including heartbeat',
        () async {
      final primitives = _RecordingPrimitives(patternCapable: true);
      final haptics =
          HapticsService(enabledOf: () => false, primitives: primitives);

      haptics.light();
      haptics.medium();
      haptics.heavy();
      haptics.selection();
      haptics.heartbeat();
      haptics.success();
      haptics.warning();

      // Let any (wrongly) scheduled heartbeat work drain.
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(primitives.calls, isEmpty);
      expect(primitives.probes, 0);
      expect(haptics.enabled, isFalse);
    });

    test('gate re-reads the toggle on every call', () {
      final primitives = _RecordingPrimitives();
      var on = true;
      final haptics =
          HapticsService(enabledOf: () => on, primitives: primitives);

      haptics.light();
      on = false;
      haptics.light();
      on = true;
      haptics.light();

      expect(primitives.calls, ['lightImpact', 'lightImpact']);
    });
  });

  group('semantic-to-primitive mapping', () {
    test('each discrete method forwards to exactly its primitive', () {
      final primitives = _RecordingPrimitives();
      final haptics = HapticsService(primitives: primitives);

      final mapping = <String, void Function()>{
        'lightImpact': haptics.light,
        'mediumImpact': haptics.medium,
        'heavyImpact': haptics.heavy,
        'selectionClick': haptics.selection,
        'successNotification': haptics.success,
        'warningNotification': haptics.warning,
      };

      mapping.forEach((primitive, method) {
        primitives.calls.clear();
        method();
        expect(primitives.calls, [primitive], reason: 'mapping of $primitive');
      });
    });
  });

  group('heartbeat', () {
    test('uses the plugin pattern when the device is capable, probing once',
        () {
      fakeAsync((async) {
        final primitives = _RecordingPrimitives(patternCapable: true);
        final haptics = HapticsService(primitives: primitives);

        haptics.heartbeat();
        async.elapse(const Duration(milliseconds: 500));
        haptics.heartbeat();
        async.elapse(const Duration(milliseconds: 500));

        expect(primitives.calls, ['vibratePattern', 'vibratePattern']);
        expect(primitives.patterns.first.$1, [0, 60, 90, 90]);
        expect(primitives.patterns.first.$2, [0, 160, 0, 96]);
        expect(primitives.probes, 1, reason: 'capability cached after probe');
      });
    });

    test('falls back to a two-pulse SDK sequence when pattern-incapable', () {
      fakeAsync((async) {
        final primitives = _RecordingPrimitives(patternCapable: false);
        final haptics = HapticsService(primitives: primitives);

        haptics.heartbeat();
        async.flushMicrotasks();
        expect(primitives.calls, ['mediumImpact'],
            reason: 'first beat fires immediately');

        async.elapse(const Duration(milliseconds: 139));
        expect(primitives.calls, ['mediumImpact'],
            reason: 'second beat waits out the gap');

        async.elapse(const Duration(milliseconds: 1));
        expect(primitives.calls, ['mediumImpact', 'lightImpact']);
      });
    });

    test('falls back when the capability probe throws', () {
      fakeAsync((async) {
        final primitives = _RecordingPrimitives(probeThrows: true);
        final haptics = HapticsService(primitives: primitives);

        haptics.heartbeat();
        async.elapse(const Duration(milliseconds: 500));

        expect(primitives.calls, ['mediumImpact', 'lightImpact']);
      });
    });

    test('falls back when the pattern call itself throws', () {
      fakeAsync((async) {
        final primitives = _RecordingPrimitives(
            patternCapable: true, vibrateThrows: true);
        final haptics = HapticsService(primitives: primitives);

        haptics.heartbeat();
        async.elapse(const Duration(milliseconds: 500));

        expect(primitives.calls, ['mediumImpact', 'lightImpact']);
      });
    });
  });

  group('real primitives degradation (VM, no plugin channels)', () {
    test('every method — heartbeat included — completes without throwing',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final haptics = HapticsService();

      haptics.light();
      haptics.medium();
      haptics.heavy();
      haptics.selection();
      haptics.heartbeat();
      haptics.success();
      haptics.warning();

      // On this VM the vibration probe resolves false (not Android/iOS), so
      // heartbeat takes the SDK fallback: give its 140ms gap time to run.
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
  });
}
