import type { Response } from 'express';
import { redis, subscriber } from '../redis.js';
import { logger } from '../logger.js';

/**
 * Hub realtime dashboard. Event dipublish ke Redis pub/sub supaya semua instance API
 * menerima event yang sama; tiap instance meneruskan ke koneksi SSE lokalnya.
 */
const clients = new Map<string, Set<Response>>();
let started = false;

function dispatch(accountId: string, payload: string) {
  for (const res of clients.get(accountId) ?? []) res.write(`data: ${payload}\n\n`);
}

export function startRealtime() {
  if (started) return;
  started = true;
  const sub = subscriber();
  sub.psubscribe('rt:acc:*').catch((err) => logger.warn({ err: err.message }, 'psubscribe gagal'));
  sub.on('pmessage', (_p, channel, msg) => dispatch(channel.slice('rt:acc:'.length), msg));
}

export function publish(accountId: string, type: string, data: unknown) {
  const payload = JSON.stringify({ type, data, at: new Date().toISOString() });
  redis.publish(`rt:acc:${accountId}`, payload).catch(() => dispatch(accountId, payload)); // fallback 1 instance
}

export function attachClient(accountId: string, res: Response) {
  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache, no-transform',
    Connection: 'keep-alive',
    'X-Accel-Buffering': 'no',
  });
  res.write(`retry: 3000\n\n`);
  const set = clients.get(accountId) ?? new Set();
  set.add(res);
  clients.set(accountId, set);
  const ping = setInterval(() => res.write(`: ping\n\n`), 20_000);
  res.on('close', () => {
    clearInterval(ping);
    set.delete(res);
    if (!set.size) clients.delete(accountId);
  });
}
