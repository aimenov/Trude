import { describe, expect, it } from 'vitest';
import {
  applyDelta, computeRatingDeltas, freshRating, kFor, RATING_FLOOR,
} from '../src/economy/rating.js';
import type { RatedParticipant, RatingSnapshot } from '../src/economy/rating.js';

function snap(partial: Partial<RatingSnapshot> = {}): RatingSnapshot {
  return { rating: 1000, peakRating: 1000, gamesRated: 0, ...partial };
}

function game(ratings: number[], gamesRated = 50): RatedParticipant[] {
  return ratings.map((rating, i) => ({
    userId: `u${i}`,
    placement: i + 1,
    snapshot: snap({ rating, peakRating: rating, gamesRated }),
  }));
}

describe('kFor', () => {
  it('is 40 for the first 30 rated games', () => {
    expect(kFor(snap({ gamesRated: 0 }))).toBe(40);
    expect(kFor(snap({ gamesRated: 29 }))).toBe(40);
  });
  it('drops to 24 from game 30', () => {
    expect(kFor(snap({ gamesRated: 30 }))).toBe(24);
    expect(kFor(snap({ gamesRated: 500 }))).toBe(24);
  });
  it('is 16 once peak reached 2200 — sticky even if rating fell back', () => {
    expect(kFor(snap({ rating: 2210, peakRating: 2210, gamesRated: 100 }))).toBe(16);
    expect(kFor(snap({ rating: 1900, peakRating: 2250, gamesRated: 100 }))).toBe(16);
    // even inside the first 30 games, 2200+ pins K to 16
    expect(kFor(snap({ rating: 2200, peakRating: 2200, gamesRated: 5 }))).toBe(16);
  });
});

describe('computeRatingDeltas', () => {
  it('is deterministic', () => {
    const a = computeRatingDeltas(game([1100, 1000, 900]));
    const b = computeRatingDeltas(game([1100, 1000, 900]));
    expect([...a.entries()]).toEqual([...b.entries()]);
  });

  it('winner gains, loser loses at equal ratings', () => {
    for (let n = 2; n <= 8; n++) {
      const deltas = computeRatingDeltas(game(Array.from({ length: n }, () => 1000)));
      const values = [...deltas.values()];
      expect(values[0]!).toBeGreaterThan(0);
      expect(values[n - 1]!).toBeLessThan(0);
      // strictly ordered by placement at equal ratings
      for (let i = 1; i < n; i++) expect(values[i]!).toBeLessThanOrEqual(values[i - 1]!);
    }
  });

  it('is near-zero-sum when all Ks match (rounding drift only)', () => {
    for (let n = 2; n <= 8; n++) {
      const ratings = Array.from({ length: n }, (_, i) => 900 + i * 37);
      const deltas = computeRatingDeltas(game(ratings));
      const sum = [...deltas.values()].reduce((a, b) => a + b, 0);
      expect(Math.abs(sum)).toBeLessThanOrEqual(n); // ±0.5 rounding per player
    }
  });

  it('upsets pay more than expected wins', () => {
    const underdogWins = computeRatingDeltas([
      { userId: 'low', placement: 1, snapshot: snap({ rating: 900, peakRating: 900, gamesRated: 50 }) },
      { userId: 'high', placement: 2, snapshot: snap({ rating: 1400, peakRating: 1400, gamesRated: 50 }) },
    ]);
    const favouriteWins = computeRatingDeltas([
      { userId: 'high', placement: 1, snapshot: snap({ rating: 1400, peakRating: 1400, gamesRated: 50 }) },
      { userId: 'low', placement: 2, snapshot: snap({ rating: 900, peakRating: 900, gamesRated: 50 }) },
    ]);
    expect(underdogWins.get('low')!).toBeGreaterThan(favouriteWins.get('high')!);
  });

  it('uses each player own K', () => {
    const deltas = computeRatingDeltas([
      { userId: 'new', placement: 1, snapshot: snap({ gamesRated: 0 }) }, // K=40
      { userId: 'vet', placement: 2, snapshot: snap({ gamesRated: 100 }) }, // K=24
    ]);
    expect(deltas.get('new')!).toBe(20); // 40 × 0.5
    expect(deltas.get('vet')!).toBe(-12); // 24 × -0.5
  });
});

describe('applyDelta', () => {
  it('never drops below the floor', () => {
    const s = applyDelta(snap({ rating: 110, peakRating: 1200 }), -50);
    expect(s.rating).toBe(RATING_FLOOR);
  });
  it('tracks peak and gamesRated', () => {
    const s = applyDelta(snap({ rating: 1190, peakRating: 1195, gamesRated: 7 }), 20);
    expect(s).toEqual({ rating: 1210, peakRating: 1210, gamesRated: 8 });
    const down = applyDelta(s, -100);
    expect(down.peakRating).toBe(1210);
    expect(down.gamesRated).toBe(9);
  });
  it('fresh rating starts at 1000', () => {
    expect(freshRating()).toEqual({ rating: 1000, peakRating: 1000, gamesRated: 0 });
  });
});
