import { mkdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { nameableRanks, projectFor, reduce, seedRng } from '../src/index.js';
import type { DeckSize, GameState } from '../src/index.js';
import { newGame, randomLegalAction } from './helpers.js';

/**
 * Exports golden legality fixtures consumed by the Dart client's mirrored rule
 * predicates (app/test). Deterministic: same seeds -> byte-identical fixtures.
 * Each fixture is the actor's redacted view plus the legality facts the client
 * must derive from it.
 */
const OUT_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', 'fixtures', 'legality');

interface Fixture {
  name: string;
  view: unknown;                       // GameView for the current actor
  expected: {
    phase: 'lead' | 'respond';
    mustCheck: boolean;
    canTrust: boolean;
    nameableRanks: string[];
    maxThrowCount: number;             // min(3, own hand size)
    lastThrowCount: number;            // flippable cards in the last group
  };
}

function fixtureFrom(state: GameState, name: string): Fixture | null {
  const phase = state.phase;
  if (phase.kind === 'over') return null;
  const view = projectFor(state, phase.seat);
  const last = state.pile[state.pile.length - 1];
  return {
    name,
    view,
    expected: {
      phase: phase.kind,
      mustCheck: phase.kind === 'respond' && phase.mustCheck,
      canTrust: phase.kind === 'respond' && !phase.mustCheck,
      nameableRanks: nameableRanks(state),
      maxThrowCount: Math.min(3, state.players[phase.seat]!.hand.length),
      lastThrowCount: last ? last.cards.length : 0,
    },
  };
}

describe('golden legality fixtures', () => {
  it('exports deterministic fixtures for the Dart mirror', () => {
    const fixtures: Fixture[] = [];
    const configs: { deckSize: DeckSize; players: number; seed: string }[] = [
      { deckSize: 37, players: 2, seed: 'golden-a' },
      { deckSize: 37, players: 4, seed: 'golden-b' },
      { deckSize: 53, players: 3, seed: 'golden-c' },
      { deckSize: 53, players: 6, seed: 'golden-d' },
    ];

    for (const cfg of configs) {
      let { state } = newGame(cfg.players, cfg.deckSize, cfg.seed);
      const rng = seedRng(`golden-driver:${cfg.seed}`);
      let sampled = 0;
      let mustCheckSampled = false;
      for (let step = 0; step < 400 && state.phase.kind !== 'over'; step++) {
        const isMustCheck = state.phase.kind === 'respond' && state.phase.mustCheck;
        const wantSample = step % 17 === 0 || (isMustCheck && !mustCheckSampled);
        if (wantSample && sampled < 8) {
          const f = fixtureFrom(state, `${cfg.seed}-step${step}`);
          if (f) {
            fixtures.push(f);
            sampled++;
            if (isMustCheck) mustCheckSampled = true;
          }
        }
        const r = reduce(state, randomLegalAction(state, rng));
        if (!r.ok) throw new Error(r.error.code);
        state = r.state;
      }
    }

    expect(fixtures.length).toBeGreaterThanOrEqual(20);
    // The suite must exercise both decision kinds and the forced check.
    expect(fixtures.some((f) => f.expected.phase === 'lead')).toBe(true);
    expect(fixtures.some((f) => f.expected.canTrust)).toBe(true);
    expect(fixtures.some((f) => f.expected.mustCheck)).toBe(true);

    mkdirSync(OUT_DIR, { recursive: true });
    writeFileSync(join(OUT_DIR, 'fixtures.json'), JSON.stringify(fixtures, null, 2));
  });
});
