import type { RequestHandler } from 'express';
import { q } from '../db.js';
import { ApiError, forbidden } from '../lib/errors.js';
import { verifyAdmin, verifyPortal } from '../lib/auth.js';

export interface PortalUser {
  id: string;
  email: string;
  fullName: string;
  role: 'owner' | 'admin' | 'responder';
  accountId: string;
  accountStatus: string;
  /** true selama pending_review / needs_revision: hanya status, unggah ulang, dan mode test. */
  limited: boolean;
}
export interface PlatformAdmin { id: string; email: string; role: 'reviewer' | 'superadmin' }

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request { user?: PortalUser; admin?: PlatformAdmin }
  }
}

function bearer(req: Parameters<RequestHandler>[0]) {
  const h = req.get('authorization');
  if (h?.startsWith('Bearer ')) return h.slice(7);
  // EventSource tidak bisa set header → SSE boleh pakai ?access_token=
  if (req.path.endsWith('/stream') && typeof req.query.access_token === 'string') return req.query.access_token;
  return null;
}

export const LOGIN_ALLOWED = new Set(['pending_review', 'needs_revision', 'approved']);

export const requireUser: RequestHandler = async (req, _res, next) => {
  const t = bearer(req);
  if (!t) return next(new ApiError(401, 'unauthenticated', 'Login diperlukan'));
  let claims;
  try {
    claims = verifyPortal(t);
  } catch {
    return next(new ApiError(401, 'invalid_token', 'Sesi tidak valid atau kedaluwarsa'));
  }
  const { rows } = await q(
    `SELECT u.id, u.email, u.full_name, u.role, u.account_id, u.disabled_at, a.status
     FROM users u JOIN accounts a ON a.id = u.account_id WHERE u.id = $1`,
    [claims.sub],
  );
  const u = rows[0];
  if (!u || u.disabled_at) return next(new ApiError(401, 'invalid_token', 'User tidak aktif'));
  if (!LOGIN_ALLOWED.has(u.status)) return next(forbidden(`account_${u.status}`, 'Akun perusahaan tidak dapat mengakses portal'));
  req.user = {
    id: u.id, email: u.email, fullName: u.full_name, role: u.role, accountId: u.account_id,
    accountStatus: u.status, limited: u.status !== 'approved',
  };
  next();
};

export const requireApprovedAccount: RequestHandler = (req, _res, next) =>
  next(req.user?.limited ? forbidden('account_not_approved', 'Fitur ini aktif setelah perusahaan disetujui') : undefined);

export const requireRole = (...roles: PortalUser['role'][]): RequestHandler => (req, _res, next) =>
  next(req.user && roles.includes(req.user.role) ? undefined : forbidden('insufficient_role', 'Peran Anda tidak diizinkan'));

export const requireAdmin: RequestHandler = async (req, _res, next) => {
  const t = req.get('authorization')?.replace(/^Bearer\s+/i, '');
  if (!t) return next(new ApiError(401, 'unauthenticated', 'Login admin diperlukan'));
  try {
    const c = verifyAdmin(t);
    const { rows } = await q(`SELECT id, email, role FROM platform_admins WHERE id = $1`, [c.sub]);
    if (!rows[0]) throw new Error();
    req.admin = rows[0];
    next();
  } catch {
    next(new ApiError(401, 'invalid_token', 'Sesi admin tidak valid'));
  }
};

export const requireSuperadmin: RequestHandler = (req, _res, next) =>
  next(req.admin?.role === 'superadmin' ? undefined : forbidden('insufficient_role', 'Hanya superadmin'));
