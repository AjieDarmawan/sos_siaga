import { q } from '../db.js';
import { randomBase62, sha256 } from './crypto.js';

/** Kunci mitra: ptk_live_<40 base62>. Disimpan hanya hash-nya; kunci utuh dikembalikan sekali ke pembuat. */
export function generatePartnerKey() {
  const key = 'ptk_live_' + randomBase62(40);
  return { key, prefix: key.slice(0, 13), hash: sha256(key) };
}

export const isPartnerKey = (s: string) => /^ptk_live_[0-9A-Za-z]{40}$/.test(s);

/** Kode wilayah bertitik (32, 32.71, 32.71.01, 32.71.01.1001), sama dengan wilayah.kode. */
export const isRegionCode = (s: string) => /^[0-9]{2}(\.[0-9]{2}(\.[0-9]{2}(\.[0-9]{4})?)?)?$/.test(s);

/** `scope` berada di dalam `max` (sama atau lebih sempit). max kosong = nasional, semua cakupan boleh. */
export const scopeWithin = (scope: string, max: string | null) => !max || scope === max || scope.startsWith(max + '.');

/** Buat mitra baru beserta kunci pertamanya. Dipakai skrip `pnpm partner:create` dan smoke test. */
export async function createPartner(name: string, maxScope: string | null = null) {
  const p = (await q(`INSERT INTO partners (name, max_scope) VALUES ($1, $2) RETURNING id`, [name, maxScope])).rows[0];
  const k = await addPartnerKey(p.id);
  return { id: p.id as string, ...k };
}

export async function addPartnerKey(partnerId: string) {
  const g = generatePartnerKey();
  const r = (await q(`INSERT INTO partner_keys (partner_id, prefix, key_hash) VALUES ($1,$2,$3) RETURNING id`, [partnerId, g.prefix, g.hash])).rows[0];
  return { keyId: r.id as string, key: g.key, prefix: g.prefix };
}
