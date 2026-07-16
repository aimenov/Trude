import type { PlayerGameStats } from '@trude/engine';
import { ACHIEVEMENTS } from '../achievements/definitions.js';
import type { LifetimeStats, UnlockedAchievement } from './store.js';

/** Folds one finished game into a player's lifetime stats (mutates and returns `s`). */
export function applyGameToLifetime(
  s: LifetimeStats,
  g: PlayerGameStats,
  outcome: { won: boolean; lost: boolean },
): LifetimeStats {
  s.gamesPlayed++;
  if (outcome.won) {
    s.gamesWon++;
    s.winStreak++;
    s.bestWinStreak = Math.max(s.bestWinStreak, s.winStreak);
  } else {
    s.winStreak = 0;
  }
  if (outcome.lost) s.gamesLost++;
  s.liesSurvived += g.liesSurvived;
  s.liesCaught += g.liesCaught;
  s.checksWon += g.checksWon;
  s.checksLost += g.checksLost;
  s.cardsPickedUp += g.cardsPickedUp;
  s.quadsDiscarded += g.quadsDiscarded;
  s.jokerPassed += g.jokerPassed;
  s.jokerSmuggles += g.jokerSmuggles;
  s.truthfulThrows += g.truthfulThrows;
  s.lyingThrows += g.lyingThrows;
  return s;
}

/** Evaluates the catalog against updated lifetime + per-game stats; returns fresh unlocks. */
export function evaluateUnlocks(
  lifetime: LifetimeStats,
  game: PlayerGameStats,
  outcome: { won: boolean; lost: boolean },
  ownedKeys: ReadonlySet<string>,
): UnlockedAchievement[] {
  const fresh: UnlockedAchievement[] = [];
  for (const def of ACHIEVEMENTS) {
    if (ownedKeys.has(def.key)) continue;
    const unlocked = def.scope === 'lifetime' ? def.check(lifetime) : def.check(game, outcome);
    if (unlocked) fresh.push({ key: def.key, title: def.title, description: def.description });
  }
  return fresh;
}
