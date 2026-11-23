import { randomInt } from 'node:crypto';
import type { RequestHandler } from 'express';
import { withTenant, type Db } from '../db.js';
import { logger } from '../logger.js';
import { ApiError } from './errors.js';
import { randomToken, safeEqual, sha256 } from './crypto.js';
import { sendSosPush } from './fcm.js';

/**
 * Responder = satpam / penerima darurat yang login di app klien dengan nomor yang tercantum di Nomor Darurat
 * pelapor (tabel emergency_contacts). Login OTP WhatsApp → token sesi `rsp_...` (header X-SOS-Responder, selalu
 * bersama publishable key app yang sama). Setiap SOS yang menyebut nomornya (snapshot reports.emergency_contacts)
 * dikirimi push FCM ke semua perangkat sesi aktif nomor itu.
 */

export const OTP_TTL_MIN = 5;
export const OTP_MAX_ATTEMPTS = 5;
/** Laporan yang tampil di app satpam: SOS 7 hari terakhir. */
const LIST_DAYS = 7;

export interface ResponderContext { sessionId: string; phone: string; name: string }

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request { responder?: ResponderContext }
  }
}

/** Nama yang dipakai pelapor untuk nomor ini (entri terbaru), atau null bila nomor tidak ada di Nomor Darurat app ini. */
export async function registeredName(c: Db, appId: string, phone: string): Promise<string | null> {
  const r = await c.query(
    `SELECT name, role FROM emergency_contacts WHERE app_id = $1 AND phone = $2 ORDER BY active DESC, updated_at DESC LIMIT 1`,
    [appId, phone],
  );
  const row = r.rows[0];
  return row ? (row.role ? `${row.name} (${row.role})` : row.name) : null;
}

/** Ganti total Nomor Darurat milik satu pelapor. */
export async function replaceContacts(
  c: Db,
  k: { appId: string; accountId: string },
  reporter: { ref: string; name?: string | null },
  sourceId: string | null,
  contacts: { name: string; role?: string | null; phone: string; active: boolean }[],
) {
  await c.query(`DELETE FROM emergency_contacts WHERE app_id = $1 AND reporter_ref = $2`, [k.appId, reporter.ref]);
  for (const ct of contacts) {
    await c.query(
      `INSERT INTO emergency_contacts (account_id, app_id, reporter_ref, reporter_name, source_id, name, role, phone, active)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
      [k.accountId, k.appId, reporter.ref, reporter.name ?? null, sourceId, ct.name, ct.role ?? null, ct.phone, ct.active],
    );
  }
}

/** Buat OTP baru. Mengembalikan kode polos (untuk dikirim) — hanya hash yang disimpan. */
export async function createOtp(c: Db, k: { appId: string; accountId: string }, phone: string): Promise<string> {
  // Kode lama untuk nomor ini tidak berlaku lagi.
  await c.query(`UPDATE responder_otps SET consumed_at = now() WHERE app_id = $1 AND phone = $2 AND consumed_at IS NULL`, [k.appId, phone]);
  const code = String(randomInt(0, 1_000_000)).padStart(6, '0');
  const id = (await c.query(`SELECT gen_random_uuid() AS id`)).rows[0].id as string;
  await c.query(
    `INSERT INTO responder_otps (id, account_id, app_id, phone, code_hash, expires_at)
     VALUES ($1,$2,$3,$4,$5, now() + make_interval(mins => $6))`,
    [id, k.accountId, k.appId, phone, sha256(id + code), OTP_TTL_MIN],
  );
  return code;
}

/** Cek OTP; lempar 422 bila salah / kedaluwarsa / terlalu banyak percobaan. */
export async function consumeOtp(c: Db, appId: string, phone: string, code: string) {
  const r = await c.query(
    `SELECT id, code_hash, attempts, expires_at < now() AS expired FROM responder_otps
     WHERE app_id = $1 AND phone = $2 AND consumed_at IS NULL ORDER BY created_at DESC LIMIT 1 FOR UPDATE`,
    [appId, phone],
  );
  const otp = r.rows[0];
  if (!otp || otp.expired) throw new ApiError(422, 'otp_expired', 'Kode sudah kedaluwarsa. Minta kode baru.');
  if (otp.attempts >= OTP_MAX_ATTEMPTS) throw new ApiError(422, 'otp_locked', 'Terlalu banyak percobaan. Minta kode baru.');
  if (!safeEqual(otp.code_hash, sha256(otp.id + code))) {
    await c.query(`UPDATE responder_otps SET attempts = attempts + 1 WHERE id = $1`, [otp.id]);
    throw new ApiError(422, 'otp_invalid', 'Kode salah');
  }
  await c.query(`UPDATE responder_otps SET consumed_at = now() WHERE id = $1`, [otp.id]);
}

export async function createSession(
  c: Db, k: { appId: string; accountId: string }, phone: string, device: { platform?: string; fcm_token?: string | null },
): Promise<string> {
  const token = `rsp_${randomToken(32)}`;
  // Token FCM sama di sesi lama (login ulang di HP yang sama) → sesi lama ditutup supaya push tidak ganda.
  if (device.fcm_token) {
    await c.query(`UPDATE responder_sessions SET revoked_at = now() WHERE app_id = $1 AND fcm_token = $2 AND revoked_at IS NULL`,
      [k.appId, device.fcm_token]);
  }
  await c.query(
    `INSERT INTO responder_sessions (account_id, app_id, phone, token_hash, fcm_token, platform) VALUES ($1,$2,$3,$4,$5,$6)`,
    [k.accountId, k.appId, phone, sha256(token), device.fcm_token ?? null, device.platform ?? null],
  );
  return token;
}

/**
 * Middleware setelah publishableKeyAuth: header X-SOS-Responder wajib, sesi aktif di app yang sama, dan nomornya
 * masih tercantum di Nomor Darurat. Bila sudah dihapus dari semua daftar → sesi dicabut, 401 responder_not_registered.
 */
export const responderAuth: RequestHandler = async (req, _res, next) => {
  const k = req.key!;
  const token = req.get('x-sos-responder') ?? '';
  if (!token.startsWith('rsp_')) throw new ApiError(401, 'responder_auth_required', 'Header X-SOS-Responder wajib');
  const ctx = await withTenant(k.accountId, async (c) => {
    const s = await c.query(
      `UPDATE responder_sessions SET last_seen_at = now() WHERE token_hash = $1 AND app_id = $2 AND revoked_at IS NULL
       RETURNING id, phone`,
      [sha256(token), k.appId],
    );
    const row = s.rows[0];
    if (!row) return null;
    const name = await registeredName(c, k.appId, row.phone);
    if (!name) {
      await c.query(`UPDATE responder_sessions SET revoked_at = now() WHERE id = $1`, [row.id]);
      return 'unregistered' as const;
    }
    return { sessionId: row.id as string, phone: row.phone as string, name };
  });
  if (ctx === 'unregistered') throw new ApiError(401, 'responder_not_registered', 'Nomor ini sudah tidak terdaftar di Nomor Darurat');
  if (!ctx) throw new ApiError(401, 'responder_session_invalid', 'Sesi berakhir, silakan login lagi');
  req.responder = ctx;
  next();
};

/** Bentuk laporan untuk app satpam: cukup untuk menolong, tanpa IP/device pelapor. */
export function responderReport(r: any) {
  return {
    id: r.id,
    status: r.status,
    mode: r.mode,
    category: r.category,
    reporter_name: r.reporter_name ?? null,
    reporter_phone: r.reporter_phone ?? null,
    source_label: r.source_label ?? null,
    message: r.message ?? null,
    location: r.lat == null ? null : { lat: r.lat, lng: r.lng, accuracy_m: r.accuracy_m },
    created_at: r.created_at,
    acknowledged_at: r.acknowledged_at ?? null,
    resolved_at: r.resolved_at ?? null,
  };
}

export const REPORT_SELECT = `SELECT r.*, coalesce(s.label, s.source_key) AS source_label
  FROM reports r LEFT JOIN sources s ON s.id = r.source_id`;

/** SOS 7 hari terakhir yang menyebut nomor ini, terbaru dulu. */
export async function listForResponder(c: Db, appId: string, phone: string) {
  const r = await c.query(
    `${REPORT_SELECT}
     WHERE r.app_id = $1 AND r.kind = 'sos' AND r.emergency_contacts @> jsonb_build_array(jsonb_build_object('phone', $2::text))
       AND r.created_at > now() - make_interval(days => $3)
     ORDER BY r.created_at DESC LIMIT 50`,
    [appId, phone, LIST_DAYS],
  );
  return r.rows;
}

/** Satu laporan, hanya bila nomor responder ada di snapshot kontaknya (selain itu 404, tidak bocor keberadaan). */
export async function loadForResponder(c: Db, appId: string, phone: string, id: string) {
  if (!/^[0-9a-f-]{36}$/i.test(id)) throw new ApiError(404, 'not_found', 'Laporan tidak ditemukan');
  const r = await c.query(
    `${REPORT_SELECT} WHERE r.id = $1 AND r.app_id = $2 AND r.emergency_contacts @> jsonb_build_array(jsonb_build_object('phone', $3::text))`,
    [id, appId, phone],
  );
  if (!r.rows[0]) throw new ApiError(404, 'not_found', 'Laporan tidak ditemukan');
  return r.rows[0];
}

/**
 * Push SOS ke HP satpam yang nomornya ada di kontak darurat laporan. Dipanggil SETELAH commit dan tidak ditunggu
 * jalur SOS (sama seperti WhatsApp). Mode test tetap dikirim (gratis, untuk uji) dengan judul [TEST].
 * Ringkasan per laporan dicatat di timeline (type 'push').
 */
export async function dispatchSosPush(report: any, appName: string): Promise<void> {
  if (report.kind === 'pengaduan') return;
  const phones = [...new Set(((report.emergency_contacts ?? []) as { phone: string }[]).map((c) => c.phone).filter(Boolean))];
  // Nomor uji 0800 tetap dapat push: push masuk ke HP yang login, bukan WhatsApp (berguna untuk QA).
  if (!phones.length) return;
  try {
    const { sessions, sourceLabel } = await withTenant(report.account_id, async (c) => {
      const s = await c.query(
        `SELECT id, phone, fcm_token FROM responder_sessions
         WHERE app_id = $1 AND phone = ANY($2::text[]) AND revoked_at IS NULL AND fcm_token IS NOT NULL`,
        [report.app_id, phones],
      );
      const src = report.source_id ? await c.query(`SELECT coalesce(label, source_key) AS l FROM sources WHERE id = $1`, [report.source_id]) : { rows: [] };
      return { sessions: s.rows as { id: string; phone: string; fcm_token: string }[], sourceLabel: (src.rows[0]?.l ?? null) as string | null };
    });
    if (!sessions.length) return;

    const who = report.reporter_name || 'Pelapor';
    const where = [appName, sourceLabel].filter(Boolean).join(' · ');
    const msg = {
      title: `${report.mode === 'test' ? '[TEST] ' : ''}SOS DARURAT: ${who}`,
      body: `${where || 'Lokasi tidak diketahui'}. Ketuk untuk melihat lokasi.`,
      data: {
        type: 'siagasos_sos',
        report_id: String(report.id),
        reporter_name: String(who),
        place: where,
        lat: report.lat == null ? '' : String(report.lat),
        lng: report.lng == null ? '' : String(report.lng),
        created_at: new Date(report.created_at).toISOString(),
      },
    };
    const results = await Promise.all(sessions.map(async (s) => ({ s, r: await sendSosPush(s.fcm_token, msg) })));
    const dead = results.filter((x) => x.r === 'unregistered').map((x) => x.s.id);
    const sent = results.filter((x) => x.r === 'sent').length;
    const stub = results.filter((x) => x.r === 'stub').length;
    const failed = results.length - sent - stub;
    await withTenant(report.account_id, async (c) => {
      if (dead.length) await c.query(`UPDATE responder_sessions SET fcm_token = NULL WHERE id = ANY($1::uuid[])`, [dead]);
      const note = stub
        ? `Push alarm ke ${stub} HP satpam: tidak dikirim, FCM belum diatur`
        : `Push alarm terkirim ke ${sent} HP satpam${failed ? `, ${failed} gagal` : ''}`;
      await c.query(`INSERT INTO report_events (report_id, account_id, actor_kind, type, note) VALUES ($1,$2,'system','push',$3)`,
        [report.id, report.account_id, note]);
    });
  } catch (err) {
    logger.error({ err, reportId: report.id }, 'dispatchSosPush gagal');
  }
}
