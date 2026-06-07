// ============================================================
// Lime AI Platform — Claude API Service
// Complete integration with streaming, retry, token tracking
// ============================================================

import Anthropic from '@anthropic-ai/sdk';
import { Message, StreamEvent } from '../types/index.js';
import { logger } from '../utils/logger.js';
import { db } from '../db/client.js';
import { Response } from 'express';

const anthropic = new Anthropic({
  apiKey: process.env.ANTHROPIC_API_KEY!,
});

// Cost per 1M tokens (USD) — update as pricing changes
const PRICING = {
  'claude-sonnet-4-20250514': { input: 3.0, output: 15.0 },
  'claude-opus-4-20250514':   { input: 15.0, output: 75.0 },
  'claude-haiku-4-5-20251001':{ input: 0.25, output: 1.25 },
} as const;

type ModelKey = keyof typeof PRICING;

// ─────────────────────────────────────────────
// SYSTEM PROMPT — Roblox AI Coding Expert
// ─────────────────────────────────────────────
export function buildSystemPrompt(): string {
  return `You are Lime AI, an expert Roblox game development assistant built into Roblox Studio. You have deep expertise in:

**Roblox Development:**
- Lua and Luau scripting (Roblox's typed Lua variant)
- Roblox API, services (Players, Workspace, ReplicatedStorage, ServerStorage, etc.)
- RemoteEvents and RemoteFunctions for client-server communication
- DataStoreService for persistent data
- TweenService, RunService, UserInputService, GuiService
- Roblox's character model, humanoids, and physics
- ModuleScripts, LocalScripts, Scripts — when to use each
- Roblox Studio workflows and best practices

**Code Quality:**
- Always write production-quality Luau code with type annotations
- Follow Roblox's security model: server authority, client prediction
- Use pcall() for error handling on potentially-failing operations
- Comment your code clearly
- Avoid deprecated APIs

**Response Format:**
- When providing code, always wrap it in code blocks with the language tag: \`\`\`lua
- Clearly label whether code goes in a Script, LocalScript, or ModuleScript
- Explain WHERE to place the script in the game hierarchy
- For multi-file systems, show each file separately with its path

**Capabilities:**
- Generate complete game systems (inventory, combat, trading, etc.)
- Fix bugs in existing code
- Refactor and optimize scripts
- Analyze scripts for security vulnerabilities
- Generate entire game frameworks
- Explain Roblox concepts clearly

Always be concise, practical, and production-focused. Never hallucinate Roblox APIs that don't exist.`;
}

// ─────────────────────────────────────────────
// LOAD CONVERSATION HISTORY FROM DB
// ─────────────────────────────────────────────
async function loadConversationHistory(
  conversationId: string,
  userId: string,
  maxMessages = 20
): Promise<Anthropic.MessageParam[]> {
  const { rows } = await db.query<Message>(
    `SELECT role, content FROM messages
     WHERE conversation_id = $1 AND user_id = $2 AND role != 'system'
     ORDER BY created_at DESC
     LIMIT $3`,
    [conversationId, userId, maxMessages]
  );

  // Reverse to get chronological order, map to Anthropic format
  return rows.reverse().map((msg) => ({
    role: msg.role as 'user' | 'assistant',
    content: msg.content,
  }));
}

// ─────────────────────────────────────────────
// SAVE MESSAGE TO DB
// ─────────────────────────────────────────────
async function saveMessage(
  conversationId: string,
  userId: string,
  role: 'user' | 'assistant',
  content: string,
  model: string,
  tokensInput: number,
  tokensOutput: number
): Promise<string> {
  const { rows } = await db.query<{ id: string }>(
    `INSERT INTO messages (conversation_id, user_id, role, content, model, tokens_input, tokens_output)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     RETURNING id`,
    [conversationId, userId, role, content, model, tokensInput, tokensOutput]
  );
  return rows[0].id;
}

// ─────────────────────────────────────────────
// ENSURE OR CREATE CONVERSATION
// ─────────────────────────────────────────────
export async function ensureConversation(
  userId: string,
  conversationId?: string,
  firstMessage?: string
): Promise<string> {
  if (conversationId) {
    // Verify it belongs to this user
    const { rows } = await db.query(
      'SELECT id FROM conversations WHERE id = $1 AND user_id = $2',
      [conversationId, userId]
    );
    if (rows.length === 0) throw new Error('Conversation not found');
    return conversationId;
  }

  // Create new conversation, use first 50 chars of message as title
  const title = firstMessage
    ? firstMessage.slice(0, 50) + (firstMessage.length > 50 ? '...' : '')
    : 'New Conversation';

  const { rows } = await db.query<{ id: string }>(
    `INSERT INTO conversations (user_id, title) VALUES ($1, $2) RETURNING id`,
    [userId, title]
  );
  return rows[0].id;
}

// ─────────────────────────────────────────────
// CALCULATE COST
// ─────────────────────────────────────────────
function calculateCost(model: string, tokensIn: number, tokensOut: number): number {
  const pricing = PRICING[model as ModelKey] ?? PRICING['claude-sonnet-4-20250514'];
  return (tokensIn / 1_000_000) * pricing.input + (tokensOut / 1_000_000) * pricing.output;
}

// ─────────────────────────────────────────────
// RECORD USAGE
// ─────────────────────────────────────────────
async function recordUsage(
  userId: string,
  conversationId: string,
  messageId: string,
  planName: string,
  model: string,
  tokensIn: number,
  tokensOut: number,
  latencyMs: number,
  success: boolean,
  errorCode?: string
): Promise<void> {
  const costUsd = calculateCost(model, tokensIn, tokensOut);
  await db.query(
    `INSERT INTO usage_logs (user_id, conversation_id, message_id, plan_name, model,
       tokens_input, tokens_output, cost_usd, latency_ms, success, error_code)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11)`,
    [userId, conversationId, messageId, planName, model,
     tokensIn, tokensOut, costUsd, latencyMs, success, errorCode]
  );
}

// ─────────────────────────────────────────────
// CHECK USAGE LIMITS
// ─────────────────────────────────────────────
export async function checkUsageLimits(
  userId: string,
  planLimits: { requestsPerDay: number; requestsPerMonth: number }
): Promise<void> {
  if (planLimits.requestsPerDay === -1) return; // unlimited

  // Daily limit
  const { rows: daily } = await db.query<{ count: string }>(
    `SELECT COUNT(*) FROM usage_logs
     WHERE user_id = $1 AND success = true
       AND created_at >= DATE_TRUNC('day', NOW())`,
    [userId]
  );
  if (parseInt(daily[0].count) >= planLimits.requestsPerDay) {
    throw Object.assign(new Error('Daily request limit exceeded'), { code: 'LIMIT_DAILY' });
  }

  // Monthly limit
  if (planLimits.requestsPerMonth !== -1) {
    const { rows: monthly } = await db.query<{ count: string }>(
      `SELECT COUNT(*) FROM usage_logs
       WHERE user_id = $1 AND success = true
         AND created_at >= DATE_TRUNC('month', NOW())`,
      [userId]
    );
    if (parseInt(monthly[0].count) >= planLimits.requestsPerMonth) {
      throw Object.assign(new Error('Monthly request limit exceeded'), { code: 'LIMIT_MONTHLY' });
    }
  }
}

// ─────────────────────────────────────────────
// NON-STREAMING CHAT
// ─────────────────────────────────────────────
export async function chatWithClaude(params: {
  userId: string;
  userMessage: string;
  conversationId: string;
  planName: string;
  model?: string;
  maxTokens?: number;
}): Promise<{ content: string; messageId: string; tokensInput: number; tokensOutput: number }> {
  const model = params.model ?? 'claude-sonnet-4-20250514';
  const maxTokens = params.maxTokens ?? 4096;
  const startTime = Date.now();

  // Save user message
  const userMsgId = await saveMessage(
    params.conversationId, params.userId, 'user',
    params.userMessage, model, 0, 0
  );

  // Load history
  const history = await loadConversationHistory(params.conversationId, params.userId);

  // Retry logic — up to 3 attempts
  let lastError: Error | null = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      const response = await anthropic.messages.create({
        model,
        max_tokens: maxTokens,
        system: buildSystemPrompt(),
        messages: [
          ...history,
          { role: 'user', content: params.userMessage },
        ],
      });

      const content = response.content
        .filter((b) => b.type === 'text')
        .map((b) => (b as Anthropic.TextBlock).text)
        .join('');

      const tokensIn = response.usage.input_tokens;
      const tokensOut = response.usage.output_tokens;
      const latencyMs = Date.now() - startTime;

      // Save assistant response
      const assistantMsgId = await saveMessage(
        params.conversationId, params.userId, 'assistant',
        content, model, tokensIn, tokensOut
      );

      await recordUsage(
        params.userId, params.conversationId, assistantMsgId,
        params.planName, model, tokensIn, tokensOut, latencyMs, true
      );

      return { content, messageId: assistantMsgId, tokensInput: tokensIn, tokensOutput: tokensOut };

    } catch (err: unknown) {
      lastError = err as Error;
      const isRetryable = (err as { status?: number }).status === 529 ||
                          (err as { status?: number }).status === 503 ||
                          (err as NodeJS.ErrnoException).code === 'ECONNRESET';
      if (!isRetryable || attempt === 2) break;

      // Exponential backoff: 1s, 2s, 4s
      await new Promise((r) => setTimeout(r, Math.pow(2, attempt) * 1000));
      logger.warn(`Claude retry attempt ${attempt + 1}`, { error: lastError.message });
    }
  }

  await recordUsage(
    params.userId, params.conversationId, userMsgId,
    params.planName, model, 0, 0, Date.now() - startTime, false,
    lastError?.message
  );
  throw lastError;
}

// ─────────────────────────────────────────────
// STREAMING CHAT — SSE to client
// Roblox HttpService polls this endpoint and reads
// Server-Sent Events (text/event-stream)
// ─────────────────────────────────────────────
export async function streamChatWithClaude(params: {
  userId: string;
  userMessage: string;
  conversationId: string;
  planName: string;
  model?: string;
  maxTokens?: number;
  res: Response;
}): Promise<void> {
  const model = params.model ?? 'claude-sonnet-4-20250514';
  const maxTokens = params.maxTokens ?? 4096;
  const startTime = Date.now();

  // SSE headers
  params.res.setHeader('Content-Type', 'text/event-stream');
  params.res.setHeader('Cache-Control', 'no-cache');
  params.res.setHeader('Connection', 'keep-alive');
  params.res.setHeader('X-Accel-Buffering', 'no');
  params.res.flushHeaders();

  const sendEvent = (event: StreamEvent) => {
    params.res.write(`data: ${JSON.stringify(event)}\n\n`);
    // Force flush for real-time streaming
    if (typeof (params.res as unknown as { flush?: () => void }).flush === 'function') {
      (params.res as unknown as { flush: () => void }).flush();
    }
  };

  // Save user message
  await saveMessage(
    params.conversationId, params.userId, 'user',
    params.userMessage, model, 0, 0
  );

  const history = await loadConversationHistory(params.conversationId, params.userId);

  let fullContent = '';
  let tokensIn = 0;
  let tokensOut = 0;
  let assistantMsgId = '';

  sendEvent({ type: 'start', conversationId: params.conversationId });

  try {
    const stream = anthropic.messages.stream({
      model,
      max_tokens: maxTokens,
      system: buildSystemPrompt(),
      messages: [
        ...history,
        { role: 'user', content: params.userMessage },
      ],
    });

    for await (const event of stream) {
      if (event.type === 'content_block_delta' && event.delta.type === 'text_delta') {
        fullContent += event.delta.text;
        sendEvent({ type: 'delta', delta: event.delta.text });
      }
    }

    const finalMessage = await stream.finalMessage();
    tokensIn = finalMessage.usage.input_tokens;
    tokensOut = finalMessage.usage.output_tokens;

    assistantMsgId = await saveMessage(
      params.conversationId, params.userId, 'assistant',
      fullContent, model, tokensIn, tokensOut
    );

    const latencyMs = Date.now() - startTime;
    await recordUsage(
      params.userId, params.conversationId, assistantMsgId,
      params.planName, model, tokensIn, tokensOut, latencyMs, true
    );

    sendEvent({
      type: 'done',
      messageId: assistantMsgId,
      fullContent,
      tokensInput: tokensIn,
      tokensOutput: tokensOut,
    });

  } catch (err: unknown) {
    const error = err as Error;
    logger.error('Claude streaming error', { error: error.message, userId: params.userId });
    sendEvent({ type: 'error', error: error.message });
    await recordUsage(
      params.userId, params.conversationId, assistantMsgId || 'unknown',
      params.planName, model, tokensIn, tokensOut, Date.now() - startTime, false, error.message
    );
  } finally {
    params.res.end();
  }
}
