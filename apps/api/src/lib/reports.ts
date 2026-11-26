import { TERMINAL_STATUSES, type ReportPublic, type ReportStatus } from '@siagasos/shared';
import type { Db } from '../db.js';
import { ApiError, notFound } from './errors.js';
import { publish } from './realtime.js';
import { enqueueWebhook } from './webhooks.js';
import { notifyResponders } from './notify.js';

const STATUS_MESSAGES: Record<ReportStatus, string> = {
  open: 'Laporan terkirim. Menunggu tim merespons.',
  acknowledged: 'Laporan diterima. Tim sedang menuju lokasi Anda.',
  in_progress: 'Tim sedang menangani laporan Anda.',
  resolved: 'Laporan sudah selesai ditangani.',
  cancelled: 'Laporan dibatalkan.',
  false_alarm: 'Laporan ditandai sebagai alarm palsu.',
};

export function publicReport(r: any): ReportPublic {
  return {
    id: r.id,
    kind: r.kind ?? 'sos',
    status: r.status,
    mode: r.mode,
    category: r.category,
    created_at: r.created_at,
    acknowledged_at: r.acknowledged_at,
    resolved_at: r.resolved_at,
    status_message: r.status_message ?? STATUS_MESSAGES[r.status as ReportStatus] ?? null,
  };
}

export function fullReport(r: any) {
  return {
    id: r.id,
    kind: r.kind ?? 'sos',
    app_id: r.app_id,
    source_key: r.source_key ?? null,
    mode: r.mode,
    category: r.category,
    status: r.status,
    status_message: r.status_message,
    message: r.message,
    complaint: r.complaint_details ?? null,
    location: r.lat == null ? null : { lat: r.lat, lng: r.lng, accuracy_m: r.accuracy_m },
    reporter: { ref: r.reporter_ref, name: r.reporter_name, phone: r.reporter_phone },
    device: r.device,
    metadata: r.metadata,
    client_created_at: r.client_created_at,
    created_at: r.created_at,
    acknowledged_at: r.acknowledged_at,
    resolved_at: r.resolved_at,
    updated_at: r.updated_at,
  };
}

export const REPORT_SELECT = `SELECT r.*, s.source_key FROM reports r LEFT JOIN sources s ON s.id = r.source_id`;

export async function loadReport(c: Db, id: string, appId?: string) {
  if (!/^[0-9a-f-]{36}$/i.test(id)) throw notFound('Laporan');
  const { rows } = await c.query(
    `${REPORT_SELECT} WHERE r.id = $1 ${appId ? 'AND r.app_id = $2' : ''}`,
    appId ? [id, appId] : [id],
  );
  if (!rows[0]) throw notFound('Laporan');
  return rows[0];
}

export interface Actor { kind: 'user' | 'reporter' | 'server' | 'system' | 'responder' | 'partner'; id?: string | null; name?: string | null }

/** Satu-satunya jalur ubah status: menulis timeline, broadcast realtime, dan antre webhook. */
export async function changeReport(c: Db, id: string, input: { status?: ReportStatus; note?: string }, actor: Actor, appId?: string) {
  const r = await loadReport(c, id, appId);
  let updated = r;

  if (input.status && input.status !== r.status) {
    if (TERMINAL_STATUSES.includes(r.status)) {
      throw new ApiError(409, 'report_closed', `Laporan sudah ${r.status}, status tidak bisa diubah`);
    }
    const terminal = TERMINAL_STATUSES.includes(input.status);
    const { rows } = await c.query(
      `UPDATE reports SET status = $2, status_message = NULL, updated_at = now(),
         acknowledged_at = CASE WHEN acknowledged_at IS NULL AND $2 <> 'open' THEN now() ELSE acknowledged_at END,
         resolved_at = CASE WHEN $3 THEN now() ELSE resolved_at END
       WHERE id = $1 RETURNING *`,
      [id, input.status, terminal],
    );
    updated = { ...rows[0], source_key: r.source_key };
    await c.query(
      `INSERT INTO report_events (report_id, account_id, actor_id, actor_kind, type, from_status, to_status, note)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
      [id, r.account_id, actor.kind === 'user' ? actor.id : null, actor.kind,
        input.status === 'cancelled' && actor.kind === 'reporter' ? 'cancelled' : 'status_changed',
        r.status, input.status, input.note ?? null],
    );
  } else if (input.note) {
    await c.query(
      `INSERT INTO report_events (report_id, account_id, actor_id, actor_kind, type, note) VALUES ($1,$2,$3,$4,'note',$5)`,
      [id, r.account_id, actor.kind === 'user' ? actor.id : null, actor.kind, input.note],
    );
  }

  const evType = input.status && input.status !== r.status
    ? (input.status === 'cancelled' ? 'report.cancelled' : 'report.status_changed')
    : 'report.note_added';
  const full = fullReport(updated);
  publish(r.account_id, evType, { report: full, actor: { kind: actor.kind, name: actor.name ?? null }, note: input.note ?? null });
  if (evType !== 'report.note_added') await enqueueWebhook(c, r.app_id, r.account_id, r.id, evType, full, r.mode);
  return updated;
}

export async function onReportCreated(c: Db, report: any, appName: string) {
  const full = fullReport(report);
  publish(report.account_id, 'report.created', { report: full });
  await enqueueWebhook(c, report.app_id, report.account_id, report.id, 'report.created', full, report.mode);
  // Pengaduan bukan darurat: tidak memicu email darurat ke responder (tetap realtime + webhook).
  if (report.mode === 'live' && report.kind !== 'pengaduan') notifyResponders(report.account_id, full, appName);
}
