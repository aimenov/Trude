import { buildShuffledDeck } from './deck.js';
import { nameableRanks, nextSeatWithCards, validate } from './legal.js';
import { chance, randInt, seedRng } from './rng.js';
import { RANK_ORDER } from './types.js';
import type {
  Card, EngineAction, EngineEvent, EnginePlayer, GameConfig, GameState,
  PileGroup, Placement, PlayerGameStats, Rank, ReduceResult,
} from './types.js';

function freshStats(): PlayerGameStats {
  return {
    liesSurvived: 0, liesCaught: 0, checksWon: 0, checksLost: 0,
    cardsPickedUp: 0, quadsDiscarded: 0, jokerPassed: 0, jokerSmuggles: 0,
    truthfulThrows: 0, lyingThrows: 0, maxHandSize: 0, wasEverCaught: false, firstOut: false,
  };
}

function trackHandSize(p: EnginePlayer): void {
  if (p.hand.length > p.stats.maxHandSize) p.stats.maxHandSize = p.hand.length;
}

function markOut(state: GameState, seat: number, events: EngineEvent[]): void {
  const p = state.players[seat]!;
  p.out = true;
  state.outOrder.push(seat);
  if (state.outOrder.length === 1) p.stats.firstOut = true;
  events.push({ type: 'playerOut', seat });
}

/** Discards every four-of-a-kind in the seat's hand, ascending rank order. May empty the hand. */
function discardQuads(state: GameState, seat: number, events: EngineEvent[]): void {
  const p = state.players[seat]!;
  for (const rank of RANK_ORDER) {
    const quad = p.hand.filter((c) => c.rank === rank);
    if (quad.length === 4) {
      p.hand = p.hand.filter((c) => c.rank !== rank);
      state.retiredRanks.push(rank);
      state.discarded.push(...quad);
      p.stats.quadsDiscarded++;
      events.push({ type: 'fourDiscarded', seat, rank, cards: quad });
    }
  }
}

function seatsWithCards(state: GameState): number[] {
  return state.players.filter((p) => p.hand.length > 0).map((p) => p.seat);
}

function findJoker(state: GameState): Card {
  for (const p of state.players) {
    const j = p.hand.find((c) => c.rank === 'JOKER');
    if (j) return j;
  }
  for (const g of state.pile) {
    const j = g.cards.find((c) => c.rank === 'JOKER');
    if (j) return j;
  }
  /* c8 ignore next */
  throw new Error('Invariant violation: joker not found');
}

/**
 * Checks the end condition (≤1 player holding cards — that player provably holds
 * the joker and loses). Emits gameOver or turnStarted for the given lead seat.
 */
function finishOrLead(state: GameState, leadFrom: number, events: EngineEvent[]): void {
  const holders = seatsWithCards(state);
  if (holders.length <= 1) {
    const loserSeat = holders[0] ?? -1;
    /* c8 ignore next */
    if (loserSeat === -1) throw new Error('Invariant violation: nobody holds cards at game end');
    const placements: Placement[] = state.outOrder.map((seat, i) => ({
      playerId: state.players[seat]!.playerId, seat, placement: i + 1,
    }));
    placements.push({
      playerId: state.players[loserSeat]!.playerId, seat: loserSeat, placement: state.players.length,
    });
    const stats: Record<string, PlayerGameStats> = {};
    for (const p of state.players) stats[p.playerId] = p.stats;
    state.phase = { kind: 'over', loserSeat };
    events.push({ type: 'gameOver', loserSeat, jokerCard: findJoker(state), placements, stats });
    return;
  }
  const seat = state.players[leadFrom]!.hand.length > 0 ? leadFrom : nextSeatWithCards(state, leadFrom);
  state.phase = { kind: 'lead', seat };
  events.push({ type: 'turnStarted', seat, phase: 'lead', mustCheck: false });
}

// ---------------------------------------------------------------------------

export interface CreateOverrides {
  /** Test-only: exact deck in deal order (must be a complete deck for the size). */
  deck?: Card[];
  /** Test-only: fixed first leader instead of a random one. */
  firstLeaderSeat?: number;
}

export function createGame(
  config: GameConfig,
  playerIds: string[],
  overrides?: CreateOverrides,
): { state: GameState; events: EngineEvent[] } {
  const caps = config.deckSize === 37 ? { min: 2, max: 6 } : { min: 2, max: 8 };
  if (playerIds.length < caps.min || playerIds.length > caps.max) {
    throw new Error(`Deck ${config.deckSize} supports ${caps.min}-${caps.max} players`);
  }
  if (new Set(playerIds).size !== playerIds.length) throw new Error('Duplicate player ids');

  const rng = seedRng(config.seed);
  const deck = overrides?.deck ?? buildShuffledDeck(config.deckSize, rng);
  if (deck.length !== config.deckSize || new Set(deck.map((c) => c.id)).size !== deck.length) {
    throw new Error('Rigged deck must be a complete deck with unique ids');
  }
  const firstLeaderSeat = overrides?.firstLeaderSeat ?? randInt(rng, playerIds.length);
  if (firstLeaderSeat < 0 || firstLeaderSeat >= playerIds.length) throw new Error('Bad firstLeaderSeat');

  const players: EnginePlayer[] = playerIds.map((playerId, seat) => ({
    playerId, seat, hand: [], out: false, stats: freshStats(),
  }));

  // Deal one card at a time clockwise starting from the first leader, so the
  // remainder (+1 cards) lands on the leader and the seats right after — deterministic.
  deck.forEach((card, i) => {
    players[(firstLeaderSeat + i) % players.length]!.hand.push(card);
  });

  const state: GameState = {
    config, rng, players, pile: [], pileRank: null,
    retiredRanks: [], discarded: [], phase: { kind: 'lead', seat: firstLeaderSeat },
    actionCount: 0, outOrder: [],
  };

  const events: EngineEvent[] = [{
    type: 'dealt', handCounts: players.map((p) => p.hand.length), firstLeaderSeat,
  }];

  // Initial quad discards, in seat order starting from the first leader.
  for (let i = 0; i < players.length; i++) {
    const seat = (firstLeaderSeat + i) % players.length;
    discardQuads(state, seat, events);
    if (players[seat]!.hand.length === 0) markOut(state, seat, events);
  }
  for (const p of players) trackHandSize(p);

  finishOrLead(state, firstLeaderSeat, events);
  return { state, events };
}

// ---------------------------------------------------------------------------

export function reduce(prev: GameState, action: EngineAction): ReduceResult {
  const error = validate(prev, action);
  if (error) return { ok: false, error };

  const state = structuredClone(prev);
  const events: EngineEvent[] = [];
  state.actionCount++;

  const effective = action.type === 'timeout' ? autoAction(state, events) : action;

  if (effective.type === 'throw') applyThrow(state, effective, events);
  else applyCheck(state, effective, events);

  return { ok: true, state, events };
}

/** Deterministic auto-move for the current actor (timeout / autopilot / disconnect). */
function autoAction(state: GameState, events: EngineEvent[]): Exclude<EngineAction, { type: 'timeout' }> {
  const phase = state.phase;
  /* c8 ignore next */
  if (phase.kind === 'over') throw new Error('unreachable');
  const seat = phase.seat;
  if (phase.kind === 'respond') {
    const last = state.pile[state.pile.length - 1]!;
    events.push({ type: 'autoActed', seat, kind: 'check' });
    return { type: 'check', seat, flipIndex: randInt(state.rng, last.cards.length) };
  }
  // Lead: one random card, claiming its true rank ~70% of the time. A guaranteed-
  // truthful policy would be public knowledge and leak certainty to opponents.
  const hand = state.players[seat]!.hand;
  const card = hand[randInt(state.rng, hand.length)]!;
  const legal = nameableRanks(state);
  let rank: Rank;
  if (card.rank !== 'JOKER' && chance(state.rng, 70)) {
    rank = card.rank; // hand cards of a retired rank cannot exist, so this is always legal
  } else {
    rank = legal[randInt(state.rng, legal.length)]!;
  }
  events.push({ type: 'autoActed', seat, kind: 'lead' });
  return { type: 'throw', seat, cardIds: [card.id], rank };
}

function applyThrow(state: GameState, action: { seat: number; cardIds: string[]; rank?: Rank }, events: EngineEvent[]): void {
  const phase = state.phase;
  /* c8 ignore next */
  if (phase.kind === 'over') throw new Error('unreachable');
  const isLead = phase.kind === 'lead';
  const player = state.players[action.seat]!;
  const claim: Rank = isLead ? action.rank! : state.pileRank!;

  // A previous group that gets covered by this trust can never be flipped again:
  // if it was a lie, it survived.
  if (!isLead) {
    const covered = state.pile[state.pile.length - 1]!;
    if (covered.lied) state.players[covered.seat]!.stats.liesSurvived++;
  }

  const cards = action.cardIds.map((id) => player.hand.find((c) => c.id === id)!);
  player.hand = player.hand.filter((c) => !action.cardIds.includes(c.id));

  const lied = cards.some((c) => c.rank !== claim);
  if (lied) player.stats.lyingThrows++;
  else player.stats.truthfulThrows++;

  const group: PileGroup = { seat: action.seat, cards, claimedRank: claim, lied };
  state.pile.push(group);
  state.pileRank = claim;

  events.push({ type: 'cardsThrown', seat: action.seat, count: cards.length, rank: claim, isLead });

  const mustCheck = player.hand.length === 0;
  const next = nextSeatWithCards(state, action.seat);
  /* c8 ignore next */
  if (next === -1) throw new Error('Invariant violation: no responder available');
  state.phase = { kind: 'respond', seat: next, mustCheck };
  events.push({ type: 'turnStarted', seat: next, phase: 'respond', mustCheck });
}

function applyCheck(state: GameState, action: { seat: number; flipIndex: number }, events: EngineEvent[]): void {
  const checkerSeat = action.seat;
  const last = state.pile[state.pile.length - 1]!;
  const targetSeat = last.seat;
  const flipped = last.cards[action.flipIndex]!;
  const matched = flipped.rank === state.pileRank;

  const checker = state.players[checkerSeat]!;
  const target = state.players[targetSeat]!;

  if (matched) {
    checker.stats.checksLost++;
    if (last.lied) target.stats.liesSurvived++; // lied, got checked, and STILL got away with it
  } else {
    checker.stats.checksWon++;
    target.stats.liesCaught++;
    target.stats.wasEverCaught = true;
  }

  const pickerSeat = matched ? checkerSeat : targetSeat;
  const picker = state.players[pickerSeat]!;

  // Joker bookkeeping before the pile moves: a thrown joker picked up by someone
  // else was successfully smuggled onward.
  for (const g of state.pile) {
    if (g.cards.some((c) => c.rank === 'JOKER') && g.seat !== pickerSeat) {
      const thrower = state.players[g.seat]!;
      thrower.stats.jokerPassed++;
      thrower.stats.jokerSmuggles++;
    }
  }

  const pickedCount = state.pile.reduce((n, g) => n + g.cards.length, 0);
  picker.hand.push(...state.pile.flatMap((g) => g.cards));
  picker.stats.cardsPickedUp += pickedCount;
  trackHandSize(picker);
  state.pile = [];
  state.pileRank = null;

  // Winner of the reveal (the non-picker party) leads the next pile.
  const winnerSeat = matched ? targetSeat : checkerSeat;

  events.push({
    type: 'checkResult', checkerSeat, targetSeat, flipIndex: action.flipIndex,
    flipped, matched, pickerSeat, pickedCount,
    nextLeadSeat: -1, // patched below once eliminations resolve
  });
  const checkResultEvent = events[events.length - 1] as Extract<EngineEvent, { type: 'checkResult' }>;

  // A truthful last-card throw is confirmed: the thrower is out (safe).
  if (matched && target.hand.length === 0) markOut(state, targetSeat, events);

  // Pickup may complete four-of-a-kinds; discards may empty the picker's hand.
  discardQuads(state, pickerSeat, events);
  if (picker.hand.length === 0) markOut(state, pickerSeat, events);

  finishOrLead(state, winnerSeat, events);

  const finalPhase = state.phase;
  checkResultEvent.nextLeadSeat = finalPhase.kind === 'lead' ? finalPhase.seat : -1;
}
