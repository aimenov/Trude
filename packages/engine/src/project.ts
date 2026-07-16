import type { Card, DeckSize, GameState, Rank } from './types.js';

export interface PlayerView {
  playerId: string;
  seat: number;
  cardCount: number;
  out: boolean;
}

export interface GameView {
  actionCount: number;
  deckSize: DeckSize;
  players: PlayerView[];
  pile: { rank: Rank | null; totalCount: number; groups: { seat: number; count: number }[] };
  lastThrowSeat: number | null;
  mustCheck: boolean;
  retiredRanks: Rank[];
  discarded: Card[];
  turn: { seat: number; phase: 'lead' | 'respond' } | null;
  loserSeat: number | null;
  hand: Card[]; // viewer's own cards; empty for spectators
}

/**
 * Per-player redacted snapshot. This is the ONLY way state leaves the engine for
 * the wire: opponents' hands and face-down pile cards are counts, never faces.
 * Pass seat = null for a spectator view.
 */
export function projectFor(state: GameState, seat: number | null): GameView {
  const last = state.pile[state.pile.length - 1];
  const phase = state.phase;
  return {
    actionCount: state.actionCount,
    deckSize: state.config.deckSize,
    players: state.players.map((p) => ({
      playerId: p.playerId, seat: p.seat, cardCount: p.hand.length, out: p.out,
    })),
    pile: {
      rank: state.pileRank,
      totalCount: state.pile.reduce((n, g) => n + g.cards.length, 0),
      groups: state.pile.map((g) => ({ seat: g.seat, count: g.cards.length })),
    },
    lastThrowSeat: last ? last.seat : null,
    mustCheck: phase.kind === 'respond' && phase.mustCheck,
    retiredRanks: [...state.retiredRanks],
    discarded: [...state.discarded],
    turn: phase.kind === 'over' ? null : { seat: phase.seat, phase: phase.kind },
    loserSeat: phase.kind === 'over' ? phase.loserSeat : null,
    hand: seat === null ? [] : [...state.players[seat]!.hand],
  };
}
