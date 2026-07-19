import { Router } from 'express';
import type { Request, Response } from 'express';
import { z } from 'zod';
import { ACHIEVEMENTS } from '../achievements/definitions.js';
import { MetaError } from '../store/store.js';
import type { Store } from '../store/store.js';
import { bearer } from './bearer.js';
import { signToken } from './jwt.js';

// Minimal launch list; extend per locale. Checked as substrings, lowercase.
const PROFANITY = ['fuck', 'shit', 'cunt', 'nigg', 'хуй', 'пизд', 'ебан', 'ебат', 'блядь', 'сука'];

export function isCleanNickname(nickname: string): boolean {
  const lower = nickname.toLowerCase();
  return !PROFANITY.some((w) => lower.includes(w));
}

const guestBody = z.object({
  deviceId: z.string().min(8).max(128),
  nickname: z.string().min(2).max(16),
  avatar: z.string().min(1).max(8).optional(),
});

const patchMeBody = z.object({
  nickname: z.string().min(2).max(16).optional(),
  avatar: z.string().min(1).max(8).optional(),
  selectedCardBack: z.string().min(1).max(64).optional(),
  selectedFelt: z.string().min(1).max(64).optional(),
});

export function authRoutes(store: Store): Router {
  const router = Router();

  router.post('/auth/guest', async (req: Request, res: Response) => {
    const body = guestBody.safeParse(req.body);
    if (!body.success) return res.status(400).json({ error: 'BAD_BODY' });
    if (!isCleanNickname(body.data.nickname)) return res.status(400).json({ error: 'BAD_NICKNAME' });
    const user = await store.upsertGuest(body.data.deviceId, body.data.nickname, body.data.avatar ?? 'a0');
    const token = signToken({ sub: user.id, nick: user.nickname, avatar: user.avatar, guest: true });
    return res.json({ token, userId: user.id, nickname: user.nickname, avatar: user.avatar });
  });

  router.post('/auth/refresh', async (req: Request, res: Response) => {
    const claims = bearer(req);
    if (!claims) return res.status(401).json({ error: 'UNAUTHORIZED' });
    const user = await store.getUser(claims.sub);
    if (!user) return res.status(401).json({ error: 'UNAUTHORIZED' });
    const token = signToken({ sub: user.id, nick: user.nickname, avatar: user.avatar, guest: claims.guest });
    return res.json({ token });
  });

  // Google/Apple identity linking ships in the meta milestone.
  router.post('/auth/google', (_req: Request, res: Response) => res.status(501).json({ error: 'NOT_IMPLEMENTED' }));
  router.post('/auth/apple', (_req: Request, res: Response) => res.status(501).json({ error: 'NOT_IMPLEMENTED' }));

  router.get('/me', async (req: Request, res: Response) => {
    const claims = bearer(req);
    if (!claims) return res.status(401).json({ error: 'UNAUTHORIZED' });
    const user = await store.getUser(claims.sub);
    if (!user) return res.status(404).json({ error: 'NOT_FOUND' });
    const [stats, meta] = await Promise.all([store.getStats(user.id), store.getMetaProfile(user.id)]);
    return res.json({
      userId: user.id, nickname: user.nickname, avatar: user.avatar, stats,
      coins: meta.coins, rating: meta.rating, premium: meta.premium,
      dailyStreak: meta.dailyStreak, dailyClaimedToday: meta.dailyClaimedToday,
      selected: meta.selected,
    });
  });

  router.patch('/me', async (req: Request, res: Response) => {
    const claims = bearer(req);
    if (!claims) return res.status(401).json({ error: 'UNAUTHORIZED' });
    const body = patchMeBody.safeParse(req.body);
    if (!body.success) return res.status(400).json({ error: 'BAD_BODY' });
    if (body.data.nickname !== undefined && !isCleanNickname(body.data.nickname)) {
      return res.status(400).json({ error: 'BAD_NICKNAME' });
    }
    const user = await store.updateProfile(claims.sub, {
      nickname: body.data.nickname, avatar: body.data.avatar,
    });
    let selected;
    try {
      selected = (body.data.selectedCardBack !== undefined || body.data.selectedFelt !== undefined)
        ? await store.selectCosmetics(claims.sub, {
            cardBack: body.data.selectedCardBack, felt: body.data.selectedFelt,
          })
        : (await store.getMetaProfile(claims.sub)).selected;
    } catch (e) {
      if (e instanceof MetaError && e.code === 'NOT_OWNED') return res.status(403).json({ error: 'NOT_OWNED' });
      throw e;
    }
    return res.json({ userId: user.id, nickname: user.nickname, avatar: user.avatar, selected });
  });

  router.get('/me/achievements', async (req: Request, res: Response) => {
    const claims = bearer(req);
    if (!claims) return res.status(401).json({ error: 'UNAUTHORIZED' });
    const unlocked = await store.getAchievements(claims.sub);
    return res.json({
      unlocked,
      catalog: ACHIEVEMENTS.map((a) => ({ key: a.key, title: a.title, description: a.description })),
    });
  });

  return router;
}
