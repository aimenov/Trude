import { describe, expect, it } from 'vitest';
import type { EngineEvent } from '@trude/engine';
import { config } from '../src/config.js';
import { graceForBatch } from '../src/rooms/animationGrace.js';

const g = config.animationGrace;

// Only `type` (and `pickedCount` for checkResult) matter to graceForBatch.
function ev(partial: { type: EngineEvent['type']; pickedCount?: number }): EngineEvent {
  return partial as EngineEvent;
}

function pickup(pickedCount: number): number {
  return Math.min(g.pickupBaseMs + g.pickupPerCardMs * Math.min(pickedCount, g.pickupCardCap), g.pickupCapMs);
}

describe('graceForBatch', () => {
  it('returns 0 for an empty batch', () => {
    expect(graceForBatch([])).toBe(0);
  });

  it('returns 0 for batches with only instant events (no buffer)', () => {
    expect(graceForBatch([
      ev({ type: 'cardsThrown' }),
      ev({ type: 'turnStarted' }),
      ev({ type: 'autoActed' }),
    ])).toBe(0);
  });

  it('charges the deal choreography plus buffer', () => {
    expect(graceForBatch([ev({ type: 'dealt' }), ev({ type: 'turnStarted' })]))
      .toBe(g.dealMs + g.bufferMs); // 2750
  });

  it('charges reveal + pickup estimate for checkResult', () => {
    expect(graceForBatch([ev({ type: 'checkResult', pickedCount: 4 })]))
      .toBe(g.checkResultMs + pickup(4) + g.bufferMs); // 2700 + 650 + 250
  });

  it('caps the pickup estimate card count at pickupCardCap', () => {
    const atCap = graceForBatch([ev({ type: 'checkResult', pickedCount: g.pickupCardCap })]);
    const beyond = graceForBatch([ev({ type: 'checkResult', pickedCount: 53 })]);
    expect(beyond).toBe(atCap);
    expect(atCap).toBe(g.checkResultMs + pickup(g.pickupCardCap) + g.bufferMs);
  });

  it('never exceeds pickupCapMs for the pickup estimate', () => {
    expect(pickup(Number.MAX_SAFE_INTEGER)).toBeLessThanOrEqual(g.pickupCapMs);
  });

  it('charges each fourDiscarded', () => {
    expect(graceForBatch([ev({ type: 'fourDiscarded' })])).toBe(g.fourDiscardedMs + g.bufferMs);
    expect(graceForBatch([ev({ type: 'fourDiscarded' }), ev({ type: 'fourDiscarded' })]))
      .toBe(2 * g.fourDiscardedMs + g.bufferMs);
  });

  it('charges each playerOut', () => {
    expect(graceForBatch([ev({ type: 'playerOut' })])).toBe(g.playerOutMs + g.bufferMs);
    expect(graceForBatch([ev({ type: 'playerOut' }), ev({ type: 'playerOut' })]))
      .toBe(2 * g.playerOutMs + g.bufferMs);
  });

  it('adds the buffer once across mixed batches', () => {
    expect(graceForBatch([
      ev({ type: 'checkResult', pickedCount: 2 }),
      ev({ type: 'fourDiscarded' }),
      ev({ type: 'playerOut' }),
      ev({ type: 'turnStarted' }),
    ])).toBe(g.checkResultMs + pickup(2) + g.fourDiscardedMs + g.playerOutMs + g.bufferMs);
  });

  it('caps the total at totalCapMs', () => {
    const huge = [
      ev({ type: 'checkResult', pickedCount: 24 }),
      ev({ type: 'checkResult', pickedCount: 24 }),
      ev({ type: 'fourDiscarded' }),
      ev({ type: 'fourDiscarded' }),
      ev({ type: 'playerOut' }),
      ev({ type: 'playerOut' }),
    ];
    expect(graceForBatch(huge)).toBe(g.totalCapMs); // raw sum 11550 > 8000
  });
});
