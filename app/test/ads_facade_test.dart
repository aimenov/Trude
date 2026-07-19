/// Ads facade tests: the no-op paths never throw, the plugin-backed backend
/// bricks itself safely under VM tests (the MissingPluginException probe),
/// and AdsService's earn flow posts /ads/reward exactly once per watched ad.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/ads/ads_backend.dart';
import 'package:trude/core/ads/ads_backend_factory.dart';
import 'package:trude/core/ads/ads_backend_google.dart';
import 'package:trude/core/ads/ads_service.dart';
import 'package:trude/core/net/trude_client.dart';

class _FakeAdsBackend implements AdsBackend {
  _FakeAdsBackend({this.reward});

  /// What showRewarded hands back (null = user bailed / nothing shown).
  AdReward? reward;

  final ValueNotifier<bool> ready = ValueNotifier<bool>(true);
  bool inited = false;
  int preloads = 0;
  int shows = 0;

  @override
  bool get supported => true;

  @override
  ValueListenable<bool> get rewardedReady => ready;

  @override
  Future<void> init() async => inited = true;

  @override
  Future<void> preloadRewarded() async => preloads++;

  @override
  Future<AdReward?> showRewarded() async {
    shows++;
    return reward;
  }

  @override
  Future<void> dispose() async {}
}

/// Records token fetches / reward posts like the transport fakes elsewhere.
class _FakeAdsApi {
  _FakeAdsApi({this.remainingToday = 5});

  int remainingToday;
  int fetches = 0;
  final List<String> postedTokens = [];

  /// Exceptions to throw from postReward before succeeding, FIFO.
  final List<Exception> postFailures = [];

  AdsTokenFetch get fetchToken => (kind, {gameId}) async {
        fetches++;
        return AdsTokenInfo(
          token: 'tok$fetches',
          remainingToday: remainingToday,
        );
      };

  AdsRewardPost get postReward => (token) async {
        postedTokens.add(token);
        if (postFailures.isNotEmpty) {
          throw postFailures.removeAt(0);
        }
        return AdEarnResult(
          coins: 25,
          balance: 100,
          remainingToday: remainingToday - 1,
        );
      };
}

AdsService _service(_FakeAdsBackend backend, _FakeAdsApi api) => AdsService(
      backend: backend,
      fetchToken: api.fetchToken,
      postReward: api.postReward,
      retryBaseDelay: Duration.zero,
    );

void main() {
  group('NoopAdsBackend', () {
    test('is inert and never throws', () async {
      const backend = NoopAdsBackend();
      expect(backend.supported, isFalse);
      expect(backend.rewardedReady.value, isFalse);
      await backend.init();
      await backend.preloadRewarded();
      expect(await backend.showRewarded(), isNull);
      await backend.dispose();
    });

    test('AlwaysFalseListenable accepts and ignores listeners', () {
      const listenable = AlwaysFalseListenable();
      void listener() {}
      listenable.addListener(listener);
      listenable.removeListener(listener);
      expect(listenable.value, isFalse);
    });
  });

  group('GoogleAdsBackend under VM tests', () {
    // VM tests report an android platform, so the io factory really does
    // hand out the plugin-backed backend here — proving the init probe
    // (catchable MissingPluginException -> broken forever) is the load-
    // bearing safety, exactly like PlayersSfxBackend.warmUp.
    testWidgets('factory picks the google backend (android platform)',
        (tester) async {
      expect(defaultTargetPlatform, TargetPlatform.android);
      expect(createAdsBackend(), isA<GoogleAdsBackend>());
    });

    testWidgets('init probe marks it broken instead of throwing',
        (tester) async {
      // runAsync is load-bearing: the missing-plugin reply for the platform
      // message arrives on the REAL event loop. Under the test body's
      // FakeAsync zone that reply is never pumped, so a bare `await
      // backend.init()` would deadlock instead of catching
      // MissingPluginException.
      await tester.runAsync(() async {
        final backend = GoogleAdsBackend();
        await backend.init(); // must not throw without plugin channels
        expect(backend.supported, isFalse);
        expect(backend.rewardedReady.value, isFalse);
        await backend.preloadRewarded(); // no-op, no throw
        expect(await backend.showRewarded(), isNull);
        await backend.dispose();
      });
    });
  });

  group('AdsService with the no-op backend', () {
    test('never touches the network and never throws', () async {
      var fetches = 0;
      var posts = 0;
      final service = AdsService(
        backend: const NoopAdsBackend(),
        fetchToken: (kind, {gameId}) async {
          fetches++;
          return const AdsTokenInfo(token: 't', remainingToday: 5);
        },
        postReward: (token) async {
          posts++;
          return const AdEarnResult(coins: 25, balance: 25, remainingToday: 4);
        },
      );
      await service.init();
      expect(service.supported, isFalse);
      expect(service.canOffer('shop'), isFalse);
      await service.prepare('shop');
      expect(await service.earn('shop'), isNull);
      expect(fetches, 0);
      expect(posts, 0);
      await service.dispose();
    });
  });

  group('AdsService.earn', () {
    test('earned reward posts /ads/reward exactly once', () async {
      final backend = _FakeAdsBackend(reward: const AdReward(amount: 1));
      final api = _FakeAdsApi();
      final service = _service(backend, api);

      final result = await service.earn('shop');

      expect(result, isNotNull);
      expect(result!.coins, 25);
      expect(result.balance, 100);
      expect(backend.shows, 1);
      expect(api.postedTokens, ['tok1'], reason: 'exactly one POST');
      expect(service.remainingToday('shop'), 4);
    });

    test('dismiss before earning posts nothing and keeps the token',
        () async {
      final backend = _FakeAdsBackend(); // showRewarded -> null
      final api = _FakeAdsApi();
      final service = _service(backend, api);

      expect(await service.earn('shop'), isNull);
      expect(backend.shows, 1);
      expect(api.postedTokens, isEmpty);
      expect(api.fetches, 1);

      // Next tap reuses the cached token instead of re-fetching.
      backend.reward = const AdReward(amount: 1);
      final result = await service.earn('shop');
      expect(result, isNotNull);
      expect(api.postedTokens, ['tok1']);
    });

    test('transient POST failures retry with a cap of 3 attempts', () async {
      final backend = _FakeAdsBackend(reward: const AdReward(amount: 1));
      final api = _FakeAdsApi()
        ..postFailures.addAll([Exception('net'), Exception('net')]);
      final service = _service(backend, api);

      final result = await service.earn('shop');
      expect(result, isNotNull);
      expect(api.postedTokens.length, 3, reason: '2 failures + 1 success');
    });

    test('three transient failures give up with null, never throw', () async {
      final backend = _FakeAdsBackend(reward: const AdReward(amount: 1));
      final api = _FakeAdsApi()
        ..postFailures
            .addAll([Exception('a'), Exception('b'), Exception('c')]);
      final service = _service(backend, api);

      expect(await service.earn('shop'), isNull);
      expect(api.postedTokens.length, 3);
    });

    test('4xx is permanent: a single POST, no retries', () async {
      final backend = _FakeAdsBackend(reward: const AdReward(amount: 1));
      final api = _FakeAdsApi()
        ..postFailures.add(TrudeApiException(409, '{"error":"TOKEN_USED"}'));
      final service = _service(backend, api);

      expect(await service.earn('shop'), isNull);
      expect(api.postedTokens.length, 1);
    });

    test('429 marks the kind capped', () async {
      final backend = _FakeAdsBackend(reward: const AdReward(amount: 1));
      final api = _FakeAdsApi()
        ..postFailures.add(TrudeApiException(429, '{"error":"DAILY_CAP"}'));
      final service = _service(backend, api);

      expect(await service.earn('shop'), isNull);
      expect(service.remainingToday('shop'), 0);
      expect(service.canOffer('shop'), isFalse);
    });

    test('server-reported zero headroom skips the ad entirely', () async {
      final backend = _FakeAdsBackend(reward: const AdReward(amount: 1));
      final api = _FakeAdsApi(remainingToday: 0);
      final service = _service(backend, api);

      expect(await service.earn('shop'), isNull);
      expect(backend.shows, 0);
      expect(api.postedTokens, isEmpty);
      expect(service.canOffer('shop'), isFalse);
    });

    test('token fetch failure resolves null, never throws', () async {
      final backend = _FakeAdsBackend(reward: const AdReward(amount: 1));
      final service = AdsService(
        backend: backend,
        fetchToken: (kind, {gameId}) async => throw Exception('offline'),
        postReward: (token) async =>
            const AdEarnResult(coins: 25, balance: 25, remainingToday: 4),
        retryBaseDelay: Duration.zero,
      );
      expect(await service.earn('shop'), isNull);
      expect(backend.shows, 0);
    });

    test('not-ready backend is a silent no-op', () async {
      final backend = _FakeAdsBackend(reward: const AdReward(amount: 1));
      backend.ready.value = false;
      final api = _FakeAdsApi();
      final service = _service(backend, api);

      expect(await service.earn('shop'), isNull);
      expect(api.fetches, 0);
      expect(backend.shows, 0);
    });
  });

  group('AdsService.prepare', () {
    test('preloads and caches token + headroom', () async {
      final backend = _FakeAdsBackend(reward: const AdReward(amount: 1));
      final api = _FakeAdsApi(remainingToday: 3);
      final service = _service(backend, api);

      expect(service.remainingToday('double'), isNull);
      await service.prepare('double', gameId: 'g1');
      expect(backend.preloads, 1);
      expect(api.fetches, 1);
      expect(service.remainingToday('double'), 3);
      expect(service.canOffer('double'), isTrue);

      // earn() for the same slot reuses the prepared token.
      final result = await service.earn('double', gameId: 'g1');
      expect(result, isNotNull);
      expect(api.postedTokens, ['tok1']);
    });

    test('token failure during prepare is silent', () async {
      final backend = _FakeAdsBackend();
      final service = AdsService(
        backend: backend,
        fetchToken: (kind, {gameId}) async => throw Exception('offline'),
        postReward: (token) async =>
            const AdEarnResult(coins: 25, balance: 25, remainingToday: 4),
      );
      await service.prepare('shop'); // must not throw
      expect(service.remainingToday('shop'), isNull);
      expect(service.canOffer('shop'), isTrue,
          reason: 'unknown headroom must not hide the button; the server '
              'is the authority when earn() posts');
    });
  });
}
