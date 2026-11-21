import { redis } from '../redis.js';
import { logger } from '../logger.js';
import { ApiError } from './errors.js';

/**
 * Fixed-window counter di Redis. Fail-open: bila Redis bermasalah, laporan darurat TIDAK diblokir
 * (Redis bukan sumber kebenaran; kehilangan laporan lebih buruk daripada spam sesaat).
 */
export async function hit(bucket: string, limit: number, windowSec: number): Promise<{ ok: boolean; count: number }> {
  try {
    const key = `rl:${bucket}:${Math.floor(Date.now() / 1000 / windowSec)}`;
    const [[, count]] = (await redis.multi().incr(key).expire(key, windowSec + 5).exec()) as [[null, number]];
    return { ok: count <= limit, count };
  } catch (err) {
    logger.warn({ err: (err as Error).message, bucket }, 'rate limit fail-open');
    return { ok: true, count: 0 };
  }
}

export async function enforce(bucket: string, limit: number, windowSec: number, code = 'rate_limited') {
  const r = await hit(bucket, limit, windowSec);
  if (!r.ok) throw new ApiError(429, code, 'Terlalu banyak permintaan, coba lagi sebentar lagi', { limit, window_s: windowSec });
}
