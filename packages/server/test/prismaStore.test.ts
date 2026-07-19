import { describe, expect, it } from 'vitest';
import type { PlayerGameStats } from '@trude/engine';

/**
 * Runs only when TEST_DATABASE_URL points at a disposable Postgres
 * (e.g. docker run -e POSTGRES_PASSWORD=test -e POSTGRES_DB=trude -p 55432:5432 postgres:16-alpine
 *  then `npx prisma db push`). Skipped otherwise.
 */
const url = process.env['TEST_DATABASE_URL'];

function gameStats(partial: Partial<PlayerGameStats>): PlayerGameStats {
  return {
    liesSurvived: 0, liesCaught: 0, checksWon: 0, checksLost: 0, cardsPickedUp: 0,
    quadsDiscarded: 0, jokerPassed: 0, jokerSmuggles: 0, truthfulThrows: 0, lyingThrows: 0,
    maxHandSize: 0, wasEverCaught: false, firstOut: false, ...partial,
  };
}

describe.skipIf(!url)('PrismaStore against real Postgres', () => {
  it('persists users, stats, results, and unlocks achievements exactly once', async () => {
    process.env['DATABASE_URL'] = url;
    const { PrismaStore } = await import('../src/store/prismaStore.js');
    const store = new PrismaStore();

    const suffix = Date.now().toString(36);
    const alice = await store.upsertGuest(`dev-a-${suffix}`, 'Alice', 'a1');
    const boris = await store.upsertGuest(`dev-b-${suffix}`, 'Boris', 'a2');
    expect((await store.upsertGuest(`dev-a-${suffix}`, 'Other', 'a9')).id).toBe(alice.id); // same device → same user

    await store.updateProfile(alice.id, { nickname: 'Alicia' });
    expect((await store.getUser(alice.id))?.nickname).toBe('Alicia');

    const result = {
      roomId: 'rtest', deckSize: 37, status: 'FINISHED' as const, loserUserId: boris.id,
      participants: [
        // Alice wins having lied 3 times uncaught and passed the joker twice.
        { userId: alice.id, placement: 1, stats: gameStats({ lyingThrows: 3, liesSurvived: 3, jokerPassed: 2, jokerSmuggles: 2, truthfulThrows: 2 }) },
        { userId: boris.id, placement: 2, stats: gameStats({ liesCaught: 2, wasEverCaught: true }) },
      ],
    };

    const unlocked = await store.recordGameResult(result);
    const aliceUnlocks = (unlocked.get(alice.id)?.achievements ?? []).map((a) => a.key).sort();
    expect(aliceUnlocks).toEqual(['hot_potato', 'it_wasnt_me']);

    // Same game again: stats accumulate, no duplicate unlocks.
    const again = await store.recordGameResult(result);
    expect(again.get(alice.id)?.achievements ?? []).toEqual([]);

    const stats = await store.getStats(alice.id);
    expect(stats.gamesPlayed).toBe(2);
    expect(stats.gamesWon).toBe(2);
    expect(stats.winStreak).toBe(2);
    expect(stats.jokerPassed).toBe(4);

    const borisStats = await store.getStats(boris.id);
    expect(borisStats.gamesLost).toBe(2);
    expect(borisStats.winStreak).toBe(0);

    const achievements = await store.getAchievements(alice.id);
    expect(achievements.map((a) => a.key).sort()).toEqual(['hot_potato', 'it_wasnt_me']);
  });

  it('meta economy round-trip: awards, wallet, daily, shop, leaderboard, delete', async () => {
    process.env['DATABASE_URL'] = url;
    const { PrismaStore } = await import('../src/store/prismaStore.js');
    const store = new PrismaStore();

    const suffix = Date.now().toString(36);
    const users = await Promise.all(['P', 'Q', 'R'].map((n, i) =>
      store.upsertGuest(`meta-${n}-${suffix}-0123456789`, `Meta${n}${i}`, 'a1')));

    // Rated public 3p game: coins + rating for everyone.
    const awards = await store.recordGameResult({
      roomId: `rmeta-${suffix}`, deckSize: 37, status: 'FINISHED',
      loserUserId: users[2]!.id, isPrivate: false, actionCount: 40,
      participants: users.map((u, i) => ({ userId: u.id, placement: i + 1, stats: gameStats({ truthfulThrows: 2 }) })),
    });
    const winner = awards.get(users[0]!.id)!;
    expect(winner.coins).toBe(25);
    expect(winner.rated).toBe(true);
    expect(winner.ratingDelta).toBeGreaterThan(0);
    expect(winner.balance).toBeGreaterThanOrEqual(25);
    expect(winner.quests).toHaveLength(3);

    // Daily claim is idempotent.
    const claim1 = await store.claimDaily(users[0]!.id);
    expect(claim1.claimed).toBe(true);
    expect(claim1.coins).toBe(10);
    const claim2 = await store.claimDaily(users[0]!.id);
    expect(claim2.claimed).toBe(false);
    expect(claim2.balance).toBe(claim1.balance);

    // Leaderboard has all three, ranked.
    const board = await store.getLeaderboard('alltime', 50, users[0]!.id);
    const ourRows = board.entries.filter((e) => users.some((u) => u.id === e.userId));
    expect(ourRows.length).toBe(3);
    expect(board.me?.value).toBe(winner.newRating);

    // Buy + equip a cosmetic (winner has 25 + daily 10 = 35 < 300, so grant via IAP first).
    const iap = await store.applyIapPurchase(users[0]!.id, {
      platform: 'google', productId: 'coins_small', orderId: `order-${suffix}`,
    });
    expect(iap.granted.coins).toBe(500);
    const replay = await store.applyIapPurchase(users[0]!.id, {
      platform: 'google', productId: 'coins_small', orderId: `order-${suffix}`,
    });
    expect(replay.alreadyProcessed).toBe(true);
    expect(replay.balance).toBe(iap.balance);

    const buy = await store.buyCosmetic(users[0]!.id, 'cb_crimson');
    expect(buy.balance).toBe(iap.balance - 300);
    const sel = await store.selectCosmetics(users[0]!.id, { cardBack: 'cb_crimson' });
    expect(sel.cardBack).toBe('cb_crimson');

    // Wallet always equals the ledger sum (invariant), then delete cascades.
    const profile = await store.getMetaProfile(users[0]!.id);
    expect(profile.coins).toBe(buy.balance);
    await store.deleteUser(users[0]!.id);
    expect(await store.getUser(users[0]!.id)).toBeNull();
    expect((await store.getOwnedCosmetics(users[0]!.id)).owned).toEqual(['cb_classic', 'felt_classic']);
  });
});
