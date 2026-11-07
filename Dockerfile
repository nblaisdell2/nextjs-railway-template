# syntax=docker/dockerfile:1
#
# Railway builds this file on every deploy (the web service in
# .railway/railway.ts uses the DOCKERFILE builder). It also builds locally:
#   docker build -t my-app .

# ---- deps: install node_modules ----
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json* ./
# Use the lockfile for reproducible installs when present; fall back to a plain
# install if it hasn't been generated yet.
RUN if [ -f package-lock.json ]; then npm ci; else npm install; fi

# ---- builder: build the standalone Next.js server ----
FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ENV NEXT_TELEMETRY_DISABLED=1
# No DATABASE_URL is needed here: lib/db.ts creates its pool lazily.
RUN npm run build

# ---- runner: minimal runtime image ----
FROM node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
# Railway injects PORT at runtime; 3000 is only the fallback for `docker run`.
ENV PORT=3000
ENV HOSTNAME=0.0.0.0
# npm runs as the non-root user for the pre-deploy `npm run migrate`; keep its
# cache somewhere writable and skip the update check.
ENV NPM_CONFIG_CACHE=/tmp/.npm
ENV NPM_CONFIG_UPDATE_NOTIFIER=false

# Run as a non-root user.
RUN addgroup --system --gid 1001 nodejs \
  && adduser --system --uid 1001 nextjs

# The standalone output bundles a minimal node_modules (including pg),
# package.json, and server.js.
COPY --from=builder /app/public ./public
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

# Migrations ship in the image: Railway runs `npm run migrate` as the
# pre-deploy command, and `npm run railway:migrate` runs it over SSH.
COPY --from=builder --chown=nextjs:nodejs /app/db ./db

USER nextjs
EXPOSE 3000

# server.js is emitted by Next.js standalone output and listens on $PORT.
CMD ["node", "server.js"]
