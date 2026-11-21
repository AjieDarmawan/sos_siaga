import { authenticator } from 'otplib';
import { pool } from '../db.js';
import { hashPassword } from '../lib/auth.js';

/**
 * Buat admin platform: pnpm create-admin <email> <password> [reviewer|superadmin]
 * Mencetak otpauth:// URL untuk didaftarkan ke Google Authenticator / 1Password.
 */
async function main() {
  const [email, password, role = 'reviewer'] = process.argv.slice(2);
  if (!email || !password || password.length < 12) {
    console.error('usage: create-admin <email> <password(min 12)> [reviewer|superadmin]');
    process.exit(1);
  }
  const secret = authenticator.generateSecret();
  await pool.query(
    `INSERT INTO platform_admins (email, password_hash, totp_secret, role) VALUES ($1,$2,$3,$4)
     ON CONFLICT (email) DO UPDATE SET password_hash = EXCLUDED.password_hash, totp_secret = EXCLUDED.totp_secret, role = EXCLUDED.role`,
    [email, await hashPassword(password), secret, role],
  );
  console.log(`admin ${email} (${role}) siap`);
  console.log(`TOTP secret : ${secret}`);
  console.log(`otpauth URL : ${authenticator.keyuri(email, 'SiagaSOS Admin', secret)}`);
  await pool.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
