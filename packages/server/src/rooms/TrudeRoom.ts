import { randomInt, randomUUID } from 'node:crypto';
import { Room } from 'colyseus';
import type { Client } from 'colyseus';
import { createGame, projectFor, reduce } from '@trude/engine';
import type { DeckSize, EngineAction, EngineEvent, GameState } from '@trude/engine';
import { verifyToken } from '../auth/jwt.js';
import { config } from '../config.js';
import {
  clientMessages, REACTION_ALLOWLIST, ROOM_CODE_ALPHABET,
} from '../protocol.js';
import type {
  ClientMessageName, EventBatch, RewardsMessage, ServerErrorCode, StateFull, WireEvent, WirePlayer,
} from '../protocol.js';
import type { GameAwards, Store } from '../store/store.js';
import { graceForBatch } from './animationGrace.js';
import { rerankPlacements } from './rerank.js';

interface SeatInfo {
  userId: string;
  nickname: string;
  avatar: string;
  /** Client opted into the `rewards` message at join (old clients never see it). */
  supportsRewards: boolean;
  connected: boolean;
  /** Epoch ms of the drop; null while connected. */
  disconnectedSince: number | null;
  autoPilot: boolean;
  consecutiveTimeouts: number;
  lastClientSeq: number;
  lastReactionAt: number;
  client: Client | null;
  /** Consented mid-game quit before going out — penalized at game over. */
  leftConsented: boolean;
  /** 1-based order of consented mid-game leaves (earlier = worse final placement); 0 = never left. */
  leftOrder: number;
}

/** The currently armed turn timer, as broadcast to clients. */
interface TurnArm {
  deadlineTs: number;
  /** Base decision window (ms), excluding animation grace. */
  durationMs: number;
  /** Animation grace baked into deadlineTs. */
  graceMs: number;
  /** True when the window was cut to disconnectedTurnMs mid-turn or armed short. */
  shortened: boolean;
}

interface RoomOptions {
  token?: string;
  name?: string;
  private?: boolean;
  deckSize?: DeckSize;
  turnTimerSec?: 15 | 30 | 60;
  maxPlayers?: number;
  /** New clients pass true to receive the post-game `rewards` message. */
  supportsRewards?: boolean;
}

interface PendingSwap { fromUserId: string; targetUserId: string; expiresAt: number; }

const DECK_CAP: Record<number, number> = { 37: 6, 53: 8 };

/** Set by index.ts at boot; swappable for tests. */
export let store: Store;
export function setStore(s: Store): void { store = s; }

export class TrudeRoom extends Room {
  private phase: 'lobby' | 'playing' | 'finished' = 'lobby';
  private displayName = 'Trude room';
  private deckSize: DeckSize = 37;
  private turnTimerSec: 15 | 30 | 60 = 30;
  private maxPlayersCfg = 6;
  private isPublic = true;
  private joinCode: string | null = null;
  private adminUserId = '';
  private seats: SeatInfo[] = [];
  private game: GameState | null = null;
  private lastResolution: EventBatch | null = null;
  private timerNonce = 0;
  private shorteningNonce = 0;
  private turnArm: TurnArm | null = null;
  private allDisconnectedSince: number | null = null;
  /** Counts consented mid-game leaves this game (feeds SeatInfo.leftOrder). */
  private leaveCounter = 0;

  override async onCreate(options: RoomOptions): Promise<void> {
    this.displayName = (options.name ?? 'Trude room').slice(0, 40);
    if (options.deckSize === 37 || options.deckSize === 53) this.deckSize = options.deckSize;
    if (options.turnTimerSec === 15 || options.turnTimerSec === 30 || options.turnTimerSec === 60) {
      this.turnTimerSec = options.turnTimerSec;
    }
    this.maxPlayersCfg = Math.min(options.maxPlayers ?? DECK_CAP[this.deckSize]!, DECK_CAP[this.deckSize]!);
    this.isPublic = options.private !== true;
    if (!this.isPublic) {
      this.joinCode = Array.from({ length: 6 }, () => ROOM_CODE_ALPHABET[randomInt(ROOM_CODE_ALPHABET.length)]).join('');
      await this.setPrivate(true);
    }
    this.maxClients = this.maxPlayersCfg;
    await this.updateMetadata();

    for (const name of Object.keys(clientMessages) as ClientMessageName[]) {
      this.onMessage(name, (client, raw: unknown) => {
        const parsed = clientMessages[name].safeParse(raw);
        if (!parsed.success) {
          this.sendError(client, 'BAD_MESSAGE', `Malformed ${name}`);
          return;
        }
        try {
          this.dispatch(client, name, parsed.data as never);
        } catch (e) {
          this.sendError(client, 'BAD_MESSAGE', e instanceof Error ? e.message : 'Internal error');
        }
      });
    }

    // Abandoned-room sweeper: every 30 s, dispose if all players gone > 5 min mid-game.
    this.clock.setInterval(() => this.sweepAbandoned(), 30_000);
  }

  override async onJoin(client: Client, options: RoomOptions): Promise<void> {
    const token = options.token;
    if (!token) throw new Error('Missing auth token');
    const claims = verifyToken(token);

    const existing = this.seats.find((s) => s.userId === claims.sub);
    if (existing) throw new Error('Already in this room');
    // Join-time block enforcement (either direction). Surfaces to the client
    // as a transport ERROR frame: code 4216 (APPLICATION_ERROR), message 'BLOCKED'.
    if (this.seats.length > 0
      && await store.hasBlockBetween(claims.sub, this.seats.map((s) => s.userId))) {
      throw new Error('BLOCKED');
    }
    if (this.phase !== 'lobby') throw new Error('GAME_IN_PROGRESS');
    if (this.seats.length >= this.maxPlayersCfg) throw new Error('Room is full');

    if (this.seats.length === 0) this.adminUserId = claims.sub;
    const seat: SeatInfo = {
      userId: claims.sub, nickname: claims.nick, avatar: claims.avatar,
      supportsRewards: options.supportsRewards === true,
      connected: true, disconnectedSince: null, autoPilot: false, consecutiveTimeouts: 0,
      lastClientSeq: -1, lastReactionAt: 0, client,
      leftConsented: false, leftOrder: 0,
    };
    this.seats.push(seat);
    client.userData = { userId: claims.sub };

    this.broadcastEvents([{
      type: 'playerJoined', userId: seat.userId, nickname: seat.nickname, avatar: seat.avatar,
      seat: this.seats.length - 1,
    }]);
    client.send('stateFull', this.buildStateFull(seat.userId));
    await this.updateMetadata();
  }

  override async onLeave(client: Client, consented: boolean): Promise<void> {
    const userId = (client.userData as { userId?: string } | undefined)?.userId;
    const seatIdx = this.seats.findIndex((s) => s.userId === userId);
    if (seatIdx === -1) return;
    const seat = this.seats[seatIdx]!;

    if (consented) {
      // A deliberate leave never holds a reconnection reservation.
      if (this.phase === 'playing') {
        // Quitting mid-game: the seat stays (cards are never redistributed) on
        // permanent autopilot; the shortened timer keeps the game moving.
        // A player who has NOT yet gone out forfeits their standing: they are
        // re-ranked below everyone who stayed (see rerank.ts) and earn nothing.
        // A player who already went out safe keeps their earned placement.
        if (!this.game?.players[seatIdx]?.out && !seat.leftConsented) {
          seat.leftConsented = true;
          seat.leftOrder = ++this.leaveCounter;
        }
        seat.connected = false;
        seat.disconnectedSince = Date.now();
        seat.client = null;
        seat.autoPilot = true;
        this.noteConnectivity();
        this.broadcastEvents([
          { type: 'playerConnection', seat: seatIdx, connected: false },
          { type: 'autoPilot', seat: seatIdx, on: true },
        ]);
        this.shortenActiveTurn(seatIdx);
      } else if (this.phase === 'finished') {
        // Seat indexes must stay aligned with the finished game's state until the
        // room resets; returnToLobby drops disconnected seats.
        seat.connected = false;
        seat.disconnectedSince = Date.now();
        seat.client = null;
        this.noteConnectivity();
        this.broadcastEvents([{ type: 'playerConnection', seat: seatIdx, connected: false }]);
      } else {
        this.removeFromLobby(seatIdx);
      }
      return;
    }

    seat.connected = false;
    seat.disconnectedSince = Date.now();
    seat.client = null;
    this.noteConnectivity();
    if (this.phase === 'playing') {
      this.broadcastEvents([{ type: 'playerConnection', seat: seatIdx, connected: false }]);
      // Blips shouldn't touch the timer: shorten only if still gone in 5 s.
      this.scheduleDisconnectShortening(seatIdx);
    }

    try {
      const rejoined = await this.allowReconnection(
        client, this.phase === 'lobby' ? config.reconnectionSecondsLobby : config.reconnectionSeconds,
      );
      seat.connected = true;
      seat.disconnectedSince = null;
      seat.client = rejoined;
      seat.autoPilot = false;
      seat.consecutiveTimeouts = 0;
      seat.lastClientSeq = -1; // reconnecting clients restart their clientSeq counter
      rejoined.userData = { userId: seat.userId };
      this.noteConnectivity();
      if (this.phase === 'playing') {
        this.broadcastEvents([
          { type: 'playerConnection', seat: seatIdx, connected: true },
          { type: 'autoPilot', seat: seatIdx, on: false },
        ]);
        // Give the full window back only if this turn was actually cut short —
        // a blip is a no-op, and reconnecting never extends an untouched timer.
        this.restoreActiveTurn(seatIdx);
      }
      rejoined.send('stateFull', this.buildStateFull(seat.userId));
    } catch {
      // Window expired. Mid-game: the player stays seated on permanent autopilot —
      // cards are never redistributed. Lobby: free the seat.
      if (this.phase === 'lobby') {
        const idx = this.seats.findIndex((s) => s.userId === seat.userId);
        if (idx !== -1) this.removeFromLobby(idx);
      } else if (!seat.autoPilot) {
        seat.autoPilot = true;
        const idx = this.seats.findIndex((s) => s.userId === seat.userId);
        this.broadcastEvents([{ type: 'autoPilot', seat: idx, on: true }]);
      }
    }
  }

  // -------------------------------------------------------------------------
  // Message dispatch
  // -------------------------------------------------------------------------

  private dispatch(client: Client, name: ClientMessageName, payload: Record<string, unknown>): void {
    const seatIdx = this.seatOf(client);
    if (seatIdx === -1) { this.sendError(client, 'NOT_IN_ROOM', 'Not seated'); return; }
    const seat = this.seats[seatIdx]!;

    if (name === 'ping') {
      client.send('pong', { t: payload['t'], serverT: Date.now() });
      return;
    }

    // Idempotency envelope (all remaining messages carry it).
    const actionCount = payload['actionCount'] as number;
    const clientSeq = payload['clientSeq'] as number;
    if (clientSeq <= seat.lastClientSeq) return; // duplicate/retry — already handled
    if (name === 'throwCards' || name === 'check') {
      if (this.game && actionCount !== this.game.actionCount) {
        this.sendError(client, 'STALE_ACTION', 'The game moved on — resync');
        return;
      }
    }
    seat.lastClientSeq = clientSeq;

    switch (name) {
      case 'configureRoom': return this.handleConfigure(client, seat, payload);
      case 'startGame': return this.handleStart(client, seat);
      case 'kickPlayer': return this.handleKick(client, seat, payload['userId'] as string);
      case 'throwCards': return this.handleGameAction(client, seatIdx, {
        type: 'throw', seat: seatIdx,
        cardIds: payload['cardIds'] as string[],
        ...(payload['rank'] !== undefined ? { rank: payload['rank'] as never } : {}),
      });
      case 'check': return this.handleGameAction(client, seatIdx, {
        type: 'check', seat: seatIdx, flipIndex: payload['flipIndex'] as number,
      });
      case 'requestSeatSwap': return this.handleSwapRequest(client, seat, payload['targetUserId'] as string);
      case 'respondSeatSwap': return this.handleSwapResponse(client, seat, payload['accept'] as boolean);
      case 'reaction': return this.handleReaction(client, seatIdx, seat, payload['emoji'] as string);
    }
  }

  private handleConfigure(client: Client, seat: SeatInfo, p: Record<string, unknown>): void {
    if (this.phase !== 'lobby') { this.sendError(client, 'GAME_IN_PROGRESS', 'Game already running'); return; }
    if (seat.userId !== this.adminUserId) { this.sendError(client, 'NOT_ADMIN', 'Only the admin can configure'); return; }
    if (p['deckSize'] === 37 || p['deckSize'] === 53) this.deckSize = p['deckSize'] as DeckSize;
    const t = p['turnTimerSec'];
    if (t === 15 || t === 30 || t === 60) this.turnTimerSec = t;
    const cap = DECK_CAP[this.deckSize]!;
    const requested = typeof p['maxPlayers'] === 'number' ? (p['maxPlayers'] as number) : this.maxPlayersCfg;
    this.maxPlayersCfg = Math.max(2, Math.min(requested, cap));
    this.maxClients = this.maxPlayersCfg;
    this.broadcastEvents([{
      type: 'roomConfigured', deckSize: this.deckSize, turnTimerSec: this.turnTimerSec, maxPlayers: this.maxPlayersCfg,
    }]);
    void this.updateMetadata();
  }

  private handleStart(client: Client, seat: SeatInfo): void {
    if (this.phase !== 'lobby') { this.sendError(client, 'GAME_IN_PROGRESS', 'Game already running'); return; }
    if (seat.userId !== this.adminUserId) { this.sendError(client, 'NOT_ADMIN', 'Only the admin can start'); return; }
    if (this.seats.length < 2) { this.sendError(client, 'NOT_ENOUGH_PLAYERS', 'Need at least 2 players'); return; }
    if (this.seats.length > DECK_CAP[this.deckSize]!) {
      this.sendError(client, 'TOO_MANY_PLAYERS', `Deck of ${this.deckSize} allows up to ${DECK_CAP[this.deckSize]}`);
      return;
    }

    const { state, events } = createGame(
      { deckSize: this.deckSize, seed: randomUUID() },
      this.seats.map((s) => s.userId),
    );
    this.game = state;
    this.phase = 'playing';
    this.lastResolution = null;
    this.leaveCounter = 0;
    for (const s of this.seats) {
      s.consecutiveTimeouts = 0;
      s.leftConsented = false;
      s.leftOrder = 0;
      // A stale disconnected flag must never leak a shortened first turn into a
      // fresh game: anyone with a live client is connected by definition.
      if (s.client) {
        s.connected = true;
        s.disconnectedSince = null;
      }
    }
    void this.setPrivate(true);
    void this.updateMetadata();
    this.sendHands();
    this.broadcastBatch(events);
  }

  private handleKick(client: Client, seat: SeatInfo, targetUserId: string): void {
    if (this.phase !== 'lobby') { this.sendError(client, 'GAME_IN_PROGRESS', 'Kicking is lobby-only'); return; }
    if (seat.userId !== this.adminUserId) { this.sendError(client, 'NOT_ADMIN', 'Only the admin can kick'); return; }
    const idx = this.seats.findIndex((s) => s.userId === targetUserId);
    if (idx === -1 || targetUserId === this.adminUserId) { this.sendError(client, 'BAD_TARGET', 'Cannot kick that player'); return; }
    const target = this.seats[idx]!;
    const targetClient = target.client;
    this.removeFromLobby(idx);
    targetClient?.leave();
  }

  private handleGameAction(client: Client, seatIdx: number, action: EngineAction): void {
    if (this.phase !== 'playing' || !this.game) { this.sendError(client, 'BAD_PHASE', 'No game running'); return; }
    const seat = this.seats[seatIdx]!;
    seat.consecutiveTimeouts = 0;
    if (seat.autoPilot) {
      seat.autoPilot = false;
      this.broadcastEvents([{ type: 'autoPilot', seat: seatIdx, on: false }]);
    }
    this.applyEngineAction(action, client);
  }

  private pendingSwap: PendingSwap | null = null;

  private handleSwapRequest(client: Client, seat: SeatInfo, targetUserId: string): void {
    if (this.phase !== 'lobby') { this.sendError(client, 'GAME_IN_PROGRESS', 'Seat swap is lobby-only in v1'); return; }
    const target = this.seats.find((s) => s.userId === targetUserId);
    if (!target || target.userId === seat.userId) { this.sendError(client, 'BAD_TARGET', 'No such player'); return; }
    if (this.pendingSwap && Date.now() < this.pendingSwap.expiresAt) {
      this.sendError(client, 'SWAP_PENDING', 'Another swap is pending');
      return;
    }
    this.pendingSwap = { fromUserId: seat.userId, targetUserId, expiresAt: Date.now() + 20_000 };
    target.client?.send('seatSwapRequested', {
      fromSeat: this.seats.indexOf(seat), fromUserId: seat.userId,
    });
  }

  private handleSwapResponse(client: Client, seat: SeatInfo, accept: boolean): void {
    const swap = this.pendingSwap;
    if (!swap || swap.targetUserId !== seat.userId || Date.now() >= swap.expiresAt) {
      this.sendError(client, 'NO_PENDING_SWAP', 'No swap request for you');
      return;
    }
    this.pendingSwap = null;
    const a = this.seats.findIndex((s) => s.userId === swap.fromUserId);
    const b = this.seats.findIndex((s) => s.userId === swap.targetUserId);
    if (accept && a !== -1 && b !== -1) {
      const tmp = this.seats[a]!;
      this.seats[a] = this.seats[b]!;
      this.seats[b] = tmp;
    }
    this.broadcastEvents([{ type: 'seatSwapResolved', seatA: a, seatB: b, accepted: accept && a !== -1 && b !== -1 }]);
    this.syncLobby();
  }

  private handleReaction(client: Client, seatIdx: number, seat: SeatInfo, emoji: string): void {
    if (!(REACTION_ALLOWLIST as readonly string[]).includes(emoji)) {
      this.sendError(client, 'BAD_EMOJI', 'Unknown reaction');
      return;
    }
    const now = Date.now();
    if (now - seat.lastReactionAt < 1500) { this.sendError(client, 'RATE_LIMITED', 'Slow down'); return; }
    seat.lastReactionAt = now;
    this.broadcast('reaction', { seat: seatIdx, emoji });
  }

  // -------------------------------------------------------------------------
  // Engine plumbing
  // -------------------------------------------------------------------------

  private applyEngineAction(action: EngineAction, origin: Client | null): void {
    if (!this.game) return;
    if (process.env['TRUDE_DEBUG']) console.log('[room] action', JSON.stringify(action));
    const before = this.game;
    const result = reduce(before, action);
    if (process.env['TRUDE_DEBUG'] && !result.ok) console.log('[room] rejected', result.error.code);
    if (!result.ok) {
      if (origin) this.sendError(origin, result.error.code, result.error.message);
      return;
    }
    this.game = result.state;

    // Private hand snapshots for every player whose hand changed.
    for (const p of result.state.players) {
      const prev = before.players[p.seat]!.hand;
      if (prev.length !== p.hand.length || prev.some((c, i) => c.id !== p.hand[i]!.id)) {
        this.sendHandTo(p.seat);
      }
    }

    this.broadcastBatch(result.events);
  }

  /** Turns engine events into wire events, arms the turn timer, handles game over. */
  private broadcastBatch(engineEvents: EngineEvent[]): void {
    if (!this.game) return;
    const graceMs = graceForBatch(engineEvents);
    const wire: WireEvent[] = [];

    for (const e of engineEvents) {
      switch (e.type) {
        case 'dealt':
          wire.push({
            type: 'gameStarted', deckSize: this.deckSize,
            seatOrder: this.seats.map((s, i) => ({ seat: i, userId: s.userId })),
            handCounts: e.handCounts,
          });
          break;
        case 'turnStarted': {
          const { deadlineTs, durationMs } = this.armTurnTimer(e.seat, graceMs);
          wire.push({ type: 'turnStarted', seat: e.seat, phase: e.phase, mustCheck: e.mustCheck, deadlineTs, durationMs });
          break;
        }
        case 'gameOver': {
          this.cancelTimer();
          const adjusted = rerankPlacements(e.placements, this.leaverSeats());
          wire.push({
            type: 'gameOver', loserSeat: e.loserSeat,
            loserUserId: this.seats[e.loserSeat]!.userId, jokerCard: e.jokerCard,
            placements: adjusted.map((p) => ({
              userId: p.playerId, seat: p.seat, placement: p.placement,
              ...(p.left ? { left: true } : {}),
            })),
            stats: e.stats,
          });
          void this.finishGame(e);
          break;
        }
        case 'autoActed': {
          const seat = this.seats[e.seat]!;
          seat.consecutiveTimeouts++;
          if (!seat.autoPilot && seat.consecutiveTimeouts >= config.autopilotAfterTimeouts) {
            seat.autoPilot = true;
            wire.push({ type: 'autoPilot', seat: e.seat, on: true });
          }
          wire.push(e);
          break;
        }
        default:
          wire.push(e);
      }
    }

    const batch: EventBatch = { actionCount: this.game.actionCount, events: wire };
    if (wire.some((e) => e.type === 'checkResult' || e.type === 'gameOver')) this.lastResolution = batch;
    if (process.env['TRUDE_DEBUG']) console.log('[room] batch', batch.actionCount, wire.map((e) => e.type).join(','));
    this.broadcast('events', batch);
  }

  /** Lobby-phase events that don't advance the game get actionCount -1. */
  private broadcastEvents(events: WireEvent[]): void {
    this.broadcast('events', { actionCount: this.game?.actionCount ?? -1, events } satisfies EventBatch);
  }

  /** Arms the decision timer for a fresh turn; graceMs comes from graceForBatch. */
  private armTurnTimer(actorSeat: number, graceMs: number): { deadlineTs: number; durationMs: number } {
    this.cancelTimer(); // also invalidates any pending shortening check — the turn advanced
    const seat = this.seats[actorSeat]!;
    const now = Date.now();
    const goneTooLong = !seat.connected && seat.disconnectedSince !== null
      && now - seat.disconnectedSince > config.disconnectedGraceMs;
    const shortened = seat.autoPilot || goneTooLong;
    const durationMs = shortened ? config.disconnectedTurnMs : this.turnTimerSec * 1000;
    const deadlineTs = now + durationMs + graceMs;
    this.turnArm = { deadlineTs, durationMs, graceMs, shortened };
    this.armTimeout(durationMs + graceMs);
    // Actor dropped moments ago and may come right back: arm full, watch for 5 s.
    if (!seat.connected && !shortened) this.scheduleDisconnectShortening(actorSeat);
    return { deadlineTs, durationMs };
  }

  /** (Re)arms the timeout that auto-acts for the current actor. */
  private armTimeout(ms: number): void {
    const nonce = ++this.timerNonce;
    this.clock.setTimeout(() => {
      if (nonce !== this.timerNonce || this.phase !== 'playing') return;
      this.applyEngineAction({ type: 'timeout' }, null);
    }, ms);
  }

  private cancelTimer(): void {
    this.timerNonce++;
    this.shorteningNonce++;
    this.turnArm = null;
  }

  private isActorSeat(seatIdx: number): boolean {
    return this.game !== null && this.game.phase.kind !== 'over' && this.game.phase.seat === seatIdx;
  }

  /** Cuts the running turn to the disconnected window (consented quit, or a drop
   *  that outlived the disconnect grace). Never extends; no-op if already short. */
  private shortenActiveTurn(seatIdx: number): void {
    if (!this.isActorSeat(seatIdx) || !this.turnArm || this.turnArm.shortened) return;
    const remaining = Math.max(this.turnArm.deadlineTs - Date.now(), 0);
    const ms = Math.min(remaining, config.disconnectedTurnMs);
    this.turnArm = {
      deadlineTs: Date.now() + ms, durationMs: config.disconnectedTurnMs, graceMs: 0, shortened: true,
    };
    this.armTimeout(ms);
    if (process.env['TRUDE_DEBUG']) console.log('[room] shorten turn', seatIdx, 'to', ms, 'ms');
    this.broadcastTurnDeadline(seatIdx);
  }

  /** A non-consented drop: shorten only if the actor is still gone in 5 s, so
   *  transient socket blips never touch the timer. Nonce-guarded — invalidated
   *  by cancelTimer/armTurnTimer whenever the turn advances. */
  private scheduleDisconnectShortening(seatIdx: number): void {
    const seat = this.seats[seatIdx];
    if (!seat || seat.connected || seat.disconnectedSince === null) return;
    if (!this.isActorSeat(seatIdx)) return;
    const delay = Math.max(seat.disconnectedSince + config.disconnectedGraceMs - Date.now(), 0);
    const nonce = ++this.shorteningNonce;
    if (process.env['TRUDE_DEBUG']) console.log('[room] disconnect shortening check for seat', seatIdx, 'in', delay, 'ms');
    this.clock.setTimeout(() => {
      if (nonce !== this.shorteningNonce || this.phase !== 'playing') return;
      const s = this.seats[seatIdx];
      if (!s || s.connected) return; // came back within grace — leave the timer alone
      this.shortenActiveTurn(seatIdx);
    }, delay);
  }

  /** Reconnect: give the full base window back ONLY if this turn was shortened.
   *  An untouched timer stays untouched (blips are no-ops; reconnecting can
   *  never be exploited to reset a running turn). */
  private restoreActiveTurn(seatIdx: number): void {
    if (!this.isActorSeat(seatIdx) || !this.turnArm?.shortened) return;
    const durationMs = this.turnTimerSec * 1000;
    this.turnArm = { deadlineTs: Date.now() + durationMs, durationMs, graceMs: 0, shortened: false };
    this.armTimeout(durationMs);
    if (process.env['TRUDE_DEBUG']) console.log('[room] restore turn', seatIdx, 'to', durationMs, 'ms');
    this.broadcastTurnDeadline(seatIdx);
  }

  /** Synthetic turnStarted re-broadcast carrying the CURRENT deadline + base window. */
  private broadcastTurnDeadline(seatIdx: number): void {
    if (!this.game || this.game.phase.kind === 'over' || !this.turnArm) return;
    this.broadcastEvents([{
      type: 'turnStarted', seat: seatIdx,
      phase: this.game.phase.kind as 'lead' | 'respond',
      mustCheck: this.game.phase.kind === 'respond' && this.game.phase.mustCheck,
      deadlineTs: this.turnArm.deadlineTs,
      durationMs: this.turnArm.durationMs,
    }]);
  }

  private async finishGame(e: Extract<EngineEvent, { type: 'gameOver' }>): Promise<void> {
    this.phase = 'finished';
    const game = this.game!;
    // Same leaver re-rank as the wire placements: leavers score last and are
    // flagged so the store denies them coins/quests (rating uses the adjusted
    // last placement — leaving is never better than losing).
    const adjusted = rerankPlacements(e.placements, this.leaverSeats());
    let awards = new Map<string, GameAwards>();
    try {
      awards = await store.recordGameResult({
        roomId: this.roomId, deckSize: this.deckSize, status: 'FINISHED',
        loserUserId: this.seats[e.loserSeat]!.userId,
        isPrivate: !this.isPublic,
        actionCount: game.actionCount,
        participants: adjusted.map((p) => ({
          userId: p.playerId, placement: p.placement, stats: game.players[p.seat]!.stats,
          ...(p.left ? { leaver: true } : {}),
        })),
      });
    } catch (err) {
      console.error('Failed to persist game result', err);
    }
    for (const [userId, userAwards] of awards) {
      const seat = this.seats.find((s) => s.userId === userId);
      for (const a of userAwards.achievements) seat?.client?.send('achievementUnlocked', a);
    }
    // Post-game economy summary — only to seats that opted in at join.
    for (const [userId, userAwards] of awards) {
      const seat = this.seats.find((s) => s.userId === userId);
      if (seat?.supportsRewards) seat.client?.send('rewards', userAwards satisfies RewardsMessage);
    }

    this.clock.setTimeout(() => this.returnToLobby(), config.rematchLobbyDelayMs);
  }

  private returnToLobby(): void {
    this.phase = 'lobby';
    this.game = null;
    this.lastResolution = null;
    this.pendingSwap = null;
    // Drop seats whose players never came back; everyone else stays for the rematch.
    this.seats = this.seats.filter((s) => s.connected);
    if (this.seats.length === 0) return; // autoDispose will reap the room
    if (!this.seats.some((s) => s.userId === this.adminUserId)) this.adminUserId = this.seats[0]!.userId;
    if (this.isPublic) void this.setPrivate(false);
    void this.updateMetadata();
    this.syncLobby();
  }

  // -------------------------------------------------------------------------
  // Snapshots & helpers
  // -------------------------------------------------------------------------

  private buildStateFull(userId: string): StateFull {
    const seatIdx = this.seats.findIndex((s) => s.userId === userId);
    const view = this.game ? projectFor(this.game, seatIdx === -1 ? null : seatIdx) : null;
    return {
      actionCount: this.game?.actionCount ?? -1,
      phase: this.phase,
      config: { deckSize: this.deckSize, turnTimerSec: this.turnTimerSec, maxPlayers: this.maxPlayersCfg },
      roomCode: this.joinCode,
      players: this.seats.map((s, i): WirePlayer => ({
        userId: s.userId, nickname: s.nickname, avatar: s.avatar, seat: i,
        cardCount: view?.players[i]?.cardCount ?? 0,
        connected: s.connected, autoPilot: s.autoPilot,
        isOut: view?.players[i]?.out ?? false,
        isAdmin: s.userId === this.adminUserId,
      })),
      pile: view?.pile ?? { rank: null, totalCount: 0, groups: [] },
      lastThrowSeat: view?.lastThrowSeat ?? null,
      mustCheck: view?.mustCheck ?? false,
      retiredRanks: view?.retiredRanks ?? [],
      discarded: view?.discarded ?? [],
      turn: view?.turn ? {
        ...view.turn,
        deadlineTs: this.turnArm?.deadlineTs ?? 0,
        durationMs: this.turnArm?.durationMs ?? this.turnTimerSec * 1000,
      } : null,
      hand: view?.hand ?? [],
      lastResolution: this.lastResolution,
      loserSeat: view?.loserSeat ?? null,
    };
  }

  private sendHands(): void {
    for (let i = 0; i < this.seats.length; i++) this.sendHandTo(i);
  }

  private sendHandTo(seatIdx: number): void {
    if (!this.game) return;
    const seat = this.seats[seatIdx];
    seat?.client?.send('hand', { cards: this.game.players[seatIdx]!.hand });
  }

  private removeFromLobby(seatIdx: number): void {
    const seat = this.seats[seatIdx]!;
    this.seats.splice(seatIdx, 1);
    if (seat.userId === this.adminUserId && this.seats.length > 0) this.adminUserId = this.seats[0]!.userId;
    this.broadcastEvents([{ type: 'playerLeft', userId: seat.userId, seat: seatIdx }]);
    this.syncLobby();
    void this.updateMetadata();
  }

  /** Seat indexes shift in lobby operations — cheapest correct move is a full resync. */
  private syncLobby(): void {
    for (const s of this.seats) s.client?.send('stateFull', this.buildStateFull(s.userId));
  }

  /** Seats that consented-left mid-game before going out, as seat → leave order. */
  private leaverSeats(): Map<number, number> {
    const m = new Map<number, number>();
    this.seats.forEach((s, i) => {
      if (s.leftConsented) m.set(i, s.leftOrder);
    });
    return m;
  }

  private seatOf(client: Client): number {
    const userId = (client.userData as { userId?: string } | undefined)?.userId;
    return this.seats.findIndex((s) => s.userId === userId);
  }

  private sendError(client: Client, code: ServerErrorCode | string, message: string): void {
    client.send('error', { code, message });
  }

  private noteConnectivity(): void {
    this.allDisconnectedSince = this.seats.every((s) => !s.connected) ? (this.allDisconnectedSince ?? Date.now()) : null;
  }

  private sweepAbandoned(): void {
    if (this.phase !== 'playing' || this.allDisconnectedSince === null) return;
    if (Date.now() - this.allDisconnectedSince < config.abandonedAfterMs) return;
    void store.recordGameResult({
      roomId: this.roomId, deckSize: this.deckSize, status: 'ABANDONED', loserUserId: null, participants: [],
    }).catch(() => undefined);
    void this.disconnect();
  }

  private async updateMetadata(): Promise<void> {
    await this.setMetadata({
      name: this.displayName,
      deckSize: this.deckSize,
      turnTimerSec: this.turnTimerSec,
      playerCount: this.seats.length,
      maxPlayers: this.maxPlayersCfg,
      phase: this.phase,
      joinCode: this.joinCode, // rooms with a code are always setPrivate в†’ never listed
    });
  }
}
