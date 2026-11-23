import { Router } from 'express';
import { z } from 'zod';
import { toWhatsAppNumber } from '@siagasos/shared';
import { withTenant } from '../db.js';
import { config } from '../config.js';
import { ApiError, parse } from '../lib/errors.js';
import { enforce } from '../lib/rateLimit.js';
import { changeReport } from '../lib/reports.js';
import { sendOtpWhatsApp } from '../lib/whatsapp.js';
import { isTestNumber } from '../lib/sosRecipients.js';
import {
  consumeOtp, createOtp, createSession, listForResponder, loadForResponder, registeredName, replaceContacts, responderAuth,
  responderReport, OTP_TTL_MIN,
} from '../lib/responders.js';

const phoneSchema = z.string().max(32).transform((p, ctx) => {
  const n = toWhatsAppNumber(p);
  if (!n) ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Nomor WhatsApp tidak valid (contoh 0812xxxxxxx)' });
  return n ?? p;
});

/** Maks. kontak tersimpan per pelapor (aktif + nonaktif), sama dengan SDK. */
const MAX_STORED = 10;
const MAX_ACTIVE = 5;

const contactsSchema = z.object({
  reporter: z.object({ ref: z.string().min(1).max(128), name: z.string().max(120).optional() }),
  source_key: z.string().min(1).max(64).optional(),
  contacts: z.array(z.object({
    name: z.string().trim().min(1).max(80),
    role: z.string().trim().max(40).nullish(),
    phone: phoneSchema,
    active: z.boolean().default(true),
  })).max(MAX_STORED),
}).superRefine((b, ctx) => {
  if (b.contacts.filter((c) => c.active).length > MAX_ACTIVE) ctx.addIssue({ code: z.ZodIssueCode.custom, message: `Maksimal ${MAX_ACTIVE} nomor aktif` });
  if (new Set(b.contacts.map((c) => c.phone)).size !== b.contacts.length) ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Nomor ganda' });
});

/**
 * Nomor Darurat pelapor (dipasang di sdkRouter, sudah lewat publishableKeyAuth). SDK memanggil PUT setiap daftar
 * berubah dan GET saat perangkat baru belum punya salinan lokal. Kepercayaan sama dengan reporter.ref di laporan:
 * ditentukan app klien yang memegang publishable key.
 */
export const contactsRouter = Router();

contactsRouter.get('/', async (req, res) => {
  const k = req.key!;
  const ref = String(req.query.reporter_ref ?? '');
  if (!ref || ref.length > 128) throw new ApiError(422, 'reporter_ref_required', 'reporter_ref wajib');
  const rows = await withTenant(k.accountId, (c) => c.query(
    `SELECT name, role, phone, active FROM emergency_contacts WHERE app_id = $1 AND reporter_ref = $2 ORDER BY active DESC, name`,
    [k.appId, ref],
  ).then((r) => r.rows));
  res.set('Cache-Control', 'no-store').json({ contacts: rows });
});

contactsRouter.put('/', async (req, res) => {
  const k = req.key!;
  const body = parse(contactsSchema, req.body);
  await enforce(`contacts:${k.appId}:${body.reporter.ref}`, 30, 600);
  await withTenant(k.accountId, async (c) => {
    let sourceId: string | null = null;
    if (body.source_key) {
      sourceId = (await c.query(`SELECT id FROM sources WHERE app_id = $1 AND source_key = $2`, [k.appId, body.source_key])).rows[0]?.id ?? null;
    }
    await replaceContacts(c, k, body.reporter, sourceId, body.contacts);
  });
  res.json({ ok: true, count: body.contacts.length });
});

/** Login & kerja satpam di app klien (dipasang di sdkRouter, sudah lewat publishableKeyAuth). */
export const responderRouter = Router();

responderRouter.post('/otp', async (req, res) => {
  const k = req.key!;
  const { phone } = parse(z.object({ phone: phoneSchema }), req.body);
  await enforce(`rsp-otp-ip:${req.ip}`, 10, 3600);
  await enforce(`rsp-otp:${k.appId}:${phone}`, 3, 600, 'otp_rate_limited');
  const out = await withTenant(k.accountId, async (c) => {
    const name = await registeredName(c, k.appId, phone);
    if (!name) {
      throw new ApiError(404, 'responder_not_registered', 'Nomor ini belum terdaftar di Nomor Darurat kasir mana pun. Minta kasir menambahkannya dulu.');
    }
    return { name, code: await createOtp(c, k, phone) };
  });
  // Nomor uji 0800: tidak pernah dikirimi WA (sama dengan WA SOS).
  const wa = isTestNumber(phone) ? { status: 'stub' as const } : await sendOtpWhatsApp(phone, out.code);
  // Tanpa WA (dev / kunci test): kode dikembalikan supaya alur bisa diuji. Kunci live di production wajib WA.
  const exposeCode = k.mode === 'test' || !config.isProd;
  if (wa.status !== 'sent' && !exposeCode) {
    throw new ApiError(503, 'otp_unavailable', 'Kode tidak bisa dikirim ke WhatsApp saat ini. Coba lagi sebentar.');
  }
  res.json({
    sent: wa.status === 'sent',
    expires_in_s: OTP_TTL_MIN * 60,
    ...(wa.status !== 'sent' && exposeCode ? { dev_code: out.code } : {}),
  });
});

const platformSchema = z.enum(['android', 'ios', 'web', 'other']).optional();
const verifySchema = z.object({
  phone: phoneSchema,
  code: z.string().regex(/^\d{6}$/, 'Kode 6 digit'),
  device: z.object({
    platform: platformSchema,
    fcm_token: z.string().min(10).max(4096).nullish(),
  }).default({}),
});

responderRouter.post('/verify', async (req, res) => {
  const k = req.key!;
  const body = parse(verifySchema, req.body);
  await enforce(`rsp-verify-ip:${req.ip}`, 30, 3600);
  const out = await withTenant(k.accountId, async (c) => {
    await consumeOtp(c, k.appId, body.phone, body.code);
    const name = await registeredName(c, k.appId, body.phone);
    if (!name) throw new ApiError(404, 'responder_not_registered', 'Nomor ini sudah tidak terdaftar di Nomor Darurat');
    return { name, token: await createSession(c, k, body.phone, body.device) };
  });
  res.status(201).json({ token: out.token, responder: { phone: body.phone, name: out.name } });
});

const loginSchema = z.object({ phone: phoneSchema, device: verifySchema.shape.device });

/**
 * Login langsung tanpa OTP (keputusan produk POS: satpam cukup memasukkan nomornya). Syaratnya hanya nomor ada di
 * Nomor Darurat app ini. Konsekuensinya siapa pun yang tahu nomor itu bisa masuk sebagai satpam, jadi dibatasi
 * rate limit per IP & nomor. /otp + /verify tetap tersedia bila nanti ingin diperketat lagi.
 */
responderRouter.post('/login', async (req, res) => {
  const k = req.key!;
  const body = parse(loginSchema, req.body);
  await enforce(`rsp-login-ip:${req.ip}`, 20, 3600);
  await enforce(`rsp-login:${k.appId}:${body.phone}`, 10, 600);
  const out = await withTenant(k.accountId, async (c) => {
    const name = await registeredName(c, k.appId, body.phone);
    if (!name) {
      throw new ApiError(404, 'responder_not_registered', 'Nomor ini belum terdaftar di Nomor Darurat kasir mana pun. Minta kasir menambahkannya dulu.');
    }
    return { name, token: await createSession(c, k, body.phone, body.device) };
  });
  res.status(201).json({ token: out.token, responder: { phone: body.phone, name: out.name } });
});

responderRouter.use(responderAuth);

/** Profil + daftar kasir/outlet yang mencantumkan nomor ini. */
responderRouter.get('/me', async (req, res) => {
  const k = req.key!;
  const me = req.responder!;
  const rows = await withTenant(k.accountId, (c) => c.query(
    `SELECT e.reporter_name, coalesce(s.label, s.source_key) AS source_label, e.active
     FROM emergency_contacts e LEFT JOIN sources s ON s.id = e.source_id
     WHERE e.app_id = $1 AND e.phone = $2 ORDER BY e.active DESC, e.reporter_name`,
    [k.appId, me.phone],
  ).then((r) => r.rows));
  res.set('Cache-Control', 'no-store').json({ phone: me.phone, name: me.name, app_name: k.appName, guarding: rows });
});

responderRouter.put('/device', async (req, res) => {
  const k = req.key!;
  const body = parse(z.object({ fcm_token: z.string().min(10).max(4096).nullable(), platform: platformSchema }), req.body);
  await withTenant(k.accountId, async (c) => {
    if (body.fcm_token) {
      await c.query(`UPDATE responder_sessions SET revoked_at = now() WHERE app_id = $1 AND fcm_token = $2 AND id <> $3 AND revoked_at IS NULL`,
        [k.appId, body.fcm_token, req.responder!.sessionId]);
    }
    await c.query(`UPDATE responder_sessions SET fcm_token = $2, platform = coalesce($3, platform) WHERE id = $1`,
      [req.responder!.sessionId, body.fcm_token, body.platform ?? null]);
  });
  res.json({ ok: true });
});

responderRouter.post('/logout', async (req, res) => {
  const k = req.key!;
  await withTenant(k.accountId, (c) => c.query(`UPDATE responder_sessions SET revoked_at = now() WHERE id = $1`, [req.responder!.sessionId]));
  res.status(204).end();
});

responderRouter.get('/reports', async (req, res) => {
  const k = req.key!;
  const rows = await withTenant(k.accountId, (c) => listForResponder(c, k.appId, req.responder!.phone));
  res.set('Cache-Control', 'no-store').json({ data: rows.map(responderReport) });
});

responderRouter.get('/reports/:id', async (req, res) => {
  const k = req.key!;
  const r = await withTenant(k.accountId, (c) => loadForResponder(c, k.appId, req.responder!.phone, String(req.params.id)));
  res.set('Cache-Control', 'no-store').json(responderReport(r));
});

const actionSchema = z.object({
  status: z.enum(['acknowledged', 'in_progress', 'resolved', 'false_alarm']),
  note: z.string().trim().max(500).optional(),
});

/** Satpam menanggapi: "Saya menuju lokasi" (acknowledged/in_progress) atau menutup (resolved/false_alarm). */
responderRouter.post('/reports/:id/status', async (req, res) => {
  const k = req.key!;
  const me = req.responder!;
  const body = parse(actionSchema, req.body);
  await enforce(`rsp-status:${me.sessionId}`, 30, 600);
  const r = await withTenant(k.accountId, async (c) => {
    const cur = await loadForResponder(c, k.appId, me.phone, String(req.params.id));
    if (cur.status === body.status) return cur;
    await changeReport(c, cur.id, { status: body.status, note: body.note ?? `Ditanggapi ${me.name}` }, { kind: 'responder', name: me.name }, k.appId);
    return loadForResponder(c, k.appId, me.phone, cur.id);
  });
  res.json(responderReport(r));
});
