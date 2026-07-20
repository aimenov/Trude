import { describe, expect, it } from 'vitest';
import type { Placement } from '@trude/engine';
import { rerankPlacements } from '../src/rooms/rerank.js';

/** Engine-style placements: seat i is player `p{i}`, placement given per seat. */
function placements(...placementBySeat: number[]): Placement[] {
  return placementBySeat.map((placement, seat) => ({ playerId: `p${seat}`, seat, placement }));
}

function bySeat(adjusted: ReturnType<typeof rerankPlacements>, seat: number) {
  return adjusted.find((p) => p.seat === seat)!;
}

describe('rerankPlacements', () => {
  it('no leavers = identity with left:false everywhere', () => {
    const input = placements(2, 1, 3);
    const out = rerankPlacements(input, new Map());
    expect(out).toHaveLength(3);
    for (const p of input) {
      expect(bySeat(out, p.seat)).toEqual({ ...p, left: false });
    }
  });

  it('a single leaver drops to last; stayers compact to 1..k', () => {
    // Engine: seat1 won, seat0 second, seat2 lost. Seat0 left mid-game.
    const out = rerankPlacements(placements(2, 1, 3), new Map([[0, 1]]));
    expect(bySeat(out, 1)).toMatchObject({ placement: 1, left: false });
    expect(bySeat(out, 2)).toMatchObject({ placement: 2, left: false }); // loser compacts above the leaver
    expect(bySeat(out, 0)).toMatchObject({ placement: 3, left: true });
  });

  it('multiple leavers: earlier leave = worse placement', () => {
    // 4 players; seats 1 and 3 left (seat1 first, seat3 later).
    const out = rerankPlacements(placements(1, 2, 3, 4), new Map([[1, 1], [3, 2]]));
    expect(bySeat(out, 0)).toMatchObject({ placement: 1, left: false });
    expect(bySeat(out, 2)).toMatchObject({ placement: 2, left: false });
    expect(bySeat(out, 3)).toMatchObject({ placement: 3, left: true }); // left later — better
    expect(bySeat(out, 1)).toMatchObject({ placement: 4, left: true }); // left first — worst
  });

  it('a leaver who is also the engine loser stays at the bottom among leavers', () => {
    // Engine loser seat2 ALSO left (first); seat0 left later.
    const out = rerankPlacements(placements(2, 1, 3), new Map([[2, 1], [0, 2]]));
    expect(bySeat(out, 1)).toMatchObject({ placement: 1, left: false });
    expect(bySeat(out, 0)).toMatchObject({ placement: 2, left: true });
    expect(bySeat(out, 2)).toMatchObject({ placement: 3, left: true });
  });

  it('a player who went out before leaving is not in the leaver set and keeps their placement', () => {
    // Seat0 finished 1st then left the table — caller must NOT include them.
    const out = rerankPlacements(placements(1, 2, 3), new Map([[1, 1]]));
    expect(bySeat(out, 0)).toMatchObject({ placement: 1, left: false });
    expect(bySeat(out, 2)).toMatchObject({ placement: 2, left: false });
    expect(bySeat(out, 1)).toMatchObject({ placement: 3, left: true });
  });

  it('all placements stay unique 1..n', () => {
    const out = rerankPlacements(placements(3, 1, 4, 2, 5), new Map([[1, 1], [4, 2], [0, 3]]));
    expect(new Set(out.map((p) => p.placement))).toEqual(new Set([1, 2, 3, 4, 5]));
  });
});
