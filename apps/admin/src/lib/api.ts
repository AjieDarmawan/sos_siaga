export const API_URL = (import.meta.env.VITE_API_URL as string | undefined)?.replace(/\/+$/, '') ?? 'http://localhost:4000';

// Token admin disimpan di sessionStorage (bukan localStorage): hilang saat tab ditutup, dan JWT admin juga hanya berlaku 8 jam.
const KEY = 'siagasos.admin.session';
export interface AdminSession { token: string; admin: { id: string; email: string; role: 'reviewer' | 'superadmin' } }

export const session = {
  get(): AdminSession | null {
    try { return JSON.parse(sessionStorage.getItem(KEY) ?? 'null'); } catch { return null; }
  },
  set(s: AdminSession | null) {
    try { s ? sessionStorage.setItem(KEY, JSON.stringify(s)) : sessionStorage.removeItem(KEY); } catch { /* */ }
  },
};

export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string, public details?: any) { super(message); }
}

let onExpired: (() => void) | null = null;
export const setExpiredHandler = (fn: () => void) => { onExpired = fn; };

export async function api<T = any>(path: string, opts: { method?: string; body?: unknown } = {}): Promise<T> {
  const headers: Record<string, string> = {};
  const s = session.get();
  if (s) headers.Authorization = `Bearer ${s.token}`;
  if (opts.body !== undefined) headers['Content-Type'] = 'application/json';
  let res: Response;
  try {
    res = await fetch(API_URL + path, { method: opts.method ?? (opts.body !== undefined ? 'POST' : 'GET'), headers, body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined });
  } catch {
    throw new ApiError(0, 'network_error', 'Tidak dapat terhubung ke server');
  }
  const data = res.status === 204 ? null : await res.json().catch(() => null);
  if (!res.ok) {
    if (res.status === 401 && s) onExpired?.();
    throw new ApiError(res.status, data?.error?.code ?? 'http_' + res.status, data?.error?.message ?? `Gagal (${res.status})`, data?.error?.details);
  }
  return data as T;
}
