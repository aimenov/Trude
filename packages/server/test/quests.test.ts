import { describe, expect, it } from 'vitest';
import type { PlayerGameStats } from '@trude/engine';
import {
  QUEST_ALL_DONE_BONUS, QUEST_REWARD_BY_TIER, QUESTS, questReward, questsForDay,
} from '../src/quests/definitions.js';

function gameStats(partial: Partial<PlayerGameStats> = {}): PlayerGameStats {
  return {
    liesSurvived: 0, liesCaught: 0, checksWon: 0, checksLost: 0, cardsPickedUp: 0,
    quadsDiscarded: 0, jokerPassed: 0, jokerSmuggles: 0, truthfulThrows: 0, lyingThrows: 0,
    maxHandSize: 0, wasEverCaught: false, firstOut: false, ...partial,
  };
}

describe('quest catalog', () => {
  it('has 9 distinct defs with positive targets', () => {
    expect(QUESTS).toHaveLength(9);
    expect(new Set(QUESTS.map((q) => q.key)).size).toBe(9);
    for (const q of QUESTS) expect(q.target).toBeGreaterThan(0);
  });

  it('rewards by tier: easy 15 / medium 20 / hard 30 (+15 all-done bonus)', () => {
    expect(QUEST_REWARD_BY_TIER).toEqual({ easy: 15, medium: 20, hard: 30 });
    expect(QUEST_ALL_DONE_BONUS).toBe(15);
    for (const q of QUESTS) expect(questReward(q)).toBe(QUEST_REWARD_BY_TIER[q.tier]);
  });
});

describe('questsForDay', () => {
  it('is deterministic for a given day', () => {
    const a = questsForDay('2026-07-19').map((q) => q.key);
    const b = questsForDay('2026-07-19').map((q) => q.key);
    expect(a).toEqual(b);
  });

  it('always picks 3 distinct quests', () => {
    for (let i = 0; i < 60; i++) {
      const day = utcDayPlus('2026-01-01', i);
      const keys = questsForDay(day).map((q) => q.key);
      expect(keys).toHaveLength(3);
      expect(new Set(keys).size).toBe(3);
    }
  });

  it('covers most of the catalog over 30 days and varies day to day', () => {
    const seen = new Set<string>();
    const signatures = new Set<string>();
    for (let i = 0; i < 30; i++) {
      const keys = questsForDay(utcDayPlus('2026-07-01', i)).map((q) => q.key);
      keys.forEach((k) => seen.add(k));
      signatures.add(keys.join(','));
    }
    expect(seen.size).toBeGreaterThanOrEqual(8); // near-full coverage of 9
    expect(signatures.size).toBeGreaterThan(10); // not the same trio every day
  });
});

describe('progress functions', () => {
  const byKey = new Map(QUESTS.map((q) => [q.key, q]));

  it('q_play_3 counts played games', () => {
    expect(byKey.get('q_play_3')!.progress(gameStats(), { won: false, played: true })).toBe(1);
  });
  it('q_win_1 counts only wins', () => {
    const q = byKey.get('q_win_1')!;
    expect(q.progress(gameStats(), { won: true, played: true })).toBe(1);
    expect(q.progress(gameStats(), { won: false, played: true })).toBe(0);
  });
  it('stat-mapped quests read the right PlayerGameStats fields', () => {
    const o = { won: false, played: true };
    expect(byKey.get('q_truthful_10')!.progress(gameStats({ truthfulThrows: 4 }), o)).toBe(4);
    expect(byKey.get('q_pickup_10')!.progress(gameStats({ cardsPickedUp: 7 }), o)).toBe(7);
    expect(byKey.get('q_checks_won_3')!.progress(gameStats({ checksWon: 2 }), o)).toBe(2);
    expect(byKey.get('q_quad_1')!.progress(gameStats({ quadsDiscarded: 1 }), o)).toBe(1);
    expect(byKey.get('q_lies_survived_5')!.progress(gameStats({ liesSurvived: 3 }), o)).toBe(3);
    expect(byKey.get('q_joker_pass_1')!.progress(gameStats({ jokerPassed: 2 }), o)).toBe(2);
    expect(byKey.get('q_smuggle_1')!.progress(gameStats({ jokerSmuggles: 1 }), o)).toBe(1);
  });
});

function utcDayPlus(day: string, days: number): string {
  const d = new Date(`${day}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString().slice(0, 10);
}
