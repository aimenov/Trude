/// Riverpod providers for the economy: wallet + rating mirrors, leaderboard,
/// quests, cosmetics catalog/ownership/selection, and the daily bonus.
///
/// The wallet and rating are Notifiers that MIRROR `meProvider` (server truth
/// re-seeds them whenever `meProvider` refreshes) but accept instant local
/// bumps — `credit()` for flows that only know a delta, `set()` for flows the
/// server answered with an authoritative balance.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'connection_providers.dart';
import 'meta_providers.dart';

export 'economy_models.dart';
export 'meta_providers.dart';

/// Coin balance; null until `GET /me` resolved (UI hides the chip then).
final walletProvider =
    NotifierProvider<WalletController, int?>(WalletController.new);

class WalletController extends Notifier<int?> {
  @override
  int? build() => ref.watch(meProvider.select((me) => me.valueOrNull?.coins));

  /// Instant local bump when only a delta is known (e.g. rewarded ad grant).
  void credit(int delta) => state = (state ?? 0) + delta;

  /// Snap to a server-authoritative balance.
  void set(int balance) => state = balance;
}

/// ELO rating; null until `GET /me` resolved.
final ratingProvider =
    NotifierProvider<RatingController, int?>(RatingController.new);

class RatingController extends Notifier<int?> {
  @override
  int? build() => ref.watch(meProvider.select((me) => me.valueOrNull?.rating));

  void set(int rating) => state = rating;
}

/// `GET /leaderboard` per scope. Refresh with
/// `ref.refresh(leaderboardProvider(scope).future)` from pull-to-refresh.
final leaderboardProvider =
    FutureProvider.family<LeaderboardPage, LeaderboardScope>(
        (ref, scope) async {
  // ensure() may log in (writing session/identity providers); leave this
  // provider's synchronous build window first (see meta_providers.dart).
  await null;
  await ref.read(sessionProvider.notifier).ensure();
  return ref.read(trudeClientProvider).getLeaderboard(scope);
});

/// `GET /me/quests` — today's three quests with progress.
final questsProvider = FutureProvider<DailyQuests>((ref) async {
  await null;
  await ref.read(sessionProvider.notifier).ensure();
  return ref.read(trudeClientProvider).getQuests();
});

/// `GET /catalog/cosmetics` — public, no session needed.
final cosmeticsCatalogProvider = FutureProvider<CosmeticsCatalog>(
    (ref) => ref.read(trudeClientProvider).getCosmeticsCatalog());

/// `GET /me/cosmetics` — owned keys + server-side selection.
final myCosmeticsProvider = FutureProvider<OwnedCosmetics>((ref) async {
  await null;
  await ref.read(sessionProvider.notifier).ensure();
  return ref.read(trudeClientProvider).getMyCosmetics();
});

/// Owned cosmetic keys, always including the implicitly-owned defaults.
/// Invalidate [myCosmeticsProvider] after a purchase to refresh.
final ownedCosmeticIdsProvider = FutureProvider<Set<String>>((ref) async {
  final mine = await ref.watch(myCosmeticsProvider.future);
  return {kDefaultCardBack, kDefaultFelt, ...mine.owned};
});

/// The equipped card back + felt. Seeds from `meProvider`; [SelectedCosmeticsController.equip]
/// applies optimistically, PATCHes /me, and reverts on error.
final selectedCosmeticsProvider =
    NotifierProvider<SelectedCosmeticsController, SelectedCosmetics>(
        SelectedCosmeticsController.new);

class SelectedCosmeticsController extends Notifier<SelectedCosmetics> {
  @override
  SelectedCosmetics build() =>
      ref.watch(meProvider.select((me) => me.valueOrNull?.selected)) ??
      const SelectedCosmetics();

  String get cardBack => state.cardBack;
  String get felt => state.felt;

  /// Optimistic equip: flips the local selection instantly, then PATCH /me;
  /// reverts and rethrows on failure (403 NOT_OWNED, network, ...).
  Future<void> equip(CosmeticKind kind, String key) async {
    final previous = state;
    state = kind == CosmeticKind.cardBack
        ? previous.copyWith(cardBack: key)
        : previous.copyWith(felt: key);
    try {
      final me = await ref.read(trudeClientProvider).patchMe(
            selectedCardBack: kind == CosmeticKind.cardBack ? key : null,
            selectedFelt: kind == CosmeticKind.felt ? key : null,
          );
      state = me.selected; // server echo is authoritative
    } catch (_) {
      state = previous;
      rethrow;
    }
  }
}

/// Daily bonus surface state for the home sheet.
class DailyBonusState {
  const DailyBonusState({
    required this.claimable,
    required this.streak,
    this.claiming = false,
    this.lastClaim,
  });

  /// True once `GET /me` resolved with `dailyClaimedToday == false`.
  final bool claimable;
  final int streak;

  /// A claim request is in flight.
  final bool claiming;

  /// The last successful claim of this session (for the sheet's result view).
  final DailyClaimResult? lastClaim;
}

final dailyBonusProvider =
    NotifierProvider<DailyBonusController, DailyBonusState>(
        DailyBonusController.new);

class DailyBonusController extends Notifier<DailyBonusState> {
  @override
  DailyBonusState build() {
    final me = ref.watch(meProvider).valueOrNull;
    return DailyBonusState(
      claimable: me != null && !me.dailyClaimedToday,
      streak: me?.dailyStreak ?? 0,
    );
  }

  /// `POST /me/daily/claim`: credits the wallet with the server's balance and
  /// refreshes `meProvider` (which re-seeds streak/claimed-today).
  Future<DailyClaimResult> claim() async {
    state = DailyBonusState(
      claimable: state.claimable,
      streak: state.streak,
      claiming: true,
      lastClaim: state.lastClaim,
    );
    try {
      final result = await ref.read(trudeClientProvider).claimDaily();
      ref.read(walletProvider.notifier).set(result.balance);
      state = DailyBonusState(
        claimable: false,
        streak: result.streak,
        lastClaim: result,
      );
      ref.invalidate(meProvider);
      return result;
    } catch (_) {
      state = DailyBonusState(
        claimable: state.claimable,
        streak: state.streak,
        lastClaim: state.lastClaim,
      );
      rethrow;
    }
  }
}
