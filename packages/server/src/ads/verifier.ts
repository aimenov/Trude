import { randomUUID } from 'node:crypto';
import jwt from 'jsonwebtoken';
import { config } from '../config.js';

export interface AdTokenClaims {
  jti: string;
  kind: 'shop' | 'double';
  gameId?: string | undefined;
}

/**
 * Issues and verifies single-use rewarded-ad tokens. The own-JWT implementation
 * ships now; an AdMob SSV callback verifier can replace it later without
 * touching the ledger logic (single-use stays enforced by ledger keys).
 */
export interface AdRewardVerifier {
  issueToken(userId: string, kind: 'shop' | 'double', gameId?: string): { token: string };
  /** Returns the claims when the token is valid and belongs to userId; null otherwise. */
  verify(token: string, userId: string): AdTokenClaims | null;
}

interface AdJwtPayload {
  sub: string;
  jti: string;
  kind: string;
  gameId?: string;
  aud: string;
}

const AUDIENCE = 'trude-ads';

export class OwnJwtAdVerifier implements AdRewardVerifier {
  issueToken(userId: string, kind: 'shop' | 'double', gameId?: string): { token: string } {
    const payload: Omit<AdJwtPayload, 'aud'> = { sub: userId, jti: randomUUID(), kind };
    if (gameId !== undefined) payload.gameId = gameId;
    const token = jwt.sign(payload, config.jwtSecret, {
      algorithm: 'HS256', expiresIn: config.economy.adTokenTtlSec, audience: AUDIENCE,
    });
    return { token };
  }

  verify(token: string, userId: string): AdTokenClaims | null {
    try {
      const decoded = jwt.verify(token, config.jwtSecret, { algorithms: ['HS256'], audience: AUDIENCE });
      if (typeof decoded === 'string') return null;
      const { sub, jti, kind, gameId } = decoded as unknown as AdJwtPayload;
      if (sub !== userId || typeof jti !== 'string') return null;
      if (kind !== 'shop' && kind !== 'double') return null;
      return { jti, kind, gameId: typeof gameId === 'string' ? gameId : undefined };
    } catch {
      return null;
    }
  }
}
