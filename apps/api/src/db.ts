import pg from 'pg';
import { config } from './config.js';
import { logger } from './logger.js';

export const pool = new pg.Pool({ connectionString: config.databaseUrl, max: 20 });
pool.on('error', (err) => logger.error({ err }, 'pg pool error'));

export type Db = pg.PoolClient;

/** Query tanpa konteks tenant. Hanya untuk tabel tanpa RLS (accounts, users, apps, api_keys, ...). */
export function q<T extends pg.QueryResultRow = any>(text: string, params?: unknown[]) {
  return pool.query<T>(text, params as any[]);
}

async function tx<T>(setup: (c: Db) => Promise<void>, fn: (c: Db) => Promise<T>): Promise<T> {
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    await setup(c);
    const out = await fn(c);
    await c.query('COMMIT');
    return out;
  } catch (e) {
    await c.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    c.release();
  }
}

/** Transaksi dengan konteks tenant; RLS hanya menampilkan baris milik accountId. */
export function withTenant<T>(accountId: string, fn: (c: Db) => Promise<T>) {
  return tx((c) => c.query(`SELECT set_config('app.account_id', $1, true)`, [accountId]).then(() => {}), fn);
}

/**
 * Transaksi mitra (/partner/v1): RLS partner_read hanya menampilkan laporan live dari app berpilar Polmas di dalam
 * prefiks wilayah `scope` ('' = nasional). Baca saja; untuk menulis, panggil asTenant() pada laporan yang terlihat.
 */
export function withPartner<T>(partnerId: string, scope: string, fn: (c: Db, asTenant: (accountId: string) => Promise<void>) => Promise<T>) {
  return tx(
    (c) => c.query(`SELECT set_config('app.partner_id', $1, true), set_config('app.partner_scope', $2, true)`, [partnerId, scope]).then(() => {}),
    (c) => fn(c, (accountId) => c.query(`SELECT set_config('app.account_id', $1, true)`, [accountId]).then(() => {})),
  );
}

/** Transaksi admin platform / job sistem lintas tenant. Jangan dipakai di route klien. */
export function withPlatform<T>(fn: (c: Db) => Promise<T>) {
  return tx((c) => c.query(`SELECT set_config('app.platform', 'on', true)`).then(() => {}), fn);
}
