import { describe, expect, it } from 'vitest';
import { createGame, reduce, nameableRanks, assertInvariants } from '../src/index.js';
import type { EngineAction, EngineEvent, GameState } from '../src/index.js';
import { buildRiggedDeck, newGame, playRandomGame, step } from './helpers.js';

function types(events: EngineEvent[]): string[] {
  return events.map((e) => e.type);
}

function expectError(state: GameState, action: EngineAction, code: string): void {
  const r = reduce(state, action);
  expect(r.ok).toBe(false);
  if (!r.ok) expect(r.error.code).toBe(code);
}

// Rigged 2-player 37-card game, first leader seat 0:
//   seat0 (19): three 6s, three each of 7/8/9/10/J, and the ace of clubs
//   seat1 (18): the fourth 6, one each of 7/8/9/10/J (spades), quad Q, quad K, three aces, JOKER
// The Q and K quads auto-discard at the deal; picking up seat0's three 6s completes seat1's 6-quad.
const RIGGED = buildRiggedDeck(
  [
    ['6C', '6D', '6H', '7C', '7D', '7H', '8C', '8D', '8H', '9C', '9D', '9H', '10C', '10D', '10H', 'JC', 'JD', 'JH', 'AC'],
    ['6S', '7S', '8S', '9S', '10S', 'JS', 'QC', 'QD', 'QH', 'QS', 'KC', 'KD', 'KH', 'KS', 'AD', 'AH', 'AS', 'JOKER'],
  ],
  0,
  37,
);

function riggedGame() {
  return newGame(2, 37, 'rigged', { deck: RIGGED, firstLeaderSeat: 0 });
}

describe('createGame', () => {
  it('deals round-robin, auto-discards initial quads, and starts the lead turn', () => {
    const { state, events } = riggedGame();
    assertInvariants(state);
    expect(types(events)).toEqual(['dealt', 'fourDiscarded', 'fourDiscarded', 'turnStarted']);
    expect(events[0]).toMatchObject({ handCounts: [19, 18], firstLeaderSeat: 0 });
    expect(events[1]).toMatchObject({ seat: 1, rank: 'Q' });
    expect(events[2]).toMatchObject({ seat: 1, rank: 'K' });
    expect(state.retiredRanks).toEqual(['Q', 'K']);
    expect(state.players[1]!.hand).toHaveLength(10);
    expect(state.phase).toEqual({ kind: 'lead', seat: 0 });
  });

  it('rejects bad player counts and duplicate ids', () => {
    expect(() => createGame({ deckSize: 37, seed: 's' }, ['a'])).toThrow();
    expect(() => createGame({ deckSize: 37, seed: 's' }, ['a', 'b', 'c', 'd', 'e', 'f', 'g'])).toThrow();
    expect(() => createGame({ deckSize: 53, seed: 's' }, Array.from({ length: 9 }, (_, i) => `p${i}`))).toThrow();
    expect(() => createGame({ deckSize: 37, seed: 's' }, ['a', 'a'])).toThrow();
  });

  it('is deterministic for the same seed and diverges across seeds', () => {
    const a = newGame(4, 53, 'seed-x').state;
    const b = newGame(4, 53, 'seed-x').state;
    const c = newGame(4, 53, 'seed-y').state;
    expect(a).toEqual(b);
    expect(a.players.map((p) => p.hand)).not.toEqual(c.players.map((p) => p.hand));
  });
});

describe('validation', () => {
  it('covers every rejection code', () => {
    const { state } = riggedGame();
    const hand0 = state.players[0]!.hand;

    expectError(state, { type: 'throw', seat: 1, cardIds: ['c1'], rank: '6' }, 'NOT_YOUR_TURN');
    expectError(state, { type: 'throw', seat: 0, cardIds: [], rank: '6' }, 'BAD_CARDS');
    expectError(state, { type: 'throw', seat: 0, cardIds: hand0.slice(0, 4).map((c) => c.id), rank: '6' }, 'BAD_CARDS');
    expectError(state, { type: 'throw', seat: 0, cardIds: [hand0[0]!.id, hand0[0]!.id], rank: '6' }, 'BAD_CARDS');
    expectError(state, { type: 'throw', seat: 0, cardIds: ['nope'], rank: '6' }, 'BAD_CARDS');
    expectError(state, { type: 'throw', seat: 0, cardIds: [hand0[0]!.id] }, 'RANK_REQUIRED');
    expectError(state, { type: 'throw', seat: 0, cardIds: [hand0[0]!.id], rank: 'JOKER' as never }, 'RANK_JOKER');
    expectError(state, { type: 'throw', seat: 0, cardIds: [hand0[0]!.id], rank: 'Q' }, 'RANK_DEAD');
    expectError(state, { type: 'check', seat: 0, flipIndex: 0 }, 'NOTHING_TO_CHECK');

    const thrown = step(state, { type: 'throw', seat: 0, cardIds: [hand0[0]!.id], rank: '6' }).state;
    const hand1 = thrown.players[1]!.hand;
    expectError(thrown, { type: 'throw', seat: 1, cardIds: [hand1[0]!.id], rank: '7' }, 'RANK_MISMATCH');
    expectError(thrown, { type: 'check', seat: 1, flipIndex: 1 }, 'BAD_FLIP_INDEX');
    expectError(thrown, { type: 'check', seat: 1, flipIndex: -1 }, 'BAD_FLIP_INDEX');
    expectError(thrown, { type: 'check', seat: 0, flipIndex: 0 }, 'NOT_YOUR_TURN');
  });
});

describe('check resolution', () => {
  it('matched check: checker picks up, pickup completes a quad, reveal winner leads', () => {
    let { state } = riggedGame();
    const sixes = state.players[0]!.hand.filter((c) => c.rank === '6').map((c) => c.id);
    expect(sixes).toHaveLength(3);

    state = step(state, { type: 'throw', seat: 0, cardIds: sixes, rank: '6' }).state;
    const { state: after, events } = step(state, { type: 'check', seat: 1, flipIndex: 1 });

    expect(types(events)).toEqual(['checkResult', 'fourDiscarded', 'turnStarted']);
    expect(events[0]).toMatchObject({
      checkerSeat: 1, targetSeat: 0, matched: true, pickerSeat: 1, pickedCount: 3, nextLeadSeat: 0,
    });
    expect(events[1]).toMatchObject({ seat: 1, rank: '6' });
    expect(after.retiredRanks).toEqual(['Q', 'K', '6']);
    expect(after.phase).toEqual({ kind: 'lead', seat: 0 }); // winner (vindicated thrower) leads
    expect(after.players[1]!.stats.checksLost).toBe(1);
    expect(after.players[1]!.stats.cardsPickedUp).toBe(3);
    expect(after.players[0]!.stats.truthfulThrows).toBe(1);
  });

  it('joker never matches: thrower is caught and picks the pile back up', () => {
    let { state } = riggedGame();
    const sixes = state.players[0]!.hand.filter((c) => c.rank === '6').map((c) => c.id);
    state = step(state, { type: 'throw', seat: 0, cardIds: sixes, rank: '6' }).state;
    state = step(state, { type: 'check', seat: 1, flipIndex: 0 }).state;

    // seat0 leads again; seat1 trusts with the joker; seat0 flips it.
    const ace = state.players[0]!.hand.find((c) => c.rank === 'A')!;
    state = step(state, { type: 'throw', seat: 0, cardIds: [ace.id], rank: 'A' }).state;
    const joker = state.players[1]!.hand.find((c) => c.rank === 'JOKER')!;
    state = step(state, { type: 'throw', seat: 1, cardIds: [joker.id] }).state;
    expect(state.players[1]!.stats.lyingThrows).toBe(1);

    const { state: after, events } = step(state, { type: 'check', seat: 0, flipIndex: 0 });
    const result = events[0]!;
    expect(result).toMatchObject({
      type: 'checkResult', matched: false, pickerSeat: 1, pickedCount: 2, nextLeadSeat: 0,
    });
    if (result.type === 'checkResult') expect(result.flipped.rank).toBe('JOKER');
    expect(after.players[0]!.stats.checksWon).toBe(1);
    expect(after.players[1]!.stats.liesCaught).toBe(1);
    expect(after.players[1]!.stats.wasEverCaught).toBe(true);
    expect(after.phase).toEqual({ kind: 'lead', seat: 0 }); // winner (successful checker) leads
  });
});

describe('forced check on an emptied hand', () => {
  it('rejects trust and requires a check when the previous thrower has no cards left', () => {
    let { state } = newGame(2, 37, 'mustcheck-seed');
    for (let guard = 0; guard < 100; guard++) {
      const phase = state.phase;
      if (phase.kind === 'over') throw new Error('game ended before the scenario triggered');
      if (phase.kind === 'respond' && phase.mustCheck) break;
      const actor = state.players[phase.seat]!;
      const cardIds = actor.hand.slice(0, Math.min(3, actor.hand.length)).map((c) => c.id);
      const action: EngineAction = phase.kind === 'lead'
        ? { type: 'throw', seat: phase.seat, cardIds, rank: nameableRanks(state)[0]! }
        : { type: 'throw', seat: phase.seat, cardIds };
      state = step(state, action).state;
    }
    const phase = state.phase;
    expect(phase).toMatchObject({ kind: 'respond', mustCheck: true });
    if (phase.kind !== 'respond') return;

    const responder = state.players[phase.seat]!;
    expectError(state, { type: 'throw', seat: phase.seat, cardIds: [responder.hand[0]!.id] }, 'MUST_CHECK');

    const { state: after, events } = step(state, { type: 'check', seat: phase.seat, flipIndex: 0 });
    expect(types(events)).toContain('checkResult');
    assertInvariants(after);
  });
});

describe('timeouts', () => {
  it('auto-leads one card and auto-checks on respond', () => {
    let { state } = newGame(3, 53, 'timeout-seed');
    expect(state.phase.kind).toBe('lead');

    const r1 = step(state, { type: 'timeout' });
    expect(types(r1.events)).toEqual(['autoActed', 'cardsThrown', 'turnStarted']);
    expect(r1.events[1]).toMatchObject({ count: 1 });
    state = r1.state;

    const r2 = step(state, { type: 'timeout' });
    expect(types(r2.events)[0]).toBe('autoActed');
    expect(types(r2.events)).toContain('checkResult');
  });

  it('is rejected after game over', () => {
    const { state } = playRandomGame(2, 37, 'over-seed');
    expectError(state, { type: 'timeout' }, 'BAD_PHASE');
    expectError(state, { type: 'check', seat: 0, flipIndex: 0 }, 'BAD_PHASE');
  });
});

describe('game over', () => {
  it("random games terminate with the joker in the loser's hand and everyone else out", () => {
    for (const seed of ['g1', 'g2', 'g3']) {
      const { state } = playRandomGame(3, 37, seed);
      const phase = state.phase;
      expect(phase.kind).toBe('over');
      if (phase.kind !== 'over') continue;
      const loser = state.players[phase.loserSeat]!;
      expect(loser.hand.some((c) => c.rank === 'JOKER')).toBe(true);
      for (const p of state.players) {
        if (p.seat !== phase.loserSeat) expect(p.out).toBe(true);
      }
      expect(state.outOrder).toHaveLength(state.players.length - 1);
    }
  });
});
