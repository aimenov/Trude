export type Suit = 'C' | 'D' | 'H' | 'S';

export type Rank =
  | '2' | '3' | '4' | '5'
  | '6' | '7' | '8' | '9' | '10'
  | 'J' | 'Q' | 'K' | 'A';

export const RANK_ORDER: readonly Rank[] = ['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A'];
export const SUITS: readonly Suit[] = ['C', 'D', 'H', 'S'];

export type DeckSize = 37 | 53;

export interface Card {
  readonly id: string;              // opaque, assigned AFTER the shuffle — never a rank lookup
  readonly rank: Rank | 'JOKER';
  readonly suit?: Suit;
}

export interface GameConfig {
  readonly deckSize: DeckSize;
  readonly seed: string;
}

/** sfc32 state — plain numbers so the whole GameState survives JSON round-trips. */
export type RngState = [number, number, number, number];

export interface PlayerGameStats {
  liesSurvived: number;
  liesCaught: number;
  checksWon: number;
  checksLost: number;
  cardsPickedUp: number;
  quadsDiscarded: number;
  jokerPassed: number;
  jokerSmuggles: number;
  truthfulThrows: number;
  lyingThrows: number;
  maxHandSize: number;
  wasEverCaught: boolean;
  firstOut: boolean;
}

export interface EnginePlayer {
  readonly playerId: string;
  readonly seat: number;            // === index in GameState.players (no in-game swaps in v1)
  hand: Card[];
  out: boolean;
  stats: PlayerGameStats;
}

export interface PileGroup {
  readonly seat: number;
  cards: Card[];
  readonly claimedRank: Rank;
  readonly lied: boolean;           // any thrown card's rank !== claimedRank (server-private)
}

export type Phase =
  | { kind: 'lead'; seat: number }
  | { kind: 'respond'; seat: number; mustCheck: boolean }
  | { kind: 'over'; loserSeat: number };

export interface GameState {
  config: GameConfig;
  rng: RngState;
  players: EnginePlayer[];
  pile: PileGroup[];
  pileRank: Rank | null;
  retiredRanks: Rank[];
  discarded: Card[];
  phase: Phase;
  actionCount: number;
  outOrder: number[];               // seats in the order they went out (safe)
}

// ---------- Actions (room resolves playerId -> seat before calling reduce) ----------

export type EngineAction =
  | { type: 'throw'; seat: number; cardIds: string[]; rank?: Rank }
  | { type: 'check'; seat: number; flipIndex: number }
  | { type: 'timeout' };            // host-injected: auto-acts for the current actor

// ---------- Events (ordered, animation-ready; room forwards to clients) ----------

export interface Placement { playerId: string; seat: number; placement: number; }

export type EngineEvent =
  | { type: 'dealt'; handCounts: number[]; firstLeaderSeat: number }
  | { type: 'cardsThrown'; seat: number; count: number; rank: Rank; isLead: boolean }
  | {
      type: 'checkResult'; checkerSeat: number; targetSeat: number; flipIndex: number;
      flipped: Card; matched: boolean; pickerSeat: number; pickedCount: number; nextLeadSeat: number;
    }
  | { type: 'fourDiscarded'; seat: number; rank: Rank; cards: Card[] }
  | { type: 'playerOut'; seat: number }
  | { type: 'autoActed'; seat: number; kind: 'lead' | 'check' }
  | { type: 'turnStarted'; seat: number; phase: 'lead' | 'respond'; mustCheck: boolean }
  | { type: 'gameOver'; loserSeat: number; jokerCard: Card; placements: Placement[]; stats: Record<string, PlayerGameStats> };

// ---------- Errors ----------

export type RuleErrorCode =
  | 'BAD_PHASE'
  | 'NOT_YOUR_TURN'
  | 'BAD_CARDS'
  | 'RANK_REQUIRED'
  | 'RANK_MISMATCH'
  | 'RANK_DEAD'
  | 'RANK_JOKER'
  | 'MUST_CHECK'
  | 'BAD_FLIP_INDEX'
  | 'NOTHING_TO_CHECK';

export interface RuleError { code: RuleErrorCode; message: string; }

export type ReduceResult =
  | { ok: true; state: GameState; events: EngineEvent[] }
  | { ok: false; error: RuleError };

// ---------- Player caps ----------

export const PLAYER_CAPS: Record<DeckSize, { min: number; max: number }> = {
  37: { min: 2, max: 6 },
  53: { min: 2, max: 8 },
};
