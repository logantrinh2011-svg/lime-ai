-- ============================================================
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
