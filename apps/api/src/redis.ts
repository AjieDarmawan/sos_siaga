import { Redis } from 'ioredis';
import { config } from './config.js';
import { logger } from './logger.js';

// Redis hanya untuk rate limit & pub/sub realtime, bukan sumber kebenaran. commandTimeout pendek:
// bila Redis lambat/mati, jalur SOS tetap jalan (rate limit fail-open).
function make(name: string, opts: { commandTimeout?: number } = {}) {
  const r = new Redis(config.redisUrl, { maxRetriesPerRequest: 1, ...opts });
  r.on('error', (err) => logger.warn({ err: err.message, name }, 'redis error'));
  return r;
}

export const redis = make('main', { commandTimeout: 500 });
let sub: Redis | null = null;
export function subscriber() {
  return (sub ??= make('sub'));
}
