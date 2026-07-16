import type { RngState } from './types.js';

/** xmur3 string hash — expands a seed string into 32-bit chunks. */
function xmur3(str: string): () => number {
  let h = 1779033703 ^ str.length;
  for (let i = 0; i < str.length; i++) {
    h = Math.imul(h ^ str.charCodeAt(i), 3432918353);
    h = (h << 13) | (h >>> 19);
  }
  return () => {
    h = Math.imul(h ^ (h >>> 16), 2246822507);
    h = Math.imul(h ^ (h >>> 13), 3266489909);
    h ^= h >>> 16;
    return h >>> 0;
  };
}

export function seedRng(seed: string): RngState {
  const next = xmur3(seed);
  return [next(), next(), next(), next()];
}

/** sfc32 — advances the state in place and returns a uint32. */
export function nextU32(s: RngState): number {
  let [a, b, c, d] = s;
  a >>>= 0; b >>>= 0; c >>>= 0; d >>>= 0;
  const t = (a + b) | 0;
  a = b ^ (b >>> 9);
  b = (c + (c << 3)) | 0;
  c = (c << 21) | (c >>> 11);
  d = (d + 1) | 0;
  const out = (t + d) | 0;
  c = (c + out) | 0;
  s[0] = a >>> 0; s[1] = b >>> 0; s[2] = c >>> 0; s[3] = d >>> 0;
  return out >>> 0;
}

/** Uniform integer in [0, n) with rejection sampling (no modulo bias). */
export function randInt(s: RngState, n: number): number {
  if (n <= 0) throw new Error('randInt: n must be > 0');
  const limit = Math.floor(0x100000000 / n) * n;
  let v = nextU32(s);
  while (v >= limit) v = nextU32(s);
  return v % n;
}

/** True with probability pct/100. */
export function chance(s: RngState, pct: number): boolean {
  return randInt(s, 100) < pct;
}
