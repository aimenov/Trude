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
  ClientMessageName, EventBatch, ServerErrorCode, StateFull, WireEvent, WirePlayer,
} from '../protocol.js';
import type { Store, UnlockedAchievement } from '../store/store.js';

interface SeatInfo {
  userId: string;
  nickname: string;
  avatar: string;
  connected: boolean;
  autoPilot: boolean;
  consecutiveTimeouts: number;
  lastClientSeq: number;
  lastReactionAt: number;
  client: Client | null;
}

interface RoomOptions {
  token?: string;
  name?: string;
  private?: boolean;
  deckSize?: DeckSize;
  turnTimerSec?: 15 | 30 | 60;
  maxPlayers?: number;
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
  private currentDeadlineTs = 0;
  private allDisconnectedSince: number | null = null;

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
    if (this.phase !== 'lobby') throw new Error('GAME_IN_PROGRESS');
    if (this.seats.length >= this.maxPlayersCfg) throw new Error('Room is full');

    if (this.seats.length === 0) this.adminUserId = claims.sub;
    const seat: SeatInfo = {
      userId: claims.sub, nickname: claims.nick, avatar: claims.avatar,
      connected: true, autoPilot: false, consecutiveTimeouts: 0,
      lastClientSeq: -1, lastReactionAt: 0, client,
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
        seat.connected = false;
        seat.client = null;
        seat.autoPilot = true;
        this.noteConnectivity();
        this.broadcastEvents([
          { type: 'playerConnection', seat: seatIdx, connected: false },
          { type: 'autoPilot', seat: seatIdx, on: true },
        ]);
        this.rearmIfActor(seatIdx);
      } else if (this.phase === 'finished') {
        // Seat indexes must stay aligned with the finished game's state until the
        // room resets; returnToLobby drops disconnected seats.
        seat.connected = false;
        seat.client = null;
        this.noteConnectivity();
        this.broadcastEvents([{ type: 'playerConnection', seat: seatIdx, connected: false }]);
      } else {
        this.removeFromLobby(seatIdx);
      }
      return;
    }

    seat.connected = false;
    seat.client = null;
    this.noteConnectivity();
    if (this.phase === 'playing') {
      this.broadcastEvents([{ type: 'playerConnection', seat: seatIdx, connected: false }]);
      this.rearmIfActor(seatIdx);
    }

    try {
      const rejoined = await this.allowReconnection(
        client, this.phase === 'lobby' ? config.reconnectionSecondsLobby : config.reconnectionSeconds,
      );
      seat.connected = true;
      seat.client = rejoined;
      seat.autoPilot = false;
      seat.consecutiveTimeouts = 0;
      seat.lastClientSeq = -1; // reconnecting clients restart their clientSeq counter
      rejoined.userData = { userId: seat.userId };
      this.noteConnectivity();
      rejoined.send('stateFull', this.buildStateFull(seat.userId));
      if (this.phase === 'playing') {
        this.broadcastEvents([
          { type: 'playerConnection', seat: seatIdx, connected: true },
          { type: 'autoPilot', seat: seatIdx, on: false },
        ]);
        this.rearmIfActor(seatIdx);
      }
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
    for (const s of this.seats) s.consecutiveTimeouts = 0;
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
    const hasResolution = engineEvents.some((e) => e.type === 'checkResult' || e.type === 'fourDiscarded');
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
          const deadlineTs = this.armTurnTimer(e.seat, hasResolution);
          wire.push({ type: 'turnStarted', seat: e.seat, phase: e.phase, mustCheck: e.mustCheck, deadlineTs });
          break;
        }
        case 'gameOver': {
          this.cancelTimer();
          wire.push({
            type: 'gameOver', loserSeat: e.loserSeat,
            loserUserId: this.seats[e.loserSeat]!.userId, jokerCard: e.jokerCard,
            placements: e.placements.map((p) => ({ userId: p.playerId, seat: p.seat, placement: p.placement })),
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

  private armTurnTimer(actorSeat: number, afterResolution: boolean): number {
    this.cancelTimer();
    const seat = this.seats[actorSeat]!;
    const base = (!seat.connected || seat.autoPilot) ? config.disconnectedTurnMs : this.turnTimerSec * 1000;
    const grace = afterResolution ? config.animationGraceMs : 0;
    const deadline = Date.now() + base + grace;
    this.currentDeadlineTs = deadline;
    const nonce = ++this.timerNonce;
    this.clock.setTimeout(() => {
      if (nonce !== this.timerNonce || this.phase !== 'playing') return;
      this.applyEngineAction({ type: 'timeout' }, null);
    }, base + grace);
    return deadline;
  }

  private cancelTimer(): void {
    this.timerNonce++;
  }

  /** Re-arms the running turn timer when the current actor's connectivity changes. */
  private rearmIfActor(seatIdx: number): void {
    if (!this.game || this.game.phase.kind === 'over') return;
    if (this.game.phase.seat !== seatIdx) return;
    const seat = this.seats[seatIdx]!;
    const remaining = Math.max(this.currentDeadlineTs - Date.now(), 0);
    const cap = (!seat.connected || seat.autoPilot) ? config.disconnectedTurnMs : this.turnTimerSec * 1000;
    const ms = Math.min(remaining, cap);
    this.currentDeadlineTs = Date.now() + ms;
    const nonce = ++this.timerNonce;
    this.clock.setTimeout(() => {
      if (nonce !== this.timerNonce || this.phase !== 'playing') return;
      this.applyEngineAction({ type: 'timeout' }, null);
    }, ms);
    this.broadcastEvents([{
      type: 'turnStarted', seat: seatIdx,
      phase: this.game.phase.kind as 'lead' | 'respond',
      mustCheck: this.game.phase.kind === 'respond' && this.game.phase.mustCheck,
      deadlineTs: this.currentDeadlineTs,
    }]);
  }

  private async finishGame(e: Extract<EngineEvent, { type: 'gameOver' }>): Promise<void> {
    this.phase = 'finished';
    const game = this.game!;
    let unlocked = new Map<string, UnlockedAchievement[]>();
    try {
      unlocked = await store.recordGameResult({
        roomId: this.roomId, deckSize: this.deckSize, status: 'FINISHED',
        loserUserId: this.seats[e.loserSeat]!.userId,
        participants: e.placements.map((p) => ({
          userId: p.playerId, placement: p.placement, stats: game.players[p.seat]!.stats,
        })),
      });
    } catch (err) {
      console.error('Failed to persist game result', err);
    }
    for (const [userId, achievements] of unlocked) {
      const seat = this.seats.find((s) => s.userId === userId);
      for (const a of achievements) seat?.client?.send('achievementUnlocked', a);
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
      turn: view?.turn ? { ...view.turn, deadlineTs: this.currentDeadlineTs } : null,
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
