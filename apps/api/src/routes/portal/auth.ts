import { Router, type RequestHandler } from 'express';
import { z } from 'zod';
import { ENTITY_TYPES } from '@siagasos/shared';
import { pool, q } from '../../db.js';
import { config } from '../../config.js';
import { ApiError, forbidden, parse } from '../../lib/errors.js';
import { hashPassword, isFreeEmail, signPortal, verifyPassword } from '../../lib/auth.js';
import { randomToken, sha256 } from '../../lib/crypto.js';
import { sendMail, sendStatusEmail } from '../../lib/mailer.js';
import { enforce } from '../../lib/rateLimit.js';
import { LOGIN_ALLOWED, requireUser } from '../../middleware/portalAuth.js';

export const portalAuthRouter = Router();

const password = z.string().min(8, 'Password minimal 8 karakter').max(128);
const phone = z.string().regex(/^\+?[0-9 ()-]{6,20}$/, 'Nomor telepon tidak valid');

const registerSchema = z.object({
  company: z.object({
    legal_name: z.string().min(3).max(200),
    entity_type: z.enum(ENTITY_TYPES),
    nib: z.string().regex(/^\d{13}$/, 'NIB terdiri dari 13 digit'),
    npwp: z.string().transform((s) => s.replace(/[.\-\s]/g, '')).pipe(z.string().regex(/^\d{15,16}$/, 'NPWP 15 atau 16 digit')),
    address: z.string().min(10).max(500),
    phone,
    website: z.string().url().max(200).optional(),
    industry: z.string().min(2).max(80),
    est_users: z.coerce.number().int().min(1).max(10_000_000),
    usage_plan: z.string().min(10).max(1000),
  }),
  pic: z.object({
    full_name: z.string().min(2).max(120),
    email: z.string().email().max(200).transform((s) => s.toLowerCase()),
    phone,
    position: z.string().min(2).max(80),
    is_director: z.boolean(),
    password,
  }),
  accept_terms: z.literal(true, { errorMap: () => ({ message: 'Syarat & ketentuan wajib disetujui' }) }),
});

function verifyLink(token: string) {
  return `${config.portalUrl}/verify-email?token=${token}`;
}

/** Buat token sekali pakai; kembalikan token mentah (yang di DB hanya hash-nya). */
type Queryable = { query: (text: string, params?: any[]) => Promise<any> };
async function issueEmailToken(c: Queryable, p: { userId: string | null; accountId: string; purpose: 'verify_email' | 'invite'; email?: string; role?: string; hours: number }) {
  const token = randomToken();
  await c.query(
    `INSERT INTO email_tokens (token_hash, user_id, account_id, purpose, email, role, expires_at) VALUES ($1,$2,$3,$4,$5,$6, now() + make_interval(hours => $7))`,
    [sha256(token), p.userId, p.accountId, p.purpose, p.email ?? null, p.role ?? null, p.hours],
  );
  return token;
}
export { issueEmailToken };

// POST /portal/auth/register — buat akun perusahaan (pending_email) + user PIC (owner)
portalAuthRouter.post('/register', async (req, res) => {
  await enforce(`register:${req.ip}`, config.isProd ? 5 : 100, 3600);
  const { company: co, pic } = parse(registerSchema, req.body);

  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const prev = await c.query(`SELECT id, status, rejected_at FROM accounts WHERE nib = $1 FOR UPDATE`, [co.nib]);
    if (prev.rows[0]) {
      const p = prev.rows[0];
      const canReapply = p.status === 'rejected' && p.rejected_at && Date.now() - new Date(p.rejected_at).getTime() > config.reapplyAfterDays * 86400_000;
      if (!canReapply) {
        throw new ApiError(409, p.status === 'rejected' ? 'reapply_too_soon' : 'nib_registered',
          p.status === 'rejected' ? `NIB ini ditolak; daftar ulang bisa dilakukan ${config.reapplyAfterDays} hari setelah penolakan` : 'NIB ini sudah terdaftar');
      }
      // Arsipkan akun lama (riwayat review tetap ada untuk audit), bebaskan NIB & email.
      await c.query(`UPDATE accounts SET nib = nib || ':archived:' || id WHERE id = $1`, [p.id]);
      await c.query(`UPDATE users SET email = email || '.archived.' || id, disabled_at = now() WHERE account_id = $1`, [p.id]);
    }
    const flags = isFreeEmail(pic.email) ? ['free_email_domain'] : [];
    const acc = await c.query(
      `INSERT INTO accounts (legal_name, entity_type, nib, npwp, address, phone, website, industry, est_users, usage_plan, pic_is_director, risk_flags)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING id, status`,
      [co.legal_name, co.entity_type, co.nib, co.npwp, co.address, co.phone, co.website ?? null, co.industry, co.est_users, co.usage_plan, pic.is_director, flags],
    );
    const accountId = acc.rows[0].id;
    const user = await c.query(
      `INSERT INTO users (account_id, email, password_hash, full_name, phone, position, role) VALUES ($1,$2,$3,$4,$5,$6,'owner') RETURNING id`,
      [accountId, pic.email, await hashPassword(pic.password), pic.full_name, pic.phone, pic.position],
    );
    const token = await issueEmailToken(c, { userId: user.rows[0].id, accountId, purpose: 'verify_email', hours: 48 });
    await c.query('COMMIT');

    sendMail(pic.email, 'Verifikasi email SiagaSOS', `Halo ${pic.full_name},\n\nKlik tautan berikut untuk verifikasi email:\n${verifyLink(token)}\n\nTautan berlaku 48 jam.`);
    res.status(201).json({
      account_id: accountId,
      status: 'pending_email',
      risk_flags: flags,
      ...(config.isProd ? {} : { dev_verification_token: token }),
    });
  } catch (e) {
    await c.query('ROLLBACK').catch(() => {});
    if ((e as any).code === '23505' && String((e as any).constraint).includes('email')) {
      throw new ApiError(409, 'email_registered', 'Email ini sudah terdaftar');
    }
    throw e;
  } finally {
    c.release();
  }
});

// POST /portal/auth/verify-email — pending_email → pending_review; kunci test langsung tersedia (F-29)
portalAuthRouter.post('/verify-email', async (req, res) => {
  const { token } = parse(z.object({ token: z.string().min(10) }), req.body);
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const t = await c.query(
      `UPDATE email_tokens SET used_at = now() WHERE token_hash = $1 AND purpose = 'verify_email' AND used_at IS NULL AND expires_at > now()
       RETURNING user_id, account_id`,
      [sha256(token)],
    );
    if (!t.rows[0]) throw new ApiError(400, 'invalid_token', 'Tautan verifikasi tidak valid atau kedaluwarsa');
    const { user_id, account_id } = t.rows[0];
    await c.query(`UPDATE users SET email_verified_at = coalesce(email_verified_at, now()) WHERE id = $1`, [user_id]);
    const a = await c.query(
      `UPDATE accounts SET status = 'pending_review', updated_at = now() WHERE id = $1 AND status = 'pending_email' RETURNING status`,
      [account_id],
    );
    const u = await c.query(`SELECT id, email, account_id FROM users WHERE id = $1`, [user_id]);
    await c.query('COMMIT');
    const acc = await q(`SELECT status FROM accounts WHERE id = $1`, [account_id]);
    if (a.rows[0]) sendStatusEmail(u.rows[0].email, 'pending_review');
    res.json({ verified: true, account_status: acc.rows[0].status, token: signPortal(user_id, u.rows[0].account_id) });
  } catch (e) {
    await c.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    c.release();
  }
});

portalAuthRouter.post('/resend-verification', async (req, res) => {
  const { email } = parse(z.object({ email: z.string().email() }), req.body);
  await enforce(`resend:${email.toLowerCase()}`, 3, 3600);
  const { rows } = await q(`SELECT id, account_id, full_name FROM users WHERE email = $1 AND email_verified_at IS NULL`, [email]);
  if (rows[0]) {
    const token = await issueEmailToken(pool, { userId: rows[0].id, accountId: rows[0].account_id, purpose: 'verify_email', hours: 48 });
    sendMail(email, 'Verifikasi email SiagaSOS', `Halo ${rows[0].full_name},\n\n${verifyLink(token)}`);
  }
  res.json({ sent: true }); // jangan bocorkan apakah email terdaftar
});

portalAuthRouter.post('/login', async (req, res) => {
  const body = parse(z.object({ email: z.string().email(), password: z.string().min(1) }), req.body);
  await enforce(`login:${body.email.toLowerCase()}`, 10, 900, 'too_many_attempts');
  const { rows } = await q(
    `SELECT u.*, a.status AS account_status, a.status_note, a.legal_name FROM users u JOIN accounts a ON a.id = u.account_id WHERE u.email = $1`,
    [body.email],
  );
  const u = rows[0];
  if (!u || u.disabled_at || !(await verifyPassword(body.password, u.password_hash))) {
    throw new ApiError(401, 'invalid_credentials', 'Email atau password salah');
  }
  if (!u.email_verified_at) throw forbidden('email_not_verified', 'Verifikasi email Anda terlebih dahulu');
  if (!LOGIN_ALLOWED.has(u.account_status)) {
    throw new ApiError(403, `account_${u.account_status}`,
      u.account_status === 'rejected' ? 'Pendaftaran perusahaan ditolak' : 'Akun perusahaan dibekukan', { note: u.status_note });
  }
  res.json({
    token: signPortal(u.id, u.account_id),
    user: { id: u.id, email: u.email, full_name: u.full_name, role: u.role },
    account: { id: u.account_id, legal_name: u.legal_name, status: u.account_status, limited: u.account_status !== 'approved' },
  });
});

// POST /portal/auth/accept-invite — responder/admin undangan membuat password
portalAuthRouter.post('/accept-invite', async (req, res) => {
  const body = parse(z.object({ token: z.string().min(10), full_name: z.string().min(2).max(120), password, phone: phone.optional() }), req.body);
  const c = await pool.connect();
  try {
    await c.query('BEGIN');
    const t = await c.query(
      `UPDATE email_tokens SET used_at = now() WHERE token_hash = $1 AND purpose = 'invite' AND used_at IS NULL AND expires_at > now()
       RETURNING account_id, email, role`,
      [sha256(body.token)],
    );
    if (!t.rows[0]) throw new ApiError(400, 'invalid_token', 'Undangan tidak valid, sudah dipakai, atau dicabut');
    const { account_id, email, role } = t.rows[0];
    const u = await c.query(
      `INSERT INTO users (account_id, email, password_hash, full_name, phone, role, email_verified_at) VALUES ($1,$2,$3,$4,$5,$6, now()) RETURNING id`,
      [account_id, email, await hashPassword(body.password), body.full_name, body.phone ?? null, role],
    );
    await c.query('COMMIT');
    res.status(201).json({ token: signPortal(u.rows[0].id, account_id) });
  } catch (e) {
    await c.query('ROLLBACK').catch(() => {});
    if ((e as any).code === '23505') throw new ApiError(409, 'email_registered', 'Email sudah terdaftar');
    throw e;
  } finally {
    c.release();
  }
});

export const meHandler: RequestHandler = async (req, res) => {
  const u = req.user!;
  const { rows } = await q(`SELECT id, legal_name, status, status_note, plan FROM accounts WHERE id = $1`, [u.accountId]);
  res.json({ user: { id: u.id, email: u.email, full_name: u.fullName, role: u.role }, account: { ...rows[0], limited: u.limited } });
};
portalAuthRouter.get('/me', requireUser, meHandler);
