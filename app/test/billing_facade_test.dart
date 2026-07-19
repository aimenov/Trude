/// Billing facade tests: no-op paths never throw, the service only completes
/// store transactions after a server 2xx, and grants are surfaced exactly
/// once per processed purchase.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:trude/core/billing/billing_backend.dart';
import 'package:trude/core/billing/billing_backend_iap.dart';
import 'package:trude/core/billing/billing_config.dart';
import 'package:trude/core/billing/billing_service.dart';

class _FakeBillingBackend implements BillingBackend {
  bool supportedFlag = true;
  PurchaseHandler? handler;
  List<StoreProduct> listings = const [];
  final List<BackendPurchase> completed = [];
  final List<(String, bool)> buys = [];
  int restores = 0;
  bool buyResult = true;

  /// Simulates the platform purchase stream delivering an event.
  void deliver(BackendPurchase purchase) => handler?.call(purchase);

  @override
  bool get supported => supportedFlag;

  @override
  Future<void> init(PurchaseHandler onPurchase) async => handler = onPurchase;

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) async =>
      [for (final p in listings) if (ids.contains(p.id)) p];

  @override
  Future<bool> buy(StoreProduct product, {required bool consumable}) async {
    buys.add((product.id, consumable));
    return buyResult;
  }

  @override
  Future<void> restore() async => restores++;

  @override
  Future<void> completePurchase(BackendPurchase purchase) async =>
      completed.add(purchase);

  @override
  Future<void> dispose() async {}
}

BackendPurchase _purchase(
  String productId, {
  BackendPurchaseStatus status = BackendPurchaseStatus.purchased,
  String platform = 'google',
  String? proof,
}) =>
    BackendPurchase(
      productId: productId,
      platform: platform,
      verificationData: proof ?? 'proof-$productId',
      status: status,
    );

const _listings = [
  StoreProduct(
      id: BillingProducts.coinsSmall,
      title: 'S',
      description: '',
      price: r'$0.99'),
  StoreProduct(
      id: BillingProducts.premiumUpgrade,
      title: 'P',
      description: '',
      price: r'$3.99'),
];

void main() {
  group('BillingProducts', () {
    test('coin packs are consumable, premium is not', () {
      for (final id in BillingProducts.coinPacks) {
        expect(BillingProducts.isConsumable(id), isTrue, reason: id);
      }
      expect(
          BillingProducts.isConsumable(BillingProducts.premiumUpgrade), isFalse);
      expect(BillingProducts.all.length, 5);
    });
  });

  group('NoopBillingBackend', () {
    test('is inert and never throws', () async {
      const backend = NoopBillingBackend();
      expect(backend.supported, isFalse);
      await backend.init((_) => fail('noop must never deliver purchases'));
      expect(await backend.queryProducts(BillingProducts.all), isEmpty);
      expect(
        await backend.buy(_listings.first, consumable: true),
        isFalse,
      );
      await backend.restore();
      await backend.completePurchase(_purchase('coins_small'));
      await backend.dispose();
    });
  });

  group('IapBillingBackend pre-init guards', () {
    // init() is NOT called here (it would touch plugin channels); every
    // other entry point must already be a safe no-op — the same "broken
    // until proven working" discipline as GoogleAdsBackend.
    test('all calls are safe no-ops before/without init', () async {
      final backend = IapBillingBackend();
      expect(backend.supported, isFalse);
      expect(await backend.queryProducts(BillingProducts.all), isEmpty);
      expect(await backend.buy(_listings.first, consumable: true), isFalse);
      await backend.restore();
      await backend.completePurchase(_purchase('coins_small'));
      await backend.dispose();
    });
  });

  group('BillingService with the no-op backend', () {
    test('unsupported: empty products, failed buys, silent restore',
        () async {
      final service = BillingService(
        backend: const NoopBillingBackend(),
        postPurchase: (p) async =>
            fail('must never reach the server unsupported'),
      );
      await service.init();
      expect(service.supported, isFalse);
      expect(service.products, isEmpty);
      expect(await service.buy(BillingProducts.coinsSmall), isFalse);
      await service.restore(); // must not throw
      await service.dispose();
    });
  });

  group('BillingService purchase processing', () {
    late _FakeBillingBackend backend;
    late List<BackendPurchase> posted;
    late List<PurchaseGrant> reported;
    late List<PurchaseGrant> streamed;
    late BillingService service;
    Exception? postFailure;

    Future<void> setUpService() async {
      backend = _FakeBillingBackend()..listings = _listings;
      posted = [];
      reported = [];
      streamed = [];
      postFailure = null;
      service = BillingService(
        backend: backend,
        postPurchase: (purchase) async {
          posted.add(purchase);
          final failure = postFailure;
          if (failure != null) throw failure;
          return PurchaseGrant(
            productId: purchase.productId,
            coins: purchase.productId == BillingProducts.premiumUpgrade
                ? 0
                : 500,
            premium: purchase.productId == BillingProducts.premiumUpgrade,
            balance: 500,
            alreadyProcessed: false,
          );
        },
        onGrant: reported.add,
      );
      service.grants.listen(streamed.add);
      await service.init();
    }

    Future<void> settle() async {
      // Let the fire-and-forget _process chains run out.
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('queried products are exposed after init', () async {
      await setUpService();
      expect(service.supported, isTrue);
      expect(service.products.length, 2);
      expect(service.product(BillingProducts.coinsSmall), isNotNull);
      expect(service.product('nope'), isNull);
    });

    test('buy dispatches with the right consumable flag', () async {
      await setUpService();
      expect(await service.buy(BillingProducts.coinsSmall), isTrue);
      expect(await service.buy(BillingProducts.premiumUpgrade), isTrue);
      expect(backend.buys,
          [(BillingProducts.coinsSmall, true), (BillingProducts.premiumUpgrade, false)]);
      // Unknown product: no store call at all.
      expect(await service.buy('coins_unknown'), isFalse);
      expect(backend.buys.length, 2);
    });

    test('purchased: POST once -> complete -> grant reported', () async {
      await setUpService();
      backend.deliver(_purchase(BillingProducts.coinsSmall));
      await settle();

      expect(posted.length, 1);
      expect(posted.single.platform, 'google');
      expect(backend.completed.length, 1);
      expect(reported.length, 1);
      expect(reported.single.coins, 500);
      expect(streamed.length, 1);
    });

    test('restored purchases validate like purchases', () async {
      await setUpService();
      backend.deliver(_purchase(BillingProducts.premiumUpgrade,
          status: BackendPurchaseStatus.restored, platform: 'apple'));
      await settle();

      expect(posted.length, 1);
      expect(posted.single.platform, 'apple');
      expect(backend.completed.length, 1);
      expect(reported.single.premium, isTrue);
    });

    test('pending purchases are left alone (no POST, no complete)', () async {
      await setUpService();
      backend.deliver(_purchase(BillingProducts.coinsSmall,
          status: BackendPurchaseStatus.pending));
      await settle();

      expect(posted, isEmpty);
      expect(backend.completed, isEmpty);
      expect(reported, isEmpty);
    });

    test('server failure: transaction NOT completed (retries next session)',
        () async {
      await setUpService();
      postFailure = Exception('server down');
      backend.deliver(_purchase(BillingProducts.coinsSmall));
      await settle();

      expect(posted.length, 1);
      expect(backend.completed, isEmpty,
          reason: 'an uncompleted purchase is the retry mechanism — '
              'completing on failure would lose the grant forever');
      expect(reported, isEmpty);

      // The store redelivers later; validation then succeeds and completes.
      postFailure = null;
      backend.deliver(_purchase(BillingProducts.coinsSmall));
      await settle();
      expect(posted.length, 2);
      expect(backend.completed.length, 1);
      expect(reported.length, 1);
    });

    test('concurrent redelivery of the same receipt posts once', () async {
      await setUpService();
      backend.deliver(_purchase(BillingProducts.coinsSmall, proof: 'same'));
      backend.deliver(_purchase(BillingProducts.coinsSmall, proof: 'same'));
      await settle();

      expect(posted.length, 1);
      expect(backend.completed.length, 1);
    });

    test('restore delegates to the backend', () async {
      await setUpService();
      await service.restore();
      expect(backend.restores, 1);
    });
  });
}
