import { PrismaClient, Prisma } from '@prisma/client';
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
import { freshLifetime, MetaError } from './store.js';
import type {
  AdGrantResult, DailyClaimResult, GameAwards, GameResultInput, IapGrantResult,
  LeaderboardPage, LifetimeStats, MetaProfile, OwnedCosmetics, QuestState, Store, UserRecord,
} from './store.js';

type Tx = Prisma.TransactionClient;

function dayStartUtc(now: Date): Date {
  return new Date(`${utcDayOf(now)}T00:00:00.000Z`);
}

/** Postgres-backed store. Selected when DATABASE_URL is set (see index.ts). */
export class PrismaStore implements Store {
  private prisma: PrismaClient;
  private economy: EconomyNumbers;

  constructor(prisma?: PrismaClient, economy: EconomyNumbers = config.economy) {
    this.prisma = prisma ?? new PrismaClient();
    this.economy = economy;
  }

  async upsertGuest(deviceId: string, nickname: string, avatar: string): Promise<UserRecord> {
    const user = await this.prisma.user.upsert({
      where: { deviceId },
      update: {},
      create: { deviceId, nickname, avatar },
    });
    return { id: user.id, nickname: user.nickname, avatar: user.avatar, deviceId: user.deviceId };
  }

  async getUser(id: string): Promise<UserRecord | null> {
    const user = await this.prisma.user.findUnique({ where: { id } });
    return user && { id: user.id, nickname: user.nickname, avatar: user.avatar, deviceId: user.deviceId };
  }

  async updateProfile(id: string, patch: { nickname?: string | undefined; avatar?: string | undefined }): Promise<UserRecord> {
    const data: Record<string, string> = {};
    if (patch.nickname !== undefined) data['nickname'] = patch.nickname;
    if (patch.avatar !== undefined) data['avatar'] = patch.avatar;
    const user = await this.prisma.user.update({ where: { id }, data });
    return { id: user.id, nickname: user.nickname, avatar: user.avatar, deviceId: user.deviceId };
  }

  async getStats(id: string): Promise<LifetimeStats> {
    const row = await this.prisma.playerStats.findUnique({ where: { userId: id } });
    if (!row) return freshLifetime();
    const { userId: _userId, ...stats } = row;
    return stats;
  }

  async getAchievements(id: string): Promise<{ key: string; unlockedAt: number }[]> {
    const rows = await this.prisma.userAchievement.findMany({ where: { userId: id } });
    return rows.map((r) => ({ key: r.key, unlockedAt: r.unlockedAt.getTime() }));
  }

  // -------------------------------------------------------------------------
  // Ledger/wallet primitives inside a transaction
  // -------------------------------------------------------------------------

  private async addLedger(tx: Tx, userId: string, delta: number, reason: string,
    idempotencyKey: string, meta: Record<string, unknown> | null = null): Promise<boolean> {
    const existing = await tx.coinLedger.findUnique({ where: { idempotencyKey } });
    if (existing) return false;
    await tx.coinLedger.create({
      data: { userId, delta, reason, idempotencyKey, meta: (meta as Prisma.InputJsonValue | null) ?? Prisma.JsonNull },
    });
    await tx.wallet.upsert({
      where: { userId },
      update: { coins: { increment: delta } },
      create: { userId, coins: delta },
    });
    return true;
  }

  private async balance(tx: Tx, userId: string): Promise<number> {
    return (await tx.wallet.findUnique({ where: { userId } }))?.coins ?? 0;
  }

  private async sumToday(tx: Tx, userId: string, reason: string, now: Date): Promise<number> {
    const agg = await tx.coinLedger.aggregate({
      _sum: { delta: true },
      where: { userId, reason, createdAt: { gte: dayStartUtc(now) } },
    });
    return agg._sum.delta ?? 0;
  }

  private async countToday(tx: Tx, userId: string, reason: string, now: Date): Promise<number> {
    return tx.coinLedger.count({ where: { userId, reason, createdAt: { gte: dayStartUtc(now) } } });
  }

  // -------------------------------------------------------------------------
  // Game results — transaction order mirrors MemoryStore exactly
  // -------------------------------------------------------------------------

  async recordGameResult(result: GameResultInput): Promise<Map<string, GameAwards>> {
    const awardsByUser = new Map<string, GameAwards>();
    const now = new Date();
    const day = utcDayOf(now);
    const seasonKey = seasonKeyFor(now);

    await this.prisma.$transaction(async (tx) => {
      // (2 pre-computed) eligibility inputs
      const ratings = new Map<string, RatingSnapshot>();
      const todayGameCoins = new Map<string, number>();
      const questProgress = new Map<string, Map<string, number>>();
      const dayQuests = questsForDay(day);
      if (result.status === 'FINISHED') {
        for (const p of result.participants) {
          const r = await tx.rating.findUnique({ where: { userId: p.userId } });
          if (r) ratings.set(p.userId, { rating: r.rating, peakRating: r.peakRating, gamesRated: r.gamesRated });
          todayGameCoins.set(p.userId, await this.sumToday(tx, p.userId, 'GAME_AWARD', now));
          const progRows = await tx.questProgress.findMany({ where: { userId: p.userId, day } });
          questProgress.set(p.userId, new Map(
            dayQuests.map((q) => [q.key, progRows.find((row) => row.questKey === q.key)?.progress ?? 0]),
          ));
        }
      }

      const plan = computeGameAwardPlan({
        isPrivate: result.isPrivate ?? false,
        actionCount: result.actionCount ?? 0,
        day,
        participants: result.participants,
        ratings,
        todayGameCoins,
        questProgress,
        economy: this.economy,
      });

      // (1) create GameResult, capture id — ledger keys use gameResultId, NOT roomId.
      const created = await tx.gameResult.create({
        data: {
          roomId: result.roomId,
          deckSize: result.deckSize,
          status: result.status,
          loserUserId: result.loserUserId,
          participants: result.participants.map((p) => ({ userId: p.userId, placement: p.placement })),
          isPrivate: result.isPrivate ?? false,
          actionCount: result.actionCount ?? 0,
          rated: result.status === 'FINISHED' && plan.rated,
        },
      });
      if (result.status !== 'FINISHED') return;

      for (const part of result.participants) {
        const planned = plan.awards.get(part.userId)!;

        // (3) rating + season score
        if (plan.rated) {
          await tx.rating.upsert({
            where: { userId: part.userId },
            update: {
              rating: planned.newRating.rating,
              peakRating: planned.newRating.peakRating,
              gamesRated: planned.newRating.gamesRated,
            },
            create: { userId: part.userId, ...planned.newRating },
          });
          await tx.seasonScore.upsert({
            where: { seasonKey_userId: { seasonKey, userId: part.userId } },
            update: { points: { increment: planned.ratingDelta }, gamesRated: { increment: 1 } },
            create: { seasonKey, userId: part.userId, points: planned.ratingDelta, gamesRated: 1 },
          });
        }

        // (4) existing fold + achievements loop — UNCHANGED
        const outcome = { won: part.placement === 1, lost: part.userId === result.loserUserId };
        const existing = await tx.playerStats.findUnique({ where: { userId: part.userId } });
        const lifetime = applyGameToLifetime(
          existing ? (({ userId: _u, ...s }) => s)(existing) : freshLifetime(),
          part.stats,
          outcome,
        );
        await tx.playerStats.upsert({
          where: { userId: part.userId },
          update: lifetime,
          create: { userId: part.userId, ...lifetime },
        });
        const owned = await tx.userAchievement.findMany({ where: { userId: part.userId }, select: { key: true } });
        const fresh = evaluateUnlocks(lifetime, part.stats, outcome, new Set(owned.map((o) => o.key)));
        if (fresh.length) {
          await tx.userAchievement.createMany({
            data: fresh.map((a) => ({ userId: part.userId, key: a.key })),
            skipDuplicates: true,
          });
        }

        // (5) coins (clamped to daily headroom in the plan)
        if (planned.coins > 0) {
          await this.addLedger(tx, part.userId, planned.coins, 'GAME_AWARD',
            `game:${created.id}:${part.userId}`, { roomId: result.roomId, placement: part.placement });
        }

        // (6) quests — progress upserts, first-crossing grants, all-3 bonus
        for (const q of planned.quests) {
          await tx.questProgress.upsert({
            where: { userId_day_questKey: { userId: part.userId, day, questKey: q.key } },
            update: { progress: q.progress, ...(q.completed ? { completedAt: now } : {}) },
            create: {
              userId: part.userId, day, questKey: q.key, progress: q.progress,
              ...(q.completed ? { completedAt: now } : {}),
            },
          });
          if (q.coins > 0) {
            await this.addLedger(tx, part.userId, q.coins, 'QUEST', `quest:${part.userId}:${day}:${q.key}`);
          }
        }
        if (planned.questBonusGranted) {
          const bonus = planned.questCoins - planned.quests.reduce((a, q) => a + q.coins, 0);
          await this.addLedger(tx, part.userId, bonus, 'QUEST_BONUS', `questbonus:${part.userId}:${day}`);
        }

        // (7) assemble
        awardsByUser.set(part.userId, {
          gameId: created.id,
          achievements: fresh,
          coins: planned.coins,
          ratingDelta: planned.ratingDelta,
          newRating: planned.newRating.rating,
          rated: planned.rated,
          quests: planned.quests,
          balance: await this.balance(tx, part.userId),
        });
      }
    });

    return awardsByUser;
  }

  // -------------------------------------------------------------------------
  // Meta profile / daily / quests
  // -------------------------------------------------------------------------

  async getMetaProfile(userId: string, now: Date = new Date()): Promise<MetaProfile> {
    const [user, wallet, rating, daily] = await Promise.all([
      this.prisma.user.findUnique({ where: { id: userId } }),
      this.prisma.wallet.findUnique({ where: { userId } }),
      this.prisma.rating.findUnique({ where: { userId } }),
      this.prisma.dailyState.findUnique({ where: { userId } }),
    ]);
    return {
      coins: wallet?.coins ?? 0,
      rating: rating?.rating ?? freshRating().rating,
      premium: user?.premium ?? false,
      dailyStreak: daily?.streak ?? 0,
      dailyClaimedToday: daily?.lastClaimDay === utcDayOf(now),
      selected: {
        cardBack: user?.selectedCardBack ?? DEFAULT_CARD_BACK,
        felt: user?.selectedFelt ?? DEFAULT_FELT,
      },
    };
  }

  async claimDaily(userId: string, now: Date = new Date()): Promise<DailyClaimResult> {
    const day = utcDayOf(now);
    return this.prisma.$transaction(async (tx) => {
      const state = await tx.dailyState.findUnique({ where: { userId } })
        ?? { lastClaimDay: null, streak: 0 };
      if (state.lastClaimDay === day) {
        return {
          claimed: false, day, streak: state.streak, coins: 0,
          balance: await this.balance(tx, userId), nextBonus: dailyBonusCoins(state.streak + 1),
        };
      }
      const streak = state.lastClaimDay === previousUtcDay(day) ? state.streak + 1 : 1;
      const coins = dailyBonusCoins(streak);
      if (!await this.addLedger(tx, userId, coins, 'DAILY_BONUS', `daily:${userId}:${day}`)) {
        return {
          claimed: false, day, streak: state.streak, coins: 0,
          balance: await this.balance(tx, userId), nextBonus: dailyBonusCoins(state.streak + 1),
        };
      }
      await tx.dailyState.upsert({
        where: { userId },
        update: { lastClaimDay: day, streak },
        create: { userId, lastClaimDay: day, streak },
      });
      return {
        claimed: true, day, streak, coins,
        balance: await this.balance(tx, userId), nextBonus: dailyBonusCoins(streak + 1),
      };
    });
  }

  async getQuestState(userId: string, now: Date = new Date()): Promise<QuestState> {
    const day = utcDayOf(now);
    const rows = await this.prisma.questProgress.findMany({ where: { userId, day } });
    return {
      day,
      quests: questsForDay(day).map((q) => {
        const progress = rows.find((r) => r.questKey === q.key)?.progress ?? 0;
        return { key: q.key, target: q.target, reward: questReward(q), progress, completed: progress >= q.target };
      }),
    };
  }

  // -------------------------------------------------------------------------
  // Cosmetics
  // -------------------------------------------------------------------------

  async getOwnedCosmetics(userId: string): Promise<OwnedCosmetics> {
    const [user, rows] = await Promise.all([
      this.prisma.user.findUnique({ where: { id: userId } }),
      this.prisma.cosmeticOwnership.findMany({ where: { userId } }),
    ]);
    const owned = new Set<string>([DEFAULT_CARD_BACK, DEFAULT_FELT, ...rows.map((r) => r.itemKey)]);
    return {
      owned: COSMETICS.filter((c) => owned.has(c.key)).map((c) => c.key),
      selected: {
        cardBack: user?.selectedCardBack ?? DEFAULT_CARD_BACK,
        felt: user?.selectedFelt ?? DEFAULT_FELT,
      },
    };
  }

  private async ownsCosmetic(tx: Tx, userId: string, key: string): Promise<boolean> {
    if (isImplicitlyOwned(key)) return true;
    return !!(await tx.cosmeticOwnership.findUnique({ where: { userId_itemKey: { userId, itemKey: key } } }));
  }

  async buyCosmetic(userId: string, itemKey: string): Promise<{ itemKey: string; balance: number }> {
    const def = COSMETICS_BY_KEY.get(itemKey);
    if (!def) throw new MetaError('UNKNOWN_ITEM');
    return this.prisma.$transaction(async (tx) => {
      if (await this.ownsCosmetic(tx, userId, itemKey)) throw new MetaError('ALREADY_OWNED');
      if (def.premiumOnly) {
        const user = await tx.user.findUnique({ where: { id: userId } });
        if (!user?.premium) throw new MetaError('PREMIUM_REQUIRED');
      }
      if (def.price > 0) {
        // Atomic conditional decrement — never lets the wallet go negative.
        const updated = await tx.wallet.updateMany({
          where: { userId, coins: { gte: def.price } },
          data: { coins: { decrement: def.price } },
        });
        if (updated.count === 0) throw new MetaError('INSUFFICIENT_FUNDS');
        await tx.coinLedger.create({
          data: {
            userId, delta: -def.price, reason: 'SHOP_PURCHASE',
            idempotencyKey: `shop:${userId}:${itemKey}`, meta: Prisma.JsonNull,
          },
        });
      }
      await tx.cosmeticOwnership.create({ data: { userId, itemKey } });
      return { itemKey, balance: await this.balance(tx, userId) };
    });
  }

  async selectCosmetics(userId: string, sel: { cardBack?: string | undefined; felt?: string | undefined }): Promise<{ cardBack: string; felt: string }> {
    return this.prisma.$transaction(async (tx) => {
      const data: Record<string, string> = {};
      if (sel.cardBack !== undefined) {
        const def = COSMETICS_BY_KEY.get(sel.cardBack);
        if (!def || def.kind !== 'cardBack' || !(await this.ownsCosmetic(tx, userId, sel.cardBack))) {
          throw new MetaError('NOT_OWNED');
        }
        data['selectedCardBack'] = sel.cardBack;
      }
      if (sel.felt !== undefined) {
        const def = COSMETICS_BY_KEY.get(sel.felt);
        if (!def || def.kind !== 'felt' || !(await this.ownsCosmetic(tx, userId, sel.felt))) {
          throw new MetaError('NOT_OWNED');
        }
        data['selectedFelt'] = sel.felt;
      }
      const user = await tx.user.update({ where: { id: userId }, data });
      return { cardBack: user.selectedCardBack, felt: user.selectedFelt };
    });
  }

  // -------------------------------------------------------------------------
  // Rewarded ads
  // -------------------------------------------------------------------------

  async adRemainingToday(userId: string, kind: 'shop' | 'double', now: Date = new Date()): Promise<number> {
    const cap = kind === 'shop' ? this.economy.adDailyCap : this.economy.adDoubleDailyCap;
    const used = await this.prisma.coinLedger.count({
      where: { userId, reason: kind === 'shop' ? 'AD_REWARD' : 'AD_DOUBLE', createdAt: { gte: dayStartUtc(now) } },
    });
    return Math.max(0, cap - used);
  }

  async grantAdReward(userId: string, grant: { jti: string; kind: 'shop' | 'double'; gameId?: string | undefined }, now: Date = new Date()): Promise<AdGrantResult> {
    return this.prisma.$transaction(async (tx) => {
      const cap = grant.kind === 'shop' ? this.economy.adDailyCap : this.economy.adDoubleDailyCap;
      const used = await this.countToday(tx, userId, grant.kind === 'shop' ? 'AD_REWARD' : 'AD_DOUBLE', now);
      const remaining = Math.max(0, cap - used);
      if (remaining <= 0) throw new MetaError('DAILY_CAP');

      if (grant.kind === 'shop') {
        if (!await this.addLedger(tx, userId, this.economy.adReward, 'AD_REWARD', `ad:${grant.jti}`)) {
          throw new MetaError('TOKEN_USED');
        }
        return { coins: this.economy.adReward, balance: await this.balance(tx, userId), remainingToday: remaining - 1 };
      }

      if (!grant.gameId) throw new MetaError('BAD_TOKEN');
      const gameAward = await tx.coinLedger.findUnique({
        where: { idempotencyKey: `game:${grant.gameId}:${userId}` },
      });
      if (!gameAward || gameAward.delta <= 0) throw new MetaError('BAD_TOKEN');
      if (!await this.addLedger(tx, userId, gameAward.delta, 'AD_DOUBLE', `double:${grant.gameId}:${userId}`)) {
        throw new MetaError('TOKEN_USED');
      }
      return { coins: gameAward.delta, balance: await this.balance(tx, userId), remainingToday: remaining - 1 };
    });
  }

  // -------------------------------------------------------------------------
  // IAP
  // -------------------------------------------------------------------------

  async applyIapPurchase(userId: string, purchase: { platform: 'google' | 'apple'; productId: string; orderId: string }): Promise<IapGrantResult> {
    const product = PRODUCTS[purchase.productId];
    if (!product) throw new MetaError('UNKNOWN_PRODUCT');
    return this.prisma.$transaction(async (tx) => {
      const existing = await tx.iapReceipt.findUnique({ where: { orderId: purchase.orderId } });
      if (existing) {
        if (existing.userId !== userId) throw new MetaError('RECEIPT_OWNED_BY_OTHER_USER');
        const user = await tx.user.findUnique({ where: { id: userId } });
        return {
          productId: product.id, granted: { coins: 0, premium: false },
          balance: await this.balance(tx, userId), premium: user?.premium ?? false, alreadyProcessed: true,
        };
      }

      await tx.iapReceipt.create({
        data: {
          userId, platform: purchase.platform, productId: product.id,
          orderId: purchase.orderId, status: 'GRANTED',
        },
      });
      if (product.coins > 0) {
        await this.addLedger(tx, userId, product.coins, 'IAP', `iap:${purchase.orderId}`, { productId: product.id });
      }
      let premium = false;
      if (product.premium) {
        await tx.user.update({ where: { id: userId }, data: { premium: true } });
        await tx.cosmeticOwnership.createMany({
          data: COSMETICS.filter((c) => c.premiumOnly).map((c) => ({ userId, itemKey: c.key })),
          skipDuplicates: true,
        });
        premium = true;
      } else {
        const user = await tx.user.findUnique({ where: { id: userId } });
        premium = user?.premium ?? false;
      }
      return {
        productId: product.id,
        granted: { coins: product.coins, premium: product.premium },
        balance: await this.balance(tx, userId),
        premium,
        alreadyProcessed: false,
      };
    });
  }

  // -------------------------------------------------------------------------
  // Leaderboards
  // -------------------------------------------------------------------------

  async getLeaderboard(scope: 'weekly' | 'alltime', limit: number, meUserId: string, now: Date = new Date()): Promise<LeaderboardPage> {
    if (scope === 'alltime') {
      const rows = await this.prisma.rating.findMany({
        orderBy: [{ rating: 'desc' }, { userId: 'asc' }],
        take: limit,
        include: { user: true },
      });
      const entries = rows.map((r, i) => ({
        rank: i + 1, userId: r.userId, nickname: r.user.nickname, avatar: r.user.avatar,
        value: r.rating, gamesRated: r.gamesRated,
      }));
      const mine = await this.prisma.rating.findUnique({ where: { userId: meUserId } });
      const me = mine
        ? {
            rank: (await this.prisma.rating.count({ where: { rating: { gt: mine.rating } } })) + 1,
            value: mine.rating, gamesRated: mine.gamesRated,
          }
        : null;
      return { scope, entries, me };
    }

    const seasonKey = seasonKeyFor(now);
    const rows = await this.prisma.seasonScore.findMany({
      where: { seasonKey },
      orderBy: [{ points: 'desc' }, { userId: 'asc' }],
      take: limit,
      include: { user: true },
    });
    const entries = rows.map((r, i) => ({
      rank: i + 1, userId: r.userId, nickname: r.user.nickname, avatar: r.user.avatar,
      value: r.points, gamesRated: r.gamesRated,
    }));
    const mine = await this.prisma.seasonScore.findUnique({
      where: { seasonKey_userId: { seasonKey, userId: meUserId } },
    });
    const me = mine
      ? {
          rank: (await this.prisma.seasonScore.count({ where: { seasonKey, points: { gt: mine.points } } })) + 1,
          value: mine.points, gamesRated: mine.gamesRated,
        }
      : null;
    return { scope, seasonKey, entries, me };
  }

  // -------------------------------------------------------------------------
  // Account deletion
  // -------------------------------------------------------------------------

  async deleteUser(userId: string): Promise<void> {
    // Relations declare onDelete: Cascade for the new models; Identity/PlayerStats/
    // UserAchievement predate that, so clear them explicitly in one transaction.
    await this.prisma.$transaction([
      this.prisma.identity.deleteMany({ where: { userId } }),
      this.prisma.playerStats.deleteMany({ where: { userId } }),
      this.prisma.userAchievement.deleteMany({ where: { userId } }),
      this.prisma.wallet.deleteMany({ where: { userId } }),
      this.prisma.coinLedger.deleteMany({ where: { userId } }),
      this.prisma.rating.deleteMany({ where: { userId } }),
      this.prisma.seasonScore.deleteMany({ where: { userId } }),
      this.prisma.dailyState.deleteMany({ where: { userId } }),
      this.prisma.questProgress.deleteMany({ where: { userId } }),
      this.prisma.cosmeticOwnership.deleteMany({ where: { userId } }),
      this.prisma.iapReceipt.deleteMany({ where: { userId } }),
      this.prisma.user.deleteMany({ where: { id: userId } }),
    ]);
  }
}
