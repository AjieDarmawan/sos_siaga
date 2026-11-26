import { pool, q } from '../db.js';
import { addPartnerKey, createPartner, isRegionCode } from '../lib/partners.js';

/**
 * Buat mitra /partner/v1 (mis. Polmas Digital) atau tambah kunci untuk mitra yang sudah ada (nama sama):
 *   pnpm --filter @siagasos/api partner:create "Polmas Digital" [kode_wilayah_maks, mis. 32.71]
 * Kunci ptk_live_ dicetak sekali; simpan di .env.local server mitra (SIAGASOS_PARTNER_KEY).
 */
async function main() {
  const [name, maxScope] = process.argv.slice(2);
  if (!name || (maxScope && !isRegionCode(maxScope))) {
    console.error('usage: partner:create "<nama mitra>" [kode wilayah maks, mis. 32.71]');
    process.exit(1);
  }
  const found = (await q(`SELECT id, max_scope FROM partners WHERE name = $1 AND disabled_at IS NULL ORDER BY created_at LIMIT 1`, [name])).rows[0];
  const out = found ? { id: found.id, ...(await addPartnerKey(found.id)) } : await createPartner(name, maxScope ?? null);
  console.log(`${found ? 'kunci baru untuk mitra' : 'mitra dibuat'}: ${name} (${out.id}), cakupan ${found?.max_scope ?? maxScope ?? 'nasional'}`);
  console.log(`SIAGASOS_PARTNER_KEY=${out.key}`);
  await pool.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
