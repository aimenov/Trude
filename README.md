# Trude — Trust or Deceive

Real-time multiplayer bluffing card game (Android + iOS, web later). A variant of the
Russian game "Verish' ne verish'": throw 1–3 cards face-down claiming a rank; the next
player trusts and continues, or flips one card to call the bluff; the check's loser picks
up the pile; four-of-a-kinds retire from the game; whoever ends up holding the joker loses.

## Layout

| Path | What |
|---|---|
| `docs/protocol.md` | **The wire contract.** Every message between client and server. Change it here first. |
| `packages/engine` | Pure, deterministic TypeScript rules engine. No I/O, seeded PRNG, `reduce(state, action) → { state, events }`. |
| `packages/server` | Colyseus 0.16 host: rooms, matchmaking, guest JWT auth, achievements, persistence. |
| `app/` | Flutter client (portrait, RU/EN). |
| `deploy/` | Docker Compose + Caddy for a single-VPS deployment. |

## Development

```bash
npm install
npm run build --workspace @trude/engine   # server imports the built engine
npm test                                  # engine unit/property/fuzz + server integration suites
npx tsx packages/server/src/index.ts      # dev server on :2567
```

Flutter client (SDK at least 3.44): `cd app && flutter run -d chrome` against a local server.

Heavier fuzzing: `FUZZ_GAMES=100 npx vitest run test/fuzz.test.ts` in `packages/engine`
(plays full random games, asserting engine invariants after every action).

## Design pillars

- **The engine is pure and the room is a shell.** All rules live in `packages/engine`;
  Colyseus translates messages to engine actions and streams the resulting events.
- **Hidden information is absent from the wire, not filtered.** Opponents' hands and
  face-down pile cards travel only as counts; card ids are opaque and assigned post-shuffle.
  The server integration test scans every received payload and fails on any card face
  outside the explicitly public paths.
- **Determinism.** Same seed + action log ⇒ identical replay: bug reports are replayable
  and the fuzzer's failures shrink.
- Games are not provably finite (two immortal bluffers can cycle); random/human play
  terminates in practice. Anything driving the game programmatically (bots, tests) must
  use randomized policies — deterministic policies livelock.
