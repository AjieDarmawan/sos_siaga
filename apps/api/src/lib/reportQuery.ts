import { z } from 'zod';
import { REPORT_STATUSES } from '@siagasos/shared';
import type { Db } from '../db.js';
import { REPORT_SELECT, fullReport } from './reports.js';
import { ApiError } from './errors.js';

const csv = <T extends z.ZodTypeAny>(item: T) =>
  z.union([z.string().transform((s) => s.split(',').filter(Boolean)), z.array(z.string())]).pipe(z.array(item));

export const listQuerySchema = z.object({
  status: csv(z.enum(REPORT_STATUSES)).optional(),
  category: csv(z.string().max(40)).optional(),
  source_key: csv(z.string().max(64)).optional(),
  app_id: z.string().uuid().optional(),
  mode: z.enum(['live', 'test']).optional(),
  from: z.string().datetime({ offset: true }).optional(),
  to: z.string().datetime({ offset: true }).optional(),
  limit: z.coerce.number().int().min(1).max(500).default(50),
  cursor: z.string().optional(),
});
export type ListQuery = z.infer<typeof listQuerySchema>;

const encodeCursor = (r: any) => Buffer.from(`${new Date(r.created_at).toISOString()}|${r.id}`).toString('base64url');
function decodeCursor(c: string) {
  const [ts, id] = Buffer.from(c, 'base64url').toString().split('|');
  if (!ts || !id || Number.isNaN(Date.parse(ts))) throw new ApiError(400, 'invalid_cursor', 'cursor tidak valid');
  return { ts, id };
}

/** RLS sudah membatasi ke akun; filter tambahan di sini. Urutan terbaru dulu, paginasi keyset. */
export async function listReports(c: Db, f: ListQuery, scope: { appId?: string; forceMode?: 'test' } = {}) {
  const where: string[] = [];
  const p: unknown[] = [];
  const add = (sql: string, v: unknown) => {
    p.push(v);
    where.push(sql.replace('?', `$${p.length}`));
  };
  if (scope.appId) add('r.app_id = ?', scope.appId);
  if (f.app_id) add('r.app_id = ?', f.app_id);
  if (scope.forceMode) add('r.mode = ?', scope.forceMode);
  else if (f.mode) add('r.mode = ?', f.mode);
  if (f.status?.length) add('r.status = ANY(?)', f.status);
  if (f.category?.length) add('r.category = ANY(?)', f.category);
  if (f.source_key?.length) add('s.source_key = ANY(?)', f.source_key);
  if (f.from) add('r.created_at >= ?', f.from);
  if (f.to) add('r.created_at < ?', f.to);
  if (f.cursor) {
    const cur = decodeCursor(f.cursor);
    p.push(cur.ts, cur.id);
    where.push(`(r.created_at, r.id) < ($${p.length - 1}::timestamptz, $${p.length}::uuid)`);
  }
  p.push(f.limit + 1);
  const { rows } = await c.query(
    `${REPORT_SELECT} ${where.length ? 'WHERE ' + where.join(' AND ') : ''} ORDER BY r.created_at DESC, r.id DESC LIMIT $${p.length}`,
    p,
  );
  const more = rows.length > f.limit;
  const page = rows.slice(0, f.limit);
  return { data: page.map(fullReport), next_cursor: more ? encodeCursor(page[page.length - 1]) : null };
}
