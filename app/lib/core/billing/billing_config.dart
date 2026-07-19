/// Store product ids (must match both stores' consoles AND the server's
/// PRODUCTS map in packages/server/src/economy/products.ts).
///
/// Coin packs are consumable; premium_upgrade is a one-time non-consumable.
/// Grants are server-authoritative — the client never decides coin amounts.
library;

abstract final class BillingProducts {
  static const coinsSmall = 'coins_small'; // 500 coins / $0.99
  static const coinsMedium = 'coins_medium'; // 1800 coins / $2.99
  static const coinsLarge = 'coins_large'; // 4800 coins / $6.99
  static const coinsHuge = 'coins_huge'; // 12000 coins / $14.99
  static const premiumUpgrade = 'premium_upgrade'; // $3.99, non-consumable

  /// Consumable coin packs, in shop display order.
  static const List<String> coinPacks = [
    coinsSmall,
    coinsMedium,
    coinsLarge,
    coinsHuge,
  ];

  /// Every product to query from the store.
  static const Set<String> all = {
    coinsSmall,
    coinsMedium,
    coinsLarge,
    coinsHuge,
    premiumUpgrade,
  };

  static bool isConsumable(String productId) => coinPacks.contains(productId);
}
