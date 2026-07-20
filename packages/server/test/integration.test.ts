import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { Client as SdkClient, Room as SdkRoom } from 'colyseus.js';
import { matchMaker } from 'colyseus';
import type { Server } from 'colyseus';
import { config } from '../src/config.js';
import { createApp } from '../src/index.js';

const PORT = 25990 + Math.floor(Math.random() * 100);
const HTTP = `http://127.0.0.1:${PORT}`;
const WS = `ws://127.0.0.1:${PORT}`;

const RANKS_37 = ['6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];

let gameServer: Server;

beforeAll(async () => {
  gameServer = (await createApp()).gameServer;
  await gameServer.listen(PORT);
});

afterAll(async () => {
  await gameServer.gracefullyShutdown(false);
});

async function guestToken(nickname: string): Promise<{ token: string; userId: string }> {
  const res = await fetch(`${HTTP}/auth/guest`, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ deviceId: `device-${nickname}-0123456789`, nickname }),
  });
  expect(res.status).toBe(200);
  return res.json() as Promise<{ token: string; userId: string }>;
}

// ---------------------------------------------------------------------------
// Wire-level hidden-information scanner. Card faces may appear ONLY at these paths.
// ---------------------------------------------------------------------------

const ALLOWED_CARD_PATHS = [
  /^hand\.cards\[\d+\]$/,                                       // my own hand snapshot
  /^events\.events\[\d+\]\.flipped$/,                           // the public reveal
  /^events\.events\[\d+\]\.cards\[\d+\]$/,                      // fourDiscarded (public by rule)
  /^events\.events\[\d+\]\.jokerCard$/,                         // gameOver
  /^stateFull\.hand\[\d+\]$/,
  /^stateFull\.discarded\[\d+\]$/,
  /^stateFull\.lastResolution\.events\[\d+\]\.(flipped|cards\[\d+\]|jokerCard)$/,
];

function scanForCards(root: unknown, prefix: string, leaks: string[]): void {
  const walk = (node: unknown, path: string): void => {
    if (Array.isArray(node)) {
      node.forEach((v, i) => walk(v, `${path}[${i}]`));
      return;
    }
    if (node !== null && typeof node === 'object') {
      const obj = node as Record<string, unknown>;
      const looksLikeCard = typeof obj['rank'] === 'string' && typeof obj['id'] === 'string';
      if (looksLikeCard && !ALLOWED_CARD_PATHS.some((re) => re.test(path))) leaks.push(path);
      for (const [k, v] of Object.entries(obj)) walk(v, path ? `${path}.${k}` : k);
    }
  };
  walk(root, prefix);
}

// ---------------------------------------------------------------------------
// A protocol-level bot: plays truthful-ish leads, mixes trust and check.
// ---------------------------------------------------------------------------

interface Bot {
  nickname: string;
  userId: string;
  token: string;
  room: SdkRoom;
  seat: number;
  hand: { id: string; rank: string }[];
  actionCount: number;
  clientSeq: number;
  retired: string[];
  gameOver: Promise<Record<string, unknown>>;
  rewards: Promise<Record<string, unknown>>;
  leaks: string[];
  errors: string[];
  trace: string[];
  lastThrowCount: number;
  /** True once this bot's own seat went out (safe). */
  out: boolean;
  /** Consented-leave the room once actionCount reaches this (unless already out). */
  leaveAtAction: number | null;
  leftGame: boolean;
}

function attachBot(
  room: SdkRoom, nickname: string, userId: string, token: string,
  leaveAtAction: number | null = null,
): Bot {
  let resolveOver!: (e: Record<string, unknown>) => void;
  let resolveRewards!: (e: Record<string, unknown>) => void;
  const bot: Bot = {
    nickname, userId, token, room, seat: -1, hand: [], actionCount: -1, clientSeq: 0,
    retired: [], gameOver: new Promise((r) => { resolveOver = r; }),
    rewards: new Promise((r) => { resolveRewards = r; }), leaks: [], errors: [], trace: [],
    lastThrowCount: 1, out: false, leaveAtAction, leftGame: false,
  };

  room.onError((code, message) => bot.errors.push(`transport error ${code}: ${message ?? ''}`));
  room.onLeave((code) => bot.trace.push(`onLeave code=${code}`));

  room.onMessage('hand', (msg: { cards: { id: string; rank: string }[] }) => {
    scanForCards(msg, 'hand', bot.leaks);
    bot.hand = msg.cards;
  });
  room.onMessage('stateFull', (msg: unknown) => scanForCards(msg, 'stateFull', bot.leaks));
  room.onMessage('error', (msg: { code: string; message: string }) => {
    bot.errors.push(`${msg.code}: ${msg.message}`);
  });
  room.onMessage('pong', () => undefined);
  room.onMessage('reaction', () => undefined);
  room.onMessage('seatSwapRequested', () => undefined);
  room.onMessage('achievementUnlocked', () => undefined);
  room.onMessage('rewards', (msg: Record<string, unknown>) => resolveRewards(msg));

  room.onMessage('events', (batch: { actionCount: number; events: Record<string, unknown>[] }) => {
    scanForCards(batch, 'events', bot.leaks);
    bot.trace.push(`#${batch.actionCount} ${batch.events.map((e) => e['type']).join(',')}`);
    if (bot.trace.length > 60) bot.trace.shift();
    if (batch.actionCount >= 0) bot.actionCount = batch.actionCount;
    let myTurn: { phase: string; mustCheck: boolean } | null = null;
    for (const e of batch.events) {
      switch (e['type']) {
        case 'gameStarted': {
          const order = e['seatOrder'] as { seat: number; userId: string }[];
          bot.seat = order.find((s) => s.userId === userId)!.seat;
          break;
        }
        case 'fourDiscarded':
          bot.retired.push(e['rank'] as string);
          break;
        case 'playerOut':
          if (e['seat'] === bot.seat) bot.out = true;
          break;
        case 'cardsThrown':
          bot.lastThrowCount = e['count'] as number;
          break;
        case 'turnStarted':
          if (typeof e['durationMs'] !== 'number' || (e['durationMs'] as number) <= 0) {
            bot.errors.push(`turnStarted missing durationMs: ${JSON.stringify(e)}`);
          }
          if (e['seat'] === bot.seat) {
            myTurn = { phase: e['phase'] as string, mustCheck: e['mustCheck'] === true };
          }
          break;
        case 'gameOver':
          resolveOver(e);
          break;
      }
    }
    // Scripted mid-game leaver: quits consented before ever going out.
    if (bot.leaveAtAction !== null && !bot.leftGame && !bot.out
      && bot.actionCount >= bot.leaveAtAction) {
      bot.leftGame = true;
      void bot.room.leave(); // consented
      return;
    }
    if (myTurn) act(bot, myTurn);
  });

  return bot;
}

// Deterministic bots livelock (throw/throw/check cycles the same cards forever),
// so each bot plays a seeded-random policy like the engine fuzzer, which terminates.
let rngState = 0xC0FFEE;
function rand(n: number): number {
  rngState = (Math.imul(rngState, 1664525) + 1013904223) >>> 0;
  return rngState % n;
}

function act(bot: Bot, turn: { phase: string; mustCheck: boolean }): void {
  const envelope = { actionCount: bot.actionCount, clientSeq: ++bot.clientSeq };
  if (turn.phase === 'respond' && (turn.mustCheck || rand(3) === 0)) {
    bot.room.send('check', { ...envelope, flipIndex: rand(bot.lastThrowCount) });
    return;
  }
  const count = 1 + rand(Math.min(3, bot.hand.length));
  const pool = [...bot.hand];
  const cardIds: string[] = [];
  for (let i = 0; i < count; i++) cardIds.push(pool.splice(rand(pool.length), 1)[0]!.id);
  if (turn.phase === 'lead') {
    const first = bot.hand.find((c) => c.id === cardIds[0])!;
    const rank = first.rank !== 'JOKER' && !bot.retired.includes(first.rank)
      ? first.rank
      : RANKS_37.find((r) => !bot.retired.includes(r))!;
    bot.room.send('throwCards', { ...envelope, cardIds, rank });
  } else {
    bot.room.send('throwCards', { ...envelope, cardIds });
  }
}

// ---------------------------------------------------------------------------

describe('full game over real websockets', () => {
  it('three clients join, play to game over, stats persist, nothing leaks', { timeout: 120_000 }, async () => {
    const users = await Promise.all([guestToken('Alice'), guestToken('Boris'), guestToken('Chika')]);

    const sdk = new SdkClient(WS);
    const adminRoom = await sdk.create('trude', {
      token: users[0]!.token, name: 'Test room', deckSize: 37, supportsRewards: true,
    });
    const bots: Bot[] = [attachBot(adminRoom, 'Alice', users[0]!.userId, users[0]!.token)];

    for (let i = 1; i < 3; i++) {
      const room = await new SdkClient(WS).joinById(adminRoom.roomId, {
        token: users[i]!.token, supportsRewards: true,
      });
      bots.push(attachBot(room, ['', 'Boris', 'Chika'][i]!, users[i]!.userId, users[i]!.token));
    }

    adminRoom.send('startGame', { actionCount: -1, clientSeq: ++bots[0]!.clientSeq });

    let stallTimer: NodeJS.Timeout;
    const stallDump = new Promise<never>((_, reject) => {
      stallTimer = setTimeout(() => {
        const dump = bots.map((b) =>
          `--- ${b.nickname} seat=${b.seat} handSize=${b.hand.length} actionCount=${b.actionCount}\n` +
          `errors: ${b.errors.join('; ') || 'none'}\n` +
          `trace tail: ${b.trace.slice(-15).join(' | ')}`,
        ).join('\n');
        reject(new Error(`Game stalled after 20s.\n${dump}`));
      }, 20_000);
    });
    const results = await Promise.race([Promise.all(bots.map((b) => b.gameOver)), stallDump]);
    clearTimeout(stallTimer!);

    // Consistent outcome on every client.
    const loserSeats = new Set(results.map((r) => r['loserSeat']));
    expect(loserSeats.size).toBe(1);
    const placements = results[0]!['placements'] as { placement: number }[];
    expect(placements).toHaveLength(3);
    expect(new Set(placements.map((p) => p.placement))).toEqual(new Set([1, 2, 3]));
    const jokerCard = results[0]!['jokerCard'] as { rank: string };
    expect(jokerCard.rank).toBe('JOKER');

    // No client ever saw a card face it shouldn't have.
    for (const bot of bots) {
      expect(bot.leaks, `${bot.nickname} saw hidden cards at: ${bot.leaks.join(', ')}`).toEqual([]);
      expect(bot.errors, `${bot.nickname} got errors: ${bot.errors.join('; ')}`).toEqual([]);
    }

    // Every bot opted into rewards and gets its post-game economy summary.
    for (const bot of bots) {
      const rewards = await bot.rewards;
      expect(rewards['gameId'], `${bot.nickname} rewards.gameId`).toBeTruthy();
      expect(rewards['rated'], `${bot.nickname} rewards.rated`).toBe(true);
      expect(rewards['balance'] as number, `${bot.nickname} rewards.balance`).toBeGreaterThan(0);
      expect(Array.isArray(rewards['quests']), `${bot.nickname} rewards.quests`).toBe(true);
      expect((rewards['quests'] as unknown[]).length).toBe(3);
      expect(typeof rewards['newRating']).toBe('number');
    }

    // Stats + coins persisted for every participant.
    for (const user of users) {
      const me = await (await fetch(`${HTTP}/me`, { headers: { authorization: `Bearer ${user.token}` } })).json() as {
        stats: { gamesPlayed: number }; coins: number;
      };
      expect(me.stats.gamesPlayed).toBe(1);
      expect(me.coins).toBeGreaterThan(0);
    }

    // All-time leaderboard now ranks the three participants.
    const board = await (await fetch(`${HTTP}/leaderboard?scope=alltime`, {
      headers: { authorization: `Bearer ${users[0]!.token}` },
    })).json() as { entries: { userId: string; rank: number }[]; me: { rank: number } | null };
    const ranked = board.entries.filter((e) => users.some((u) => u.userId === e.userId));
    expect(ranked).toHaveLength(3);
    expect(board.me).not.toBeNull();

    for (const bot of bots) await bot.room.leave();
  });

  it('private rooms are joinable by code and hidden from the lobby list', async () => {
    const user = await guestToken('Diana');
    const room = await new SdkClient(WS).create('trude', { token: user.token, private: true });
    room.onMessage('stateFull', () => undefined);
    room.onMessage('events', () => undefined);
    room.onMessage('hand', () => undefined);

    const listing = await matchMaker.query({ name: 'trude' });
    const mine = listing.find((r) => r.roomId === room.roomId);
    expect(mine).toBeDefined();
    const code = (mine!.metadata as { joinCode: string }).joinCode;
    expect(code).toMatch(/^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{6}$/);
    expect(mine!.private).toBe(true);

    const found = await (await fetch(`${HTTP}/rooms/by-code/${code.toLowerCase()}`)).json() as { roomId: string };
    expect(found.roomId).toBe(room.roomId);

    const missing = await fetch(`${HTTP}/rooms/by-code/ZZZZZZ`);
    expect(missing.status).toBe(404);

    const friend = await guestToken('Egor');
    const joined = await new SdkClient(WS).joinById(found.roomId, { token: friend.token });
    expect(joined.roomId).toBe(room.roomId);
    await joined.leave();
    await room.leave();
  });

  it('rejects joins without a valid token', async () => {
    await expect(new SdkClient(WS).create('trude', { token: 'garbage' })).rejects.toThrow();
    await expect(new SdkClient(WS).create('trude', {})).rejects.toThrow();
  });

  it('a consented mid-game leaver ranks last with left:true and earns nothing', { timeout: 120_000 }, async () => {
    // Speed knobs so autopilot turns for the departed seat resolve in ms, and a
    // lower action floor so the stayers' awards never depend on game length.
    const cfg = config as unknown as { disconnectedTurnMs: number; disconnectedGraceMs: number };
    const eco = config.economy as unknown as { minActionsForAwards: number };
    const anim = config.animationGrace as unknown as Record<string, number>;
    const saved = {
      turn: cfg.disconnectedTurnMs, grace: cfg.disconnectedGraceMs,
      minActions: eco.minActionsForAwards, anim: { ...anim },
    };
    cfg.disconnectedTurnMs = 200;
    cfg.disconnectedGraceMs = 200;
    eco.minActionsForAwards = 10;
    for (const k of Object.keys(anim)) anim[k] = 0;
    try {
      const users = await Promise.all([guestToken('Fedor'), guestToken('Galya'), guestToken('Hank')]);
      const sdk = new SdkClient(WS);
      const adminRoom = await sdk.create('trude', {
        token: users[0]!.token, name: 'Leaver room', deckSize: 37, supportsRewards: true,
      });
      const bots: Bot[] = [attachBot(adminRoom, 'Fedor', users[0]!.userId, users[0]!.token)];
      // Hank consented-leaves once the game passes action 8 — long before going out.
      for (let i = 1; i < 3; i++) {
        const room = await new SdkClient(WS).joinById(adminRoom.roomId, {
          token: users[i]!.token, supportsRewards: true,
        });
        bots.push(attachBot(room, ['', 'Galya', 'Hank'][i]!, users[i]!.userId, users[i]!.token,
          i === 2 ? 8 : null));
      }
      adminRoom.send('startGame', { actionCount: -1, clientSeq: ++bots[0]!.clientSeq });

      const stayers = [bots[0]!, bots[1]!];
      let stallTimer: NodeJS.Timeout;
      const stallDump = new Promise<never>((_, reject) => {
        stallTimer = setTimeout(() => {
          const dump = bots.map((b) =>
            `--- ${b.nickname} seat=${b.seat} left=${b.leftGame} actionCount=${b.actionCount}\n` +
            `errors: ${b.errors.join('; ') || 'none'}\ntrace tail: ${b.trace.slice(-15).join(' | ')}`,
          ).join('\n');
          reject(new Error(`Leaver game stalled after 60s.\n${dump}`));
        }, 60_000);
      });
      const results = await Promise.race([Promise.all(stayers.map((b) => b.gameOver)), stallDump]);
      clearTimeout(stallTimer!);

      expect(bots[2]!.leftGame).toBe(true);
      const leaverId = users[2]!.userId;
      for (const r of results) {
        const placements = r['placements'] as { userId: string; placement: number; left?: boolean }[];
        expect(placements).toHaveLength(3);
        const leaver = placements.find((p) => p.userId === leaverId)!;
        expect(leaver.placement).toBe(3); // re-ranked last regardless of autopilot play
        expect(leaver.left).toBe(true);
        for (const p of placements) {
          if (p.userId !== leaverId) expect(p.left).toBeUndefined();
        }
      }
      for (const bot of stayers) {
        expect(bot.errors, `${bot.nickname} got errors: ${bot.errors.join('; ')}`).toEqual([]);
      }

      // The leaver earned nothing and took the last-place rating hit; stayers earned.
      const me = async (token: string) => (await fetch(`${HTTP}/me`, {
        headers: { authorization: `Bearer ${token}` },
      })).json() as Promise<{ coins: number; rating: number }>;
      const leaverMe = await me(users[2]!.token);
      expect(leaverMe.coins).toBe(0);
      expect(leaverMe.rating).toBeLessThan(1000);
      for (const u of [users[0]!, users[1]!]) {
        expect((await me(u.token)).coins).toBeGreaterThan(0);
      }

      // Rated for everyone: the leaderboard ranks all three.
      const board = await (await fetch(`${HTTP}/leaderboard?scope=alltime`, {
        headers: { authorization: `Bearer ${users[0]!.token}` },
      })).json() as { entries: { userId: string }[] };
      for (const u of users) {
        expect(board.entries.some((e) => e.userId === u.userId), u.userId).toBe(true);
      }

      for (const bot of stayers) await bot.room.leave();
    } finally {
      cfg.disconnectedTurnMs = saved.turn;
      cfg.disconnectedGraceMs = saved.grace;
      eco.minActionsForAwards = saved.minActions;
      Object.assign(anim, saved.anim);
    }
  });

  it('a block rejects joins in both directions with the BLOCKED marker', async () => {
    const ivan = await guestToken('Ivan');
    const jana = await guestToken('Jana');

    // Ivan blocks Jana over HTTP.
    const blockRes = await fetch(`${HTTP}/me/blocks`, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${ivan.token}` },
      body: JSON.stringify({ userId: jana.userId }),
    });
    expect(blockRes.status).toBe(200);

    const quiet = (room: SdkRoom) => {
      room.onMessage('stateFull', () => undefined);
      room.onMessage('events', () => undefined);
      room.onMessage('hand', () => undefined);
    };

    // Jana cannot join Ivan's room. The rejection surfaces as a transport-level
    // ERROR frame: code 4216 (Colyseus APPLICATION_ERROR), message 'BLOCKED'.
    const ivanRoom = await new SdkClient(WS).create('trude', { token: ivan.token });
    quiet(ivanRoom);
    const err = await new SdkClient(WS)
      .joinById(ivanRoom.roomId, { token: jana.token })
      .then(() => null, (e: unknown) => e as { message?: string; code?: number });
    expect(err).not.toBeNull();
    expect(String(err!.message)).toContain('BLOCKED');
    expect(err!.code).toBe(4216);

    // Same block, other direction: the blocker cannot join the blocked's room.
    const janaRoom = await new SdkClient(WS).create('trude', { token: jana.token });
    quiet(janaRoom);
    const err2 = await new SdkClient(WS)
      .joinById(janaRoom.roomId, { token: ivan.token })
      .then(() => null, (e: unknown) => e as { message?: string });
    expect(String(err2!.message)).toContain('BLOCKED');

    // Unblocking lifts the rejection.
    const del = await fetch(`${HTTP}/me/blocks/${jana.userId}`, {
      method: 'DELETE', headers: { authorization: `Bearer ${ivan.token}` },
    });
    expect(del.status).toBe(204);
    const joined = await new SdkClient(WS).joinById(ivanRoom.roomId, { token: jana.token });
    expect(joined.roomId).toBe(ivanRoom.roomId);
    await joined.leave();
    await ivanRoom.leave();
    await janaRoom.leave();
  });
});
