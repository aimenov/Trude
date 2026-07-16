import {
  createGame, reduce, assertInvariants, nameableRanks, randInt, seedRng,
} from '../src/index.js';
import type {
  Card, DeckSize, EngineAction, EngineEvent, GameConfig, GameState, Rank, RngState,
} from '../src/index.js';

/** Parses "7C", "10H", "AS", "JOKER" into a Card face (id assigned by buildRiggedDeck). */
export function face(spec: string): { rank: Rank | 'JOKER'; suit?: 'C' | 'D' | 'H' | 'S' } {
  if (spec === 'JOKER') return { rank: 'JOKER' };
  const suit = spec.slice(-1) as 'C' | 'D' | 'H' | 'S';
  const rank = spec.slice(0, -1) as Rank;
  return { rank, suit };
}

/**
 * Builds a complete rigged deck from per-seat hand specs, laid out so that
 * round-robin dealing from `firstLeaderSeat` reproduces exactly those hands.
 * Seat s receives deck indices i with (firstLeaderSeat + i) % n === s, in order.
 */
export function buildRiggedDeck(handsBySeat: string[][], firstLeaderSeat: number, deckSize: DeckSize): Card[] {
  const n = handsBySeat.length;
  const total = handsBySeat.reduce((a, h) => a + h.length, 0);
  if (total !== deckSize) throw new Error(`Rigged hands hold ${total} cards, deck needs ${deckSize}`);
  const cursors = handsBySeat.map(() => 0);
  const deck: Card[] = [];
  for (let i = 0; i < total; i++) {
    const seat = (firstLeaderSeat + i) % n;
    const spec = handsBySeat[seat]![cursors[seat]!++];
    if (spec === undefined) throw new Error(`Seat ${seat} ran out of cards at deal position ${i} — sizes don't fit round-robin`);
    const f = face(spec);
    deck.push(f.suit ? { id: `c${i}`, rank: f.rank, suit: f.suit } : { id: `c${i}`, rank: f.rank });
  }
  cursors.forEach((c, seat) => {
    if (c !== handsBySeat[seat]!.length) throw new Error(`Seat ${seat} has leftover rigged cards`);
  });
  return deck;
}

export function newGame(
  playerCount: number,
  deckSize: DeckSize = 37,
  seed = 'test-seed',
  overrides?: { deck?: Card[]; firstLeaderSeat?: number },
): { state: GameState; events: EngineEvent[] } {
  const config: GameConfig = { deckSize, seed };
  const ids = Array.from({ length: playerCount }, (_, i) => `p${i}`);
  return createGame(config, ids, overrides);
}

/** Applies an action that must succeed; asserts invariants on the result. */
export function step(state: GameState, action: EngineAction): { state: GameState; events: EngineEvent[] } {
  const r = reduce(state, action);
  if (!r.ok) throw new Error(`Expected legal action ${JSON.stringify(action)}, got ${r.error.code}: ${r.error.message}`);
  assertInvariants(r.state);
  return { state: r.state, events: r.events };
}

/** A uniformly random legal action for the current actor (drives properties + fuzzer). */
export function randomLegalAction(state: GameState, rng: RngState): EngineAction {
  const phase = state.phase;
  if (phase.kind === 'over') throw new Error('game over');
  if (randInt(rng, 20) === 0) return { type: 'timeout' }; // occasional timer expiry
  const hand = state.players[phase.seat]!.hand;

  const pickCards = (): string[] => {
    const count = 1 + randInt(rng, Math.min(3, hand.length));
    const pool = [...hand];
    const picked: string[] = [];
    for (let i = 0; i < count; i++) picked.push(pool.splice(randInt(rng, pool.length), 1)[0]!.id);
    return picked;
  };

  if (phase.kind === 'lead') {
    const ranks = nameableRanks(state);
    return { type: 'throw', seat: phase.seat, cardIds: pickCards(), rank: ranks[randInt(rng, ranks.length)]! };
  }
  const last = state.pile[state.pile.length - 1]!;
  if (phase.mustCheck || randInt(rng, 3) === 0) {
    return { type: 'check', seat: phase.seat, flipIndex: randInt(rng, last.cards.length) };
  }
  return { type: 'throw', seat: phase.seat, cardIds: pickCards() };
}

/** Plays random legal moves until game over (or the cap). Returns final state + action count. */
export function playRandomGame(
  playerCount: number,
  deckSize: DeckSize,
  seed: string,
  cap = 10_000,
): { state: GameState; steps: number } {
  let { state } = newGame(playerCount, deckSize, seed);
  const rng = seedRng(`driver:${seed}`);
  let steps = 0;
  while (state.phase.kind !== 'over') {
    if (steps++ > cap) throw new Error(`Game did not terminate within ${cap} actions (seed ${seed})`);
    const action = randomLegalAction(state, rng);
    const r = reduce(state, action);
    if (!r.ok) throw new Error(`Legal-move generator produced illegal move: ${r.error.code} (seed ${seed})`);
    assertInvariants(r.state);
    state = r.state;
  }
  return { state, steps };
}
