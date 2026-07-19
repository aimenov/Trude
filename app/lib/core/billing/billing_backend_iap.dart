/// in_app_purchase-backed [BillingBackend].
///
/// THE ONLY FILE in the app allowed to import `in_app_purchase` — the plugin
/// has no web implementation, so any other import site breaks
/// `flutter build web`. Reached exclusively through the conditional import
/// in `billing_backend_factory.dart`.
///
/// Safety discipline (see `PlayersSfxBackend.warmUp` /
/// `GoogleAdsBackend.init`): VM widget tests report android and DO construct
/// this class; the try/catch probe in [init] (first plugin call throws a
/// catchable MissingPluginException / missing-platform error) marks the
/// backend broken forever. Construction never touches plugin channels.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'billing_backend.dart';

class IapBillingBackend implements BillingBackend {
  IapBillingBackend();

  bool _initialized = false;

  /// Set when plugin channels / the store are unavailable; keeps every later
  /// call a cheap no-op, forever.
  bool _broken = false;

  StreamSubscription<List<PurchaseDetails>>? _sub;
  PurchaseHandler? _onPurchase;

  @override
  bool get supported => _initialized && !_broken;

  @override
  Future<void> init(PurchaseHandler onPurchase) async {
    if (_initialized || _broken) return;
    _onPurchase = onPurchase;
    try {
      // Probe: under VM tests this either throws MissingPluginException
      // (catchable) or an unimplemented-platform error — both mark broken.
      final available = await InAppPurchase.instance.isAvailable();
      if (!available) {
        _broken = true;
        return;
      }
      // Subscribing FIRST thing is load-bearing: unfinished purchases from
      // previous sessions (server was down when we tried to validate) are
      // redelivered here at startup.
      _sub = InAppPurchase.instance.purchaseStream.listen(
        _onUpdates,
        onError: (Object e) {
          if (kDebugMode) debugPrint('IapBillingBackend: stream error: $e');
        },
      );
      _initialized = true;
    } catch (e) {
      _broken = true;
      if (kDebugMode) debugPrint('IapBillingBackend: plugin unavailable: $e');
    }
  }

  void _onUpdates(List<PurchaseDetails> purchases) {
    for (final p in purchases) {
      switch (p.status) {
        case PurchaseStatus.pending:
          _onPurchase?.call(_map(p, BackendPurchaseStatus.pending));
        case PurchaseStatus.purchased:
          _onPurchase?.call(_map(p, BackendPurchaseStatus.purchased));
        case PurchaseStatus.restored:
          _onPurchase?.call(_map(p, BackendPurchaseStatus.restored));
        case PurchaseStatus.error:
        case PurchaseStatus.canceled:
          // Nothing was granted, so no server call — but the transaction
          // must still be finished or iOS redelivers it forever.
          if (p.pendingCompletePurchase) {
            unawaited(
              InAppPurchase.instance.completePurchase(p).catchError((_) {}),
            );
          }
      }
    }
  }

  BackendPurchase _map(PurchaseDetails p, BackendPurchaseStatus status) =>
      BackendPurchase(
        productId: p.productID,
        platform: defaultTargetPlatform == TargetPlatform.iOS ||
                defaultTargetPlatform == TargetPlatform.macOS
            ? 'apple'
            : 'google',
        verificationData: p.verificationData.serverVerificationData,
        status: status,
        raw: p,
      );

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> ids) async {
    if (!supported) return const [];
    try {
      final res = await InAppPurchase.instance.queryProductDetails(ids);
      if (kDebugMode && res.notFoundIDs.isNotEmpty) {
        debugPrint('IapBillingBackend: not in store: ${res.notFoundIDs}');
      }
      return [
        for (final d in res.productDetails)
          StoreProduct(
            id: d.id,
            title: d.title,
            description: d.description,
            price: d.price,
            raw: d,
          ),
      ];
    } catch (e) {
      if (kDebugMode) debugPrint('IapBillingBackend: query failed: $e');
      return const [];
    }
  }

  @override
  Future<bool> buy(StoreProduct product, {required bool consumable}) async {
    final details = product.raw;
    if (!supported || details is! ProductDetails) return false;
    try {
      final param = PurchaseParam(productDetails: details);
      return consumable
          ? await InAppPurchase.instance.buyConsumable(purchaseParam: param)
          : await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
    } catch (e) {
      if (kDebugMode) debugPrint('IapBillingBackend: buy failed: $e');
      return false;
    }
  }

  @override
  Future<void> restore() async {
    if (!supported) return;
    try {
      await InAppPurchase.instance.restorePurchases();
    } catch (e) {
      if (kDebugMode) debugPrint('IapBillingBackend: restore failed: $e');
    }
  }

  @override
  Future<void> completePurchase(BackendPurchase purchase) async {
    final details = purchase.raw;
    if (!supported || details is! PurchaseDetails) return;
    if (!details.pendingCompletePurchase) return;
    try {
      await InAppPurchase.instance.completePurchase(details);
    } catch (e) {
      if (kDebugMode) debugPrint('IapBillingBackend: complete failed: $e');
    }
  }

  @override
  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _onPurchase = null;
  }
}
