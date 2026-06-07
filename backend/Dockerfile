# ============================================================
# Lime AI Backend — Dockerfile (multi-stage)
# ============================================================

# ── Build stage ────────────────────────────
FROM node:20-alpine AS builder

WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# ── Runtime stage ──────────────────────────
FROM node:20-alpine AS runtime

# Security: run as non-root
RUN addgroup -S limeai && adduser -S limeai -G limeai

WORKDIR /app

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./

# Create logs dir
RUN mkdir -p logs && chown -R limeai:limeai /app

USER limeai

EXPOSE 3001

HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3001/api/v1/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

CMD ["node", "dist/server.js"]
