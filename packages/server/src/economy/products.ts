/**
 * IAP product catalog. Store prices live in the store consoles; the server
 * only needs the grant per product id.
 */

export interface ProductDef {
  id: string;
  /** 'consumable' grants coins; 'nonconsumable' flips a flag. */
  kind: 'consumable' | 'nonconsumable';
  coins: number;
  premium: boolean;
}

export const PRODUCTS: Record<string, ProductDef> = {
  coins_small: { id: 'coins_small', kind: 'consumable', coins: 500, premium: false },
  coins_medium: { id: 'coins_medium', kind: 'consumable', coins: 1800, premium: false },
  coins_large: { id: 'coins_large', kind: 'consumable', coins: 4800, premium: false },
  coins_huge: { id: 'coins_huge', kind: 'consumable', coins: 12000, premium: false },
  premium_upgrade: { id: 'premium_upgrade', kind: 'nonconsumable', coins: 0, premium: true },
};
