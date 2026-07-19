/**
 * Coin-economy pure functions — the canonical numbers live HERE (and in
 * config.ts for env-tunable caps). See docs/protocol.md for the wire contracts.
 */

/**
 * Placement coin table for public games with 3..8 players.
 * Winner = 25 + 5×(N−3); interior places decay ~geometrically; last place 5.
 */
export const PLACEMENT_COINS: Record<number, readonly number[]> = {
  3: [25, 12, 5],
  4: [30, 17, 9, 5],
  5: [35, 21, 13, 8, 5],
  6: [40, 26, 17, 11, 7, 5],
  7: [45, 31, 21, 15, 10, 7, 5],
  8: [50, 36, 26, 18, 13, 9, 6, 5],
};

/** Base coins for a placement (1-based) in an N-player game; 0 outside the table. */
export function placementCoins(playerCount: number, placement: number): number {
  const row = PLACEMENT_COINS[playerCount];
  if (!row) return 0;
  return row[placement - 1] ?? 0;
}

export interface Eligibility {
  /** Any awards at all (coins). False when the game was too short. */
  awardsEligible: boolean;
  /** Rating + season points + quest progress. */
  rated: boolean;
  /** 1 for public, 0.5 for private rooms. */
  coinMultiplier: number;
}

export function gameEligibility(input: {
  isPrivate: boolean;
  playerCount: number;
  actionCount: number;
  minActions: number;
  minRatedPlayers: number;
  privateRoomCoinMultiplier: number;
}): Eligibility {
  const longEnough = input.actionCount >= input.minActions;
  return {
    awardsEligible: longEnough,
    rated: longEnough && !input.isPrivate && input.playerCount >= input.minRatedPlayers,
    coinMultiplier: input.isPrivate ? input.privateRoomCoinMultiplier : 1,
  };
}

/** Daily bonus curve: streak day 1..7+ → 10/15/20/30/40/50/60 (capped). */
const DAILY_BONUS = [10, 15, 20, 30, 40, 50, 60] as const;

export function dailyBonusCoins(streakDay: number): number {
  const idx = Math.max(1, Math.min(streakDay, DAILY_BONUS.length)) - 1;
  return DAILY_BONUS[idx]!;
}

/** UTC calendar day, e.g. "2026-07-19". */
export function utcDayOf(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/** The UTC day before the given day string. */
export function previousUtcDay(day: string): string {
  const d = new Date(`${day}T00:00:00.000Z`);
  d.setUTCDate(d.getUTCDate() - 1);
  return utcDayOf(d);
}

/** ISO-8601 week key in UTC, e.g. "2026-W29". Weeks start Monday; week 1 holds Jan 4. */
export function seasonKeyFor(date: Date): string {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  // Shift to the Thursday of this ISO week — its year is the ISO year.
  const dayOfWeek = d.getUTCDay() || 7; // Mon=1..Sun=7
  d.setUTCDate(d.getUTCDate() + 4 - dayOfWeek);
  const isoYear = d.getUTCFullYear();
  const yearStart = Date.UTC(isoYear, 0, 1);
  const week = Math.ceil(((d.getTime() - yearStart) / 86_400_000 + 1) / 7);
  return `${isoYear}-W${String(week).padStart(2, '0')}`;
}
