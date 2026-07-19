import type { PlayerGameStats } from '@trude/engine';

/**
 * Daily quests: 3 per UTC day, picked deterministically from this fixed
 * catalog of 9. Progress accrues from per-game stats of rated-eligible games.
 */

export type QuestTier = 'easy' | 'medium' | 'hard';

export const QUEST_REWARD_BY_TIER: Record<QuestTier, number> = { easy: 15, medium: 20, hard: 30 };

/** Coins for finishing all 3 quests of the day. */
export const QUEST_ALL_DONE_BONUS = 15;

export interface QuestOutcome { won: boolean; played: boolean; }

export interface QuestDef {
  key: string;
  tier: QuestTier;
  target: number;
  /** How much one finished game advances this quest. */
  progress: (g: PlayerGameStats, outcome: QuestOutcome) => number;
}

export function questReward(def: QuestDef): number {
  return QUEST_REWARD_BY_TIER[def.tier];
}

export const QUESTS: QuestDef[] = [
  { key: 'q_play_3', tier: 'easy', target: 3, progress: (_g, o) => (o.played ? 1 : 0) },
  { key: 'q_truthful_10', tier: 'easy', target: 10, progress: (g) => g.truthfulThrows },
  { key: 'q_pickup_10', tier: 'easy', target: 10, progress: (g) => g.cardsPickedUp },
  { key: 'q_win_1', tier: 'medium', target: 1, progress: (_g, o) => (o.won ? 1 : 0) },
  { key: 'q_checks_won_3', tier: 'medium', target: 3, progress: (g) => g.checksWon },
  { key: 'q_quad_1', tier: 'medium', target: 1, progress: (g) => g.quadsDiscarded },
  { key: 'q_lies_survived_5', tier: 'hard', target: 5, progress: (g) => g.liesSurvived },
  { key: 'q_joker_pass_1', tier: 'hard', target: 1, progress: (g) => g.jokerPassed },
  { key: 'q_smuggle_1', tier: 'hard', target: 1, progress: (g) => g.jokerSmuggles },
];

/** FNV-1a 32-bit over a string. */
export function fnv1a(input: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

/**
 * Deterministic 3-pick for a UTC day string ("2026-07-19"): FNV-1a seeds a
 * tiny LCG that drives a partial Fisher–Yates over the catalog. Same day ⇒
 * same 3 distinct quests on every server instance.
 */
export function questsForDay(day: string): QuestDef[] {
  let state = fnv1a(day) || 1;
  const next = (): number => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return state;
  };
  const pool = [...QUESTS];
  const picked: QuestDef[] = [];
  for (let i = 0; i < 3; i++) {
    const idx = next() % pool.length;
    picked.push(pool.splice(idx, 1)[0]!);
  }
  return picked;
}
