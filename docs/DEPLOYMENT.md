# Lime AI Platform — Complete Deployment & Architecture Guide

## Table of Contents

1. [Architecture Overview](#architecture)
2. [How Networking Works](#networking)
3. [Deployment Guide](#deployment)
4. [Security Implementation](#security)
5. [Monetization Setup](#monetization)
6. [CI/CD Pipeline](#cicd)

---

## 1. Architecture Overview {#architecture}

```
Roblox Studio Plugin
  │  (HttpService HTTPS POST with JWT Bearer token)
  ▼
Nginx Reverse Proxy (SSL termination, rate limiting)
  │
  ▼
Node.js Backend API (Express + TypeScript)
  ├── Auth Middleware (JWT verification)
  ├── Rate Limiter (per-plan enforcement)
  ├── Usage Tracker (DB writes)
  │
  ▼
Anthropic Claude API (server-to-server only)
  │  (streaming SSE response)
  ▼
Backend Stream Proxy
  │  (relays SSE chunks to plugin)
  ▼
Roblox Studio Plugin (displays response)
  │
  ▼
PostgreSQL (messages, users, usage, billing persisted)
```

**Critical security boundary:** The Anthropic API key lives ONLY in the backend's
environment variables. It is never sent to, stored in, or accessible from the
Roblox Studio plugin.

---

## 2. How Networking Works {#networking}

### 2.1 Roblox Studio → Backend

Roblox Studio plugins use `HttpService:RequestAsync()` to make HTTP calls.
This is standard HTTPS — identical to any web client making API requests.

```lua
-- Plugin sends a request like this:
local response = HttpService:RequestAsync({
  Url = "https://api.limeai.dev/api/v1/chat",
  Method = "POST",
  Headers = {
    ["Content-Type"] = "application/json",
    ["Authorization"] = "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
  },
  Body = HttpService:JSONEncode({
    message = "Write a DataStore script for player currency",
    conversationId = "uuid-from-previous-response",
    stream = false
  })
})

-- Response arrives as a standard HTTP response:
local data = HttpService:JSONDecode(response.Body)
-- data.content = Claude's complete response
-- data.conversationId = conversation UUID for next message
```

**Why `stream = false` in the plugin?**
Roblox's HttpService does NOT support Server-Sent Events (SSE) or chunked
transfer encoding reading mid-stream. The plugin polls a non-streaming endpoint
that waits for the full response before returning. For a streaming experience,
the plugin could poll a status endpoint repeatedly, but the simpler non-streaming
approach works well for most Studio use cases.

### 2.2 Backend → Claude API

The backend uses the official Anthropic Node.js SDK:

```typescript
import Anthropic from '@anthropic-ai/sdk';

const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY,  // NEVER exposed to client
});

// Non-streaming (for plugin requests):
const response = await anthropic.messages.create({
  model: 'claude-sonnet-4-20250514',
  max_tokens: 4096,
  system: ROBLOX_SYSTEM_PROMPT,
  messages: [
    // Previous conversation history from DB
    { role: 'user', content: 'Previous message' },
    { role: 'assistant', content: 'Previous reply' },
    // New message
    { role: 'user', content: 'Write a DataStore script for player currency' },
  ],
});

const aiText = response.content[0].text;
const tokensUsed = response.usage.output_tokens;

// Streaming (for web dashboard or future SSE support):
const stream = anthropic.messages.stream({ ... });
for await (const event of stream) {
  if (event.type === 'content_block_delta') {
    // Write SSE chunk to HTTP response
    res.write(`data: ${JSON.stringify({ delta: event.delta.text })}\n\n`);
  }
}
```

### 2.3 Conversation Memory

Every message is stored in PostgreSQL. Before each Claude request, the backend
loads the last 20 messages from the conversation and includes them in the
`messages` array. This gives Claude full context of the conversation.

```
User sends message
  → Backend loads conversation history from DB (up to 20 msgs)
  → Backend builds: [history..., newUserMessage]
  → Sends to Claude API with full context
  → Claude responds with awareness of all previous exchanges
  → Response saved to DB
  → Response returned to plugin
```

### 2.4 Code Insertion into Studio

When Claude returns code blocks (wrapped in triple backticks), the plugin parses
them and creates actual Roblox script objects:

```lua
-- User clicks "Insert as Script"
local script = Instance.new("Script")
script.Source = extractedCode  -- the Luau code from Claude's response
script.Name = "LimeAI_Generated"
script.Parent = workspace  -- or selected instance

-- Optionally open in Script Editor
ScriptEditorService:OpenScriptDocumentAsync(script)
```

---

## 3. Deployment Guide {#deployment}

### Prerequisites
- A VPS or cloud server (minimum 2GB RAM, 2 vCPUs)
- Docker and Docker Compose installed
- A domain name with DNS configured
- Stripe account (for billing)
- Anthropic API key

### Recommended Providers
- **DigitalOcean** — $24/mo droplet, easy setup, managed PostgreSQL available
- **AWS** — EC2 t3.small + RDS PostgreSQL for production scale
- **Railway** — Easiest deployment, auto-handles PostgreSQL and SSL
- **Render** — Good free tier for testing, managed DB available

### Step 1: Server Setup

```bash
# Clone the repo
git clone https://github.com/yourorg/limeai-platform.git
cd limeai-platform

# Copy environment file
cp backend/.env.example backend/.env

# Generate JWT secrets
openssl rand -hex 64  # Use output for JWT_ACCESS_SECRET
openssl rand -hex 64  # Use output for JWT_REFRESH_SECRET

# Edit .env with all values
nano backend/.env
```

### Step 2: SSL Certificates

```bash
# Install certbot on host (for initial certificate)
sudo apt install certbot

# Get certificates for both domains
sudo certbot certonly --standalone \
  -d limeai.dev \
  -d api.limeai.dev \
  --email your@email.com \
  --agree-tos

# Copy to docker SSL volume
cp -r /etc/letsencrypt docker/ssl/
```

### Step 3: Database Init

```bash
# Start just PostgreSQL first
docker compose -f docker/docker-compose.yml up postgres -d

# Wait for it to be healthy, then schema auto-runs from initdb.d/
# Check:
docker logs limeai_postgres | tail -20
```

### Step 4: Deploy Everything

```bash
# Build and start all services
docker compose -f docker/docker-compose.yml up -d --build

# Check all services are healthy
docker compose ps

# View logs
docker compose logs -f backend
```

### Step 5: Verify

```bash
# Test health endpoint
curl https://api.limeai.dev/api/v1/health

# Should return:
# {"status":"ok","timestamp":"2025-..."}

# Test dashboard
open https://limeai.dev
```

### Scaling Strategy

For high traffic:
1. Add a read replica PostgreSQL for read-heavy queries
2. Use Redis for session storage and rate limiting (replace in-memory)
3. Put Cloudflare in front for CDN + DDoS protection
4. Use Anthropic's batch API for non-realtime workloads
5. Horizontal scale the backend behind a load balancer

---

## 4. Security Implementation {#security}

### Authentication Flow
```
1. User logs in → backend issues 15-minute JWT access token + 30-day refresh token
2. Plugin stores refresh token in plugin:SetSetting() (sandboxed per-plugin storage)
3. On each request, plugin sends JWT in Authorization header
4. If JWT expired, plugin uses refresh token to get new access token (silent refresh)
5. Refresh tokens are rotated on each use (prevents token theft reuse)
6. All tokens stored as hashes in DB — plain tokens never stored
```

### Secrets Management
```
✓ ANTHROPIC_API_KEY — backend .env only, never in code, never in responses
✓ JWT secrets — backend .env only
✓ Database password — Docker secrets / .env
✓ Stripe keys — backend .env only
✗ NEVER commit .env to git (add to .gitignore)
✗ NEVER log API keys
✗ NEVER return API keys in any API response
```

### Input Validation
All API inputs validated with Zod schemas before processing:
- Email format validated, lowercased, trimmed
- Message length capped at 32,000 characters
- UUID format validated for IDs
- JSON bodies size-limited to 1MB
- SQL injection prevented by parameterized queries (pg driver)

### Rate Limiting Layers
```
Layer 1: Nginx rate limits (IP-based, blocks DDoS)
  - /api/v1/auth/*  → 10 req/min per IP
  - /api/v1/*       → 30 req/min per IP

Layer 2: express-rate-limit (application-level)
  - Global: 300 req/15min per IP
  - Auth: 20 req/hour per IP

Layer 3: Plan-based limits (per user per day/month)
  - Free:       20/day, 100/month
  - Pro:        200/day, 5000/month
  - Team:       1000/day, 25000/month
  - Enterprise: unlimited
```

### Additional Security Measures
- HTTPS everywhere (TLS 1.2+ only)
- HSTS headers (1 year, includeSubDomains)
- Helmet.js security headers (CSP, X-Frame-Options, etc.)
- CORS restricted to known origins
- Roblox plugin has no origin header → treated as trusted client
- Banned users blocked at middleware level
- All admin actions logged to audit_logs table
- bcrypt password hashing (cost factor 12)
- Email verification required for full access

---

## 5. Monetization Setup {#monetization}

### Stripe Setup

1. Create products in Stripe Dashboard:
   - Pro: $19/month recurring
   - Team: $49/month recurring
   - Enterprise: $199/month recurring

2. Copy Price IDs (price_xxx) into database:
```sql
UPDATE subscription_plans
SET stripe_price_id = 'price_XXXX'
WHERE name = 'pro';
```

3. Set webhook endpoint in Stripe:
   - URL: `https://api.limeai.dev/webhooks/stripe`
   - Events: `checkout.session.completed`, `customer.subscription.deleted`,
     `invoice.payment_succeeded`, `invoice.payment_failed`

4. Copy webhook signing secret to `STRIPE_WEBHOOK_SECRET` in .env

### Trial System
Add a trial for Pro:
```typescript
// In create-checkout route
await stripe.checkout.sessions.create({
  ...
  subscription_data: {
    trial_period_days: 7,  // 7-day free trial
  },
});
```

---

## 6. CI/CD Pipeline {#cicd}

### GitHub Actions

```yaml
# .github/workflows/deploy.yml
name: Deploy to Production

on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: cd backend && npm ci && npm run build

  deploy:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy to server
        uses: appleboy/ssh-action@master
        with:
          host: ${{ secrets.SERVER_HOST }}
          username: ${{ secrets.SERVER_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          script: |
            cd /opt/limeai
            git pull origin main
            docker compose -f docker/docker-compose.yml up -d --build
            docker system prune -f
```

---

## Plugin Distribution

To publish the Roblox Studio plugin:

1. Open Roblox Studio
2. Create a new plugin project
3. Copy `plugin/src/main.lua` into a Script in ServerScriptService
4. Set the API_BASE_URL at the top of main.lua to your deployed backend URL
5. Plugin → Publish to Roblox (for public) or save locally as .rbxmx file
6. Users install from Roblox Creator Store

The plugin file structure in Studio:
```
ServerScriptService/
  LimeAI_Plugin (Script, RunContext: Plugin)
    └── main.lua content here
```

---

## Cost Estimates

At 1,000 Pro users ($19/month each) = $19,000 MRR

Claude API costs at average usage:
- Pro user: ~5,000 req/month × avg 500 input + 1000 output tokens
- = 2.5M input + 5M output tokens × $3/$15 per 1M
- = $7.50 + $75 = $82.50/user/month worst case
- Real usage typically 20-30% of max limit = ~$16-25/user

Infrastructure: ~$150/month (DigitalOcean droplet + managed DB)

Gross margin at average usage: 60-80%
