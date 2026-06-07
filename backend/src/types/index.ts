// ============================================================
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
