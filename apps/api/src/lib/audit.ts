import { q, type Db } from '../db.js';

export interface AuditEntry {
  accountId?: string | null;
  actorKind: 'user' | 'platform_admin' | 'system' | 'server';
  actorId?: string | null;
  action: string;
  targetType?: string;
  targetId?: string;
  detail?: unknown;
  ip?: string | null;
}

export function audit(e: AuditEntry, c?: Db) {
  const sql = `INSERT INTO audit_logs (account_id, actor_kind, actor_id, action, target_type, target_id, detail, ip)
               VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`;
  const p = [e.accountId ?? null, e.actorKind, e.actorId ?? null, e.action, e.targetType ?? null, e.targetId ?? null,
    e.detail ? JSON.stringify(e.detail) : null, e.ip ?? null];
  return c ? c.query(sql, p) : q(sql, p);
}
