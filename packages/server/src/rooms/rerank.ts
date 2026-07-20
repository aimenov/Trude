import type { Placement } from '@trude/engine';

/**
 * A placement after the leaver penalty: consented mid-game leavers are pushed
 * to the bottom of the standings, everyone else compacts upward.
 */
export interface AdjustedPlacement extends Placement {
  /** True when this player consented-left mid-game before going out. */
  left: boolean;
}

/**
 * Re-ranks engine placements so that mid-game leavers always finish below
 * everyone who stayed:
 *
 * - Non-leavers keep their engine relative order, compacted to 1..k.
 * - Leavers occupy the bottom places; an EARLIER leave means a WORSE (higher
 *   number) final placement.
 * - The engine loser (joker holder), when not a leaver, therefore ranks above
 *   all leavers; a leaver-loser is ordered among the leavers by leave order.
 * - No leavers ⇒ identity (same placements, `left: false` everywhere).
 *
 * @param placements engine `gameOver` placements (placement 1 = best).
 * @param leavers    seat → leave order (1 = left first). Seats that already
 *                   went out before leaving must NOT be in this map — they
 *                   keep their earned placement.
 */
export function rerankPlacements(
  placements: readonly Placement[],
  leavers: ReadonlyMap<number, number>,
): AdjustedPlacement[] {
  if (leavers.size === 0) {
    return placements.map((p) => ({ ...p, left: false }));
  }
  const stayers = placements
    .filter((p) => !leavers.has(p.seat))
    .sort((a, b) => a.placement - b.placement);
  const left = placements
    .filter((p) => leavers.has(p.seat))
    // Later leave = better placement, so sort by leave order descending.
    .sort((a, b) => leavers.get(b.seat)! - leavers.get(a.seat)!);
  return [
    ...stayers.map((p, i) => ({ ...p, placement: i + 1, left: false })),
    ...left.map((p, i) => ({ ...p, placement: stayers.length + i + 1, left: true })),
  ];
}
