import { randomUUID } from 'node:crypto';
import type { Db } from '../db.js';
import { withPlatform } from '../db.js';
import { hmac } from './crypto.js';
import { logger } from '../logger.js';

export function signPayload(secret: string, body: string, ts = Math.floor(Date.now() / 1000)) {
  return `t=${ts},v1=${hmac(secret, `${ts}.${body}`)}`;
}

export async function enqueueWebhook(c: Db, appId: string, accountId: string, reportId: string, event: string, data: unknown, mode: string) {
  const { rows } = await c.query(`SELECT webhook_url FROM apps WHERE id = $1`, [appId]);
  if (!rows[0]?.webhook_url) return;
  const payload = { id: `evt_${randomUUID().replace(/-/g, '')}`, type: event, livemode: mode === 'live', created: new Date().toISOString(), data: { report: data } };
  await c.query(
    `INSERT INTO webhook_deliveries (app_id, account_id, report_id, event, payload, next_retry_at) VALUES ($1,$2,$3,$4,$5, now())`,
    [appId, accountId, reportId, event, JSON.stringify(payload)],
  );
}

export async function deliver(url: string, secret: string, payload: unknown) {
  const body = JSON.stringify(payload);
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'User-Agent': 'SiagaSOS-Webhook/0.1', 'X-SOS-Signature': signPayload(secret, body) },
    body,
    signal: AbortSignal.timeout(10_000),
  });
  return res.status;
}

const MAX_AGE_MS = 24 * 3600_000;

/** Worker sederhana di proses API: ambil job jatuh tempo, kirim, backoff eksponensial s.d. 24 jam. */
export function startWebhookWorker(intervalMs = 3000) {
  let busy = false;
  const tick = async () => {
    if (busy) return;
    busy = true;
    try {
      await withPlatform(async (c) => {
        const { rows } = await c.query(
          `SELECT d.*, a.webhook_url, a.webhook_secret FROM webhook_deliveries d JOIN apps a ON a.id = d.app_id
           WHERE d.delivered_at IS NULL AND d.next_retry_at <= now() ORDER BY d.next_retry_at LIMIT 20
           FOR UPDATE OF d SKIP LOCKED`,
        );
        for (const d of rows) {
          let status: number | null = null;
          let error: string | null = null;
          try {
            if (!d.webhook_url) throw new Error('webhook_url kosong');
            status = await deliver(d.webhook_url, d.webhook_secret, d.payload);
            if (status < 200 || status >= 300) error = `HTTP ${status}`;
          } catch (e) {
            error = (e as Error).message;
          }
          const attempts = d.attempts + 1;
          const expired = Date.now() - new Date(d.created_at).getTime() > MAX_AGE_MS;
          const delaySec = Math.min(30 * 2 ** (attempts - 1), 6 * 3600);
          await c.query(
            `UPDATE webhook_deliveries SET attempts = $2, status_code = $3, last_error = $4,
               delivered_at = CASE WHEN $4::text IS NULL THEN now() END,
               next_retry_at = CASE WHEN $4::text IS NULL OR $5 THEN NULL ELSE now() + make_interval(secs => $6) END
             WHERE id = $1`,
            [d.id, attempts, status, error, expired, delaySec],
          );
        }
      });
    } catch (err) {
      logger.error({ err }, 'webhook worker error');
    } finally {
      busy = false;
    }
  };
  return setInterval(tick, intervalMs);
}
