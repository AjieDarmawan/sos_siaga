import { createHash, randomBytes } from 'node:crypto';
import { withPlatform, type Db } from '../db.js';
import { logger } from '../logger.js';
import { reverseRegion } from './regions.js';

/**
 * Polmas Keamanan: aplikasi penerima SOS & laporan dari aplikasi sumber Polmas Digital (apps.polmas_source).
 * Semua akses lintas tenant lewat withPlatform(); pembatasan per kecamatan/peran dilakukan di query (lihat visibleWhere).
 */

export const PK_ROLES = ['penerima', 'warga', 'kantor', 'umkm', 'sekolah', 'komunitas', 'bhabinkamtibmas'] as const;
export type PkRole = (typeof PK_ROLES)[number];
export const SOURCE_LABEL: Record<string, string> = {
  warga: 'Polmas Warga', kantor: 'Polmas Kantor', umkm: 'Polmas UMKM', sekolah: 'Polmas Sekolah', komunitas: 'Polmas Komunitas',
};
export const ROLE_LABEL: Record<PkRole, string> = {
  penerima: 'Penerima darurat', warga: 'Warga', kantor: 'Kantor', umkm: 'UMKM', sekolah: 'Sekolah', komunitas: 'Komunitas', bhabinkamtibmas: 'Bhabinkamtibmas',
};

export const SESSION_TTL_H = 12;
/** Batas waktu respons pertama untuk menandai laporan terlambat (usulan, menunggu SLA resmi). */
export const SLA_MIN = { sos: 15, pengaduan: 24 * 60 } as const;

export interface PkArea {
  province?: { code: string; name: string } | null;
  regency?: { code: string; name: string } | null;
  district?: { code: string; name: string } | null;
  village?: { code: string; name: string } | null;
}

export interface PkContext {
  sessionId: string;
  userId: string;
  phone: string;
  name: string;
  isDemo: boolean;
  area: PkArea | null;
  areaLat: number | null;
  areaLng: number | null;
  role: { id: string; role: PkRole; kecamatan_code: string | null; kelurahan_code: string | null; unit: string | null };
}

export const newSessionToken = () => `pks_${randomBytes(24).toString('base64url')}`;
export const hashToken = (t: string) => createHash('sha256').update(t).digest('hex');

/** 08… / +62… / 62… → 62xxxxxxxx. Null bila bukan nomor Indonesia yang masuk akal. */
export function normPhone(p: string): string | null {
  let d = p.replace(/[^0-9]/g, '');
  if (d.startsWith('0')) d = '62' + d.slice(1);
  else if (d.startsWith('8')) d = '62' + d;
  return /^62[0-9]{8,13}$/.test(d) ? d : null;
}

export const isOfficer = (pk: PkContext) => pk.role.role === 'bhabinkamtibmas';
/** Peran yang boleh menanggapi: Bhabinkamtibmas (kecamatannya) dan penerima Nomor Darurat (laporan yang memanggil nomornya). */
export const canRespondAny = (pk: PkContext) => pk.role.role === 'bhabinkamtibmas' || pk.role.role === 'penerima';
export const isContactOf = (r: { emergency_contacts?: unknown }, phone: string) =>
  Array.isArray(r.emergency_contacts) && r.emergency_contacts.some((c: any) => c?.phone === phone);
/** Boleh menanggapi laporan ini: nomornya dipanggil, atau Bhabinkamtibmas di kecamatan kejadian (app sumber berbagi). */
export function canRespondTo(pk: PkContext, r: { emergency_contacts?: unknown; kecamatan_code?: string | null; polmas_source?: string | null }) {
  if (!canRespondAny(pk)) return false;
  if (isContactOf(r, pk.phone)) return true;
  return isOfficer(pk) && !!r.polmas_source && !!r.kecamatan_code && r.kecamatan_code === scopeOf(pk);
}
/** Kecamatan yang laporannya ditampilkan: wilayah tugas peran, atau wilayah yang dikonfirmasi saat login. */
export const scopeOf = (pk: PkContext): string | null => pk.role.kecamatan_code ?? pk.area?.district?.code ?? null;

/** Status tampilan PRD (Darurat/Baru → Diterima → Diverifikasi → Ditangani → Selesai). */
export type PkStatus = 'baru' | 'diterima' | 'diverifikasi' | 'ditangani' | 'selesai' | 'tidak_valid' | 'dibatalkan';
export function pkStatus(r: { status: string; verified_at?: unknown }): PkStatus {
  switch (r.status) {
    case 'open': return 'baru';
    case 'acknowledged': return r.verified_at ? 'diverifikasi' : 'diterima';
    case 'in_progress': return 'ditangani';
    case 'resolved': return 'selesai';
    case 'false_alarm': return 'tidak_valid';
    default: return 'dibatalkan';
  }
}

/** Filter status dari aplikasi → kondisi SQL (tanpa input pengguna di string). */
export const STATUS_SQL: Record<string, string> = {
  baru: `r.status = 'open'`,
  diproses: `r.status IN ('acknowledged','in_progress')`,
  diterima: `r.status = 'acknowledged' AND r.verified_at IS NULL`,
  diverifikasi: `r.status = 'acknowledged' AND r.verified_at IS NOT NULL`,
  ditangani: `r.status = 'in_progress'`,
  selesai: `r.status = 'resolved'`,
  tidak_valid: `r.status = 'false_alarm'`,
};

/** Join standar laporan Polmas Keamanan: app sumber, source, nama wilayah. */
export const PK_FROM = `
  FROM reports r
  JOIN apps a ON a.id = r.app_id
  LEFT JOIN sources s ON s.id = r.source_id
  LEFT JOIN wilayah wk ON wk.kode = r.kecamatan_code
  LEFT JOIN wilayah wl ON wl.kode = r.kelurahan_code`;

/**
 * Syarat dasar: laporan live dari app aktif. Laporan yang memanggil nomor pengguna (Nomor Darurat) selalu boleh;
 * tampilan per kecamatan hanya dari app yang ditandai apps.polmas_source (persetujuan berbagi), lihat visibleWhere.
 */
export const PK_BASE = `r.mode = 'live' AND a.disabled_at IS NULL`;

/**
 * Kondisi "laporan ini terlihat oleh pengguna": di kecamatannya, ATAU nomornya tercatat sebagai kontak darurat SOS,
 * ATAU dia pelapornya, ATAU dia pernah menanggapinya. Parameter: $phone (62xx), $scope (kode kecamatan atau null),
 * $user (uuid). Nomor parameter diberikan pemanggil supaya bisa digabung dengan filter lain.
 */
export function visibleWhere(p: { phone: number; scope: number; user: number }) {
  return `(
    (a.polmas_source IS NOT NULL AND r.kecamatan_code IS NOT NULL AND r.kecamatan_code = $${p.scope})
    OR r.emergency_contacts @> jsonb_build_array(jsonb_build_object('phone', $${p.phone}::text))
    OR pk_norm_phone(r.reporter_phone) = $${p.phone}
    OR EXISTS (SELECT 1 FROM pk_responses x WHERE x.report_id = r.id AND x.user_id = $${p.user})
  )`;
}

/** "Saya": laporan saya, laporan yang memanggil nomor saya, atau yang pernah saya tanggapi. */
export function mineWhere(p: { phone: number; user: number }) {
  return `(
    pk_norm_phone(r.reporter_phone) = $${p.phone}
    OR r.emergency_contacts @> jsonb_build_array(jsonb_build_object('phone', $${p.phone}::text))
    OR EXISTS (SELECT 1 FROM pk_responses x WHERE x.report_id = r.id AND x.user_id = $${p.user})
  )`;
}

export const maskName = (n: string | null | undefined) =>
  !n ? 'Warga' : n.split(/\s+/).filter(Boolean).map((w) => (w.length <= 1 ? w : w[0] + '•'.repeat(Math.min(w.length - 1, 4)))).join(' ');

const round3 = (v: number) => Math.round(v * 1000) / 1000;

/** Bentuk satu laporan untuk aplikasi. Identitas & lokasi persis hanya untuk petugas, pelapor sendiri, dan kontak daruratnya. */
export function serializePk(r: any, pk: PkContext, media?: { image: number; video: number; audio: number }) {
  const own = r.reporter_phone_norm === pk.phone;
  const contact = isContactOf(r, pk.phone);
  const full = isOfficer(pk) || own || contact;
  const cd = r.complaint_details ?? null;
  return {
    id: r.id,
    kind: r.kind === 'pengaduan' ? 'laporan' : 'sos',
    category: r.category,
    title: cd?.title ?? null,
    message: r.message ?? cd?.description ?? null,
    status: pkStatus(r),
    status_raw: r.status,
    source: r.polmas_source,
    source_label: SOURCE_LABEL[r.polmas_source] ?? r.app_name,
    app_name: r.app_name,
    source_place: r.source_label ?? r.source_alamat ?? null,
    location_text: cd?.location_text ?? r.source_alamat ?? null,
    kecamatan: r.kecamatan_code ? { code: r.kecamatan_code, name: r.kecamatan_name } : null,
    kelurahan: r.kelurahan_code ? { code: r.kelurahan_code, name: r.kelurahan_name } : null,
    location: r.lat == null ? null : full ? { lat: r.lat, lng: r.lng, accuracy_m: r.accuracy_m } : { lat: round3(r.lat), lng: round3(r.lng), accuracy_m: 100 },
    reporter: { name: full ? r.reporter_name ?? 'Tanpa nama' : maskName(r.reporter_name), phone: full ? r.reporter_phone ?? null : null, is_me: own },
    is_contact: contact,
    created_at: r.created_at,
    acknowledged_at: r.acknowledged_at,
    verified_at: r.verified_at,
    resolved_at: r.resolved_at,
    occurred_at: cd?.occurred_at ?? null,
    media: media ?? { image: r.n_image ?? 0, video: r.n_video ?? 0, audio: r.n_audio ?? 0 },
    last_response: r.last_action ? { action: r.last_action, officer: r.last_officer, note: r.last_note, created_at: r.last_response_at } : null,
    is_demo: r.app_name?.includes('(Demo)') ?? false,
  };
}

/** Kolom SELECT standar untuk serializePk. */
export const PK_COLUMNS = `
  r.*, pk_norm_phone(r.reporter_phone) AS reporter_phone_norm,
  a.name AS app_name, a.polmas_source, s.label AS source_label, s.alamat AS source_alamat,
  wk.nama AS kecamatan_name, wl.nama AS kelurahan_name,
  (SELECT count(*)::int FROM report_media m WHERE m.report_id = r.id AND m.status = 'ready' AND m.kind = 'image') AS n_image,
  (SELECT count(*)::int FROM report_media m WHERE m.report_id = r.id AND m.status = 'ready' AND m.kind = 'video') AS n_video,
  (SELECT count(*)::int FROM report_media m WHERE m.report_id = r.id AND m.status = 'ready' AND m.kind = 'audio') AS n_audio,
  (SELECT m.storage_key FROM report_media m WHERE m.report_id = r.id AND m.status = 'ready' AND m.kind = 'image' ORDER BY m.created_at LIMIT 1) AS thumb_key,
  lr.action AS last_action, lr.officer AS last_officer, lr.note AS last_note, lr.created_at AS last_response_at`;
export const PK_LAST_RESPONSE = `
  LEFT JOIN LATERAL (SELECT action, officer, note, created_at FROM pk_responses x WHERE x.report_id = r.id ORDER BY created_at DESC LIMIT 1) lr ON true`;

export async function audit(c: Db, userId: string | null, action: string, reportId: string | null, detail: unknown, ip?: string) {
  await c.query(`INSERT INTO pk_audit (user_id, action, report_id, detail, ip) VALUES ($1,$2,$3,$4,$5)`,
    [userId, action, reportId, detail == null ? null : JSON.stringify(detail), ip ?? null]);
}

// ---------------------------------------------------------------- Nomor Darurat → akun & peran

export interface ContactRow {
  name: string; role: string | null; area: PkArea | null; app_name: string; source_label: string | null; reporter_name: string | null;
}

/** Semua baris Nomor Darurat aktif untuk nomor ini, lintas app (commerceOS, tata-warga, …). */
export async function contactRows(c: Db, phone: string): Promise<ContactRow[]> {
  return (await c.query<ContactRow>(
    `SELECT e.name, e.role, e.area, a.name AS app_name, s.label AS source_label, e.reporter_name
     FROM emergency_contacts e JOIN apps a ON a.id = e.app_id LEFT JOIN sources s ON s.id = e.source_id
     WHERE e.phone = $1 AND e.active AND a.disabled_at IS NULL ORDER BY e.updated_at DESC`, [phone])).rows;
}

const isBhabin = (role: string | null) => !!role && /bhabin/i.test(role);

/**
 * Turunkan peran dari Nomor Darurat (setiap login): satu peran `penerima` (unit = ringkasan jabatan & tempat), plus
 * `bhabinkamtibmas` per kecamatan bila jabatan kontak mengandung "Bhabin" dan wilayahnya diisi. Peran buatan admin
 * tidak disentuh. Peran kontak yang sudah tidak didukung dilepas, kecuali yang sedang dipakai sesi aktif.
 */
export async function syncContactRoles(c: Db, userId: string, phone: string) {
  const rows = await contactRows(c, phone);
  const want: { role: PkRole; kec: string | null; unit: string }[] = [];
  if (rows.length) {
    const labels = [...new Set(rows.map((r) => [r.role, r.source_label ?? r.reporter_name ?? r.app_name].filter(Boolean).join(' · ')))];
    const unit = labels.length > 2 ? `${labels.slice(0, 2).join(', ')} +${labels.length - 2}` : labels.join(', ');
    want.push({ role: 'penerima', kec: null, unit: unit.slice(0, 120) });
  }
  for (const r of rows) {
    const kec = r.area?.district?.code;
    if (isBhabin(r.role) && kec && !want.some((w) => w.role === 'bhabinkamtibmas' && w.kec === kec)) {
      want.push({ role: 'bhabinkamtibmas', kec, unit: (r.source_label ?? `Kec. ${r.area?.district?.name ?? ''}`).slice(0, 120) });
    }
  }
  const all = (await c.query(`SELECT id, role, kecamatan_code, from_contact FROM pk_user_roles WHERE user_id = $1`, [userId])).rows;
  const have = all.filter((x) => x.from_contact);
  for (const w of want) {
    // Peran yang sama sudah dibuat admin → biarkan (unit dari admin lebih tepat), jangan duplikat.
    if (all.some((x) => !x.from_contact && x.role === w.role && x.kecamatan_code === w.kec)) continue;
    const h = have.find((x) => x.role === w.role && x.kecamatan_code === w.kec);
    if (h) {
      await c.query(`UPDATE pk_user_roles SET unit = $2 WHERE id = $1`, [h.id, w.unit]);
    } else {
      await c.query(
        `INSERT INTO pk_user_roles (user_id, role, kecamatan_code, unit, from_contact) VALUES ($1,$2,$3,$4,true)`, [userId, w.role, w.kec, w.unit]);
    }
  }
  const stale = have.filter((h) => !want.some((w) => w.role === h.role && w.kec === h.kecamatan_code)).map((h) => h.id);
  if (stale.length) {
    await c.query(
      `DELETE FROM pk_user_roles r WHERE r.id = ANY($1::uuid[])
         AND NOT EXISTS (SELECT 1 FROM pk_sessions s WHERE s.role_id = r.id AND s.revoked_at IS NULL AND s.expires_at > now())`, [stale]);
  }
  return rows;
}

// ---------------------------------------------------------------- worker wilayah

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * Isi kecamatan/kelurahan laporan dari koordinat (Nominatim lewat reverseRegion, ±100 m). Di luar jalur SOS:
 * laporan sudah tersimpan & terkirim ke dashboard tenant sebelum ini berjalan. Gagal = dicoba lagi 10 menit kemudian
 * selama laporan < 1 hari.
 */
export async function fillReportAreas(limit = 5): Promise<number> {
  const rows = await withPlatform((c) => c.query<{ id: string; lat: number; lng: number }>(
    `SELECT r.id, r.lat, r.lng FROM reports r JOIN apps a ON a.id = r.app_id
     WHERE r.lat IS NOT NULL AND r.kecamatan_code IS NULL AND r.mode = 'live' AND a.polmas_source IS NOT NULL
       AND (r.area_checked_at IS NULL OR (r.area_checked_at < now() - interval '10 minutes' AND r.created_at > now() - interval '1 day'))
     ORDER BY r.area_checked_at NULLS FIRST, r.created_at DESC LIMIT $1`, [limit]).then((r) => r.rows));
  let filled = 0;
  for (const [i, r] of rows.entries()) {
    if (i > 0) await sleep(1100); // kebijakan Nominatim: maks. 1 permintaan/detik
    const m = await reverseRegion(r.lat, r.lng).catch(() => null);
    await withPlatform((c) => c.query(
      `UPDATE reports SET area_checked_at = now(), kecamatan_code = $2, kelurahan_code = $3, area_source = CASE WHEN $2::text IS NULL THEN NULL ELSE 'gps' END
       WHERE id = $1 AND kecamatan_code IS NULL`,
      [r.id, m?.district?.code ?? null, m?.village?.code ?? null]));
    if (m?.district) filled++;
  }
  return filled;
}

export function startPolmasWorker(intervalMs = 5000) {
  let busy = false;
  const t = setInterval(async () => {
    if (busy) return;
    busy = true;
    try {
      const n = await fillReportAreas();
      if (n) logger.info({ n }, 'polmas: wilayah laporan diisi');
    } catch (err) {
      logger.error({ err }, 'polmas worker error');
    } finally {
      busy = false;
    }
  }, intervalMs);
  t.unref();
  return () => clearInterval(t);
}
