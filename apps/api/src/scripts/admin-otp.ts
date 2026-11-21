import { authenticator } from 'otplib';
import { pool } from '../db.js';

/** Dev saja: cetak kode 2FA saat ini untuk admin platform. pnpm admin:otp [email] */
async function main() {
  if (process.env.NODE_ENV === 'production') throw new Error('admin:otp hanya untuk development');
  const email = process.argv[2] ?? 'admin@siagasos.test';
  const { rows } = await pool.query(`SELECT totp_secret FROM platform_admins WHERE email = $1`, [email]);
  if (!rows[0]) throw new Error(`admin ${email} tidak ada (jalankan pnpm seed:demo)`);
  const left = authenticator.timeRemaining();
  console.log(`${authenticator.generate(rows[0].totp_secret)}  (${email}, berlaku ${left} dtk lagi)`);
  await pool.end();
}
main().catch(async (e) => { console.error(e.message); await pool.end().catch(() => {}); process.exit(1); });
