import { Router, type NextFunction, type Request, type Response } from 'express';
import { randomUUID } from 'node:crypto';
import { z } from 'zod';
import { withPlatform, withTenant, type Db } from '../db.js';
import { ApiError, notFound, parse } from '../lib/errors.js';
import { enforce } from '../lib/rateLimit.js';
import { hashPassword, verifyPassword } from '../lib/auth.js';
import { childRegions, isParentCode, reverseRegion } from '../lib/regions.js';
import { changeReport, onReportCreated } from '../lib/reports.js';
import { listReadyMedia } from '../lib/media.js';
import { mediaEnabled, presignGet } from '../lib/objectStorage.js';
import { config } from '../config.js';
import {
  PK_BASE, PK_COLUMNS, PK_FROM, PK_LAST_RESPONSE, ROLE_LABEL, SESSION_TTL_H, SLA_MIN, SOURCE_LABEL, STATUS_SQL,
  audit, canRespondAny, canRespondTo, contactRows, hashToken, isOfficer, mineWhere, newSessionToken, normPhone, scopeOf,
  serializePk, syncContactRoles, visibleWhere,
  type PkArea, type PkContext, type PkRole,
} from '../lib/polmas.js';

/**
 * /v1/pk — API aplikasi Polmas Keamanan: penerima Nomor Darurat (docs/POLMAS_KEAMANAN.md).
 * Auth: Bearer pks_… dari POST /v1/pk/auth/login. Semua data lintas tenant dibaca dengan withPlatform(), lalu
 * dibatasi per nomor (Nomor Darurat), kecamatan & peran di query. Penerima menanggapi laporan yang memanggil nomornya.
 */
export const polmasRouter = Router();

const pkOf = (res: Response) => res.locals.pk as PkContext;

const phoneSchema = z.string().max(32).transform((p, ctx) => {
  const n = normPhone(p);
  if (!n) ctx.addIssue({ code: z.ZodIssueCode.custom, message: 'Nomor telepon tidak valid' });
  return n ?? '';
});

// ---------------------------------------------------------------- auth (tanpa token)

const NOT_REGISTERED = 'Nomor ini belum terdaftar. Minta pemilik toko / warga yang Anda jaga menambahkan nomor ini di menu Nomor Darurat aplikasinya.';

/**
 * Langkah 1 login. Nomor terdaftar bila punya akun (pk_users) atau ada di Nomor Darurat aktif app mana pun
 * (docs/POLMAS_KEAMANAN.md). has_password=false → aplikasi menampilkan "Buat password" (login pertama).
 */
polmasRouter.post('/auth/check', async (req, res) => {
  const { phone } = parse(z.object({ phone: phoneSchema }), req.body);
  await enforce(`pk-check-ip:${req.ip}`, 30, 600);
  const out = await withPlatform(async (c) => {
    const user = (await c.query(`SELECT name, disabled_at FROM pk_users WHERE phone = $1`, [phone])).rows[0];
    if (user?.disabled_at) return null;
    const contacts = await contactRows(c, phone);
    if (!user && !contacts.length) return null;
    return {
      has_password: !!user,
      name: user?.name ?? contacts[0]!.name,
      // Dari mana nomor ini dikenal, mis. "Satpam · Kios Melati (commerceOS POS)", supaya pengguna yakin nomornya benar.
      contacts: contacts.slice(0, 5).map((ct) => ({ role: ct.role, place: ct.source_label ?? ct.reporter_name, app: ct.app_name })),
    };
  });
  if (!out) throw new ApiError(404, 'phone_not_registered', NOT_REGISTERED);
  res.json({ registered: true, phone, ...out });
});

const deviceSchema = z.object({ platform: z.enum(['android', 'ios', 'web', 'other']).optional() }).default({});
const loginSchema = z.object({ phone: phoneSchema, password: z.string().min(1).max(200), device: deviceSchema });

async function openSession(c: Db, userId: string, platform: string | null) {
  const role = (await c.query(
    `SELECT id FROM pk_user_roles WHERE user_id = $1
     ORDER BY (role = 'bhabinkamtibmas') DESC, (role = 'penerima') DESC, created_at LIMIT 1`, [userId])).rows[0];
  if (!role) throw new ApiError(403, 'no_role', 'Nomor ini sudah tidak ada di Nomor Darurat mana pun. Hubungi pemilik toko / pengurus wilayah.');
  const token = newSessionToken();
  const s = await c.query(
    `INSERT INTO pk_sessions (user_id, role_id, token_hash, platform, expires_at)
     VALUES ($1,$2,$3,$4, now() + make_interval(hours => $5)) RETURNING id, expires_at`,
    [userId, role.id, hashToken(token), platform, SESSION_TTL_H]);
  return { token, sessionId: s.rows[0].id as string, expires_at: s.rows[0].expires_at };
}

const setupSchema = z.object({
  phone: phoneSchema,
  name: z.string().trim().min(2).max(100).optional(),
  password: z.string().min(8, 'Password minimal 8 karakter').max(200),
  device: deviceSchema,
});

/**
 * Login pertama untuk nomor dari Nomor Darurat: membuat akun + password sendiri (tanpa OTP, PRD tanpa WA/SMS;
 * sejalan dengan login satpam). Hanya bila nomor belum punya akun. Dicatat di audit.
 */
polmasRouter.post('/auth/setup', async (req, res) => {
  const body = parse(setupSchema, req.body);
  await enforce(`pk-setup-ip:${req.ip}`, 10, 3600);
  await enforce(`pk-setup:${body.phone}`, 5, 3600);
  const hash = await hashPassword(body.password);
  const out = await withPlatform(async (c) => {
    if ((await c.query(`SELECT 1 FROM pk_users WHERE phone = $1`, [body.phone])).rowCount) {
      throw new ApiError(409, 'already_registered', 'Nomor ini sudah punya password. Silakan masuk.');
    }
    const contacts = await contactRows(c, body.phone);
    if (!contacts.length) throw new ApiError(404, 'phone_not_registered', NOT_REGISTERED);
    const user = (await c.query(
      `INSERT INTO pk_users (phone, name, password_hash, created_via, last_login_at) VALUES ($1,$2,$3,'contact',now()) RETURNING id`,
      [body.phone, body.name ?? contacts[0]!.name, hash])).rows[0];
    await syncContactRoles(c, user.id, body.phone);
    await audit(c, user.id, 'account_created', null, { via: 'emergency_contact', contacts: contacts.length }, req.ip);
    return openSession(c, user.id, body.device.platform ?? null);
  });
  const ctx = await loadContext(out.sessionId);
  res.status(201).json({ token: out.token, expires_at: out.expires_at, me: await mePayload(ctx!) });
});

polmasRouter.post('/auth/login', async (req, res) => {
  const body = parse(loginSchema, req.body);
  await enforce(`pk-login-ip:${req.ip}`, 30, 3600);
  await enforce(`pk-login:${body.phone}`, 10, 600);
  const user = await withPlatform((c) => c.query(`SELECT * FROM pk_users WHERE phone = $1`, [body.phone]).then((r) => r.rows[0]));
  if (!user || user.disabled_at) throw new ApiError(404, 'phone_not_registered', NOT_REGISTERED);
  if (user.locked_until && new Date(user.locked_until) > new Date()) {
    throw new ApiError(423, 'account_locked', 'Terlalu banyak percobaan. Coba lagi dalam 15 menit.');
  }
  const ok = await verifyPassword(body.password, user.password_hash);
  const out = await withPlatform(async (c) => {
    if (!ok) {
      await c.query(
        `UPDATE pk_users SET failed_logins = failed_logins + 1,
           locked_until = CASE WHEN failed_logins + 1 >= 5 THEN now() + interval '15 minutes' ELSE locked_until END
         WHERE id = $1`, [user.id]);
      await audit(c, user.id, 'login_failed', null, null, req.ip);
      return null;
    }
    // Peran mengikuti isian Nomor Darurat terbaru (kios baru menambahkan nomor ini, jabatan berubah, dihapus, …).
    await syncContactRoles(c, user.id, user.phone);
    const session = await openSession(c, user.id, body.device.platform ?? null);
    await c.query(`UPDATE pk_users SET failed_logins = 0, locked_until = NULL, last_login_at = now() WHERE id = $1`, [user.id]);
    await audit(c, user.id, 'login', null, { platform: body.device.platform ?? null }, req.ip);
    return session;
  });
  if (!out) throw new ApiError(401, 'invalid_password', 'Password salah. Periksa lagi lalu coba ulang.');
  const ctx = await loadContext(out.sessionId);
  res.status(201).json({ token: out.token, expires_at: out.expires_at, me: await mePayload(ctx!) });
});

// ---------------------------------------------------------------- middleware sesi

async function loadContext(sessionId: string): Promise<PkContext | null> {
  const r = await withPlatform((c) => c.query(
    `SELECT s.id AS session_id, u.id AS user_id, u.phone, u.name, u.is_demo, u.area, u.area_lat, u.area_lng,
            ro.id AS role_id, ro.role, ro.kecamatan_code, ro.kelurahan_code, ro.unit
     FROM pk_sessions s JOIN pk_users u ON u.id = s.user_id JOIN pk_user_roles ro ON ro.id = s.role_id
     WHERE s.id = $1 AND s.revoked_at IS NULL AND s.expires_at > now() AND u.disabled_at IS NULL`, [sessionId]));
  const x = r.rows[0];
  if (!x) return null;
  return {
    sessionId: x.session_id, userId: x.user_id, phone: x.phone, name: x.name, isDemo: x.is_demo,
    area: x.area, areaLat: x.area_lat, areaLng: x.area_lng,
    role: { id: x.role_id, role: x.role, kecamatan_code: x.kecamatan_code, kelurahan_code: x.kelurahan_code, unit: x.unit },
  };
}

async function requirePk(req: Request, res: Response, next: NextFunction) {
  const h = req.headers.authorization ?? '';
  const token = h.startsWith('Bearer pks_') ? h.slice(7) : '';
  if (!token) return next(new ApiError(401, 'unauthorized', 'Sesi tidak ada. Silakan masuk.'));
  const sid = await withPlatform((c) => c.query(
    `UPDATE pk_sessions SET last_seen_at = now() WHERE token_hash = $1 AND revoked_at IS NULL AND expires_at > now() RETURNING id`,
    [hashToken(token)]).then((r) => r.rows[0]?.id as string | undefined));
  const ctx = sid ? await loadContext(sid) : null;
  if (!ctx) return next(new ApiError(401, 'session_expired', 'Sesi berakhir. Silakan masuk lagi.'));
  res.locals.pk = ctx;
  next();
}

/**
 * Kondisi "laporan di wilayah/untuk saya" + parameter dasarnya ($1 nomor, $2 user, $3 kecamatan atau null).
 * Dipakai dashboard, daftar, peta, video, analisa: penerima tanpa kecamatan tetap melihat SOS yang memanggil nomornya.
 */
const scopeParams = (pk: PkContext): unknown[] => [pk.phone, pk.userId, scopeOf(pk)];
const SCOPE = visibleWhere({ phone: 1, user: 2, scope: 3 });

polmasRouter.use(requirePk);

// ---------------------------------------------------------------- profil, peran, wilayah

async function mePayload(pk: PkContext) {
  const { roles, scopeName, eco } = await withPlatform(async (c) => {
    const roles = (await c.query(
      `SELECT ro.id, ro.role, ro.unit, ro.kecamatan_code, wk.nama AS kecamatan_name, ro.kelurahan_code, wl.nama AS kelurahan_name
       FROM pk_user_roles ro LEFT JOIN wilayah wk ON wk.kode = ro.kecamatan_code LEFT JOIN wilayah wl ON wl.kode = ro.kelurahan_code
       WHERE ro.user_id = $1 ORDER BY (ro.role = 'bhabinkamtibmas') DESC, ro.created_at`, [pk.userId])).rows;
    const s = scopeOf(pk);
    const scopeName = s ? (await c.query(`SELECT nama FROM wilayah WHERE kode = $1`, [s])).rows[0]?.nama ?? null : null;
    // Ekosistem yang dilayani (Profil): app yang mencantumkan nomor ini di Nomor Darurat, plus untuk Bhabinkamtibmas
    // app Polmas yang punya laporan di kecamatannya 90 hari terakhir.
    const eco = (await c.query(
      `SELECT DISTINCT a.polmas_source AS source, a.name AS app_name FROM emergency_contacts e JOIN apps a ON a.id = e.app_id
       WHERE e.phone = $1 AND e.active AND a.disabled_at IS NULL AND a.polmas_source IS NOT NULL
       UNION
       SELECT DISTINCT a.polmas_source, a.name FROM reports r JOIN apps a ON a.id = r.app_id
       WHERE $2::boolean AND $3::text IS NOT NULL AND r.kecamatan_code = $3 AND r.mode = 'live' AND a.polmas_source IS NOT NULL
         AND a.disabled_at IS NULL AND r.created_at > now() - interval '90 days'`, [pk.phone, isOfficer(pk), s])).rows;
    return { roles, scopeName, eco };
  });
  const s = scopeOf(pk);
  return {
    user: { id: pk.userId, name: pk.name, phone: pk.phone, is_demo: pk.isDemo },
    role: { ...pk.role, label: ROLE_LABEL[pk.role.role] },
    roles: roles.map((r) => ({
      id: r.id, role: r.role, label: ROLE_LABEL[r.role as PkRole], unit: r.unit,
      kecamatan: r.kecamatan_code ? { code: r.kecamatan_code, name: r.kecamatan_name } : null,
      kelurahan: r.kelurahan_code ? { code: r.kelurahan_code, name: r.kelurahan_name } : null,
    })),
    area: pk.area,
    area_location: pk.areaLat == null ? null : { lat: pk.areaLat, lng: pk.areaLng },
    scope: s ? { code: s, name: scopeName } : null,
    ecosystems: eco.map((e) => ({ source: e.source, label: SOURCE_LABEL[e.source] ?? e.source, app_name: e.app_name })),
    needs_area: !pk.area?.district,
    can_respond: canRespondAny(pk),
    is_officer: isOfficer(pk),
  };
}

polmasRouter.get('/me', async (_req, res) => {
  res.set('Cache-Control', 'no-store').json(await mePayload(pkOf(res)));
});

/** Ubah nama tampilan (pensil di avatar Profil). Nomor tidak bisa diubah: itu identitas dari Nomor Darurat. */
polmasRouter.patch('/me', async (req, res) => {
  const pk = pkOf(res);
  const { name } = parse(z.object({ name: z.string().trim().min(2).max(100) }), req.body);
  await withPlatform(async (c) => {
    await c.query(`UPDATE pk_users SET name = $2 WHERE id = $1`, [pk.userId, name]);
    await audit(c, pk.userId, 'update_name', null, null, req.ip);
  });
  res.json(await mePayload((await loadContext(pk.sessionId))!));
});

const deviceBody = z.object({
  fcm_token: z.string().min(10).max(4096),
  platform: z.enum(['android', 'ios', 'web', 'other']).optional(),
  device_name: z.string().trim().max(80).optional(),
});

/** Daftarkan token FCM perangkat ini (dipanggil app setelah login & saat token berganti). Token pindah pemilik bila HP dipakai nomor lain. */
polmasRouter.post('/me/device', async (req, res) => {
  const pk = pkOf(res);
  const b = parse(deviceBody, req.body);
  await enforce(`pk-device:${pk.userId}`, 30, 3600);
  await withPlatform((c) => c.query(
    `INSERT INTO pk_devices (user_id, fcm_token, platform, device_name) VALUES ($1,$2,$3,$4)
     ON CONFLICT (fcm_token) DO UPDATE SET user_id = EXCLUDED.user_id, platform = EXCLUDED.platform,
       device_name = coalesce(EXCLUDED.device_name, pk_devices.device_name), updated_at = now()`,
    [pk.userId, b.fcm_token, b.platform ?? null, b.device_name || null]));
  res.status(204).end();
});

/**
 * Perangkat terdaftar (Profil). Token tidak dikirim balik; `token_tail` (6 karakter terakhir) cukup bagi app untuk
 * menandai "perangkat ini".
 */
polmasRouter.get('/me/devices', async (_req, res) => {
  const pk = pkOf(res);
  const rows = await withPlatform((c) => c.query(
    `SELECT id, platform, device_name, right(fcm_token, 6) AS token_tail, created_at, updated_at
     FROM pk_devices WHERE user_id = $1 ORDER BY updated_at DESC`, [pk.userId]).then((r) => r.rows));
  res.set('Cache-Control', 'no-store').json({ items: rows });
});

polmasRouter.post('/me/devices/:id/remove', async (req, res) => {
  const pk = pkOf(res);
  const id = String(req.params.id);
  if (!/^[0-9a-f-]{36}$/i.test(id)) throw notFound('Perangkat');
  const n = await withPlatform(async (c) => {
    const r = await c.query(`DELETE FROM pk_devices WHERE id = $1 AND user_id = $2`, [id, pk.userId]);
    if (r.rowCount) await audit(c, pk.userId, 'device_removed', null, { id }, req.ip);
    return r.rowCount;
  });
  if (!n) throw notFound('Perangkat');
  res.status(204).end();
});

/** Ubah kata sandi dari Profil. Sesi lain milik nomor ini ikut dicabut; sesi yang dipakai sekarang tetap. */
polmasRouter.post('/me/password', async (req, res) => {
  const pk = pkOf(res);
  const b = parse(z.object({
    current_password: z.string().min(1).max(200),
    new_password: z.string().min(8, 'Password minimal 8 karakter').max(200),
  }), req.body);
  await enforce(`pk-password:${pk.userId}`, 10, 3600);
  const user = await withPlatform((c) => c.query(`SELECT password_hash FROM pk_users WHERE id = $1`, [pk.userId]).then((r) => r.rows[0]));
  if (!(await verifyPassword(b.current_password, user.password_hash))) {
    throw new ApiError(401, 'invalid_password', 'Password lama salah.');
  }
  const hash = await hashPassword(b.new_password);
  await withPlatform(async (c) => {
    await c.query(`UPDATE pk_users SET password_hash = $2 WHERE id = $1`, [pk.userId, hash]);
    await c.query(`UPDATE pk_sessions SET revoked_at = now() WHERE user_id = $1 AND id <> $2 AND revoked_at IS NULL`, [pk.userId, pk.sessionId]);
    await audit(c, pk.userId, 'password_changed', null, null, req.ip);
  });
  res.status(204).end();
});

/**
 * Kinerja saya (kartu di Profil): laporan yang saya tanggapi dalam N hari, berapa yang saya selesaikan,
 * dan median waktu tanggapan pertama saya sejak laporan masuk.
 */
polmasRouter.get('/me/stats', async (req, res) => {
  const pk = pkOf(res);
  const { days } = parse(z.object({ days: z.coerce.number().int().min(1).max(365).default(30) }), req.query);
  const row = await withPlatform((c) => c.query(
    `WITH mine AS (
       SELECT x.report_id, min(x.created_at) AS first_at, bool_or(x.action = 'selesai') AS done
       FROM pk_responses x WHERE x.user_id = $1 AND x.created_at > now() - make_interval(days => $2) GROUP BY 1)
     SELECT count(*)::int AS handled, count(*) FILTER (WHERE m.done)::int AS resolved,
            round(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM m.first_at - r.created_at)))::int AS median_response_s
     FROM mine m JOIN reports r ON r.id = m.report_id`, [pk.userId, days]).then((r) => r.rows[0]));
  res.set('Cache-Control', 'no-store').json({
    days, handled: row.handled, resolved: row.resolved, median_response_s: row.median_response_s,
    pct_resolved: row.handled ? Math.round((row.resolved / row.handled) * 100) : null,
  });
});

/** Lepas token perangkat (logout / Lupakan perangkat): HP ini tidak lagi menerima SOS untuk nomor ini. */
polmasRouter.post('/me/device/remove', async (req, res) => {
  const pk = pkOf(res);
  const { fcm_token } = parse(deviceBody.pick({ fcm_token: true }), req.body);
  await withPlatform((c) => c.query(`DELETE FROM pk_devices WHERE user_id = $1 AND fcm_token = $2`, [pk.userId, fcm_token]));
  res.status(204).end();
});

polmasRouter.post('/me/role', async (req, res) => {
  const pk = pkOf(res);
  const { role_id } = parse(z.object({ role_id: z.string().uuid() }), req.body);
  await withPlatform(async (c) => {
    const ok = await c.query(`SELECT 1 FROM pk_user_roles WHERE id = $1 AND user_id = $2`, [role_id, pk.userId]);
    if (!ok.rowCount) throw notFound('Peran');
    await c.query(`UPDATE pk_sessions SET role_id = $2 WHERE id = $1`, [pk.sessionId, role_id]);
    await audit(c, pk.userId, 'switch_role', null, { role_id }, req.ip);
  });
  res.json(await mePayload((await loadContext(pk.sessionId))!));
});

polmasRouter.post('/auth/logout', async (_req, res) => {
  const pk = pkOf(res);
  await withPlatform((c) => c.query(`UPDATE pk_sessions SET revoked_at = now() WHERE id = $1`, [pk.sessionId]));
  res.status(204).end();
});

const coordSchema = z.object({ lat: z.coerce.number().min(-90).max(90), lng: z.coerce.number().min(-180).max(180) });

/** Wilayah yang sudah dikonfirmasi + usulan dari koordinat GPS (bila lat/lng dikirim). */
polmasRouter.get('/me/area', async (req, res) => {
  const pk = pkOf(res);
  let suggestion = null;
  if (req.query.lat !== undefined) {
    const { lat, lng } = parse(coordSchema, req.query);
    await enforce(`pk-reverse:${pk.userId}`, 20, 600);
    suggestion = await reverseRegion(lat, lng);
  }
  res.set('Cache-Control', 'no-store').json({ confirmed: pk.area, suggestion, geocoder: suggestion !== null || req.query.lat === undefined });
});

const regionRef = z.object({ code: z.string(), name: z.string().trim().min(1).max(100) });
const areaSchema = z.object({
  province: regionRef, regency: regionRef, district: regionRef, village: regionRef.nullish(),
  lat: z.number().min(-90).max(90).nullish(), lng: z.number().min(-180).max(180).nullish(),
});

polmasRouter.put('/me/area', async (req, res) => {
  const pk = pkOf(res);
  const a = parse(areaSchema, req.body);
  const chain = [a.province, a.regency, a.district, ...(a.village ? [a.village] : [])];
  await withPlatform(async (c) => {
    const rows = (await c.query(`SELECT kode, nama, parent, level FROM wilayah WHERE kode = ANY($1)`, [chain.map((x) => x.code)])).rows;
    const byCode = new Map(rows.map((r) => [r.kode, r]));
    chain.forEach((x, i) => {
      const w = byCode.get(x.code);
      if (!w || w.level !== i + 1 || (i > 0 && w.parent !== chain[i - 1]!.code)) {
        throw new ApiError(422, 'invalid_area', 'Susunan wilayah tidak valid. Pilih ulang dari daftar.');
      }
      x.name = w.nama; // nama resmi dari tabel, bukan dari klien
    });
    const area: PkArea = { province: a.province, regency: a.regency, district: a.district, village: a.village ?? null };
    await c.query(
      `UPDATE pk_users SET area = $2, area_lat = $3, area_lng = $4, area_confirmed_at = now() WHERE id = $1`,
      [pk.userId, JSON.stringify(area), a.lat ?? null, a.lng ?? null]);
    await audit(c, pk.userId, 'confirm_area', null, { district: a.district.code }, req.ip);
  });
  res.json(await mePayload((await loadContext(pk.sessionId))!));
});

polmasRouter.get('/regions', async (req, res) => {
  const parent = typeof req.query.parent === 'string' && req.query.parent !== '' ? req.query.parent : null;
  if (parent !== null && !isParentCode(parent)) throw new ApiError(422, 'invalid_parent', 'parent harus kode wilayah');
  res.set('Cache-Control', 'private, max-age=86400').json({ parent, regions: await childRegions(parent) });
});

// ---------------------------------------------------------------- dashboard

polmasRouter.get('/dashboard', async (_req, res) => {
  const pk = pkOf(res);
  const scope = scopeOf(pk);
  const row = await withPlatform((c) => c.query(
    `SELECT
       count(*) FILTER (WHERE r.kind = 'sos' AND r.created_at >= date_trunc('day', now() AT TIME ZONE 'Asia/Jakarta') AT TIME ZONE 'Asia/Jakarta')::int AS sos_today,
       count(*) FILTER (WHERE r.status = 'open')::int AS new_reports,
       count(*) FILTER (WHERE r.status IN ('acknowledged','in_progress'))::int AS in_progress,
       count(*) FILTER (WHERE r.status = 'resolved' AND r.resolved_at > now() - interval '7 days')::int AS resolved_7d,
       count(*) FILTER (WHERE r.status = 'open' AND r.kind = 'sos' AND r.created_at > now() - interval '30 minutes')::int AS active_sos
     ${PK_FROM} WHERE ${PK_BASE} AND ${SCOPE} AND r.created_at > now() - interval '90 days'`, scopeParams(pk)).then((r) => r.rows[0]));
  res.set('Cache-Control', 'no-store').json({ cards: row, scope });
});

// ---------------------------------------------------------------- daftar laporan / riwayat

const listSchema = z.object({
  scope: z.enum(['kecamatan', 'me']).default('kecamatan'),
  kind: z.enum(['sos', 'laporan']).optional(),
  status: z.enum(['baru', 'diproses', 'diterima', 'diverifikasi', 'ditangani', 'selesai', 'tidak_valid']).optional(),
  kelurahan: z.string().regex(/^[0-9.]{13}$/).optional(),
  source: z.enum(['warga', 'kantor', 'umkm', 'sekolah', 'komunitas']).optional(),
  q: z.string().trim().max(80).optional(),
  from: z.string().date().optional(),
  to: z.string().date().optional(),
  before: z.string().datetime({ offset: true }).optional(),
  limit: z.coerce.number().int().min(1).max(100).default(30),
});

/** GET /reports (FR-16) dan /history (FR-18) memakai daftar yang sama; history default scope=me. */
async function listReports(req: Request, res: Response, defaults: Partial<z.infer<typeof listSchema>> = {}) {
  const pk = pkOf(res);
  const f = parse(listSchema, { ...defaults, ...req.query });
  // "Saya" tidak memakai $3 (kecamatan); parameter yang tidak dirujuk ditolak Postgres, jadi jangan dikirim.
  const params: unknown[] = f.scope === 'me' ? [pk.phone, pk.userId] : scopeParams(pk);
  const where = [PK_BASE, f.scope === 'me' ? mineWhere({ phone: 1, user: 2 }) : SCOPE];
  if (f.kind) where.push(f.kind === 'sos' ? `r.kind = 'sos'` : `r.kind = 'pengaduan'`);
  const statusAt = where.length;
  if (f.status) where.push(STATUS_SQL[f.status]!);
  if (f.kelurahan) { params.push(f.kelurahan); where.push(`r.kelurahan_code = $${params.length}`); }
  if (f.source) { params.push(f.source); where.push(`a.polmas_source = $${params.length}`); }
  if (f.q) {
    params.push(`%${f.q.replace(/[%_\\]/g, '\\$&')}%`);
    const p = `$${params.length}`;
    where.push(`(r.message ILIKE ${p} OR r.category ILIKE ${p} OR r.reporter_name ILIKE ${p} OR r.complaint_details->>'title' ILIKE ${p} OR wl.nama ILIKE ${p})`);
  }
  if (f.from) { params.push(f.from); where.push(`r.created_at >= ($${params.length}::date)::timestamp AT TIME ZONE 'Asia/Jakarta'`); }
  if (f.to) { params.push(f.to); where.push(`r.created_at < ($${params.length}::date + 1)::timestamp AT TIME ZONE 'Asia/Jakarta'`); }
  if (f.before) { params.push(f.before); where.push(`r.created_at < $${params.length}`); }
  // Jumlah per status untuk chip filter (Semua/Darurat/Diproses/Selesai): filter lain tetap, status diabaikan.
  // Hanya di halaman pertama; halaman berikut (before=…) tidak perlu.
  const countWhere = where.filter((_, i) => !(f.status && i === statusAt));
  const countParams = [...params];
  params.push(f.limit + 1);
  const { rows, counts } = await withPlatform(async (c) => ({
    rows: (await c.query(
      `SELECT ${PK_COLUMNS} ${PK_FROM} ${PK_LAST_RESPONSE}
       WHERE ${where.join(' AND ')} ORDER BY r.created_at DESC LIMIT $${params.length}`, params)).rows,
    counts: f.before ? null : (await c.query(
      `SELECT count(*)::int AS semua, count(*) FILTER (WHERE r.status = 'open')::int AS baru,
              count(*) FILTER (WHERE r.status IN ('acknowledged','in_progress'))::int AS diproses,
              count(*) FILTER (WHERE r.status = 'resolved')::int AS selesai
       ${PK_FROM} WHERE ${countWhere.join(' AND ')}`, countParams)).rows[0],
  }));
  const more = rows.length > f.limit;
  // Gambar mini kartu = foto bukti pertama (presigned GET 15 mnt; ditandatangani lokal, tanpa panggilan ke storage).
  // thumb_urls: sampai 3 foto untuk deretan gambar mini di kartu (video/suara tampil sebagai ubin + durasi).
  const sign = (k: string) => (mediaEnabled() ? presignGet(k).catch(() => null) : Promise.resolve(null));
  const items = await Promise.all(rows.slice(0, f.limit).map(async (r) => {
    const thumbs = (await Promise.all(((r.thumb_keys as string[] | null) ?? []).map(sign))).filter((u): u is string => !!u);
    return { ...serializePk(r, pk), thumb_url: thumbs[0] ?? null, thumb_urls: thumbs };
  }));
  res.set('Cache-Control', 'no-store').json({ items, counts, next_before: more ? items[items.length - 1]!.created_at : null });
}

polmasRouter.get('/reports', (req, res) => listReports(req, res));
polmasRouter.get('/history', (req, res) => listReports(req, res, { scope: 'me' }));

// ---------------------------------------------------------------- peta & video

polmasRouter.get('/map', async (req, res) => {
  const pk = pkOf(res);
  const { days, kind } = parse(z.object({ days: z.coerce.number().int().min(1).max(365).default(30), kind: z.enum(['sos', 'laporan']).optional() }), req.query);
  const rows = await withPlatform((c) => c.query(
    `SELECT ${PK_COLUMNS} ${PK_FROM} ${PK_LAST_RESPONSE}
     WHERE ${PK_BASE} AND ${SCOPE} AND r.lat IS NOT NULL AND r.created_at > now() - make_interval(days => $4)
       ${kind ? (kind === 'sos' ? `AND r.kind = 'sos'` : `AND r.kind = 'pengaduan'`) : ''}
     ORDER BY r.created_at DESC LIMIT 500`, [...scopeParams(pk), days]).then((r) => r.rows));
  res.set('Cache-Control', 'no-store').json({ items: rows.map((r) => serializePk(r, pk)) });
});

polmasRouter.get('/videos', async (_req, res) => {
  const pk = pkOf(res);
  const rows = await withPlatform((c) => c.query(
    `SELECT m.id AS media_id, m.storage_key, m.duration_s, m.content_type, m.created_at AS media_created_at, ${PK_COLUMNS}
     ${PK_FROM} JOIN report_media m ON m.report_id = r.id AND m.status = 'ready' AND m.kind = 'video' ${PK_LAST_RESPONSE}
     WHERE ${PK_BASE} AND ${SCOPE} ORDER BY m.created_at DESC LIMIT 40`, scopeParams(pk)).then((r) => r.rows));
  const items = await Promise.all(rows.map(async (r) => ({
    id: r.media_id,
    duration_s: r.duration_s,
    content_type: r.content_type,
    created_at: r.media_created_at,
    url: mediaEnabled() ? await presignGet(r.storage_key).catch(() => null) : null,
    report: serializePk(r, pk),
  })));
  res.set('Cache-Control', 'no-store').json({ items, url_expires_in: config.media.viewUrlTtlS });
});

// ---------------------------------------------------------------- berita

polmasRouter.get('/news', async (_req, res) => {
  const pk = pkOf(res);
  const scope = scopeOf(pk);
  const rows = await withPlatform((c) => c.query(
    `SELECT n.*, w.nama AS kecamatan_name FROM pk_news n LEFT JOIN wilayah w ON w.kode = n.kecamatan_code
     WHERE (n.kecamatan_code IS NULL OR n.kecamatan_code = $1) AND n.published_at <= now()
     ORDER BY n.published_at DESC LIMIT 30`, [scope]).then((r) => r.rows));
  res.set('Cache-Control', 'no-store').json({ items: rows.map((n) => ({
    id: n.id, category: n.category, title: n.title, summary: n.summary, body: n.body, author: n.author,
    published_at: n.published_at, is_demo: n.is_demo, kecamatan: n.kecamatan_code ? { code: n.kecamatan_code, name: n.kecamatan_name } : null,
  })) });
});

// ---------------------------------------------------------------- detail & tanggapan

async function loadVisible(c: Db, id: string, pk: PkContext) {
  if (!/^[0-9a-f-]{36}$/i.test(id)) throw notFound('Laporan');
  const r = (await c.query(
    `SELECT ${PK_COLUMNS} ${PK_FROM} ${PK_LAST_RESPONSE}
     WHERE r.id = $4 AND ${PK_BASE} AND ${visibleWhere({ phone: 1, scope: 3, user: 2 })}`,
    [pk.phone, pk.userId, scopeOf(pk), id])).rows[0];
  if (!r) throw notFound('Laporan');
  return r;
}

polmasRouter.get('/reports/:id', async (req, res) => {
  const pk = pkOf(res);
  const out = await withPlatform(async (c) => {
    const r = await loadVisible(c, String(req.params.id), pk);
    const media = await listReadyMedia(c, r.id);
    const responses = (await c.query(
      `SELECT action, officer, note, created_at, user_id = $2 AS is_me FROM pk_responses WHERE report_id = $1 ORDER BY created_at`, [r.id, pk.userId])).rows;
    const events = (await c.query(
      `SELECT e.type, e.actor_kind, e.from_status, e.to_status, e.note, e.created_at, u.full_name AS actor_name
       FROM report_events e LEFT JOIN users u ON u.id = e.actor_id
       WHERE e.report_id = $1 AND e.type IN ('status_changed','cancelled','note','media')
         AND NOT (e.actor_kind = 'responder' AND coalesce(e.note, '') LIKE 'Polmas Keamanan · %')
       ORDER BY e.created_at`, [r.id])).rows;
    const trail = (await c.query(
      `SELECT lat, lng, recorded_at FROM report_locations WHERE report_id = $1 ORDER BY recorded_at DESC LIMIT 50`, [r.id])).rows;
    await audit(c, pk.userId, 'view_report', r.id, { media: media.length }, req.ip);
    return { r, media, responses, events, trail };
  });
  const item = serializePk(out.r, pk, {
    image: out.media.filter((m) => m.kind === 'image').length,
    video: out.media.filter((m) => m.kind === 'video').length,
    audio: out.media.filter((m) => m.kind === 'audio').length,
  });
  const timeline = [
    { at: out.r.created_at, kind: 'created', title: out.r.kind === 'sos' ? 'SOS dikirim' : 'Laporan dikirim', actor: item.reporter.name, note: null },
    ...out.events.map((e) => ({
      at: e.created_at,
      kind: e.type === 'media' ? 'media' : e.type === 'note' ? 'note' : 'status',
      title: e.type === 'media' ? (e.note ?? 'Lampiran ditambahkan') : e.type === 'note' ? 'Catatan' : statusTitle(e.to_status),
      actor: e.actor_kind === 'reporter' ? 'Pelapor' : e.actor_kind === 'user' ? (e.actor_name ?? 'Petugas aplikasi sumber') : e.actor_kind === 'responder' ? 'Penerima darurat' : 'Sistem',
      note: e.type === 'media' ? null : e.note,
    })),
    ...out.responses.map((x) => ({ at: x.created_at, kind: 'response', action: x.action, title: ACTION_TITLE[x.action as Action], actor: x.officer, note: x.note, is_me: x.is_me })),
  ].sort((a, b) => new Date(a.at).getTime() - new Date(b.at).getTime());
  const full = item.reporter.phone !== null;
  res.set('Cache-Control', 'no-store').json({
    ...item,
    accuracy_m: out.r.accuracy_m,
    complaint: out.r.complaint_details ?? null,
    media: out.media.map((m) => ({ id: m.id, kind: m.kind, content_type: m.content_type, duration_s: m.duration_s, url: m.url, created_at: m.created_at })),
    timeline,
    trail: full ? out.trail : [],
    actions: canRespondTo(pk, out.r) ? allowedActions(out.r) : [],
    sla_min: SLA_MIN[out.r.kind === 'pengaduan' ? 'pengaduan' : 'sos'],
  });
});

const statusTitle = (s: string | null) => ({
  acknowledged: 'Diterima', in_progress: 'Ditangani', resolved: 'Selesai', cancelled: 'Dibatalkan pelapor', false_alarm: 'Tidak valid', open: 'Dibuka ulang',
} as Record<string, string>)[s ?? ''] ?? 'Status berubah';

type Action = 'terima' | 'hubungi' | 'verifikasi' | 'tangani' | 'selesai' | 'tidak_valid' | 'catatan';
const ACTION_TITLE: Record<Action, string> = {
  terima: 'Diterima', hubungi: 'Menghubungi pelapor', verifikasi: 'Diverifikasi', tangani: 'Ditangani',
  selesai: 'Selesai', tidak_valid: 'Dinyatakan tidak valid', catatan: 'Catatan petugas',
};
const ACTION_STATUS: Partial<Record<Action, 'acknowledged' | 'in_progress' | 'resolved' | 'false_alarm'>> = {
  terima: 'acknowledged', tangani: 'in_progress', selesai: 'resolved', tidak_valid: 'false_alarm',
};
const TERMINAL = ['resolved', 'cancelled', 'false_alarm'];

function allowedActions(r: { status: string; verified_at: unknown }): Action[] {
  if (TERMINAL.includes(r.status)) return [];
  const out: Action[] = ['hubungi'];
  if (r.status === 'open') out.push('terima');
  if (!r.verified_at) out.push('verifikasi');
  if (r.status !== 'in_progress') out.push('tangani');
  out.push('selesai', 'tidak_valid', 'catatan');
  return out;
}

const responseSchema = z.object({
  action: z.enum(['terima', 'hubungi', 'verifikasi', 'tangani', 'selesai', 'tidak_valid', 'catatan']),
  note: z.string().trim().max(1000).optional(),
}).superRefine((b, ctx) => {
  if (b.action === 'catatan' && !b.note) ctx.addIssue({ code: z.ZodIssueCode.custom, path: ['note'], message: 'Catatan wajib diisi' });
});

/**
 * Tanggapan penerima (FR-07, FR-17): pemilik Nomor Darurat untuk laporan yang memanggil nomornya, Bhabinkamtibmas
 * untuk laporan di kecamatannya. Status kembali ke aplikasi sumber lewat changeReport (timeline, realtime, webhook, SDK).
 */
polmasRouter.post('/reports/:id/responses', async (req, res) => {
  const pk = pkOf(res);
  if (!canRespondAny(pk)) throw new ApiError(403, 'cannot_respond', 'Peran ini hanya bisa melihat laporan.');
  const body = parse(responseSchema, req.body);
  await enforce(`pk-respond:${pk.userId}`, 60, 600);
  const officer = `${pk.name}${pk.role.unit ? ` (${pk.role.unit})` : ''}`;
  const result = await withPlatform(async (c) => {
    const r = await loadVisible(c, String(req.params.id), pk);
    if (!canRespondTo(pk, r)) throw new ApiError(403, 'cannot_respond', 'Anda tidak tercatat sebagai penerima laporan ini.');
    if (TERMINAL.includes(r.status)) throw new ApiError(409, 'report_closed', 'Laporan sudah ditutup.');
    const allowed = allowedActions(r);
    if (!allowed.includes(body.action)) throw new ApiError(409, 'action_not_allowed', 'Aksi ini tidak berlaku untuk status laporan sekarang.');

    let target = ACTION_STATUS[body.action];
    // Hubungi/verifikasi laporan yang belum diterima otomatis menerimanya dulu (waktu respons pertama tercatat).
    if (!target && r.status === 'open' && (body.action === 'hubungi' || body.action === 'verifikasi')) target = 'acknowledged';
    const note = `Polmas Keamanan · ${officer}: ${ACTION_TITLE[body.action]}${body.note ? ` — ${body.note}` : ''}`;
    await changeReport(c, r.id, { status: target && target !== r.status ? target : undefined, note }, { kind: 'responder', name: officer });
    if (body.action === 'verifikasi') await c.query(`UPDATE reports SET verified_at = now() WHERE id = $1`, [r.id]);
    const msg = statusMessage(body.action, isOfficer(pk) ? `Bhabinkamtibmas ${pk.name}` : pk.name);
    if (msg) await c.query(`UPDATE reports SET status_message = $2 WHERE id = $1`, [r.id, msg]);
    await c.query(
      `INSERT INTO pk_responses (report_id, account_id, user_id, officer, action, note) VALUES ($1,$2,$3,$4,$5,$6)`,
      [r.id, r.account_id, pk.userId, officer, body.action, body.note ?? null]);
    await audit(c, pk.userId, 'respond', r.id, { action: body.action }, req.ip);
    return loadVisible(c, r.id, pk);
  });
  res.status(201).json(serializePk(result, pk));
});

/** Teks status di SDK pelapor, mis. "Agus (Satpam) sedang menangani laporan Anda." */
function statusMessage(a: Action, who: string): string | null {
  switch (a) {
    case 'terima': return `Laporan diterima ${who}.`;
    case 'verifikasi': return `Laporan sudah diverifikasi ${who}.`;
    case 'tangani': return `${who} sedang menangani laporan Anda.`;
    case 'selesai': return `Laporan selesai ditangani ${who}.`;
    case 'tidak_valid': return `Laporan dinyatakan tidak valid oleh ${who}.`;
    default: return null;
  }
}

// ---------------------------------------------------------------- panggilan SOS masuk & notifikasi

/**
 * Polling ringan (tiap ±4 dtk saat app terbuka): SOS terbuka ≤ 30 menit yang memanggil pengguna ini, yaitu nomornya
 * ada di kontak darurat SOS, atau dia Bhabinkamtibmas di kecamatan kejadian. Plus jumlah notifikasi belum dibaca.
 */
polmasRouter.get('/inbox', async (_req, res) => {
  const pk = pkOf(res);
  const scope = scopeOf(pk);
  const out = await withPlatform(async (c) => {
    const calls = (await c.query(
      `SELECT ${PK_COLUMNS} ${PK_FROM} ${PK_LAST_RESPONSE}
       WHERE ${PK_BASE} AND r.kind = 'sos' AND r.status = 'open' AND r.created_at > now() - interval '30 minutes'
         AND (r.emergency_contacts @> jsonb_build_array(jsonb_build_object('phone', $1::text))
              OR ($3::boolean AND a.polmas_source IS NOT NULL AND r.kecamatan_code = $4))
         AND NOT EXISTS (SELECT 1 FROM pk_call_dismissals d WHERE d.user_id = $2 AND d.report_id = r.id)
       ORDER BY r.created_at DESC LIMIT 3`, [pk.phone, pk.userId, isOfficer(pk), scope])).rows;
    const unread = (await c.query(
      `SELECT count(*)::int AS n ${PK_FROM}
       WHERE ${PK_BASE} AND r.created_at > (SELECT notif_seen_at FROM pk_users WHERE id = $2)
         AND r.created_at > now() - interval '14 days' AND ${visibleWhere({ phone: 1, scope: 3, user: 2 })}`,
      [pk.phone, pk.userId, scope])).rows[0].n;
    // Badge tab Laporan: laporan yang belum ditanggapi siapa pun (90 hari, cakupan sama dengan daftar).
    const open = (await c.query(
      `SELECT count(*)::int AS n ${PK_FROM} WHERE ${PK_BASE} AND ${SCOPE} AND r.status = 'open' AND r.created_at > now() - interval '90 days'`,
      scopeParams(pk))).rows[0].n;
    return { calls, unread, open };
  });
  res.set('Cache-Control', 'no-store').json({
    calls: out.calls.map((r) => serializePk(r, pk)), unread: out.unread, open_reports: out.open, server_time: new Date().toISOString(),
  });
});

polmasRouter.post('/reports/:id/call', async (req, res) => {
  const pk = pkOf(res);
  const { action } = parse(z.object({ action: z.enum(['accepted', 'ignored']) }), req.body);
  await withPlatform(async (c) => {
    const r = await loadVisible(c, String(req.params.id), pk);
    await c.query(
      `INSERT INTO pk_call_dismissals (user_id, report_id, action) VALUES ($1,$2,$3)
       ON CONFLICT (user_id, report_id) DO UPDATE SET action = EXCLUDED.action, created_at = now()`, [pk.userId, r.id, action]);
    await audit(c, pk.userId, action === 'accepted' ? 'call_accepted' : 'call_ignored', r.id, null, req.ip);
  });
  res.status(204).end();
});

/** Riwayat notifikasi (FR-05): laporan baru di wilayah/untuk saya + tanggapan petugas + berita, 14 hari terakhir. */
polmasRouter.get('/notifications', async (_req, res) => {
  const pk = pkOf(res);
  const scope = scopeOf(pk);
  const rows = await withPlatform(async (c) => {
    const seen = (await c.query(`SELECT notif_seen_at FROM pk_users WHERE id = $1`, [pk.userId])).rows[0].notif_seen_at;
    const vis = visibleWhere({ phone: 1, scope: 3, user: 2 });
    const reports = (await c.query(
      `SELECT ${PK_COLUMNS} ${PK_FROM} ${PK_LAST_RESPONSE}
       WHERE ${PK_BASE} AND r.created_at > now() - interval '14 days' AND ${vis} ORDER BY r.created_at DESC LIMIT 40`,
      [pk.phone, pk.userId, scope])).rows;
    const responses = (await c.query(
      `SELECT x.action, x.officer, x.note, x.created_at, x.user_id = $2 AS is_me, r.id AS report_id, r.kind, r.category
       FROM pk_responses x JOIN reports r ON r.id = x.report_id JOIN apps a ON a.id = r.app_id
       WHERE ${PK_BASE} AND x.created_at > now() - interval '14 days' AND x.user_id IS DISTINCT FROM $2 AND ${vis}
       ORDER BY x.created_at DESC LIMIT 40`, [pk.phone, pk.userId, scope])).rows;
    const news = (await c.query(
      `SELECT id, title, category, published_at FROM pk_news
       WHERE (kecamatan_code IS NULL OR kecamatan_code = $1) AND published_at > now() - interval '14 days' AND published_at <= now()
       ORDER BY published_at DESC LIMIT 10`, [scope])).rows;
    return { seen: new Date(seen).getTime(), reports, responses, news };
  });
  const items = [
    ...rows.reports.map((r) => {
      const s = serializePk(r, pk);
      return {
        id: `r:${r.id}`, type: s.kind, report_id: r.id, at: r.created_at,
        title: s.kind === 'sos' ? `SOS dari ${s.source_label}` : `Laporan baru: ${s.title ?? r.category}`,
        body: [s.kelurahan?.name ? `Kel. ${s.kelurahan.name}` : null, s.reporter.name].filter(Boolean).join(' · '),
      };
    }),
    ...rows.responses.map((x) => ({
      id: `x:${x.report_id}:${new Date(x.created_at).getTime()}`, type: 'tanggapan', report_id: x.report_id, at: x.created_at,
      title: `Tanggapan: ${ACTION_TITLE[x.action as Action]}`, body: `${x.officer}${x.note ? ` — ${x.note}` : ''}`,
    })),
    ...rows.news.map((n) => ({ id: `n:${n.id}`, type: 'berita', news_id: n.id, at: n.published_at, title: n.title, body: n.category === 'imbauan' ? 'Imbauan' : n.category === 'pengumuman' ? 'Pengumuman' : 'Kabar' })),
  ]
    .sort((a, b) => new Date(b.at).getTime() - new Date(a.at).getTime())
    .slice(0, 60)
    .map((n) => ({ ...n, unread: new Date(n.at).getTime() > rows.seen }));
  res.set('Cache-Control', 'no-store').json({ items });
});

polmasRouter.post('/notifications/read-all', async (_req, res) => {
  const pk = pkOf(res);
  await withPlatform((c) => c.query(`UPDATE pk_users SET notif_seen_at = now() WHERE id = $1`, [pk.userId]));
  res.status(204).end();
});

// ---------------------------------------------------------------- analisa & evaluasi

const periodSchema = z.object({
  period: z.enum(['7d', '30d', '90d', 'custom']).default('7d'),
  from: z.string().date().optional(),
  to: z.string().date().optional(),
});

/** Rentang [from, to) dalam hari Asia/Jakarta + rentang sebelumnya dengan panjang sama (untuk perbandingan). */
function periodRange(q: unknown) {
  const p = parse(periodSchema, q);
  const dayMs = 86400_000;
  const todayJkt = new Date(Date.now() + 7 * 3600_000).toISOString().slice(0, 10);
  let from: string, to: string;
  if (p.period === 'custom') {
    if (!p.from || !p.to || p.from > p.to) throw new ApiError(422, 'invalid_period', 'Isi tanggal mulai dan selesai dengan benar.');
    from = p.from; to = p.to;
    if ((Date.parse(to) - Date.parse(from)) / dayMs > 366) throw new ApiError(422, 'invalid_period', 'Rentang maksimal 1 tahun.');
  } else {
    const n = p.period === '7d' ? 7 : p.period === '30d' ? 30 : 90;
    to = todayJkt;
    from = new Date(Date.parse(todayJkt) - (n - 1) * dayMs).toISOString().slice(0, 10);
  }
  const days = Math.round((Date.parse(to) - Date.parse(from)) / dayMs) + 1;
  const prevTo = new Date(Date.parse(from) - dayMs).toISOString().slice(0, 10);
  const prevFrom = new Date(Date.parse(from) - days * dayMs).toISOString().slice(0, 10);
  return { period: p.period, from, to, days, prevFrom, prevTo };
}

const RANGE = (a: number, b: number) =>
  `r.created_at >= ($${a}::date)::timestamp AT TIME ZONE 'Asia/Jakarta' AND r.created_at < ($${b}::date + 1)::timestamp AT TIME ZONE 'Asia/Jakarta'`;

const sourceSchema = z.object({ source: z.enum(['warga', 'kantor', 'umkm', 'sekolah', 'komunitas']).optional() });

/** Median detik dari laporan masuk sampai pertama ditanggapi (acknowledged_at). */
const MEDIAN_RESPONSE = `round(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM r.acknowledged_at - r.created_at))
  FILTER (WHERE r.acknowledged_at IS NOT NULL))::int`;

const DOW_NAME = ['', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];

/**
 * Saran patroli (tab Waktu & Wilayah): jendela 3 jam teramai, hari teramai (akhir pekan bila rata-rata per harinya
 * ≥ 1,2× hari kerja), dan 2 kelurahan teratas. Null bila data terlalu sedikit (< 10 laporan).
 */
function patrolHint(heat: { dow: number; hour: number; n: number }[], byHour: number[], kel: { name: string; code: string | null }[]) {
  const total = byHour.reduce((a, b) => a + b, 0);
  if (total < 10) return null;
  let best = 0;
  for (let h = 1; h <= 21; h++) if (byHour[h]! + byHour[h + 1]! + byHour[h + 2]! > byHour[best]! + byHour[best + 1]! + byHour[best + 2]!) best = h;
  const perDow = Array.from({ length: 8 }, (_, d) => heat.filter((x) => x.dow === d).reduce((s, x) => s + x.n, 0));
  const weekend = (perDow[6]! + perDow[7]!) / 2;
  const weekday = (perDow[1]! + perDow[2]! + perDow[3]! + perDow[4]! + perDow[5]!) / 5;
  const topDow = perDow.indexOf(Math.max(...perDow.slice(1)));
  return {
    days: weekend >= weekday * 1.2 ? 'Sabtu–Minggu' : DOW_NAME[topDow]!,
    from_hour: best,
    to_hour: best + 3,
    kelurahan: kel.filter((k) => k.code).slice(0, 2).map((k) => k.name),
  };
}

polmasRouter.get('/analytics/summary', async (req, res) => {
  const pk = pkOf(res);
  const p = periodRange(req.query);
  const { source } = parse(sourceSchema, req.query);
  // $1–$3 cakupan, $4–$5 rentang, $6 ekosistem (opsional).
  const src = source ? ` AND a.polmas_source = $6` : '';
  const base = `${PK_FROM} WHERE ${PK_BASE} AND ${SCOPE} AND ${RANGE(4, 5)}${src}`;
  const args = [...scopeParams(pk), p.from, p.to, ...(source ? [source] : [])];
  const prevArgs = [...scopeParams(pk), p.prevFrom, p.prevTo, ...(source ? [source] : [])];
  const out = await withPlatform(async (c) => {
    const totalsSql =
      `SELECT count(*)::int AS total, count(*) FILTER (WHERE r.kind = 'sos')::int AS sos, count(*) FILTER (WHERE r.kind = 'pengaduan')::int AS laporan,
              count(*) FILTER (WHERE r.status = 'resolved')::int AS selesai, count(*) FILTER (WHERE r.status IN ('acknowledged','in_progress'))::int AS diproses,
              count(*) FILTER (WHERE r.status = 'open')::int AS baru, count(*) FILTER (WHERE r.status IN ('false_alarm','cancelled'))::int AS lainnya,
              ${MEDIAN_RESPONSE} AS median_response_s
       ${base}`;
    const totals = (await c.query(totalsSql, args)).rows[0];
    // Periode sebelumnya dengan panjang sama → persen naik/turun di kartu ringkasan.
    const previous = (await c.query(totalsSql, prevArgs)).rows[0];
    const trend = (await c.query(
      `SELECT d::date AS day,
              count(r.id) FILTER (WHERE r.kind = 'sos')::int AS sos,
              count(r.id) FILTER (WHERE r.kind = 'pengaduan')::int AS laporan
       FROM generate_series($4::date, $5::date, interval '1 day') d
       LEFT JOIN (SELECT r.id, r.kind, r.created_at ${base}) r ON (r.created_at AT TIME ZONE 'Asia/Jakarta')::date = d::date
       GROUP BY d ORDER BY d`, args)).rows;
    const kelSql = `SELECT coalesce(wl.nama, 'Belum diketahui') AS name, r.kelurahan_code AS code, count(*)::int AS n ${base} GROUP BY 1, 2 ORDER BY n DESC LIMIT 12`;
    const byKelurahan = (await c.query(kelSql, args)).rows;
    const kelPrev = (await c.query(kelSql, prevArgs)).rows;
    const byCategory = (await c.query(
      `SELECT r.category AS name, count(*)::int AS n ${base} GROUP BY 1 ORDER BY n DESC LIMIT 8`, args)).rows;
    const bySource = (await c.query(
      `SELECT a.polmas_source AS source, count(*)::int AS n ${base} GROUP BY 1 ORDER BY n DESC`, args)).rows;
    const byEcosystem = (await c.query(
      `SELECT a.polmas_source AS source, a.name AS app_name, count(*)::int AS n, ${MEDIAN_RESPONSE} AS median_response_s
       ${base} GROUP BY 1, 2 ORDER BY n DESC`, args)).rows;
    const matrix = (await c.query(
      `SELECT a.polmas_source AS source, r.category, count(*)::int AS n ${base} GROUP BY 1, 2`, args)).rows;
    const funnel = (await c.query(
      `SELECT count(*) FILTER (WHERE r.status <> 'cancelled')::int AS masuk,
              count(*) FILTER (WHERE r.acknowledged_at IS NOT NULL OR r.status IN ('acknowledged','in_progress','resolved'))::int AS diterima,
              count(*) FILTER (WHERE r.verified_at IS NOT NULL OR r.status IN ('in_progress','resolved'))::int AS diverifikasi,
              count(*) FILTER (WHERE r.status IN ('in_progress','resolved'))::int AS ditangani,
              count(*) FILTER (WHERE r.status = 'resolved')::int AS selesai,
              count(*) FILTER (WHERE r.status = 'false_alarm')::int AS tidak_valid
       ${base}`, args)).rows[0];
    // Per petugas: tanggapan pertama tiap petugas per laporan → jumlah ditangani, selesai, median respons.
    const officers = (await c.query(
      `SELECT f.user_id, max(f.officer) AS officer, bool_or(f.user_id = $2) AS is_me, count(*)::int AS ditangani,
              count(*) FILTER (WHERE f.done)::int AS selesai,
              round(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM f.first_at - f.created_at)))::int AS median_response_s
       FROM (SELECT x.user_id, x.report_id, max(x.officer) AS officer, min(x.created_at) AS first_at,
                    bool_or(x.action = 'selesai') AS done, min(r.created_at) AS created_at
             ${base.replace(' WHERE ', ' JOIN pk_responses x ON x.report_id = r.id WHERE x.user_id IS NOT NULL AND ')}
             GROUP BY 1, 2) f
       GROUP BY f.user_id ORDER BY selesai DESC, ditangani DESC LIMIT 10`, args)).rows;
    const heat = (await c.query(
      `SELECT extract(isodow FROM r.created_at AT TIME ZONE 'Asia/Jakarta')::int AS dow,
              extract(hour FROM r.created_at AT TIME ZONE 'Asia/Jakarta')::int AS hour, count(*)::int AS n
       ${base} GROUP BY 1, 2`, args)).rows;
    const weekly = (await c.query(
      `SELECT to_char(date_trunc('week', r.created_at AT TIME ZONE 'Asia/Jakarta'), 'YYYY-MM-DD') AS week, count(*)::int AS n,
              ${MEDIAN_RESPONSE} AS median_response_s
       ${PK_FROM} WHERE ${PK_BASE} AND ${SCOPE} AND r.created_at > now() - interval '8 weeks'${source ? ' AND a.polmas_source = $4' : ''}
       GROUP BY 1 ORDER BY 1`, [...scopeParams(pk), ...(source ? [source] : [])])).rows;
    return { totals, previous, trend, byKelurahan, kelPrev, byCategory, bySource, byEcosystem, matrix, funnel, officers, heat, weekly };
  });
  const byHour = Array.from({ length: 24 }, (_, h) => out.heat.filter((x) => x.hour === h).reduce((s, x) => s + x.n, 0));
  const prevKel = new Map(out.kelPrev.map((k) => [k.code ?? '', k.n as number]));
  const total = out.totals.total as number;
  res.set('Cache-Control', 'no-store').json({
    period: { key: p.period, from: p.from, to: p.to, days: p.days },
    source: source ?? null,
    totals: out.totals,
    previous_totals: out.previous,
    trend: out.trend.map((t) => ({ day: (t.day as Date).toISOString().slice(0, 10), sos: t.sos, laporan: t.laporan })),
    by_kelurahan: out.byKelurahan.map((k) => ({ ...k, prev_n: prevKel.get(k.code ?? '') ?? 0 })),
    by_category: out.byCategory,
    by_source: out.bySource.map((s) => ({ ...s, label: SOURCE_LABEL[s.source] ?? s.source })),
    // Ekosistem = pilar + nama app sumber (mis. "UMKM · commerceOS"), dengan persen dari total dan median respons.
    by_ecosystem: out.byEcosystem.map((e) => ({
      ...e, label: SOURCE_LABEL[e.source] ?? e.source, pct: total ? Math.round((e.n / total) * 100) : 0,
      top_categories: out.matrix.filter((m) => m.source === e.source).sort((a, b) => b.n - a.n).slice(0, 2).map((m) => m.category),
    })),
    matrix: out.matrix.map((m) => ({ ...m, label: SOURCE_LABEL[m.source] ?? m.source })),
    funnel: out.funnel,
    officers: out.officers.map((o) => ({ ...o, user_id: undefined })),
    heatmap: out.heat, // dow 1 = Senin … 7 = Minggu
    by_hour: byHour,
    weekly: out.weekly,
    patrol_hint: patrolHint(out.heat, byHour, out.byKelurahan),
    sla_min: SLA_MIN,
  });
});

async function evalMetrics(c: Db, pk: PkContext, from: string, to: string, source?: string) {
  return (await c.query(
    `SELECT count(*) FILTER (WHERE r.status <> 'cancelled')::int AS total,
            count(*) FILTER (WHERE r.status = 'resolved')::int AS selesai,
            count(*) FILTER (WHERE r.status IN ('open','acknowledged','in_progress'))::int AS tertunda,
            count(*) FILTER (WHERE r.status = 'open')::int AS belum_ditanggapi,
            round(avg(extract(epoch FROM r.acknowledged_at - r.created_at)) FILTER (WHERE r.acknowledged_at IS NOT NULL))::int AS avg_response_s,
            round(avg(extract(epoch FROM r.acknowledged_at - r.created_at)) FILTER (WHERE r.acknowledged_at IS NOT NULL AND r.kind = 'sos'))::int AS avg_response_sos_s,
            ${MEDIAN_RESPONSE} AS median_response_s,
            round(avg(extract(epoch FROM r.resolved_at - r.created_at)) FILTER (WHERE r.status = 'resolved'))::int AS avg_resolve_s,
            count(*) FILTER (WHERE r.acknowledged_at IS NOT NULL)::int AS ditanggapi
     ${PK_FROM} WHERE ${PK_BASE} AND ${SCOPE} AND ${RANGE(4, 5)}${source ? ' AND a.polmas_source = $6' : ''}`,
    [...scopeParams(pk), from, to, ...(source ? [source] : [])])).rows[0];
}

polmasRouter.get('/analytics/evaluation', async (req, res) => {
  const pk = pkOf(res);
  const p = periodRange(req.query);
  const { source } = parse(sourceSchema, req.query);
  const out = await withPlatform(async (c) => {
    const cur = await evalMetrics(c, pk, p.from, p.to, source);
    const prev = await evalMetrics(c, pk, p.prevFrom, p.prevTo, source);
    // Daftar belum ditanggapi hanya untuk yang bisa menanggapi (dan hanya laporan yang boleh dia tanggapi).
    const pending = canRespondAny(pk) ? (await c.query(
      `SELECT ${PK_COLUMNS} ${PK_FROM} ${PK_LAST_RESPONSE}
       WHERE ${PK_BASE} AND ${SCOPE} AND r.status = 'open'${source ? ' AND a.polmas_source = $4' : ''}
       ORDER BY (r.kind = 'sos') DESC, r.created_at LIMIT 40`, [...scopeParams(pk), ...(source ? [source] : [])])).rows
      .filter((r) => canRespondTo(pk, r)).slice(0, 20) : [];
    return { cur, prev, pending };
  });
  const pct = (m: any) => (m.total ? Math.round((m.selesai / m.total) * 1000) / 10 : null);
  const now = Date.now();
  res.set('Cache-Control', 'no-store').json({
    period: { key: p.period, from: p.from, to: p.to, prev_from: p.prevFrom, prev_to: p.prevTo },
    current: { ...out.cur, pct_selesai: pct(out.cur) },
    previous: { ...out.prev, pct_selesai: pct(out.prev) },
    sla_min: SLA_MIN,
    pending: out.pending.map((r) => {
      const s = serializePk(r, pk);
      const ageMin = Math.floor((now - new Date(r.created_at).getTime()) / 60000);
      return { ...s, age_min: ageMin, late: ageMin > SLA_MIN[r.kind === 'pengaduan' ? 'pengaduan' : 'sos'] };
    }),
    detail: canRespondAny(pk),
  });
});

// ---------------------------------------------------------------- demo (fase 0/1)

const DEMO_PLACES = ['Jl. Suryakencana', 'Jl. Pengadilan', 'Jl. Juanda', 'Gg. Aut', 'Jl. Kapten Muslihat', 'Jl. Paledang'];
const DEMO_NAMES = ['Siti Rahmawati', 'Dedi Kurniawan', 'Rina Marlina', 'Andi Saputra', 'Yuni Lestari'];

/**
 * Simulasi SOS masuk untuk akun demo: membuat laporan SOS di app sumber demo, kecamatan pengguna, dengan nomor
 * pengguna sebagai kontak darurat → layar panggilan muncul di perangkat ini dalam ±4 detik.
 */
polmasRouter.post('/demo/sos', async (req, res) => {
  const pk = pkOf(res);
  if (!pk.isDemo) throw new ApiError(403, 'demo_only', 'Simulasi hanya untuk akun demo.');
  const scope = scopeOf(pk) ?? '32.71.03'; // tanpa wilayah: kecamatan demo Bogor Tengah
  await enforce(`pk-demo-sos:${pk.userId}`, 6, 600);
  const { source } = parse(z.object({ source: z.enum(['warga', 'kantor', 'umkm', 'sekolah', 'komunitas']).default('warga') }), req.body ?? {});
  const app = await withPlatform((c) => c.query(
    `SELECT a.id, a.account_id, a.name FROM apps a WHERE a.polmas_source = $1 AND a.name LIKE '%(Demo)%' AND a.disabled_at IS NULL LIMIT 1`, [source]).then((r) => r.rows[0]));
  if (!app) throw new ApiError(409, 'demo_not_seeded', 'Data demo belum dibuat. Jalankan pnpm seed:pk.');
  const kel = await withPlatform((c) => c.query(`SELECT kode FROM wilayah WHERE parent = $1 ORDER BY random() LIMIT 1`, [scope]).then((r) => r.rows[0]?.kode ?? null));
  const baseLat = pk.areaLat ?? -6.5971;
  const baseLng = pk.areaLng ?? 106.7973;
  const jitter = () => (Math.random() - 0.5) * 0.008;
  const name = DEMO_NAMES[Math.floor(Math.random() * DEMO_NAMES.length)]!;
  const place = DEMO_PLACES[Math.floor(Math.random() * DEMO_PLACES.length)]!;
  const id = await withTenant(app.account_id, async (c) => {
    const r = (await c.query(
      `INSERT INTO reports (app_id, account_id, mode, kind, category, reporter_ref, reporter_name, reporter_phone, message, lat, lng, accuracy_m,
                            idempotency_key, emergency_contacts, metadata, kecamatan_code, kelurahan_code, area_source, area_checked_at)
       VALUES ($1,$2,'live','sos','darurat',$3,$4,$5,$6,$7,$8,12,$9,$10,$11,$12,$13,'seed',now()) RETURNING *`,
      [app.id, app.account_id, `demo:${randomUUID().slice(0, 8)}`, `${name} (Demo)`, '628009' + String(Math.floor(Math.random() * 1e6)).padStart(6, '0'),
        `Tolong! Ada orang mencurigakan masuk pekarangan di ${place}.`, baseLat + jitter(), baseLng + jitter(), randomUUID(),
        JSON.stringify([{ name: pk.name, phone: pk.phone }]), JSON.stringify({ demo: true }), scope, kel])).rows[0];
    await onReportCreated(c, r, app.name);
    return r.id as string;
  });
  res.status(201).json({ id });
});
