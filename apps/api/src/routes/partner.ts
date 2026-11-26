import { Router, type Response } from 'express';
import { z } from 'zod';
import { PILLAR_LABELS, REPORT_STATUSES, type ReportStatus } from '@siagasos/shared';
import { q, withPartner, type Db } from '../db.js';
import { ApiError, notFound, parse } from '../lib/errors.js';
import { enforce } from '../lib/rateLimit.js';
import { audit } from '../lib/audit.js';
import { sha256 } from '../lib/crypto.js';
import { changeReport } from '../lib/reports.js';
import { listReadyMedia, mediaCounts } from '../lib/media.js';
import { isPartnerKey, isRegionCode, scopeWithin } from '../lib/partners.js';

/**
 * /partner/v1: API mitra lintas tenant (Polmas Digital), Authorization: Bearer ptk_live_...
 * Dipanggil hanya dari server mitra, tidak pernah dari browser. RLS partner_read (migrasi 016) membatasi ke laporan
 * live dari app berpilar Polmas, di dalam cakupan wilayah: header X-Partner-Scope (kode wilayah satuan pengguna),
 * yang harus berada di dalam partners.max_scope. Tanpa header = max_scope (NULL = nasional).
 * Header opsional X-Partner-Actor (petugas) dan X-Partner-Unit (satuan) masuk audit dan timeline.
 */
export const partnerRouter = Router();

interface PartnerCtx { partnerId: string; partnerName: string; keyId: string; scope: string; actor: string | null; unit: string | null }
const ctxOf = (res: Response) => res.locals.partner as PartnerCtx;
const header = (v: unknown, max = 120) => (typeof v === 'string' && v.trim() ? v.trim().slice(0, max) : null);

partnerRouter.use(async (req, res, next) => {
  const m = /^Bearer (\S+)$/.exec(req.get('authorization') ?? '');
  if (!m || !isPartnerKey(m[1]!)) throw new ApiError(401, 'invalid_api_key', 'Kunci mitra tidak valid atau sudah dicabut');
  const row = (await q(
    `SELECT k.id AS key_id, p.id, p.name, p.max_scope FROM partner_keys k JOIN partners p ON p.id = k.partner_id
     WHERE k.key_hash = $1 AND k.revoked_at IS NULL AND p.disabled_at IS NULL`, [sha256(m[1]!)])).rows[0];
  if (!row) throw new ApiError(401, 'invalid_api_key', 'Kunci mitra tidak valid atau sudah dicabut');
  await enforce(`ptk:${row.key_id}`, 600, 60);
  const want = header(req.get('x-partner-scope'), 20);
  if (want && !isRegionCode(want)) throw new ApiError(422, 'invalid_scope', 'X-Partner-Scope harus kode wilayah, mis. 32.71.01');
  const scope = want ?? row.max_scope ?? '';
  if (!scopeWithin(scope, row.max_scope)) throw new ApiError(403, 'scope_out_of_range', 'Cakupan wilayah di luar izin mitra');
  q(`UPDATE partner_keys SET last_used_at = now() WHERE id = $1 AND (last_used_at IS NULL OR last_used_at < now() - interval '1 minute')`, [row.key_id]).catch(() => {});
  res.locals.partner = {
    partnerId: row.id, partnerName: row.name, keyId: row.key_id, scope,
    actor: header(req.get('x-partner-actor')), unit: header(req.get('x-partner-unit')),
  } satisfies PartnerCtx;
  next();
});

const SELECT = `
  SELECT r.*, a.name AS app_name, a.polmas_source, wk.nama AS kecamatan_name, wl.nama AS kelurahan_name
  FROM reports r JOIN apps a ON a.id = r.app_id
  LEFT JOIN wilayah wk ON wk.kode = r.kecamatan_code
  LEFT JOIN wilayah wl ON wl.kode = r.kelurahan_code`;

/** Data yang dibagikan ke mitra (INTEGRASI_POLMAS §3d): tanpa reporter_ref, device, metadata, IP. */
function partnerReport(r: any, media?: Record<string, number>) {
  return {
    id: r.id,
    kind: r.kind ?? 'sos',
    app_id: r.app_id,
    app_name: r.app_name,
    pillar: r.polmas_source,
    pillar_label: (PILLAR_LABELS as Record<string, string>)[r.polmas_source] ?? null,
    mode: r.mode,
    category: r.category,
    status: r.status,
    status_message: r.status_message,
    message: r.message,
    complaint: r.complaint_details ?? null,
    location: r.lat == null ? null : { lat: r.lat, lng: r.lng, accuracy_m: r.accuracy_m },
    address: r.source_alamat ?? null,
    kecamatan: r.kecamatan_code ? { code: r.kecamatan_code, name: r.kecamatan_name } : null,
    kelurahan: r.kelurahan_code ? { code: r.kelurahan_code, name: r.kelurahan_name } : null,
    reporter: { name: r.reporter_name, phone: r.reporter_phone },
    created_at: r.created_at,
    acknowledged_at: r.acknowledged_at,
    resolved_at: r.resolved_at,
    updated_at: r.updated_at,
    ...(media ? { media_count: { image: media.image ?? 0, video: media.video ?? 0, audio: media.audio ?? 0 } } : {}),
  };
}

const csv = <T extends z.ZodTypeAny>(item: T) =>
  z.union([z.string().transform((s) => s.split(',').filter(Boolean)), z.array(z.string())]).pipe(z.array(item));
const listSchema = z.object({
  status: csv(z.enum(REPORT_STATUSES)).optional(),
  kind: z.enum(['sos', 'pengaduan']).optional(),
  /** Sinkron bertahap: hanya laporan yang berubah sejak waktu ini (updated_at). */
  since: z.string().datetime({ offset: true }).optional(),
  /** Paginasi: laporan yang dibuat sebelum waktu ini (next_before dari halaman sebelumnya). */
  before: z.string().datetime({ offset: true }).optional(),
  limit: z.coerce.number().int().min(1).max(200).default(50),
});

partnerRouter.get('/reports', async (req, res) => {
  const p = ctxOf(res);
  const f = parse(listSchema, req.query);
  const where: string[] = [];
  const params: unknown[] = [];
  const add = (sql: string, v: unknown) => { params.push(v); where.push(sql.replace('?', `$${params.length}`)); };
  if (f.status?.length) add('r.status = ANY(?)', f.status);
  if (f.kind) add('r.kind = ?', f.kind);
  if (f.since) add('r.updated_at >= ?', f.since);
  if (f.before) add('r.created_at < ?', f.before);
  params.push(f.limit + 1);
  const out = await withPartner(p.partnerId, p.scope, async (c) => {
    const { rows } = await c.query(
      `${SELECT} ${where.length ? 'WHERE ' + where.join(' AND ') : ''} ORDER BY r.created_at DESC, r.id DESC LIMIT $${params.length}`, params);
    const page = rows.slice(0, f.limit);
    const counts = await mediaCounts(c, page.map((r) => r.id));
    return { page, more: rows.length > f.limit, counts };
  });
  res.json({
    scope: p.scope || null,
    data: out.page.map((r) => partnerReport(r, out.counts.get(r.id) ?? {})),
    next_before: out.more ? new Date(out.page[out.page.length - 1].created_at).toISOString() : null,
  });
});

async function loadVisible(c: Db, id: string) {
  if (!/^[0-9a-f-]{36}$/i.test(id)) throw notFound('Laporan');
  const r = (await c.query(`${SELECT} WHERE r.id = $1`, [id])).rows[0];
  if (!r) throw notFound('Laporan');
  return r;
}

async function detail(c: Db, r: any) {
  // Satu koneksi transaksi: query berurutan, bukan Promise.all.
  const media = await listReadyMedia(c, r.id);
  const timeline = await c.query(`SELECT type, actor_kind, from_status, to_status, note, created_at FROM report_events WHERE report_id = $1 ORDER BY created_at`, [r.id]);
  const track = await c.query(`SELECT lat, lng, accuracy_m, recorded_at FROM report_locations WHERE report_id = $1 ORDER BY recorded_at DESC LIMIT 50`, [r.id]);
  const counts = { image: 0, video: 0, audio: 0 } as Record<string, number>;
  for (const m of media) counts[m.kind] = (counts[m.kind] ?? 0) + 1;
  return { ...partnerReport(r, counts), media, timeline: timeline.rows, track: track.rows };
}

partnerRouter.get('/reports/:id', async (req, res) => {
  const p = ctxOf(res);
  const out = await withPartner(p.partnerId, p.scope, async (c) => {
    const r = await loadVisible(c, String(req.params.id));
    return { r, body: await detail(c, r) };
  });
  // Setiap baca detail (identitas pelapor + media) tercatat: mitra, petugas, satuan.
  await audit({ accountId: out.r.account_id, actorKind: 'partner', action: 'report.read', targetType: 'report', targetId: out.r.id,
    detail: { partner_id: p.partnerId, key_id: p.keyId, actor: p.actor, unit: p.unit, scope: p.scope || null }, ip: req.ip });
  res.json(out.body);
});

const ACTIONS = ['acknowledge', 'forward_110', 'dispatch', 'resolve', 'false_alarm', 'note'] as const;
type Action = (typeof ACTIONS)[number];
const ACTION_STATUS: Record<Action, ReportStatus | undefined> = {
  acknowledge: 'acknowledged', forward_110: 'in_progress', dispatch: 'in_progress', resolve: 'resolved', false_alarm: 'false_alarm', note: undefined,
};
const ACTION_TITLE: Record<Action, string> = {
  acknowledge: 'Laporan diterima', forward_110: 'Diteruskan ke Call Center 110', dispatch: 'Petugas menuju lokasi',
  resolve: 'Laporan ditangani dan ditutup', false_alarm: 'Ditandai laporan palsu', note: 'Catatan',
};
const actionSchema = z.object({
  action: z.enum(ACTIONS),
  note: z.string().trim().max(1500).optional(),
  /** Unit yang dikirim, mis. "R2-07" (dispatch). */
  unit: z.string().trim().max(60).optional(),
}).superRefine((b, ctx) => {
  if (b.action === 'note' && !b.note) ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['note'], message: 'Catatan wajib diisi' });
});

/** Teks status di SDK pelapor, mis. "Polsek Bogor Tengah menuju lokasi." */
function statusMessage(a: Action, unit: string, dispatched?: string): string | null {
  switch (a) {
    case 'acknowledge': return `${unit} menerima laporan Anda.`;
    case 'dispatch': return `${unit} menuju lokasi${dispatched ? ` (unit ${dispatched})` : ''}.`;
    case 'forward_110': return `${unit} meneruskan laporan Anda ke Call Center 110.`;
    default: return null;
  }
}

/**
 * Tindakan petugas mitra. Laporan harus terlihat dalam cakupan; perubahan berjalan di konteks tenant pemilik laporan
 * lewat changeReport (timeline actor_kind=partner, realtime portal, webhook klien, status di SDK).
 */
partnerRouter.post('/reports/:id/actions', async (req, res) => {
  const p = ctxOf(res);
  const b = parse(actionSchema, req.body);
  await enforce(`ptk-act:${p.keyId}`, 120, 60);
  const unit = p.unit ?? p.partnerName;
  const who = [unit, p.actor].filter(Boolean).join(' · ');
  const out = await withPartner(p.partnerId, p.scope, async (c, asTenant) => {
    const r = await loadVisible(c, String(req.params.id));
    await asTenant(r.account_id);
    const target = ACTION_STATUS[b.action];
    const extra = [b.unit && `unit ${b.unit}`, b.note].filter(Boolean).join(' — ');
    const note = `${who}: ${ACTION_TITLE[b.action]}${b.action !== 'note' && extra ? ` — ${extra}` : b.action === 'note' ? ` — ${b.note}` : ''}`;
    await changeReport(c, r.id, { status: target && target !== r.status ? target : undefined, note }, { kind: 'partner', name: who });
    const msg = statusMessage(b.action, unit, b.unit);
    if (msg) await c.query(`UPDATE reports SET status_message = $2 WHERE id = $1`, [r.id, msg]);
    await audit({ accountId: r.account_id, actorKind: 'partner', action: `report.${b.action}`, targetType: 'report', targetId: r.id,
      detail: { partner_id: p.partnerId, key_id: p.keyId, actor: p.actor, unit: p.unit, unit_dispatched: b.unit ?? null }, ip: req.ip }, c);
    return detail(c, await loadVisible(c, r.id));
  });
  res.status(201).json(out);
});
