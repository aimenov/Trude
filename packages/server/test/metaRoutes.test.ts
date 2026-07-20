import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import type { Server } from 'colyseus';
import type { PlayerGameStats } from '@trude/engine';
import { createApp } from '../src/index.js';
import type { Store } from '../src/store/store.js';

const PORT = 26200 + Math.floor(Math.random() * 100);
const HTTP = `http://127.0.0.1:${PORT}`;

let gameServer: Server;
let store: Store;

beforeAll(async () => {
  const created = await createApp();
  gameServer = created.gameServer;
  store = created.store;
  await gameServer.listen(PORT);
});

afterAll(async () => {
  await gameServer.gracefullyShutdown(false);
});

interface Session { token: string; userId: string; }

async function guest(nickname: string): Promise<Session> {
  const res = await fetch(`${HTTP}/auth/guest`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceId: `device-${nickname}-0123456789`, nickname }),
  });
  expect(res.status).toBe(200);
  return res.json() as Promise<Session>;
}

function call(method: string, path: string, session: Session | null, body?: unknown): Promise<globalThis.Response> {
  return fetch(`${HTTP}${path}`, {
    method,
    headers: {
      ...(session ? { authorization: `Bearer ${session.token}` } : {}),
      ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
    },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  });
}

function gameStats(partial: Partial<PlayerGameStats> = {}): PlayerGameStats {
  return {
    liesSurvived: 0, liesCaught: 0, checksWon: 0, checksLost: 0, cardsPickedUp: 0,
    quadsDiscarded: 0, jokerPassed: 0, jokerSmuggles: 0, truthfulThrows: 0, lyingThrows: 0,
    maxHandSize: 0, wasEverCaught: false, firstOut: false, ...partial,
  };
}

/** Seeds a finished rated game directly through the store; returns per-user awards. */
async function seedRatedGame(users: Session[], roomId: string) {
  return store.recordGameResult({
    roomId, deckSize: 37, status: 'FINISHED',
    loserUserId: users[users.length - 1]!.userId,
    isPrivate: false, actionCount: 42,
    participants: users.map((u, i) => ({ userId: u.userId, placement: i + 1, stats: gameStats() })),
  });
}

describe('meta routes', () => {
  it('401s without a bearer token on every authed route', async () => {
    const routes: [string, string, unknown?][] = [
      ['GET', '/leaderboard'], ['POST', '/me/daily/claim'], ['GET', '/me/quests'],
      ['GET', '/me/cosmetics'], ['POST', '/shop/buy', { itemKey: 'cb_crimson' }],
      ['GET', '/ads/token?kind=shop'], ['POST', '/ads/reward', { token: 'x' }],
      ['POST', '/iap/google', { purchaseToken: 'x', productId: 'coins_small' }],
      ['POST', '/iap/apple', { receipt: 'x' }], ['DELETE', '/me'],
      ['GET', '/me/blocks'], ['POST', '/me/blocks', { userId: 'x' }],
      ['DELETE', '/me/blocks/x'], ['POST', '/reports', { userId: 'x', reason: 'abuse' }],
    ];
    for (const [method, path, body] of routes) {
      const res = await call(method, path, null, body);
      expect(res.status, `${method} ${path}`).toBe(401);
    }
  });

  it('GET /catalog/cosmetics is public and lists the v1 catalog', async () => {
    const res = await fetch(`${HTTP}/catalog/cosmetics`);
    expect(res.status).toBe(200);
    const data = await res.json() as { items: { key: string; kind: string; price: number; premiumOnly: boolean }[] };
    expect(data.items.length).toBe(10);
    const gilded = data.items.find((i) => i.key === 'cb_gilded')!;
    expect(gilded.premiumOnly).toBe(true);
    expect(data.items.find((i) => i.key === 'felt_navy')!.price).toBe(400);
  });

  it('GET /me carries the meta extension fields', async () => {
    const u = await guest('MetaMe');
    const me = await (await call('GET', '/me', u)).json() as Record<string, unknown>;
    expect(me['coins']).toBe(0);
    expect(me['rating']).toBe(1000);
    expect(me['premium']).toBe(false);
    expect(me['dailyStreak']).toBe(0);
    expect(me['dailyClaimedToday']).toBe(false);
    expect(me['selected']).toEqual({ cardBack: 'cb_classic', felt: 'felt_classic' });
  });

  it('daily claim round-trip: grant then idempotent replay', async () => {
    const u = await guest('Daily');
    const first = await (await call('POST', '/me/daily/claim', u)).json() as Record<string, unknown>;
    expect(first['claimed']).toBe(true);
    expect(first['streak']).toBe(1);
    expect(first['coins']).toBe(10);
    expect(first['balance']).toBe(10);
    expect(first['nextBonus']).toBe(15);

    const again = await (await call('POST', '/me/daily/claim', u)).json() as Record<string, unknown>;
    expect(again['claimed']).toBe(false);
    expect(again['balance']).toBe(10);

    const me = await (await call('GET', '/me', u)).json() as Record<string, unknown>;
    expect(me['coins']).toBe(10);
    expect(me['dailyClaimedToday']).toBe(true);
  });

  it('GET /me/quests returns 3 quests for today', async () => {
    const u = await guest('Quester');
    const data = await (await call('GET', '/me/quests', u)).json() as {
      day: string; quests: { key: string; target: number; reward: number; progress: number; completed: boolean }[];
    };
    expect(data.day).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(data.quests).toHaveLength(3);
    for (const q of data.quests) {
      expect(q.progress).toBe(0);
      expect(q.completed).toBe(false);
      expect([15, 20, 30]).toContain(q.reward);
    }
  });

  it('shop round-trip: buy errors, purchase, equip via PATCH /me', async () => {
    const u = await guest('Shopper');
    expect((await call('POST', '/shop/buy', u, { itemKey: 'cb_wat' })).status).toBe(404);
    expect((await call('POST', '/shop/buy', u, { itemKey: 'cb_crimson' })).status).toBe(402);
    expect((await call('POST', '/shop/buy', u, { itemKey: 'cb_gilded' })).status).toBe(403);
    expect((await call('POST', '/shop/buy', u, {})).status).toBe(400);

    // Fund via fake IAP, then buy.
    const iapRes = await call('POST', '/iap/google', u, {
      purchaseToken: 'fake:shopper-order-1:coins_small', productId: 'coins_small',
    });
    expect(iapRes.status).toBe(200);
    const bought = await (await call('POST', '/shop/buy', u, { itemKey: 'cb_crimson' })).json() as Record<string, unknown>;
    expect(bought).toEqual({ itemKey: 'cb_crimson', balance: 200 });
    expect((await call('POST', '/shop/buy', u, { itemKey: 'cb_crimson' })).status).toBe(409);

    // Equip owned; reject unowned; wrong-slot key rejected.
    const patched = await (await call('PATCH', '/me', u, { selectedCardBack: 'cb_crimson' })).json() as Record<string, unknown>;
    expect(patched['selected']).toEqual({ cardBack: 'cb_crimson', felt: 'felt_classic' });
    expect((await call('PATCH', '/me', u, { selectedFelt: 'felt_navy' })).status).toBe(403);
    expect((await call('PATCH', '/me', u, { selectedFelt: 'cb_crimson' })).status).toBe(403);

    const mine = await (await call('GET', '/me/cosmetics', u)).json() as { owned: string[]; selected: Record<string, string> };
    expect(mine.owned).toEqual(expect.arrayContaining(['cb_classic', 'felt_classic', 'cb_crimson']));
    expect(mine.selected).toEqual({ cardBack: 'cb_crimson', felt: 'felt_classic' });
  });

  it('ads round-trip: shop token grants 25 once; caps enforced', async () => {
    const u = await guest('AdWatcher');
    const tokenRes = await (await call('GET', '/ads/token?kind=shop', u)).json() as { token: string; remainingToday: number };
    expect(tokenRes.remainingToday).toBe(5);

    const reward = await (await call('POST', '/ads/reward', u, { token: tokenRes.token })).json() as Record<string, unknown>;
    expect(reward).toEqual({ coins: 25, balance: 25, remainingToday: 4 });

    // Replay of the same token: 409 TOKEN_USED.
    const replay = await call('POST', '/ads/reward', u, { token: tokenRes.token });
    expect(replay.status).toBe(409);
    expect((await replay.json() as Record<string, unknown>)['error']).toBe('TOKEN_USED');

    // Garbage token: 401 BAD_TOKEN. Someone else's token: 401 too.
    expect((await call('POST', '/ads/reward', u, { token: 'garbage' })).status).toBe(401);
    const other = await guest('AdThief');
    const otherToken = await (await call('GET', '/ads/token?kind=shop', other)).json() as { token: string };
    expect((await call('POST', '/ads/reward', u, { token: otherToken.token })).status).toBe(401);

    // Burn the remaining 4 → 429 DAILY_CAP.
    for (let i = 0; i < 4; i++) {
      const t = await (await call('GET', '/ads/token?kind=shop', u)).json() as { token: string };
      expect((await call('POST', '/ads/reward', u, { token: t.token })).status).toBe(200);
    }
    const t6 = await (await call('GET', '/ads/token?kind=shop', u)).json() as { token: string; remainingToday: number };
    expect(t6.remainingToday).toBe(0);
    expect((await call('POST', '/ads/reward', u, { token: t6.token })).status).toBe(429);
  });

  it('ads double: grants the game award once per game', async () => {
    const users = [await guest('DblWin'), await guest('DblMid'), await guest('DblLose')];
    const awards = await seedRatedGame(users, 'dbl-room');
    const winner = awards.get(users[0]!.userId)!;
    expect(winner.coins).toBe(25);

    // kind=double without gameId → 400.
    expect((await call('GET', '/ads/token?kind=double', users[0])).status).toBe(400);

    const t = await (await call('GET', `/ads/token?kind=double&gameId=${winner.gameId}`, users[0])).json() as { token: string };
    const doubled = await (await call('POST', '/ads/reward', users[0], { token: t.token })).json() as Record<string, unknown>;
    expect(doubled['coins']).toBe(25);
    expect(doubled['balance']).toBe(winner.balance + 25);

    // Fresh token, same game → 409.
    const t2 = await (await call('GET', `/ads/token?kind=double&gameId=${winner.gameId}`, users[0])).json() as { token: string };
    expect((await call('POST', '/ads/reward', users[0], { token: t2.token })).status).toBe(409);
  });

  it('iap: invalid receipt, unknown product, cross-user replay, premium grant', async () => {
    const u = await guest('Buyer');
    expect((await call('POST', '/iap/google', u, { purchaseToken: 'not-fake', productId: 'coins_small' })).status).toBe(400);
    expect((await call('POST', '/iap/google', u, {
      purchaseToken: 'fake:o-x:coins_unknown', productId: 'coins_unknown',
    })).status).toBe(404);
    // productId mismatch between body and receipt → invalid.
    expect((await call('POST', '/iap/google', u, {
      purchaseToken: 'fake:o-y:coins_small', productId: 'coins_large',
    })).status).toBe(400);

    const grant = await (await call('POST', '/iap/apple', u, { receipt: 'fake:apple-1:premium_upgrade' })).json() as Record<string, unknown>;
    expect(grant['premium']).toBe(true);
    expect(grant['alreadyProcessed']).toBe(false);
    expect((grant['granted'] as Record<string, unknown>)['premium']).toBe(true);

    const replay = await (await call('POST', '/iap/apple', u, { receipt: 'fake:apple-1:premium_upgrade' })).json() as Record<string, unknown>;
    expect(replay['alreadyProcessed']).toBe(true);

    const thief = await guest('Thief');
    expect((await call('POST', '/iap/apple', thief, { receipt: 'fake:apple-1:premium_upgrade' })).status).toBe(409);

    // Premium user now owns cb_gilded and can buy/equip it—already granted.
    const mine = await (await call('GET', '/me/cosmetics', u)).json() as { owned: string[] };
    expect(mine.owned).toContain('cb_gilded');
    const me = await (await call('GET', '/me', u)).json() as Record<string, unknown>;
    expect(me['premium']).toBe(true);
  });

  it('leaderboard: ranked entries with me, scope validation, limit clamp', async () => {
    const users = [await guest('LbA'), await guest('LbB'), await guest('LbC')];
    await seedRatedGame(users, 'lb-room');

    const bad = await call('GET', '/leaderboard?scope=daily', users[0]);
    expect(bad.status).toBe(400);
    expect((await call('GET', '/leaderboard?limit=0', users[0])).status).toBe(400);

    const alltime = await (await call('GET', '/leaderboard?scope=alltime', users[0])).json() as {
      scope: string; entries: { rank: number; userId: string; nickname: string; value: number }[];
      me: { rank: number; value: number } | null;
    };
    expect(alltime.scope).toBe('alltime');
    expect(alltime.entries.length).toBeGreaterThanOrEqual(3);
    expect(alltime.entries[0]!.rank).toBe(1);
    expect(alltime.me).not.toBeNull();

    const weekly = await (await call('GET', '/leaderboard?scope=weekly&limit=2', users[2])).json() as {
      scope: string; seasonKey?: string; entries: unknown[]; me: { rank: number } | null;
    };
    expect(weekly.scope).toBe('weekly');
    expect(weekly.seasonKey).toMatch(/^\d{4}-W\d{2}$/);
    expect(weekly.entries.length).toBeLessThanOrEqual(2);
    expect(weekly.me).not.toBeNull(); // pinned rank even when off-page
  });

  it('blocks round-trip: self 400, block, list, idempotent unblock', async () => {
    const u1 = await guest('Blocker');
    const u2 = await guest('Blockee');

    const self = await call('POST', '/me/blocks', u1, { userId: u1.userId });
    expect(self.status).toBe(400);
    expect((await self.json() as Record<string, unknown>)['error']).toBe('CANNOT_BLOCK_SELF');
    expect((await call('POST', '/me/blocks', u1, {})).status).toBe(400);

    const blocked = await (await call('POST', '/me/blocks', u1, { userId: u2.userId })).json();
    expect(blocked).toEqual({ blocked: true });
    expect((await call('POST', '/me/blocks', u1, { userId: u2.userId })).status).toBe(200); // idempotent

    const list = await (await call('GET', '/me/blocks', u1)).json() as {
      blocks: { userId: string; nickname: string; createdAt: number }[];
    };
    expect(list.blocks).toHaveLength(1);
    expect(list.blocks[0]).toMatchObject({ userId: u2.userId, nickname: 'Blockee' });
    expect(typeof list.blocks[0]!.createdAt).toBe('number');
    // The blocked side's own list stays empty.
    expect(((await (await call('GET', '/me/blocks', u2)).json()) as { blocks: unknown[] }).blocks).toEqual([]);

    expect((await call('DELETE', `/me/blocks/${u2.userId}`, u1)).status).toBe(204);
    expect(((await (await call('GET', '/me/blocks', u1)).json()) as { blocks: unknown[] }).blocks).toEqual([]);
    expect((await call('DELETE', `/me/blocks/${u2.userId}`, u1)).status).toBe(204); // idempotent
  });

  it('reports round-trip: received, bad reason 400, same-day dedupe 200, cap 429', async () => {
    const u = await guest('Reporter');
    const target = await guest('ReportTarget');

    const ok = await (await call('POST', '/reports', u, {
      userId: target.userId, reason: 'abuse', roomId: 'room-9',
    })).json();
    expect(ok).toEqual({ received: true });

    expect((await call('POST', '/reports', u, { userId: target.userId, reason: 'volcano' })).status).toBe(400);
    expect((await call('POST', '/reports', u, { userId: target.userId })).status).toBe(400);

    // Same reporter → same target, same day: idempotent 200.
    expect((await call('POST', '/reports', u, { userId: target.userId, reason: 'cheating' })).status).toBe(200);

    // Fill the day's remaining 19 slots through the store, then the cap bites.
    for (let i = 0; i < 19; i++) {
      await store.reportUser(u.userId, { userId: `ghost-${i}`, reason: 'other' });
    }
    const capped = await call('POST', '/reports', u, { userId: 'one-too-many', reason: 'other' });
    expect(capped.status).toBe(429);
    expect((await capped.json() as Record<string, unknown>)['error']).toBe('REPORT_LIMIT');
  });

  it('DELETE /me removes the account and its data', async () => {
    const u = await guest('Doomed');
    await call('POST', '/me/daily/claim', u);
    const del = await call('DELETE', '/me', u);
    expect(del.status).toBe(204);
    expect((await call('GET', '/me', u)).status).toBe(404);
  });
});
