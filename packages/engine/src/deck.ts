import { RANK_ORDER, SUITS } from './types.js';
import type { Card, DeckSize, Rank, RngState, Suit } from './types.js';
import { randInt } from './rng.js';

export function ranksForDeck(deckSize: DeckSize): Rank[] {
  return deckSize === 53 ? [...RANK_ORDER] : RANK_ORDER.slice(RANK_ORDER.indexOf('6'));
}

/**
 * Builds and shuffles the deck. Card ids are assigned AFTER the shuffle so an id
 * carries no information about rank or suit.
 */
export function buildShuffledDeck(deckSize: DeckSize, rng: RngState): Card[] {
  const faces: { rank: Rank | 'JOKER'; suit?: Suit }[] = [];
  for (const rank of ranksForDeck(deckSize)) {
    for (const suit of SUITS) faces.push({ rank, suit });
  }
  faces.push({ rank: 'JOKER' });

  // Fisher–Yates
  for (let i = faces.length - 1; i > 0; i--) {
    const j = randInt(rng, i + 1);
    const tmp = faces[i]!;
    faces[i] = faces[j]!;
    faces[j] = tmp;
  }

  return faces.map((f, i) =>
    f.suit !== undefined ? { id: `c${i}`, rank: f.rank, suit: f.suit } : { id: `c${i}`, rank: f.rank },
  );
}
