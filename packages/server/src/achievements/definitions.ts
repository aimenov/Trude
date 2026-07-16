import type { PlayerGameStats } from '@trude/engine';
import type { LifetimeStats } from '../store/store.js';

export type AchievementDef =
  | {
      key: string; title: string; description: string;
      scope: 'lifetime';
      check: (s: LifetimeStats) => boolean;
    }
  | {
      key: string; title: string; description: string;
      scope: 'perGame';
      check: (g: PlayerGameStats, outcome: { won: boolean; lost: boolean }) => boolean;
    };

/**
 * Launch catalog (v1). Titles are marketing copy — localized client-side by key.
 * "Win" = first player to go out safe (placement 1). "Lose" = stuck with the joker.
 */
export const ACHIEVEMENTS: AchievementDef[] = [
  {
    key: 'best_liar', title: 'The Best Liar',
    description: 'Win 10 games', scope: 'lifetime',
    check: (s) => s.gamesWon >= 10,
  },
  {
    key: 'pathological_truther', title: 'Pathological Truther',
    description: 'Win a game without a single lie (at least 8 truthful throws)', scope: 'perGame',
    check: (g, o) => o.won && g.lyingThrows === 0 && g.truthfulThrows >= 8,
  },
  {
    key: 'human_polygraph', title: 'Human Polygraph',
    description: 'Catch 25 liars', scope: 'lifetime',
    check: (s) => s.checksWon >= 25,
  },
  {
    key: 'gullible', title: 'Gullible',
    description: 'Flip a truthful card 15 times', scope: 'lifetime',
    check: (s) => s.checksLost >= 15,
  },
  {
    key: 'poker_face', title: 'Poker Face',
    description: 'Get away with 50 lies', scope: 'lifetime',
    check: (s) => s.liesSurvived >= 50,
  },
  {
    key: 'smuggler', title: 'Smuggler',
    description: 'Sneak the joker into someone else\'s hand 10 times', scope: 'lifetime',
    check: (s) => s.jokerSmuggles >= 10,
  },
  {
    key: 'hot_potato', title: 'Hot Potato',
    description: 'Pass the joker on twice in a single game', scope: 'perGame',
    check: (g) => g.jokerPassed >= 2,
  },
  {
    key: 'jokers_best_friend', title: "Joker's Best Friend",
    description: 'Lose 5 games — the joker just likes you', scope: 'lifetime',
    check: (s) => s.gamesLost >= 5,
  },
  {
    key: 'demolition_crew', title: 'Demolition Crew',
    description: 'Discard 10 four-of-a-kinds', scope: 'lifetime',
    check: (s) => s.quadsDiscarded >= 10,
  },
  {
    key: 'comeback_season', title: 'Comeback Season',
    description: 'Win a game after holding 20 or more cards', scope: 'perGame',
    check: (g, o) => o.won && g.maxHandSize >= 20,
  },
  {
    key: 'serial_winner', title: 'Serial Winner',
    description: 'Win 3 games in a row', scope: 'lifetime',
    check: (s) => s.winStreak >= 3,
  },
  {
    key: 'it_wasnt_me', title: "It Wasn't Me",
    description: 'Win a game where you lied at least 3 times and were never caught', scope: 'perGame',
    check: (g, o) => o.won && g.lyingThrows >= 3 && !g.wasEverCaught,
  },
];
