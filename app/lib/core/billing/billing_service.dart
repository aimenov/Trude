/// Billing facade: platform store flow + server-authoritative granting.
///
/// Flow (plan §C-D): purchase events stream in (including PENDING purchases
/// left over from previous sessions) → for purchased|restored the purchase
/// proof is POSTed to the server (POST /iap/google | /iap/apple) → ONLY on a
/// 2xx is the store transaction completed and the grant reported; on server
/// failure the transaction is deliberately left incomplete so the store
/// redelivers it next session (no lost grants, no client-side granting).
///
/// UI contract (shop coin-packs row / premium card, settings "restore"):
/// - hide everything while [BillingService.supported] is false (web build);
/// - list [BillingService.products] (server display order via
///   `BillingProducts.coinPacks`);
/// - [BillingService.buy] just starts the flow — grants arrive later via
///   [BillingService.grants] (and meProvider invalidation refreshes
///   coins/premium app-wide).
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../net/connection_providers.dart';
import '../net/meta_providers.dart';
import 'billing_backend.dart';
import 'billing_backend_factory.dart';
import 'billing_config.dart';

/// Server-confirmed grant for one processed purchase
/// (POST /iap/* 2xx response).
class PurchaseGrant {
  const PurchaseGrant({
    required this.productId,
    required this.coins,
    required this.premium,
    required this.balance,
    required this.alreadyProcessed,
  });

  final String productId;

  /// Coins granted by this receipt (0 for premium / replays).
  final int coins;

  /// Whether the account is premium after this purchase.
  final bool premium;

  /// Wallet balance after the grant.
  final int balance;

  /// True when the server had already processed this receipt (replay) —
  /// nothing new was granted.
  final bool alreadyProcessed;
}

typedef IapPost = Future<PurchaseGrant> Function(BackendPurchase purchase);

/// App-wide billing service. On web/desktop the factory hands out
/// [NoopBillingBackend] ⇒ [BillingService.supported] is false and the shop
/// hides its store shelves.
final billingProvider = Provider<BillingService>((ref) {
  final client = ref.watch(trudeClientProvider);
  final service = BillingService(
    backend: createBillingBackend(),
    postPurchase: (purchase) async {
      final dynamic res = purchase.platform == 'apple'
          ? await client.postIapApple(receipt: purchase.verificationData)
          : await client.postIapGoogle(
              purchaseToken: purchase.verificationData,
              productId: purchase.productId,
            );
      return PurchaseGrant(
        productId: (_field(res, 'productId') as String?) ?? purchase.productId,
        coins: _asInt(_field(_field(res, 'granted'), 'coins')),
        premium: _field(res, 'premium') == true,
        balance: _asInt(_field(res, 'balance')),
        alreadyProcessed: _field(res, 'alreadyProcessed') == true,
      );
    },
    onGrant: (grant) {
      // walletProvider mirrors GET /me coins and MeProfile carries premium
      // (lane C-B): one refetch updates both app-wide.
      ref.invalidate(meProvider);
    },
  );
  unawaited(service.init());
  ref.onDispose(() => unawaited(service.dispose()));
  return service;
});

/// Reads [name] off either a decoded JSON map or a typed model whose field
/// names follow the wire contract (lane C-B owns the model classes; this
/// seam works with both shapes).
dynamic _field(dynamic o, String name) {
  if (o == null) return null;
  if (o is Map) return o[name];
  final dynamic d = o;
  switch (name) {
    case 'productId':
      return d.productId;
    case 'granted':
      return d.granted;
    case 'coins':
      return d.coins;
    case 'premium':
      return d.premium;
    case 'balance':
      return d.balance;
    case 'alreadyProcessed':
      return d.alreadyProcessed;
  }
  return null;
}

int _asInt(dynamic v) => v == null ? 0 : (v as num).toInt();

class BillingService {
  BillingService({
    required this._backend,
    required this._postPurchase,
    this._onGrant,
  });

  final BillingBackend _backend;
  final IapPost _postPurchase;
  final void Function(PurchaseGrant grant)? _onGrant;

  final _grants = StreamController<PurchaseGrant>.broadcast();
  final Completer<void> _ready = Completer<void>();

  /// Receipts currently being validated (keyed by proof) — guards against
  /// double-POSTing when the store redelivers while a POST is in flight.
  /// Server replays are safe anyway (alreadyProcessed), this just avoids
  /// noise.
  final Set<String> _inFlight = {};

  List<StoreProduct> _products = const [];

  /// False on web/desktop and when the store/plugin is unavailable.
  bool get supported => _backend.supported;

  /// Completes once [init] finished (products queried or determined empty).
  Future<void> get ready => _ready.future;

  /// Store listings queried at [init]; empty while unsupported/unavailable.
  List<StoreProduct> get products => _products;

  /// Server-confirmed grants, in arrival order (replays included with
  /// `alreadyProcessed == true` and zero grant).
  Stream<PurchaseGrant> get grants => _grants.stream;

  StoreProduct? product(String productId) {
    for (final p in _products) {
      if (p.id == productId) return p;
    }
    return null;
  }

  /// One-time startup: backend probe, purchase-stream subscription (pending
  /// purchases from previous sessions replay through it), product query.
  /// Never throws.
  Future<void> init() async {
    try {
      await _backend.init(_handlePurchase);
      if (_backend.supported) {
        _products = await _backend.queryProducts(BillingProducts.all);
      }
    } catch (_) {
      // Backends guard themselves; this is belt and braces.
    } finally {
      if (!_ready.isCompleted) _ready.complete();
    }
  }

  /// Starts the platform purchase flow for [productId]. False when the flow
  /// could not start (unknown product, store unavailable). The outcome
  /// arrives asynchronously on [grants].
  Future<bool> buy(String productId) async {
    if (!supported) return false;
    final listing = product(productId);
    if (listing == null) return false;
    return _backend.buy(
      listing,
      consumable: BillingProducts.isConsumable(productId),
    );
  }

  /// Settings «Восстановить покупки»: replays owned non-consumables through
  /// the purchase stream (server replies alreadyProcessed for known ones,
  /// grants for lost ones). Never throws.
  Future<void> restore() => _backend.restore();

  void _handlePurchase(BackendPurchase purchase) =>
      unawaited(_process(purchase));

  Future<void> _process(BackendPurchase purchase) async {
    // Pending: the store is still working (e.g. slow card, parental
    // approval); a terminal purchased/error event follows later.
    if (purchase.status == BackendPurchaseStatus.pending) return;
    if (!_inFlight.add(purchase.verificationData)) return;
    try {
      final grant = await _postPurchase(purchase);
      // 2xx (incl. alreadyProcessed replays): safe to finish the
      // transaction — the grant is durably recorded server-side.
      await _backend.completePurchase(purchase);
      if (!_grants.isClosed) _grants.add(grant);
      _onGrant?.call(grant);
    } catch (_) {
      // Server unreachable / rejected: do NOT complete. The store
      // redelivers the purchase next session and we retry validation then.
    } finally {
      _inFlight.remove(purchase.verificationData);
    }
  }

  Future<void> dispose() async {
    await _grants.close();
    await _backend.dispose();
  }
}
