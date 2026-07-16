import { nameableRanks } from './legal.js';
import type { Card, GameState } from './types.js';

function fail(name: string, detail: string): never {
  throw new Error(`Invariant ${name} violated: ${detail}`);
}

/**
 * Asserts the engine's structural invariants. Called after every step in tests
 * and the fuzzer; cheap enough for dev builds.
 */
export function assertInvariants(state: GameState): void {
  const deckCount = state.config.deckSize;
  const all: Card[] = [
    ...state.players.flatMap((p) => p.hand),
    ...state.pile.flatMap((g) => g.cards),
    ...state.discarded,
  ];

  // I1 — card conservation: every card exists exactly once.
  if (all.length !== deckCount) fail('I1', `expected ${deckCount} cards, found ${all.length}`);
  const ids = new Set(all.map((c) => c.id));
  if (ids.size !== deckCount) fail('I1', 'duplicate card ids');

  // I2 — joker uniqueness & immortality.
  const jokers = all.filter((c) => c.rank === 'JOKER');
  if (jokers.length !== 1) fail('I2', `expected exactly 1 joker, found ${jokers.length}`);
  if (state.discarded.some((c) => c.rank === 'JOKER')) fail('I2', 'joker in discard');
  if ((state.retiredRanks as string[]).includes('JOKER')) fail('I2', 'joker rank retired');

  // I3 — retirement integrity.
  if (state.discarded.length !== 4 * state.retiredRanks.length) {
    fail('I3', `discard has ${state.discarded.length} cards for ${state.retiredRanks.length} retired ranks`);
  }
  for (const c of state.discarded) {
    if (!state.retiredRanks.includes(c.rank as never)) fail('I3', `discarded ${c.rank} not retired`);
  }
  for (const p of state.players) {
    if (p.hand.some((c) => state.retiredRanks.includes(c.rank as never))) {
      fail('I3', `seat ${p.seat} holds a retired rank`);
    }
  }
  if (state.pile.some((g) => g.cards.some((c) => state.retiredRanks.includes(c.rank as never)))) {
    fail('I3', 'pile contains a retired rank');
  }

  // I4 — actor validity & out-status coherence.
  for (const p of state.players) {
    if (p.out && p.hand.length > 0) fail('I4', `seat ${p.seat} is out but holds cards`);
  }
  if (state.pile.length === 0 && state.phase.kind !== 'over') {
    for (const p of state.players) {
      if (!p.out && p.hand.length === 0) fail('I4', `seat ${p.seat} has no cards but is not out (pile empty)`);
    }
  }
  const emptyPending = state.players.filter((p) => !p.out && p.hand.length === 0);
  if (emptyPending.length > 1) fail('I4', 'more than one pending-out player');
  if (state.phase.kind !== 'over') {
    const actor = state.players[state.phase.seat]!;
    if (actor.out) fail('I4', `actor seat ${actor.seat} is out`);
    if (actor.hand.length === 0) fail('I4', `actor seat ${actor.seat} has an empty hand`);
  }

  // I5 — pile coherence.
  if ((state.pileRank === null) !== (state.pile.length === 0)) fail('I5', 'pileRank/pile mismatch');
  for (const g of state.pile) {
    if (g.claimedRank !== state.pileRank) fail('I5', 'group claim differs from pile rank');
    if (g.cards.length < 1 || g.cards.length > 3) fail('I5', `group size ${g.cards.length}`);
  }

  // I6 — pile rank liveness.
  if (state.pileRank !== null && state.retiredRanks.includes(state.pileRank)) {
    fail('I6', `pile rank ${state.pileRank} is retired`);
  }

  // I7 — a leader always has a legal claim.
  if (state.phase.kind === 'lead' && nameableRanks(state).length === 0) fail('I7', 'no nameable ranks');

  // Out-order bookkeeping matches out flags.
  const outSeats = state.players.filter((p) => p.out).map((p) => p.seat).sort((a, b) => a - b);
  const ordered = [...state.outOrder].sort((a, b) => a - b);
  if (outSeats.length !== ordered.length || outSeats.some((s, i) => s !== ordered[i])) {
    fail('I9', 'outOrder does not match out flags');
  }
}
