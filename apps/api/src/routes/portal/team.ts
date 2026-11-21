import { Router } from 'express';
import { z } from 'zod';
import { pool, q } from '../../db.js';
import { config } from '../../config.js';
import { ApiError, notFound, parse } from '../../lib/errors.js';
import { sendMail } from '../../lib/mailer.js';
import { audit } from '../../lib/audit.js';
import { requireRole, requireUser } from '../../middleware/portalAuth.js';
import { issueEmailToken } from './auth.js';

export const teamRouter = Router();
teamRouter.use(requireUser);

teamRouter.get('/', async (req, res) => {
  const u = req.user!;
  const users = await q(
    `SELECT id, email, full_name, phone, role, disabled_at, created_at FROM users WHERE account_id = $1 AND email NOT LIKE '%.archived.%' ORDER BY created_at`,
    [u.accountId],
  );
  const invites = await q(
    `SELECT token_hash AS id, email, role, expires_at, created_at FROM email_tokens
     WHERE account_id = $1 AND purpose = 'invite' AND used_at IS NULL AND expires_at > now() ORDER BY created_at`,
    [u.accountId],
  );
  res.json({ members: users.rows, pending_invites: invites.rows.map((i) => ({ ...i, id: i.id.slice(0, 16) })) });
});

// F-02: undang responder/admin via email
teamRouter.post('/invites', requireRole('owner', 'admin'), async (req, res) => {
  const u = req.user!;
  const body = parse(z.object({ email: z.string().email().transform((s) => s.toLowerCase()), role: z.enum(['admin', 'responder']) }), req.body);
  if (u.role === 'admin' && body.role === 'admin') throw new ApiError(403, 'insufficient_role', 'Hanya owner yang bisa mengundang admin');
  const exists = await q(`SELECT 1 FROM users WHERE email = $1`, [body.email]);
  if (exists.rows[0]) throw new ApiError(409, 'email_registered', 'Email sudah terdaftar di SiagaSOS');
  const token = await issueEmailToken(pool, { userId: null, accountId: u.accountId, purpose: 'invite', email: body.email, role: body.role, hours: 72 });
  sendMail(body.email, 'Undangan tim SiagaSOS',
    `${u.fullName} mengundang Anda sebagai ${body.role} di SiagaSOS.\n\nTerima undangan: ${config.portalUrl}/accept-invite?token=${token}\n\nBerlaku 72 jam.`);
  await audit({ accountId: u.accountId, actorKind: 'user', actorId: u.id, action: 'team.invited', detail: { email: body.email, role: body.role } });
  res.status(201).json({ invited: body.email, role: body.role, ...(config.isProd ? {} : { dev_invite_token: token }) });
});

teamRouter.delete('/invites/:id', requireRole('owner', 'admin'), async (req, res) => {
  const { rowCount } = await q(
    `UPDATE email_tokens SET used_at = now(), expires_at = now() WHERE account_id = $1 AND purpose = 'invite' AND used_at IS NULL AND starts_with(token_hash, $2)`,
    [req.user!.accountId, req.params.id],
  );
  if (!rowCount) throw notFound('Undangan');
  res.status(204).end();
});

teamRouter.patch('/:userId', requireRole('owner'), async (req, res) => {
  const u = req.user!;
  const body = parse(z.object({ role: z.enum(['admin', 'responder']).optional(), disabled: z.boolean().optional() }), req.body);
  if (req.params.userId === u.id) throw new ApiError(422, 'cannot_modify_self', 'Tidak bisa mengubah akun sendiri');
  const { rows } = await q(
    `UPDATE users SET role = coalesce($3, role),
       disabled_at = CASE WHEN $4::boolean IS NULL THEN disabled_at WHEN $4 THEN coalesce(disabled_at, now()) ELSE NULL END
     WHERE id = $1 AND account_id = $2 AND role <> 'owner' RETURNING id, email, role, disabled_at`,
    [req.params.userId, u.accountId, body.role ?? null, body.disabled ?? null],
  );
  if (!rows[0]) throw notFound('Anggota');
  await audit({ accountId: u.accountId, actorKind: 'user', actorId: u.id, action: 'team.updated', targetType: 'user', targetId: rows[0].id, detail: body });
  res.json(rows[0]);
});
