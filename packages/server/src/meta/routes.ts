import { Router } from 'express';
import type { Request, Response } from 'express';
import { z } from 'zod';
import { bearer } from '../auth/bearer.js';
import { COSMETICS } from '../cosmetics/definitions.js';
import { MetaError } from '../store/store.js';
import type { Store } from '../store/store.js';
import type { AdRewardVerifier } from '../ads/verifier.js';
import type { PurchaseValidator } from '../iap/validator.js';

/** MetaError code → HTTP status. Unknown codes fall through to 500. */
const STATUS_BY_CODE: Record<string, number> = {
  UNKNOWN_ITEM: 404,
  ALREADY_OWNED: 409,
  INSUFFICIENT_FUNDS: 402,
  PREMIUM_REQUIRED: 403,
  NOT_OWNED: 403,
  BAD_TOKEN: 401,
  TOKEN_USED: 409,
  DAILY_CAP: 429,
  UNKNOWN_PRODUCT: 404,
  RECEIPT_OWNED_BY_OTHER_USER: 409,
  INVALID_RECEIPT: 400,
};

function sendMetaError(res: Response, e: unknown): void {
  if (e instanceof MetaError) {
    res.status(STATUS_BY_CODE[e.code] ?? 500).json({ error: e.code });
    return;
  }
  console.error('meta route failure', e);
  res.status(500).json({ error: 'INTERNAL' });
}

const leaderboardQuery = z.object({
  scope: z.enum(['weekly', 'alltime']).default('alltime'),
  limit: z.coerce.number().int().min(1).max(100).default(50),
});

const buyBody = z.object({ itemKey: z.string().min(1).max(64) });

const adsTokenQuery = z.object({
  kind: z.enum(['shop', 'double']),
  gameId: z.string().min(1).max(64).optional(),
});

const adsRewardBody = z.object({ token: z.string().min(1) });

const iapGoogleBody = z.object({
  purchaseToken: z.string().min(1).max(4096),
  productId: z.string().min(1).max(128),
});

const iapAppleBody = z.object({ receipt: z.string().min(1).max(65536) });

export function metaRoutes(store: Store, ads: AdRewardVerifier, iap: PurchaseValidator): Router {
  const router = Router();

  // ---- Leaderboard ---------------------------------------------------------

  router.get('/leaderboard', async (req: Request, res: Response) => {
    const claims = bearer(req);
    if (!claims) return res.status(401).json({ error: 'UNAUTHORIZED' });
    const q = leaderboardQuery.safeParse(req.query);
    if (!q.success) return res.status(400).json({ error: 'BAD_QUERY' });
    const page = await store.getLeaderboard(q.data.scope, q.data.limit, claims.sub);
    return res.json(page);
  });

  // ---- Daily bonus + quests ------------------------------------------------

  router.post('/me/daily/claim', async (req: Request, res: Response) => {
    const claims = bearer(req);
    if (!claims) return res.status(401).json({ error: 'UNAUTHORIZED' });
    return res.json(await store.claimDaily(claims.sub)); // idempotent, always 200
  });

  router.get('/me/quests', async (req: Request, res: Response) => {
    const claims = bearer(req);
    if (!claims) return res.status(401).json({ error: 'UNAUTHORIZED' });
    return res.json(await store.getQuestState(claims.sub));
  });

  // ---- Cosmetics -----------------------------------------------------------

  router.get('/catalog/cosmetics', (_req: Request, res: Response) => res.json({
    items: COSMETICS.map((c) => ({ key: c.key, kind: c.kind, price: c.price, premiumOnly: c.premiumOnly })),
  }));

  router.get('/me/cosmetics', async (req: Request, res: Response) => {
    const claims = bearer(req);
    if (!claims) return res.status(401).json({ error: 'UNAUTHORIZED' });
    return res.json(await store.getOwnedCosmetics(claims.sub));
  });

  router.post('/shop/buy', async (req: Request, res: Response) => {
    const claims = bearer(req);
    if (!claims) return res.status(401).json({ error: 'UNAUTHORIZED' });
    const body = buyBody.safeParse(req.body);
    if (!body.success) return res.status(400).json({ error: 'BAD_BODY' });
    try {
      return res.json(await store.buyCosmetic(claims.sub, body.data.itemKey));
    } catch (e) {
      return sendMetaError(res, e);
    }
  });

  // ---- Rewarded ads --------------------------------------------------------

  router.get('/ads/token', async (req: Request, res: Response) => {
    const claims = bearer(req);
    if (!claims) return res.status(401).json({ error: 'UNAUTHORIZED' });
    const q = adsTokenQuery.safeParse(req.query);
    if (!q.success) return res.status(400).json({ error: 'BAD_QUERY' });
    if (q.data.kind === 'double' && !q.data.gameId) return res.status(400).json({ error: 'BAD_QUERY' });
    const { token } = ads.issueToken(claims.sub, q.data.kind, q.data.gameId);
    const remainingToday = await store.adRemainingToday(claims.sub, q.data.kind);
    return res.json({ token, remainingToday });
  });

  router.post('/ads/reward', async (req: Request, res: Response) => {
    const claims = bearer(req);
    if (!claims) return res.status(401).json({ error: 'UNAUTHORIZED' });
    const body = adsRewardBody.safeParse(req.body);
    if (!body.success) return res.status(400).json({ error: 'BAD_BODY' });
    const tokenClaims = ads.verify(body.data.token, claims.sub);
    if (!tokenClaims) return res.status(401).json({ error: 'BAD_TOKEN' });
    try {
      return res.json(await store.grantAdReward(claims.sub, tokenClaims));
    } catch (e) {
      return sendMetaError(res, e);
    }
  });

  // ---- IAP -----------------------------------------------------------------

  router.post('/iap/google', async (req: Request, res: Response) => {
    const claims = bearer(req);
    if (!claims) return res.status(401).json({ error: 'UNAUTHORIZED' });
    const body = iapGoogleBody.safeParse(req.body);
    if (!body.success) return res.status(400).json({ error: 'BAD_BODY' });
    const valid = await iap.validateGoogle(body.data.purchaseToken, body.data.productId);
    if (!valid) return res.status(400).json({ error: 'INVALID_RECEIPT' });
    try {
      return res.json(await store.applyIapPurchase(claims.sub, {
        platform: 'google', productId: valid.productId, orderId: valid.orderId,
      }));
    } catch (e) {
      return sendMetaError(res, e);
    }
  });

  router.post('/iap/apple', async (req: Request, res: Response) => {
    const claims = bearer(req);
    if (!claims) return res.status(401).json({ error: 'UNAUTHORIZED' });
    const body = iapAppleBody.safeParse(req.body);
    if (!body.success) return res.status(400).json({ error: 'BAD_BODY' });
    const valid = await iap.validateApple(body.data.receipt);
    if (!valid) return res.status(400).json({ error: 'INVALID_RECEIPT' });
    try {
      return res.json(await store.applyIapPurchase(claims.sub, {
        platform: 'apple', productId: valid.productId, orderId: valid.orderId,
      }));
    } catch (e) {
      return sendMetaError(res, e);
    }
  });

  // ---- Account deletion ----------------------------------------------------

  router.delete('/me', async (req: Request, res: Response) => {
    const claims = bearer(req);
    if (!claims) return res.status(401).json({ error: 'UNAUTHORIZED' });
    await store.deleteUser(claims.sub);
    return res.status(204).end();
  });

  return router;
}
