import type { Request } from 'express';
import { verifyToken } from './jwt.js';
import type { AuthClaims } from './jwt.js';

/** Parses and verifies the Authorization: Bearer header; null when absent/invalid. */
export function bearer(req: Request): AuthClaims | null {
  const header = req.headers.authorization;
  if (!header?.startsWith('Bearer ')) return null;
  try {
    return verifyToken(header.slice(7));
  } catch {
    return null;
  }
}
