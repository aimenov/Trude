import { describe, expect, it } from 'vitest';
import {
  dailyBonusCoins, gameEligibility, placementCoins, PLACEMENT_COINS, previousUtcDay,
  seasonKeyFor, utcDayOf,
} from '../src/economy/economy.js';

const ELIG = {
  minActions: 20, minRatedPlayers: 3, privateRoomCoinMultiplier: 0.5,
};

describe('placementCoins', () => {
  it('encodes the canonical table 3p..8p', () => {
    expect(PLACEMENT_COINS[3]).toEqual([25, 12, 5]);
    expect(PLACEMENT_COINS[8]).toEqual([50, 36, 26, 18, 13, 9, 6, 5]);
  });

  it('winner = 25 + 5×(N−3); last place 5; strictly decreasing', () => {
    for (let n = 3; n <= 8; n++) {
      const row = PLACEMENT_COINS[n]!;
      expect(row).toHaveLength(n);
      expect(row[0]).toBe(25 + 5 * (n - 3));
      expect(row[n - 1]).toBe(5);
      for (let i = 1; i < n; i++) expect(row[i]!).toBeLessThan(row[i - 1]!);
    }
  });

  it('returns 0 outside the table', () => {
    expect(placementCoins(2, 1)).toBe(0);
    expect(placementCoins(9, 1)).toBe(0);
    expect(placementCoins(3, 4)).toBe(0);
    expect(placementCoins(3, 0)).toBe(0);
  });

  it('looks up by 1-based placement', () => {
    expect(placementCoins(3, 1)).toBe(25);
    expect(placementCoins(3, 2)).toBe(12);
    expect(placementCoins(3, 3)).toBe(5);
    expect(placementCoins(6, 1)).toBe(40);
  });
});

describe('gameEligibility', () => {
  it('short games award nothing', () => {
    const e = gameEligibility({ isPrivate: false, playerCount: 4, actionCount: 19, ...ELIG });
    expect(e).toEqual({ awardsEligible: false, rated: false, coinMultiplier: 1 });
  });
  it('public ≥3 players and ≥20 actions is rated', () => {
    const e = gameEligibility({ isPrivate: false, playerCount: 3, actionCount: 20, ...ELIG });
    expect(e).toEqual({ awardsEligible: true, rated: true, coinMultiplier: 1 });
  });
  it('private rooms halve coins and are never rated', () => {
    const e = gameEligibility({ isPrivate: true, playerCount: 5, actionCount: 100, ...ELIG });
    expect(e).toEqual({ awardsEligible: true, rated: false, coinMultiplier: 0.5 });
  });
  it('2-player public games are never rated', () => {
    const e = gameEligibility({ isPrivate: false, playerCount: 2, actionCount: 100, ...ELIG });
    expect(e.rated).toBe(false);
    expect(e.awardsEligible).toBe(true);
  });
});

describe('dailyBonusCoins', () => {
  it('follows the 7-day curve and caps at 60', () => {
    expect([1, 2, 3, 4, 5, 6, 7].map(dailyBonusCoins)).toEqual([10, 15, 20, 30, 40, 50, 60]);
    expect(dailyBonusCoins(8)).toBe(60);
    expect(dailyBonusCoins(400)).toBe(60);
  });
  it('clamps nonsense input to day 1', () => {
    expect(dailyBonusCoins(0)).toBe(10);
    expect(dailyBonusCoins(-3)).toBe(10);
  });
});

describe('utcDayOf / previousUtcDay', () => {
  it('formats UTC days', () => {
    expect(utcDayOf(new Date('2026-07-19T12:34:56Z'))).toBe('2026-07-19');
  });
  it('crosses year boundaries', () => {
    expect(utcDayOf(new Date('2025-12-31T23:59:59Z'))).toBe('2025-12-31');
    expect(utcDayOf(new Date('2026-01-01T00:00:00Z'))).toBe('2026-01-01');
    expect(previousUtcDay('2026-01-01')).toBe('2025-12-31');
    expect(previousUtcDay('2026-03-01')).toBe('2026-02-28');
  });
});

describe('seasonKeyFor (ISO week, UTC)', () => {
  it('mid-year weeks', () => {
    expect(seasonKeyFor(new Date('2026-07-19T00:00:00Z'))).toBe('2026-W29'); // Sunday of W29
    expect(seasonKeyFor(new Date('2026-07-20T00:00:00Z'))).toBe('2026-W30'); // Monday starts W30
  });
  it('early January belongs to the previous ISO year when the week does', () => {
    // 2021-01-01 was a Friday — still ISO week 53 of 2020.
    expect(seasonKeyFor(new Date('2021-01-01T10:00:00Z'))).toBe('2020-W53');
    expect(seasonKeyFor(new Date('2021-01-04T00:00:00Z'))).toBe('2021-W01');
  });
  it('week-53 years', () => {
    expect(seasonKeyFor(new Date('2020-12-31T00:00:00Z'))).toBe('2020-W53');
    // 2026 starts on a Thursday → 53 ISO weeks; Jan 1 2027 (Friday) is still 2026-W53.
    expect(seasonKeyFor(new Date('2026-12-31T23:59:59Z'))).toBe('2026-W53');
    expect(seasonKeyFor(new Date('2027-01-01T00:00:00Z'))).toBe('2026-W53');
    expect(seasonKeyFor(new Date('2027-01-04T00:00:00Z'))).toBe('2027-W01');
  });
  it('late December can belong to next year W01', () => {
    // 2025-12-29 is a Monday of the week containing Jan 1 2026 (Thursday) → 2026-W01.
    expect(seasonKeyFor(new Date('2025-12-29T00:00:00Z'))).toBe('2026-W01');
  });
  it('pads the week number', () => {
    expect(seasonKeyFor(new Date('2026-01-05T00:00:00Z'))).toBe('2026-W02');
  });
});
