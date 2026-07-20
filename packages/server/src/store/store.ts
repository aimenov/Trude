import { randomUUID } from 'node:crypto';
import type { PlayerGameStats } from '@trude/engine';
import { config } from '../config.js';
import {
  dailyBonusCoins, previousUtcDay, seasonKeyFor, utcDayOf,
} from '../economy/economy.js';
import { freshRating } from '../economy/rating.js';
import type { RatingSnapshot } from '../economy/rating.js';
import { PRODUCTS } from '../economy/products.js';
import {
  COSMETICS, COSMETICS_BY_KEY, DEFAULT_CARD_BACK, DEFAULT_FELT, isImplicitlyOwned,
} from '../cosmetics/definitions.js';
import { questReward, questsForDay } from '../quests/definitions.js';
import { applyGameToLifetime, computeGameAwardPlan, evaluateUnlocks } from './shared.js';
import type { EconomyNumbers } from './shared.js';

export interface UserRecord {
  id: string;
  nickname: string;
  avatar: string;
  deviceId: string | null;
}

export interface LifetimeStats {
  gamesPlayed: number;
  gamesWon: number;       // placement 1 (first to go out safe)
  gamesLost: number;      // stuck with the joker
  winStreak: number;
  bestWinStreak: number;
  liesSurvived: number;
  liesCaught: number;
  checksWon: number;
  checksLost: number;
  cardsPickedUp: number;
  quadsDiscarded: number;
  jokerPassed: number;
  jokerSmuggles: number;
  truthfulThrows: number;
  lyingThrows: number;
}

export interface GameResultInput {
  roomId: string;
  deckSize: number;
  status: 'FINISHED' | 'ABANDONED';
  loserUserId: string | null;
  /** `placement` is the leaver-adjusted standing; `leaver: true` marks a consented
   *  mid-game quit (0 coins, no quest progress; rating applies as normal). */
  participants: { userId: string; placement: number; stats: PlayerGameStats; leaver?: boolean }[];
  /** Private rooms halve coins and are never rated. Defaults false. */
  isPrivate?: boolean;
  /** Engine action count at game over; short games award nothing. Defaults 0. */
  actionCount?: number;
}

export interface UnlockedAchievement { key: string; title: string; description: string; }

/** One daily quest's post-game state; `coins` > 0 only on first completion. */
export interface QuestDelta {
  key: string;
  progress: number;
  target: number;
  completed: boolean;
  coins: number;
}

/** Per-user payload of the `rewards` room message (see docs/protocol.md). */
export interface GameAwards {
  /** The persisted GameResult id — the `gameId` for "double your winnings" ads. */
  gameId: string;
  achievements: UnlockedAchievement[];
  coins: number;
  ratingDelta: number;
  newRating: number;
  rated: boolean;
  quests: QuestDelta[];
  balance: number;
}

export interface MetaProfile {
  coins: number;
  rating: number;
  premium: boolean;
  dailyStreak: number;
  dailyClaimedToday: boolean;
  selected: { cardBack: string; felt: string };
}

export interface DailyClaimResult {
  claimed: boolean;
  day: string;
  streak: number;
  coins: number;
  balance: number;
  nextBonus: number;
}

export interface QuestState {
  day: string;
  quests: { key: string; target: number; reward: number; progress: number; completed: boolean }[];
}

export interface OwnedCosmetics {
  owned: string[];
  selected: { cardBack: string; felt: string };
}

export interface AdGrantResult { coins: number; balance: number; remainingToday: number; }

export interface IapGrantResult {
  productId: string;
  granted: { coins: number; premium: boolean };
  balance: number;
  premium: boolean;
  alreadyProcessed: boolean;
}

export interface LeaderboardEntry {
  rank: number;
  userId: string;
  nickname: string;
  avatar: string;
  value: number;
  gamesRated: number;
}

export interface LeaderboardPage {
  scope: 'weekly' | 'alltime';
  seasonKey?: string;
  entries: LeaderboardEntry[];
  me: { rank: number; value: number; gamesRated: number } | null;
}

/** One row of `GET /me/blocks` — a user the caller has blocked. */
export interface BlockEntry {
  userId: string;
  /** '—' when the blocked account no longer exists. */
  nickname: string;
  /** Epoch ms of the block. */
  createdAt: number;
}

/** Max NEW reports (distinct reported users) one reporter may file per UTC day. */
export const REPORT_DAILY_LIMIT = 20;

/** Store-level failure with a wire error code (mapped to HTTP in meta/routes.ts). */
export class MetaError extends Error {
  constructor(public readonly code: string) {
    super(code);
    this.name = 'MetaError';
  }
}

export interface Store {
  upsertGuest(deviceId: string, nickname: string, avatar: string): Promise<UserRecord>;
  getUser(id: string): Promise<UserRecord | null>;
  updateProfile(id: string, patch: { nickname?: string | undefined; avatar?: string | undefined }): Promise<UserRecord>;
  getStats(id: string): Promise<LifetimeStats>;
  getAchievements(id: string): Promise<{ key: string; unlockedAt: number }[]>;
  /** Applies a finished game transactionally; returns per-user awards (achievements, coins, rating, quests). */
  recordGameResult(result: GameResultInput): Promise<Map<string, GameAwards>>;
  getMetaProfile(userId: string, now?: Date): Promise<MetaProfile>;
  claimDaily(userId: string, now?: Date): Promise<DailyClaimResult>;
  getQuestState(userId: string, now?: Date): Promise<QuestState>;
  getOwnedCosmetics(userId: string): Promise<OwnedCosmetics>;
  buyCosmetic(userId: string, itemKey: string): Promise<{ itemKey: string; balance: number }>;
  selectCosmetics(userId: string, sel: { cardBack?: string | undefined; felt?: string | undefined }): Promise<{ cardBack: string; felt: string }>;
  grantAdReward(userId: string, grant: { jti: string; kind: 'shop' | 'double'; gameId?: string | undefined }, now?: Date): Promise<AdGrantResult>;
  /** How many rewarded ads of this kind the user may still claim today. */
  adRemainingToday(userId: string, kind: 'shop' | 'double', now?: Date): Promise<number>;
  applyIapPurchase(userId: string, purchase: { platform: 'google' | 'apple'; productId: string; orderId: string }): Promise<IapGrantResult>;
  getLeaderboard(scope: 'weekly' | 'alltime', limit: number, meUserId: string, now?: Date): Promise<LeaderboardPage>;
  /** Blocks `blockedId` for `blockerId`. Duplicate = idempotent success; self ⇒ CANNOT_BLOCK_SELF. */
  blockUser(blockerId: string, blockedId: string): Promise<void>;
  /** Removes a block. Idempotent (unblocking a non-block succeeds silently). */
  unblockUser(blockerId: string, blockedId: string): Promise<void>;
  /** Users blocked BY `userId`, newest first. */
  listBlocks(userId: string): Promise<BlockEntry[]>;
  /** Files a report. Same reporter→reported same UTC day = idempotent success;
   *  more than REPORT_DAILY_LIMIT new reports/day ⇒ REPORT_LIMIT. */
  reportUser(reporterId: string, report: { userId: string; reason: string; roomId?: string | undefined }, now?: Date): Promise<void>;
  /** True when a block exists between `userId` and ANY of `otherIds`, in either direction. */
  hasBlockBetween(userId: string, otherIds: string[]): Promise<boolean>;
  /** Deletes the user and every dependent row. Idempotent. */
  deleteUser(userId: string): Promise<void>;
}

export function freshLifetime(): LifetimeStats {
  return {
    gamesPlayed: 0, gamesWon: 0, gamesLost: 0, winStreak: 0, bestWinStreak: 0,
    liesSurvived: 0, liesCaught: 0, checksWon: 0, checksLost: 0, cardsPickedUp: 0,
    quadsDiscarded: 0, jokerPassed: 0, jokerSmuggles: 0, truthfulThrows: 0, lyingThrows: 0,
  };
}

interface LedgerRow {
  userId: string;
  delta: number;
  reason: string;
  idempotencyKey: string;
  meta: Record<string, unknown> | null;
  createdAt: Date;
}

/**
 * In-memory store — the dev/test default. The Prisma/Postgres implementation
 * implements the same interface; game code never sees the difference.
 * Feature-complete mirror: every meta flow works here (all HTTP tests run on it).
 */
export class MemoryStore implements Store {
  private users = new Map<string, UserRecord>();
  private byDevice = new Map<string, string>();
  private stats = new Map<string, LifetimeStats>();
  private achievements = new Map<string, Map<string, number>>();
  private wallets = new Map<string, number>();
  private ledger = new Map<string, LedgerRow>(); // keyed by idempotencyKey
  private ratings = new Map<string, RatingSnapshot>();
  private seasons = new Map<string, Map<string, { points: number; gamesRated: number }>>();
  private daily = new Map<string, { lastClaimDay: string | null; streak: number }>();
  private questProg = new Map<string, number>(); // `${userId}|${day}|${questKey}` -> progress
  private owned = new Map<string, Set<string>>();
  private selected = new Map<string, { cardBack: string; felt: string }>();
  private premium = new Set<string>();
  private iapOrders = new Map<string, { userId: string; productId: string }>();
  private blocks = new Map<string, Map<string, Date>>(); // blockerId -> (blockedId -> createdAt)
  private reports: { reporterId: string; reportedId: string; reason: string; roomId: string | null; createdAt: Date }[] = [];

  constructor(private economy: EconomyNumbers = config.economy) {}

  async upsertGuest(deviceId: string, nickname: string, avatar: string): Promise<UserRecord> {
    const existingId = this.byDevice.get(deviceId);
    if (existingId) return this.users.get(existingId)!;
    const user: UserRecord = { id: randomUUID(), nickname, avatar, deviceId };
    this.users.set(user.id, user);
    this.byDevice.set(deviceId, user.id);
    return user;
  }

  async getUser(id: string): Promise<UserRecord | null> {
    return this.users.get(id) ?? null;
  }

  async updateProfile(id: string, patch: { nickname?: string | undefined; avatar?: string | undefined }): Promise<UserRecord> {
    const user = this.users.get(id);
    if (!user) throw new Error('No such user');
    if (patch.nickname !== undefined) user.nickname = patch.nickname;
    if (patch.avatar !== undefined) user.avatar = patch.avatar;
    return user;
  }

  async getStats(id: string): Promise<LifetimeStats> {
    return this.stats.get(id) ?? freshLifetime();
  }

  async getAchievements(id: string): Promise<{ key: string; unlockedAt: number }[]> {
    const m = this.achievements.get(id);
    return m ? [...m.entries()].map(([key, unlockedAt]) => ({ key, unlockedAt })) : [];
  }

  // -------------------------------------------------------------------------
  // Ledger/wallet primitives (idempotencyKey-unique, wallet mirrors the sum)
  // -------------------------------------------------------------------------

  private addLedger(userId: string, delta: number, reason: string, idempotencyKey: string,
    meta: Record<string, unknown> | null = null, now: Date = new Date()): boolean {
    if (this.ledger.has(idempotencyKey)) return false;
    this.ledger.set(idempotencyKey, { userId, delta, reason, idempotencyKey, meta, createdAt: now });
    this.wallets.set(userId, (this.wallets.get(userId) ?? 0) + delta);
    return true;
  }

  private balance(userId: string): number {
    return this.wallets.get(userId) ?? 0;
  }

  private sumToday(userId: string, reasons: string[], now: Date): number {
    const day = utcDayOf(now);
    let sum = 0;
    for (const row of this.ledger.values()) {
      if (row.userId === userId && reasons.includes(row.reason) && utcDayOf(row.createdAt) === day) sum += row.delta;
    }
    return sum;
  }

  private countToday(userId: string, reason: string, now: Date): number {
    const day = utcDayOf(now);
    let n = 0;
    for (const row of this.ledger.values()) {
      if (row.userId === userId && row.reason === reason && utcDayOf(row.createdAt) === day) n++;
    }
    return n;
  }

  // -------------------------------------------------------------------------
  // Game results
  // -------------------------------------------------------------------------

  async recordGameResult(result: GameResultInput): Promise<Map<string, GameAwards>> {
    const awardsByUser = new Map<string, GameAwards>();
    if (result.status !== 'FINISHED') return awardsByUser; // ABANDONED: no row to keep in memory

    const now = new Date();
    const day = utcDayOf(now);
    const seasonKey = seasonKeyFor(now);
    const gameResultId = randomUUID(); // (1) the "created row" — ledger keys use this, not roomId

    // (2)+(3) eligibility + rating plan from current snapshots
    const plan = computeGameAwardPlan({
      isPrivate: result.isPrivate ?? false,
      actionCount: result.actionCount ?? 0,
      day,
      participants: result.participants,
      ratings: this.ratings,
      todayGameCoins: new Map(result.participants.map((p) => [
        p.userId, this.sumToday(p.userId, ['GAME_AWARD'], now),
      ])),
      questProgress: new Map(result.participants.map((p) => [
        p.userId,
        new Map(questsForDay(day).map((q) => [q.key, this.questProg.get(`${p.userId}|${day}|${q.key}`) ?? 0])),
      ])),
      economy: this.economy,
    });

    for (const part of result.participants) {
      const planned = plan.awards.get(part.userId)!;

      // (3) rating + season score
      if (plan.rated) {
        this.ratings.set(part.userId, planned.newRating);
        const season = this.seasons.get(seasonKey) ?? new Map<string, { points: number; gamesRated: number }>();
        this.seasons.set(seasonKey, season);
        const row = season.get(part.userId) ?? { points: 0, gamesRated: 0 };
        row.points += planned.ratingDelta;
        row.gamesRated += 1;
        season.set(part.userId, row);
      }

      // (4) existing fold + achievements loop — unchanged behavior
      const outcome = { won: part.placement === 1, lost: part.userId === result.loserUserId };
      const s = applyGameToLifetime(this.stats.get(part.userId) ?? freshLifetime(), part.stats, outcome);
      this.stats.set(part.userId, s);
      const mine = this.achievements.get(part.userId) ?? new Map<string, number>();
      this.achievements.set(part.userId, mine);
      const fresh = evaluateUnlocks(s, part.stats, outcome, new Set(mine.keys()));
      for (const a of fresh) mine.set(a.key, Date.now());

      // (5) coins (clamped in the plan)
      if (planned.coins > 0) {
        this.addLedger(part.userId, planned.coins, 'GAME_AWARD', `game:${gameResultId}:${part.userId}`,
          { roomId: result.roomId, placement: part.placement }, now);
      }

      // (6) quests — first crossings + all-3 bonus
      for (const q of planned.quests) {
        this.questProg.set(`${part.userId}|${day}|${q.key}`, q.progress);
        if (q.coins > 0) {
          this.addLedger(part.userId, q.coins, 'QUEST', `quest:${part.userId}:${day}:${q.key}`, null, now);
        }
      }
      if (planned.questBonusGranted) {
        this.addLedger(part.userId, planned.questCoins - planned.quests.reduce((a, q) => a + q.coins, 0),
          'QUEST_BONUS', `questbonus:${part.userId}:${day}`, null, now);
      }

      // (7) assemble
      awardsByUser.set(part.userId, {
        gameId: gameResultId,
        achievements: fresh,
        coins: planned.coins,
        ratingDelta: planned.ratingDelta,
        newRating: planned.newRating.rating,
        rated: planned.rated,
        quests: planned.quests,
        balance: this.balance(part.userId),
      });
    }
    return awardsByUser;
  }

  // -------------------------------------------------------------------------
  // Meta profile / daily / quests
  // -------------------------------------------------------------------------

  async getMetaProfile(userId: string, now: Date = new Date()): Promise<MetaProfile> {
    const rating = this.ratings.get(userId) ?? freshRating();
    const daily = this.daily.get(userId);
    const sel = this.selected.get(userId);
    return {
      coins: this.balance(userId),
      rating: rating.rating,
      premium: this.premium.has(userId),
      dailyStreak: daily?.streak ?? 0,
      dailyClaimedToday: daily?.lastClaimDay === utcDayOf(now),
      selected: { cardBack: sel?.cardBack ?? DEFAULT_CARD_BACK, felt: sel?.felt ?? DEFAULT_FELT },
    };
  }

  async claimDaily(userId: string, now: Date = new Date()): Promise<DailyClaimResult> {
    const day = utcDayOf(now);
    const state = this.daily.get(userId) ?? { lastClaimDay: null, streak: 0 };
    if (state.lastClaimDay === day) {
      return {
        claimed: false, day, streak: state.streak, coins: 0,
        balance: this.balance(userId), nextBonus: dailyBonusCoins(state.streak + 1),
      };
    }
    const streak = state.lastClaimDay === previousUtcDay(day) ? state.streak + 1 : 1;
    const coins = dailyBonusCoins(streak);
    if (!this.addLedger(userId, coins, 'DAILY_BONUS', `daily:${userId}:${day}`, null, now)) {
      return {
        claimed: false, day, streak: state.streak, coins: 0,
        balance: this.balance(userId), nextBonus: dailyBonusCoins(state.streak + 1),
      };
    }
    this.daily.set(userId, { lastClaimDay: day, streak });
    return { claimed: true, day, streak, coins, balance: this.balance(userId), nextBonus: dailyBonusCoins(streak + 1) };
  }

  async getQuestState(userId: string, now: Date = new Date()): Promise<QuestState> {
    const day = utcDayOf(now);
    return {
      day,
      quests: questsForDay(day).map((q) => {
        const progress = this.questProg.get(`${userId}|${day}|${q.key}`) ?? 0;
        return { key: q.key, target: q.target, reward: questReward(q), progress, completed: progress >= q.target };
      }),
    };
  }

  // -------------------------------------------------------------------------
  // Cosmetics
  // -------------------------------------------------------------------------

  async getOwnedCosmetics(userId: string): Promise<OwnedCosmetics> {
    const sel = this.selected.get(userId);
    const owned = new Set<string>([DEFAULT_CARD_BACK, DEFAULT_FELT, ...(this.owned.get(userId) ?? [])]);
    return {
      owned: COSMETICS.filter((c) => owned.has(c.key)).map((c) => c.key),
      selected: { cardBack: sel?.cardBack ?? DEFAULT_CARD_BACK, felt: sel?.felt ?? DEFAULT_FELT },
    };
  }

  private ownsCosmetic(userId: string, key: string): boolean {
    return isImplicitlyOwned(key) || (this.owned.get(userId)?.has(key) ?? false);
  }

  async buyCosmetic(userId: string, itemKey: string): Promise<{ itemKey: string; balance: number }> {
    const def = COSMETICS_BY_KEY.get(itemKey);
    if (!def) throw new MetaError('UNKNOWN_ITEM');
    if (this.ownsCosmetic(userId, itemKey)) throw new MetaError('ALREADY_OWNED');
    if (def.premiumOnly && !this.premium.has(userId)) throw new MetaError('PREMIUM_REQUIRED');
    if (this.balance(userId) < def.price) throw new MetaError('INSUFFICIENT_FUNDS');
    if (def.price > 0
      && !this.addLedger(userId, -def.price, 'SHOP_PURCHASE', `shop:${userId}:${itemKey}`)) {
      throw new MetaError('ALREADY_OWNED');
    }
    const mine = this.owned.get(userId) ?? new Set<string>();
    this.owned.set(userId, mine);
    mine.add(itemKey);
    return { itemKey, balance: this.balance(userId) };
  }

  async selectCosmetics(userId: string, sel: { cardBack?: string | undefined; felt?: string | undefined }): Promise<{ cardBack: string; felt: string }> {
    const current = this.selected.get(userId) ?? { cardBack: DEFAULT_CARD_BACK, felt: DEFAULT_FELT };
    if (sel.cardBack !== undefined) {
      const def = COSMETICS_BY_KEY.get(sel.cardBack);
      if (!def || def.kind !== 'cardBack' || !this.ownsCosmetic(userId, sel.cardBack)) throw new MetaError('NOT_OWNED');
      current.cardBack = sel.cardBack;
    }
    if (sel.felt !== undefined) {
      const def = COSMETICS_BY_KEY.get(sel.felt);
      if (!def || def.kind !== 'felt' || !this.ownsCosmetic(userId, sel.felt)) throw new MetaError('NOT_OWNED');
      current.felt = sel.felt;
    }
    this.selected.set(userId, current);
    return { ...current };
  }

  // -------------------------------------------------------------------------
  // Rewarded ads
  // -------------------------------------------------------------------------

  async adRemainingToday(userId: string, kind: 'shop' | 'double', now: Date = new Date()): Promise<number> {
    const cap = kind === 'shop' ? this.economy.adDailyCap : this.economy.adDoubleDailyCap;
    const used = this.countToday(userId, kind === 'shop' ? 'AD_REWARD' : 'AD_DOUBLE', now);
    return Math.max(0, cap - used);
  }

  async grantAdReward(userId: string, grant: { jti: string; kind: 'shop' | 'double'; gameId?: string | undefined }, now: Date = new Date()): Promise<AdGrantResult> {
    const remaining = await this.adRemainingToday(userId, grant.kind, now);
    if (remaining <= 0) throw new MetaError('DAILY_CAP');

    if (grant.kind === 'shop') {
      if (!this.addLedger(userId, this.economy.adReward, 'AD_REWARD', `ad:${grant.jti}`, null, now)) {
        throw new MetaError('TOKEN_USED');
      }
      return { coins: this.economy.adReward, balance: this.balance(userId), remainingToday: remaining - 1 };
    }

    // kind === 'double': grant that game's GAME_AWARD amount, once per game.
    if (!grant.gameId) throw new MetaError('BAD_TOKEN');
    const gameAward = this.ledger.get(`game:${grant.gameId}:${userId}`);
    if (!gameAward || gameAward.delta <= 0) throw new MetaError('BAD_TOKEN');
    if (!this.addLedger(userId, gameAward.delta, 'AD_DOUBLE', `double:${grant.gameId}:${userId}`, null, now)) {
      throw new MetaError('TOKEN_USED');
    }
    return { coins: gameAward.delta, balance: this.balance(userId), remainingToday: remaining - 1 };
  }

  // -------------------------------------------------------------------------
  // IAP
  // -------------------------------------------------------------------------

  async applyIapPurchase(userId: string, purchase: { platform: 'google' | 'apple'; productId: string; orderId: string }): Promise<IapGrantResult> {
    const product = PRODUCTS[purchase.productId];
    if (!product) throw new MetaError('UNKNOWN_PRODUCT');

    const existing = this.iapOrders.get(purchase.orderId);
    if (existing) {
      if (existing.userId !== userId) throw new MetaError('RECEIPT_OWNED_BY_OTHER_USER');
      return {
        productId: product.id, granted: { coins: 0, premium: false },
        balance: this.balance(userId), premium: this.premium.has(userId), alreadyProcessed: true,
      };
    }

    this.iapOrders.set(purchase.orderId, { userId, productId: product.id });
    if (product.coins > 0) {
      this.addLedger(userId, product.coins, 'IAP', `iap:${purchase.orderId}`, { productId: product.id });
    }
    if (product.premium) {
      this.premium.add(userId);
      // Premium unlocks premium-only cosmetics exactly once.
      const mine = this.owned.get(userId) ?? new Set<string>();
      this.owned.set(userId, mine);
      for (const c of COSMETICS) if (c.premiumOnly) mine.add(c.key);
    }
    return {
      productId: product.id,
      granted: { coins: product.coins, premium: product.premium },
      balance: this.balance(userId),
      premium: this.premium.has(userId),
      alreadyProcessed: false,
    };
  }

  // -------------------------------------------------------------------------
  // Leaderboards
  // -------------------------------------------------------------------------

  async getLeaderboard(scope: 'weekly' | 'alltime', limit: number, meUserId: string, now: Date = new Date()): Promise<LeaderboardPage> {
    const rows: { userId: string; value: number; gamesRated: number }[] = [];
    let seasonKey: string | undefined;
    if (scope === 'alltime') {
      for (const [userId, r] of this.ratings) rows.push({ userId, value: r.rating, gamesRated: r.gamesRated });
    } else {
      seasonKey = seasonKeyFor(now);
      for (const [userId, r] of this.seasons.get(seasonKey) ?? []) {
        rows.push({ userId, value: r.points, gamesRated: r.gamesRated });
      }
    }
    rows.sort((a, b) => b.value - a.value || a.userId.localeCompare(b.userId));
    const entries = rows.slice(0, limit).map((r, i) => {
      const user = this.users.get(r.userId);
      return {
        rank: i + 1, userId: r.userId,
        nickname: user?.nickname ?? '???', avatar: user?.avatar ?? 'a0',
        value: r.value, gamesRated: r.gamesRated,
      };
    });
    const mine = rows.find((r) => r.userId === meUserId);
    const me = mine
      ? { rank: rows.filter((r) => r.value > mine.value).length + 1, value: mine.value, gamesRated: mine.gamesRated }
      : null;
    const page: LeaderboardPage = { scope, entries, me };
    if (seasonKey !== undefined) page.seasonKey = seasonKey;
    return page;
  }

  // -------------------------------------------------------------------------
  // Blocks & reports
  // -------------------------------------------------------------------------

  async blockUser(blockerId: string, blockedId: string): Promise<void> {
    if (blockerId === blockedId) throw new MetaError('CANNOT_BLOCK_SELF');
    const mine = this.blocks.get(blockerId) ?? new Map<string, Date>();
    this.blocks.set(blockerId, mine);
    if (!mine.has(blockedId)) mine.set(blockedId, new Date());
  }

  async unblockUser(blockerId: string, blockedId: string): Promise<void> {
    this.blocks.get(blockerId)?.delete(blockedId);
  }

  async listBlocks(userId: string): Promise<BlockEntry[]> {
    const mine = this.blocks.get(userId);
    if (!mine) return [];
    return [...mine.entries()]
      .map(([blockedId, createdAt]) => ({
        userId: blockedId,
        nickname: this.users.get(blockedId)?.nickname ?? '—',
        createdAt: createdAt.getTime(),
      }))
      .sort((a, b) => b.createdAt - a.createdAt || a.userId.localeCompare(b.userId));
  }

  async reportUser(
    reporterId: string,
    report: { userId: string; reason: string; roomId?: string | undefined },
    now: Date = new Date(),
  ): Promise<void> {
    const day = utcDayOf(now);
    const todays = this.reports.filter((r) => r.reporterId === reporterId && utcDayOf(r.createdAt) === day);
    if (todays.some((r) => r.reportedId === report.userId)) return; // idempotent per day
    if (todays.length >= REPORT_DAILY_LIMIT) throw new MetaError('REPORT_LIMIT');
    this.reports.push({
      reporterId, reportedId: report.userId, reason: report.reason,
      roomId: report.roomId ?? null, createdAt: now,
    });
  }

  async hasBlockBetween(userId: string, otherIds: string[]): Promise<boolean> {
    const mine = this.blocks.get(userId);
    return otherIds.some((other) =>
      (mine?.has(other) ?? false) || (this.blocks.get(other)?.has(userId) ?? false));
  }

  // -------------------------------------------------------------------------
  // Account deletion
  // -------------------------------------------------------------------------

  async deleteUser(userId: string): Promise<void> {
    const user = this.users.get(userId);
    if (user?.deviceId) this.byDevice.delete(user.deviceId);
    this.users.delete(userId);
    this.stats.delete(userId);
    this.achievements.delete(userId);
    this.wallets.delete(userId);
    this.ratings.delete(userId);
    this.daily.delete(userId);
    this.owned.delete(userId);
    this.selected.delete(userId);
    this.premium.delete(userId);
    for (const [key, row] of this.ledger) if (row.userId === userId) this.ledger.delete(key);
    for (const season of this.seasons.values()) season.delete(userId);
    for (const key of [...this.questProg.keys()]) if (key.startsWith(`${userId}|`)) this.questProg.delete(key);
    for (const [orderId, o] of this.iapOrders) if (o.userId === userId) this.iapOrders.delete(orderId);
    this.blocks.delete(userId);
    for (const mine of this.blocks.values()) mine.delete(userId);
    this.reports = this.reports.filter((r) => r.reporterId !== userId && r.reportedId !== userId);
  }
}
