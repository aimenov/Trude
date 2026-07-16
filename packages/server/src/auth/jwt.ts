import jwt from 'jsonwebtoken';
import { config } from '../config.js';

export interface AuthClaims {
  sub: string;       // userId
  nick: string;
  avatar: string;
  guest: boolean;
}

export function signToken(claims: AuthClaims): string {
  return jwt.sign(claims, config.jwtSecret, { algorithm: 'HS256', expiresIn: config.tokenTtl });
}

export function verifyToken(token: string): AuthClaims {
  const decoded = jwt.verify(token, config.jwtSecret, { algorithms: ['HS256'] });
  if (typeof decoded === 'string') throw new Error('Bad token payload');
  const { sub, nick, avatar, guest } = decoded as Record<string, unknown>;
  if (typeof sub !== 'string' || typeof nick !== 'string') throw new Error('Bad token payload');
  return { sub, nick, avatar: typeof avatar === 'string' ? avatar : 'a0', guest: guest === true };
}
