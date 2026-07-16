import type { EngineEvent } from '@trude/engine';
import { config } from '../config.js';

/**
 * Animation-aware timer grace: how long the client's animation queue is
 * expected to run for a given event batch. The deadline of the turn armed in
 * the same batch is pushed back by this much so the decision window only
 * starts draining once the choreography has (roughly) finished.
 *
 * Pure function of the batch; all constants live in config.animationGrace and
 * mirror the client MotionSpec durations.
 */
export function graceForBatch(events: readonly EngineEvent[]): number {
  const g = config.animationGrace;
  let total = 0;
  for (const e of events) {
    switch (e.type) {
      case 'dealt':
        total += g.dealMs;
        break;
      case 'checkResult': {
        const pickup = Math.min(
          g.pickupBaseMs + g.pickupPerCardMs * Math.min(e.pickedCount, g.pickupCardCap),
          g.pickupCapMs,
        );
        total += g.checkResultMs + pickup;
        break;
      }
      case 'fourDiscarded':
        total += g.fourDiscardedMs;
        break;
      case 'playerOut':
        total += g.playerOutMs;
        break;
      default:
        break; // cardsThrown/turnStarted/etc. are effectively instant
    }
  }
  if (total > 0) total += g.bufferMs;
  return Math.min(total, g.totalCapMs);
}
