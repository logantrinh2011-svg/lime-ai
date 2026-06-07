// ============================================================
// Lime AI Platform — Rate Limiting Middleware
// Per-plan rate limits, IP-based DDoS protection
// ============================================================

import rateLimit from 'express-rate-limit';
import { Request, Response, NextFunction } from 'express';
import { db } from '../db/client.js';

// ─────────────────────────────────────────────
// IP-BASED RATE LIMITER (DDoS protection)
// Applied globally to all routes
// ─────────────────────────────────────────────
export const globalRateLimit = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 300,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests from this IP, please try again later.' },
  skip: (req) => req.path === '/health', // skip health checks
});

// ─────────────────────────────────────────────
// AUTH ENDPOINT LIMITER (prevent brute force)
// ─────────────────────────────────────────────
export const authRateLimit = rateLimit({
  windowMs: 60 * 60 * 1000, // 1 hour
  max: 20,
  message: { error: 'Too many authentication attempts, try again later.' },
});

// ─────────────────────────────────────────────
// PLAN-BASED USAGE LIMIT MIDDLEWARE
// Checks DB usage against plan limits before each AI call
// ─────────────────────────────────────────────
export async function planUsageLimit(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  if (!req.user) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }

  try {
    // Get plan limits
    const { rows } = await db.query<{
      requests_per_day: number;
      requests_per_month: number;
    }>(
      `SELECT sp.requests_per_day, sp.requests_per_month
       FROM users u
       JOIN subscription_plans sp ON u.plan_id = sp.id
       WHERE u.id = $1`,
      [req.user.sub]
    );

    if (rows.length === 0) {
      res.status(403).json({ error: 'No active subscription' });
      return;
    }

    const limits = rows[0];

    // Skip checks for unlimited plans
    if (limits.requests_per_day === -1) {
      next();
      return;
    }

    // Check daily usage
    const { rows: daily } = await db.query<{ count: string }>(
      `SELECT COUNT(*) FROM usage_logs
       WHERE user_id = $1 AND success = true
         AND created_at >= DATE_TRUNC('day', NOW())`,
      [req.user.sub]
    );

    if (parseInt(daily[0].count) >= limits.requests_per_day) {
      res.status(429).json({
        error: 'Daily request limit reached',
        limit: limits.requests_per_day,
        used: parseInt(daily[0].count),
        resetAt: new Date(new Date().setHours(24, 0, 0, 0)).toISOString(),
        upgradeUrl: `${process.env.DASHBOARD_URL}/billing`,
      });
      return;
    }

    // Check monthly usage
    if (limits.requests_per_month !== -1) {
      const { rows: monthly } = await db.query<{ count: string }>(
        `SELECT COUNT(*) FROM usage_logs
         WHERE user_id = $1 AND success = true
           AND created_at >= DATE_TRUNC('month', NOW())`,
        [req.user.sub]
      );

      if (parseInt(monthly[0].count) >= limits.requests_per_month) {
        res.status(429).json({
          error: 'Monthly request limit reached',
          limit: limits.requests_per_month,
          used: parseInt(monthly[0].count),
          upgradeUrl: `${process.env.DASHBOARD_URL}/billing`,
        });
        return;
      }
    }

    next();
  } catch (err) {
    res.status(500).json({ error: 'Failed to check usage limits' });
  }
}

// ─────────────────────────────────────────────
// REQUEST TIMING MIDDLEWARE
// ─────────────────────────────────────────────
export function requestTiming(req: Request, _res: Response, next: NextFunction): void {
  req.startTime = Date.now();
  next();
}

// ─────────────────────────────────────────────
// BANNED USER CHECK
// ─────────────────────────────────────────────
export async function checkBanned(
  req: Request,
  res: Response,
  next: NextFunction
): Promise<void> {
  if (!req.user) { next(); return; }

  const { rows } = await db.query<{ is_banned: boolean; ban_reason?: string }>(
    `SELECT is_banned, ban_reason FROM users WHERE id = $1`,
    [req.user.sub]
  );

  if (rows[0]?.is_banned) {
    res.status(403).json({
      error: 'Account suspended',
      reason: rows[0].ban_reason || 'Violation of terms of service',
    });
    return;
  }
  next();
}
