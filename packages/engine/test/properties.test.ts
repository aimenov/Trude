import fc from 'fast-check';
import { describe, expect, it } from 'vitest';
import { assertInvariants, projectFor, reduce, seedRng } from '../src/index.js';
import type { DeckSize, EngineAction, GameState } from '../src/index.js';
import { newGame, randomLegalAction } from './helpers.js';

const arbConfig = fc.record({
  deckSize: fc.constantFrom<DeckSize>(37, 53),
  players: fc.integer({ min: 2, max: 6 }),
  seed: fc.string({ minLength: 1, maxLength: 12 }),
  driverSeed: fc.string({ minLength: 1, maxLength: 12 }),
  steps: fc.integer({ min: 1, max: 120 }),
});

interface TrajectoryConfig {
  deckSize: DeckSize; players: number; seed: string; driverSeed: string; steps: number;
}

/** Plays `steps` random legal moves (stops early at game over); returns every intermediate state. */
function trajectory(cfg: TrajectoryConfig): { states: GameState[]; actions: EngineAction[] } {
  const { state: initial } = newGame(cfg.players, cfg.deckSize, cfg.seed);
  const rng = seedRng(cfg.driverSeed);
  const states = [initial];
  const actions: EngineAction[] = [];
  let state = initial;
  for (let i = 0; i < cfg.steps && state.phase.kind !== 'over'; i++) {
    const action = randomLegalAction(state, rng);
    const r = reduce(state, action);
    if (!r.ok) throw new Error(`generator produced illegal action: ${r.error.code}`);
    state = r.state;
    states.push(state);
    actions.push(action);
  }
  return { states, actions };
}

describe('properties', () => {
  it('invariants hold along every random legal trajectory', () => {
    fc.assert(
      fc.property(arbConfig, (cfg) => {
        for (const s of trajectory(cfg).states) assertInvariants(s);
      }),
      { numRuns: 60 },
    );
  });

  it('replaying the same seed and action log reproduces the state bit-for-bit', () => {
    fc.assert(
      fc.property(arbConfig, (cfg) => {
        const a = trajectory(cfg);
        const { state: initial } = newGame(cfg.players, cfg.deckSize, cfg.seed);
        let replayed = initial;
        for (const action of a.actions) {
          const r = reduce(replayed, action);
          if (!r.ok) throw new Error('replay diverged: action became illegal');
          replayed = r.state;
        }
        expect(replayed).toEqual(a.states[a.states.length - 1]);
      }),
      { numRuns: 30 },
    );
  });

  it('projections never leak another player\'s card faces or face-down pile cards', () => {
    fc.assert(
      fc.property(arbConfig, (cfg) => {
        for (const state of trajectory(cfg).states) {
          for (const viewer of [...state.players.map((p) => p.seat), null]) {
            const view = projectFor(state, viewer);
            const visibleIds = new Set([
              ...view.hand.map((c) => c.id),
              ...view.discarded.map((c) => c.id),
            ]);
            const serialized = JSON.stringify({ ...view, hand: [], discarded: [] });
            // No card id outside the viewer's own hand / public discard may appear anywhere.
            for (const p of state.players) {
              for (const c of p.hand) {
                if (!visibleIds.has(c.id)) expect(serialized).not.toContain(`"${c.id}"`);
              }
            }
            for (const g of state.pile) {
              for (const c of g.cards) expect(serialized).not.toContain(`"${c.id}"`);
            }
          }
        }
      }),
      { numRuns: 25 },
    );
  });

  it('state survives a JSON serialization round-trip', () => {
    fc.assert(
      fc.property(arbConfig, (cfg) => {
        const { states } = trajectory(cfg);
        const last = states[states.length - 1]!;
        expect(JSON.parse(JSON.stringify(last))).toEqual(last);
      }),
      { numRuns: 25 },
    );
  });
});
