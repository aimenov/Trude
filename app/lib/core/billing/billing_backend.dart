/// Store-billing engine contract, plugin-free.
///
/// Mirrors the `AdsBackend` / `SfxBackend` split: pure Dart here; the
/// in_app_purchase-backed implementation lives in `billing_backend_iap.dart`
/// — the ONLY file allowed to import the plugin. Callers obtain a backend
/// via `billing_backend_factory.dart`.
library;

/// A purchasable product as reported by the platform store.
class StoreProduct {
  const StoreProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
    this.raw,
  });

  final String id;
  final String title;
  final String description;

  /// Localized display price, e.g. "$0.99" — show verbatim, never compute.
  final String price;

  /// Backend-specific handle (`ProductDetails`) needed to launch a purchase.
  final Object? raw;
}

enum BackendPurchaseStatus { pending, purchased, restored }

/// One purchase event surfaced by the backend. Canceled/error events are
/// cleaned up inside the backend and never forwarded.
class BackendPurchase {
  const BackendPurchase({
    required this.productId,
    required this.platform,
    required this.verificationData,
    required this.status,
    this.raw,
  });

  final String productId;

  /// 'google' | 'apple' — selects POST /iap/google vs POST /iap/apple.
  final String platform;

  /// Server-verifiable proof: Play purchaseToken / App Store receipt
  /// (`verificationData.serverVerificationData`).
  final String verificationData;

  final BackendPurchaseStatus status;

  /// Backend-specific handle (`PurchaseDetails`) for [BillingBackend.completePurchase].
  final Object? raw;
}

typedef PurchaseHandler = void Function(BackendPurchase purchase);

/// The billing engine behind `BillingService`. Every method must never throw
/// (silently degrade when plugin channels are missing, e.g. VM tests, web).
abstract interface class BillingBackend {
  /// False for the no-op/broken backend; the UI hides IAP shelves entirely.
  /// Only meaningful after [init] completed.
  bool get supported;

  /// One-time startup: probe + subscribe to the purchase stream so pending
  /// purchases from previous sessions are (re)delivered. Never throws.
  Future<void> init(PurchaseHandler onPurchase);

  /// Store listings for [ids]; empty list on any failure/unsupported.
  Future<List<StoreProduct>> queryProducts(Set<String> ids);

  /// Launches the platform purchase flow. Returns false when the flow could
  /// not even start; the actual outcome arrives via the purchase stream.
  Future<bool> buy(StoreProduct product, {required bool consumable});

  /// Replays owned non-consumables (and unfinished transactions) through the
  /// purchase stream as `restored` events.
  Future<void> restore();

  /// Acknowledge/finish a delivered purchase. Call ONLY after the server
  /// confirmed the grant (2xx) — an uncompleted purchase is redelivered next
  /// session, which is exactly the retry we want.
  Future<void> completePurchase(BackendPurchase purchase);

  Future<void> dispose();
}

/// Inert backend for web/desktop/tests: no store, no products, no purchases.
class NoopBillingBackend implements BillingBackend {
  const NoopBillingBackend();

  @override
  bool get supported => false;

  @override
  Future<void> init(PurchaseHandler onPurchase) async {}

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) async => const [];

  @override
  Future<bool> buy(StoreProduct product, {required bool consumable}) async =>
      false;

  @override
  Future<void> restore() async {}

  @override
  Future<void> completePurchase(BackendPurchase purchase) async {}

  @override
  Future<void> dispose() async {}
}
