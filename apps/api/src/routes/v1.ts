import { Router } from 'express';
import { listReadyMedia } from '../lib/media.js';
import { updateReportSchema } from '@siagasos/shared';
import { q, withTenant } from '../db.js';
import { ApiError, notFound, parse } from '../lib/errors.js';
import { enforce } from '../lib/rateLimit.js';
import { secretKeyAuth } from '../middleware/keyAuth.js';
import { changeReport, fullReport, loadReport } from '../lib/reports.js';
import { listQuerySchema, listReports } from '../lib/reportQuery.js';
import { deliver } from '../lib/webhooks.js';
import { audit } from '../lib/audit.js';

/** /v1 — API server-ke-server untuk backend klien, Authorization: Bearer sk_... */
export const serverRouter = Router();
serverRouter.use(secretKeyAuth);
serverRouter.use(async (req, _res, next) => {
  await enforce(`sk:${req.key!.keyId}`, 300, 60);
  next();
});

serverRouter.get('/reports', async (req, res) => {
  const k = req.key!;
  const f = parse(listQuerySchema, req.query);
  // Kunci test hanya melihat data test; kunci live hanya data live.
  res.json(await withTenant(k.accountId, (c) => listReports(c, { ...f, mode: k.mode, app_id: undefined }, { appId: k.appId })));
});

serverRouter.get('/reports/:id', async (req, res) => {
  const k = req.key!;
  const r = await withTenant(k.accountId, (c) => loadReport(c, req.params.id!, k.appId));
  if (r.mode !== k.mode) throw notFound('Laporan');
  const media = await withTenant(k.accountId, (c) => listReadyMedia(c, r.id));
  await audit({ accountId: k.accountId, actorKind: 'server', action: 'report.read', targetType: 'report', targetId: r.id, detail: { key_id: k.keyId } });
  res.json({ ...fullReport(r), media });
});

serverRouter.patch('/reports/:id', async (req, res) => {
  const k = req.key!;
  const body = parse(updateReportSchema, req.body);
  const r = await withTenant(k.accountId, async (c) => {
    const cur = await loadReport(c, req.params.id!, k.appId);
    if (cur.mode !== k.mode) throw notFound('Laporan');
    return changeReport(c, cur.id, body, { kind: 'server', name: 'server' }, k.appId);
  });
  res.json(fullReport(r));
});

serverRouter.post('/webhooks/test', async (req, res) => {
  const k = req.key!;
  const { rows } = await q(`SELECT webhook_url, webhook_secret FROM apps WHERE id = $1`, [k.appId]);
  if (!rows[0]?.webhook_url) throw new ApiError(422, 'webhook_not_configured', 'webhook_url app belum diisi di portal');
  const payload = { id: 'evt_test', type: 'webhook.test', livemode: k.mode === 'live', created: new Date().toISOString(), data: {} };
  try {
    const status = await deliver(rows[0].webhook_url, rows[0].webhook_secret, payload);
    res.json({ delivered: status >= 200 && status < 300, status_code: status });
  } catch (e) {
    res.json({ delivered: false, error: (e as Error).message });
  }
});
