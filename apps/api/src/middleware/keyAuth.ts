import type { RequestHandler, Request } from 'express';
import type { KeyMode } from '@siagasos/shared';
import { q } from '../db.js';
import { config } from '../config.js';
import { ApiError, forbidden } from '../lib/errors.js';
import { parseKeyPrefix, type KeyKind } from '../lib/keys.js';
import { sha256 } from '../lib/crypto.js';

export interface KeyContext {
  keyId: string;
  kind: KeyKind;
  mode: KeyMode;
  appId: string;
  appName: string;
  accountId: string;
  accountStatus: string;
  allowedOrigins: string[];
  allowedBundleIds: string[];
  sdkConfig: Record<string, unknown>;
  /** Pilar app (apps.polmas_source): umkm | warga | kantor | sekolah | komunitas, null = belum dipilih. */
  pillar: string | null;
  autoCreateSources: boolean;
  appDisabled: boolean;
  revoked: boolean;
}

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace Express {
    interface Request { key?: KeyContext }
  }
}

/** Cache in-process 30 detik → revoke, suspend, dan disable app berlaku ≤ 60 detik di semua instance. */
const cache = new Map<string, { at: number; ctx: KeyContext | null }>();

async function lookup(hash: string, kind: KeyKind): Promise<KeyContext | null> {
  const hit = cache.get(hash);
  if (hit && Date.now() - hit.at < config.keyCacheTtlMs) return hit.ctx;
  const { rows } = await q(
    `SELECT k.id, k.kind, k.mode, (k.revoked_at IS NOT NULL OR (k.expires_at IS NOT NULL AND k.expires_at < now())) AS revoked,
            a.id AS app_id, a.name AS app_name, a.account_id, a.allowed_origins, a.allowed_bundle_ids, a.sdk_config, a.polmas_source,
            a.auto_create_sources, a.disabled_at IS NOT NULL AS app_disabled, acc.status AS account_status
     FROM api_keys k JOIN apps a ON a.id = k.app_id JOIN accounts acc ON acc.id = a.account_id
     WHERE k.key_hash = $1 AND k.kind = $2`,
    [hash, kind],
  );
  const r = rows[0];
  const ctx: KeyContext | null = r
    ? {
        keyId: r.id, kind: r.kind, mode: r.mode, appId: r.app_id, appName: r.app_name, accountId: r.account_id,
        accountStatus: r.account_status, allowedOrigins: r.allowed_origins, allowedBundleIds: r.allowed_bundle_ids,
        sdkConfig: r.sdk_config ?? {}, pillar: r.polmas_source ?? null, autoCreateSources: r.auto_create_sources, appDisabled: r.app_disabled, revoked: r.revoked,
      }
    : null;
  cache.set(hash, { at: Date.now(), ctx });
  if (ctx && !ctx.revoked) q(`UPDATE api_keys SET last_used_at = now() WHERE id = $1`, [ctx.keyId]).catch(() => {});
  return ctx;
}

export function invalidateKeyCache() {
  cache.clear();
}

function checkCommon(ctx: KeyContext | null): KeyContext {
  if (!ctx || ctx.revoked) throw new ApiError(401, 'invalid_api_key', 'API key tidak valid atau sudah dicabut');
  if (ctx.appDisabled) throw forbidden('app_disabled', 'App ini dinonaktifkan oleh admin SiagaSOS');
  if (ctx.accountStatus === 'suspended' || ctx.accountStatus === 'rejected') {
    throw forbidden('account_suspended', 'Akun perusahaan tidak aktif');
  }
  if (ctx.mode === 'live' && ctx.accountStatus !== 'approved') {
    throw forbidden('account_not_approved', 'Kunci live hanya bisa dipakai setelah perusahaan disetujui. Gunakan pk_test_ selama review.');
  }
  return ctx;
}

function normalizeOrigin(o: string) {
  return o.replace(/\/+$/, '').toLowerCase();
}

/** Origin web dicek terhadap allowed_origins; app native mengirim X-SOS-Bundle. */
function checkClientOrigin(req: Request, ctx: KeyContext) {
  const origin = req.get('origin');
  const bundle = req.get('x-sos-bundle');
  if (origin) {
    const ok = ctx.allowedOrigins.some((o) => o === '*' ? ctx.mode === 'test' : normalizeOrigin(o) === normalizeOrigin(origin));
    if (!ok && !(ctx.mode === 'test' && ctx.allowedOrigins.length === 0)) {
      throw forbidden('origin_not_allowed', `Origin ${origin} tidak terdaftar di allowed_origins app ini`);
    }
  } else if (bundle) {
    if (!ctx.allowedBundleIds.includes(bundle) && !(ctx.mode === 'test' && ctx.allowedBundleIds.length === 0)) {
      throw forbidden('bundle_not_allowed', `Bundle ${bundle} tidak terdaftar di allowed_bundle_ids app ini`);
    }
  } else if (ctx.mode === 'live') {
    throw forbidden('origin_required', 'Request live wajib membawa header Origin (web) atau X-SOS-Bundle (mobile)');
  }
}

export const publishableKeyAuth: RequestHandler = async (req, _res, next) => {
  const raw = req.get('x-sos-key') ?? '';
  const p = parseKeyPrefix(raw);
  if (!p) return next(new ApiError(401, 'invalid_api_key', 'Header X-SOS-Key wajib berisi publishable key (pk_...)'));
  if (p.kind !== 'publishable') return next(new ApiError(401, 'wrong_key_type', 'Secret key tidak boleh dipakai di SDK. Gunakan pk_...'));
  const ctx = checkCommon(await lookup(sha256(raw), 'publishable'));
  checkClientOrigin(req, ctx);
  req.key = ctx;
  next();
};

export const secretKeyAuth: RequestHandler = async (req, _res, next) => {
  const raw = (req.get('authorization') ?? '').replace(/^Bearer\s+/i, '');
  const p = parseKeyPrefix(raw);
  if (!p || p.kind !== 'secret') return next(new ApiError(401, 'invalid_api_key', 'Authorization: Bearer sk_... wajib diisi'));
  req.key = checkCommon(await lookup(sha256(raw), 'secret'));
  next();
};
