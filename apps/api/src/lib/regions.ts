import { pool } from '../db.js';
import { config } from '../config.js';
import { logger } from '../logger.js';

/** Satu wilayah administratif (kode Kemendagri bertitik). */
export interface Region { code: string; name: string }

/** Hasil reverse geocode yang sudah dicocokkan ke tabel `wilayah`. Level yang tidak cocok = null. */
export interface RegionMatch {
  province: Region | null;
  regency: Region | null;
  district: Region | null;
  village: Region | null;
}

const CODE_RE = /^[0-9]{2}(\.[0-9]{2}(\.[0-9]{2})?)?$/;
export const isParentCode = (s: string) => CODE_RE.test(s);

/** Anak langsung dari `parent` (tanpa parent = daftar provinsi), urut nama. Tabel referensi publik, tanpa RLS. */
export async function childRegions(parent: string | null): Promise<Region[]> {
  const r = await pool.query<Region>(
    parent
      ? `SELECT kode AS code, nama AS name FROM wilayah WHERE parent = $1 ORDER BY nama`
      : `SELECT kode AS code, nama AS name FROM wilayah WHERE parent IS NULL ORDER BY nama`,
    parent ? [parent] : [],
  );
  return r.rows;
}

/** Semua desa/kelurahan di satu kabupaten/kota (untuk alamat geocoder yang tidak menyebut kecamatan). */
export async function villagesOfRegency(regencyCode: string): Promise<Region[]> {
  const r = await pool.query<Region>(
    `SELECT kode AS code, nama AS name FROM wilayah WHERE level = 4 AND kode LIKE $1 ORDER BY kode`,
    [`${regencyCode}.%`],
  );
  return r.rows;
}

/** Nama dinormalisasi untuk dicocokkan: tanpa awalan jenis wilayah, huruf kecil, hanya huruf/angka. */
export function normRegion(s: string): string {
  return s
    .toLowerCase()
    .replace(/^(provinsi|prov\.|daerah khusus ibukota|daerah khusus ibu kota|daerah khusus|daerah istimewa|dki|diy|kabupaten administrasi|kabupaten|kab\.|kota administrasi|kota adm\.|kota|kecamatan|kec\.|kelurahan|kel\.|desa|distrik)\s+/, '')
    .replace(/[^a-z0-9]/g, '');
}

type Kind = 'kota' | 'kabupaten' | null;
const kindOf = (s: string): Kind => (/^kota\b/i.test(s) ? 'kota' : /^(kabupaten|kab\.)/i.test(s) ? 'kabupaten' : null);

interface Candidate { text: string; hint: Kind }

/**
 * Pilih anak yang namanya cocok dengan salah satu kandidat teks dari geocoder. Bila "Bandung" cocok dengan
 * Kota Bandung & Kabupaten Bandung, pakai petunjuk jenis (teks berawalan "Kota"/"Kabupaten", atau field `city` vs
 * `county`), kalau tetap ragu ambil yang pertama muncul di kandidat.
 */
export function pickRegion(children: Region[], candidates: Candidate[]): Region | null {
  for (const cand of candidates) {
    const n = normRegion(cand.text);
    if (!n) continue;
    const hits = children.filter((c) => normRegion(c.name) === n);
    if (hits.length === 0) continue;
    if (hits.length === 1) return hits[0]!;
    const hint = cand.hint ?? kindOf(cand.text);
    return hits.find((h) => kindOf(h.name) === hint) ?? hits[0]!;
  }
  return null;
}

const LEVEL_KEYS: Record<1 | 2 | 3 | 4, [string, Kind][]> = {
  1: [['state', null], ['province', null], ['region', null]],
  2: [['city', 'kota'], ['county', 'kabupaten'], ['regency', 'kabupaten'], ['municipality', null], ['town', null]],
  3: [['city_district', null], ['district', null], ['subdistrict', null], ['municipality', null], ['suburb', null], ['town', null], ['village', null]],
  4: [['village', null], ['suburb', null], ['hamlet', null], ['neighbourhood', null], ['quarter', null], ['city_block', null]],
};

/**
 * Kandidat nama untuk satu level dari alamat Nominatim: field yang lazim untuk level itu dulu, lalu potongan
 * display_name (Nominatim tidak konsisten menaruh kecamatan/desa Indonesia di field yang sama). Kandidat hanya
 * dicocokkan ke anak dari induk yang sudah cocok, jadi salah pilih antar-level kecil kemungkinannya.
 */
export function addressCandidates(address: Record<string, string>, displayName: string, level: 1 | 2 | 3 | 4): Candidate[] {
  const out: Candidate[] = [];
  const push = (text: string | undefined, hint: Kind) => {
    if (text && !out.some((o) => o.text === text)) out.push({ text, hint });
  };
  for (const [k, hint] of LEVEL_KEYS[level]) push(address[k], hint);
  for (const part of displayName.split(',')) push(part.trim(), null);
  return out;
}

/** Cocokkan alamat geocoder ke tabel wilayah, turun level demi level (provinsi → desa). */
export async function matchAddress(
  address: Record<string, string>,
  displayName = '',
  children = childRegions,
  villages = villagesOfRegency,
): Promise<RegionMatch> {
  const c = (level: 1 | 2 | 3 | 4) => addressCandidates(address, displayName, level);
  const out: RegionMatch = { province: null, regency: null, district: null, village: null };
  out.province = pickRegion(await children(null), c(1));
  if (!out.province) return out;
  out.regency = pickRegion(await children(out.province.code), c(2));
  if (!out.regency) return out;
  out.district = pickRegion(await children(out.regency.code), c(3));
  if (!out.district) {
    // Kecamatan tidak disebut (mis. hanya village + county): cari desanya di seluruh kabupaten, kecamatan ikut kodenya.
    const vs = await villages(out.regency.code);
    const v = pickRegion(vs, c(4));
    if (!v || vs.filter((x) => normRegion(x.name) === normRegion(v.name)).length > 1) return out;
    const parent = v.code.slice(0, v.code.lastIndexOf('.'));
    out.district = (await children(out.regency.code)).find((d) => d.code === parent) ?? null;
    out.village = out.district ? v : null;
    return out;
  }
  out.village = pickRegion(await children(out.district.code), c(4));
  return out;
}

const cache = new Map<string, { at: number; value: RegionMatch }>();
const CACHE_MAX = 2000;
const CACHE_TTL_MS = 24 * 3600_000;

/**
 * Koordinat → wilayah. Koordinat dibulatkan 3 desimal (±100 m) sebelum dikirim ke geocoder, jadi lokasi persis
 * pengguna tidak keluar dari server. GEOCODER_URL kosong = fitur nonaktif (null).
 */
export async function reverseRegion(lat: number, lng: number): Promise<RegionMatch | null> {
  if (!config.geocoderUrl) return null;
  const la = lat.toFixed(3);
  const lo = lng.toFixed(3);
  const key = `${la},${lo}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < CACHE_TTL_MS) return hit.value;

  const url = new URL(config.geocoderUrl);
  url.searchParams.set('format', 'jsonv2');
  url.searchParams.set('lat', la);
  url.searchParams.set('lon', lo);
  url.searchParams.set('zoom', '18');
  url.searchParams.set('addressdetails', '1');
  url.searchParams.set('accept-language', 'id');
  let body: { address?: Record<string, string>; display_name?: string };
  try {
    const res = await fetch(url, { headers: { 'User-Agent': config.geocoderUserAgent, Accept: 'application/json' }, signal: AbortSignal.timeout(6000) });
    if (!res.ok) throw new Error(`geocoder ${res.status}`);
    body = (await res.json()) as typeof body;
  } catch (e) {
    logger.warn({ err: (e as Error).message }, 'reverse geocode gagal');
    return null;
  }
  const value = await matchAddress(body.address ?? {}, body.display_name ?? '');
  if (cache.size >= CACHE_MAX) cache.delete(cache.keys().next().value!);
  cache.set(key, { at: Date.now(), value });
  return value;
}
