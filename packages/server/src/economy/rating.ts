/**
 * Pairwise ELO for N-player games:
 *   delta_i = round( K_i/(N−1) × Σ_{j≠i} (S_ij − 1/(1+10^((Rj−Ri)/400))) )
 * where S_ij = 1 if i placed above j, else 0 (placements are unique — no ties).
 * Initial rating 1000, floor 100.
 */

export const INITIAL_RATING = 1000;
export const RATING_FLOOR = 100;

export interface RatingSnapshot {
  rating: number;
  peakRating: number;
  gamesRated: number;
}

export function freshRating(): RatingSnapshot {
  return { rating: INITIAL_RATING, peakRating: INITIAL_RATING, gamesRated: 0 };
}

/**
 * K-factor: 40 for the first 30 rated games, then 24 — but 16 once the player
 * has EVER reached 2200 (sticky via peakRating, so dipping below keeps K=16).
 */
export function kFor(snapshot: RatingSnapshot): number {
  if (snapshot.peakRating >= 2200) return 16;
  return snapshot.gamesRated < 30 ? 40 : 24;
}

export interface RatedParticipant {
  userId: string;
  placement: number; // 1 = best
  snapshot: RatingSnapshot;
}

/** Per-user rating delta for one rated game. Deterministic; near-zero-sum when Ks match. */
export function computeRatingDeltas(participants: RatedParticipant[]): Map<string, number> {
  const deltas = new Map<string, number>();
  const n = participants.length;
  for (const me of participants) {
    let sum = 0;
    for (const other of participants) {
      if (other.userId === me.userId) continue;
      const s = me.placement < other.placement ? 1 : 0;
      const expected = 1 / (1 + 10 ** ((other.snapshot.rating - me.snapshot.rating) / 400));
      sum += s - expected;
    }
    deltas.set(me.userId, Math.round((kFor(me.snapshot) / (n - 1)) * sum));
  }
  return deltas;
}

/** Applies a delta to a snapshot: floor 100, peak tracks the max, gamesRated++. */
export function applyDelta(snapshot: RatingSnapshot, delta: number): RatingSnapshot {
  const rating = Math.max(RATING_FLOOR, snapshot.rating + delta);
  return {
    rating,
    peakRating: Math.max(snapshot.peakRating, rating),
    gamesRated: snapshot.gamesRated + 1,
  };
}
