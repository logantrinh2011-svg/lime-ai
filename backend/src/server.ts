// ============================================================
// Lime AI Platform — Express Server (main entry point)
// ============================================================

import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import compression from 'compression';
import morgan from 'morgan';
import { globalRateLimit, requestTiming } from './middleware/rateLimiter.js';
import routes from './routes/index.js';
import { logger } from './utils/logger.js';
import { db } from './db/client.js';

const app = express();
const PORT = parseInt(process.env.PORT ?? '3001', 10);

// ─────────────────────────────────────────────
// SECURITY HEADERS
// ─────────────────────────────────────────────
app.set('trust proxy', 1); // Trust first proxy (nginx/cloudflare)

app.use(helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      connectSrc: ["'self'", 'https://api.anthropic.com'],
    },
  },
  hsts: { maxAge: 31536000, includeSubDomains: true },
}));

// ─────────────────────────────────────────────
// CORS — allow Studio plugin + dashboard + API clients
// ─────────────────────────────────────────────
const allowedOrigins = [
  process.env.DASHBOARD_URL ?? 'http://localhost:3000',
  'https://limeai.dev',
  // Roblox Studio uses HttpService which doesn't send Origin header,
  // so it passes CORS automatically (no origin = server-to-server call)
];

app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (Roblox Studio, Postman, mobile apps)
    if (!origin) return callback(null, true);
    if (allowedOrigins.includes(origin)) return callback(null, true);
    callback(new Error(`Origin ${origin} not allowed`));
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// ─────────────────────────────────────────────
// MIDDLEWARE
// ─────────────────────────────────────────────
app.use(compression());
app.use(requestTiming);
app.use(globalRateLimit);

// Stripe webhook needs raw body
app.use('/webhooks/stripe', express.raw({ type: 'application/json' }));

// Everything else gets JSON parsing
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true }));

// HTTP request logging
app.use(morgan('combined', {
  stream: { write: (message) => logger.info(message.trim()) },
  skip: (req) => req.path === '/health',
}));

// ─────────────────────────────────────────────
// STRIPE WEBHOOKS (must come before auth)
// ─────────────────────────────────────────────
app.post('/webhooks/stripe', async (req, res) => {
  const sig = req.headers['stripe-signature'];
  if (!sig) { res.status(400).send('No signature'); return; }

  try {
    const { default: Stripe } = await import('stripe');
    const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, { apiVersion: '2023-10-16' });
    const event = stripe.webhooks.constructEvent(
      req.body, sig, process.env.STRIPE_WEBHOOK_SECRET!
    );

    if (event.type === 'checkout.session.completed') {
      const session = event.data.object as { metadata?: { userId?: string; planName?: string }; customer?: string; subscription?: string };
      const { userId, planName } = session.metadata ?? {};
      if (userId && planName) {
        // Update user plan
        const { rows: plan } = await db.query(
          `SELECT id FROM subscription_plans WHERE name = $1`, [planName]
        );
        if (plan[0]) {
          await db.query(
            `UPDATE users SET plan_id = $1 WHERE id = $2`,
            [plan[0].id, userId]
          );
          await db.query(
            `UPDATE subscriptions SET plan_id = $1, stripe_customer_id = $2,
               stripe_subscription_id = $3, status = 'active', updated_at = NOW()
             WHERE user_id = $4`,
            [plan[0].id, session.customer, session.subscription, userId]
          );
          logger.info('Subscription upgraded', { userId, planName });
        }
      }
    }

    if (event.type === 'customer.subscription.deleted') {
      const sub = event.data.object as { id: string };
      await db.query(
        `UPDATE subscriptions SET status = 'canceled', updated_at = NOW()
         WHERE stripe_subscription_id = $1`,
        [sub.id]
      );
      // Downgrade to free
      const { rows: free } = await db.query(
        `SELECT id FROM subscription_plans WHERE name = 'free'`
      );
      if (free[0]) {
        await db.query(
          `UPDATE users SET plan_id = $1
           WHERE id = (SELECT user_id FROM subscriptions WHERE stripe_subscription_id = $2)`,
          [free[0].id, sub.id]
        );
      }
    }

    res.json({ received: true });
  } catch (err: unknown) {
    logger.error('Stripe webhook error', err);
    res.status(400).send(`Webhook Error: ${(err as Error).message}`);
  }
});

// ─────────────────────────────────────────────
// API ROUTES
// ─────────────────────────────────────────────
app.use('/api/v1', routes);

// ─────────────────────────────────────────────
// 404 HANDLER
// ─────────────────────────────────────────────
app.use((_req, res) => {
  res.status(404).json({ error: 'Route not found' });
});

// ─────────────────────────────────────────────
// GLOBAL ERROR HANDLER
// ─────────────────────────────────────────────
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  logger.error('Unhandled error', { error: err.message, stack: err.stack });
  res.status(500).json({ error: 'Internal server error' });
});

// ─────────────────────────────────────────────
// START SERVER
// ─────────────────────────────────────────────
app.listen(PORT, async () => {
  try {
    await db.query('SELECT 1');
    logger.info(`✅ Lime AI Backend running on port ${PORT}`);
    logger.info(`📊 Dashboard: ${process.env.DASHBOARD_URL}`);
    logger.info(`🤖 AI Model: ${process.env.CLAUDE_MODEL ?? 'claude-sonnet-4-20250514'}`);
  } catch (err) {
    logger.error('❌ Database connection failed', err);
    process.exit(1);
  }
});

export default app;
