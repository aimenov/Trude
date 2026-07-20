import type { PlayerGameStats } from '@trude/engine';
import { ACHIEVEMENTS } from '../achievements/definitions.js';
import { gameEligibility, placementCoins } from '../economy/economy.js';
import { applyDelta, computeRatingDeltas, freshRating } from '../economy/rating.js';
import type { RatingSnapshot } from '../economy/rating.js';
import { QUEST_ALL_DONE_BONUS, questReward, questsForDay } from '../quests/definitions.js';
import type { LifetimeStats, QuestDelta, UnlockedAchievement } from './store.js';

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

// ---------------------------------------------------------------------------
// Game-award planning — the pure heart of recordGameResult, shared verbatim by
// MemoryStore and PrismaStore so both grant identical coins/rating/quests.
// ---------------------------------------------------------------------------

export interface EconomyNumbers {
  gameCoinsDailyCap: number;
  minActionsForAwards: number;
  minRatedPlayers: number;
  privateRoomCoinMultiplier: number;
  adReward: number;
  adDailyCap: number;
  adDoubleDailyCap: number;
}

export interface GameAwardPlanInput {
  isPrivate: boolean;
  actionCount: number;
  day: string;
  /** `placement` is leaver-adjusted; `leaver: true` = consented mid-game quit. */
  participants: { userId: string; placement: number; stats: PlayerGameStats; leaver?: boolean }[];
  /** Current rating snapshots; missing user = fresh 1000. */
  ratings: ReadonlyMap<string, RatingSnapshot>;
  /** Per-user sum of today's GAME_AWARD ledger deltas (daily-cap clamp). */
  todayGameCoins: ReadonlyMap<string, number>;
  /** Per-user quest progress for `day`, keyed by questKey. */
  questProgress: ReadonlyMap<string, ReadonlyMap<string, number>>;
  economy: EconomyNumbers;
}

export interface PlannedAward {
  coins: number;
  rated: boolean;
  ratingDelta: number;
  newRating: RatingSnapshot;
  /** All 3 daily quests with post-game progress; coins > 0 on first crossing. */
  quests: QuestDelta[];
  /** Total quest coins to grant now (completions + all-3 bonus). */
  questCoins: number;
  questBonusGranted: boolean;
}

export interface GameAwardPlan {
  rated: boolean;
  awardsEligible: boolean;
  awards: Map<string, PlannedAward>;
}

export function computeGameAwardPlan(input: GameAwardPlanInput): GameAwardPlan {
  const eligibility = gameEligibility({
    isPrivate: input.isPrivate,
    playerCount: input.participants.length,
    actionCount: input.actionCount,
    minActions: input.economy.minActionsForAwards,
    minRatedPlayers: input.economy.minRatedPlayers,
    privateRoomCoinMultiplier: input.economy.privateRoomCoinMultiplier,
  });

  const ratingDeltas = eligibility.rated
    ? computeRatingDeltas(input.participants.map((p) => ({
        userId: p.userId,
        placement: p.placement,
        snapshot: input.ratings.get(p.userId) ?? freshRating(),
      })))
    : new Map<string, number>();

  const dayQuests = questsForDay(input.day);
  const awards = new Map<string, PlannedAward>();

  for (const part of input.participants) {
    const snapshot = input.ratings.get(part.userId) ?? freshRating();
    const ratingDelta = ratingDeltas.get(part.userId) ?? 0;
    const newRating = eligibility.rated ? applyDelta(snapshot, ratingDelta) : snapshot;

    // A mid-game leaver forfeits coins and quest progress entirely; their
    // rating still takes the adjusted-last-placement hit computed above.
    let coins = 0;
    if (eligibility.awardsEligible && part.leaver !== true) {
      const base = Math.round(
        placementCoins(input.participants.length, part.placement) * eligibility.coinMultiplier,
      );
      const spentToday = input.todayGameCoins.get(part.userId) ?? 0;
      coins = Math.max(0, Math.min(base, input.economy.gameCoinsDailyCap - spentToday));
    }

    const quests: QuestDelta[] = [];
    let questCoins = 0;
    let completedCount = 0;
    let freshlyCompleted = 0;
    if (eligibility.rated && part.leaver !== true) {
      const mine = input.questProgress.get(part.userId);
      const outcome = { won: part.placement === 1, played: true };
      for (const def of dayQuests) {
        const before = mine?.get(def.key) ?? 0;
        const after = Math.min(def.target, before + def.progress(part.stats, outcome));
        const completed = after >= def.target;
        const firstCrossing = completed && before < def.target;
        const reward = firstCrossing ? questReward(def) : 0;
        if (completed) completedCount++;
        if (firstCrossing) freshlyCompleted++;
        questCoins += reward;
        quests.push({ key: def.key, progress: after, target: def.target, completed, coins: reward });
      }
    }
    const questBonusGranted = eligibility.rated
      && completedCount === dayQuests.length && freshlyCompleted > 0;
    if (questBonusGranted) questCoins += QUEST_ALL_DONE_BONUS;

    awards.set(part.userId, {
      coins,
      rated: eligibility.rated,
      ratingDelta: eligibility.rated ? ratingDelta : 0,
      newRating,
      quests,
      questCoins,
      questBonusGranted,
    });
  }

  return { rated: eligibility.rated, awardsEligible: eligibility.awardsEligible, awards };
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
