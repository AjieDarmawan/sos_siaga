import { Router } from 'express';
import { z } from 'zod';
import { authenticator } from 'otplib';
import { ACCOUNT_STATUSES, REVIEW_DECISIONS } from '@siagasos/shared';
import { pool, q, withPlatform } from '../db.js';
import { config } from '../config.js';
import { ApiError, notFound, parse } from '../lib/errors.js';
import { signAdmin, verifyPassword } from '../lib/auth.js';
import { enforce } from '../lib/rateLimit.js';
import { audit } from '../lib/audit.js';
import { sendStatusEmail } from '../lib/mailer.js';
import { getPrivate, signToken, verifyToken } from '../lib/storage.js';
import { businessHoursBetween } from '../lib/businessTime.js';
import { invalidateKeyCache } from '../middleware/keyAuth.js';
import { requireAdmin } from '../middleware/portalAuth.js';
import { requiredDocs } from './portal/onboarding.js';

export const adminRouter = Router();

adminRouter.post('/auth/login', async (req, res) => {
  const b = parse(z.object({ email: z.string().email(), password: z.string().min(1), totp: z.string().regex(/^\d{6}$/) }), req.body);
  await enforce(`admin-login:${b.email.toLowerCase()}`, 5, 900, 'too_many_attempts');
  const a = (await q(`SELECT * FROM platform_admins WHERE email = $1`, [b.email])).rows[0];
  // 2FA wajib: password DAN kode TOTP harus benar
  if (!a || !(await verifyPassword(b.password, a.password_hash)) || !authenticator.check(b.totp, a.totp_secret)) {
    throw new ApiError(401, 'invalid_credentials', 'Email, password, atau kode 2FA salah');
  }
  await audit({ actorKind: 'platform_admin', actorId: a.id, action: 'admin.login', ip: req.ip });
  res.json({ token: signAdmin(a.id, a.role), admin: { id: a.id, email: a.email, role: a.role } });
});

// File dokumen lewat signed URL 5 menit. Tidak butuh header (bisa dibuka di tab baru); token sudah terikat ke dokumen & admin.
adminRouter.get('/files/:token', async (req, res) => {
  const t = verifyToken<{ doc: string; adm: string }>(req.params.token!);
  const doc = await withPlatform(async (c) => (await c.query(`SELECT * FROM account_documents WHERE id = $1`, [t.doc])).rows[0]);
  if (!doc) throw notFound('Dokumen');
  const data = await getPrivate(doc.storage_key);
  res.set({
    'Content-Type': doc.mime_type,
    'Content-Disposition': `inline; filename="${doc.doc_type}${doc.mime_type === 'application/pdf' ? '.pdf' : ''}"`,
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
  });
  res.send(data);
});

adminRouter.use(requireAdmin);

// F-23: antrean review, terlama dulu, dengan peringatan SLA (F-27). status=all = semua perusahaan terdaftar.
adminRouter.get('/accounts', async (req, res) => {
  const f = parse(z.object({ status: z.enum([...ACCOUNT_STATUSES, 'all']).default('pending_review'), search: z.string().trim().max(100).optional() }), req.query);
  const { rows } = await q(
    `SELECT a.id, a.legal_name, a.entity_type, a.nib, a.industry, a.est_users, a.status, a.risk_flags, a.submitted_at, a.created_at,
            a.approved_at, u.full_name AS pic_name, u.email AS pic_email
     FROM accounts a LEFT JOIN LATERAL (SELECT full_name, email FROM users WHERE account_id = a.id AND role = 'owner' ORDER BY created_at LIMIT 1) u ON true
     WHERE a.nib NOT LIKE '%:archived:%'
       AND ($1 = 'all' OR a.status = $1) AND ($1 <> 'pending_review' OR a.submitted_at IS NOT NULL)
       AND ($2::text IS NULL OR a.legal_name ILIKE '%' || $2 || '%' OR a.nib = $2 OR u.email ILIKE '%' || $2 || '%')
     ORDER BY CASE WHEN $1 = 'all' THEN a.created_at END DESC, coalesce(a.submitted_at, a.created_at) ASC LIMIT 200`,
    [f.status, f.search || null],
  );
  // jumlah per status untuk tab; pending_review dipisah: sudah diajukan (antrean) vs masih melengkapi dokumen
  const counts = (await q(
    `SELECT CASE WHEN status = 'pending_review' AND submitted_at IS NULL THEN 'drafting' ELSE status END AS k, count(*)::int AS n
     FROM accounts WHERE nib NOT LIKE '%:archived:%' GROUP BY 1`)).rows;
  const now = new Date();
  res.json({
    data: rows.map((r) => {
      const hours = r.status === 'pending_review' && r.submitted_at ? businessHoursBetween(new Date(r.submitted_at), now) : null;
      return { ...r, waiting_business_hours: hours && Math.round(hours * 10) / 10, sla_warning: hours != null && hours > config.reviewSlaWarnHours };
    }),
    counts: Object.fromEntries(counts.map((c) => [c.k, c.n])),
  });
});

adminRouter.get('/accounts/:id', async (req, res) => {
  const id = req.params.id!;
  const acc = (await q(`SELECT * FROM accounts WHERE id = $1`, [id])).rows[0];
  if (!acc) throw notFound('Akun');
  const out = await withPlatform(async (c) => ({
    documents: (await c.query(
      `SELECT id, doc_type, original_name, mime_type, size_bytes, sha256, review_state, review_note, uploaded_at, superseded_at
       FROM account_documents WHERE account_id = $1 ORDER BY superseded_at NULLS FIRST, uploaded_at`, [id])).rows,
  }));
  const users = (await q(`SELECT id, email, full_name, phone, position, role, email_verified_at, created_at FROM users WHERE account_id = $1`, [id])).rows;
  const reviews = (await q(
    `SELECT r.decision, r.reason, r.checklist, r.created_at, p.email AS reviewer FROM account_reviews r JOIN platform_admins p ON p.id = r.reviewer_id
     WHERE r.account_id = $1 ORDER BY r.created_at DESC`, [id])).rows;
  const apps = (await q(`SELECT id, name, disabled_at, created_at FROM apps WHERE account_id = $1`, [id])).rows;
  res.json({
    account: acc,
    required_documents: requiredDocs(acc.entity_type, acc.pic_is_director),
    ...out,
    users,
    reviews,
    apps,
    verification_checklist: [
      { key: 'nib_oss', label: 'NIB valid di OSS (oss.go.id) dan nama badan usaha cocok' },
      { key: 'npwp_match', label: 'NPWP cocok dengan nama & alamat' },
      { key: 'akta_ahu', label: 'Akta + SK Kemenkumham terdaftar di AHU Online (PT/Yayasan)' },
      { key: 'ktp_pic', label: 'Nama di KTP sesuai data PIC' },
      { key: 'surat_kuasa', label: 'Surat kuasa ditandatangani direksi yang tercantum di akta (jika PIC bukan direksi)' },
      { key: 'usage_reasonable', label: 'Rencana penggunaan dan jumlah pengguna wajar' },
    ],
  });
});

adminRouter.get('/documents/:id/url', async (req, res) => {
  const a = req.admin!;
  const doc = await withPlatform(async (c) => (await c.query(`SELECT id, account_id FROM account_documents WHERE id = $1`, [req.params.id])).rows[0]);
  if (!doc) throw notFound('Dokumen');
  const token = signToken({ doc: doc.id, adm: a.id }, 300);
  await audit({ accountId: doc.account_id, actorKind: 'platform_admin', actorId: a.id, action: 'document.url_issued', targetType: 'document', targetId: doc.id, ip: req.ip });
  res.json({ url: `${config.publicApiUrl}/admin/files/${token}`, expires_in: 300 });
});

// Tandai dokumen ok / perlu diunggah ulang (dipakai bersama keputusan needs_revision, F-26)
adminRouter.patch('/documents/:id', async (req, res) => {
  const b = parse(z.object({ review_state: z.enum(['pending', 'ok', 'rejected']), review_note: z.string().max(500).optional() }), req.body);
  if (b.review_state === 'rejected' && !b.review_note) throw new ApiError(422, 'note_required', 'Catatan wajib untuk dokumen yang ditolak');
  const doc = await withPlatform(async (c) =>
    (await c.query(`UPDATE account_documents SET review_state = $2, review_note = $3 WHERE id = $1 AND superseded_at IS NULL RETURNING *`,
      [req.params.id, b.review_state, b.review_note ?? null])).rows[0]);
  if (!doc) throw notFound('Dokumen');
  await audit({ accountId: doc.account_id, actorKind: 'platform_admin', actorId: req.admin!.id, action: 'document.reviewed', targetType: 'document', targetId: doc.id, detail: b });
  res.json({ id: doc.id, review_state: doc.review_state, review_note: doc.review_note });
});

const TRANSITIONS: Record<string, { from: string[]; to: string }> = {
  approved: { from: ['pending_review'], to: 'approved' },
  needs_revision: { from: ['pending_review'], to: 'needs_revision' },
  rejected: { from: ['pending_review', 'needs_revision'], to: 'rejected' },
  suspended: { from: ['approved'], to: 'suspended' },
  reinstated: { from: ['suspended'], to: 'approved' },
};

// F-24 / F-28: keputusan review; alasan wajib untuk revisi/tolak/bekukan
adminRouter.post('/accounts/:id/decision', async (req, res) => {
  const a = req.admin!;
  const b = parse(z.object({ decision: z.enum(REVIEW_DECISIONS), reason: z.string().max(2000).optional(), checklist: z.record(z.boolean()).optional() }), req.body);
  if (['needs_revision', 'rejected', 'suspended'].includes(b.decision) && !b.reason?.trim()) {
    throw new ApiError(422, 'reason_required', 'Alasan wajib diisi untuk keputusan ini');
  }
  const t = TRANSITIONS[b.decision]!;
  const c = await pool.connect();
  let pic: string | undefined;
  try {
    await c.query('BEGIN');
    await c.query(`SELECT set_config('app.platform', 'on', true)`);
    const acc = (await c.query(`SELECT * FROM accounts WHERE id = $1 FOR UPDATE`, [req.params.id])).rows[0];
    if (!acc) throw notFound('Akun');
    if (!t.from.includes(acc.status)) throw new ApiError(409, 'invalid_transition', `Tidak bisa ${b.decision} dari status ${acc.status}`);
    if (b.decision === 'needs_revision') {
      const flagged = await c.query(`SELECT 1 FROM account_documents WHERE account_id = $1 AND superseded_at IS NULL AND review_state = 'rejected'`, [acc.id]);
      if (!flagged.rows[0]) throw new ApiError(422, 'no_documents_flagged', 'Tandai minimal satu dokumen sebagai rejected sebelum meminta revisi');
    }
    await c.query(
      `UPDATE accounts SET status = $2, status_note = $3, updated_at = now(),
         approved_at = CASE WHEN $2 = 'approved' THEN coalesce(approved_at, now()) ELSE approved_at END,
         rejected_at = CASE WHEN $2 = 'rejected' THEN now() ELSE rejected_at END,
         submitted_at = CASE WHEN $2 = 'needs_revision' THEN NULL ELSE submitted_at END
       WHERE id = $1`,
      [acc.id, t.to, b.reason ?? null],
    );
    if (b.decision === 'approved') {
      await c.query(`UPDATE account_documents SET review_state = 'ok' WHERE account_id = $1 AND superseded_at IS NULL AND review_state = 'pending'`, [acc.id]);
    }
    if (b.decision === 'rejected' || b.decision === 'suspended') {
      // semua kunci nonaktif; cache key ≤ 30 detik → berlaku ≤ 60 detik di semua instance
      await c.query(`UPDATE api_keys SET revoked_at = now() WHERE revoked_at IS NULL AND app_id IN (SELECT id FROM apps WHERE account_id = $1)`, [acc.id]);
    }
    await c.query(`INSERT INTO account_reviews (account_id, reviewer_id, decision, reason, checklist) VALUES ($1,$2,$3,$4,$5)`,
      [acc.id, a.id, b.decision, b.reason ?? null, b.checklist ? JSON.stringify(b.checklist) : null]);
    await audit({ accountId: acc.id, actorKind: 'platform_admin', actorId: a.id, action: `account.${b.decision}`, targetType: 'account', targetId: acc.id, detail: { reason: b.reason, from: acc.status } }, c);
    pic = (await c.query(`SELECT email FROM users WHERE account_id = $1 AND role = 'owner' ORDER BY created_at LIMIT 1`, [acc.id])).rows[0]?.email;
    await c.query('COMMIT');
  } catch (e) {
    await c.query('ROLLBACK').catch(() => {});
    throw e;
  } finally {
    c.release();
  }
  invalidateKeyCache();
  if (pic) sendStatusEmail(pic, t.to, b.reason); // F-25
  res.json({ account_id: req.params.id, status: t.to });
});

// F-19: nonaktifkan app yang menyalahgunakan layanan
adminRouter.post('/apps/:id/disable', async (req, res) => {
  const { reason } = parse(z.object({ reason: z.string().min(3).max(500) }), req.body);
  const { rows } = await q(`UPDATE apps SET disabled_at = now(), disabled_reason = $2 WHERE id = $1 RETURNING id, account_id`, [req.params.id, reason]);
  if (!rows[0]) throw notFound('App');
  invalidateKeyCache();
  await audit({ accountId: rows[0].account_id, actorKind: 'platform_admin', actorId: req.admin!.id, action: 'app.disabled', targetType: 'app', targetId: rows[0].id, detail: { reason } });
  res.json({ id: rows[0].id, disabled: true });
});

adminRouter.post('/apps/:id/enable', async (req, res) => {
  const { rows } = await q(`UPDATE apps SET disabled_at = NULL, disabled_reason = NULL WHERE id = $1 RETURNING id, account_id`, [req.params.id]);
  if (!rows[0]) throw notFound('App');
  invalidateKeyCache();
  await audit({ accountId: rows[0].account_id, actorKind: 'platform_admin', actorId: req.admin!.id, action: 'app.enabled', targetType: 'app', targetId: rows[0].id });
  res.json({ id: rows[0].id, disabled: false });
});

adminRouter.get('/stats', async (_req, res) => {
  const accounts = await q(`SELECT status, count(*)::int AS n FROM accounts GROUP BY status`);
  const reports = await withPlatform((c) => c.query(
    `SELECT mode, status, count(*)::int AS n FROM reports WHERE created_at > now() - interval '30 days' GROUP BY mode, status`));
  res.json({ accounts: accounts.rows, reports_30d: reports.rows });
});
