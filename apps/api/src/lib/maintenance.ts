import { withPlatform, type Db } from '../db.js';
import { config } from '../config.js';
import { logger } from '../logger.js';
import { deleteObject, mediaEnabled } from './objectStorage.js';

/** Kunci advisory Postgres supaya hanya satu instance API yang menjalankan pembersihan per putaran. */
const LOCK_KEY = 0x5105_0001;
/** Media pending boleh tetap ada selama URL upload masih berlaku + masa tenggang (unggah lambat di jaringan seluler). */
const PENDING_GRACE_S = 3600;
const BATCH = 200;

export interface MaintenanceResult { skipped: boolean; mediaRemoved: number; otpsRemoved: number; reportsRemoved: number }

/** Laporan mode test dihapus 30 hari setelah ditutup, tanpa pengaturan. */
const TEST_RETENTION_DAYS = 30;

/**
 * Hapus laporan permanen (lokasi, timeline, media ikut lewat ON DELETE CASCADE). Mengembalikan key objek media
 * yang harus dihapus dari bucket SETELAH transaksi commit (lihat removeObjects).
 */
export async function deleteReports(c: Db, ids: string[]): Promise<{ reports: number; storageKeys: string[] }> {
  if (!ids.length) return { reports: 0, storageKeys: [] };
  const media = await c.query<{ storage_key: string }>(`SELECT storage_key FROM report_media WHERE report_id = ANY($1::uuid[])`, [ids]);
  const del = await c.query(`DELETE FROM reports WHERE id = ANY($1::uuid[])`, [ids]);
  return { reports: del.rowCount ?? 0, storageKeys: media.rows.map((m) => m.storage_key) };
}

/** Hapus objek dari bucket; kegagalan hanya dicatat (objek yatim lebih baik daripada data DB tertahan). */
export async function removeObjects(keys: string[]) {
  if (!keys.length || !mediaEnabled()) return;
  for (const key of keys) await deleteObject(key);
}

/**
 * Bersihkan sisa & data kedaluwarsa:
 * - report_media `pending` yang tidak pernah di-complete;
 * - laporan berstatus akhir yang melewati retensi app (apps.retention_days) atau 30 hari untuk mode test;
 * - responder_otps yang sudah kedaluwarsa / terpakai > 1 hari.
 * Laporan yang belum ditutup tidak pernah dihapus. Bukan bagian jalur SOS; gagal di sini hanya dicatat.
 */
export async function runMaintenance(): Promise<MaintenanceResult> {
  const out = await withPlatform(async (c) => {
    const lock = await c.query(`SELECT pg_try_advisory_xact_lock($1) AS ok`, [LOCK_KEY]);
    if (!lock.rows[0].ok) return { skipped: true, mediaRemoved: 0, otpsRemoved: 0, reportsRemoved: 0, keys: [] as string[] };

    const stale = await c.query<{ id: string; storage_key: string }>(
      `SELECT id, storage_key FROM report_media
       WHERE status = 'pending' AND created_at < now() - make_interval(secs => $1)
       ORDER BY created_at LIMIT $2 FOR UPDATE SKIP LOCKED`,
      [config.media.uploadUrlTtlS + PENDING_GRACE_S, BATCH],
    );
    if (stale.rows.length) await c.query(`DELETE FROM report_media WHERE id = ANY($1::uuid[])`, [stale.rows.map((m) => m.id)]);

    const expired = await c.query<{ id: string }>(
      `SELECT r.id FROM reports r JOIN apps a ON a.id = r.app_id
       WHERE r.resolved_at IS NOT NULL AND r.status IN ('resolved', 'cancelled', 'false_alarm')
         AND ((r.mode = 'test' AND r.resolved_at < now() - make_interval(days => $1))
           OR (r.mode = 'live' AND a.retention_days IS NOT NULL AND r.resolved_at < now() - make_interval(days => a.retention_days)))
       ORDER BY r.resolved_at LIMIT $2 FOR UPDATE OF r SKIP LOCKED`,
      [TEST_RETENTION_DAYS, BATCH],
    );
    const purged = await deleteReports(c, expired.rows.map((r) => r.id));

    const otps = await c.query(
      `DELETE FROM responder_otps WHERE coalesce(consumed_at, expires_at) < now() - interval '1 day'`,
    );
    return {
      skipped: false, mediaRemoved: stale.rows.length, otpsRemoved: otps.rowCount ?? 0, reportsRemoved: purged.reports,
      keys: [...stale.rows.map((m) => m.storage_key), ...purged.storageKeys],
    };
  });
  const { keys, ...result } = out;
  await removeObjects(keys);
  return result;
}

/** Jalankan berkala di proses API (default tiap 10 menit, pertama 30 dtk setelah start). */
export function startMaintenance(intervalMs = 10 * 60_000) {
  let busy = false;
  const tick = async () => {
    if (busy) return;
    busy = true;
    try {
      const r = await runMaintenance();
      if (r.mediaRemoved || r.otpsRemoved || r.reportsRemoved) logger.info(r, 'maintenance: sisa dibersihkan');
    } catch (err) {
      logger.error({ err }, 'maintenance error');
    } finally {
      busy = false;
    }
  };
  const first = setTimeout(tick, 30_000);
  first.unref();
  const every = setInterval(tick, intervalMs);
  every.unref();
  return () => { clearTimeout(first); clearInterval(every); };
}
