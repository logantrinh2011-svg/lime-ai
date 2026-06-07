// ============================================================
// Lime AI Platform — Authentication Middleware
// JWT access tokens + refresh token rotation
// ============================================================

import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { randomBytes } from 'crypto';
import { db } from '../db/client.js';
import { JWTPayload } from '../types/index.js';
import { logger } from '../utils/logger.js';

const ACCESS_SECRET  = process.env.JWT_ACCESS_SECRET!;
const REFRESH_SECRET = process.env.JWT_REFRESH_SECRET!;
const ACCESS_EXPIRY  = '15m';
const REFRESH_EXPIRY = '30d';

// ─────────────────────────────────────────────
// TOKEN GENERATION
// ─────────────────────────────────────────────
export function generateAccessToken(payload: Omit<JWTPayload, 'iat' | 'exp'>): string {
  return jwt.sign(payload, ACCESS_SECRET, { expiresIn: ACCESS_EXPIRY });
}

export function generateRefreshToken(): string {
  return randomBytes(64).toString('hex');
}

// ─────────────────────────────────────────────
// VERIFY ACCESS TOKEN MIDDLEWARE
// ─────────────────────────────────────────────
export function requireAuth(req: Request, res: Response, next: NextFunction): void {
  const authHeader = req.headers.authorization;
  if (!authHeader?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Missing authorization header' });
    return;
  }

  const token = authHeader.slice(7);
  try {
    const payload = jwt.verify(token, ACCESS_SECRET) as JWTPayload;
    req.user = payload;
    next();
  } catch {
    res.status(401).json({ error: 'Invalid or expired access token' });
  }
}

// ─────────────────────────────────────────────
// REQUIRE ADMIN
// ─────────────────────────────────────────────
export function requireAdmin(req: Request, res: Response, next: NextFunction): void {
  if (!req.user?.isAdmin) {
    res.status(403).json({ error: 'Admin access required' });
    return;
  }
  next();
}

// ─────────────────────────────────────────────
// REQUIRE PLAN (e.g. 'pro', 'team', 'enterprise')
// ─────────────────────────────────────────────
export function requirePlan(...plans: string[]) {
  return (req: Request, res: Response, next: NextFunction): void => {
    if (!req.user || !plans.includes(req.user.plan)) {
      res.status(403).json({
        error: 'Plan upgrade required',
        requiredPlan: plans[0],
        currentPlan: req.user?.plan,
      });
      return;
    }
    next();
  };
}

// ─────────────────────────────────────────────
// AUTH SERVICE FUNCTIONS (used in auth routes)
// ─────────────────────────────────────────────

export async function registerUser(
  email: string,
  password: string,
  username?: string
): Promise<{ userId: string; verifyToken: string }> {
  // Check email exists
  const { rows: existing } = await db.query(
    'SELECT id FROM users WHERE email = $1', [email.toLowerCase()]
  );
  if (existing.length > 0) throw Object.assign(new Error('Email already registered'), { code: 'EMAIL_EXISTS' });

  const passwordHash = await bcrypt.hash(password, 12);
  const verifyToken = randomBytes(32).toString('hex');
  const verifyExpires = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24h

  // Get free plan id
  const { rows: plan } = await db.query(
    `SELECT id FROM subscription_plans WHERE name = 'free' LIMIT 1`
  );

  const { rows } = await db.query<{ id: string }>(
    `INSERT INTO users (email, password_hash, username, plan_id, email_verify_token, email_verify_expires)
     VALUES ($1, $2, $3, $4, $5, $6) RETURNING id`,
    [email.toLowerCase(), passwordHash, username, plan[0]?.id, verifyToken, verifyExpires]
  );

  // Create free subscription
  await db.query(
    `INSERT INTO subscriptions (user_id, plan_id, status) VALUES ($1, $2, 'active')`,
    [rows[0].id, plan[0]?.id]
  );

  return { userId: rows[0].id, verifyToken };
}

export async function loginUser(
  email: string,
  password: string,
  ipAddress: string,
  userAgent: string
): Promise<{ accessToken: string; refreshToken: string }> {
  const { rows } = await db.query<{
    id: string; email: string; password_hash: string;
    is_banned: boolean; is_admin: boolean;
    plan_name: string;
  }>(
    `SELECT u.id, u.email, u.password_hash, u.is_banned, u.is_admin,
            sp.name AS plan_name
     FROM users u
     LEFT JOIN subscription_plans sp ON u.plan_id = sp.id
     WHERE u.email = $1`,
    [email.toLowerCase()]
  );

  if (rows.length === 0) throw Object.assign(new Error('Invalid credentials'), { code: 'INVALID_CREDENTIALS' });
  const user = rows[0];
  if (user.is_banned) throw Object.assign(new Error('Account banned'), { code: 'BANNED' });

  const valid = await bcrypt.compare(password, user.password_hash);
  if (!valid) throw Object.assign(new Error('Invalid credentials'), { code: 'INVALID_CREDENTIALS' });

  // Generate tokens
  const accessToken = generateAccessToken({
    sub: user.id, email: user.email,
    plan: user.plan_name || 'free', isAdmin: user.is_admin,
  });
  const refreshToken = generateRefreshToken();

  // Store session
  const expires = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);
  await db.query(
    `INSERT INTO sessions (user_id, refresh_token, ip_address, user_agent, expires_at)
     VALUES ($1, $2, $3, $4, $5)`,
    [user.id, refreshToken, ipAddress, userAgent, expires]
  );

  // Update last login
  await db.query(
    `UPDATE users SET last_login_at = NOW(), last_login_ip = $1 WHERE id = $2`,
    [ipAddress, user.id]
  );

  logger.info('User login', { userId: user.id, ip: ipAddress });
  return { accessToken, refreshToken };
}

export async function refreshTokens(
  refreshToken: string,
  ipAddress: string
): Promise<{ accessToken: string; refreshToken: string }> {
  const { rows } = await db.query<{
    id: string; user_id: string; expires_at: Date; revoked: boolean;
    email: string; is_admin: boolean; plan_name: string;
  }>(
    `SELECT s.id, s.user_id, s.expires_at, s.revoked,
            u.email, u.is_admin, sp.name AS plan_name
     FROM sessions s
     JOIN users u ON s.user_id = u.id
     LEFT JOIN subscription_plans sp ON u.plan_id = sp.id
     WHERE s.refresh_token = $1`,
    [refreshToken]
  );

  if (rows.length === 0 || rows[0].revoked || rows[0].expires_at < new Date()) {
    throw Object.assign(new Error('Invalid refresh token'), { code: 'INVALID_REFRESH' });
  }

  const session = rows[0];

  // Rotate refresh token (revoke old, issue new)
  const newRefreshToken = generateRefreshToken();
  const newExpires = new Date(Date.now() + 30 * 24 * 60 * 60 * 1000);

  await db.query(`UPDATE sessions SET revoked = true WHERE id = $1`, [session.id]);
  await db.query(
    `INSERT INTO sessions (user_id, refresh_token, ip_address, expires_at)
     VALUES ($1, $2, $3, $4)`,
    [session.user_id, newRefreshToken, ipAddress, newExpires]
  );

  const accessToken = generateAccessToken({
    sub: session.user_id, email: session.email,
    plan: session.plan_name || 'free', isAdmin: session.is_admin,
  });

  return { accessToken, refreshToken: newRefreshToken };
}

export async function revokeRefreshToken(refreshToken: string): Promise<void> {
  await db.query(`UPDATE sessions SET revoked = true WHERE refresh_token = $1`, [refreshToken]);
}

export async function verifyEmail(token: string): Promise<void> {
  const { rowCount } = await db.query(
    `UPDATE users
     SET email_verified = true, email_verify_token = NULL, email_verify_expires = NULL
     WHERE email_verify_token = $1 AND email_verify_expires > NOW()`,
    [token]
  );
  if (rowCount === 0) throw Object.assign(new Error('Invalid or expired token'), { code: 'INVALID_VERIFY' });
}
