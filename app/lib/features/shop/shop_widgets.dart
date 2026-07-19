/// Shared shop plumbing and small widgets: thin provider wrappers over the
/// ads/billing services (so widget tests can override a tiny, owned surface
/// instead of faking whole services), the felt swatch preview, price/state
/// chips, and section headers.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ads/ads_service.dart';
import '../../core/billing/billing_service.dart';
import '../../core/net/economy_providers.dart';
import '../../core/strings.dart';
import '../../core/theme/trude_theme.dart';
import '../game/widgets/cosmetic_styles.dart';

// -- Cross-lane wrappers ------------------------------------------------------
// The shop/results screens watch these instead of the services directly;
// tests override them with plain values.

/// Whether a rewarded ad is loaded and ready to show.
final rewardedAdReadyProvider = Provider<ValueListenable<bool>>(
    (ref) => ref.watch(adsProvider).rewardedReady);

/// Shows a rewarded ad of [kind] ('shop' | 'double') and settles the server
/// reward; resolves to the coins granted, or null when nothing was earned
/// (dismissed early, no fill, daily cap). Credits the wallet with the
/// server's post-grant balance before resolving.
typedef AdEarn = Future<int?> Function(String kind, {String? gameId});

final adEarnProvider = Provider<AdEarn>((ref) {
  final ads = ref.watch(adsProvider);
  return (kind, {gameId}) async {
    final result = await ads.earn(kind, gameId: gameId);
    if (result == null) return null;
    ref.read(walletProvider.notifier).set(result.balance);
    return result.coins;
  };
});

/// Preloads the rewarded ad + token for a placement (call on shop entry /
/// results panel mount). Never throws.
final adPrepareProvider =
    Provider<Future<void> Function(String kind, {String? gameId})>(
        (ref) => ref.watch(adsProvider).prepare);

/// Whether store billing works on this platform (false on web/desktop).
final billingSupportedProvider =
    Provider<bool>((ref) => ref.watch(billingProvider).supported);

/// Store products (coin packs + premium); resolves once the billing service
/// finished its startup query. Empty when unsupported.
final billingProductsProvider = FutureProvider<List<dynamic>>((ref) async {
  final billing = ref.watch(billingProvider);
  if (!billing.supported) return const [];
  await billing.ready;
  return billing.products;
});

/// Launches a store purchase for [productId]; loosely typed (`Function`)
/// so this file compiles against any buy() return type.
final billingBuyProvider =
    Provider<Function(String productId)>((ref) => ref.watch(billingProvider).buy);

/// Restores prior purchases (settings + shop).
final billingRestoreProvider =
    Provider<Function()>((ref) => ref.watch(billingProvider).restore);

// -- Constants ---------------------------------------------------------------

/// Coins granted per IAP product id (display only — the server is the truth).
const kCoinPackAmounts = <String, int>{
  'coins_small': 500,
  'coins_medium': 1800,
  'coins_large': 4800,
  'coins_huge': 12000,
};

/// Product id of the one-time Premium upgrade.
const kPremiumProductId = 'premium_upgrade';

/// Coins granted by the shop's rewarded-ad button.
const kShopAdCoins = 25;

// -- Widgets -----------------------------------------------------------------

/// Etched section header with hairline rules either side.
class ShopSectionHeader extends StatelessWidget {
  const ShopSectionHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(
              child: SizedBox(
                  height: 1, child: ColoredBox(color: TrudeColors.hairline))),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label.toUpperCase(),
              style: TrudeType.etched.copyWith(fontSize: 11, letterSpacing: 2.4),
            ),
          ),
          const Expanded(
              child: SizedBox(
                  height: 1, child: ColoredBox(color: TrudeColors.hairline))),
        ],
      ),
    );
  }
}

/// A round felt preview: the felt's light pool over its base and deep tones,
/// with a brass rim when [selected].
class FeltSwatch extends StatelessWidget {
  const FeltSwatch({
    super.key,
    required this.style,
    this.size = 64,
    this.selected = false,
  });

  final FeltStyle style;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? TrudeColors.brassBright : TrudeColors.hairline,
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: TrudeColors.midnight.withValues(alpha: 0.45),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: CustomPaint(painter: _FeltSwatchPainter(style)),
    );
  }
}

class _FeltSwatchPainter extends CustomPainter {
  const _FeltSwatchPainter(this.style);

  final FeltStyle style;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1;
    final paint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.3),
        colors: [style.lit, style.base, style.deep],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(Rect.fromCircle(center: c, radius: r));
    canvas.drawCircle(c, r, paint);
  }

  @override
  bool shouldRepaint(covariant _FeltSwatchPainter oldDelegate) =>
      oldDelegate.style.id != style.id;
}

/// The small state chip under a shop cell: a coin price, «В коллекции»,
/// brass-lit «Выбрано», or a premium lock.
class ShopStateChip extends StatelessWidget {
  const ShopStateChip.price(this.price, {super.key})
      : kind = ShopChipKind.price;
  const ShopStateChip.owned({super.key})
      : kind = ShopChipKind.owned,
        price = 0;
  const ShopStateChip.equipped({super.key})
      : kind = ShopChipKind.equipped,
        price = 0;
  const ShopStateChip.locked({super.key})
      : kind = ShopChipKind.locked,
        price = 0;

  final ShopChipKind kind;
  final int price;

  @override
  Widget build(BuildContext context) {
    final (label, icon) = switch (kind) {
      ShopChipKind.price => ('$price', Icons.paid_outlined),
      ShopChipKind.owned => (Strings.shopOwned, null),
      ShopChipKind.equipped => (Strings.shopEquipped, Icons.check),
      ShopChipKind.locked => (Strings.shopPremiumLock, Icons.lock_outline),
    };
    final equipped = kind == ShopChipKind.equipped;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: equipped ? TrudeGradients.brass : null,
        color: equipped ? null : TrudeColors.surfaceSunken,
        borderRadius: BorderRadius.circular(TrudeDims.chipRadius),
        border: Border.all(
          color: equipped ? TrudeColors.brassDark : TrudeColors.hairline,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon,
                size: 12,
                color: equipped
                    ? TrudeColors.textOnBrass
                    : TrudeColors.brassBright),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TrudeType.cardIndex.copyWith(
                fontSize: 11,
                color: equipped
                    ? TrudeColors.textOnBrass
                    : (kind == ShopChipKind.locked
                        ? TrudeColors.textMuted
                        : TrudeColors.brassBright),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum ShopChipKind { price, owned, equipped, locked }
