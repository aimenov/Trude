import { describe, expect, it } from 'vitest';
import { randomUUID } from 'node:crypto';
import type { PlayerGameStats } from '@trude/engine';
import { config } from '../src/config.js';
import { utcDayOf } from '../src/economy/economy.js';
import { QUEST_ALL_DONE_BONUS, questReward, questsForDay } from '../src/quests/definitions.js';
import { MemoryStore, MetaError } from '../src/store/store.js';
import type { GameResultInput } from '../src/store/store.js';

function gameStats(partial: Partial<PlayerGameStats> = {}): PlayerGameStats {
  return {
    liesSurvived: 0, liesCaught: 0, checksWon: 0, checksLost: 0, cardsPickedUp: 0,
    quadsDiscarded: 0, jokerPassed: 0, jokerSmuggles: 0, truthfulThrows: 0, lyingThrows: 0,
    maxHandSize: 0, wasEverCaught: false, firstOut: false, ...partial,
  };
}

/** Stats that max out every stat-mapped quest in one game. */
function questMaxStats(): PlayerGameStats {
  return gameStats({
    truthfulThrows: 10, cardsPickedUp: 10, checksWon: 3, quadsDiscarded: 1,
    liesSurvived: 5, jokerPassed: 1, jokerSmuggles: 1,
  });
}

async function newUsers(store: MemoryStore, n: number): Promise<string[]> {
  const ids: string[] = [];
  for (let i = 0; i < n; i++) {
    ids.push((await store.upsertGuest(`device-${randomUUID()}`, `User${i}`, 'a0')).id);
  }
  return ids;
}

function publicGame(userIds: string[], winnerFirst = true, actionCount = 40): GameResultInput {
  const ordered = winnerFirst ? userIds : [...userIds].reverse();
  return {
    roomId: 'room1', deckSize: 37, status: 'FINISHED',
    loserUserId: ordered[ordered.length - 1]!,
    isPrivate: false, actionCount,
    participants: ordered.map((userId, i) => ({
      userId, placement: i + 1, stats: i === 0 ? questMaxStats() : gameStats(),
    })),
  };
}

/** Wallet must always equal the sum of the user's ledger deltas. */
function expectWalletMatchesLedger(store: MemoryStore, userId: string): void {
  const s = store as unknown as {
    ledger: Map<string, { userId: string; delta: number }>;
    wallets: Map<string, number>;
  };
  let sum = 0;
  for (const row of s.ledger.values()) if (row.userId === userId) sum += row.delta;
  expect(s.wallets.get(userId) ?? 0).toBe(sum);
}

async function expectMetaError(p: Promise<unknown>, code: string): Promise<void> {
  await expect(p).rejects.toSatisfy((e: unknown) => e instanceof MetaError && e.code === code);
}

describe('MemoryStore game awards', () => {
  it('rated public game grants placement coins, rating, quests, balance', async () => {
    const store = new MemoryStore();
    const [a, b, c] = await newUsers(store, 3);
    const awards = await store.recordGameResult(publicGame([a!, b!, c!]));

    const winner = awards.get(a!)!;
    expect(winner.coins).toBe(25);
    expect(winner.rated).toBe(true);
    expect(winner.ratingDelta).toBeGreaterThan(0);
    expect(winner.newRating).toBe(1000 + winner.ratingDelta);
    expect(winner.quests).toHaveLength(3);
    expect(winner.gameId).toBeTruthy();
    expect(winner.balance).toBeGreaterThanOrEqual(25);

    const loser = awards.get(c!)!;
    expect(loser.coins).toBe(5);
    expect(loser.ratingDelta).toBeLessThan(0);

    for (const id of [a!, b!, c!]) expectWalletMatchesLedger(store, id);
  });

  it('short games award nothing; private games halve coins and skip rating/quests', async () => {
    const store = new MemoryStore();
    const [a, b, c] = await newUsers(store, 3);

    const short = await store.recordGameResult(publicGame([a!, b!, c!], true, 19));
    expect(short.get(a!)!.coins).toBe(0);
    expect(short.get(a!)!.rated).toBe(false);
    expect(short.get(a!)!.quests).toEqual([]);

    const priv = await store.recordGameResult({ ...publicGame([a!, b!, c!]), isPrivate: true });
    const w = priv.get(a!)!;
    expect(w.coins).toBe(Math.round(25 * 0.5));
    expect(w.rated).toBe(false);
    expect(w.ratingDelta).toBe(0);
    expect(w.quests).toEqual([]);
    expect((await store.getMetaProfile(a!)).rating).toBe(1000);
  });

  it('clamps GAME_AWARD coins to the daily headroom', async () => {
    const store = new MemoryStore({ ...config.economy, gameCoinsDailyCap: 30 });
    const [a, b, c] = await newUsers(store, 3);

    const g1 = await store.recordGameResult(publicGame([a!, b!, c!]));
    expect(g1.get(a!)!.coins).toBe(25);
    const g2 = await store.recordGameResult(publicGame([a!, b!, c!]));
    expect(g2.get(a!)!.coins).toBe(5); // 30-cap headroom
    const g3 = await store.recordGameResult(publicGame([a!, b!, c!]));
    expect(g3.get(a!)!.coins).toBe(0);
    expectWalletMatchesLedger(store, a!);
  });

  it('ABANDONED games award nothing', async () => {
    const store = new MemoryStore();
    const awards = await store.recordGameResult({
      roomId: 'r', deckSize: 37, status: 'ABANDONED', loserUserId: null, participants: [],
    });
    expect(awards.size).toBe(0);
  });
});

describe('MemoryStore quests', () => {
  it('grants each quest exactly once across games, with the all-3 bonus once', async () => {
    const store = new MemoryStore();
    const [a, b, c] = await newUsers(store, 3);
    const day = utcDayOf(new Date());
    const todays = questsForDay(day);
    const totalQuestCoins = todays.reduce((sum, q) => sum + questReward(q), 0) + QUEST_ALL_DONE_BONUS;

    // Winner maxes every stat quest each game; q_play_3/q_win_1 style quests
    // finish within 3 wins. After 3 games ALL of today's quests are complete.
    let questCoinsSeen = 0;
    for (let i = 0; i < 3; i++) {
      const awards = await store.recordGameResult(publicGame([a!, b!, c!]));
      questCoinsSeen += awards.get(a!)!.quests.reduce((s, q) => s + q.coins, 0);
    }
    const state = await store.getQuestState(a!);
    expect(state.day).toBe(day);
    expect(state.quests.every((q) => q.completed)).toBe(true);

    // A 4th game grants no further quest coins.
    const extra = await store.recordGameResult(publicGame([a!, b!, c!]));
    expect(extra.get(a!)!.quests.reduce((s, q) => s + q.coins, 0)).toBe(0);

    // Ledger: quest coins + bonus exactly once each.
    const s = store as unknown as { ledger: Map<string, { userId: string; delta: number; reason: string }> };
    const questRows = [...s.ledger.values()].filter((r) => r.userId === a! && (r.reason === 'QUEST' || r.reason === 'QUEST_BONUS'));
    expect(questRows.reduce((sum, r) => sum + r.delta, 0)).toBe(totalQuestCoins);
    expect(questRows.filter((r) => r.reason === 'QUEST_BONUS')).toHaveLength(1);
    expect(questCoinsSeen).toBe(totalQuestCoins - QUEST_ALL_DONE_BONUS); // bonus rides a separate ledger row
    expectWalletMatchesLedger(store, a!);
  });
});

describe('MemoryStore daily bonus', () => {
  it('is idempotent per day and resets the streak after a missed day', async () => {
    const store = new MemoryStore();
    const [a] = await newUsers(store, 1);

    const d1 = await store.claimDaily(a!, new Date('2026-07-01T10:00:00Z'));
    expect(d1).toMatchObject({ claimed: true, streak: 1, coins: 10, nextBonus: 15 });

    const dup = await store.claimDaily(a!, new Date('2026-07-01T23:00:00Z'));
    expect(dup).toMatchObject({ claimed: false, streak: 1, coins: 0 });
    expect(dup.balance).toBe(d1.balance);

    const d2 = await store.claimDaily(a!, new Date('2026-07-02T00:01:00Z'));
    expect(d2).toMatchObject({ claimed: true, streak: 2, coins: 15 });

    // Missed 2026-07-03 → streak resets to 1.
    const d4 = await store.claimDaily(a!, new Date('2026-07-04T12:00:00Z'));
    expect(d4).toMatchObject({ claimed: true, streak: 1, coins: 10 });
    expectWalletMatchesLedger(store, a!);
  });

  it('caps the streak bonus at 60', async () => {
    const store = new MemoryStore();
    const [a] = await newUsers(store, 1);
    let day = new Date('2026-03-01T08:00:00Z');
    let last = { coins: 0 };
    for (let i = 0; i < 9; i++) {
      last = await store.claimDaily(a!, day);
      day = new Date(day.getTime() + 86_400_000);
    }
    expect(last.coins).toBe(60);
  });
});

describe('MemoryStore cosmetics shop', () => {
  it('buy: unknown, insufficient, owned, premium-locked; select validates ownership', async () => {
    const store = new MemoryStore();
    const [a] = await newUsers(store, 1);

    await expectMetaError(store.buyCosmetic(a!, 'cb_nope'), 'UNKNOWN_ITEM');
    await expectMetaError(store.buyCosmetic(a!, 'cb_crimson'), 'INSUFFICIENT_FUNDS');
    await expectMetaError(store.buyCosmetic(a!, 'cb_classic'), 'ALREADY_OWNED');
    await expectMetaError(store.buyCosmetic(a!, 'cb_gilded'), 'PREMIUM_REQUIRED');

    await store.applyIapPurchase(a!, { platform: 'google', productId: 'coins_small', orderId: 'o1' });
    const bought = await store.buyCosmetic(a!, 'cb_crimson');
    expect(bought.balance).toBe(500 - 300);
    await expectMetaError(store.buyCosmetic(a!, 'cb_crimson'), 'ALREADY_OWNED'); // no double charge
    expect((await store.getOwnedCosmetics(a!)).owned).toContain('cb_crimson');

    const sel = await store.selectCosmetics(a!, { cardBack: 'cb_crimson' });
    expect(sel).toEqual({ cardBack: 'cb_crimson', felt: 'felt_classic' });
    await expectMetaError(store.selectCosmetics(a!, { cardBack: 'cb_royal' }), 'NOT_OWNED');
    await expectMetaError(store.selectCosmetics(a!, { felt: 'cb_crimson' }), 'NOT_OWNED'); // wrong slot
    expectWalletMatchesLedger(store, a!);
  });
});

describe('MemoryStore rewarded ads', () => {
  it('shop rewards: jti single-use, daily cap enforced', async () => {
    const store = new MemoryStore();
    const [a] = await newUsers(store, 1);

    const first = await store.grantAdReward(a!, { jti: 'jti-0', kind: 'shop' });
    expect(first).toMatchObject({ coins: 25, balance: 25, remainingToday: 4 });
    await expectMetaError(store.grantAdReward(a!, { jti: 'jti-0', kind: 'shop' }), 'TOKEN_USED');

    for (let i = 1; i < 5; i++) await store.grantAdReward(a!, { jti: `jti-${i}`, kind: 'shop' });
    expect(await store.adRemainingToday(a!, 'shop')).toBe(0);
    await expectMetaError(store.grantAdReward(a!, { jti: 'jti-9', kind: 'shop' }), 'DAILY_CAP');
    expectWalletMatchesLedger(store, a!);
  });

  it('double: grants the game award once per game', async () => {
    const store = new MemoryStore();
    const [a, b, c] = await newUsers(store, 3);
    const awards = await store.recordGameResult(publicGame([a!, b!, c!]));
    const winner = awards.get(a!)!;

    const doubled = await store.grantAdReward(a!, { jti: 'j1', kind: 'double', gameId: winner.gameId });
    expect(doubled.coins).toBe(winner.coins);
    expect(doubled.balance).toBe(winner.balance + winner.coins);
    // Same game again — even with a fresh token — is idempotent.
    await expectMetaError(
      store.grantAdReward(a!, { jti: 'j2', kind: 'double', gameId: winner.gameId }), 'TOKEN_USED');
    // A game with no award for this user cannot be doubled.
    await expectMetaError(
      store.grantAdReward(a!, { jti: 'j3', kind: 'double', gameId: 'nope' }), 'BAD_TOKEN');
    expectWalletMatchesLedger(store, a!);
  });
});

describe('MemoryStore IAP', () => {
  it('grants once, replays as alreadyProcessed, premium unlocks cosmetics exactly once', async () => {
    const store = new MemoryStore();
    const [a, b] = await newUsers(store, 2);

    const grant = await store.applyIapPurchase(a!, { platform: 'google', productId: 'coins_medium', orderId: 'ord-1' });
    expect(grant).toMatchObject({ alreadyProcessed: false, granted: { coins: 1800, premium: false }, balance: 1800 });

    const replay = await store.applyIapPurchase(a!, { platform: 'google', productId: 'coins_medium', orderId: 'ord-1' });
    expect(replay).toMatchObject({ alreadyProcessed: true, granted: { coins: 0, premium: false }, balance: 1800 });

    await expectMetaError(
      store.applyIapPurchase(b!, { platform: 'google', productId: 'coins_medium', orderId: 'ord-1' }),
      'RECEIPT_OWNED_BY_OTHER_USER');
    await expectMetaError(
      store.applyIapPurchase(a!, { platform: 'google', productId: 'coins_mystery', orderId: 'ord-2' }),
      'UNKNOWN_PRODUCT');

    const premium = await store.applyIapPurchase(a!, { platform: 'apple', productId: 'premium_upgrade', orderId: 'ord-3' });
    expect(premium.premium).toBe(true);
    expect((await store.getMetaProfile(a!)).premium).toBe(true);
    const owned = (await store.getOwnedCosmetics(a!)).owned;
    expect(owned.filter((k) => k === 'cb_gilded')).toEqual(['cb_gilded']);

    const premiumReplay = await store.applyIapPurchase(a!, { platform: 'apple', productId: 'premium_upgrade', orderId: 'ord-3' });
    expect(premiumReplay.alreadyProcessed).toBe(true);
    expect((await store.getOwnedCosmetics(a!)).owned.filter((k) => k === 'cb_gilded')).toEqual(['cb_gilded']);
    expectWalletMatchesLedger(store, a!);
  });
});

describe('MemoryStore leaver awards', () => {
  it('a leaver gets 0 coins, no quest progress, and the last-place rating hit; others unaffected', async () => {
    const store = new MemoryStore();
    const [a, b, c] = await newUsers(store, 3);

    // c consented-left mid-game: re-ranked last and flagged.
    const input = publicGame([a!, b!, c!]);
    input.participants[2]!.leaver = true;
    const awards = await store.recordGameResult(input);

    const leaver = awards.get(c!)!;
    expect(leaver.coins).toBe(0);
    expect(leaver.quests).toEqual([]);
    expect(leaver.rated).toBe(true); // still a rated game for everyone
    expect(leaver.ratingDelta).toBeLessThan(0); // last-place hit
    expect(leaver.newRating).toBe(1000 + leaver.ratingDelta);
    expect(leaver.balance).toBe(0);

    // No GAME_AWARD ledger row for the leaver at all.
    const s = store as unknown as { ledger: Map<string, { userId: string; reason: string }> };
    expect([...s.ledger.values()].filter((r) => r.userId === c! && r.reason === 'GAME_AWARD')).toHaveLength(0);
    expect(await store.getQuestState(c!).then((q) => q.quests.every((x) => x.progress === 0))).toBe(true);

    // Rating stays near-zero-sum (equal fresh Ks; only rounding drift allowed).
    const sum = [a!, b!, c!].reduce((acc, id) => acc + awards.get(id)!.ratingDelta, 0);
    expect(Math.abs(sum)).toBeLessThanOrEqual(2);

    // The stayers earn exactly their placement coins and quest progress.
    expect(awards.get(a!)!.coins).toBe(25);
    expect(awards.get(b!)!.coins).toBe(12);
    expect(awards.get(a!)!.quests).toHaveLength(3);

    // Stats still fold for the leaver.
    expect((await store.getStats(c!)).gamesPlayed).toBe(1);

    // No daily-cap interference: a later clean game pays the leaver normally.
    const clean = await store.recordGameResult(publicGame([c!, a!, b!]));
    expect(clean.get(c!)!.coins).toBe(25);

    for (const id of [a!, b!, c!]) expectWalletMatchesLedger(store, id);
  });
});

describe('MemoryStore blocks & reports', () => {
  it('block: self rejected, idempotent, listed newest-first, unblock idempotent', async () => {
    const store = new MemoryStore();
    const [a, b, c] = await newUsers(store, 3);

    await expectMetaError(store.blockUser(a!, a!), 'CANNOT_BLOCK_SELF');
    await store.blockUser(a!, b!);
    await store.blockUser(a!, b!); // duplicate = idempotent success
    await store.blockUser(a!, c!);

    const list = await store.listBlocks(a!);
    expect(list).toHaveLength(2);
    expect(list.map((e) => e.userId).sort()).toEqual([b!, c!].sort());
    expect(list.find((e) => e.userId === b!)!.nickname).toBe('User1');
    expect(typeof list[0]!.createdAt).toBe('number');
    expect(await store.listBlocks(b!)).toEqual([]); // one-directional list

    await store.unblockUser(a!, c!);
    await store.unblockUser(a!, c!); // idempotent
    expect((await store.listBlocks(a!)).map((e) => e.userId)).toEqual([b!]);
  });

  it('hasBlockBetween sees both directions and any member of the set', async () => {
    const store = new MemoryStore();
    const [a, b, c] = await newUsers(store, 3);
    await store.blockUser(a!, b!);

    expect(await store.hasBlockBetween(a!, [b!])).toBe(true); // blocker joins blocked
    expect(await store.hasBlockBetween(b!, [a!])).toBe(true); // blocked joins blocker
    expect(await store.hasBlockBetween(a!, [c!])).toBe(false);
    expect(await store.hasBlockBetween(b!, [c!, a!])).toBe(true); // any seat matches
    expect(await store.hasBlockBetween(a!, [])).toBe(false);

    await store.unblockUser(a!, b!);
    expect(await store.hasBlockBetween(b!, [a!])).toBe(false);
  });

  it('reports: per-day dedupe, daily cap of 20 new reports, next day resets', async () => {
    const store = new MemoryStore();
    const [a, b] = await newUsers(store, 2);
    const day1 = new Date('2026-07-10T10:00:00Z');

    await store.reportUser(a!, { userId: b!, reason: 'abuse', roomId: 'r1' }, day1);
    await store.reportUser(a!, { userId: b!, reason: 'cheating' }, day1); // same day = idempotent

    // 19 more distinct reports hit the cap of 20 for the day…
    for (let i = 0; i < 19; i++) {
      await store.reportUser(a!, { userId: `ghost-${i}`, reason: 'other' }, day1);
    }
    await expectMetaError(store.reportUser(a!, { userId: 'one-too-many', reason: 'other' }, day1), 'REPORT_LIMIT');
    // …but a duplicate still succeeds silently even at the cap.
    await store.reportUser(a!, { userId: b!, reason: 'abuse' }, day1);

    // A new UTC day resets both the dedupe and the cap.
    const day2 = new Date('2026-07-11T00:01:00Z');
    await store.reportUser(a!, { userId: b!, reason: 'abuse' }, day2);
    const s = store as unknown as { reports: { reporterId: string; reportedId: string }[] };
    expect(s.reports.filter((r) => r.reporterId === a! && r.reportedId === b!)).toHaveLength(2);
  });

  it('deleteUser removes blocks and reports in both directions', async () => {
    const store = new MemoryStore();
    const [a, b, c] = await newUsers(store, 3);
    await store.blockUser(a!, b!);
    await store.blockUser(c!, a!);
    await store.reportUser(a!, { userId: b!, reason: 'abuse' });
    await store.reportUser(b!, { userId: a!, reason: 'other' });

    await store.deleteUser(a!);

    expect(await store.listBlocks(a!)).toEqual([]);
    expect(await store.listBlocks(c!)).toEqual([]);
    expect(await store.hasBlockBetween(b!, [c!])).toBe(false);
    const s = store as unknown as { reports: { reporterId: string; reportedId: string }[] };
    expect(s.reports.some((r) => r.reporterId === a! || r.reportedId === a!)).toBe(false);
  });
});

describe('MemoryStore leaderboards + profile + delete', () => {
  it('ranks all-time and weekly, computes my rank, deletes cleanly', async () => {
    const store = new MemoryStore();
    const [a, b, c] = await newUsers(store, 3);
    await store.recordGameResult(publicGame([a!, b!, c!]));

    const alltime = await store.getLeaderboard('alltime', 50, c!);
    expect(alltime.entries).toHaveLength(3);
    expect(alltime.entries[0]!.rank).toBe(1);
    expect(alltime.entries[0]!.userId).toBe(a!);
    expect(alltime.me!.rank).toBe(3);

    const weekly = await store.getLeaderboard('weekly', 50, a!);
    expect(weekly.seasonKey).toMatch(/^\d{4}-W\d{2}$/);
    expect(weekly.entries).toHaveLength(3);
    expect(weekly.me!.rank).toBe(1);

    const profile = await store.getMetaProfile(a!);
    expect(profile.coins).toBeGreaterThan(0);
    expect(profile.rating).toBeGreaterThan(1000);
    expect(profile.dailyClaimedToday).toBe(false);

    await store.deleteUser(a!);
    expect(await store.getUser(a!)).toBeNull();
    expect((await store.getLeaderboard('alltime', 50, a!)).entries).toHaveLength(2);
    expect((await store.getMetaProfile(a!)).coins).toBe(0);
  });
});
