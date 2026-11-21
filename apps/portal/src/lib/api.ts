export const API_URL = (import.meta.env.VITE_API_URL as string | undefined)?.replace(/\/+$/, '') ?? 'http://localhost:4000';

const TOKEN_KEY = 'siagasos.portal.token';

export const tokenStore = {
  get(): string | null {
    try { return localStorage.getItem(TOKEN_KEY); } catch { return null; }
  },
  set(t: string | null) {
    try { t ? localStorage.setItem(TOKEN_KEY, t) : localStorage.removeItem(TOKEN_KEY); } catch { /* mode privat */ }
  },
};

export class ApiError extends Error {
  constructor(public status: number, public code: string, message: string, public details?: any) {
    super(message);
  }
  /** Pesan validasi dari `ZodError.flatten()` (`details.fieldErrors`), digabung jadi satu kalimat. */
  get detailMessage(): string {
    const f = this.details?.fieldErrors as Record<string, string[]> | undefined;
    const msgs = [...(this.details?.formErrors ?? []), ...Object.values(f ?? {}).flat()];
    return msgs.length ? `${this.message}: ${msgs.join('; ')}` : this.message;
  }
}

let onUnauthorized: (() => void) | null = null;
export const setUnauthorizedHandler = (fn: () => void) => { onUnauthorized = fn; };

export async function api<T = any>(path: string, opts: { method?: string; body?: unknown; form?: FormData; auth?: boolean } = {}): Promise<T> {
  const headers: Record<string, string> = {};
  const token = tokenStore.get();
  if (opts.auth !== false && token) headers.Authorization = `Bearer ${token}`;
  let body: BodyInit | undefined;
  if (opts.form) body = opts.form;
  else if (opts.body !== undefined) { headers['Content-Type'] = 'application/json'; body = JSON.stringify(opts.body); }

  let res: Response;
  try {
    res = await fetch(API_URL + path, { method: opts.method ?? (body ? 'POST' : 'GET'), headers, body });
  } catch {
    throw new ApiError(0, 'network_error', 'Tidak dapat terhubung ke server. Periksa koneksi Anda.');
  }
  if (res.status === 204) return undefined as T;
  const data = await res.json().catch(() => null);
  if (!res.ok) {
    const e = data?.error ?? {};
    if (res.status === 401 && opts.auth !== false && token) onUnauthorized?.();
    throw new ApiError(res.status, e.code ?? 'http_' + res.status, e.message ?? `Permintaan gagal (${res.status})`, e.details);
  }
  return data as T;
}

/** Unduh file dengan header Authorization (mis. ekspor CSV). */
export async function download(path: string, fallbackName: string) {
  const res = await fetch(API_URL + path, { headers: { Authorization: `Bearer ${tokenStore.get() ?? ''}` } });
  if (!res.ok) throw new ApiError(res.status, 'download_failed', 'Gagal mengunduh file');
  const blob = await res.blob();
  const name = /filename="([^"]+)"/.exec(res.headers.get('content-disposition') ?? '')?.[1] ?? fallbackName;
  const url = URL.createObjectURL(blob);
  const a = Object.assign(document.createElement('a'), { href: url, download: name });
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}
