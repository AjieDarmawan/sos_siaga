import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { TERMINAL_STATUSES } from '@siagasos/shared';
import type { Db } from '../db.js';
import { config } from '../config.js';
import { ApiError, notFound } from './errors.js';
import { headObject, mediaEnabled, presignGet, presignPut } from './objectStorage.js';
import { publish } from './realtime.js';

export type MediaKind = 'image' | 'video' | 'audio';

/** MIME yang diterima → jenis + ekstensi file. Parameter seperti `;codecs=opus` dibuang sebelum dicek. */
const MIME: Record<string, { kind: MediaKind; ext: string }> = {
  'image/jpeg': { kind: 'image', ext: 'jpg' },
  'image/png': { kind: 'image', ext: 'png' },
  'image/webp': { kind: 'image', ext: 'webp' },
  'image/heic': { kind: 'image', ext: 'heic' },
  'image/heif': { kind: 'image', ext: 'heif' },
  'video/mp4': { kind: 'video', ext: 'mp4' },
  'video/webm': { kind: 'video', ext: 'webm' },
  'video/quicktime': { kind: 'video', ext: 'mov' },
  'audio/webm': { kind: 'audio', ext: 'webm' },
  'audio/ogg': { kind: 'audio', ext: 'ogg' },
  'audio/mpeg': { kind: 'audio', ext: 'mp3' },
  'audio/mp4': { kind: 'audio', ext: 'm4a' },
  'audio/aac': { kind: 'audio', ext: 'aac' },
  'audio/wav': { kind: 'audio', ext: 'wav' },
  'audio/x-m4a': { kind: 'audio', ext: 'm4a' },
};
export const ACCEPTED_MIME = Object.keys(MIME);

export const createMediaSchema = z.object({
  content_type: z.string().min(3).max(120),
  size_bytes: z.number().int().positive(),
  duration_s: z.number().nonnegative().max(3600).optional(),
});

const KIND_LABEL: Record<MediaKind, string> = { image: 'Foto', video: 'Video', audio: 'Rekaman suara' };

function assertEnabled() {
  if (!mediaEnabled()) throw new ApiError(503, 'media_disabled', 'Penyimpanan media belum dikonfigurasi di server');
}

/** Izinkan lampiran selama laporan aktif, plus masa tenggang singkat setelah selesai (mis. upload video yang lambat). */
function assertReportAcceptsMedia(report: any) {
  if (!TERMINAL_STATUSES.includes(report.status)) return;
  const closedAt = new Date(report.resolved_at ?? report.updated_at).getTime();
  if (Date.now() - closedAt > config.media.graceAfterCloseMin * 60_000) {
    throw new ApiError(409, 'report_closed', 'Laporan sudah ditutup; lampiran tidak bisa ditambahkan lagi');
  }
}

/** Langkah 1: catat media `pending` dan berikan presigned PUT. Klien mengunggah langsung ke object storage. */
export async function createMediaUpload(c: Db, report: any, input: z.infer<typeof createMediaSchema>, uploadedBy: 'reporter' | 'user' | 'server') {
  assertEnabled();
  assertReportAcceptsMedia(report);
  const contentType = input.content_type.split(';')[0]!.trim().toLowerCase();
  const m = MIME[contentType];
  if (!m) throw new ApiError(415, 'unsupported_media_type', `Tipe ${contentType} tidak didukung. Gunakan foto (JPG/PNG/WEBP/HEIC), video (MP4/WEBM/MOV), atau suara (WEBM/OGG/MP3/M4A/AAC/WAV).`, { accepted: ACCEPTED_MIME });
  const max = config.media.maxBytes[m.kind];
  if (input.size_bytes > max) throw new ApiError(413, 'media_too_large', `${KIND_LABEL[m.kind]} maksimal ${Math.round(max / 1024 / 1024)} MB`);

  const { rows: cnt } = await c.query(`SELECT count(*)::int AS n FROM report_media WHERE report_id = $1`, [report.id]);
  if (cnt[0].n >= config.media.maxPerReport) throw new ApiError(422, 'media_limit', `Maksimal ${config.media.maxPerReport} lampiran per laporan`);

  const id = randomUUID();
  const key = `accounts/${report.account_id}/reports/${report.id}/${id}.${m.ext}`;
  const { rows } = await c.query(
    `INSERT INTO report_media (id, report_id, account_id, kind, content_type, size_bytes, duration_s, storage_key, uploaded_by)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
    [id, report.id, report.account_id, m.kind, contentType, input.size_bytes, input.duration_s ?? null, key, uploadedBy],
  );
  const uploadUrl = await presignPut(key, contentType, input.size_bytes);
  return {
    media: serializeMedia(rows[0]),
    upload: {
      method: 'PUT' as const,
      url: uploadUrl,
      // Header ini wajib persis sama saat PUT (ikut ditandatangani).
      headers: { 'Content-Type': contentType },
      expires_in: config.media.uploadUrlTtlS,
    },
  };
}

/** Langkah 2: klien memberi tahu upload selesai. Server memverifikasi objek (HEAD) sebelum menampilkannya. */
export async function completeMediaUpload(c: Db, report: any, mediaId: string, actor: { kind: 'reporter' | 'user' | 'server'; id?: string | null; name?: string | null }) {
  assertEnabled();
  if (!/^[0-9a-f-]{36}$/i.test(mediaId)) throw notFound('Media');
  const { rows } = await c.query(`SELECT * FROM report_media WHERE id = $1 AND report_id = $2 FOR UPDATE`, [mediaId, report.id]);
  const m = rows[0];
  if (!m) throw notFound('Media');
  if (m.status === 'ready') return serializeMedia(m);

  const head = await headObject(m.storage_key);
  if (!head) throw new ApiError(409, 'upload_missing', 'File belum diterima storage. Unggah ulang lewat URL upload, lalu coba lagi.');
  if (head.size !== Number(m.size_bytes)) throw new ApiError(422, 'upload_size_mismatch', 'Ukuran file di storage tidak sama dengan yang dideklarasikan');

  const { rows: upd } = await c.query(`UPDATE report_media SET status = 'ready', uploaded_at = now() WHERE id = $1 RETURNING *`, [m.id]);
  await c.query(
    `INSERT INTO report_events (report_id, account_id, actor_id, actor_kind, type, note) VALUES ($1,$2,$3,$4,'media',$5)`,
    [report.id, report.account_id, actor.kind === 'user' ? actor.id ?? null : null, actor.kind, `${KIND_LABEL[m.kind as MediaKind]} ditambahkan`],
  );
  const out = serializeMedia(upd[0]);
  publish(report.account_id, 'report.media_added', { report_id: report.id, media: out });
  return out;
}

export function serializeMedia(m: any) {
  return {
    id: m.id, kind: m.kind as MediaKind, content_type: m.content_type, size_bytes: Number(m.size_bytes),
    duration_s: m.duration_s, status: m.status, uploaded_by: m.uploaded_by, created_at: m.created_at, uploaded_at: m.uploaded_at,
  };
}

/** Media siap tampil + presigned GET (berlaku `viewUrlTtlS`). Kegagalan storage tidak menggagalkan detail laporan. */
export async function listReadyMedia(c: Db, reportId: string) {
  const { rows } = await c.query(`SELECT * FROM report_media WHERE report_id = $1 AND status = 'ready' ORDER BY created_at`, [reportId]);
  if (!rows.length || !mediaEnabled()) return [];
  return Promise.all(rows.map(async (m) => ({
    ...serializeMedia(m),
    url: await presignGet(m.storage_key, { filename: `${m.kind}-${m.id.slice(0, 8)}.${m.storage_key.split('.').pop()}` }).catch(() => null),
    url_expires_in: config.media.viewUrlTtlS,
  })));
}

export async function mediaCounts(c: Db, reportIds: string[]) {
  if (!reportIds.length) return new Map<string, Record<MediaKind, number>>();
  const { rows } = await c.query(
    `SELECT report_id, kind, count(*)::int AS n FROM report_media WHERE report_id = ANY($1) AND status = 'ready' GROUP BY 1, 2`, [reportIds]);
  const out = new Map<string, Record<MediaKind, number>>();
  for (const r of rows) {
    const cur = out.get(r.report_id) ?? { image: 0, video: 0, audio: 0 };
    cur[r.kind as MediaKind] = r.n;
    out.set(r.report_id, cur);
  }
  return out;
}
