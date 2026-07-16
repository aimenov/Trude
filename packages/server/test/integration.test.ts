import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { Client as SdkClient, Room as SdkRoom } from 'colyseus.js';
import { matchMaker } from 'colyseus';
import type { Server } from 'colyseus';
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
  leaks: string[];
  errors: string[];
  trace: string[];
  lastThrowCount: number;
}

function attachBot(room: SdkRoom, nickname: string, userId: string, token: string): Bot {
  let resolveOver!: (e: Record<string, unknown>) => void;
  const bot: Bot = {
    nickname, userId, token, room, seat: -1, hand: [], actionCount: -1, clientSeq: 0,
    retired: [], gameOver: new Promise((r) => { resolveOver = r; }), leaks: [], errors: [], trace: [],
    lastThrowCount: 1,
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
        case 'cardsThrown':
          bot.lastThrowCount = e['count'] as number;
          break;
        case 'turnStarted':
          if (e['seat'] === bot.seat) {
            myTurn = { phase: e['phase'] as string, mustCheck: e['mustCheck'] === true };
          }
          break;
        case 'gameOver':
          resolveOver(e);
          break;
      }
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
    const adminRoom = await sdk.create('trude', { token: users[0]!.token, name: 'Test room', deckSize: 37 });
    const bots: Bot[] = [attachBot(adminRoom, 'Alice', users[0]!.userId, users[0]!.token)];

    for (let i = 1; i < 3; i++) {
      const room = await new SdkClient(WS).joinById(adminRoom.roomId, { token: users[i]!.token });
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

    // Stats persisted for every participant.
    for (const user of users) {
      const me = await (await fetch(`${HTTP}/me`, { headers: { authorization: `Bearer ${user.token}` } })).json() as {
        stats: { gamesPlayed: number };
      };
      expect(me.stats.gamesPlayed).toBe(1);
    }

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
});
