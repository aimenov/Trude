const dev = process.env['NODE_ENV'] !== 'production';

function required(name: string, devDefault: string): string {
  const v = process.env[name];
  if (v) return v;
  if (dev) return devDefault;
  throw new Error(`Missing required env var ${name}`);
}

export const config = {
  dev,
  port: Number(process.env['PORT'] ?? 2567),
  jwtSecret: required('JWT_SECRET', 'trude-dev-secret-do-not-use-in-prod'),
  tokenTtl: '30d',
  /** Reconnection window (seconds) for an unexpected drop during a game. */
  reconnectionSeconds: 120,
  reconnectionSecondsLobby: 30,
  /** Shortened decision timer for disconnected/autopilot players. */
  disconnectedTurnMs: 10_000,
  /** How long the current actor may stay disconnected before their running turn
   *  is shortened to disconnectedTurnMs. Blips under this never touch the timer. */
  disconnectedGraceMs: 5_000,
  /** Per-event grace (ms) added to the next deadline so the visible timer starts
   *  roughly when the client's animation queue drains. Mirrors the client
   *  MotionSpec choreography; combined in rooms/animationGrace.ts. */
  animationGrace: {
    /** Opening deal choreography. */
    dealMs: 2_500,
    /** Reveal set piece (flip + verdict) before the pickup starts. */
    checkResultMs: 2_700,
    /** Pickup flight estimate: base + perCard * min(pickedCount, cardCap), capped. */
    pickupBaseMs: 550,
    pickupPerCardMs: 25,
    pickupCardCap: 24,
    pickupCapMs: 1_600,
    /** Quad-discard celebration, per event. */
    fourDiscardedMs: 1_200,
    /** "Safe!" flourish, per event. */
    playerOutMs: 600,
    /** Settle buffer added once whenever any grace applies. */
    bufferMs: 250,
    /** Hard cap for a single batch. */
    totalCapMs: 8_000,
  },
  /** Consecutive timeouts before a connected player is flagged autopilot. */
  autopilotAfterTimeouts: 3,
  /** Dispose an all-disconnected mid-game room after this long (ms). */
  abandonedAfterMs: 5 * 60_000,
  /** Return to lobby this long after gameOver (ms). */
  rematchLobbyDelayMs: 10_000,
} as const;
