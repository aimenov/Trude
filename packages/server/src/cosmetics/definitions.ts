/**
 * Cosmetics catalog v1. Key namespaces: `cb_*` (card backs), `felt_*` (table
 * felts). Defaults are price 0 and implicitly owned by everyone. The client
 * holds the matching visual styles keyed by these ids.
 */

export type CosmeticKind = 'cardBack' | 'felt';

export interface CosmeticDef {
  key: string;
  kind: CosmeticKind;
  price: number;
  premiumOnly: boolean;
}

export const DEFAULT_CARD_BACK = 'cb_classic';
export const DEFAULT_FELT = 'felt_classic';

export const COSMETICS: CosmeticDef[] = [
  { key: 'cb_classic', kind: 'cardBack', price: 0, premiumOnly: false },
  { key: 'cb_crimson', kind: 'cardBack', price: 300, premiumOnly: false },
  { key: 'cb_noir', kind: 'cardBack', price: 300, premiumOnly: false },
  { key: 'cb_royal', kind: 'cardBack', price: 800, premiumOnly: false },
  { key: 'cb_imperial', kind: 'cardBack', price: 2000, premiumOnly: false },
  { key: 'cb_gilded', kind: 'cardBack', price: 0, premiumOnly: true },
  { key: 'felt_classic', kind: 'felt', price: 0, premiumOnly: false },
  { key: 'felt_burgundy', kind: 'felt', price: 400, premiumOnly: false },
  { key: 'felt_navy', kind: 'felt', price: 400, premiumOnly: false },
  { key: 'felt_midnight', kind: 'felt', price: 1000, premiumOnly: false },
];

export const COSMETICS_BY_KEY = new Map(COSMETICS.map((c) => [c.key, c]));

/** Defaults every user owns without a purchase or ownership row. */
export const IMPLICITLY_OWNED = [DEFAULT_CARD_BACK, DEFAULT_FELT] as const;

export function isImplicitlyOwned(key: string): boolean {
  return (IMPLICITLY_OWNED as readonly string[]).includes(key);
}
