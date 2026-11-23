import { Router } from 'express';
import { z } from 'zod';
import { KEY_MODES, PLATFORMS, toWhatsAppNumber, type KeyMode } from '@siagasos/shared';
import { pool, q, withTenant, type Db } from '../../db.js';
import { ApiError, forbidden, notFound, parse } from '../../lib/errors.js';
import { generateKey } from '../../lib/keys.js';
import { audit } from '../../lib/audit.js';
import { invalidateKeyCache } from '../../middleware/keyAuth.js';
import { requireRole, requireUser, type PortalUser } from '../../middleware/portalAuth.js';

export const appsRouter = Router();
appsRouter.use(requireUser);

const origin = z
  .string()
  .transform((s) => s.trim().replace(/\/+$/, '').toLowerCase())
  .refine((s) => s === '*' || /^https:\/\/[a-z0-9.-]+(:\d+)?$/.test(s) || /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/.test(s), {
    message: 'Origin harus https://domain (http hanya untuk localhost); "*" hanya berlaku untuk kunci test',
  });
const bundleId = z.string().regex(/^[a-zA-Z][a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)+$/, 'Bundle id tidak valid, mis. com.klien.app');

const appSchema = z.object({
  name: z.string().min(2).max(80),
  allowed_origins: z.array(origin).max(20).default([]),
  allowed_bundle_ids: z.array(bundleId).max(20).default([]),
  webhook_url: z.string().url().startsWith('https://', 'webhook_url wajib https').nullable().optional(),
  auto_create_sources: z.boolean().optional(),
  sdk_config: z
    .object({
      categories: z.array(z.string().min(1).max(40)).max(12).optional(),
      complaint_categories: z.array(z.string().min(1).max(40)).max(12).optional(),
      button_text: z.string().max(20).optional(),
      hold_seconds: z.number().int().min(1).max(10).optional(),
      recipient_text: z.string().max(200).optional(),
      fallback_phone: z.string().max(20).optional(),
      live_location_interval_s: z.number().int().min(5).max(120).optional(),
    })
    .optional(),
  /** Hari penyimpanan laporan live setelah ditutup; null = tanpa batas. */
  retention_days: z.number().int().min(30).max(3650).nullable().optional(),
});

const canManage = requireRole('owner', 'admin');

async function loadApp(u: PortalUser, rawId: unknown) {
  const id = String(rawId);
  if (!/^[0-9a-f-]{36}$/i.test(id)) throw notFound('App');
  const { rows } = await q(`SELECT * FROM apps WHERE id = $1 AND account_id = $2`, [id, u.accountId]);
  if (!rows[0]) throw notFound('App');
  return rows[0];
}

function serializeApp(a: any, keys: any[] = []) {
  return {
    id: a.id, name: a.name, allowed_origins: a.allowed_origins, allowed_bundle_ids: a.allowed_bundle_ids,
    webhook_url: a.webhook_url, auto_create_sources: a.auto_create_sources, sdk_config: a.sdk_config, retention_days: a.retention_days ?? null,
    disabled: a.disabled_at != null, disabled_reason: a.disabled_reason, created_at: a.created_at,
    keys: keys.map(serializeKey),
  };
}

function serializeKey(k: any) {
  return {
    id: k.id, kind: k.kind, mode: k.mode, prefix: k.prefix,
    // publishable key boleh disalin kapan saja; secret hanya prefix
    key: k.kind === 'publishable' ? k.plain_key : undefined,
    revoked_at: k.revoked_at, expires_at: k.expires_at, last_used_at: k.last_used_at, created_at: k.created_at,
    active: !k.revoked_at && (!k.expires_at || new Date(k.expires_at) > new Date()),
  };
}

async function insertKey(c: Db | typeof pool, appId: string, kind: 'publishable' | 'secret', mode: KeyMode) {
  const g = generateKey(kind, mode);
  const { rows } = await c.query(
    `INSERT INTO api_keys (app_id, kind, mode, prefix, key_hash, plain_key) VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
    [appId, kind, mode, g.prefix, g.hash, kind === 'publishable' ? g.key : null],
  );
  return { ...serializeKey(rows[0]), key: g.key };
}

async function createPair(c: Db | typeof pool, appId: string, mode: KeyMode) {
  return { publishable: await insertKey(c, appId, 'publishable', mode), secret: await insertKey(c, appId, 'secret', mode) };
}

function assertModeAllowed(u: PortalUser, mode: KeyMode) {
  if (mode === 'live' && u.limited) {
    throw forbidden('account_not_approved', 'Kunci live tersedia setelah perusahaan disetujui. Selama review gunakan kunci test.');
  }
}

appsRouter.get('/', async (req, res) => {
  const u = req.user!;
  const apps = await q(`SELECT * FROM apps WHERE account_id = $1 ORDER BY created_at`, [u.accountId]);
  const keys = await q(`SELECT k.* FROM api_keys k JOIN apps a ON a.id = k.app_id WHERE a.account_id = $1 ORDER BY k.created_at`, [u.accountId]);
  res.json({ data: apps.rows.map((a) => serializeApp(a, keys.rows.filter((k) => k.app_id === a.id))) });
});

appsRouter.post('/', canManage, async (req, res) => {
  const u = req.user!;
  const body = parse(appSchema, req.body);
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const { rows } = await c.query(
      `INSERT INTO apps (account_id, name, allowed_origins, allowed_bundle_ids, webhook_url, auto_create_sources, sdk_config, retention_days)
       VALUES ($1,$2,$3,$4,$5, coalesce($6, true), $7, $8) RETURNING *`,
      [u.accountId, body.name, body.allowed_origins, body.allowed_bundle_ids, body.webhook_url ?? null, body.auto_create_sources ?? null, JSON.stringify(body.sdk_config ?? {}),
        body.retention_days ?? null],
    );
    const app = rows[0];
    const keys: Record<string, unknown> = { test: await createPair(c, app.id, 'test') };
    if (!u.limited) keys.live = await createPair(c, app.id, 'live');
    await c.query('COMMIT');
    res.status(201).json({
      app: serializeApp(app),
      keys,
      notice: 'Simpan secret key sekarang. Secret key hanya ditampilkan sekali.',
    });
  } catch (e) {
    await c.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    c.release();
  }
});

appsRouter.get('/:id', async (req, res) => {
  const app = await loadApp(req.user!, req.params.id!);
  const keys = await q(`SELECT * FROM api_keys WHERE app_id = $1 ORDER BY created_at`, [app.id]);
  res.json(serializeApp(app, keys.rows));
});

appsRouter.patch('/:id', canManage, async (req, res) => {
  const app = await loadApp(req.user!, req.params.id!);
  const body = parse(appSchema.partial(), req.body);
  const { rows } = await q(
    `UPDATE apps SET name = coalesce($2, name), allowed_origins = coalesce($3, allowed_origins),
       allowed_bundle_ids = coalesce($4, allowed_bundle_ids),
       webhook_url = CASE WHEN $5 THEN $6 ELSE webhook_url END,
       auto_create_sources = coalesce($7, auto_create_sources),
       sdk_config = CASE WHEN $8::jsonb IS NULL THEN sdk_config ELSE $8::jsonb END,
       retention_days = CASE WHEN $9 THEN $10::int ELSE retention_days END
     WHERE id = $1 RETURNING *`,
    [app.id, body.name ?? null, body.allowed_origins ?? null, body.allowed_bundle_ids ?? null,
      'webhook_url' in body, body.webhook_url ?? null, body.auto_create_sources ?? null,
      body.sdk_config ? JSON.stringify(body.sdk_config) : null, 'retention_days' in body, body.retention_days ?? null],
  );
  invalidateKeyCache();
  res.json(serializeApp(rows[0]));
});

// ---------------------------------------------------------------- kunci
appsRouter.get('/:id/keys', async (req, res) => {
  const app = await loadApp(req.user!, req.params.id!);
  const keys = await q(`SELECT * FROM api_keys WHERE app_id = $1 ORDER BY created_at`, [app.id]);
  res.json({ data: keys.rows.map(serializeKey) });
});

appsRouter.post('/:id/keys', canManage, async (req, res) => {
  const u = req.user!;
  const app = await loadApp(u, req.params.id!);
  const { mode } = parse(z.object({ mode: z.enum(KEY_MODES) }), req.body);
  assertModeAllowed(u, mode);
  const pair = await createPair(pool, app.id, mode);
  await audit({ accountId: u.accountId, actorKind: 'user', actorId: u.id, action: 'key.created', targetType: 'app', targetId: app.id, detail: { mode } });
  res.status(201).json({ ...pair, notice: 'Simpan secret key sekarang. Secret key hanya ditampilkan sekali.' });
});

appsRouter.post('/:id/keys/:keyId/rotate', canManage, async (req, res) => {
  const u = req.user!;
  const app = await loadApp(u, req.params.id!);
  const { grace_hours } = parse(z.object({ grace_hours: z.number().int().min(0).max(72).default(0) }), req.body ?? {});
  const old = (await q(`SELECT * FROM api_keys WHERE id = $1 AND app_id = $2 AND revoked_at IS NULL`, [req.params.keyId, app.id])).rows[0];
  if (!old) throw notFound('Kunci aktif');
  assertModeAllowed(u, old.mode);
  const fresh = await insertKey(pool, app.id, old.kind, old.mode);
  if (grace_hours === 0) await q(`UPDATE api_keys SET revoked_at = now() WHERE id = $1`, [old.id]);
  else await q(`UPDATE api_keys SET expires_at = now() + make_interval(hours => $2) WHERE id = $1`, [old.id, grace_hours]);
  invalidateKeyCache();
  await audit({ accountId: u.accountId, actorKind: 'user', actorId: u.id, action: 'key.rotated', targetType: 'api_key', targetId: old.id, detail: { new_key_id: fresh.id, grace_hours } });
  res.status(201).json({ key: fresh, old_key: { id: old.id, ...(grace_hours ? { expires_in_hours: grace_hours } : { revoked: true }) } });
});

appsRouter.post('/:id/keys/:keyId/revoke', canManage, async (req, res) => {
  const u = req.user!;
  const app = await loadApp(u, req.params.id!);
  const { rows } = await q(`UPDATE api_keys SET revoked_at = coalesce(revoked_at, now()) WHERE id = $1 AND app_id = $2 RETURNING *`, [req.params.keyId, app.id]);
  if (!rows[0]) throw notFound('Kunci');
  invalidateKeyCache();
  await audit({ accountId: u.accountId, actorKind: 'user', actorId: u.id, action: 'key.revoked', targetType: 'api_key', targetId: rows[0].id });
  res.json(serializeKey(rows[0]));
});

// ---------------------------------------------------------------- source
const sourceSchema = z.object({
  source_key: z.string().min(1).max(64).regex(/^[a-z0-9][a-z0-9._-]*$/, 'huruf kecil, angka, titik, minus, garis bawah'),
  label: z.string().max(120).optional(),
  platform: z.enum(PLATFORMS).optional(),
});

appsRouter.get('/:id/sources', async (req, res) => {
  const u = req.user!;
  const app = await loadApp(u, req.params.id!);
  const { rows } = await withTenant(u.accountId, (c) =>
    c.query(
      `SELECT s.*, (SELECT count(*)::int FROM reports r WHERE r.source_id = s.id) AS report_count
       FROM sources s WHERE s.app_id = $1 ORDER BY s.created_at`,
      [app.id],
    ),
  );
  res.json({ data: rows });
});

appsRouter.post('/:id/sources', canManage, async (req, res) => {
  const u = req.user!;
  const app = await loadApp(u, req.params.id!);
  const body = parse(sourceSchema, req.body);
  const { rows } = await withTenant(u.accountId, (c) =>
    c.query(`INSERT INTO sources (app_id, account_id, source_key, label, platform) VALUES ($1,$2,$3,$4,$5) RETURNING *`,
      [app.id, u.accountId, body.source_key, body.label ?? null, body.platform ?? null]),
  ).catch((e) => {
    if (e.code === '23505') throw new ApiError(409, 'source_exists', 'source_key sudah dipakai di app ini');
    throw e;
  });
  res.status(201).json(rows[0]);
});

appsRouter.patch('/:id/sources/:sourceId', canManage, async (req, res) => {
  const u = req.user!;
  const app = await loadApp(u, req.params.id!);
  const body = parse(sourceSchema.omit({ source_key: true }), req.body);
  const { rows } = await withTenant(u.accountId, (c) =>
    c.query(`UPDATE sources SET label = coalesce($3, label), platform = coalesce($4, platform) WHERE id = $1 AND app_id = $2 RETURNING *`,
      [req.params.sourceId, app.id, body.label ?? null, body.platform ?? null]),
  );
  if (!rows[0]) throw notFound('Source');
  res.json(rows[0]);
});

// ---------------------------------------------------------------- penerima SOS (WhatsApp)
const recipientSchema = z.object({
  name: z.string().trim().min(1).max(80),
  phone: z.string().max(32).transform((p, ctx) => {
    const n = toWhatsAppNumber(p);
    if (!n) ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Nomor WhatsApp tidak valid (contoh 0812xxxxxxx)' });
    return n ?? p;
  }),
  /** null / tidak diisi = semua source app. */
  source_id: z.string().uuid().nullable().optional(),
  active: z.boolean().optional(),
});

const RECIPIENT_COLS = `r.id, r.name, r.phone, r.source_id, r.active, r.created_at, s.source_key, s.label AS source_label`;

appsRouter.get('/:id/recipients', async (req, res) => {
  const u = req.user!;
  const app = await loadApp(u, req.params.id!);
  const { rows } = await withTenant(u.accountId, (c) =>
    c.query(`SELECT ${RECIPIENT_COLS} FROM sos_recipients r LEFT JOIN sources s ON s.id = r.source_id
             WHERE r.app_id = $1 ORDER BY r.source_id NULLS FIRST, r.name`, [app.id]),
  );
  res.json({ data: rows });
});

appsRouter.post('/:id/recipients', canManage, async (req, res) => {
  const u = req.user!;
  const app = await loadApp(u, req.params.id!);
  const body = parse(recipientSchema, req.body);
  const row = await withTenant(u.accountId, async (c) => {
    if (body.source_id) {
      const s = await c.query(`SELECT 1 FROM sources WHERE id = $1 AND app_id = $2`, [body.source_id, app.id]);
      if (!s.rows[0]) throw notFound('Source');
    }
    const ins = await c.query(
      `INSERT INTO sos_recipients (account_id, app_id, source_id, name, phone, active) VALUES ($1,$2,$3,$4,$5,coalesce($6,true)) RETURNING id`,
      [u.accountId, app.id, body.source_id ?? null, body.name, body.phone, body.active ?? null],
    );
    const { rows } = await c.query(`SELECT ${RECIPIENT_COLS} FROM sos_recipients r LEFT JOIN sources s ON s.id = r.source_id WHERE r.id = $1`, [ins.rows[0].id]);
    return rows[0];
  }).catch((e) => {
    if (e.code === '23505') throw new ApiError(409, 'recipient_exists', 'Nomor ini sudah menjadi penerima untuk cakupan yang sama');
    throw e;
  });
  await audit({ accountId: u.accountId, actorKind: 'user', actorId: u.id, action: 'recipient.created', targetType: 'app', targetId: app.id, detail: { recipient_id: row.id } });
  res.status(201).json(row);
});

appsRouter.patch('/:id/recipients/:recipientId', canManage, async (req, res) => {
  const u = req.user!;
  const app = await loadApp(u, req.params.id!);
  const body = parse(recipientSchema.partial(), req.body);
  const row = await withTenant(u.accountId, async (c) => {
    const upd = await c.query(
      `UPDATE sos_recipients SET name = coalesce($3, name), phone = coalesce($4, phone), active = coalesce($5, active)
       WHERE id = $1 AND app_id = $2 RETURNING id`,
      [req.params.recipientId, app.id, body.name ?? null, body.phone ?? null, body.active ?? null],
    );
    if (!upd.rows[0]) throw notFound('Penerima');
    const { rows } = await c.query(`SELECT ${RECIPIENT_COLS} FROM sos_recipients r LEFT JOIN sources s ON s.id = r.source_id WHERE r.id = $1`, [upd.rows[0].id]);
    return rows[0];
  }).catch((e) => {
    if (e.code === '23505') throw new ApiError(409, 'recipient_exists', 'Nomor ini sudah menjadi penerima untuk cakupan yang sama');
    throw e;
  });
  res.json(row);
});

appsRouter.delete('/:id/recipients/:recipientId', canManage, async (req, res) => {
  const u = req.user!;
  const app = await loadApp(u, req.params.id!);
  const { rowCount } = await withTenant(u.accountId, (c) =>
    c.query(`DELETE FROM sos_recipients WHERE id = $1 AND app_id = $2`, [req.params.recipientId, app.id]),
  );
  if (!rowCount) throw notFound('Penerima');
  await audit({ accountId: u.accountId, actorKind: 'user', actorId: u.id, action: 'recipient.deleted', targetType: 'app', targetId: app.id, detail: { recipient_id: req.params.recipientId } });
  res.status(204).end();
});

// ---------------------------------------------------------------- log webhook
appsRouter.get('/:id/webhooks', async (req, res) => {
  const u = req.user!;
  const app = await loadApp(u, req.params.id!);
  const { rows } = await withTenant(u.accountId, (c) =>
    c.query(
      `SELECT id, report_id, event, status_code, attempts, last_error, next_retry_at, delivered_at, created_at
       FROM webhook_deliveries WHERE app_id = $1 ORDER BY created_at DESC LIMIT 100`,
      [app.id],
    ),
  );
  res.json({ data: rows, webhook_secret_hint: 'Verifikasi header X-SOS-Signature: t=<unix>,v1=hex(HMAC_SHA256(webhook_secret, "<t>.<raw body>"))' });
});

appsRouter.get('/:id/webhook-secret', canManage, async (req, res) => {
  const app = await loadApp(req.user!, req.params.id!);
  res.json({ webhook_secret: app.webhook_secret });
});
