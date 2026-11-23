import { Router } from 'express';
import cors from 'cors';
import { createReportSchema, locationUpdateSchema, DEFAULT_CATEGORIES, DEFAULT_COMPLAINT_CATEGORIES, TERMINAL_STATUSES, type SdkConfig } from '@siagasos/shared';
import { withTenant } from '../db.js';
import { ApiError, parse } from '../lib/errors.js';
import { enforce, hit } from '../lib/rateLimit.js';
import { publishableKeyAuth } from '../middleware/keyAuth.js';
import { changeReport, loadReport, onReportCreated, publicReport } from '../lib/reports.js';
import { publish } from '../lib/realtime.js';
import { dispatchSosWhatsApp } from '../lib/sosRecipients.js';
import { config } from '../config.js';
import { dispatchSosPush } from '../lib/responders.js';
import { contactsRouter, responderRouter } from './responder.js';
import { completeMediaUpload, createMediaSchema, createMediaUpload, listReadyMedia } from '../lib/media.js';

/** /v1/sdk — dipanggil @siagasos/js dan SDK native dengan publishable key. */
export const sdkRouter = Router();

// Preflight boleh dari mana saja; Origin sebenarnya dicek di publishableKeyAuth terhadap allowed_origins.
sdkRouter.use(cors({ origin: true, credentials: false, allowedHeaders: ['Content-Type', 'X-SOS-Key', 'X-SOS-Bundle', 'X-SOS-Responder', 'Idempotency-Key'], maxAge: 600 }));
sdkRouter.use(publishableKeyAuth);
sdkRouter.use(async (req, _res, next) => {
  await enforce(`key:${req.key!.keyId}`, 120, 60);
  await enforce(`ip:${req.ip}`, 60, 60);
  next();
});

// Nomor Darurat pelapor (sinkron dari perangkat) + login & kerja satpam (OTP WA, push FCM).
sdkRouter.use('/contacts', contactsRouter);
sdkRouter.use('/responder', responderRouter);

sdkRouter.get('/config', (req, res) => {
  const k = req.key!;
  const c = k.sdkConfig as Partial<SdkConfig>;
  const body: SdkConfig = {
    app_name: k.appName,
    mode: k.mode,
    categories: c.categories?.length ? c.categories : [...DEFAULT_CATEGORIES],
    complaint_categories: c.complaint_categories?.length ? c.complaint_categories : [...DEFAULT_COMPLAINT_CATEGORIES],
    button_text: c.button_text ?? 'SOS',
    hold_seconds: c.hold_seconds ?? 3,
    recipient_text: c.recipient_text ?? `Laporan dikirim ke tim keamanan ${k.appName}, bukan ke polisi/110.`,
    fallback_phone: c.fallback_phone ?? '110',
    live_location_interval_s: c.live_location_interval_s ?? 15,
  };
  res.set('Cache-Control', 'private, max-age=300').json(body);
});

const IDEM_RE = /^[A-Za-z0-9_.:-]{8,128}$/;

sdkRouter.post('/reports', async (req, res) => {
  const k = req.key!;
  const idem = req.get('idempotency-key') ?? '';
  if (!IDEM_RE.test(idem)) throw new ApiError(400, 'idempotency_key_required', 'Header Idempotency-Key wajib (8–128 karakter)');
  const body = parse(createReportSchema, req.body);

  const result = await withTenant(k.accountId, async (c) => {
    // Retry dari antrian offline: kembalikan laporan yang sama, tanpa kena rate limit lagi.
    const dup = await c.query(`SELECT * FROM reports WHERE app_id = $1 AND idempotency_key = $2`, [k.appId, idem]);
    if (dup.rows[0]) return { report: dup.rows[0], replay: true };

    if (body.reporter?.ref) {
      // Kuota terpisah: pengaduan tidak boleh menghabiskan jatah SOS pengguna yang sama.
      if (body.kind === 'pengaduan') await enforce(`complaint:${k.appId}:${body.reporter.ref}`, 5, 3600, 'reporter_rate_limited');
      else await enforce(`reporter:${k.appId}:${body.reporter.ref}`, 3, 600, 'reporter_rate_limited');
    }
    if (k.mode === 'test') {
      const day = new Date().toISOString().slice(0, 10);
      const r = await hit(`test:${k.accountId}:${day}`, config.testReportsPerDay, 86400);
      if (!r.ok) throw new ApiError(429, 'test_quota_exceeded', `Laporan test dibatasi ${config.testReportsPerDay} per hari per akun`);
    }

    let sourceId: string | null = null;
    if (body.source_key) {
      const s = await c.query(`SELECT id FROM sources WHERE app_id = $1 AND source_key = $2`, [k.appId, body.source_key]);
      sourceId = s.rows[0]?.id ?? null;
      if (!sourceId) {
        if (!k.autoCreateSources) throw new ApiError(422, 'unknown_source', `source_key "${body.source_key}" belum terdaftar`);
        const ins = await c.query(
          `INSERT INTO sources (app_id, account_id, source_key, label, platform, alamat) VALUES ($1,$2,$3,$4,$5,$6)
           ON CONFLICT (app_id, source_key) DO UPDATE SET source_key = EXCLUDED.source_key RETURNING id`,
          [k.appId, k.accountId, body.source_key, body.source_label ?? null, body.device?.platform ?? null, body.source_alamat ?? null],
        );
        sourceId = ins.rows[0].id;
      } else if (body.source_label || body.source_alamat) {
        // Nama tampilan & alamat dari app (mis. nama kios, wilayah tenant) mengikuti perubahan di sisi klien.
        await c.query(
          `UPDATE sources SET label = coalesce($2, label), alamat = coalesce($3, alamat)
           WHERE id = $1 AND (label IS DISTINCT FROM coalesce($2, label) OR alamat IS DISTINCT FROM coalesce($3, alamat))`,
          [sourceId, body.source_label ?? null, body.source_alamat ?? null],
        );
      }
    }

    const ins = await c.query(
      `INSERT INTO reports (app_id, account_id, source_id, mode, category, reporter_ref, reporter_name, reporter_phone,
         message, lat, lng, accuracy_m, device, metadata, ip, idempotency_key, client_created_at, kind, emergency_contacts,
         complaint_details)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,$19,$20)
       ON CONFLICT (app_id, idempotency_key) DO NOTHING RETURNING *`,
      [k.appId, k.accountId, sourceId, k.mode, body.category, body.reporter?.ref ?? null, body.reporter?.name ?? null,
        body.reporter?.phone ?? null, body.message ?? null, body.location?.lat ?? null, body.location?.lng ?? null,
        body.location?.accuracy_m ?? null, body.device ? JSON.stringify(body.device) : null,
        body.metadata ? JSON.stringify(body.metadata) : null, req.ip ?? null, idem, body.client_created_at ?? null, body.kind,
        body.kind === 'sos' && body.emergency_contacts?.length ? JSON.stringify(body.emergency_contacts) : null,
        body.kind === 'pengaduan' && body.complaint ? JSON.stringify(body.complaint) : null],
    );
    if (!ins.rows[0]) {
      // balapan dua retry bersamaan
      const again = await c.query(`SELECT * FROM reports WHERE app_id = $1 AND idempotency_key = $2`, [k.appId, idem]);
      return { report: again.rows[0], replay: true };
    }
    const report = { ...ins.rows[0], source_key: body.source_key ?? null };
    await c.query(
      `INSERT INTO report_events (report_id, account_id, actor_kind, type, to_status) VALUES ($1,$2,'reporter','created','open')`,
      [report.id, k.accountId],
    );
    if (body.location) {
      await c.query(`INSERT INTO report_locations (report_id, account_id, lat, lng, accuracy_m) VALUES ($1,$2,$3,$4,$5)`,
        [report.id, k.accountId, body.location.lat, body.location.lng, body.location.accuracy_m ?? null]);
    }
    await onReportCreated(c, report, k.appName);
    return { report, replay: false };
  });

  res.status(result.replay ? 200 : 201).set('Idempotent-Replayed', String(result.replay)).json(publicReport(result.report));
  // Setelah commit & respons: WA ke Penerima SOS + kontak darurat. Tidak ditunggu, tidak memblokir jalur SOS.
  if (!result.replay) {
    void dispatchSosWhatsApp(result.report, k.appName);
    // Push alarm + sirene ke HP satpam yang login dengan nomor di kontak darurat laporan ini.
    void dispatchSosPush(result.report, k.appName);
  }
});

sdkRouter.get('/reports/:id', async (req, res) => {
  const k = req.key!;
  const r = await withTenant(k.accountId, (c) => loadReport(c, req.params.id!, k.appId));
  res.set('Cache-Control', 'no-store').json(publicReport(r));
});

/**
 * Detail untuk "Riwayat laporan" di perangkat pelapor: uraian, lokasi, timeline, dan media (URL baca 15 menit).
 * Tanpa data pribadi lain: nomor HP/device/IP pelapor tidak dikirim, hasil WhatsApp hanya diringkas (nomor penerima
 * SOS tidak dibuka ke pelapor). Hanya pemegang id laporan (UUID acak dari respons POST) yang bisa membacanya.
 */
sdkRouter.get('/reports/:id/detail', async (req, res) => {
  const k = req.key!;
  const out = await withTenant(k.accountId, async (c) => {
    const r = await loadReport(c, req.params.id!, k.appId);
    const ev = await c.query(
      `SELECT e.type, e.actor_kind, e.to_status, e.note, e.created_at, u.full_name AS actor_name
       FROM report_events e LEFT JOIN users u ON u.id = e.actor_id
       WHERE e.report_id = $1 ORDER BY e.created_at, e.id`,
      [r.id],
    );
    const timeline: { type: string; actor: string; to_status: string | null; note: string | null; created_at: string }[] = [];
    let wa: { sent: number; failed: number; at: string } | null = null;
    for (const e of ev.rows) {
      if (e.type === 'whatsapp') {
        wa ??= { sent: 0, failed: 0, at: e.created_at };
        if (/: terkirim$/.test(e.note ?? '')) wa.sent++;
        else if (/: gagal/.test(e.note ?? '')) wa.failed++;
        continue;
      }
      timeline.push({
        type: e.type,
        actor: e.actor_kind === 'reporter' ? 'Anda' : e.actor_kind === 'responder' ? 'Satpam' : e.actor_kind === 'user' ? (e.actor_name ?? 'Petugas') : e.actor_kind === 'server' ? 'Petugas' : 'Sistem',
        to_status: e.to_status,
        note: e.note,
        created_at: e.created_at,
      });
    }
    if (wa && (wa.sent || wa.failed)) {
      timeline.push({
        type: 'whatsapp', actor: 'Sistem', to_status: null, created_at: wa.at,
        note: `WhatsApp terkirim ke ${wa.sent} penerima${wa.failed ? `, ${wa.failed} gagal` : ''}`,
      });
      timeline.sort((a, b) => new Date(a.created_at).getTime() - new Date(b.created_at).getTime());
    }
    const media = (await listReadyMedia(c, r.id)).map((m) => ({
      id: m.id, kind: m.kind, content_type: m.content_type, duration_s: m.duration_s, uploaded_by: m.uploaded_by, created_at: m.created_at, url: m.url,
    }));
    return {
      ...publicReport(r),
      message: r.message ?? null,
      location: r.lat == null ? null : { lat: r.lat, lng: r.lng, accuracy_m: r.accuracy_m },
      timeline,
      media,
    };
  });
  res.set('Cache-Control', 'no-store').json(out);
});

sdkRouter.post('/reports/:id/locations', async (req, res) => {
  const k = req.key!;
  const body = parse(locationUpdateSchema, req.body);
  await enforce(`loc:${req.params.id}`, 20, 60); // ~ tiap 3 detik maksimum
  const out = await withTenant(k.accountId, async (c) => {
    const r = await loadReport(c, req.params.id!, k.appId);
    // Pengaduan tidak memakai lokasi live; SDK berhenti mengirim saat accepted:false.
    if (TERMINAL_STATUSES.includes(r.status) || r.kind === 'pengaduan') return { r, accepted: false };
    await c.query(`INSERT INTO report_locations (report_id, account_id, lat, lng, accuracy_m, recorded_at) VALUES ($1,$2,$3,$4,$5, coalesce($6::timestamptz, now()))`,
      [r.id, k.accountId, body.lat, body.lng, body.accuracy_m ?? null, body.recorded_at ?? null]);
    await c.query(`UPDATE reports SET lat = $2, lng = $3, accuracy_m = $4, updated_at = now() WHERE id = $1`,
      [r.id, body.lat, body.lng, body.accuracy_m ?? null]);
    return { r, accepted: true };
  });
  if (out.accepted) publish(k.accountId, 'report.location_updated', { report_id: out.r.id, location: body });
  // 200 + accepted:false memberi tahu SDK untuk berhenti mengirim lokasi
  res.json({ accepted: out.accepted, status: out.r.status });
});

sdkRouter.post('/reports/:id/cancel', async (req, res) => {
  const k = req.key!;
  const reason = typeof req.body?.reason === 'string' ? req.body.reason.slice(0, 500) : undefined;
  const r = await withTenant(k.accountId, async (c) => {
    const cur = await loadReport(c, req.params.id!, k.appId);
    if (cur.status === 'cancelled') return cur;
    if (cur.status !== 'open') throw new ApiError(409, 'cannot_cancel', 'Laporan sudah ditangani petugas dan tidak bisa dibatalkan dari aplikasi');
    return changeReport(c, cur.id, { status: 'cancelled', note: reason ?? 'Dibatalkan pengguna' }, { kind: 'reporter', name: cur.reporter_name }, k.appId);
  });
  res.json(publicReport(r));
});

// Catatan pelapor setelah laporan terkirim (mis. keterangan rekaman TKP). Masuk timeline sebagai event `note`
// (actor reporter) dan realtime `report.note_added`; tidak mengubah status, tidak memicu webhook.
sdkRouter.post('/reports/:id/notes', async (req, res) => {
  const k = req.key!;
  const note = typeof req.body?.note === 'string' ? req.body.note.trim() : '';
  if (!note || note.length > 1000) throw new ApiError(422, 'invalid_note', 'Catatan wajib diisi, maksimal 1000 karakter');
  await enforce(`note:${req.params.id}`, 10, 600);
  const r = await withTenant(k.accountId, async (c) => {
    const cur = await loadReport(c, req.params.id!, k.appId);
    if (TERMINAL_STATUSES.includes(cur.status)) throw new ApiError(409, 'report_closed', 'Laporan sudah ditutup, catatan tidak bisa ditambahkan');
    return changeReport(c, cur.id, { note }, { kind: 'reporter', name: cur.reporter_name }, k.appId);
  });
  res.status(201).json(publicReport(r));
});

// Lampiran foto/video/suara. Langkah 1: minta presigned PUT; perangkat mengunggah langsung ke object storage.
sdkRouter.post('/reports/:id/media', async (req, res) => {
  const k = req.key!;
  const body = parse(createMediaSchema, req.body);
  await enforce(`media:${req.params.id}`, 20, 600);
  const out = await withTenant(k.accountId, async (c) => createMediaUpload(c, await loadReport(c, req.params.id!, k.appId), body, 'reporter'));
  res.status(201).json(out);
});

// Langkah 2: konfirmasi upload selesai → server cek objek, lalu media tampil realtime di dashboard.
sdkRouter.post('/reports/:id/media/:mediaId/complete', async (req, res) => {
  const k = req.key!;
  const out = await withTenant(k.accountId, async (c) => {
    const r = await loadReport(c, req.params.id!, k.appId);
    return completeMediaUpload(c, r, String(req.params.mediaId), { kind: 'reporter', name: r.reporter_name });
  });
  res.json(out);
});
