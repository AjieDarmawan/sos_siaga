import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { pool } from './db.js';

/** Runner migrasi sederhana: jalankan file migrations/*.sql yang belum tercatat, masing-masing dalam satu transaksi. */
const dir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../migrations');

async function main() {
  await pool.query(`CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())`);
  const done = new Set((await pool.query(`SELECT name FROM schema_migrations`)).rows.map((r) => r.name));
  const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();
  for (const f of files) {
    if (done.has(f)) continue;
    const sql = await readFile(path.join(dir, f), 'utf8');
    const c = await pool.connect();
    try {
      await c.query('BEGIN');
      await c.query(sql);
      await c.query(`INSERT INTO schema_migrations (name) VALUES ($1)`, [f]);
      await c.query('COMMIT');
      console.log(`✔ ${f}`);
    } catch (e) {
      await c.query('ROLLBACK');
      console.error(`✘ ${f}`);
      throw e;
    } finally {
      c.release();
    }
  }
  console.log('migrations up to date');
  await pool.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
