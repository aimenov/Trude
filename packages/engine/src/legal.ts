import { ranksForDeck } from './deck.js';
import type { EngineAction, GameState, Rank, RuleError, RuleErrorCode } from './types.js';

export function err(code: RuleErrorCode, message: string): { ok: false; error: RuleError } {
  return { ok: false, error: { code, message } };
}

/** Ranks a leader may currently claim: deck ranks minus retired (joker is not a Rank). */
export function nameableRanks(state: GameState): Rank[] {
  return ranksForDeck(state.config.deckSize).filter((r) => !state.retiredRanks.includes(r));
}

/** Seat of the next player after `seat` who still holds cards. Returns -1 if none. */
export function nextSeatWithCards(state: GameState, seat: number): number {
  const n = state.players.length;
  for (let i = 1; i <= n; i++) {
    const s = (seat + i) % n;
    if (state.players[s]!.hand.length > 0) return s;
  }
  return -1;
}

/**
 * Validates an action against the current state. Returns null when legal,
 * otherwise the RuleError. The reducer and well-behaved clients share these
 * predicates (mirrored in Dart, kept honest by golden fixtures).
 */
export function validate(state: GameState, action: EngineAction): RuleError | null {
  const phase = state.phase;
  if (phase.kind === 'over') return { code: 'BAD_PHASE', message: 'Game is over' };
  if (action.type === 'timeout') return null;

  if (action.type === 'throw') {
    if (phase.seat !== action.seat) return { code: 'NOT_YOUR_TURN', message: 'Not your turn' };
    if (phase.kind === 'respond' && phase.mustCheck) {
      return { code: 'MUST_CHECK', message: 'Previous player has no cards left — you must check' };
    }
    const hand = state.players[action.seat]!.hand;
    const ids = action.cardIds;
    if (ids.length < 1 || ids.length > 3 || new Set(ids).size !== ids.length) {
      return { code: 'BAD_CARDS', message: 'Throw 1 to 3 distinct cards' };
    }
    for (const id of ids) {
      if (!hand.some((c) => c.id === id)) return { code: 'BAD_CARDS', message: 'Card not in hand' };
    }
    if (phase.kind === 'lead') {
      if (action.rank === undefined) return { code: 'RANK_REQUIRED', message: 'Name a rank to lead' };
      if ((action.rank as string) === 'JOKER') return { code: 'RANK_JOKER', message: 'Joker cannot be named' };
      if (!nameableRanks(state).includes(action.rank)) {
        return { code: 'RANK_DEAD', message: `Rank ${action.rank} is out of the game` };
      }
    } else if (action.rank !== undefined && action.rank !== state.pileRank) {
      return { code: 'RANK_MISMATCH', message: `The pile rank is ${state.pileRank}` };
    }
    return null;
  }

  // check
  if (phase.kind !== 'respond') return { code: 'NOTHING_TO_CHECK', message: 'No throw to check' };
  if (phase.seat !== action.seat) return { code: 'NOT_YOUR_TURN', message: 'Not your turn' };
  const last = state.pile[state.pile.length - 1];
  if (!last) return { code: 'NOTHING_TO_CHECK', message: 'The pile is empty' };
  if (action.flipIndex < 0 || action.flipIndex >= last.cards.length || !Number.isInteger(action.flipIndex)) {
    return { code: 'BAD_FLIP_INDEX', message: `Flip index must be 0..${last.cards.length - 1}` };
  }
  return null;
}
