# Trude Wire Protocol — Canonical Message Catalog

**This document is the contract.** The TypeScript types in `packages/engine` / `packages/server` and the Dart freezed unions in `app/` are generated/written from this file. Any protocol change lands here first.

Transport: Colyseus 0.16 room messages (msgpack envelope). All payloads below are plain JSON objects. **`@colyseus/schema` is NOT used for game state** — the synced schema is empty; everything travels as messages.

## Principles

1. **Hidden information is absent from the wire, not filtered.** Opponents' hands = counts. Face-down pile cards = counts + claimed rank. Card faces appear on the wire only in: your own `hand` snapshot, a `checkResult` reveal, `fourDiscarded`, and `gameOver.jokerCard`.
2. **Card ids are opaque strings** (`"c17"`) assigned AFTER the shuffle. Face-down opponent cards are animated with synthetic keys (seat + ordinal), never real ids.
3. **Events drive animations; state snapshots drive resync.** After every applied action the server broadcasts one ordered event batch tagged with `actionCount`. `stateFull` is sent only on join/reconnect.
4. **Idempotency:** every client action carries `{ actionCount, clientSeq }`. `actionCount` = last batch the client has seen (server rejects stale with `STALE_ACTION`); `clientSeq` dedupes retries.

## Shared scalar types

| Type | Values |
|---|---|
| `Rank` | `"2" "3" "4" "5" "6" "7" "8" "9" "10" "J" "Q" "K" "A"` (2–5 only in the 53 deck) |
| `Suit` | `"C" "D" "H" "S"` |
| `Card` | `{ id: string, rank: Rank \| "JOKER", suit?: Suit }` |
| `DeckSize` | `37 \| 53` (37 = ranks 6–A + joker) |
| `Phase` | `"lead" \| "respond"` |
| `deadlineTs` | epoch ms, server clock; client renders via smoothed ping/pong offset |

## Client → Server

All actions include `actionCount: number` and `clientSeq: number` (omitted from tables).

| Message | Payload | Valid when | Errors |
|---|---|---|---|
| `configureRoom` | `{ deckSize?: DeckSize, turnTimerSec?: 15\|30\|60, maxPlayers?: number }` | lobby, sender is admin | `NOT_ADMIN`, `BAD_CONFIG` |
| `startGame` | `{}` | lobby, admin, ≥2 seated, players ≤ deck cap (37→6, 53→8) | `NOT_ADMIN`, `NOT_ENOUGH_PLAYERS`, `TOO_MANY_PLAYERS` |
| `kickPlayer` | `{ userId: string }` | lobby only, admin, target ≠ admin | `NOT_ADMIN`, `BAD_TARGET` |
| `throwCards` | `{ cardIds: string[], rank?: Rank }` | your turn. 1–3 own cards. `rank` REQUIRED on a fresh pile (lead); on a live pile it must be omitted or equal the pile rank | `NOT_YOUR_TURN`, `BAD_CARDS`, `RANK_REQUIRED`, `RANK_MISMATCH`, `RANK_DEAD`, `RANK_JOKER`, `MUST_CHECK` |
| `check` | `{ flipIndex: number }` | your respond turn, pile non-empty, `flipIndex < lastThrowCount` | `NOT_YOUR_TURN`, `BAD_FLIP_INDEX`, `NOTHING_TO_CHECK` |
| `requestSeatSwap` | `{ targetUserId: string }` | **lobby only in v1**, target seated | `BAD_TARGET`, `SWAP_PENDING` |
| `respondSeatSwap` | `{ accept: boolean }` | a pending request targets you (20 s wall-clock expiry) | `NO_PENDING_SWAP` |
| `reaction` | `{ emoji: string }` | anytime; allowlist of 8; ≥1.5 s since your last | `BAD_EMOJI`, `RATE_LIMITED` |
| `ping` | `{ t: number }` | anytime | — |

Reaction allowlist v1: `joy` `sob` `angry` `monocle` `clown` `fire` `thumbsup` `scream`.

## Server → Client

### Continuous / resync

| Message | Target | Payload |
|---|---|---|
| `stateFull` | one client | `{ actionCount, phase: "lobby"\|"playing"\|"finished", config: { deckSize, turnTimerSec, maxPlayers }, roomCode?: string, players: [{ userId, nickname, avatar, seat, cardCount, connected, autoPilot, isOut, isAdmin }], pile: { rank: Rank\|null, totalCount, groups: [{ seat, count }] }, lastThrowSeat: number\|null, mustCheck: boolean, retiredRanks: Rank[], discarded: Card[], turn: { seat, phase: Phase, deadlineTs }\|null, hand: Card[], lastResolution: EventBatch\|null, loserSeat: number\|null }` |
| `hand` | one client | `{ cards: Card[] }` — full snapshot after every change to YOUR hand (deal, throw, pickup, quad discard) and on reconnect |
| `pong` | one client | `{ t: number, serverT: number }` |

`lastResolution` is the most recent reveal/pickup event batch with its `actionCount`; a reconnecting client replays it if unseen (never miss a verdict).

### Event batches

Broadcast as `events { actionCount: number, events: Event[] }` — ordered; client's AnimationQueue paces rendering. Server adds ~2.5 s animation grace to `deadlineTs` after reveal/pickup batches.

| Event | Payload | Notes |
|---|---|---|
| `gameStarted` | `{ deckSize, seatOrder: [{ seat, userId }], handCounts: number[] }` | deal animation runs off this |
| `turnStarted` | `{ seat, phase: Phase, mustCheck: boolean, deadlineTs }` | after every resolution; drives turn ring + action bar |
| `cardsThrown` | `{ seat, count: 1\|2\|3, rank: Rank, isLead: boolean }` | no card ids — flights use synthetic keys |
| `checkResult` | `{ checkerSeat, targetSeat, flipIndex, flipped: Card, matched: boolean, pickerSeat, pickedCount, nextLeadSeat }` | the reveal set piece; `nextLeadSeat` is authoritative (winner-leads rule lives server-side) |
| `fourDiscarded` | `{ seat, rank: Rank, cards: Card[] }` | public celebration; rank retires |
| `playerOut` | `{ seat }` | safe! |
| `autoActed` | `{ seat, kind: "lead"\|"check" }` | timeout/autopilot acted for a player |
| `autoPilot` | `{ seat, on: boolean }` | badge |
| `playerConnection` | `{ seat, connected: boolean }` | reconnecting plug icon; disconnected players get shortened 10 s timer |
| `seatSwapRequested` | (target client only) `{ fromSeat, fromUserId }` | |
| `seatSwapResolved` | `{ seatA, seatB, accepted: boolean }` | |
| `playerJoined` / `playerLeft` | `{ userId, nickname, avatar, seat }` / `{ userId, seat }` | lobby |
| `roomConfigured` | `{ deckSize, turnTimerSec, maxPlayers }` | |
| `gameOver` | `{ loserSeat, loserUserId, jokerCard: Card, placements: [{ userId, seat, placement }], stats: { [userId]: { liesSurvived, liesCaught, checksWon, checksLost, cardsPickedUp, quadsDiscarded, jokerPassed, maxHandSize, truthfulThrows, lyingThrows, firstOut, wasEverCaught, jokerSmuggles } } }` | stats is a map keyed by userId; results screen; room returns to lobby phase afterwards, seats kept |
| `achievementUnlocked` | (one client) `{ key, title, description }` | toast deferred by AnimationQueue |
| `reaction` | `{ seat, emoji }` | burst overlay |
| `error` | (one client) `{ code: string, message: string }` | codes listed above + `STALE_ACTION`, `NOT_IN_ROOM` |

## HTTP API (Express, same origin)

| Route | Body → Response |
|---|---|
| `POST /auth/guest` | `{ deviceId, nickname }` → `{ token, userId, nickname, avatar }` |
| `POST /auth/refresh` | (Bearer) → `{ token }` |
| `POST /auth/google` / `POST /auth/apple` | `{ idToken }` (Bearer = current guest) → `{ token, userId, merged: boolean }` |
| `GET /me` | (Bearer) → profile + lifetime stats |
| `PATCH /me` | `{ nickname?, avatar? }` (profanity-checked) → profile |
| `GET /me/achievements` | (Bearer) → `{ unlocked: [...], catalog: [{ key, title, description, threshold, progress }] }` |
| `GET /rooms/by-code/:code` | → `{ roomId }` or 404 |
| `GET /health` | → `{ ok: true }` |

## Room lifecycle notes

- Public rooms listed via Colyseus `LobbyRoom`; `setPrivate(true)` while `phase === "playing"`, restored to public when the room returns to lobby (rematch).
- Private rooms: 6-char code, alphabet `23456789ABCDEFGHJKMNPQRSTUVWXYZ` (no 0/O/1/I/L).
- Mid-game join rejected; reconnection keyed by `userId` with `allowReconnection(client, 120)`.
- Disconnect policy: autopilot forever, cards never redistributed; room disposes (game `ABANDONED`) only when ALL players are gone > 5 min.
