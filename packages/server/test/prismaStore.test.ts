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
    const aliceUnlocks = (unlocked.get(alice.id) ?? []).map((a) => a.key).sort();
    expect(aliceUnlocks).toEqual(['hot_potato', 'it_wasnt_me']);

    // Same game again: stats accumulate, no duplicate unlocks.
    const again = await store.recordGameResult(result);
    expect(again.get(alice.id) ?? []).toEqual([]);

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
});
