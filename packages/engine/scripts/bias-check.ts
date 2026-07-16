// One-off diagnostic: loser-seat distribution over random-policy games.
import { playRandomGame } from '../test/helpers.js';

for (const players of [2, 3, 4]) {
  const tally = new Map<number, number>();
  const N = 400;
  for (let i = 0; i < N; i++) {
    const { state } = playRandomGame(players, 37, `bias-${players}-${i}`);
    if (state.phase.kind === 'over') tally.set(state.phase.loserSeat, (tally.get(state.phase.loserSeat) ?? 0) + 1);
  }
  console.log(`${players}p/37, ${N} games — loserSeat:`, Object.fromEntries([...tally.entries()].sort()));
}
