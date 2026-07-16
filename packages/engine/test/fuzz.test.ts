import { describe, expect, it } from 'vitest';
import type { DeckSize } from '../src/index.js';
import { playRandomGame } from './helpers.js';

/**
 * Full random games across both decks and all player counts. Invariants are
 * asserted after every action inside playRandomGame; here we additionally check
 * termination and the end condition. Nightly CI can raise GAMES_PER_CONFIG.
 */
const GAMES_PER_CONFIG = Number(process.env['FUZZ_GAMES'] ?? 12);

const CONFIGS: { deckSize: DeckSize; players: number }[] = [
  { deckSize: 37, players: 2 }, { deckSize: 37, players: 3 }, { deckSize: 37, players: 4 },
  { deckSize: 37, players: 5 }, { deckSize: 37, players: 6 },
  { deckSize: 53, players: 2 }, { deckSize: 53, players: 3 }, { deckSize: 53, players: 4 },
  { deckSize: 53, players: 5 }, { deckSize: 53, players: 6 }, { deckSize: 53, players: 7 },
  { deckSize: 53, players: 8 },
];

describe('fuzzer', () => {
  for (const { deckSize, players } of CONFIGS) {
    it(`plays ${GAMES_PER_CONFIG} clean games: ${players}p / ${deckSize} cards`, () => {
      const turnCounts: number[] = [];
      for (let i = 0; i < GAMES_PER_CONFIG; i++) {
        const { state, steps } = playRandomGame(players, deckSize, `fuzz-${deckSize}-${players}-${i}`);
        turnCounts.push(steps);
        const phase = state.phase;
        expect(phase.kind).toBe('over');
        if (phase.kind !== 'over') continue;
        // The loser holds the joker; every other player is out and placed.
        expect(state.players[phase.loserSeat]!.hand.some((c) => c.rank === 'JOKER')).toBe(true);
        expect(state.outOrder).toHaveLength(players - 1);
      }
      // Telemetry guard from the design review: flag pathological stalls.
      const max = Math.max(...turnCounts);
      expect(max).toBeLessThan(5000);
    });
  }
});
