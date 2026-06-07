// ============================================================
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
