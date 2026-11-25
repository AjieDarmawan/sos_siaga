import { pool, withPlatform } from '../db.js';
import { hashPassword } from '../lib/auth.js';
import { PK_ROLES, normPhone, type PkRole } from '../lib/polmas.js';

/**
 * Buat / perbarui akun Polmas Keamanan (fase 1 tanpa pendaftaran mandiri).
 *   PK_PASSWORD='rahasia123' pnpm pk:user <nomor> "<nama>" <peran> [kode_kecamatan] ["unit"]
 * Contoh: PK_PASSWORD=... pnpm pk:user 081234567890 "Aiptu Joko" bhabinkamtibmas 32.71.03 "Polsek Bogor Tengah"
 * Menjalankan lagi untuk nomor yang sama menambah peran (multi-peran) dan mengganti password bila PK_PASSWORD diisi.
 */
async function main() {
  const [phoneArg, name, role, kec, unit] = process.argv.slice(2);
  const phone = normPhone(phoneArg ?? '');
  if (!phone || !name || !PK_ROLES.includes(role as PkRole)) {
    throw new Error(`Pemakaian: pnpm pk:user <nomor> "<nama>" <${PK_ROLES.join('|')}> [kode_kecamatan] ["unit"]`);
  }
  if (role === 'bhabinkamtibmas' && !kec) throw new Error('bhabinkamtibmas wajib punya kode kecamatan, mis. 32.71.03');
  const pw = process.env.PK_PASSWORD;
  if (pw !== undefined && pw.length < 8) throw new Error('PK_PASSWORD minimal 8 karakter');
  await withPlatform(async (c) => {
    if (kec) {
      const w = (await c.query(`SELECT level FROM wilayah WHERE kode = $1`, [kec])).rows[0];
      if (!w || w.level !== 3) throw new Error(`${kec} bukan kode kecamatan`);
    }
    let user = (await c.query(`SELECT id FROM pk_users WHERE phone = $1`, [phone])).rows[0];
    if (!user) {
      if (!pw) throw new Error('Akun baru: isi PK_PASSWORD');
      user = (await c.query(`INSERT INTO pk_users (phone, name, password_hash) VALUES ($1,$2,$3) RETURNING id`, [phone, name, await hashPassword(pw)])).rows[0];
    } else {
      await c.query(`UPDATE pk_users SET name = $2 WHERE id = $1`, [user.id, name]);
      if (pw) await c.query(`UPDATE pk_users SET password_hash = $2, failed_logins = 0, locked_until = NULL WHERE id = $1`, [user.id, await hashPassword(pw)]);
    }
    // UNIQUE tidak menangkap kecamatan NULL, jadi cek manual.
    const upd = await c.query(
      `UPDATE pk_user_roles SET unit = $4 WHERE user_id = $1 AND role = $2 AND kecamatan_code IS NOT DISTINCT FROM $3`,
      [user.id, role, kec ?? null, unit ?? null]);
    if (!upd.rowCount) {
      await c.query(`INSERT INTO pk_user_roles (user_id, role, kecamatan_code, unit) VALUES ($1,$2,$3,$4)`, [user.id, role, kec ?? null, unit ?? null]);
    }
  });
  console.log(`✔ ${phone} ${name} · ${role}${kec ? ` · ${kec}` : ''}`);
  await pool.end();
}

main().catch(async (e) => {
  console.error(e.message ?? e);
  await pool.end();
  process.exit(1);
});
