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
  /** Grace added to the next deadline after a reveal/pickup batch so the on-screen
   *  timer starts roughly when the client's animation queue drains. */
  animationGraceMs: 2_500,
  /** Consecutive timeouts before a connected player is flagged autopilot. */
  autopilotAfterTimeouts: 3,
  /** Dispose an all-disconnected mid-game room after this long (ms). */
  abandonedAfterMs: 5 * 60_000,
  /** Return to lobby this long after gameOver (ms). */
  rematchLobbyDelayMs: 10_000,
} as const;
