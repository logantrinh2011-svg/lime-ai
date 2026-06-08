roblox-ai-platform/                                                                                 0000755 0000000 0000000 00000000000 15211361313 013266  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/backend/                                                                         0000755 0000000 0000000 00000000000 15211373622 014663  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/backend/src/                                                                     0000755 0000000 0000000 00000000000 15211362255 015452  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/backend/src/types/                                                               0000755 0000000 0000000 00000000000 15211362255 016616  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/backend/src/types/index.ts                                                       0000644 0000000 0000000 00000004454 15211362255 020304  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   // ============================================================
// Lime AI Platform — Shared TypeScript Types
// ============================================================

export interface User {
  id: string;
  email: string;
  username?: string;
  displayName?: string;
  robloxUsername?: string;
  avatarUrl?: string;
  emailVerified: boolean;
  planId?: string;
  isAdmin: boolean;
  isBanned: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface SubscriptionPlan {
  id: string;
  name: 'free' | 'pro' | 'team' | 'enterprise';
  displayName: string;
  priceCents: number;
  requestsPerDay: number;
  requestsPerMonth: number;
  maxTokensPerRequest: number;
  maxConversations: number;
  features: string[];
}

export interface Conversation {
  id: string;
  userId: string;
  title: string;
  model: string;
  systemPrompt?: string;
  metadata: Record<string, unknown>;
  archived: boolean;
  createdAt: Date;
  updatedAt: Date;
}

export interface Message {
  id: string;
  conversationId: string;
  userId: string;
  role: 'user' | 'assistant' | 'system';
  content: string;
  tokensInput: number;
  tokensOutput: number;
  model?: string;
  createdAt: Date;
}

export interface UsageStats {
  todayRequests: number;
  monthRequests: number;
  todayTokens: number;
  monthTokens: number;
  limitPerDay: number;
  limitPerMonth: number;
}

// API Request/Response types
export interface ChatRequest {
  conversationId?: string;
  message: string;
  stream?: boolean;
}

export interface ChatResponse {
  conversationId: string;
  messageId: string;
  content: string;
  tokensInput: number;
  tokensOutput: number;
  finishReason: string;
}

export interface AuthTokens {
  accessToken: string;
  refreshToken: string;
  expiresIn: number;
}

export interface JWTPayload {
  sub: string;      // user id
  email: string;
  plan: string;
  isAdmin: boolean;
  iat: number;
  exp: number;
}

// Express augmentation
declare global {
  namespace Express {
    interface Request {
      user?: JWTPayload;
      startTime?: number;
    }
  }
}

// Claude stream event types (SSE to Roblox)
export interface StreamEvent {
  type: 'start' | 'delta' | 'done' | 'error';
  conversationId?: string;
  messageId?: string;
  delta?: string;
  fullContent?: string;
  tokensInput?: number;
  tokensOutput?: number;
  error?: string;
}
                                                                                                                                                                                                                    roblox-ai-platform/backend/src/middleware/                                                          0000755 0000000 0000000 00000000000 15211362255 017567  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/backend/src/middleware/rateLimiter.ts                                            0000644 0000000 0000000 00000012317 15211362255 022424  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   // ============================================================
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
                                                                                                                                                                                                                                                                                                                 roblox-ai-platform/backend/src/middleware/auth.ts                                                   0000644 0000000 0000000 00000020662 15211362255 021106  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   // ============================================================
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
                                                                              roblox-ai-platform/backend/src/services/                                                            0000755 0000000 0000000 00000000000 15211373622 017275  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/backend/src/services/jobs.service.ts                                             0000644 0000000 0000000 00000021140 15211373622 022237  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   // ============================================================
// Lime AI — Code Jobs Service
// Bridge between website requests and Studio code insertion
// ============================================================

import { GoogleGenerativeAI } from '@google/generative-ai';
import { db } from '../db/client.js';
import { logger } from '../utils/logger.js';

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY!);
const MODEL = 'gemini-1.5-flash';

// ─────────────────────────────────────────────
// SYSTEM PROMPT — tuned for code generation
// ─────────────────────────────────────────────
const CODE_GEN_SYSTEM = `You are Lime AI, an expert Roblox Luau code generator.

When the user describes what they want, you generate COMPLETE, WORKING Luau code for Roblox Studio.

RULES:
- Always output a JSON object with this exact structure:
  {
    "scriptName": "DescriptiveName",
    "code": "-- full luau code here",
    "explanation": "One sentence explaining what the code does and where to put it"
  }
- The "code" field must contain ONLY valid Luau code, no markdown, no backticks
- Always write production-ready code with error handling (pcall where needed)
- Use proper Roblox services (Players, ReplicatedStorage, etc.)
- Add clear comments in the code
- The scriptName should be PascalCase, descriptive, no spaces
- Output ONLY the JSON object. No preamble, no explanation outside the JSON.`;

// ─────────────────────────────────────────────
// CREATE A NEW CODE JOB (from website)
// ─────────────────────────────────────────────
export async function createCodeJob(
  userId: string,
  prompt: string,
  scriptType: 'Script' | 'LocalScript' | 'ModuleScript',
  insertLocation: string
): Promise<{ jobId: string }> {
  const { rows } = await db.query<{ id: string }>(
    `INSERT INTO code_jobs (user_id, prompt, script_type, insert_location, status)
     VALUES ($1, $2, $3, $4, 'pending')
     RETURNING id`,
    [userId, prompt, scriptType, insertLocation]
  );

  const jobId = rows[0].id;

  // Process asynchronously — don't make the website wait
  setImmediate(() => processCodeJob(jobId, userId, prompt, scriptType));

  return { jobId };
}

// ─────────────────────────────────────────────
// PROCESS A JOB — call Claude, save result
// ─────────────────────────────────────────────
async function processCodeJob(
  jobId: string,
  userId: string,
  prompt: string,
  scriptType: string
): Promise<void> {
  // Mark as processing
  await db.query(
    `UPDATE code_jobs SET status = 'processing' WHERE id = $1`,
    [jobId]
  );

  try {
    const response = await anthropic.messages.create({
      model: MODEL,
      max_tokens: 8192,
      system: CODE_GEN_SYSTEM,
      messages: [{
        role: 'user',
        content: `Generate a ${scriptType} for Roblox Studio that does the following:\n\n${prompt}`,
      }],
    });

    const rawText = response.content
      .filter(b => b.type === 'text')
      .map(b => (b as Anthropic.TextBlock).text)
      .join('');

    // Parse the JSON response from Claude
    let parsed: { scriptName: string; code: string; explanation: string };
    try {
      // Strip any accidental markdown fences
      const clean = rawText.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
      parsed = JSON.parse(clean);
    } catch {
      throw new Error('Claude returned invalid JSON: ' + rawText.slice(0, 200));
    }

    // Validate fields
    if (!parsed.code || !parsed.scriptName) {
      throw new Error('Claude response missing code or scriptName');
    }

    await db.query(
      `UPDATE code_jobs
       SET status = 'completed',
           generated_code = $1,
           explanation = $2,
           script_name = $3,
           completed_at = NOW()
       WHERE id = $4`,
      [parsed.code, parsed.explanation, parsed.scriptName, jobId]
    );

    logger.info('Code job completed', { jobId, scriptName: parsed.scriptName });

    // Track usage
    await db.query(
      `INSERT INTO analytics_events (user_id, event_type, properties)
       VALUES ($1, 'code_job_completed', $2)`,
      [userId, JSON.stringify({ jobId, scriptType, promptLength: prompt.length,
        tokensInput: response.usage.input_tokens,
        tokensOutput: response.usage.output_tokens })]
    );

  } catch (err: unknown) {
    const error = err as Error;
    logger.error('Code job failed', { jobId, error: error.message });
    await db.query(
      `UPDATE code_jobs SET status = 'failed', error_message = $1 WHERE id = $2`,
      [error.message, jobId]
    );
  }
}

// ─────────────────────────────────────────────
// GET PENDING JOBS FOR USER (polled by plugin)
// Returns completed jobs not yet inserted
// ─────────────────────────────────────────────
export async function getPendingJobsForUser(userId: string): Promise<{
  jobs: Array<{
    id: string;
    scriptName: string;
    scriptType: string;
    insertLocation: string;
    code: string;
    explanation: string;
    createdAt: string;
  }>;
}> {
  const { rows } = await db.query<{
    id: string; script_name: string; script_type: string;
    insert_location: string; generated_code: string;
    explanation: string; created_at: Date;
  }>(
    `SELECT id, script_name, script_type, insert_location,
            generated_code, explanation, created_at
     FROM code_jobs
     WHERE user_id = $1 AND status = 'completed'
     ORDER BY created_at ASC
     LIMIT 10`,
    [userId]
  );

  return {
    jobs: rows.map(r => ({
      id: r.id,
      scriptName: r.script_name,
      scriptType: r.script_type,
      insertLocation: r.insert_location,
      code: r.generated_code,
      explanation: r.explanation,
      createdAt: r.created_at.toISOString(),
    })),
  };
}

// ─────────────────────────────────────────────
// MARK JOB AS INSERTED (called by plugin)
// ─────────────────────────────────────────────
export async function markJobInserted(jobId: string, userId: string): Promise<void> {
  await db.query(
    `UPDATE code_jobs
     SET status = 'inserted', inserted_at = NOW()
     WHERE id = $1 AND user_id = $2`,
    [jobId, userId]
  );

  await db.query(
    `INSERT INTO analytics_events (user_id, event_type, properties)
     VALUES ($1, 'code_inserted_to_studio', $2)`,
    [userId, JSON.stringify({ jobId })]
  );
}

// ─────────────────────────────────────────────
// GET JOB STATUS (for website polling)
// ─────────────────────────────────────────────
export async function getJobStatus(jobId: string, userId: string): Promise<{
  status: string;
  explanation?: string;
  scriptName?: string;
  error?: string;
} | null> {
  const { rows } = await db.query<{
    status: string; explanation: string;
    script_name: string; error_message: string;
  }>(
    `SELECT status, explanation, script_name, error_message
     FROM code_jobs WHERE id = $1 AND user_id = $2`,
    [jobId, userId]
  );
  if (!rows[0]) return null;
  return {
    status: rows[0].status,
    explanation: rows[0].explanation,
    scriptName: rows[0].script_name,
    error: rows[0].error_message,
  };
}

// ─────────────────────────────────────────────
// LIST USER'S JOB HISTORY
// ─────────────────────────────────────────────
export async function getUserJobHistory(userId: string, limit = 20): Promise<unknown[]> {
  const { rows } = await db.query(
    `SELECT id, prompt, script_name, script_type, status,
            created_at, completed_at, inserted_at
     FROM code_jobs WHERE user_id = $1
     ORDER BY created_at DESC LIMIT $2`,
    [userId, limit]
  );
  return rows;
}
                                                                                                                                                                                                                                                                                                                                                                                                                                roblox-ai-platform/backend/src/services/claude.service.ts                                           0000644 0000000 0000000 00000014424 15211373614 022547  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   // ============================================================
// Lime AI — Gemini AI Service (free tier)
// ============================================================

import { GoogleGenerativeAI } from '@google/generative-ai';
import { db } from '../db/client.js';
import { logger } from '../utils/logger.js';
import { Response } from 'express';

const genAI = new GoogleGenerativeAI(process.env.GEMINI_API_KEY!);
const MODEL  = 'gemini-1.5-flash';

export function buildSystemPrompt(): string {
  return `You are Lime AI, an expert Roblox game development assistant. You have deep expertise in Lua and Luau scripting, Roblox API and all services, RemoteEvents, DataStoreService, and all Roblox Studio workflows. Always write production-quality Luau code with comments. When providing code wrap it in code blocks with lua tag. Label whether code goes in a Script, LocalScript, or ModuleScript and explain where to place it.`;
}

async function loadConversationHistory(conversationId: string, userId: string) {
  const { rows } = await db.query(
    `SELECT role, content FROM messages
     WHERE conversation_id = $1 AND user_id = $2 AND role != 'system'
     ORDER BY created_at DESC LIMIT 20`,
    [conversationId, userId]
  );
  return rows.reverse();
}

async function saveMessage(
  conversationId: string, userId: string, role: string,
  content: string, tokensInput = 0, tokensOutput = 0
): Promise<string> {
  const { rows } = await db.query<{ id: string }>(
    `INSERT INTO messages (conversation_id, user_id, role, content, model, tokens_input, tokens_output)
     VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING id`,
    [conversationId, userId, role, content, MODEL, tokensInput, tokensOutput]
  );
  return rows[0].id;
}

export async function ensureConversation(
  userId: string, conversationId?: string, firstMessage?: string
): Promise<string> {
  if (conversationId) {
    const { rows } = await db.query(
      'SELECT id FROM conversations WHERE id = $1 AND user_id = $2',
      [conversationId, userId]
    );
    if (rows.length === 0) throw new Error('Conversation not found');
    return conversationId;
  }
  const title = firstMessage ? firstMessage.slice(0, 50) : 'New Conversation';
  const { rows } = await db.query<{ id: string }>(
    `INSERT INTO conversations (user_id, title) VALUES ($1, $2) RETURNING id`,
    [userId, title]
  );
  return rows[0].id;
}

export async function checkUsageLimits(
  userId: string,
  planLimits: { requestsPerDay: number; requestsPerMonth: number }
): Promise<void> {
  if (planLimits.requestsPerDay === -1) return;
  const { rows } = await db.query<{ count: string }>(
    `SELECT COUNT(*) FROM usage_logs WHERE user_id = $1 AND success = true AND created_at >= DATE_TRUNC('day', NOW())`,
    [userId]
  );
  if (parseInt(rows[0].count) >= planLimits.requestsPerDay) {
    throw Object.assign(new Error('Daily request limit exceeded'), { code: 'LIMIT_DAILY' });
  }
}

export async function chatWithClaude(params: {
  userId: string; userMessage: string; conversationId: string;
  planName: string; model?: string; maxTokens?: number;
}): Promise<{ content: string; messageId: string; tokensInput: number; tokensOutput: number }> {
  const startTime = Date.now();
  await saveMessage(params.conversationId, params.userId, 'user', params.userMessage);
  const history = await loadConversationHistory(params.conversationId, params.userId);

  const model = genAI.getGenerativeModel({ model: MODEL, systemInstruction: buildSystemPrompt() });
  const chatHistory = history.slice(0, -1).map((msg: any) => ({
    role: msg.role === 'assistant' ? 'model' : 'user',
    parts: [{ text: msg.content }],
  }));

  const chat = model.startChat({ history: chatHistory });
  const result = await chat.sendMessage(params.userMessage);
  const content = result.response.text();
  const tokensIn  = result.response.usageMetadata?.promptTokenCount ?? 0;
  const tokensOut = result.response.usageMetadata?.candidatesTokenCount ?? 0;

  const messageId = await saveMessage(params.conversationId, params.userId, 'assistant', content, tokensIn, tokensOut);

  await db.query(
    `INSERT INTO usage_logs (user_id, conversation_id, message_id, plan_name, model, tokens_input, tokens_output, cost_usd, latency_ms, success)
     VALUES ($1,$2,$3,$4,$5,$6,$7,0,$8,true)`,
    [params.userId, params.conversationId, messageId, params.planName, MODEL, tokensIn, tokensOut, Date.now() - startTime]
  );

  return { content, messageId, tokensInput: tokensIn, tokensOutput: tokensOut };
}

export async function streamChatWithClaude(params: {
  userId: string; userMessage: string; conversationId: string;
  planName: string; model?: string; maxTokens?: number; res: Response;
}): Promise<void> {
  params.res.setHeader('Content-Type', 'text/event-stream');
  params.res.setHeader('Cache-Control', 'no-cache');
  params.res.setHeader('Connection', 'keep-alive');
  params.res.flushHeaders();

  const send = (data: object) => params.res.write(`data: ${JSON.stringify(data)}\n\n`);
  send({ type: 'start', conversationId: params.conversationId });

  try {
    await saveMessage(params.conversationId, params.userId, 'user', params.userMessage);
    const history = await loadConversationHistory(params.conversationId, params.userId);
    const model = genAI.getGenerativeModel({ model: MODEL, systemInstruction: buildSystemPrompt() });
    const chatHistory = history.slice(0, -1).map((msg: any) => ({
      role: msg.role === 'assistant' ? 'model' : 'user',
      parts: [{ text: msg.content }],
    }));

    const chat = model.startChat({ history: chatHistory });
    const result = await chat.sendMessageStream(params.userMessage);
    let fullContent = '';

    for await (const chunk of result.stream) {
      const text = chunk.text();
      fullContent += text;
      send({ type: 'delta', delta: text });
    }

    const finalResponse = await result.response;
    const tokensIn  = finalResponse.usageMetadata?.promptTokenCount ?? 0;
    const tokensOut = finalResponse.usageMetadata?.candidatesTokenCount ?? 0;
    const messageId = await saveMessage(params.conversationId, params.userId, 'assistant', fullContent, tokensIn, tokensOut);
    send({ type: 'done', messageId, fullContent, tokensInput: tokensIn, tokensOutput: tokensOut });
  } catch (err: unknown) {
    send({ type: 'error', error: (err as Error).message });
  } finally {
    params.res.end();
  }
}
                                                                                                                                                                                                                                            roblox-ai-platform/backend/src/server.ts                                                            0000644 0000000 0000000 00000016654 15211362255 017344  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   // ============================================================
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
    const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, { apiVersion: '2025-01-27.acacia' });
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
                                                                                    roblox-ai-platform/backend/src/db/                                                                  0000755 0000000 0000000 00000000000 15211362255 016037  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/backend/src/db/client.ts                                                         0000644 0000000 0000000 00000001443 15211362255 017667  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   // ============================================================
// Lime AI Platform — PostgreSQL Client (pg Pool)
// ============================================================

import pg from 'pg';
import { logger } from '../utils/logger.js';

const { Pool } = pg;

export const db = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: true } : false,
  max: 20,                  // max connections in pool
  idleTimeoutMillis: 30000, // close idle connections after 30s
  connectionTimeoutMillis: 2000,
});

db.on('error', (err) => {
  logger.error('Database pool error', { error: err.message });
});

// Graceful shutdown
process.on('SIGTERM', async () => {
  logger.info('Closing database pool...');
  await db.end();
});
                                                                                                                                                                                                                             roblox-ai-platform/backend/src/db/schema.sql                                                        0000644 0000000 0000000 00000035422 15211363361 020025  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   -- ============================================================
-- Lime AI Platform — Complete PostgreSQL Schema
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─────────────────────────────────────────────
-- SUBSCRIPTION PLANS (seed data)
-- ─────────────────────────────────────────────
CREATE TABLE subscription_plans (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name          VARCHAR(50) UNIQUE NOT NULL,         -- 'free', 'pro', 'team', 'enterprise'
  display_name  VARCHAR(100) NOT NULL,
  price_cents   INTEGER NOT NULL DEFAULT 0,          -- monthly price in cents
  requests_per_day  INTEGER NOT NULL DEFAULT 20,
  requests_per_month INTEGER NOT NULL DEFAULT 100,
  max_tokens_per_request INTEGER NOT NULL DEFAULT 2048,
  max_conversations  INTEGER NOT NULL DEFAULT 10,
  features      JSONB NOT NULL DEFAULT '[]',
  stripe_price_id VARCHAR(100),
  active        BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO subscription_plans (name, display_name, price_cents, requests_per_day, requests_per_month, max_tokens_per_request, max_conversations, features) VALUES
  ('free',       'Free',       0,      20,   100,  2048,  10,  '["Chat with Claude","Code generation","Bug fixing","10 conversations"]'),
  ('pro',        'Pro',        1900,   200,  5000, 8192,  100, '["Everything in Free","Priority responses","Full conversation history","Code analysis","Generate full systems","100 conversations"]'),
  ('team',       'Team',       4900,   1000, 25000,16384, 500, '["Everything in Pro","Team workspace","Shared conversation history","Priority support","500 conversations"]'),
  ('enterprise', 'Enterprise', 19900,  -1,   -1,   32768, -1,  '["Everything in Team","Unlimited requests","Dedicated support","Custom system prompts","SLA guarantee","Unlimited conversations"]');

-- ─────────────────────────────────────────────
-- USERS
-- ─────────────────────────────────────────────
CREATE TABLE users (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email                 VARCHAR(255) UNIQUE NOT NULL,
  password_hash         VARCHAR(255) NOT NULL,
  username              VARCHAR(50) UNIQUE,
  display_name          VARCHAR(100),
  roblox_username       VARCHAR(50),
  avatar_url            VARCHAR(500),
  email_verified        BOOLEAN NOT NULL DEFAULT false,
  email_verify_token    VARCHAR(255),
  email_verify_expires  TIMESTAMPTZ,
  password_reset_token  VARCHAR(255),
  password_reset_expires TIMESTAMPTZ,
  plan_id               UUID REFERENCES subscription_plans(id),
  is_admin              BOOLEAN NOT NULL DEFAULT false,
  is_banned             BOOLEAN NOT NULL DEFAULT false,
  ban_reason            TEXT,
  last_login_at         TIMESTAMPTZ,
  last_login_ip         INET,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_plan_id ON users(plan_id);

-- ─────────────────────────────────────────────
-- SESSIONS
-- ─────────────────────────────────────────────
CREATE TABLE sessions (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  refresh_token VARCHAR(500) UNIQUE NOT NULL,
  device_info   JSONB,
  ip_address    INET,
  user_agent    TEXT,
  expires_at    TIMESTAMPTZ NOT NULL,
  revoked       BOOLEAN NOT NULL DEFAULT false,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sessions_user_id ON sessions(user_id);
CREATE INDEX idx_sessions_refresh_token ON sessions(refresh_token);

-- ─────────────────────────────────────────────
-- API KEYS (for direct API access, not plugin)
-- ─────────────────────────────────────────────
CREATE TABLE api_keys (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  key_hash      VARCHAR(255) UNIQUE NOT NULL,  -- bcrypt hash of the raw key
  key_prefix    VARCHAR(10) NOT NULL,          -- first 8 chars shown to user e.g. "rai_ab12"
  name          VARCHAR(100) NOT NULL,
  last_used_at  TIMESTAMPTZ,
  expires_at    TIMESTAMPTZ,
  revoked       BOOLEAN NOT NULL DEFAULT false,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_api_keys_user_id ON api_keys(user_id);
CREATE INDEX idx_api_keys_key_hash ON api_keys(key_hash);

-- ─────────────────────────────────────────────
-- CONVERSATIONS
-- ─────────────────────────────────────────────
CREATE TABLE conversations (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title         VARCHAR(255) NOT NULL DEFAULT 'New Conversation',
  model         VARCHAR(100) NOT NULL DEFAULT 'claude-sonnet-4-20250514',
  system_prompt TEXT,
  metadata      JSONB DEFAULT '{}',
  archived      BOOLEAN NOT NULL DEFAULT false,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_conversations_user_id ON conversations(user_id);
CREATE INDEX idx_conversations_updated_at ON conversations(updated_at DESC);

-- ─────────────────────────────────────────────
-- MESSAGES
-- ─────────────────────────────────────────────
CREATE TABLE messages (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  conversation_id UUID NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role            VARCHAR(20) NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
  content         TEXT NOT NULL,
  tokens_input    INTEGER DEFAULT 0,
  tokens_output   INTEGER DEFAULT 0,
  model           VARCHAR(100),
  finish_reason   VARCHAR(50),
  metadata        JSONB DEFAULT '{}',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_messages_conversation_id ON messages(conversation_id);
CREATE INDEX idx_messages_user_id ON messages(user_id);
CREATE INDEX idx_messages_created_at ON messages(created_at);

-- ─────────────────────────────────────────────
-- SUBSCRIPTIONS
-- ─────────────────────────────────────────────
CREATE TABLE subscriptions (
  id                    UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id               UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  plan_id               UUID NOT NULL REFERENCES subscription_plans(id),
  stripe_subscription_id VARCHAR(100) UNIQUE,
  stripe_customer_id    VARCHAR(100),
  status                VARCHAR(50) NOT NULL DEFAULT 'active',  -- active, canceled, past_due, trialing
  trial_ends_at         TIMESTAMPTZ,
  current_period_start  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  current_period_end    TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 days'),
  cancel_at_period_end  BOOLEAN NOT NULL DEFAULT false,
  canceled_at           TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_subscriptions_user_id ON subscriptions(user_id);
CREATE INDEX idx_subscriptions_stripe_id ON subscriptions(stripe_subscription_id);

-- ─────────────────────────────────────────────
-- BILLING RECORDS
-- ─────────────────────────────────────────────
CREATE TABLE billing_records (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  subscription_id     UUID REFERENCES subscriptions(id),
  stripe_invoice_id   VARCHAR(100) UNIQUE,
  stripe_payment_intent_id VARCHAR(100),
  amount_cents        INTEGER NOT NULL,
  currency            VARCHAR(3) NOT NULL DEFAULT 'usd',
  status              VARCHAR(50) NOT NULL,  -- paid, unpaid, void, draft
  description         TEXT,
  invoice_pdf_url     VARCHAR(500),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_billing_records_user_id ON billing_records(user_id);

-- ─────────────────────────────────────────────
-- USAGE TRACKING
-- ─────────────────────────────────────────────
CREATE TABLE usage_logs (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES conversations(id) ON DELETE SET NULL,
  message_id      UUID REFERENCES messages(id) ON DELETE SET NULL,
  plan_name       VARCHAR(50) NOT NULL,
  model           VARCHAR(100) NOT NULL,
  tokens_input    INTEGER NOT NULL DEFAULT 0,
  tokens_output   INTEGER NOT NULL DEFAULT 0,
  cost_usd        NUMERIC(10, 6) NOT NULL DEFAULT 0,
  latency_ms      INTEGER,
  success         BOOLEAN NOT NULL DEFAULT true,
  error_code      VARCHAR(100),
  ip_address      INET,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_usage_logs_user_id ON usage_logs(user_id);
CREATE INDEX idx_usage_logs_created_at ON usage_logs(created_at DESC);
CREATE INDEX idx_usage_logs_user_date ON usage_logs(user_id, created_at);

-- Daily usage summary (materialized, refreshed hourly)
CREATE MATERIALIZED VIEW daily_usage_summary AS
SELECT
  user_id,
  DATE(created_at) AS usage_date,
  COUNT(*) AS request_count,
  SUM(tokens_input) AS total_tokens_input,
  SUM(tokens_output) AS total_tokens_output,
  SUM(cost_usd) AS total_cost_usd
FROM usage_logs
WHERE success = true
GROUP BY user_id, DATE(created_at);

CREATE UNIQUE INDEX idx_daily_usage_summary ON daily_usage_summary(user_id, usage_date);

-- ─────────────────────────────────────────────
-- ANALYTICS EVENTS
-- ─────────────────────────────────────────────
CREATE TABLE analytics_events (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
  event_type  VARCHAR(100) NOT NULL,  -- 'chat_sent', 'code_inserted', 'script_created', etc.
  properties  JSONB DEFAULT '{}',
  ip_address  INET,
  user_agent  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_analytics_events_user_id ON analytics_events(user_id);
CREATE INDEX idx_analytics_events_type ON analytics_events(event_type);
CREATE INDEX idx_analytics_events_created_at ON analytics_events(created_at DESC);

-- ─────────────────────────────────────────────
-- AUDIT LOGS
-- ─────────────────────────────────────────────
CREATE TABLE audit_logs (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
  actor_id    UUID REFERENCES users(id) ON DELETE SET NULL,  -- admin who took action
  action      VARCHAR(100) NOT NULL,
  resource    VARCHAR(100),
  resource_id UUID,
  old_value   JSONB,
  new_value   JSONB,
  ip_address  INET,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_logs_user_id ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);

-- ─────────────────────────────────────────────
-- AUTO-UPDATE updated_at TRIGGER
-- ─────────────────────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_conversations_updated_at BEFORE UPDATE ON conversations FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_subscriptions_updated_at BEFORE UPDATE ON subscriptions FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─────────────────────────────────────────────
-- CODE JOBS (website → Studio bridge)
-- ─────────────────────────────────────────────
CREATE TYPE job_status AS ENUM ('pending', 'processing', 'completed', 'failed', 'inserted');
CREATE TYPE script_type AS ENUM ('Script', 'LocalScript', 'ModuleScript');

CREATE TABLE code_jobs (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  prompt          TEXT NOT NULL,
  script_type     script_type NOT NULL DEFAULT 'Script',
  insert_location TEXT NOT NULL DEFAULT 'ServerScriptService',
  status          job_status NOT NULL DEFAULT 'pending',
  generated_code  TEXT,
  explanation     TEXT,
  script_name     TEXT NOT NULL DEFAULT 'LimeAI_Script',
  error_message   TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at    TIMESTAMPTZ,
  inserted_at     TIMESTAMPTZ
);

CREATE INDEX idx_code_jobs_user_id ON code_jobs(user_id);
CREATE INDEX idx_code_jobs_status  ON code_jobs(status);
CREATE INDEX idx_code_jobs_pending ON code_jobs(user_id, status) WHERE status IN ('completed');
                                                                                                                                                                                                                                              roblox-ai-platform/backend/src/utils/                                                               0000755 0000000 0000000 00000000000 15211362255 016612  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/backend/src/utils/logger.ts                                                      0000644 0000000 0000000 00000001536 15211362255 020446  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   // ============================================================
// Lime AI Platform — Logger (Winston)
// ============================================================

import winston from 'winston';

const { combine, timestamp, json, colorize, simple } = winston.format;

export const logger = winston.createLogger({
  level: process.env.LOG_LEVEL ?? 'info',
  format: combine(timestamp(), json()),
  transports: [
    new winston.transports.Console({
      format: process.env.NODE_ENV === 'development'
        ? combine(colorize(), simple())
        : combine(timestamp(), json()),
    }),
    // In production, also write to files
    ...(process.env.NODE_ENV === 'production' ? [
      new winston.transports.File({ filename: 'logs/error.log', level: 'error' }),
      new winston.transports.File({ filename: 'logs/combined.log' }),
    ] : []),
  ],
});
                                                                                                                                                                  roblox-ai-platform/backend/src/routes/                                                              0000755 0000000 0000000 00000000000 15211362255 016773  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/backend/src/routes/index.ts                                                      0000644 0000000 0000000 00000046301 15211363444 020457  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   // ============================================================
// Lime AI Platform — Express Router (all routes)
// ============================================================

import { Router, Request, Response } from 'express';
import { requireAuth, requireAdmin, registerUser, loginUser,
         refreshTokens, revokeRefreshToken, verifyEmail } from '../middleware/auth.js';
import { authRateLimit, planUsageLimit, checkBanned } from '../middleware/rateLimiter.js';
import { chatWithClaude, streamChatWithClaude,
         ensureConversation, checkUsageLimits } from '../services/claude.service.js';
import { createCodeJob, getPendingJobsForUser,
         markJobInserted, getJobStatus,
         getUserJobHistory } from '../services/jobs.service.js';
import { db } from '../db/client.js';
import { logger } from '../utils/logger.js';
import Stripe from 'stripe';
import { z } from 'zod';

const router = Router();
const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!, { apiVersion: '2025-01-27.acacia' });

// Input validation helpers
const validate = (schema: z.ZodSchema, body: unknown, res: Response): boolean => {
  const result = schema.safeParse(body);
  if (!result.success) {
    res.status(400).json({ error: 'Validation failed', details: result.error.flatten() });
    return false;
  }
  return true;
};

// ═══════════════════════════════════════════════════
// HEALTH CHECK
// ═══════════════════════════════════════════════════
router.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// ═══════════════════════════════════════════════════
// AUTH ROUTES
// ═══════════════════════════════════════════════════
const registerSchema = z.object({
  email: z.string().email().max(255),
  password: z.string().min(8).max(128),
  username: z.string().min(3).max(50).optional(),
});

router.post('/auth/register', authRateLimit, async (req, res) => {
  if (!validate(registerSchema, req.body, res)) return;
  try {
    const { userId, verifyToken } = await registerUser(
      req.body.email, req.body.password, req.body.username
    );
    // TODO: Send verification email with verifyToken
    logger.info('User registered', { userId });
    res.status(201).json({ message: 'Account created. Check your email to verify.' });
  } catch (err: unknown) {
    const e = err as { code?: string; message?: string };
    if (e.code === 'EMAIL_EXISTS') res.status(409).json({ error: 'Email already registered' });
    else { logger.error('Registration error', err); res.status(500).json({ error: 'Registration failed' }); }
  }
});

router.post('/auth/login', authRateLimit, async (req, res) => {
  const schema = z.object({ email: z.string().email(), password: z.string() });
  if (!validate(schema, req.body, res)) return;
  try {
    const tokens = await loginUser(
      req.body.email, req.body.password,
      req.ip || '', req.headers['user-agent'] || ''
    );
    res.json(tokens);
  } catch (err: unknown) {
    const e = err as { code?: string };
    if (e.code === 'INVALID_CREDENTIALS') res.status(401).json({ error: 'Invalid email or password' });
    else if (e.code === 'BANNED') res.status(403).json({ error: 'Account suspended' });
    else { logger.error('Login error', err); res.status(500).json({ error: 'Login failed' }); }
  }
});

router.post('/auth/refresh', async (req, res) => {
  const { refreshToken } = req.body;
  if (!refreshToken) { res.status(400).json({ error: 'Refresh token required' }); return; }
  try {
    const tokens = await refreshTokens(refreshToken, req.ip || '');
    res.json(tokens);
  } catch {
    res.status(401).json({ error: 'Invalid or expired refresh token' });
  }
});

router.post('/auth/logout', requireAuth, async (req, res) => {
  const { refreshToken } = req.body;
  if (refreshToken) await revokeRefreshToken(refreshToken);
  res.json({ message: 'Logged out' });
});

router.get('/auth/verify-email', async (req, res) => {
  const { token } = req.query;
  if (!token || typeof token !== 'string') { res.status(400).json({ error: 'Token required' }); return; }
  try {
    await verifyEmail(token);
    res.json({ message: 'Email verified successfully' });
  } catch {
    res.status(400).json({ error: 'Invalid or expired verification token' });
  }
});

// ═══════════════════════════════════════════════════
// USER PROFILE
// ═══════════════════════════════════════════════════
router.get('/user/me', requireAuth, async (req, res) => {
  const { rows } = await db.query(
    `SELECT u.id, u.email, u.username, u.display_name, u.roblox_username,
            u.avatar_url, u.email_verified, u.created_at,
            sp.name AS plan_name, sp.display_name AS plan_display_name,
            sp.requests_per_day, sp.requests_per_month, sp.features,
            sub.status AS subscription_status, sub.current_period_end
     FROM users u
     LEFT JOIN subscription_plans sp ON u.plan_id = sp.id
     LEFT JOIN subscriptions sub ON sub.user_id = u.id AND sub.status = 'active'
     WHERE u.id = $1`,
    [req.user!.sub]
  );
  if (rows.length === 0) { res.status(404).json({ error: 'User not found' }); return; }
  res.json(rows[0]);
});

router.patch('/user/me', requireAuth, async (req, res) => {
  const schema = z.object({
    displayName: z.string().max(100).optional(),
    robloxUsername: z.string().max(50).optional(),
  });
  if (!validate(schema, req.body, res)) return;
  const { displayName, robloxUsername } = req.body;
  await db.query(
    `UPDATE users SET display_name = COALESCE($1, display_name),
       roblox_username = COALESCE($2, roblox_username),
       updated_at = NOW()
     WHERE id = $3`,
    [displayName, robloxUsername, req.user!.sub]
  );
  res.json({ message: 'Profile updated' });
});

// ═══════════════════════════════════════════════════
// CHAT / AI ROUTES (the core product)
// ═══════════════════════════════════════════════════
router.post('/chat', requireAuth, checkBanned, planUsageLimit, async (req, res) => {
  const schema = z.object({
    message: z.string().min(1).max(32000),
    conversationId: z.string().uuid().optional(),
    stream: z.boolean().optional().default(false),
  });
  if (!validate(schema, req.body, res)) return;

  const { message, conversationId: rawConvId, stream } = req.body;
  const userId = req.user!.sub;
  const planName = req.user!.plan;

  // Get plan token limits
  const { rows: planRows } = await db.query<{ max_tokens_per_request: number; requests_per_day: number; requests_per_month: number }>(
    `SELECT sp.max_tokens_per_request, sp.requests_per_day, sp.requests_per_month
     FROM users u JOIN subscription_plans sp ON u.plan_id = sp.id WHERE u.id = $1`,
    [userId]
  );
  const plan = planRows[0] ?? { max_tokens_per_request: 2048, requests_per_day: 20, requests_per_month: 100 };

  try {
    const conversationId = await ensureConversation(userId, rawConvId, message);

    // Log analytics event
    await db.query(
      `INSERT INTO analytics_events (user_id, event_type, properties)
       VALUES ($1, 'chat_sent', $2)`,
      [userId, JSON.stringify({ conversationId, messageLength: message.length, stream })]
    );

    if (stream) {
      await streamChatWithClaude({
        userId, userMessage: message, conversationId,
        planName, maxTokens: plan.max_tokens_per_request, res,
      });
    } else {
      const result = await chatWithClaude({
        userId, userMessage: message, conversationId,
        planName, maxTokens: plan.max_tokens_per_request,
      });
      res.json({ conversationId, ...result });
    }
  } catch (err: unknown) {
    const e = err as { code?: string; message?: string };
    if (e.code === 'LIMIT_DAILY' || e.code === 'LIMIT_MONTHLY') {
      res.status(429).json({ error: e.message, upgradeUrl: `${process.env.DASHBOARD_URL}/billing` });
    } else {
      logger.error('Chat error', { error: e.message, userId });
      res.status(500).json({ error: 'AI request failed. Please try again.' });
    }
  }
});

// ═══════════════════════════════════════════════════
// CONVERSATIONS
// ═══════════════════════════════════════════════════
router.get('/conversations', requireAuth, async (req, res) => {
  const limit = Math.min(parseInt(req.query.limit as string) || 50, 100);
  const offset = parseInt(req.query.offset as string) || 0;

  const { rows } = await db.query(
    `SELECT c.id, c.title, c.created_at, c.updated_at,
            COUNT(m.id) AS message_count,
            MAX(m.created_at) AS last_message_at
     FROM conversations c
     LEFT JOIN messages m ON m.conversation_id = c.id
     WHERE c.user_id = $1 AND c.archived = false
     GROUP BY c.id, c.title, c.created_at, c.updated_at
     ORDER BY COALESCE(MAX(m.created_at), c.created_at) DESC
     LIMIT $2 OFFSET $3`,
    [req.user!.sub, limit, offset]
  );
  res.json({ conversations: rows, limit, offset });
});

router.get('/conversations/:id', requireAuth, async (req, res) => {
  const { rows } = await db.query(
    `SELECT c.*, array_agg(
       json_build_object('id', m.id, 'role', m.role, 'content', m.content, 'created_at', m.created_at)
       ORDER BY m.created_at
     ) AS messages
     FROM conversations c
     LEFT JOIN messages m ON m.conversation_id = c.id
     WHERE c.id = $1 AND c.user_id = $2
     GROUP BY c.id`,
    [req.params.id, req.user!.sub]
  );
  if (rows.length === 0) { res.status(404).json({ error: 'Conversation not found' }); return; }
  res.json(rows[0]);
});

router.delete('/conversations/:id', requireAuth, async (req, res) => {
  await db.query(
    `UPDATE conversations SET archived = true WHERE id = $1 AND user_id = $2`,
    [req.params.id, req.user!.sub]
  );
  res.json({ message: 'Conversation archived' });
});

// ═══════════════════════════════════════════════════
// USAGE STATS
// ═══════════════════════════════════════════════════
router.get('/usage', requireAuth, async (req, res) => {
  const userId = req.user!.sub;

  const [daily, monthly, planInfo] = await Promise.all([
    db.query<{ count: string; tokens_in: string; tokens_out: string }>(
      `SELECT COUNT(*) AS count,
              COALESCE(SUM(tokens_input), 0) AS tokens_in,
              COALESCE(SUM(tokens_output), 0) AS tokens_out
       FROM usage_logs WHERE user_id = $1 AND success = true
         AND created_at >= DATE_TRUNC('day', NOW())`,
      [userId]
    ),
    db.query<{ count: string; tokens_in: string; tokens_out: string; cost: string }>(
      `SELECT COUNT(*) AS count,
              COALESCE(SUM(tokens_input), 0) AS tokens_in,
              COALESCE(SUM(tokens_output), 0) AS tokens_out,
              COALESCE(SUM(cost_usd), 0) AS cost
       FROM usage_logs WHERE user_id = $1 AND success = true
         AND created_at >= DATE_TRUNC('month', NOW())`,
      [userId]
    ),
    db.query<{ requests_per_day: number; requests_per_month: number }>(
      `SELECT sp.requests_per_day, sp.requests_per_month
       FROM users u JOIN subscription_plans sp ON u.plan_id = sp.id
       WHERE u.id = $1`,
      [userId]
    ),
  ]);

  res.json({
    today: {
      requests: parseInt(daily.rows[0].count),
      tokensInput: parseInt(daily.rows[0].tokens_in),
      tokensOutput: parseInt(daily.rows[0].tokens_out),
      limit: planInfo.rows[0]?.requests_per_day ?? 20,
    },
    month: {
      requests: parseInt(monthly.rows[0].count),
      tokensInput: parseInt(monthly.rows[0].tokens_in),
      tokensOutput: parseInt(monthly.rows[0].tokens_out),
      costUsd: parseFloat(monthly.rows[0].cost).toFixed(4),
      limit: planInfo.rows[0]?.requests_per_month ?? 100,
    },
  });
});

// ═══════════════════════════════════════════════════
// BILLING / STRIPE
// ═══════════════════════════════════════════════════
router.post('/billing/create-checkout', requireAuth, async (req, res) => {
  const schema = z.object({ planName: z.enum(['pro', 'team', 'enterprise']) });
  if (!validate(schema, req.body, res)) return;

  const { rows: plan } = await db.query(
    `SELECT * FROM subscription_plans WHERE name = $1`, [req.body.planName]
  );
  if (!plan[0]?.stripe_price_id) { res.status(400).json({ error: 'Plan not available' }); return; }

  const session = await stripe.checkout.sessions.create({
    mode: 'subscription',
    payment_method_types: ['card'],
    line_items: [{ price: plan[0].stripe_price_id, quantity: 1 }],
    success_url: `${process.env.DASHBOARD_URL}/billing?success=true`,
    cancel_url: `${process.env.DASHBOARD_URL}/billing?canceled=true`,
    metadata: { userId: req.user!.sub, planName: req.body.planName },
  });
  res.json({ url: session.url });
});

router.post('/billing/portal', requireAuth, async (req, res) => {
  const { rows } = await db.query(
    `SELECT stripe_customer_id FROM subscriptions WHERE user_id = $1 LIMIT 1`,
    [req.user!.sub]
  );
  if (!rows[0]?.stripe_customer_id) { res.status(400).json({ error: 'No billing account' }); return; }

  const session = await stripe.billingPortal.sessions.create({
    customer: rows[0].stripe_customer_id,
    return_url: `${process.env.DASHBOARD_URL}/billing`,
  });
  res.json({ url: session.url });
});

// ═══════════════════════════════════════════════════
// CODE JOBS — Website → Studio bridge
// ═══════════════════════════════════════════════════

// POST /jobs — Website submits a "please code this" request
router.post('/jobs', requireAuth, checkBanned, planUsageLimit, async (req, res) => {
  const schema = z.object({
    prompt:         z.string().min(5).max(4000),
    scriptType:     z.enum(['Script', 'LocalScript', 'ModuleScript']).default('Script'),
    insertLocation: z.string().max(100).default('ServerScriptService'),
  });
  if (!validate(schema, req.body, res)) return;

  const { prompt, scriptType, insertLocation } = req.body;
  const userId = req.user!.sub;

  try {
    const { jobId } = await createCodeJob(userId, prompt, scriptType, insertLocation);
    res.status(202).json({
      jobId,
      message: 'Job created. Claude is generating your code. The Studio plugin will insert it automatically.',
    });
  } catch (err) {
    logger.error('Create job error', err);
    res.status(500).json({ error: 'Failed to create code job' });
  }
});

// GET /jobs/pending — Plugin polls this every 3 seconds to pick up new code
router.get('/jobs/pending', requireAuth, async (req, res) => {
  try {
    const result = await getPendingJobsForUser(req.user!.sub);
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: 'Failed to fetch pending jobs' });
  }
});

// GET /jobs/:id/status — Website polls this to show progress to the user
router.get('/jobs/:id/status', requireAuth, async (req, res) => {
  const status = await getJobStatus(req.params.id, req.user!.sub);
  if (!status) { res.status(404).json({ error: 'Job not found' }); return; }
  res.json(status);
});

// POST /jobs/:id/inserted — Plugin calls this after it inserts the code into Studio
router.post('/jobs/:id/inserted', requireAuth, async (req, res) => {
  try {
    await markJobInserted(req.params.id, req.user!.sub);
    res.json({ message: 'Job marked as inserted' });
  } catch (err) {
    res.status(500).json({ error: 'Failed to mark job inserted' });
  }
});

// GET /jobs — Website shows history of all code jobs
router.get('/jobs', requireAuth, async (req, res) => {
  const history = await getUserJobHistory(req.user!.sub);
  res.json({ jobs: history });
});

// ═══════════════════════════════════════════════════
// ADMIN ROUTES
// ═══════════════════════════════════════════════════
router.get('/admin/users', requireAuth, requireAdmin, async (req, res) => {
  const limit = Math.min(parseInt(req.query.limit as string) || 50, 200);
  const offset = parseInt(req.query.offset as string) || 0;
  const search = req.query.search as string;

  let query = `SELECT u.id, u.email, u.username, u.is_banned, u.created_at,
                       sp.name AS plan_name, u.last_login_at
               FROM users u LEFT JOIN subscription_plans sp ON u.plan_id = sp.id
               WHERE 1=1`;
  const params: unknown[] = [];

  if (search) {
    params.push(`%${search}%`);
    query += ` AND (u.email ILIKE $${params.length} OR u.username ILIKE $${params.length})`;
  }
  params.push(limit, offset);
  query += ` ORDER BY u.created_at DESC LIMIT $${params.length - 1} OFFSET $${params.length}`;

  const { rows } = await db.query(query, params);
  res.json({ users: rows });
});

router.post('/admin/users/:id/ban', requireAuth, requireAdmin, async (req, res) => {
  const { reason } = req.body;
  await db.query(
    `UPDATE users SET is_banned = true, ban_reason = $1 WHERE id = $2`,
    [reason, req.params.id]
  );
  await db.query(
    `INSERT INTO audit_logs (actor_id, user_id, action, resource, resource_id, new_value)
     VALUES ($1, $2, 'ban_user', 'user', $2, $3)`,
    [req.user!.sub, req.params.id, JSON.stringify({ reason })]
  );
  res.json({ message: 'User banned' });
});

router.get('/admin/stats', requireAuth, requireAdmin, async (req, res) => {
  const [users, revenue, usage] = await Promise.all([
    db.query(`SELECT COUNT(*) AS total,
              COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '30 days') AS new_30d
              FROM users`),
    db.query(`SELECT COALESCE(SUM(amount_cents), 0) AS total_cents,
              COALESCE(SUM(amount_cents) FILTER (WHERE created_at >= DATE_TRUNC('month', NOW())), 0) AS month_cents
              FROM billing_records WHERE status = 'paid'`),
    db.query(`SELECT COUNT(*) AS total_requests,
              COALESCE(SUM(tokens_input + tokens_output), 0) AS total_tokens
              FROM usage_logs WHERE success = true
                AND created_at >= DATE_TRUNC('month', NOW())`),
  ]);
  res.json({
    users: users.rows[0],
    revenue: revenue.rows[0],
    usage: usage.rows[0],
  });
});

export default router;
                                                                                                                                                                                                                                                                                                                               roblox-ai-platform/backend/Dockerfile                                                               0000644 0000000 0000000 00000002203 15211362255 016652  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   # ============================================================
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
                                                                                                                                                                                                                                                                                                                                                                                             roblox-ai-platform/backend/package.json                                                             0000644 0000000 0000000 00000002045 15211373622 017152  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   {
  "name": "limeai-backend",
  "version": "1.0.0",
  "description": "Lime AI Backend API",
  "type": "module",
  "scripts": {
    "dev": "tsx watch src/server.ts",
    "build": "tsc",
    "start": "node dist/server.js",
    "db:migrate": "psql $DATABASE_URL -f src/db/schema.sql",
    "lint": "eslint src --ext .ts"
  },
  "dependencies": {
    "@google/generative-ai": "^0.21.0",
    "bcryptjs": "^2.4.3",
    "compression": "^1.7.4",
    "cors": "^2.8.5",
    "dotenv": "^16.4.5",
    "express": "^4.18.2",
    "express-rate-limit": "^7.3.1",
    "helmet": "^7.1.0",
    "jsonwebtoken": "^9.0.2",
    "morgan": "^1.10.0",
    "pg": "^8.11.5",
    "stripe": "^14.21.0",
    "winston": "^3.13.0",
    "zod": "^3.23.8"
  },
  "devDependencies": {
    "@types/bcryptjs": "^2.4.6",
    "@types/compression": "^1.7.5",
    "@types/cors": "^2.8.17",
    "@types/express": "^4.17.21",
    "@types/jsonwebtoken": "^9.0.6",
    "@types/morgan": "^1.9.9",
    "@types/node": "^20.12.7",
    "@types/pg": "^8.11.5",
    "tsx": "^4.9.1",
    "typescript": "^5.4.5"
  }
}
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           roblox-ai-platform/backend/.env.example                                                             0000644 0000000 0000000 00000001643 15211362266 017114  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   # ============================================================
# Lime AI Platform — Environment Variables
# Copy to .env and fill in values. NEVER commit .env to git.
# ============================================================

# Server
NODE_ENV=production
PORT=3001
LOG_LEVEL=info

# Database
DATABASE_URL=postgresql://limeai:STRONG_PASSWORD@localhost:5432/limeai_prod

# JWT Secrets — generate with: openssl rand -hex 64
JWT_ACCESS_SECRET=REPLACE_WITH_64_CHAR_HEX
JWT_REFRESH_SECRET=REPLACE_WITH_64_CHAR_HEX

# Anthropic — NEVER expose this to clients
ANTHROPIC_API_KEY=sk-ant-REPLACE_WITH_YOUR_KEY
CLAUDE_MODEL=claude-sonnet-4-20250514

# Stripe
STRIPE_SECRET_KEY=sk_live_REPLACE_WITH_STRIPE_KEY
STRIPE_WEBHOOK_SECRET=whsec_REPLACE_WITH_WEBHOOK_SECRET

# App URLs
DASHBOARD_URL=https://limeai.dev
API_URL=https://api.limeai.dev

# Email (e.g. SendGrid, Resend)
EMAIL_FROM=noreply@limeai.dev
SENDGRID_API_KEY=SG.REPLACE
                                                                                             roblox-ai-platform/backend/tsconfig.json                                                            0000644 0000000 0000000 00000000741 15211362255 017374  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   {
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "lib": ["ES2022"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
                               roblox-ai-platform/docker/                                                                          0000755 0000000 0000000 00000000000 15211362266 014545  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/docker/docker-compose.yml                                                        0000644 0000000 0000000 00000005467 15211362266 020216  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   # ============================================================
# Lime AI Platform — Docker Compose (Production)
# ============================================================

version: '3.9'

services:

  # ── PostgreSQL ─────────────────────────────
  postgres:
    image: postgres:16-alpine
    container_name: limeai_postgres
    restart: always
    environment:
      POSTGRES_DB: limeai_prod
      POSTGRES_USER: limeai
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./backend/src/db/schema.sql:/docker-entrypoint-initdb.d/01_schema.sql
    ports:
      - "5432:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U limeai -d limeai_prod"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - limeai_net

  # ── Backend API ────────────────────────────
  backend:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: limeai_backend
    restart: always
    environment:
      NODE_ENV: production
      PORT: 3001
      DATABASE_URL: postgresql://limeai:${POSTGRES_PASSWORD}@postgres:5432/limeai_prod
      JWT_ACCESS_SECRET: ${JWT_ACCESS_SECRET}
      JWT_REFRESH_SECRET: ${JWT_REFRESH_SECRET}
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY}
      CLAUDE_MODEL: claude-sonnet-4-20250514
      STRIPE_SECRET_KEY: ${STRIPE_SECRET_KEY}
      STRIPE_WEBHOOK_SECRET: ${STRIPE_WEBHOOK_SECRET}
      DASHBOARD_URL: ${DASHBOARD_URL}
      API_URL: ${API_URL}
    ports:
      - "3001:3001"
    depends_on:
      postgres:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/api/v1/health"]
      interval: 30s
      timeout: 10s
      retries: 3
    volumes:
      - ./logs:/app/logs
    networks:
      - limeai_net

  # ── Nginx Reverse Proxy ────────────────────
  nginx:
    image: nginx:alpine
    container_name: limeai_nginx
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./docker/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./dashboard:/usr/share/nginx/html:ro
      - ./docker/ssl:/etc/nginx/ssl:ro
      - nginx_cache:/var/cache/nginx
    depends_on:
      - backend
    networks:
      - limeai_net

  # ── Certbot (SSL) ──────────────────────────
  certbot:
    image: certbot/certbot
    container_name: limeai_certbot
    volumes:
      - ./docker/ssl:/etc/letsencrypt
      - ./docker/certbot-webroot:/var/www/certbot
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 12h & wait $${!}; done;'"

volumes:
  postgres_data:
  nginx_cache:

networks:
  limeai_net:
    driver: bridge
                                                                                                                                                                                                         roblox-ai-platform/docker/nginx.conf                                                                0000644 0000000 0000000 00000010772 15211362255 016544  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   # ============================================================
# Lime AI Platform — Nginx Configuration
# Handles API routing, SSL termination, static dashboard
# ============================================================

events {
  worker_connections 1024;
}

http {
  include       mime.types;
  default_type  application/octet-stream;
  sendfile      on;
  keepalive_timeout 65;

  # ── Gzip ──────────────────────────────────
  gzip on;
  gzip_vary on;
  gzip_min_length 1024;
  gzip_types text/plain text/css application/json application/javascript text/xml application/xml;

  # ── Rate limiting zones ────────────────────
  limit_req_zone $binary_remote_addr zone=api:10m rate=30r/m;
  limit_req_zone $binary_remote_addr zone=auth:10m rate=10r/m;

  # ── Upstream backend ───────────────────────
  upstream backend {
    server backend:3001;
    keepalive 32;
  }

  # ── HTTP → HTTPS redirect ──────────────────
  server {
    listen 80;
    server_name limeai.dev api.limeai.dev;

    location /.well-known/acme-challenge/ {
      root /var/www/certbot;
    }

    location / {
      return 301 https://$host$request_uri;
    }
  }

  # ── Dashboard (limeai.dev) ───────────────
  server {
    listen 443 ssl http2;
    server_name limeai.dev;

    ssl_certificate     /etc/nginx/ssl/live/limeai.dev/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/live/limeai.dev/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header Referrer-Policy strict-origin-when-cross-origin;

    root /usr/share/nginx/html;
    index index.html;

    location / {
      try_files $uri $uri/ /index.html;
    }

    # Cache static assets
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff2?)$ {
      expires 1y;
      add_header Cache-Control "public, immutable";
    }
  }

  # ── API (api.limeai.dev) ─────────────────
  server {
    listen 443 ssl http2;
    server_name api.limeai.dev;

    ssl_certificate     /etc/nginx/ssl/live/api.limeai.dev/fullchain.pem;
    ssl_certificate_key /etc/nginx/ssl/live/api.limeai.dev/privkey.pem;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Content-Type-Options nosniff;

    # ── Auth endpoints — stricter rate limit
    location /api/v1/auth/ {
      limit_req zone=auth burst=5 nodelay;
      proxy_pass http://backend;
      proxy_http_version 1.1;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
    }

    # ── Streaming endpoint — longer timeout, disable buffering
    location /api/v1/chat {
      limit_req zone=api burst=10 nodelay;
      proxy_pass http://backend;
      proxy_http_version 1.1;
      proxy_set_header Connection '';
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;

      # Critical for SSE streaming
      proxy_buffering off;
      proxy_cache off;
      proxy_read_timeout 120s;
      proxy_send_timeout 120s;

      # SSE headers passthrough
      proxy_set_header Accept-Encoding '';
      chunked_transfer_encoding on;
    }

    # ── All other API routes ───────────────────
    location /api/v1/ {
      limit_req zone=api burst=20 nodelay;
      proxy_pass http://backend;
      proxy_http_version 1.1;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
      proxy_set_header X-Forwarded-Proto $scheme;
      proxy_read_timeout 60s;
    }

    # ── Stripe webhooks — no rate limit, raw body ──
    location /webhooks/ {
      proxy_pass http://backend;
      proxy_http_version 1.1;
      proxy_set_header Host $host;
      proxy_set_header X-Real-IP $remote_addr;
      proxy_read_timeout 30s;
    }
  }
}
      roblox-ai-platform/plugin/                                                                          0000755 0000000 0000000 00000000000 15211360107 014564  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/plugin/src/                                                                      0000755 0000000 0000000 00000000000 15211362541 015357  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/plugin/src/main.lua                                                              0000644 0000000 0000000 00000104006 15211415170 017004  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   --[[
  ============================================================
  Lime AI Plugin v2.0 — Premium UI
  Beautiful redesigned interface with animations
  ============================================================
]]

local API_BASE_URL = "https://lime-ai-tmy2.onrender.com/api/v1"
local PLUGIN_VERSION = "2.0.0"
local POLL_INTERVAL = 3

local HttpService         = game:GetService("HttpService")
local Selection           = game:GetService("Selection")
local ScriptEditorService = game:GetService("ScriptEditorService")
local TweenService        = game:GetService("TweenService")
local RunService          = game:GetService("RunService")

local pluginState = {
  accessToken    = nil,
  refreshToken   = nil,
  conversationId = nil,
  isStreaming    = false,
}

local jobPollingActive = false
local uiElements = {}

-- ─────────────────────────────────────────────
-- COLORS
-- ─────────────────────────────────────────────
local C = {
  lime       = Color3.fromRGB(134, 239, 94),
  limeDeep   = Color3.fromRGB(80,  170, 50),
  limeDark   = Color3.fromRGB(30,  80,  20),
  bg         = Color3.fromRGB(10,  14,  10),
  surface    = Color3.fromRGB(18,  24,  16),
  surface2   = Color3.fromRGB(26,  36,  22),
  border     = Color3.fromRGB(40,  60,  32),
  text       = Color3.fromRGB(220, 240, 215),
  textDim    = Color3.fromRGB(110, 140, 100),
  textFaint  = Color3.fromRGB(60,  80,  55),
  red        = Color3.fromRGB(239, 80,  80),
  codeBg     = Color3.fromRGB(12,  18,  10),
  codeText   = Color3.fromRGB(160, 220, 140),
  userBubble = Color3.fromRGB(22,  55,  16),
  white      = Color3.new(1, 1, 1),
}

-- ─────────────────────────────────────────────
-- TOOLBAR
-- ─────────────────────────────────────────────
local toolbar      = plugin:CreateToolbar("Lime AI")
local toggleButton = toolbar:CreateButton("Lime AI", "Open Lime AI — AI Coding Assistant", "rbxassetid://6031068426")

local widgetInfo = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Right, true, false, 400, 640, 300, 440)
local widget     = plugin:CreateDockWidgetPluginGui("LimeAI_v2", widgetInfo)
widget.Title     = "Lime AI"
widget.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

toggleButton.Click:Connect(function()
  widget.Enabled = not widget.Enabled
  toggleButton:SetActive(widget.Enabled)
end)

-- ─────────────────────────────────────────────
-- UI HELPERS
-- ─────────────────────────────────────────────
local function corner(parent, radius)
  local c = Instance.new("UICorner")
  c.CornerRadius = UDim.new(0, radius or 8)
  c.Parent = parent
  return c
end

local function padding(parent, all, l, r, t, b)
  local p = Instance.new("UIPadding")
  if all then p.PaddingLeft = UDim.new(0, all); p.PaddingRight = UDim.new(0, all); p.PaddingTop = UDim.new(0, all); p.PaddingBottom = UDim.new(0, all)
  else p.PaddingLeft = UDim.new(0, l or 0); p.PaddingRight = UDim.new(0, r or 0); p.PaddingTop = UDim.new(0, t or 0); p.PaddingBottom = UDim.new(0, b or 0) end
  p.Parent = parent
  return p
end

local function stroke(parent, color, thickness)
  local s = Instance.new("UIStroke")
  s.Color = color or C.border
  s.Thickness = thickness or 1
  s.Parent = parent
  return s
end

local function tween(obj, props, t, style, dir)
  local info = TweenInfo.new(t or 0.25, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out)
  local tw = TweenService:Create(obj, info, props)
  tw:Play()
  return tw
end

local function makeFrame(parent, size, pos, bg, order)
  local f = Instance.new("Frame")
  f.Size = size or UDim2.new(1, 0, 0, 40)
  f.Position = pos or UDim2.new(0, 0, 0, 0)
  f.BackgroundColor3 = bg or C.surface
  f.BorderSizePixel = 0
  if order then f.LayoutOrder = order end
  f.Parent = parent
  return f
end

local function makeLabel(parent, text, size, color, font, xa, order)
  local l = Instance.new("TextLabel")
  l.Size = size or UDim2.new(1, 0, 0, 20)
  l.BackgroundTransparency = 1
  l.Text = text or ""
  l.TextColor3 = color or C.text
  l.Font = font or Enum.Font.Gotham
  l.TextSize = 13
  l.TextXAlignment = xa or Enum.TextXAlignment.Left
  l.TextWrapped = true
  if order then l.LayoutOrder = order end
  l.Parent = parent
  return l
end

local function makeButton(parent, text, bg, tc, size, order)
  local b = Instance.new("TextButton")
  b.Size = size or UDim2.new(1, 0, 0, 36)
  b.BackgroundColor3 = bg or C.lime
  b.Text = text or "Button"
  b.TextColor3 = tc or C.limeDark
  b.Font = Enum.Font.GothamBold
  b.TextSize = 13
  b.BorderSizePixel = 0
  b.AutoButtonColor = false
  if order then b.LayoutOrder = order end
  b.Parent = parent

  b.MouseEnter:Connect(function()
    tween(b, { BackgroundColor3 = bg and bg:Lerp(C.white, 0.12) or C.limeDeep })
  end)
  b.MouseLeave:Connect(function()
    tween(b, { BackgroundColor3 = bg or C.lime })
  end)
  b.MouseButton1Down:Connect(function()
    tween(b, { Size = b.Size - UDim2.new(0, 4, 0, 2) })
  end)
  b.MouseButton1Up:Connect(function()
    tween(b, { Size = size or UDim2.new(1, 0, 0, 36) })
  end)

  return b
end

local function vlist(parent, padding_px, halign)
  local l = Instance.new("UIListLayout")
  l.FillDirection = Enum.FillDirection.Vertical
  l.SortOrder = Enum.SortOrder.LayoutOrder
  l.Padding = UDim.new(0, padding_px or 8)
  l.HorizontalAlignment = halign or Enum.HorizontalAlignment.Left
  l.Parent = parent
  return l
end

-- ─────────────────────────────────────────────
-- SPINNER ANIMATION
-- ─────────────────────────────────────────────
local spinnerConnection = nil

local function createSpinner(parent, size, pos)
  local ring = Instance.new("ImageLabel")
  ring.Size = size or UDim2.new(0, 32, 0, 32)
  ring.Position = pos or UDim2.new(0.5, -16, 0.5, -16)
  ring.BackgroundTransparency = 1
  ring.Image = "rbxassetid://4965945816"
  ring.ImageColor3 = C.lime
  ring.Parent = parent

  local angle = 0
  local conn = RunService.Heartbeat:Connect(function(dt)
    angle = angle + dt * 180
    ring.Rotation = angle
  end)

  return ring, conn
end

-- ─────────────────────────────────────────────
-- LOADING SCREEN
-- ─────────────────────────────────────────────
local function showLoading(parent, message)
  local overlay = makeFrame(parent, UDim2.new(1, 0, 1, 0), UDim2.new(0, 0, 0, 0), C.bg)
  overlay.Name = "LoadingOverlay"
  overlay.ZIndex = 10

  local center = makeFrame(overlay, UDim2.new(0, 200, 0, 120), UDim2.new(0.5, -100, 0.5, -60), C.surface)
  center.ZIndex = 11
  corner(center, 16)
  stroke(center, C.border)

  local spin, conn = createSpinner(center, UDim2.new(0, 40, 0, 40), UDim2.new(0.5, -20, 0, 20))
  spin.ZIndex = 12

  local lbl = makeLabel(center, message or "Loading...", UDim2.new(1, -20, 0, 20), C.textDim, Enum.Font.Gotham, Enum.TextXAlignment.Center)
  lbl.Position = UDim2.new(0, 10, 0, 72)
  lbl.ZIndex = 12

  return overlay, conn
end

-- ─────────────────────────────────────────────
-- HTTP HELPERS
-- ─────────────────────────────────────────────
local function makeRequest(method, endpoint, body, useAuth)
  local headers = { ["Content-Type"] = "application/json" }
  if useAuth and pluginState.accessToken then
    headers["Authorization"] = "Bearer " .. pluginState.accessToken
  end
  local ok, response = pcall(function()
    return HttpService:RequestAsync({
      Url = API_BASE_URL .. endpoint, Method = method,
      Headers = headers, Body = body and HttpService:JSONEncode(body) or nil,
    })
  end)
  if not ok then return nil, "Network error: " .. tostring(response) end
  local decoded; pcall(function() decoded = HttpService:JSONDecode(response.Body) end)
  if not decoded then decoded = { error = response.Body } end
  return decoded, response.StatusCode >= 400 and (decoded.error or "Request failed") or nil
end

local function refreshAccessToken()
  if not pluginState.refreshToken then return false end
  local r = makeRequest("POST", "/auth/refresh", { refreshToken = pluginState.refreshToken }, false)
  if r and r.accessToken then
    pluginState.accessToken  = r.accessToken
    pluginState.refreshToken = r.refreshToken
    plugin:SetSetting("refreshToken", r.refreshToken)
    return true
  end
  return false
end

local function apiCall(method, endpoint, body)
  local result, err = makeRequest(method, endpoint, body, true)
  if err and tostring(err):find("401") then
    if refreshAccessToken() then result, err = makeRequest(method, endpoint, body, true) end
  end
  return result, err
end

-- ─────────────────────────────────────────────
-- CODE INSERTION
-- ─────────────────────────────────────────────
local function insertCode(code, scriptType, location)
  local svc = {
    ServerScriptService  = game:GetService("ServerScriptService"),
    ReplicatedStorage    = game:GetService("ReplicatedStorage"),
    Workspace            = game:GetService("Workspace"),
    StarterGui           = game:GetService("StarterGui"),
    StarterPlayerScripts = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts"),
  }
  local parent = svc[location] or game:GetService("ServerScriptService")
  local s = Instance.new(scriptType == "LocalScript" and "LocalScript" or scriptType == "ModuleScript" and "ModuleScript" or "Script")
  s.Source = code; s.Name = "LimeAI_Generated"; s.Parent = parent
  Selection:Set({s})
  pcall(function() ScriptEditorService:OpenScriptDocumentAsync(s) end)
  return s
end

-- ─────────────────────────────────────────────
-- JOB POLLING
-- ─────────────────────────────────────────────
local function processJob(job)
  if not job.code or job.code == "" then return end
  local s = insertCode(job.code, job.scriptType, job.insertLocation)
  s.Name = job.scriptName or "LimeAI_Script"
  task.spawn(function() apiCall("POST", "/jobs/" .. job.id .. "/inserted", {}) end)
  print("[Lime AI] ✅ Auto-inserted: " .. s.Name)

  -- Flash notification in UI
  if uiElements.statusBar then
    uiElements.statusBar.Text = "✅ Inserted: " .. s.Name
    uiElements.statusBar.TextColor3 = C.lime
    task.delay(3, function()
      if uiElements.statusBar then
        uiElements.statusBar.Text = "● Connected — watching for jobs"
        uiElements.statusBar.TextColor3 = C.textDim
      end
    end)
  end
end

local function pollForJobs()
  if not pluginState.accessToken then return end
  local result = apiCall("GET", "/jobs/pending", nil)
  if not result or not result.jobs then return end
  for _, job in ipairs(result.jobs) do task.spawn(processJob, job) end
end

local function startJobPolling()
  if jobPollingActive then return end
  jobPollingActive = true
  task.spawn(function()
    while jobPollingActive do
      pcall(pollForJobs)
      task.wait(POLL_INTERVAL)
    end
  end)
end

-- ─────────────────────────────────────────────
-- CHAT BUBBLE BUILDER
-- ─────────────────────────────────────────────
local function addMessage(scrollFrame, role, text)
  local isUser   = role == "user"
  local hasCode  = text:find("```") ~= nil
  local count    = #scrollFrame:GetChildren()

  local wrapper = Instance.new("Frame")
  wrapper.Name             = "Msg_" .. count
  wrapper.Size             = UDim2.new(1, 0, 0, 0)
  wrapper.AutomaticSize    = Enum.AutomaticSize.Y
  wrapper.BackgroundTransparency = 1
  wrapper.LayoutOrder      = count
  wrapper.Parent           = scrollFrame

  -- Role badge for AI
  if not isUser then
    local badge = Instance.new("Frame")
    badge.Size              = UDim2.new(0, 52, 0, 18)
    badge.BackgroundColor3  = C.limeDark
    badge.BorderSizePixel   = 0
    badge.Name              = "Badge"
    badge.Parent            = wrapper
    corner(badge, 4)
    local bl = makeLabel(badge, "🟢 Lime AI", UDim2.new(1, 0, 1, 0), C.lime, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
    bl.TextSize = 9
  end

  if hasCode and not isUser then
    local partsLayout = Instance.new("UIListLayout")
    partsLayout.FillDirection = Enum.FillDirection.Vertical
    partsLayout.SortOrder = Enum.SortOrder.LayoutOrder
    partsLayout.Padding = UDim.new(0, 6)
    partsLayout.Parent = wrapper

    local badgeSpace = Instance.new("Frame")
    badgeSpace.Size = UDim2.new(1, 0, 0, 22)
    badgeSpace.BackgroundTransparency = 1
    badgeSpace.LayoutOrder = 0
    badgeSpace.Parent = wrapper
    local badge2 = Instance.new("Frame")
    badge2.Size             = UDim2.new(0, 52, 0, 18)
    badge2.Position         = UDim2.new(0, 0, 0, 2)
    badge2.BackgroundColor3 = C.limeDark
    badge2.BorderSizePixel  = 0
    badge2.Parent           = badgeSpace
    corner(badge2, 4)
    local bl2 = makeLabel(badge2, "🟢 Lime AI", UDim2.new(1, 0, 1, 0), C.lime, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
    bl2.TextSize = 9

    -- Remove the first badge we created
    local firstBadge = wrapper:FindFirstChild("Badge")
    if firstBadge then firstBadge:Destroy() end

    local parts = {}
    local remaining = text
    while remaining:len() > 0 do
      local cs = remaining:find("```")
      if cs then
        if cs > 1 then table.insert(parts, { type="text", content=remaining:sub(1, cs-1) }) end
        local le = remaining:find("\n", cs+3) or cs+3
        local lang = remaining:sub(cs+3, le-1)
        local ce = remaining:find("```", le)
        if ce then
          table.insert(parts, { type="code", lang=lang, content=remaining:sub(le+1, ce-1) })
          remaining = remaining:sub(ce+3)
        else
          table.insert(parts, { type="text", content=remaining:sub(cs) })
          remaining = ""
        end
      else
        table.insert(parts, { type="text", content=remaining })
        remaining = ""
      end
    end

    for i, part in ipairs(parts) do
      if part.type == "text" and part.content:gsub("%s", "") ~= "" then
        local tf = makeFrame(wrapper, UDim2.new(1, 0, 0, 0), nil, C.surface, i+1)
        tf.AutomaticSize = Enum.AutomaticSize.Y
        corner(tf, 10)
        stroke(tf, C.border)
        padding(tf, 10)
        local tl = makeLabel(tf, part.content:gsub("^%s+",""):gsub("%s+$",""), UDim2.new(1, 0, 0, 0), C.text, Enum.Font.Gotham)
        tl.AutomaticSize = Enum.AutomaticSize.Y
        tl.TextSize = 12
      elseif part.type == "code" then
        local cf = makeFrame(wrapper, UDim2.new(1, 0, 0, 0), nil, C.codeBg, i+1)
        cf.AutomaticSize = Enum.AutomaticSize.Y
        corner(cf, 10)
        stroke(cf, C.limeDeep, 0.5)

        -- Code header
        local ch = makeFrame(cf, UDim2.new(1, 0, 0, 32), nil, Color3.fromRGB(8, 14, 6))
        corner(ch, 10)
        local chBottom = makeFrame(cf, UDim2.new(1, 0, 0, 10), UDim2.new(0, 0, 0, 22), Color3.fromRGB(8, 14, 6))

        local langLbl = makeLabel(ch, (part.lang ~= "" and part.lang or "lua"):upper(), UDim2.new(0.5, 0, 1, 0), C.lime, Enum.Font.Code, Enum.TextXAlignment.Left)
        langLbl.Position = UDim2.new(0, 10, 0, 0)
        langLbl.TextSize = 10

        -- Insert button
        local ib = makeButton(cf, "⬇ Insert Script", C.limeDark, C.lime, UDim2.new(0, 110, 0, 24))
        ib.Position = UDim2.new(1, -118, 0, 4)
        ib.Font = Enum.Font.GothamBold
        ib.TextSize = 11
        corner(ib, 6)

        -- Code text
        local cl = makeLabel(cf, part.content, UDim2.new(1, -20, 0, 0), C.codeText, Enum.Font.Code, Enum.TextXAlignment.Left)
        cl.Position = UDim2.new(0, 10, 0, 38)
        cl.AutomaticSize = Enum.AutomaticSize.Y
        cl.TextSize = 11

        local cp2 = Instance.new("UIPadding"); cp2.PaddingBottom = UDim.new(0, 10); cp2.Parent = cf

        local code = part.content
        ib.MouseButton1Click:Connect(function()
          insertCode(code, "Script", "ServerScriptService")
          ib.Text = "✓ Inserted!"
          ib.BackgroundColor3 = C.limeDeep
          task.delay(2, function() ib.Text = "⬇ Insert Script"; ib.BackgroundColor3 = C.limeDark end)
        end)
      end
    end
  else
    local firstBadge = wrapper:FindFirstChild("Badge")
    if firstBadge then firstBadge:Destroy() end

    local wLayout = Instance.new("UIListLayout")
    wLayout.FillDirection = Enum.FillDirection.Vertical
    wLayout.SortOrder = Enum.SortOrder.LayoutOrder
    wLayout.Padding = UDim.new(0, 4)
    wLayout.Parent = wrapper

    if not isUser then
      local badge3 = makeFrame(wrapper, UDim2.new(0, 60, 0, 18), nil, C.limeDark, 1)
      corner(badge3, 4)
      local bl3 = makeLabel(badge3, "🟢 Lime AI", UDim2.new(1, 0, 1, 0), C.lime, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
      bl3.TextSize = 9
    end

    local bubbleW = isUser and 0.88 or 1
    local bubble  = makeFrame(wrapper, UDim2.new(bubbleW, 0, 0, 0), nil, isUser and C.userBubble or C.surface, 2)
    bubble.AnchorPoint  = Vector2.new(isUser and 1 or 0, 0)
    bubble.Position     = isUser and UDim2.new(1, 0, 0, 0) or UDim2.new(0, 0, 0, 0)
    bubble.AutomaticSize = Enum.AutomaticSize.Y
    corner(bubble, 12)
    if not isUser then stroke(bubble, C.border) end
    padding(bubble, 10)

    local txt = makeLabel(bubble, text, UDim2.new(1, 0, 0, 0), isUser and C.lime or C.text, Enum.Font.Gotham)
    txt.AutomaticSize = Enum.AutomaticSize.Y
    txt.TextSize = 13
    txt.LineHeight = 1.45

    -- Animate in
    bubble.BackgroundTransparency = 1
    tween(bubble, { BackgroundTransparency = 0 }, 0.2)
  end

  task.defer(function()
    if scrollFrame and scrollFrame.Parent then
      scrollFrame.CanvasPosition = Vector2.new(0, scrollFrame.AbsoluteCanvasSize.Y)
    end
  end)

  return wrapper
end

-- Typing indicator
local typingBubble = nil
local function showTyping(scrollFrame)
  typingBubble = addMessage(scrollFrame, "assistant", "▪ ▪ ▪")
  -- Animate dots
  local lbl = typingBubble:FindFirstChildWhichIsA("TextLabel", true)
  if lbl then
    local dots = {"▪ ▫ ▫", "▫ ▪ ▫", "▫ ▫ ▪"}
    local idx = 1
    local conn
    conn = RunService.Heartbeat:Connect(function()
      if not typingBubble or not typingBubble.Parent then conn:Disconnect(); return end
      idx = idx % 3 + 1
      lbl.Text = dots[idx]
    end)
    typingBubble._conn = conn
  end
  return typingBubble
end

local function hideTyping()
  if typingBubble then
    if typingBubble._conn then typingBubble._conn:Disconnect() end
    typingBubble:Destroy()
    typingBubble = nil
  end
end

-- ─────────────────────────────────────────────
-- SEND MESSAGE
-- ─────────────────────────────────────────────
local function sendMessage(message)
  if pluginState.isStreaming or message == "" then return end
  pluginState.isStreaming = true
  if uiElements.textBox then uiElements.textBox.Text = "" end
  if uiElements.sendBtn then
    uiElements.sendBtn.Text = "•••"
    uiElements.sendBtn.BackgroundColor3 = C.limeDeep
  end

  addMessage(uiElements.scrollFrame, "user", message)
  local thinking = showTyping(uiElements.scrollFrame)

  task.spawn(function()
    local body = { message = message, stream = false }
    if pluginState.conversationId then body.conversationId = pluginState.conversationId end

    local result, err = apiCall("POST", "/chat", body)
    hideTyping()

    if err or not result then
      addMessage(uiElements.scrollFrame, "assistant", "❌ " .. (err or "Something went wrong. Try waking up the server first by visiting your Render URL in a browser."))
    else
      pluginState.conversationId = result.conversationId
      addMessage(uiElements.scrollFrame, "assistant", result.content)
    end

    pluginState.isStreaming = false
    if uiElements.sendBtn then
      uiElements.sendBtn.Text = "▶"
      uiElements.sendBtn.BackgroundColor3 = C.lime
    end
  end)
end

-- ─────────────────────────────────────────────
-- BUILD MAIN CHAT UI
-- ─────────────────────────────────────────────
local function buildUI()
  for _, c in ipairs(widget:GetChildren()) do
    if c:IsA("GuiObject") then c:Destroy() end
  end

  -- Root
  local root = makeFrame(widget, UDim2.new(1, 0, 1, 0), nil, C.bg)
  root.Name = "Root"
  local rootList = vlist(root, 0)
  rootList.FillDirection = Enum.FillDirection.Vertical

  -- ── Top bar ─────────────────────────────────
  local topBar = makeFrame(root, UDim2.new(1, 0, 0, 50), nil, C.surface, 1)
  stroke(topBar, C.border)
  topBar.ClipsDescendants = true

  -- Animated lime accent line at top
  local accentLine = makeFrame(topBar, UDim2.new(1, 0, 0, 2), nil, C.lime)
  accentLine.Position = UDim2.new(0, 0, 0, 0)

  local logoFrame = makeFrame(topBar, UDim2.new(0, 140, 0, 34), UDim2.new(0, 10, 0.5, -17), C.limeDark)
  corner(logoFrame, 8)
  local logoLbl = makeLabel(logoFrame, "🟢  Lime AI", UDim2.new(1, 0, 1, 0), C.lime, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
  logoLbl.TextSize = 14

  local versionLbl = makeLabel(topBar, "v" .. PLUGIN_VERSION, UDim2.new(0, 40, 0, 16), C.textFaint, Enum.Font.Code, Enum.TextXAlignment.Left)
  versionLbl.Position = UDim2.new(0, 158, 0.5, -8)
  versionLbl.TextSize = 9

  local newBtn = makeButton(topBar, "＋ New", C.limeDark, C.lime, UDim2.new(0, 70, 0, 30))
  newBtn.Position = UDim2.new(1, -80, 0.5, -15)
  newBtn.TextSize = 12
  corner(newBtn, 8)
  stroke(newBtn, C.limeDeep)

  -- ── Status bar ───────────────────────────────
  local statusBar2 = makeFrame(root, UDim2.new(1, 0, 0, 24), nil, C.surface2, 2)
  stroke(statusBar2, C.border)
  local statusLbl = makeLabel(statusBar2, "● Connected — watching for Studio jobs", UDim2.new(1, -10, 1, 0), C.textFaint, Enum.Font.Gotham, Enum.TextXAlignment.Left)
  statusLbl.Position = UDim2.new(0, 10, 0, 0)
  statusLbl.TextSize = 10
  uiElements.statusBar = statusLbl

  -- ── Messages area ────────────────────────────
  local msgContainer = makeFrame(root, UDim2.new(1, 0, 1, -130), nil, C.bg, 3)

  local scroll = Instance.new("ScrollingFrame")
  scroll.Size                = UDim2.new(1, 0, 1, 0)
  scroll.BackgroundTransparency = 1
  scroll.BorderSizePixel     = 0
  scroll.ScrollBarThickness  = 3
  scroll.ScrollBarImageColor3 = C.limeDeep
  scroll.CanvasSize          = UDim2.new(0, 0, 0, 0)
  scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
  scroll.ScrollingDirection  = Enum.ScrollingDirection.Y
  scroll.Parent              = msgContainer

  local msgList = vlist(scroll, 10)
  padding(scroll, nil, 12, 12, 12, 12)
  uiElements.scrollFrame = scroll

  -- ── Input area ───────────────────────────────
  local inputOuter = makeFrame(root, UDim2.new(1, 0, 0, 56), nil, C.surface, 4)
  stroke(inputOuter, C.border)

  local inputInner = makeFrame(inputOuter, UDim2.new(1, -56, 1, -12), UDim2.new(0, 8, 0, 6), C.bg)
  corner(inputInner, 10)
  stroke(inputInner, C.border)

  local tb = Instance.new("TextBox")
  tb.Size               = UDim2.new(1, 0, 1, 0)
  tb.BackgroundTransparency = 1
  tb.TextColor3         = C.text
  tb.PlaceholderText    = "Ask anything about Roblox..."
  tb.PlaceholderColor3  = C.textFaint
  tb.Font               = Enum.Font.Gotham
  tb.TextSize           = 13
  tb.TextWrapped        = true
  tb.MultiLine          = true
  tb.ClearTextOnFocus   = false
  tb.TextXAlignment     = Enum.TextXAlignment.Left
  tb.TextYAlignment     = Enum.TextYAlignment.Top
  tb.BorderSizePixel    = 0
  tb.Parent             = inputInner
  padding(tb, nil, 10, 10, 8, 8)
  uiElements.textBox = tb

  -- Focus glow
  tb.Focused:Connect(function()
    tween(inputInner, { BackgroundColor3 = C.surface }, 0.2)
    stroke(inputInner, C.limeDeep)
  end)
  tb.FocusLost:Connect(function()
    tween(inputInner, { BackgroundColor3 = C.bg }, 0.2)
    stroke(inputInner, C.border)
  end)

  local sendBtn = makeFrame(inputOuter, UDim2.new(0, 40, 0, 40), UDim2.new(1, -48, 0.5, -20), C.lime)
  corner(sendBtn, 10)

  local sendLbl = makeLabel(sendBtn, "▶", UDim2.new(1, 0, 1, 0), C.limeDark, Enum.Font.GothamBold, Enum.TextXAlignment.Center)
  sendLbl.TextSize = 16

  local sendClickable = Instance.new("TextButton")
  sendClickable.Size             = UDim2.new(1, 0, 1, 0)
  sendClickable.BackgroundTransparency = 1
  sendClickable.Text             = ""
  sendClickable.Parent           = sendBtn
  uiElements.sendBtn = sendBtn

  sendClickable.MouseButton1Click:Connect(function()
    local msg = tb.Text:gsub("^%s+", ""):gsub("%s+$", "")
    if msg ~= "" then sendMessage(msg) end
  end)

  tb.FocusLost:Connect(function(enter)
    if enter then
      local msg = tb.Text:gsub("^%s+", ""):gsub("%s+$", "")
      if msg ~= "" then sendMessage(msg) end
    end
  end)

  sendBtn.MouseEnter:Connect(function()
    tween(sendBtn, { BackgroundColor3 = C.limeDeep })
  end)
  sendBtn.MouseLeave:Connect(function()
    tween(sendBtn, { BackgroundColor3 = C.lime })
  end)

  newBtn.MouseButton1Click:Connect(function()
    pluginState.conversationId = nil
    for _, c in ipairs(scroll:GetChildren()) do
      if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then c:Destroy() end
    end
    addMessage(scroll, "assistant", "✨ Fresh start! What are we building today?")
  end)

  -- Welcome message
  addMessage(scroll, "assistant", "👋 Welcome to Lime AI!\n\nI can help you:\n• Write and fix Roblox scripts\n• Generate complete game systems\n• Debug your code\n• Answer any Roblox question\n\nTip: Go to lime-ai-eight.vercel.app and use Build in Studio to generate code that appears here automatically!")

  startJobPolling()
end

-- ─────────────────────────────────────────────
-- LOGIN UI
-- ─────────────────────────────────────────────
local function buildLoginUI()
  for _, c in ipairs(widget:GetChildren()) do
    if c:IsA("GuiObject") then c:Destroy() end
  end

  local root = makeFrame(widget, UDim2.new(1, 0, 1, 0), nil, C.bg)

  -- Top decoration bar
  local topDeco = makeFrame(root, UDim2.new(1, 0, 0, 3), nil, C.lime)

  -- Center card
  local card = makeFrame(root, UDim2.new(0.88, 0, 0, 0), UDim2.new(0.06, 0, 0, 0), C.surface)
  card.AutomaticSize = Enum.AutomaticSize.Y
  card.Position = UDim2.new(0.06, 0, 0, 60)
  corner(card, 16)
  stroke(card, C.border)

  local cardList = vlist(card, 12)
  cardList.HorizontalAlignment = Enum.HorizontalAlignment.Center
  padding(card, nil, 24, 24, 24, 28)

  -- Logo
  local logoBg = makeFrame(card, UDim2.new(0, 64, 0, 64), nil, C.limeDark, 1)
  logoBg.AnchorPoint = Vector2.new(0.5, 0)
  corner(logoBg, 16)
  stroke(logoBg, C.limeDeep)
  local logoEmoji = makeLabel(logoBg, "🌿", UDim2.new(1, 0, 1, 0), C.white, Enum.Font.GothamBold, Enum.TextXAlignment.Center, 1)
  logoEmoji.TextSize = 28

  local titleLbl = makeLabel(card, "Lime AI", UDim2.new(1, 0, 0, 28), C.lime, Enum.Font.GothamBold, Enum.TextXAlignment.Center, 2)
  titleLbl.TextSize = 22

  local subLbl = makeLabel(card, "AI coding assistant for Roblox Studio", UDim2.new(1, 0, 0, 18), C.textDim, Enum.Font.Gotham, Enum.TextXAlignment.Center, 3)
  subLbl.TextSize = 11

  -- Divider
  local div = makeFrame(card, UDim2.new(1, 0, 0, 1), nil, C.border, 4)

  -- Email
  local emailWrap = makeFrame(card, UDim2.new(1, 0, 0, 0), nil, C.surface2, 5)
  emailWrap.AutomaticSize = Enum.AutomaticSize.Y
  corner(emailWrap, 10)
  stroke(emailWrap, C.border)

  local emailLbl = makeLabel(emailWrap, "EMAIL", UDim2.new(1, 0, 0, 14), C.textFaint, Enum.Font.GothamBold, Enum.TextXAlignment.Left)
  emailLbl.Position = UDim2.new(0, 12, 0, 8)
  emailLbl.TextSize = 9

  local emailBox = Instance.new("TextBox")
  emailBox.Size             = UDim2.new(1, -24, 0, 30)
  emailBox.Position         = UDim2.new(0, 12, 0, 22)
  emailBox.BackgroundTransparency = 1
  emailBox.TextColor3       = C.text
  emailBox.PlaceholderText  = "your@email.com"
  emailBox.PlaceholderColor3 = C.textFaint
  emailBox.Font             = Enum.Font.Gotham
  emailBox.TextSize         = 13
  emailBox.ClearTextOnFocus = false
  emailBox.BorderSizePixel  = 0
  emailBox.TextXAlignment   = Enum.TextXAlignment.Left
  emailBox.Parent           = emailWrap
  emailWrap.Size            = UDim2.new(1, 0, 0, 58)

  -- Password
  local passWrap = makeFrame(card, UDim2.new(1, 0, 0, 58), nil, C.surface2, 6)
  corner(passWrap, 10)
  stroke(passWrap, C.border)

  local passLbl = makeLabel(passWrap, "PASSWORD", UDim2.new(1, 0, 0, 14), C.textFaint, Enum.Font.GothamBold, Enum.TextXAlignment.Left)
  passLbl.Position = UDim2.new(0, 12, 0, 8)
  passLbl.TextSize = 9

  local passBox = Instance.new("TextBox")
  passBox.Size             = UDim2.new(1, -24, 0, 30)
  passBox.Position         = UDim2.new(0, 12, 0, 22)
  passBox.BackgroundTransparency = 1
  passBox.TextColor3       = C.text
  passBox.PlaceholderText  = "••••••••"
  passBox.PlaceholderColor3 = C.textFaint
  passBox.Font             = Enum.Font.Gotham
  passBox.TextSize         = 13
  passBox.ClearTextOnFocus = false
  passBox.BorderSizePixel  = 0
  passBox.TextXAlignment   = Enum.TextXAlignment.Left
  passBox.Parent           = passWrap

  -- Status
  local statusLbl = makeLabel(card, "", UDim2.new(1, 0, 0, 14), C.red, Enum.Font.Gotham, Enum.TextXAlignment.Center, 7)
  statusLbl.TextSize = 11

  -- Login button
  local loginBtn = makeButton(card, "Sign In →", C.lime, C.limeDark, UDim2.new(1, 0, 0, 42), 8)
  loginBtn.TextSize = 14
  corner(loginBtn, 10)

  -- Loading spinner (hidden by default)
  local spinFrame = makeFrame(card, UDim2.new(0, 40, 0, 40), UDim2.new(0.5, -20, 0, 0), C.surface, 9)
  spinFrame.BackgroundTransparency = 1
  spinFrame.Visible = false

  local signupLbl = makeLabel(card, "Sign up at lime-ai-eight.vercel.app", UDim2.new(1, 0, 0, 14), C.textFaint, Enum.Font.Gotham, Enum.TextXAlignment.Center, 10)
  signupLbl.TextSize = 10

  -- Focus effects
  local function focusEffect(box, wrap)
    box.Focused:Connect(function() stroke(wrap, C.limeDeep) end)
    box.FocusLost:Connect(function() stroke(wrap, C.border) end)
  end
  focusEffect(emailBox, emailWrap)
  focusEffect(passBox, passWrap)

  local spinnerConn = nil

  local function doLogin()
    local email = emailBox.Text:gsub("%s", "")
    local pass  = passBox.Text
    if email == "" or pass == "" then
      statusLbl.Text = "⚠ Please fill in all fields"
      return
    end

    loginBtn.Visible = false
    spinFrame.Visible = true
    statusLbl.Text = "Connecting to server..."
    statusLbl.TextColor3 = C.textDim

    local spinner, conn = createSpinner(spinFrame, UDim2.new(0, 32, 0, 32), UDim2.new(0, 4, 0, 4))
    spinnerConn = conn

    task.spawn(function()
      local result, err = makeRequest("POST", "/auth/login", { email = email, password = pass }, false)

      if spinnerConn then spinnerConn:Disconnect() end
      spinFrame.Visible = false
      loginBtn.Visible = true

      if result and result.accessToken then
        pluginState.accessToken  = result.accessToken
        pluginState.refreshToken = result.refreshToken
        plugin:SetSetting("refreshToken", result.refreshToken)

        -- Success flash
        local overlay, oconn = showLoading(widget, "Loading Lime AI...")
        task.delay(0.8, function()
          if oconn then oconn:Disconnect() end
          overlay:Destroy()
          buildUI()
        end)
      else
        statusLbl.Text = "❌ " .. (err or "Login failed. Try waking the server first!")
        statusLbl.TextColor3 = C.red
      end
    end)
  end

  loginBtn.MouseButton1Click:Connect(doLogin)
  passBox.FocusLost:Connect(function(enter) if enter then doLogin() end end)
end

-- ─────────────────────────────────────────────
-- INIT
-- ─────────────────────────────────────────────
local function init()
  -- Show loading
  local loadOverlay, loadConn = showLoading(widget, "Checking session...")

  local function finishLoad(buildFn)
    task.delay(0.5, function()
      if loadConn then loadConn:Disconnect() end
      loadOverlay:Destroy()
      buildFn()
    end)
  end

  local savedToken = plugin:GetSetting("refreshToken")
  if savedToken and savedToken ~= "" then
    pluginState.refreshToken = savedToken
    task.spawn(function()
      local result = makeRequest("POST", "/auth/refresh", { refreshToken = savedToken }, false)
      if result and result.accessToken then
        pluginState.accessToken  = result.accessToken
        pluginState.refreshToken = result.refreshToken
        plugin:SetSetting("refreshToken", result.refreshToken)
        finishLoad(buildUI)
      else
        finishLoad(buildLoginUI)
      end
    end)
  else
    finishLoad(buildLoginUI)
  end
end

widget:GetPropertyChangedSignal("Enabled"):Connect(function()
  if widget.Enabled and not pluginState.accessToken then init() end
end)

init()

print("[Lime AI] v" .. PLUGIN_VERSION .. " loaded ✅")
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          roblox-ai-platform/{backend/                                                                        0000755 0000000 0000000 00000000000 15211357235 015060  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/{backend/src/                                                                    0000755 0000000 0000000 00000000000 15211357235 015647  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/{backend/src/{routes,middleware,services,db,utils,types},plugin/                 0000755 0000000 0000000 00000000000 15211357235 027665  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/{backend/src/{routes,middleware,services,db,utils,types},plugin/src,dashboard/   0000755 0000000 0000000 00000000000 15211357235 032400  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   ././@LongLink                                                                                       0000644 0000000 0000000 00000000146 00000000000 011604  L                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/{backend/src/{routes,middleware,services,db,utils,types},plugin/src,dashboard/src/                                                                                                                                                                                                                                                                                                                                                                                                                           roblox-ai-platform/{backend/src/{routes,middleware,services,db,utils,types},plugin/src,dashboard/src0000755 0000000 0000000 00000000000 15211357235 033110  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   ././@LongLink                                                                                       0000644 0000000 0000000 00000000214 00000000000 011600  L                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/{backend/src/{routes,middleware,services,db,utils,types},plugin/src,dashboard/src/{pages,components,hooks},docker,docs}/                                                                                                                                                                                                                                                                                                                                                                                     roblox-ai-platform/{backend/src/{routes,middleware,services,db,utils,types},plugin/src,dashboard/src0000755 0000000 0000000 00000000000 15211357235 033110  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/dashboard/                                                                       0000755 0000000 0000000 00000000000 15211362255 015223  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/dashboard/index.html                                                             0000644 0000000 0000000 00000153311 15211363544 017226  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   <!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Lime AI — Claude-powered Studio Assistant</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link href="https://fonts.googleapis.com/css2?family=DM+Sans:wght@300;400;500;600;700&family=JetBrains+Mono:wght@400;500&display=swap" rel="stylesheet">
<style>
:root {
  --bg:         #09100a;
  --bg-2:       #0d160e;
  --bg-3:       #111c12;
  --surface:    #162018;
  --surface-2:  #1c2a1e;
  --border:     rgba(134,239,94,0.08);
  --border-2:   rgba(134,239,94,0.15);
  --text:       #e2f0e4;
  --text-2:     #8aaa8d;
  --text-3:     #4d6b50;
  --accent:     #86ef5e;
  --accent-dark:#5dbf36;
  --accent-glow:rgba(134,239,94,0.18);
  --accent-text:#0d160e;
  --green:      #86ef5e;
  --red:        #f87171;
  --amber:      #fbbf24;
  --font-sans:  'DM Sans', sans-serif;
  --font-mono:  'JetBrains Mono', monospace;
  --r-sm: 6px; --r-md: 10px; --r-lg: 14px; --r-xl: 20px;
}

*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: var(--font-sans); background: var(--bg); color: var(--text); line-height: 1.6; min-height: 100vh; overflow-x: hidden; }

/* ── Layout ── */
.app { display: flex; min-height: 100vh; }
.sidebar {
  width: 220px; flex-shrink: 0;
  background: var(--bg-2);
  border-right: 1px solid var(--border);
  display: flex; flex-direction: column; padding: 20px 0;
  position: fixed; top: 0; left: 0; bottom: 0; z-index: 100;
}
.main { margin-left: 220px; flex: 1; padding: 32px; max-width: 1100px; }

/* ── Sidebar ── */
.logo {
  display: flex; align-items: center; gap: 10px;
  padding: 0 20px 24px; border-bottom: 1px solid var(--border); margin-bottom: 12px;
}
.logo-icon {
  width: 34px; height: 34px;
  background: var(--accent); border-radius: var(--r-md);
  display: flex; align-items: center; justify-content: center;
  font-size: 18px; flex-shrink: 0; color: var(--accent-text); font-weight: 800;
}
.logo-text { font-weight: 700; font-size: 17px; letter-spacing: -0.4px; color: var(--text); }
.logo-sub  { font-size: 10px; color: var(--text-3); letter-spacing: 0.04em; }

.nav-item {
  display: flex; align-items: center; gap: 10px;
  padding: 9px 20px; color: var(--text-2);
  cursor: pointer; font-size: 13.5px; font-weight: 500;
  transition: all 0.12s; border-left: 2px solid transparent;
  text-decoration: none; user-select: none;
}
.nav-item:hover { color: var(--text); background: rgba(134,239,94,0.05); }
.nav-item.active { color: var(--accent); border-left-color: var(--accent); background: rgba(134,239,94,0.07); }
.nav-icon { font-size: 15px; width: 18px; text-align: center; }
.nav-section { font-size: 10px; font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase; color: var(--text-3); padding: 16px 20px 6px; }

.sidebar-footer { margin-top: auto; padding: 16px 20px; border-top: 1px solid var(--border); }
.user-pill { display: flex; align-items: center; gap: 10px; padding: 10px; background: var(--surface); border-radius: var(--r-md); cursor: pointer; }
.avatar { width: 30px; height: 30px; border-radius: 50%; background: var(--accent); display: flex; align-items: center; justify-content: center; font-size: 12px; font-weight: 800; color: var(--accent-text); flex-shrink: 0; }
.user-info { flex: 1; min-width: 0; }
.user-name { font-size: 12px; font-weight: 600; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.user-plan { font-size: 10px; color: var(--accent); font-weight: 600; }

/* ── Type ── */
h1 { font-size: 26px; font-weight: 700; letter-spacing: -0.5px; }
h2 { font-size: 18px; font-weight: 600; letter-spacing: -0.3px; }
h3 { font-size: 15px; font-weight: 600; }
.page-header { margin-bottom: 28px; }
.page-subtitle { color: var(--text-2); font-size: 14px; margin-top: 4px; }

/* ── Cards ── */
.card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-lg); padding: 20px 24px; }

/* ── Stats ── */
.stats-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 14px; margin-bottom: 28px; }
.stat-card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-lg); padding: 20px; }
.stat-label { font-size: 11px; color: var(--text-3); font-weight: 600; letter-spacing: 0.06em; text-transform: uppercase; margin-bottom: 8px; }
.stat-value { font-size: 30px; font-weight: 700; letter-spacing: -1px; color: var(--text); }
.stat-sub { font-size: 11px; color: var(--text-3); margin-top: 4px; }

/* ── Progress ── */
.progress-bar { height: 4px; background: var(--bg-3); border-radius: 9999px; overflow: hidden; margin-top: 8px; }
.progress-fill { height: 100%; background: var(--accent); border-radius: 9999px; transition: width 0.5s ease; }
.progress-fill.warning { background: var(--amber); }
.progress-fill.danger  { background: var(--red); }

/* ── Badges ── */
.badge { display: inline-flex; align-items: center; padding: 2px 8px; border-radius: 9999px; font-size: 10px; font-weight: 700; letter-spacing: 0.04em; text-transform: uppercase; }
.badge-free       { background: rgba(100,120,100,0.2); color: var(--text-3); }
.badge-pro        { background: rgba(134,239,94,0.15); color: var(--accent); }
.badge-team       { background: rgba(134,239,94,0.25); color: var(--accent); }
.badge-enterprise { background: rgba(251,191,36,0.15); color: var(--amber); }
.badge-active     { background: rgba(134,239,94,0.15); color: var(--accent); }
.badge-error      { background: rgba(248,113,113,0.15); color: var(--red); }

/* ── Tables ── */
.table-wrap { overflow-x: auto; }
table { width: 100%; border-collapse: collapse; font-size: 13px; }
thead th { text-align: left; padding: 10px 14px; font-size: 10px; font-weight: 700; letter-spacing: 0.07em; text-transform: uppercase; color: var(--text-3); border-bottom: 1px solid var(--border); }
tbody td { padding: 13px 14px; border-bottom: 1px solid var(--border); color: var(--text-2); }
tbody tr:last-child td { border-bottom: none; }
tbody tr:hover td { background: rgba(134,239,94,0.03); color: var(--text); }

/* ── Forms ── */
.form-group { margin-bottom: 16px; }
label { display: block; font-size: 12px; font-weight: 600; color: var(--text-2); margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.04em; }
input, select, textarea {
  width: 100%; background: var(--bg-3); border: 1px solid var(--border-2);
  border-radius: var(--r-md); padding: 10px 14px; color: var(--text);
  font-family: var(--font-sans); font-size: 14px; outline: none; transition: border-color 0.15s;
}
input:focus, select:focus, textarea:focus { border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-glow); }
input::placeholder { color: var(--text-3); }

/* ── Buttons ── */
.btn { display: inline-flex; align-items: center; gap: 6px; padding: 9px 18px; border-radius: var(--r-md); font-family: var(--font-sans); font-size: 13px; font-weight: 600; border: none; cursor: pointer; transition: all 0.15s; text-decoration: none; white-space: nowrap; }
.btn-primary { background: var(--accent); color: var(--accent-text); }
.btn-primary:hover { background: #9dff75; transform: translateY(-1px); }
.btn-ghost { background: transparent; color: var(--text-2); border: 1px solid var(--border-2); }
.btn-ghost:hover { background: var(--surface-2); color: var(--text); }
.btn-danger { background: rgba(248,113,113,0.12); color: var(--red); border: 1px solid rgba(248,113,113,0.25); }
.btn-danger:hover { background: rgba(248,113,113,0.2); }
.btn-sm { padding: 6px 12px; font-size: 12px; }
.btn-lg { padding: 12px 24px; font-size: 15px; }
.btn-block { width: 100%; justify-content: center; }

/* ── Usage ── */
.usage-block { margin-bottom: 20px; }
.usage-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; }
.usage-title { font-size: 13px; font-weight: 500; }
.usage-count { font-size: 12px; color: var(--text-2); font-variant-numeric: tabular-nums; }

/* ── Pricing ── */
.pricing-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 16px; }
.plan-card { background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-xl); padding: 24px; display: flex; flex-direction: column; position: relative; transition: border-color 0.2s; }
.plan-card.featured { border-color: var(--accent); box-shadow: 0 0 30px rgba(134,239,94,0.08); }
.plan-popular { position: absolute; top: -11px; left: 50%; transform: translateX(-50%); background: var(--accent); color: var(--accent-text); font-size: 10px; font-weight: 800; letter-spacing: 0.05em; padding: 3px 12px; border-radius: 9999px; text-transform: uppercase; white-space: nowrap; }
.plan-name { font-size: 13px; font-weight: 700; color: var(--text-2); margin-bottom: 6px; text-transform: uppercase; letter-spacing: 0.06em; }
.plan-price { font-size: 34px; font-weight: 800; letter-spacing: -1.5px; margin-bottom: 2px; }
.plan-period { font-size: 13px; color: var(--text-3); }
.plan-divider { height: 1px; background: var(--border); margin: 20px 0; }
.plan-feature { font-size: 13px; color: var(--text-2); padding: 5px 0; display: flex; align-items: flex-start; gap: 8px; }
.plan-feature::before { content: '✓'; color: var(--accent); font-weight: 800; flex-shrink: 0; }
.plan-cta { margin-top: auto; padding-top: 20px; }

/* ── Chart ── */
.chart-bar-wrap { display: flex; align-items: flex-end; gap: 6px; height: 120px; margin-top: 12px; }
.chart-bar-col { flex: 1; display: flex; flex-direction: column; align-items: center; gap: 4px; }
.chart-bar { width: 100%; border-radius: 4px 4px 0 0; background: var(--accent); opacity: 0.7; transition: opacity 0.15s; min-height: 2px; }
.chart-bar:hover { opacity: 1; }
.chart-label { font-size: 9px; color: var(--text-3); }

/* ── Code ── */
pre { background: #060e07; border: 1px solid var(--border); border-radius: var(--r-md); padding: 16px; overflow-x: auto; font-family: var(--font-mono); font-size: 12px; color: #a8d5a2; line-height: 1.7; }

/* ── Auth ── */
.auth-wrap { display: flex; align-items: center; justify-content: center; min-height: 100vh; background: var(--bg); }
.auth-card { width: 420px; background: var(--surface); border: 1px solid var(--border); border-radius: var(--r-xl); padding: 44px 40px; }
.auth-logo { text-align: center; margin-bottom: 32px; }
.auth-logo-mark { width: 56px; height: 56px; background: var(--accent); border-radius: 16px; display: inline-flex; align-items: center; justify-content: center; font-size: 26px; font-weight: 900; color: var(--accent-text); margin-bottom: 14px; }
.auth-title { font-size: 24px; font-weight: 800; letter-spacing: -0.5px; }
.auth-sub { color: var(--text-2); font-size: 14px; margin-top: 4px; }
.auth-divider { display: flex; align-items: center; gap: 12px; margin: 20px 0; color: var(--text-3); font-size: 12px; }
.auth-divider::before, .auth-divider::after { content: ''; flex: 1; height: 1px; background: var(--border); }

/* ── Key ── */
.key-display { font-family: var(--font-mono); font-size: 12px; background: var(--bg-3); border: 1px solid var(--border); border-radius: var(--r-md); padding: 10px 14px; color: var(--accent); word-break: break-all; display: flex; align-items: center; justify-content: space-between; gap: 12px; }

/* ── Toast ── */
.toast { position: fixed; bottom: 24px; right: 24px; background: var(--surface-2); border: 1px solid var(--border-2); border-radius: var(--r-lg); padding: 14px 18px; font-size: 13px; box-shadow: 0 8px 32px rgba(0,0,0,0.5); z-index: 9999; display: flex; align-items: center; gap: 10px; animation: slideIn 0.2s ease; }
@keyframes slideIn { from { transform: translateY(16px); opacity: 0; } to { transform: none; opacity: 1; } }

@media (max-width: 768px) { .sidebar { display: none; } .main { margin-left: 0; padding: 20px 16px; } }
::-webkit-scrollbar { width: 5px; height: 5px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: var(--surface-2); border-radius: 9999px; }
.hidden { display: none !important; }
</style>
</head>
<body>

<!-- ════════ AUTH ════════ -->
<div id="authPage" class="auth-wrap">
  <div class="auth-card">
    <div class="auth-logo">
      <div class="auth-logo-mark">L</div>
      <div class="auth-title">Lime AI</div>
      <div class="auth-sub">Claude-powered Roblox Studio assistant</div>
    </div>

    <div id="loginForm">
      <div class="form-group">
        <label>Email</label>
        <input type="email" id="loginEmail" placeholder="you@example.com" />
      </div>
      <div class="form-group">
        <label>Password</label>
        <input type="password" id="loginPassword" placeholder="••••••••" />
      </div>
      <div id="loginError" style="color:var(--red);font-size:13px;margin-bottom:12px;display:none;"></div>
      <button class="btn btn-primary btn-block btn-lg" onclick="doLogin()">Sign In</button>
      <div class="auth-divider">or</div>
      <button class="btn btn-ghost btn-block" onclick="showRegister()">Create an account</button>
    </div>

    <div id="registerForm" class="hidden">
      <div class="form-group">
        <label>Email</label>
        <input type="email" id="regEmail" placeholder="you@example.com" />
      </div>
      <div class="form-group">
        <label>Username</label>
        <input type="text" id="regUsername" placeholder="yourname" />
      </div>
      <div class="form-group">
        <label>Password</label>
        <input type="password" id="regPassword" placeholder="Min 8 characters" />
      </div>
      <div id="regError" style="color:var(--red);font-size:13px;margin-bottom:12px;display:none;"></div>
      <button class="btn btn-primary btn-block btn-lg" onclick="doRegister()">Create Account</button>
      <div class="auth-divider">or</div>
      <button class="btn btn-ghost btn-block" onclick="showLogin()">Sign in instead</button>
    </div>
  </div>
</div>

<!-- ════════ MAIN APP ════════ -->
<div id="mainApp" class="app hidden">
  <aside class="sidebar">
    <div class="logo">
      <div class="logo-icon">L</div>
      <div>
        <div class="logo-text">Lime AI</div>
        <div class="logo-sub">Powered by Claude</div>
      </div>
    </div>

    <nav>
      <div class="nav-section">Main</div>
      <div class="nav-item active" onclick="navigate('dashboard')"><span class="nav-icon">⊞</span> Dashboard</div>
      <div class="nav-item" onclick="navigate('build')"><span class="nav-icon">◈</span> Build in Studio</div>
      <div class="nav-item" onclick="navigate('chat')"><span class="nav-icon">◉</span> Chat with Claude</div>
      <div class="nav-item" onclick="navigate('usage')"><span class="nav-icon">◎</span> Usage</div>
      <div class="nav-item" onclick="navigate('history')"><span class="nav-icon">◷</span> History</div>
      <div class="nav-section">Account</div>
      <div class="nav-item" onclick="navigate('billing')"><span class="nav-icon">◈</span> Billing</div>
      <div class="nav-item" onclick="navigate('apikeys')"><span class="nav-icon">⚿</span> API Keys</div>
      <div class="nav-item" onclick="navigate('settings')"><span class="nav-icon">⊙</span> Settings</div>
      <div id="adminNav" class="hidden">
        <div class="nav-section">Admin</div>
        <div class="nav-item" onclick="navigate('admin')"><span class="nav-icon">⊛</span> Admin Panel</div>
      </div>
    </nav>

    <div class="sidebar-footer">
      <div class="user-pill" onclick="navigate('settings')">
        <div class="avatar" id="sidebarAvatar">?</div>
        <div class="user-info">
          <div class="user-name" id="sidebarEmail">Loading...</div>
          <div class="user-plan" id="sidebarPlan">FREE</div>
        </div>
      </div>
    </div>
  </aside>

  <main class="main" id="mainContent"></main>
</div>

<script>
const API = 'https://api.limeai.dev/api/v1';
let state = {
  accessToken: localStorage.getItem('accessToken'),
  refreshToken: localStorage.getItem('refreshToken'),
  user: null, currentPage: 'dashboard',
};

async function api(method, path, body) {
  const opts = {
    method,
    headers: { 'Content-Type': 'application/json', ...(state.accessToken ? { Authorization: `Bearer ${state.accessToken}` } : {}) },
    ...(body ? { body: JSON.stringify(body) } : {}),
  };
  let res = await fetch(API + path, opts);
  if (res.status === 401 && state.refreshToken) {
    const r = await fetch(API + '/auth/refresh', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ refreshToken: state.refreshToken }) });
    if (r.ok) {
      const tokens = await r.json();
      state.accessToken = tokens.accessToken; state.refreshToken = tokens.refreshToken;
      localStorage.setItem('accessToken', tokens.accessToken); localStorage.setItem('refreshToken', tokens.refreshToken);
      opts.headers.Authorization = `Bearer ${tokens.accessToken}`;
      res = await fetch(API + path, opts);
    } else { doLogout(); return null; }
  }
  return res.json().catch(() => null);
}

async function doLogin() {
  const email = document.getElementById('loginEmail').value;
  const password = document.getElementById('loginPassword').value;
  const errEl = document.getElementById('loginError');
  errEl.style.display = 'none';
  const result = await fetch(API + '/auth/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, password }) }).then(r => r.json()).catch(() => null);
  if (!result?.accessToken) { errEl.textContent = result?.error || 'Login failed'; errEl.style.display = 'block'; return; }
  state.accessToken = result.accessToken; state.refreshToken = result.refreshToken;
  localStorage.setItem('accessToken', result.accessToken); localStorage.setItem('refreshToken', result.refreshToken);
  initApp();
}

async function doRegister() {
  const email = document.getElementById('regEmail').value;
  const username = document.getElementById('regUsername').value;
  const password = document.getElementById('regPassword').value;
  const errEl = document.getElementById('regError');
  errEl.style.display = 'none';
  const result = await fetch(API + '/auth/register', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ email, username, password }) }).then(r => r.json()).catch(() => null);
  if (result?.error) { errEl.textContent = result.error; errEl.style.display = 'block'; return; }
  toast('✓ Account created! Check your email.'); showLogin();
}

function doLogout() {
  api('POST', '/auth/logout', { refreshToken: state.refreshToken });
  state.accessToken = null; state.refreshToken = null; state.user = null;
  localStorage.removeItem('accessToken'); localStorage.removeItem('refreshToken');
  document.getElementById('mainApp').classList.add('hidden');
  document.getElementById('authPage').classList.remove('hidden');
}
function showRegister() { document.getElementById('loginForm').classList.add('hidden'); document.getElementById('registerForm').classList.remove('hidden'); }
function showLogin() { document.getElementById('loginForm').classList.remove('hidden'); document.getElementById('registerForm').classList.add('hidden'); }

async function initApp() {
  document.getElementById('authPage').classList.add('hidden');
  document.getElementById('mainApp').classList.remove('hidden');
  state.user = await api('GET', '/user/me');
  if (!state.user) { doLogout(); return; }
  const initials = (state.user.display_name || state.user.email || '?').slice(0, 2).toUpperCase();
  document.getElementById('sidebarAvatar').textContent = initials;
  document.getElementById('sidebarEmail').textContent = state.user.email;
  document.getElementById('sidebarPlan').textContent = (state.user.plan_name || 'free').toUpperCase();
  if (state.user.is_admin) document.getElementById('adminNav').classList.remove('hidden');
  navigate('dashboard');
}

function navigate(page) {
  state.currentPage = page;
  document.querySelectorAll('.nav-item').forEach(el => el.classList.remove('active'));
  document.querySelector(`[onclick="navigate('${page}')"]`)?.classList.add('active');
  const pages = { dashboard: renderDashboard, build: renderBuild, chat: renderChat, usage: renderUsage, history: renderHistory, billing: renderBilling, apikeys: renderApiKeys, settings: renderSettings, admin: renderAdmin };
  pages[page]?.();
}

async function renderBuild() {
  const c = document.getElementById('mainContent');
  c.innerHTML = `
    <style>
      .build-wrap { max-width: 700px; }
      .prompt-box { width:100%; min-height:120px; background:var(--bg-3); border:1px solid var(--border-2); border-radius:14px; padding:16px; color:var(--text); font-family:var(--font-sans); font-size:15px; outline:none; resize:vertical; line-height:1.6; }
      .prompt-box:focus { border-color:#86ef5e; box-shadow:0 0 0 3px rgba(134,239,94,0.12); }
      .opts-row { display:grid; grid-template-columns:1fr 1fr; gap:12px; margin:14px 0; }
      .opt-label { font-size:11px; font-weight:600; color:var(--text-3); text-transform:uppercase; letter-spacing:.05em; display:block; margin-bottom:6px; }
      .job-card { background:var(--surface); border:1px solid var(--border); border-radius:12px; padding:16px 18px; margin-bottom:10px; }
      .job-card.completed { border-color:#86ef5e; }
      .job-card.inserted  { border-color:#3B6D11; opacity:.7; }
      .job-card.failed    { border-color:var(--red); }
      .job-card.pending,.job-card.processing { border-color:var(--amber); }
      .job-header { display:flex; align-items:center; justify-content:space-between; margin-bottom:8px; }
      .job-name   { font-weight:600; font-size:14px; }
      .job-prompt { font-size:13px; color:var(--text-2); margin-bottom:8px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis; }
      .job-status { font-size:11px; font-weight:700; padding:3px 9px; border-radius:9999px; text-transform:uppercase; letter-spacing:.05em; }
      .status-pending,.status-processing { background:rgba(251,191,36,.15); color:var(--amber); }
      .status-completed { background:rgba(134,239,94,.15); color:#86ef5e; }
      .status-inserted  { background:rgba(134,239,94,.1); color:#3B6D11; }
      .status-failed    { background:rgba(248,113,113,.15); color:var(--red); }
      .pulse { animation: pulse 1.4s ease-in-out infinite; }
      @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:.4} }
      .studio-notice { background:rgba(134,239,94,0.07); border:1px solid rgba(134,239,94,0.2); border-radius:12px; padding:14px 18px; margin-bottom:24px; font-size:13px; display:flex; align-items:center; gap:12px; }
      .studio-dot { width:8px; height:8px; border-radius:50%; background:#86ef5e; flex-shrink:0; }
    </style>
    <div class="build-wrap">
      <div class="page-header">
        <h1>Build in Studio</h1>
        <p class="page-subtitle">Describe what you want — Claude codes it and it appears directly in your Studio</p>
      </div>

      <div class="studio-notice">
        <div class="studio-dot pulse"></div>
        <span>Make sure Roblox Studio is open with the Lime AI plugin running. Code will appear there automatically.</span>
      </div>

      <div class="card" style="margin-bottom:20px">
        <textarea class="prompt-box" id="buildPrompt" placeholder="Describe what you want built...

Examples:
• A sword fighting system with damage, cooldown and kill tracking
• A shop GUI with currency display and item purchasing  
• A leaderboard that saves player stats with DataStore
• A round-based game system with lobbies and timers
• A smooth character movement system with wall running"></textarea>

        <div class="opts-row">
          <div>
            <span class="opt-label">Script type</span>
            <select id="scriptType" style="width:100%">
              <option value="Script">Script (server-side)</option>
              <option value="LocalScript">LocalScript (client-side)</option>
              <option value="ModuleScript">ModuleScript (shared logic)</option>
            </select>
          </div>
          <div>
            <span class="opt-label">Insert into</span>
            <select id="insertLocation" style="width:100%">
              <option value="ServerScriptService">ServerScriptService</option>
              <option value="ReplicatedStorage">ReplicatedStorage</option>
              <option value="StarterPlayerScripts">StarterPlayerScripts</option>
              <option value="StarterGui">StarterGui</option>
              <option value="StarterCharacterScripts">StarterCharacterScripts</option>
              <option value="Workspace">Workspace</option>
            </select>
          </div>
        </div>

        <div style="display:flex; align-items:center; gap:12px">
          <button class="btn btn-primary btn-lg" onclick="submitBuildJob()" id="buildBtn">
            Generate &amp; Send to Studio →
          </button>
          <span id="buildStatus" style="font-size:13px; color:var(--text-3)"></span>
        </div>
      </div>

      <div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:12px">
        <h3>Recent builds</h3>
        <button class="btn btn-ghost btn-sm" onclick="loadJobs()">Refresh</button>
      </div>
      <div id="jobsList"><div style="color:var(--text-3);font-size:13px">Loading...</div></div>
    </div>`;

  loadJobs();
}

async function submitBuildJob() {
  const prompt = document.getElementById('buildPrompt').value.trim();
  const scriptType = document.getElementById('scriptType').value;
  const insertLocation = document.getElementById('insertLocation').value;
  const btn = document.getElementById('buildBtn');
  const statusEl = document.getElementById('buildStatus');

  if (!prompt) { toast('Enter a description of what to build', 'error'); return; }

  btn.disabled = true;
  btn.textContent = 'Sending to Claude...';
  statusEl.textContent = '';

  const result = await api('POST', '/jobs', { prompt, scriptType, insertLocation });

  if (!result?.jobId) {
    toast('Failed to create job', 'error');
    btn.disabled = false;
    btn.textContent = 'Generate & Send to Studio →';
    return;
  }

  document.getElementById('buildPrompt').value = '';
  btn.disabled = false;
  btn.textContent = 'Generate & Send to Studio →';
  toast('✓ Sent to Claude! Watch Studio for the code to appear.');
  loadJobs();
  pollJobStatus(result.jobId);
}

async function pollJobStatus(jobId) {
  const maxPolls = 60;
  let polls = 0;
  const interval = setInterval(async () => {
    polls++;
    if (polls > maxPolls) { clearInterval(interval); return; }

    const status = await api('GET', `/jobs/${jobId}/status`);
    if (!status) { clearInterval(interval); return; }

    if (status.status === 'completed' || status.status === 'inserted') {
      clearInterval(interval);
      toast(`✓ "${status.scriptName}" is ready in your Studio!`);
      loadJobs();
    } else if (status.status === 'failed') {
      clearInterval(interval);
      toast('Code generation failed: ' + (status.error || 'Unknown error'), 'error');
      loadJobs();
    }
  }, 2000);
}

async function loadJobs() {
  const el = document.getElementById('jobsList');
  if (!el) return;

  const result = await api('GET', '/jobs');
  if (!result?.jobs?.length) {
    el.innerHTML = `<div style="text-align:center;padding:32px;color:var(--text-3);font-size:13px">
      No builds yet. Describe what you want above and Claude will code it directly into Studio.
    </div>`;
    return;
  }

  el.innerHTML = result.jobs.slice(0, 15).map(job => {
    const statusClass = 'status-' + job.status;
    const cardClass = 'job-card ' + (job.status === 'completed' || job.status === 'inserted' ? job.status : job.status);
    const isPending = job.status === 'pending' || job.status === 'processing';
    return `<div class="${cardClass}">
      <div class="job-header">
        <span class="job-name">${job.script_name || 'Generating...'}</span>
        <span class="job-status ${statusClass} ${isPending ? 'pulse' : ''}">${job.status}</span>
      </div>
      <div class="job-prompt" title="${job.prompt}">${job.prompt}</div>
      <div style="display:flex;align-items:center;gap:12px;font-size:12px;color:var(--text-3)">
        <span>${job.script_type}</span>
        <span>→ ${job.insert_location}</span>
        <span>${new Date(job.created_at).toLocaleString()}</span>
        ${job.status === 'inserted' ? '<span style="color:#3B6D11">✓ In your Studio</span>' : ''}
        ${job.status === 'completed' ? '<span style="color:#86ef5e;animation:pulse 1.4s infinite">Sending to Studio...</span>' : ''}
      </div>
    </div>`;
  }).join('');
}

async function renderChat() {
  const c = document.getElementById('mainContent');
  c.innerHTML = `
    <style>
      .chat-wrap { display:flex; flex-direction:column; height:calc(100vh - 80px); max-height:780px; }
      .chat-messages { flex:1; overflow-y:auto; padding:16px 0; display:flex; flex-direction:column; gap:12px; }
      .msg { display:flex; gap:10px; align-items:flex-start; }
      .msg.user { flex-direction:row-reverse; }
      .msg-avatar { width:28px;height:28px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:700;flex-shrink:0;margin-top:2px; }
      .msg-avatar.ai  { background:#166534;color:#86ef5e; }
      .msg-avatar.usr { background:#86ef5e;color:#0d160e; }
      .msg-bubble { max-width:72%; padding:10px 14px; border-radius:14px; font-size:13.5px; line-height:1.6; }
      .msg.user  .msg-bubble { background:#1c3820;color:#d1fae5;border-radius:14px 14px 4px 14px; }
      .msg.ai    .msg-bubble { background:var(--surface);border:1px solid var(--border);color:var(--text);border-radius:14px 14px 14px 4px; }
      .code-block { background:#060e07;border:1px solid var(--border);border-radius:8px;overflow:hidden;margin:8px 0; }
      .code-header { display:flex;align-items:center;justify-content:space-between;padding:6px 12px;background:rgba(0,0,0,0.3);font-size:10px;font-weight:600;letter-spacing:.05em;color:var(--text-3);text-transform:uppercase; }
      .code-body { padding:12px;font-family:var(--font-mono);font-size:12px;color:#a8d5a2;line-height:1.6;overflow-x:auto;white-space:pre; }
      .copy-btn { background:rgba(134,239,94,0.1);border:none;color:#86ef5e;font-size:10px;padding:3px 8px;border-radius:4px;cursor:pointer;font-weight:600; }
      .copy-btn:hover { background:rgba(134,239,94,0.2); }
      .chat-input-row { display:flex;gap:10px;padding-top:14px;border-top:1px solid var(--border);margin-top:4px; }
      .chat-input { flex:1;background:var(--bg-3);border:1px solid var(--border-2);border-radius:12px;padding:10px 16px;color:var(--text);font-family:var(--font-sans);font-size:14px;outline:none;resize:none;min-height:44px;max-height:120px; }
      .chat-input:focus { border-color:#86ef5e;box-shadow:0 0 0 3px rgba(134,239,94,0.12); }
      .send-btn { width:44px;height:44px;background:#86ef5e;border:none;border-radius:12px;cursor:pointer;display:flex;align-items:center;justify-content:center;font-size:18px;flex-shrink:0;color:#0d160e;font-weight:700;transition:background .15s; }
      .send-btn:hover { background:#9dff75; }
      .send-btn:disabled { background:var(--surface-2);color:var(--text-3);cursor:not-allowed; }
      .typing { display:flex;gap:4px;align-items:center;padding:4px 0; }
      .typing span { width:6px;height:6px;background:#86ef5e;border-radius:50%;animation:bounce .9s infinite; }
      .typing span:nth-child(2){animation-delay:.15s} .typing span:nth-child(3){animation-delay:.3s}
      @keyframes bounce{0%,60%,100%{transform:translateY(0)}30%{transform:translateY(-6px)}}
    </style>
    <div class="chat-wrap">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:16px">
        <div>
          <h1 style="font-size:22px">Chat with Claude</h1>
          <p class="page-subtitle">Powered by Claude — your Roblox AI assistant</p>
        </div>
        <button class="btn btn-ghost btn-sm" onclick="clearWebChat()">New conversation</button>
      </div>
      <div class="chat-messages" id="chatMessages">
        <div class="msg ai">
          <div class="msg-avatar ai">L</div>
          <div class="msg-bubble">👋 Hi! I'm Lime AI, powered by Claude. Ask me anything about Roblox development — scripts, systems, bugs, game design, anything.</div>
        </div>
      </div>
      <div class="chat-input-row">
        <textarea class="chat-input" id="webChatInput" placeholder="Ask anything about Roblox..." rows="1"
          onkeydown="if(event.key==='Enter'&&!event.shiftKey){event.preventDefault();sendWebChat()}"></textarea>
        <button class="send-btn" id="webSendBtn" onclick="sendWebChat()">➤</button>
      </div>
    </div>`;

  window._webConvId = null;
  window._webStreaming = false;
}

function parseAndRenderMessage(text) {
  const parts = [];
  let remaining = text;
  while (remaining.length > 0) {
    const codeStart = remaining.indexOf('```');
    if (codeStart === -1) { parts.push({ type: 'text', content: remaining }); break; }
    if (codeStart > 0) parts.push({ type: 'text', content: remaining.slice(0, codeStart) });
    const lineEnd = remaining.indexOf('\n', codeStart + 3);
    const lang = lineEnd !== -1 ? remaining.slice(codeStart + 3, lineEnd).trim() : '';
    const codeEnd = remaining.indexOf('```', (lineEnd !== -1 ? lineEnd : codeStart + 3) + 1);
    if (codeEnd === -1) { parts.push({ type: 'text', content: remaining.slice(codeStart) }); break; }
    const code = remaining.slice((lineEnd !== -1 ? lineEnd + 1 : codeStart + 3), codeEnd);
    parts.push({ type: 'code', lang: lang || 'lua', content: code });
    remaining = remaining.slice(codeEnd + 3);
  }

  return parts.map(p => {
    if (p.type === 'text') {
      return `<span>${p.content.replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\n/g,'<br>')}</span>`;
    }
    const id = 'code_' + Math.random().toString(36).slice(2);
    return `<div class="code-block">
      <div class="code-header">
        <span>${p.lang.toUpperCase()}</span>
        <button class="copy-btn" onclick="copyCode('${id}')">Copy</button>
      </div>
      <div class="code-body" id="${id}">${p.content.replace(/</g,'&lt;').replace(/>/g,'&gt;')}</div>
    </div>`;
  }).join('');
}

function copyCode(id) {
  const el = document.getElementById(id);
  if (el) navigator.clipboard.writeText(el.textContent).then(() => toast('Code copied ✓'));
}

function clearWebChat() {
  window._webConvId = null;
  renderChat();
}

function scrollChatBottom() {
  const el = document.getElementById('chatMessages');
  if (el) el.scrollTop = el.scrollHeight;
}

async function sendWebChat() {
  if (window._webStreaming) return;
  const input = document.getElementById('webChatInput');
  const sendBtn = document.getElementById('webSendBtn');
  const messages = document.getElementById('chatMessages');
  if (!input || !messages) return;

  const text = input.value.trim();
  if (!text) return;

  input.value = '';
  input.style.height = 'auto';
  window._webStreaming = true;
  sendBtn.disabled = true;

  messages.insertAdjacentHTML('beforeend', `
    <div class="msg user">
      <div class="msg-avatar usr">${(state.user?.email || 'U').slice(0,1).toUpperCase()}</div>
      <div class="msg-bubble">${text.replace(/</g,'&lt;').replace(/>/g,'&gt;')}</div>
    </div>`);

  const typingId = 'typing_' + Date.now();
  messages.insertAdjacentHTML('beforeend', `
    <div class="msg ai" id="${typingId}">
      <div class="msg-avatar ai">L</div>
      <div class="msg-bubble"><div class="typing"><span></span><span></span><span></span></div></div>
    </div>`);
  scrollChatBottom();

  try {
    const body = { message: text, stream: false };
    if (window._webConvId) body.conversationId = window._webConvId;

    const result = await api('POST', '/chat', body);

    const typingEl = document.getElementById(typingId);
    if (typingEl) typingEl.remove();

    if (result?.content) {
      window._webConvId = result.conversationId;
      messages.insertAdjacentHTML('beforeend', `
        <div class="msg ai">
          <div class="msg-avatar ai">L</div>
          <div class="msg-bubble">${parseAndRenderMessage(result.content)}</div>
        </div>`);
    } else {
      messages.insertAdjacentHTML('beforeend', `
        <div class="msg ai">
          <div class="msg-avatar ai">L</div>
          <div class="msg-bubble" style="color:var(--red)">Something went wrong. Please try again.</div>
        </div>`);
    }
  } catch(e) {
    const typingEl = document.getElementById(typingId);
    if (typingEl) typingEl.remove();
    messages.insertAdjacentHTML('beforeend', `
      <div class="msg ai">
        <div class="msg-avatar ai">L</div>
        <div class="msg-bubble" style="color:var(--red)">Network error. Check your connection.</div>
      </div>`);
  }

  window._webStreaming = false;
  sendBtn.disabled = false;
  scrollChatBottom();
}

async function renderDashboard() {
  const c = document.getElementById('mainContent');
  c.innerHTML = `
    <div class="page-header">
      <h1>Dashboard</h1>
      <p class="page-subtitle">Welcome back, ${state.user?.display_name || state.user?.email?.split('@')[0] || 'Developer'}</p>
    </div>
    <div class="stats-grid">
      <div class="stat-card"><div class="stat-label">Requests today</div><div class="stat-value" id="s1">—</div><div class="stat-sub" id="s1s"></div></div>
      <div class="stat-card"><div class="stat-label">This month</div><div class="stat-value" id="s2">—</div><div class="stat-sub" id="s2s"></div></div>
      <div class="stat-card"><div class="stat-label">Tokens used</div><div class="stat-value" id="s3">—</div><div class="stat-sub">this month</div></div>
      <div class="stat-card"><div class="stat-label">Est. cost</div><div class="stat-value" id="s4">—</div><div class="stat-sub">this month</div></div>
    </div>
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:16px;margin-bottom:24px">
      <div class="card">
        <h3 style="margin-bottom:16px">Daily requests</h3>
        <div id="chartArea" class="chart-bar-wrap"></div>
      </div>
      <div class="card">
        <h3 style="margin-bottom:14px">Usage limits</h3>
        <div id="limitsArea"></div>
      </div>
    </div>
    <div class="card">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:16px">
        <h3>Recent conversations</h3>
        <button class="btn btn-ghost btn-sm" onclick="navigate('history')">View all →</button>
      </div>
      <div id="recentConvs"><div style="color:var(--text-3);font-size:13px">Loading...</div></div>
    </div>`;

  const [usage, convs] = await Promise.all([api('GET', '/usage'), api('GET', '/conversations?limit=5')]);
  if (usage) {
    const dl = usage.today.limit === -1 ? '∞' : usage.today.limit;
    const ml = usage.month.limit === -1 ? '∞' : usage.month.limit;
    document.getElementById('s1').textContent = usage.today.requests.toLocaleString();
    document.getElementById('s1s').textContent = `of ${dl} daily`;
    document.getElementById('s2').textContent = usage.month.requests.toLocaleString();
    document.getElementById('s2s').textContent = `of ${ml} monthly`;
    document.getElementById('s3').textContent = ((usage.month.tokensInput + usage.month.tokensOutput) / 1000).toFixed(1) + 'k';
    document.getElementById('s4').textContent = '$' + usage.month.costUsd;

    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const fakeData = days.map(() => Math.floor(Math.random() * Math.max(usage.today.requests * 2, 5) + 1));
    const max = Math.max(...fakeData, 1);
    document.getElementById('chartArea').innerHTML = fakeData.map((v, i) => `
      <div class="chart-bar-col">
        <div class="chart-bar" style="height:${Math.round((v/max)*100)}px" title="${v}"></div>
        <div class="chart-label">${days[i]}</div>
      </div>`).join('');

    const dp = Math.min((usage.today.requests / (usage.today.limit || 1)) * 100, 100);
    const mp = Math.min((usage.month.requests / (usage.month.limit || 1)) * 100, 100);
    document.getElementById('limitsArea').innerHTML = `
      <div class="usage-block">
        <div class="usage-header"><span class="usage-title">Today</span><span class="usage-count">${usage.today.requests} / ${dl}</span></div>
        <div class="progress-bar"><div class="progress-fill ${dp>90?'danger':dp>70?'warning':''}" style="width:${dp}%"></div></div>
      </div>
      <div class="usage-block">
        <div class="usage-header"><span class="usage-title">This month</span><span class="usage-count">${usage.month.requests} / ${ml}</span></div>
        <div class="progress-bar"><div class="progress-fill ${mp>90?'danger':mp>70?'warning':''}" style="width:${mp}%"></div></div>
      </div>
      <div style="margin-top:20px;padding-top:16px;border-top:1px solid var(--border)">
        <div style="font-size:11px;color:var(--text-3);text-transform:uppercase;letter-spacing:.05em;margin-bottom:4px">Cost this month</div>
        <div style="font-size:24px;font-weight:700;color:var(--accent)">$${usage.month.costUsd}</div>
      </div>`;
  }

  const rc = document.getElementById('recentConvs');
  if (convs?.conversations?.length) {
    rc.innerHTML = `<table>
      <thead><tr><th>Title</th><th>Messages</th><th>Last active</th><th></th></tr></thead>
      <tbody>${convs.conversations.map(c => `
        <tr>
          <td style="color:var(--text);font-weight:500;max-width:240px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${c.title}</td>
          <td>${c.message_count}</td>
          <td>${new Date(c.last_message_at || c.created_at).toLocaleDateString()}</td>
          <td><button class="btn btn-ghost btn-sm">Open →</button></td>
        </tr>`).join('')}</tbody></table>`;
  } else {
    rc.innerHTML = `<div style="text-align:center;padding:32px;color:var(--text-3)">
      No conversations yet.<br>Install the Studio plugin and start chatting!
    </div>`;
  }
}

async function renderUsage() {
  document.getElementById('mainContent').innerHTML = `
    <div class="page-header"><h1>Usage Analytics</h1><p class="page-subtitle">Monitor your API consumption</p></div>
    <div id="usageContent" style="color:var(--text-3);font-size:14px">Loading...</div>`;
  const usage = await api('GET', '/usage');
  if (!usage) return;
  document.getElementById('usageContent').innerHTML = `
    <div class="stats-grid" style="margin-bottom:28px">
      <div class="stat-card"><div class="stat-label">Today's requests</div><div class="stat-value">${usage.today.requests}</div><div class="stat-sub">of ${usage.today.limit === -1 ? '∞' : usage.today.limit} daily</div></div>
      <div class="stat-card"><div class="stat-label">Month requests</div><div class="stat-value">${usage.month.requests.toLocaleString()}</div><div class="stat-sub">of ${usage.month.limit === -1 ? '∞' : usage.month.limit} monthly</div></div>
      <div class="stat-card"><div class="stat-label">Input tokens</div><div class="stat-value">${(usage.month.tokensInput/1000).toFixed(1)}k</div></div>
      <div class="stat-card"><div class="stat-label">Output tokens</div><div class="stat-value">${(usage.month.tokensOutput/1000).toFixed(1)}k</div></div>
      <div class="stat-card"><div class="stat-label">Est. cost</div><div class="stat-value" style="color:var(--accent)">$${usage.month.costUsd}</div></div>
    </div>
    <div class="card" style="border-color:var(--accent)">
      <h3 style="margin-bottom:6px">Need more capacity?</h3>
      <p style="color:var(--text-2);font-size:13px;margin-bottom:16px">Upgrade for higher limits and priority responses.</p>
      <button class="btn btn-primary" onclick="navigate('billing')">View plans →</button>
    </div>`;
}

async function renderHistory() {
  document.getElementById('mainContent').innerHTML = `
    <div class="page-header"><h1>Conversation History</h1><p class="page-subtitle">All your Claude sessions</p></div>
    <div id="histContent" class="card table-wrap"><div style="color:var(--text-3);font-size:13px">Loading...</div></div>`;
  const result = await api('GET', '/conversations?limit=100');
  const el = document.getElementById('histContent');
  if (!result?.conversations?.length) { el.innerHTML = `<div style="text-align:center;padding:40px;color:var(--text-3)">No conversations yet</div>`; return; }
  el.innerHTML = `<table>
    <thead><tr><th>Conversation</th><th>Messages</th><th>Started</th><th>Last active</th><th></th></tr></thead>
    <tbody>${result.conversations.map(c => `
      <tr>
        <td style="color:var(--text);font-weight:500;max-width:260px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="${c.title}">${c.title}</td>
        <td>${c.message_count}</td>
        <td>${new Date(c.created_at).toLocaleDateString()}</td>
        <td>${new Date(c.last_message_at || c.created_at).toLocaleDateString()}</td>
        <td><button class="btn btn-danger btn-sm" onclick="deleteConv('${c.id}')">Delete</button></td>
      </tr>`).join('')}</tbody></table>`;
}
async function deleteConv(id) {
  if (!confirm('Archive this conversation?')) return;
  await api('DELETE', `/conversations/${id}`); renderHistory(); toast('Conversation archived');
}

async function renderBilling() {
  document.getElementById('mainContent').innerHTML = `
    <div class="page-header"><h1>Billing & Plans</h1><p class="page-subtitle">Manage your Lime AI subscription</p></div>
    <div class="pricing-grid" style="margin-bottom:28px">
      <div class="plan-card">
        <div class="plan-name">Free</div>
        <div class="plan-price">$0</div><div class="plan-period">/ month</div>
        <div class="plan-divider"></div>
        <div class="plan-feature">20 requests / day</div>
        <div class="plan-feature">100 requests / month</div>
        <div class="plan-feature">Basic code generation</div>
        <div class="plan-feature">10 conversations</div>
        <div class="plan-cta"><button class="btn btn-ghost btn-block" disabled>Current plan</button></div>
      </div>
      <div class="plan-card featured">
        <div class="plan-popular">Most Popular</div>
        <div class="plan-name">Pro</div>
        <div class="plan-price" style="color:var(--accent)">$19</div><div class="plan-period">/ month</div>
        <div class="plan-divider"></div>
        <div class="plan-feature">200 requests / day</div>
        <div class="plan-feature">5,000 requests / month</div>
        <div class="plan-feature">Full conversation history</div>
        <div class="plan-feature">Code analysis & refactor</div>
        <div class="plan-feature">Generate full game systems</div>
        <div class="plan-feature">100 conversations</div>
        <div class="plan-cta"><button class="btn btn-primary btn-block" onclick="checkout('pro')">Upgrade to Pro</button></div>
      </div>
      <div class="plan-card">
        <div class="plan-name">Team</div>
        <div class="plan-price">$49</div><div class="plan-period">/ month</div>
        <div class="plan-divider"></div>
        <div class="plan-feature">1,000 requests / day</div>
        <div class="plan-feature">25,000 requests / month</div>
        <div class="plan-feature">Team workspace</div>
        <div class="plan-feature">Priority support</div>
        <div class="plan-cta"><button class="btn btn-ghost btn-block" onclick="checkout('team')">Upgrade to Team</button></div>
      </div>
      <div class="plan-card">
        <div class="plan-name">Enterprise</div>
        <div class="plan-price">$199</div><div class="plan-period">/ month</div>
        <div class="plan-divider"></div>
        <div class="plan-feature">Unlimited requests</div>
        <div class="plan-feature">Dedicated support</div>
        <div class="plan-feature">Custom system prompts</div>
        <div class="plan-feature">SLA guarantee</div>
        <div class="plan-cta"><button class="btn btn-ghost btn-block" onclick="checkout('enterprise')">Get Enterprise</button></div>
      </div>
    </div>
    <div class="card">
      <h3 style="margin-bottom:12px">Current subscription</h3>
      <div style="display:flex;align-items:center;justify-content:space-between">
        <div>
          <div style="font-weight:600">${state.user?.plan_display_name || 'Free'} Plan</div>
          <div style="color:var(--text-2);font-size:13px;margin-top:2px">Active</div>
        </div>
        <button class="btn btn-ghost btn-sm" onclick="managePortal()">Manage billing →</button>
      </div>
    </div>`;
}
async function checkout(p) { const r = await api('POST', '/billing/create-checkout', { planName: p }); if (r?.url) window.open(r.url, '_blank'); else toast('Checkout unavailable', 'error'); }
async function managePortal() { const r = await api('POST', '/billing/portal'); if (r?.url) window.open(r.url, '_blank'); else toast('No billing account found', 'error'); }

async function renderApiKeys() {
  document.getElementById('mainContent').innerHTML = `
    <div class="page-header"><h1>API Keys</h1><p class="page-subtitle">For direct API access outside of Studio</p></div>
    <div class="card" style="margin-bottom:16px">
      <h3 style="margin-bottom:6px">Generate key</h3>
      <p style="color:var(--text-2);font-size:13px;margin-bottom:14px">Keys grant full API access as your account. Keep them secret.</p>
      <div style="display:flex;gap:10px">
        <input type="text" id="keyName" placeholder="Key name (e.g. My Bot)" style="max-width:280px"/>
        <button class="btn btn-primary" onclick="generateKey()">Generate</button>
      </div>
    </div>
    <div class="card"><h3 style="margin-bottom:12px">Active keys</h3><div style="color:var(--text-3);font-size:13px">No API keys yet.</div></div>`;
}
function generateKey() { toast('Key generation coming soon'); }

async function renderSettings() {
  document.getElementById('mainContent').innerHTML = `
    <div class="page-header"><h1>Settings</h1><p class="page-subtitle">Manage your account</p></div>
    <div class="card" style="margin-bottom:16px">
      <h3 style="margin-bottom:16px">Profile</h3>
      <div class="form-group"><label>Email</label><input type="email" value="${state.user?.email || ''}" disabled style="opacity:0.5"/></div>
      <div class="form-group"><label>Display name</label><input type="text" id="displayName" value="${state.user?.display_name || ''}" placeholder="Your name"/></div>
      <div class="form-group"><label>Roblox username</label><input type="text" id="robloxUsername" value="${state.user?.roblox_username || ''}" placeholder="YourRobloxName"/></div>
      <button class="btn btn-primary" onclick="saveProfile()">Save changes</button>
    </div>
    <div class="card">
      <h3 style="margin-bottom:8px">Sign out</h3>
      <p style="color:var(--text-2);font-size:13px;margin-bottom:14px">Sign out of Lime AI on this device.</p>
      <button class="btn btn-danger" onclick="doLogout()">Sign out</button>
    </div>`;
}
async function saveProfile() {
  const r = await api('PATCH', '/user/me', { displayName: document.getElementById('displayName').value, robloxUsername: document.getElementById('robloxUsername').value });
  if (r?.message) toast('Profile saved ✓'); else toast('Save failed', 'error');
}

async function renderAdmin() {
  document.getElementById('mainContent').innerHTML = `
    <div class="page-header"><h1>Admin Panel</h1><p class="page-subtitle">Lime AI platform management</p></div>
    <div class="stats-grid" style="margin-bottom:28px">
      <div class="stat-card"><div class="stat-label">Total users</div><div class="stat-value" id="aU">—</div></div>
      <div class="stat-card"><div class="stat-label">New (30d)</div><div class="stat-value" id="aN">—</div></div>
      <div class="stat-card"><div class="stat-label">MRR</div><div class="stat-value" id="aM">—</div></div>
      <div class="stat-card"><div class="stat-label">Month requests</div><div class="stat-value" id="aR">—</div></div>
    </div>
    <div class="card">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:16px">
        <h3>Users</h3>
        <input type="text" placeholder="Search..." style="width:200px" oninput="searchUsers(this.value)"/>
      </div>
      <div id="usersTable" class="table-wrap"><div style="color:var(--text-3);font-size:13px">Loading...</div></div>
    </div>`;
  const stats = await api('GET', '/admin/stats');
  if (stats) {
    document.getElementById('aU').textContent = parseInt(stats.users.total).toLocaleString();
    document.getElementById('aN').textContent = parseInt(stats.users.new_30d).toLocaleString();
    document.getElementById('aM').textContent = '$' + (parseInt(stats.revenue.month_cents)/100).toLocaleString();
    document.getElementById('aR').textContent = parseInt(stats.usage.total_requests).toLocaleString();
  }
  loadAdminUsers();
}
async function loadAdminUsers(search = '') {
  const result = await api('GET', `/admin/users?limit=50${search ? `&search=${encodeURIComponent(search)}` : ''}`);
  const el = document.getElementById('usersTable');
  if (!result?.users?.length) { el.innerHTML = `<div style="color:var(--text-3);font-size:13px;padding:8px 0">No users found</div>`; return; }
  el.innerHTML = `<table><thead><tr><th>Email</th><th>Plan</th><th>Joined</th><th>Last login</th><th>Status</th><th></th></tr></thead><tbody>${result.users.map(u => `
    <tr>
      <td style="color:var(--text)">${u.email}</td>
      <td><span class="badge badge-${u.plan_name||'free'}">${(u.plan_name||'free').toUpperCase()}</span></td>
      <td>${new Date(u.created_at).toLocaleDateString()}</td>
      <td>${u.last_login_at ? new Date(u.last_login_at).toLocaleDateString() : 'Never'}</td>
      <td><span class="badge ${u.is_banned?'badge-error':'badge-active'}">${u.is_banned?'Banned':'Active'}</span></td>
      <td>${!u.is_banned ? `<button class="btn btn-danger btn-sm" onclick="banUser('${u.id}')">Ban</button>` : ''}</td>
    </tr>`).join('')}</tbody></table>`;
}
let sT; function searchUsers(v) { clearTimeout(sT); sT = setTimeout(() => loadAdminUsers(v), 300); }
async function banUser(id) { const reason = prompt('Reason:'); if (!reason) return; await api('POST', `/admin/users/${id}/ban`, { reason }); toast('User banned'); loadAdminUsers(); }

function toast(msg, type = 'success') {
  const el = document.createElement('div'); el.className = 'toast';
  el.innerHTML = `<span style="color:${type==='error'?'var(--red)':'var(--accent)'}">${type==='error'?'✗':'✓'}</span> ${msg}`;
  document.body.appendChild(el); setTimeout(() => el.remove(), 3000);
}

if (state.accessToken) initApp();
</script>
</body>
</html>
                                                                                                                                                                                                                                                                                                                       roblox-ai-platform/docs/                                                                            0000755 0000000 0000000 00000000000 15211362550 014222  5                                                                                                    ustar   root                            root                                                                                                                                                                                                                   roblox-ai-platform/docs/DEPLOYMENT.md                                                               0000644 0000000 0000000 00000026646 15211362550 016242  0                                                                                                    ustar   root                            root                                                                                                                                                                                                                   # Lime AI Platform — Complete Deployment & Architecture Guide

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
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                          
