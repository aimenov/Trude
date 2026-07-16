import { createServer } from 'node:http';
import express from 'express';
import { LobbyRoom, Server, matchMaker } from 'colyseus';
import { WebSocketTransport } from '@colyseus/ws-transport';
import { authRoutes } from './auth/routes.js';
import { config } from './config.js';
import { TrudeRoom, setStore } from './rooms/TrudeRoom.js';
import { MemoryStore } from './store/store.js';

export async function createApp(): Promise<{ app: express.Express; gameServer: Server }> {
  let store;
  if (process.env['DATABASE_URL']) {
    const { PrismaStore } = await import('./store/prismaStore.js');
    store = new PrismaStore();
    console.log('Persistence: Postgres (Prisma)');
  } else {
    store = new MemoryStore();
    console.log('Persistence: in-memory (set DATABASE_URL for Postgres)');
  }
  setStore(store);

  const app = express();
  // Browser clients (Flutter web) call these routes cross-origin. Auth is via
  // Bearer tokens (no cookies), so a wildcard origin is safe.
  app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Methods', 'GET,POST,PATCH,OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Content-Type, Authorization');
    res.header('Access-Control-Max-Age', '86400');
    if (req.method === 'OPTIONS') {
      res.sendStatus(204);
      return;
    }
    next();
  });
  app.use(express.json());
  app.use(authRoutes(store));

  app.get('/health', (_req, res) => res.json({ ok: true }));

  app.get('/rooms/by-code/:code', async (req, res) => {
    const code = String(req.params['code']).toUpperCase();
    const rooms = await matchMaker.query({ name: 'trude' });
    const room = rooms.find((r) => (r.metadata as { joinCode?: string } | undefined)?.joinCode === code);
    if (!room) return res.status(404).json({ error: 'NOT_FOUND' });
    return res.json({ roomId: room.roomId });
  });

  const httpServer = createServer(app);
  const gameServer = new Server({
    transport: new WebSocketTransport({ server: httpServer }),
  });

  gameServer.define('lobby', LobbyRoom);
  gameServer.define('trude', TrudeRoom).enableRealtimeListing();

  return { app, gameServer };
}

const isMain = process.argv[1]?.replace(/\\/g, '/').endsWith('index.js') === true
  || process.argv[1]?.replace(/\\/g, '/').endsWith('src/index.ts') === true;

if (isMain) {
  void createApp().then(({ gameServer }) =>
    gameServer.listen(config.port).then(() => {
      console.log(`Trude server listening on :${config.port}`);
    }),
  );
}
