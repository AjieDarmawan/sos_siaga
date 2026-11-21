import { Router } from 'express';
import { updateReportSchema } from '@siagasos/shared';
import { withTenant } from '../../db.js';
import { notFound, parse } from '../../lib/errors.js';
import { audit } from '../../lib/audit.js';
import { attachClient } from '../../lib/realtime.js';
import { changeReport, fullReport, loadReport } from '../../lib/reports.js';
import { listQuerySchema, listReports } from '../../lib/reportQuery.js';
import { requireRole, requireUser } from '../../middleware/portalAuth.js';
import { completeMediaUpload, createMediaSchema, createMediaUpload, listReadyMedia, mediaCounts } from '../../lib/media.js';

export const reportsRouter = Router();
reportsRouter.use(requireUser);

/** Sesi terbatas (belum approved) hanya melihat laporan test. */
const modeScope = (limited: boolean) => (limited ? ({ forceMode: 'test' } as const) : {});

reportsRouter.get('/', async (req, res) => {
  const u = req.user!;
  const f = parse(listQuerySchema, req.query);
  res.json(await withTenant(u.accountId, async (c) => {
    const page = await listReports(c, f, modeScope(u.limited));
    const counts = await mediaCounts(c, page.data.map((r) => r.id));
    return { ...page, data: page.data.map((r) => ({ ...r, media_count: counts.get(r.id) ?? null })) };
  }));
});

// Ekspor CSV (F-15). Batas 10.000 baris per ekspor; persempit filter tanggal untuk data lebih banyak.
reportsRouter.get('/export.csv', requireRole('owner', 'admin'), async (req, res) => {
  const u = req.user!;
  const f = parse(listQuerySchema, { ...req.query, limit: 500 });
  const cols = ['id', 'created_at', 'mode', 'status', 'category', 'source_key', 'message', 'reporter_ref', 'reporter_name',
    'reporter_phone', 'lat', 'lng', 'accuracy_m', 'acknowledged_at', 'resolved_at'];
  const esc = (v: unknown) => {
    const s = v == null ? '' : String(v);
    const safe = /^[=+\-@\t\r]/.test(s) ? `'${s}` : s; // cegah CSV/formula injection
    return /[",\n]/.test(safe) ? `"${safe.replace(/"/g, '""')}"` : safe;
  };
  res.setHeader('Content-Type', 'text/csv; charset=utf-8');
  res.setHeader('Content-Disposition', `attachment; filename="siagasos-reports-${new Date().toISOString().slice(0, 10)}.csv"`);
  res.write('﻿' + cols.join(',') + '\n');
  let cursor: string | undefined;
  let total = 0;
  do {
    const page = await withTenant(u.accountId, (c) => listReports(c, { ...f, cursor }, modeScope(u.limited)));
    for (const r of page.data) {
      const row: Record<string, unknown> = { ...r, lat: r.location?.lat, lng: r.location?.lng, accuracy_m: r.location?.accuracy_m,
        reporter_ref: r.reporter.ref, reporter_name: r.reporter.name, reporter_phone: r.reporter.phone };
      res.write(cols.map((c) => esc(row[c])).join(',') + '\n');
    }
    total += page.data.length;
    cursor = page.next_cursor ?? undefined;
  } while (cursor && total < 10_000);
  await audit({ accountId: u.accountId, actorKind: 'user', actorId: u.id, action: 'report.exported', detail: { rows: total, filter: req.query } });
  res.end();
});

// SSE realtime untuk dashboard: report.created, report.status_changed, report.location_updated, ...
reportsRouter.get('/stream', (req, res) => {
  attachClient(req.user!.accountId, res);
});

reportsRouter.get('/:id', async (req, res) => {
  const u = req.user!;
  const out = await withTenant(u.accountId, async (c) => {
    const r = await loadReport(c, req.params.id!);
    if (u.limited && r.mode !== 'test') throw notFound('Laporan');
    const events = await c.query(
      `SELECT e.id, e.type, e.actor_kind, e.from_status, e.to_status, e.note, e.created_at, u.full_name AS actor_name
       FROM report_events e LEFT JOIN users u ON u.id = e.actor_id WHERE e.report_id = $1 ORDER BY e.created_at, e.id`,
      [r.id],
    );
    const locations = await c.query(
      `SELECT lat, lng, accuracy_m, recorded_at FROM report_locations WHERE report_id = $1 ORDER BY recorded_at`,
      [r.id],
    );
    return { ...fullReport(r), timeline: events.rows, locations: locations.rows, media: await listReadyMedia(c, r.id) };
  });
  // audit log setiap akses detail laporan (UU PDP)
  await audit({ accountId: u.accountId, actorKind: 'user', actorId: u.id, action: 'report.viewed', targetType: 'report', targetId: out.id, ip: req.ip });
  res.json(out);
});

reportsRouter.patch('/:id', async (req, res) => {
  const u = req.user!;
  const body = parse(updateReportSchema, req.body);
  const r = await withTenant(u.accountId, async (c) => {
    const cur = await loadReport(c, req.params.id!);
    if (u.limited && cur.mode !== 'test') throw notFound('Laporan');
    return changeReport(c, cur.id, body, { kind: 'user', id: u.id, name: u.fullName });
  });
  res.json(fullReport(r));
});

// Petugas juga bisa melampirkan foto/video/suara (mis. dokumentasi di lokasi). Alurnya sama dengan SDK.
reportsRouter.post('/:id/media', async (req, res) => {
  const u = req.user!;
  const body = parse(createMediaSchema, req.body);
  const out = await withTenant(u.accountId, async (c) => {
    const r = await loadReport(c, req.params.id!);
    if (u.limited && r.mode !== 'test') throw notFound('Laporan');
    return createMediaUpload(c, r, body, 'user');
  });
  res.status(201).json(out);
});

reportsRouter.post('/:id/media/:mediaId/complete', async (req, res) => {
  const u = req.user!;
  const out = await withTenant(u.accountId, async (c) => {
    const r = await loadReport(c, req.params.id!);
    if (u.limited && r.mode !== 'test') throw notFound('Laporan');
    return completeMediaUpload(c, r, String(req.params.mediaId), { kind: 'user', id: u.id, name: u.fullName });
  });
  res.json(out);
});
