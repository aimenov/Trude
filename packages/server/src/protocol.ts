import { z } from 'zod';
import type { Card, EngineEvent, Rank } from '@trude/engine';

// ---------------------------------------------------------------------------
// Client -> Server (zod-validated). See docs/protocol.md — that file is the contract.
// ---------------------------------------------------------------------------

const rank = z.enum(['2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A']);

const actionEnvelope = {
  actionCount: z.number().int().min(-1), // -1 while no game is running (lobby)
  clientSeq: z.number().int().nonnegative(),
};

export const clientMessages = {
  configureRoom: z.object({
    ...actionEnvelope,
    deckSize: z.union([z.literal(37), z.literal(53)]).optional(),
    turnTimerSec: z.union([z.literal(15), z.literal(30), z.literal(60)]).optional(),
    maxPlayers: z.number().int().min(2).max(8).optional(),
  }),
  startGame: z.object({ ...actionEnvelope }),
  kickPlayer: z.object({ ...actionEnvelope, userId: z.string().min(1) }),
  throwCards: z.object({
    ...actionEnvelope,
    cardIds: z.array(z.string().min(1)).min(1).max(3),
    rank: rank.optional(),
  }),
  check: z.object({ ...actionEnvelope, flipIndex: z.number().int().min(0).max(2) }),
  requestSeatSwap: z.object({ ...actionEnvelope, targetUserId: z.string().min(1) }),
  respondSeatSwap: z.object({ ...actionEnvelope, accept: z.boolean() }),
  reaction: z.object({ ...actionEnvelope, emoji: z.string().min(1).max(16) }),
  ping: z.object({ t: z.number() }),
} as const;

export type ClientMessageName = keyof typeof clientMessages;

export const REACTION_ALLOWLIST = [
  'joy', 'sob', 'angry', 'monocle', 'clown', 'fire', 'thumbsup', 'scream',
] as const;

export const ROOM_CODE_ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';

// ---------------------------------------------------------------------------
// Server -> Client
// ---------------------------------------------------------------------------

export interface WirePlayer {
  userId: string;
  nickname: string;
  avatar: string;
  seat: number;
  cardCount: number;
  connected: boolean;
  autoPilot: boolean;
  isOut: boolean;
  isAdmin: boolean;
}

export interface EventBatch {
  actionCount: number;
  events: WireEvent[];
}

/** Engine events pass through; turn/gameStarted gain room-level fields. */
export type WireEvent =
  | { type: 'gameStarted'; deckSize: number; seatOrder: { seat: number; userId: string }[]; handCounts: number[] }
  | { type: 'turnStarted'; seat: number; phase: 'lead' | 'respond'; mustCheck: boolean; deadlineTs: number; durationMs: number }
  | Extract<EngineEvent, { type: 'cardsThrown' | 'checkResult' | 'fourDiscarded' | 'playerOut' | 'autoActed' }>
  | { type: 'autoPilot'; seat: number; on: boolean }
  | { type: 'playerConnection'; seat: number; connected: boolean }
  | { type: 'seatSwapResolved'; seatA: number; seatB: number; accepted: boolean }
  | { type: 'playerJoined'; userId: string; nickname: string; avatar: string; seat: number }
  | { type: 'playerLeft'; userId: string; seat: number }
  | { type: 'roomConfigured'; deckSize: number; turnTimerSec: number; maxPlayers: number }
  | {
      type: 'gameOver'; loserSeat: number; loserUserId: string; jokerCard: Card;
      placements: { userId: string; seat: number; placement: number }[];
      stats: Record<string, unknown>;
    }
  | { type: 'reaction'; seat: number; emoji: string };

export interface StateFull {
  actionCount: number;
  phase: 'lobby' | 'playing' | 'finished';
  config: { deckSize: number; turnTimerSec: number; maxPlayers: number };
  roomCode: string | null;
  players: WirePlayer[];
  pile: { rank: Rank | null; totalCount: number; groups: { seat: number; count: number }[] };
  lastThrowSeat: number | null;
  mustCheck: boolean;
  retiredRanks: Rank[];
  discarded: Card[];
  turn: { seat: number; phase: 'lead' | 'respond'; deadlineTs: number; durationMs: number } | null;
  hand: Card[];
  lastResolution: EventBatch | null;
  loserSeat: number | null;
}

export type ServerErrorCode =
  | 'NOT_ADMIN' | 'BAD_CONFIG' | 'NOT_ENOUGH_PLAYERS' | 'TOO_MANY_PLAYERS' | 'BAD_TARGET'
  | 'NOT_IN_ROOM' | 'STALE_ACTION' | 'BAD_EMOJI' | 'RATE_LIMITED' | 'NO_PENDING_SWAP'
  | 'SWAP_PENDING' | 'BAD_MESSAGE' | 'GAME_IN_PROGRESS'
  // engine RuleErrorCodes pass through as-is:
  | 'BAD_PHASE' | 'NOT_YOUR_TURN' | 'BAD_CARDS' | 'RANK_REQUIRED' | 'RANK_MISMATCH'
  | 'RANK_DEAD' | 'RANK_JOKER' | 'MUST_CHECK' | 'BAD_FLIP_INDEX' | 'NOTHING_TO_CHECK';
