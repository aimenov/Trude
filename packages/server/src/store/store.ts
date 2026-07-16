import { randomUUID } from 'node:crypto';
import type { PlayerGameStats } from '@trude/engine';
import { applyGameToLifetime, evaluateUnlocks } from './shared.js';

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
  participants: { userId: string; placement: number; stats: PlayerGameStats }[];
}

export interface UnlockedAchievement { key: string; title: string; description: string; }

export interface Store {
  upsertGuest(deviceId: string, nickname: string, avatar: string): Promise<UserRecord>;
  getUser(id: string): Promise<UserRecord | null>;
  updateProfile(id: string, patch: { nickname?: string | undefined; avatar?: string | undefined }): Promise<UserRecord>;
  getStats(id: string): Promise<LifetimeStats>;
  getAchievements(id: string): Promise<{ key: string; unlockedAt: number }[]>;
  /** Applies a finished game transactionally; returns newly unlocked achievements per user. */
  recordGameResult(result: GameResultInput): Promise<Map<string, UnlockedAchievement[]>>;
}

export function freshLifetime(): LifetimeStats {
  return {
    gamesPlayed: 0, gamesWon: 0, gamesLost: 0, winStreak: 0, bestWinStreak: 0,
    liesSurvived: 0, liesCaught: 0, checksWon: 0, checksLost: 0, cardsPickedUp: 0,
    quadsDiscarded: 0, jokerPassed: 0, jokerSmuggles: 0, truthfulThrows: 0, lyingThrows: 0,
  };
}

/**
 * In-memory store — the dev/test default. The Prisma/Postgres implementation
 * (deployment milestone) implements the same interface; game code never sees the difference.
 */
export class MemoryStore implements Store {
  private users = new Map<string, UserRecord>();
  private byDevice = new Map<string, string>();
  private stats = new Map<string, LifetimeStats>();
  private achievements = new Map<string, Map<string, number>>();

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

  async recordGameResult(result: GameResultInput): Promise<Map<string, UnlockedAchievement[]>> {
    const unlockedByUser = new Map<string, UnlockedAchievement[]>();
    if (result.status !== 'FINISHED') return unlockedByUser;

    for (const part of result.participants) {
      const outcome = { won: part.placement === 1, lost: part.userId === result.loserUserId };
      const s = applyGameToLifetime(this.stats.get(part.userId) ?? freshLifetime(), part.stats, outcome);
      this.stats.set(part.userId, s);

      const mine = this.achievements.get(part.userId) ?? new Map<string, number>();
      this.achievements.set(part.userId, mine);
      const fresh = evaluateUnlocks(s, part.stats, outcome, new Set(mine.keys()));
      for (const a of fresh) mine.set(a.key, Date.now());
      if (fresh.length) unlockedByUser.set(part.userId, fresh);
    }
    return unlockedByUser;
  }
}
