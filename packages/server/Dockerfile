# Build from the repo root: docker build -f packages/server/Dockerfile .
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
COPY packages/engine/package.json packages/engine/
COPY packages/server/package.json packages/server/
RUN npm ci --workspaces --include-workspace-root
COPY tsconfig.base.json ./
COPY packages/engine packages/engine
COPY packages/server packages/server
RUN cd packages/server && npx prisma generate
RUN npm run build --workspace @trude/engine \
    && npm run build --workspace @trude/server

FROM node:22-alpine
ENV NODE_ENV=production
WORKDIR /app
COPY package.json package-lock.json ./
COPY packages/engine/package.json packages/engine/
COPY packages/server/package.json packages/server/
RUN npm ci --workspaces --include-workspace-root --omit=dev
COPY --from=build /app/packages/engine/dist packages/engine/dist
COPY --from=build /app/packages/server/dist packages/server/dist
# Prisma query engine + generated client from the build stage (nested under the workspace)
COPY --from=build /app/packages/server/node_modules/.prisma packages/server/node_modules/.prisma
COPY --from=build /app/packages/server/node_modules/@prisma/client packages/server/node_modules/@prisma/client
COPY packages/server/prisma packages/server/prisma
EXPOSE 2567
USER node
CMD ["node", "packages/server/dist/index.js"]
