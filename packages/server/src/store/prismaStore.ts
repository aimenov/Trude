import { PrismaClient } from '@prisma/client';
import { applyGameToLifetime, evaluateUnlocks } from './shared.js';
import { freshLifetime } from './store.js';
import type {
  GameResultInput, LifetimeStats, Store, UnlockedAchievement, UserRecord,
} from './store.js';

/** Postgres-backed store. Selected when DATABASE_URL is set (see index.ts). */
export class PrismaStore implements Store {
  private prisma: PrismaClient;

  constructor(prisma?: PrismaClient) {
    this.prisma = prisma ?? new PrismaClient();
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

  async recordGameResult(result: GameResultInput): Promise<Map<string, UnlockedAchievement[]>> {
    const unlockedByUser = new Map<string, UnlockedAchievement[]>();

    await this.prisma.$transaction(async (tx) => {
      await tx.gameResult.create({
        data: {
          roomId: result.roomId,
          deckSize: result.deckSize,
          status: result.status,
          loserUserId: result.loserUserId,
          participants: result.participants.map((p) => ({ userId: p.userId, placement: p.placement })),
        },
      });
      if (result.status !== 'FINISHED') return;

      for (const part of result.participants) {
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
          unlockedByUser.set(part.userId, fresh);
        }
      }
    });

    return unlockedByUser;
  }
}
