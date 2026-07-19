/// «Лавка» — the parlor shop: rewarded-ad coins, card backs, table felts,
/// coin packs (mobile only), and the one-time Premium patronage.
///
/// Coins come from [walletProvider]; catalog/ownership/selection come from
/// the economy providers. Buying is server-authoritative: POST /shop/buy,
/// then the wallet snaps to the returned balance and ownership refreshes.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion/animation_speed.dart';
import '../../core/net/connection_providers.dart';
import '../../core/net/economy_providers.dart';
import '../../core/strings.dart';
import '../../core/theme/trude_theme.dart';
import '../game/widgets/card_widgets.dart';
import '../game/widgets/cosmetic_styles.dart';
import '../home/parlor_widgets.dart';
import 'shop_widgets.dart';

/// Whether the device-bound purchase warning was already shown this session
/// (shown once, the first time the IAP shelves are visible).
final iapWarningShownProvider = StateProvider<bool>((_) => false);

class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key});

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (!mounted) return;
      // Preload the rewarded ad + token so the «+25» button can appear.
      ref.read(adPrepareProvider)('shop');
    });
  }

  void _maybeShowIapWarning() {
    if (!ref.read(billingSupportedProvider)) return;
    if (ref.read(iapWarningShownProvider)) return;
    // Provider writes must not happen during build — defer to post-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ref.read(iapWarningShownProvider)) return;
      ref.read(iapWarningShownProvider.notifier).state = true;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(Strings.shopPurchaseWarningTitle),
          content: Text(Strings.shopPurchaseWarningBody),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(Strings.accept),
            ),
          ],
        ),
      );
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _watchAd() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final got = await ref.read(adEarnProvider)('shop');
      if (got != null) _snack('+$got');
    } catch (_) {
      // Ad failures are silent by design — the button simply stops helping.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _equip(dynamic item) async {
    try {
      await ref
          .read(selectedCosmeticsProvider.notifier)
          .equip(item.kindEnum as CosmeticKind, item.key as String);
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _buyCosmetic(dynamic item) async {
    final key = item.key as String;
    final price = item.price as int;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(Strings.shopBuyConfirmTitle),
        content: Text(
            Strings.shopBuyConfirmBody(Strings.cosmeticName(key), price)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(Strings.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(Strings.buy),
          ),
        ],
      ),
    );
    if (confirmed != true || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(trudeClientProvider).buyCosmetic(key);
      ref.read(walletProvider.notifier).set(result.balance);
      // ownedCosmeticIdsProvider derives from myCosmeticsProvider — refresh
      // the source.
      ref.invalidate(myCosmeticsProvider);
    } on TrudeApiException catch (e) {
      switch (e.statusCode) {
        case 402:
          _snack(Strings.shopInsufficientFunds);
        case 403:
          _snack(Strings.shopPremiumLock);
        case 409:
          // Already owned (e.g. another tab) — just refresh ownership.
          ref.invalidate(myCosmeticsProvider);
        default:
          _snack('$e');
      }
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buyProduct(String productId) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref.read(billingBuyProvider)(productId);
      ref.invalidate(meProvider);
    } catch (e) {
      _snack('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final billingSupported = ref.watch(billingSupportedProvider);
    if (billingSupported) _maybeShowIapWarning();
    final premium = ref.watch(meProvider).valueOrNull?.premium ?? false;
    final catalog = ref.watch(cosmeticsCatalogProvider).valueOrNull;
    final owned =
        ref.watch(ownedCosmeticIdsProvider).valueOrNull ?? const <String>{};
    final selected = ref.watch(selectedCosmeticsProvider);

    // Kept loosely typed on purpose: cells only touch key/kind/price/
    // premiumOnly, so this file does not compile-couple to the model class.
    final List<dynamic> items = catalog?.items ?? const <dynamic>[];
    final cardBacks =
        [for (final i in items) if ((i.key as String).startsWith('cb_')) i];
    final felts =
        [for (final i in items) if ((i.key as String).startsWith('felt_')) i];

    return ParlorBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(Strings.shopTitle),
          leading: BackButton(onPressed: () => context.go('/home')),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _WalletHeader(onWatchAd: _busy ? null : _watchAd),
                ShopSectionHeader(label: Strings.shopCardBacksSection),
                _cosmeticGrid(
                  cardBacks,
                  premium: premium,
                  owned: owned,
                  equippedKey: selected.cardBack,
                  preview: (key, isEquipped) => TrudeCardBack(
                    width: 54,
                    style: cardBackStyleFor(key),
                    selected: isEquipped,
                  ),
                ),
                ShopSectionHeader(label: Strings.shopFeltsSection),
                _cosmeticGrid(
                  felts,
                  premium: premium,
                  owned: owned,
                  equippedKey: selected.felt,
                  preview: (key, isEquipped) => FeltSwatch(
                    style: feltStyleFor(key),
                    size: 58,
                    selected: isEquipped,
                  ),
                ),
                ShopSectionHeader(label: Strings.shopCoinsSection),
                if (!billingSupported)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      Strings.shopBillingUnavailable,
                      textAlign: TextAlign.center,
                      style: TrudeType.cardIndex.copyWith(
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w400,
                        fontSize: 13,
                        color: TrudeColors.textMuted,
                      ),
                    ),
                  )
                else
                  _CoinPacksRow(onBuy: _busy ? null : _buyProduct),
                ShopSectionHeader(label: Strings.shopPremiumSection),
                _PremiumCard(
                  premium: premium,
                  billingSupported: billingSupported,
                  onBuy: _busy ? null : () => _buyProduct(kPremiumProductId),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cosmeticGrid(
    List<dynamic> items, {
    required bool premium,
    required Set<String> owned,
    required String? equippedKey,
    required Widget Function(String key, bool isEquipped) preview,
  }) {
    if (items.isEmpty) {
      // Catalog still loading (or unreachable) — keep the shelf quiet.
      return const SizedBox(height: 8);
    }
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 0.62,
      children: [
        for (final item in items)
          _CosmeticCell(
            item: item,
            equipped: equippedKey == item.key,
            owned: owned.contains(item.key) ||
                (item.price as int) == 0 ||
                ((item.premiumOnly as bool) && premium),
            locked: (item.premiumOnly as bool) && !premium,
            preview: preview(item.key as String, equippedKey == item.key),
            onEquip: () => _equip(item),
            onBuy: () => _buyCosmetic(item),
          ),
      ],
    );
  }
}

/// Wallet readout (count-up) + the rewarded-ad button when an ad is ready.
class _WalletHeader extends ConsumerWidget {
  const _WalletHeader({required this.onWatchAd});

  final VoidCallback? onWatchAd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coins = ref.watch(walletProvider);
    final speed = ref.watch(animationSpeedProvider);
    return Column(
      children: [
        if (coins != null)
          EtchedPlaque(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.paid_outlined,
                    size: 18, color: TrudeColors.brassBright),
                const SizedBox(width: 8),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: coins.toDouble()),
                  duration: speed.scale(const Duration(milliseconds: 600)),
                  builder: (context, value, _) => Text(
                    '${value.round()}',
                    style: TrudeType.display.copyWith(
                        fontSize: 22, color: TrudeColors.brassBright),
                  ),
                ),
              ],
            ),
          ),
        ValueListenableBuilder<bool>(
          valueListenable: ref.watch(rewardedAdReadyProvider),
          builder: (context, ready, _) => !ready
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: BrassButton(
                    height: 48,
                    onPressed: onWatchAd,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.play_circle_outline),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            Strings.shopWatchAd(kShopAdCoins),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

/// One shelf cell: preview art, localized name, and a state chip.
class _CosmeticCell extends StatelessWidget {
  const _CosmeticCell({
    required this.item,
    required this.equipped,
    required this.owned,
    required this.locked,
    required this.preview,
    required this.onEquip,
    required this.onBuy,
  });

  final dynamic item;
  final bool equipped;
  final bool owned;
  final bool locked;
  final Widget preview;
  final VoidCallback onEquip;
  final VoidCallback onBuy;

  @override
  Widget build(BuildContext context) {
    final key = item.key as String;
    // The premium lock outranks ownership: cb_gilded is price-0 (counted as
    // implicitly owned) yet must stay locked for non-premium players.
    final chip = equipped
        ? const ShopStateChip.equipped()
        : locked
            ? const ShopStateChip.locked()
            : owned
                ? const ShopStateChip.owned()
                : ShopStateChip.price(item.price as int);
    final onTap = equipped
        ? null
        : locked
            ? null
            : owned
                ? onEquip
                : onBuy;
    return PressableScale(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: TrudeColors.surfaceRaised,
          borderRadius: BorderRadius.circular(TrudeDims.panelRadius),
          border: Border.all(
            color: equipped
                ? TrudeColors.brassBright
                : TrudeColors.hairline,
            width: equipped ? 1.6 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: TrudeColors.midnight.withValues(alpha: 0.45),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Opacity(opacity: locked ? 0.55 : 1, child: preview),
            const SizedBox(height: 8),
            Text(
              Strings.cosmeticName(key),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TrudeType.cardIndex.copyWith(
                fontSize: 11.5,
                color: equipped
                    ? TrudeColors.brassBright
                    : TrudeColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            chip,
          ],
        ),
      ),
    );
  }
}

/// Store coin packs (mobile only), one card per product.
class _CoinPacksRow extends ConsumerWidget {
  const _CoinPacksRow({required this.onBuy});

  final void Function(String productId)? onBuy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final products = ref.watch(billingProductsProvider).valueOrNull ?? const [];
    final packs = [
      for (final p in products)
        if (kCoinPackAmounts.containsKey(p.id as String)) p
    ];
    if (packs.isEmpty) return const SizedBox(height: 8);
    return Row(
      children: [
        for (var i = 0; i < packs.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: PressableScale(
              onTap: onBuy == null
                  ? null
                  : () => onBuy!(packs[i].id as String),
              child: EtchedPlaque(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.paid_outlined,
                        size: 18, color: TrudeColors.brassBright),
                    const SizedBox(height: 4),
                    Text(
                      Strings.coinPackLabel(
                          kCoinPackAmounts[packs[i].id as String]!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TrudeType.cardIndex.copyWith(
                          fontSize: 11, color: TrudeColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${packs[i].price}',
                      maxLines: 1,
                      style: TrudeType.etched.copyWith(
                          fontSize: 10, letterSpacing: 0.6),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// The wide Premium pitch card.
class _PremiumCard extends ConsumerWidget {
  const _PremiumCard({
    required this.premium,
    required this.billingSupported,
    required this.onBuy,
  });

  final bool premium;
  final bool billingSupported;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    String? price;
    if (billingSupported) {
      final products =
          ref.watch(billingProductsProvider).valueOrNull ?? const [];
      for (final p in products) {
        if (p.id == kPremiumProductId) price = '${p.price}';
      }
    }
    return ParlorPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium_outlined,
                  color: TrudeColors.brassBright),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  Strings.premiumTitle,
                  style: TrudeType.display.copyWith(fontSize: 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            Strings.premiumPitch,
            style: TrudeType.cardIndex.copyWith(
              fontWeight: FontWeight.w400,
              fontStyle: FontStyle.italic,
              fontSize: 13,
              height: 1.35,
              color: TrudeColors.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          if (premium)
            Center(
              child: Text(
                Strings.premiumOwned.toUpperCase(),
                style:
                    TrudeType.etched.copyWith(fontSize: 11, letterSpacing: 2),
              ),
            )
          else if (billingSupported)
            BrassButton(
              height: 46,
              onPressed: onBuy,
              child: Text(
                price == null ? Strings.buy : '${Strings.buy} · $price',
                style: const TextStyle(fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }
}
