import type { ReportPublic, ReportStatus, SdkConfig, KeyMode } from '@siagasos/shared';
import { createQueue, type QueueItem, type Queue } from './queue';

export type { ReportPublic, ReportStatus, SdkConfig };

export const SDK_VERSION = '0.1.0';
const DEFAULT_BASE_URL = 'https://api.siagasos.id';
const TERMINAL: ReportStatus[] = ['resolved', 'cancelled', 'false_alarm'];

export interface SiagaSOSOptions {
  /** Publishable key: pk_live_... atau pk_test_... (mode test otomatis dari prefix). */
  apiKey: string;
  /** Label asal laporan, mis. "kantor-jakarta-web". */
  sourceKey?: string;
  user?: { ref?: string; name?: string; phone?: string };
  /** Kirim lokasi berkala selama laporan aktif. Default true. */
  liveLocation?: boolean;
  /** Interval polling status (ms). Default 4000 → status tampil ≤ 5 detik. */
  pollIntervalMs?: number;
  baseUrl?: string;
  /** Timeout pengambilan GPS saat trigger (ms). Default 8000. */
  locationTimeoutMs?: number;
}

export interface TriggerInput {
  category?: string;
  message?: string;
  metadata?: Record<string, unknown>;
}

/** Laporan dari sudut pandang perangkat. id null selama masih di antrian offline. */
export interface ActiveReport {
  localId: string;
  id: string | null;
  status: ReportStatus | 'queued';
  statusMessage: string | null;
  mode: KeyMode;
  category: string;
  createdAt: string;
}

export class SiagaSOSError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
    this.name = 'SiagaSOSError';
  }
}

type Events = {
  status: ActiveReport;
  queued: ActiveReport;
  sent: ActiveReport;
  error: SiagaSOSError;
};
type Listener<T> = (v: T) => void;

const uuid = () =>
  globalThis.crypto?.randomUUID?.() ??
  'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
  });

const hasWindow = typeof window !== 'undefined';

function getLocation(timeout: number): Promise<{ lat: number; lng: number; accuracy_m: number } | undefined> {
  const geo = typeof navigator !== 'undefined' ? navigator.geolocation : undefined;
  if (!geo) return Promise.resolve(undefined);
  return new Promise((resolve) => {
    const t = setTimeout(() => resolve(undefined), timeout + 500);
    geo.getCurrentPosition(
      (p) => {
        clearTimeout(t);
        resolve({ lat: p.coords.latitude, lng: p.coords.longitude, accuracy_m: Math.round(p.coords.accuracy) });
      },
      () => {
        clearTimeout(t);
        resolve(undefined); // tetap kirim tanpa lokasi
      },
      { enableHighAccuracy: true, timeout, maximumAge: 10_000 },
    );
  });
}

export class SiagaSOS {
  readonly mode: KeyMode;
  private opts: Required<Omit<SiagaSOSOptions, 'sourceKey' | 'user'>> & Pick<SiagaSOSOptions, 'sourceKey' | 'user'>;
  private listeners: { [K in keyof Events]?: Set<Listener<Events[K]>> } = {};
  private queue: Queue;
  private reports = new Map<string, ActiveReport>();
  private timers = new Map<string, ReturnType<typeof setInterval>>();
  private watchers = new Map<string, number>();
  private flushing = false;
  private retryTimer: ReturnType<typeof setTimeout> | null = null;
  private retryDelay = 2000;
  private configCache: Promise<SdkConfig> | null = null;
  private onOnline = () => this.flush();

  static init(options: SiagaSOSOptions) {
    return new SiagaSOS(options);
  }

  constructor(options: SiagaSOSOptions) {
    const m = /^pk_(live|test)_/.exec(options.apiKey ?? '');
    if (!m) throw new SiagaSOSError(0, 'invalid_api_key', 'apiKey harus publishable key (pk_live_... / pk_test_...)');
    this.mode = m[1] as KeyMode;
    this.opts = {
      liveLocation: true,
      pollIntervalMs: 4000,
      baseUrl: DEFAULT_BASE_URL,
      locationTimeoutMs: 8000,
      ...options,
    };
    this.opts.baseUrl = this.opts.baseUrl.replace(/\/+$/, '');
    this.queue = createQueue(`siagasos:${options.apiKey.slice(0, 16)}`);
    if (hasWindow) window.addEventListener('online', this.onOnline);
    void this.flush(); // kirim sisa antrian dari sesi sebelumnya
  }

  on<K extends keyof Events>(event: K, fn: Listener<Events[K]>): () => void {
    const set = (this.listeners[event] ??= new Set() as any) as Set<Listener<Events[K]>>;
    set.add(fn);
    return () => set.delete(fn);
  }

  private emit<K extends keyof Events>(event: K, v: Events[K]) {
    this.listeners[event]?.forEach((fn) => {
      try {
        (fn as Listener<Events[K]>)(v);
      } catch {
        /* listener error tidak boleh mengganggu SDK */
      }
    });
  }

  private async request<T>(method: string, path: string, body?: unknown, idem?: string): Promise<T> {
    const headers: Record<string, string> = { 'X-SOS-Key': this.opts.apiKey };
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    if (idem) headers['Idempotency-Key'] = idem;
    const res = await fetch(this.opts.baseUrl + path, { method, headers, body: body === undefined ? undefined : JSON.stringify(body), keepalive: method !== 'GET' });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      throw new SiagaSOSError(res.status, data?.error?.code ?? 'http_error', data?.error?.message ?? `HTTP ${res.status}`);
    }
    return data as T;
  }

  /** Konfigurasi app (kategori, teks tombol, durasi tahan, teks penerima). */
  getConfig(): Promise<SdkConfig> {
    return (this.configCache ??= this.request<SdkConfig>('GET', '/v1/sdk/config').catch((e) => {
      this.configCache = null;
      throw e;
    }));
  }

  /** Kirim laporan SOS. Bila offline, laporan masuk antrian dan dikirim otomatis saat sinyal kembali. */
  async trigger(input: TriggerInput = {}): Promise<ActiveReport> {
    const location = await getLocation(this.opts.locationTimeoutMs);
    const item: QueueItem = {
      localId: uuid(),
      idempotencyKey: uuid(),
      createdAt: new Date().toISOString(),
      body: {
        source_key: this.opts.sourceKey,
        category: input.category ?? 'general',
        message: input.message,
        metadata: input.metadata,
        location,
        reporter: this.opts.user,
        client_created_at: new Date().toISOString(),
        device: {
          platform: 'web',
          sdk_version: SDK_VERSION,
          browser: typeof navigator !== 'undefined' ? navigator.userAgent.slice(0, 120) : undefined,
        },
      },
    };
    const active: ActiveReport = {
      localId: item.localId,
      id: null,
      status: 'queued',
      statusMessage: 'Mengirim laporan…',
      mode: this.mode,
      category: item.body.category as string,
      createdAt: item.createdAt,
    };
    this.reports.set(item.localId, active);
    // Simpan dulu, baru kirim: laporan tidak hilang walau tab tertutup di tengah request.
    await this.queue.put(item);
    const sent = await this.send(item);
    if (!sent) {
      this.emit('queued', active);
      this.scheduleRetry();
    }
    return this.reports.get(item.localId)!;
  }

  /** true = terkirim (atau ditolak permanen), false = perlu dicoba lagi. */
  private async send(item: QueueItem): Promise<boolean> {
    try {
      const r = await this.request<ReportPublic>('POST', '/v1/sdk/reports', item.body, item.idempotencyKey);
      await this.queue.remove(item.localId);
      this.retryDelay = 2000;
      const active = this.update(item.localId, r);
      this.emit('sent', active);
      this.track(item.localId);
      return true;
    } catch (e) {
      const err = e instanceof SiagaSOSError ? e : new SiagaSOSError(0, 'network_error', (e as Error).message);
      const retryable = err.status === 0 || err.status === 408 || err.status === 429 || err.status >= 500;
      if (!retryable) {
        await this.queue.remove(item.localId);
        this.reports.delete(item.localId);
        this.emit('error', err);
        throw err;
      }
      return false;
    }
  }

  private scheduleRetry() {
    if (this.retryTimer) return;
    this.retryTimer = setTimeout(() => {
      this.retryTimer = null;
      void this.flush();
    }, this.retryDelay);
    this.retryDelay = Math.min(this.retryDelay * 2, 30_000);
  }

  /** Kirim ulang semua laporan di antrian offline. */
  async flush() {
    if (this.flushing) return;
    this.flushing = true;
    let pending = false;
    try {
      for (const item of await this.queue.all()) {
        if (!this.reports.has(item.localId)) {
          this.reports.set(item.localId, {
            localId: item.localId, id: null, status: 'queued', statusMessage: 'Menunggu sinyal…', mode: this.mode,
            category: String(item.body.category ?? 'general'), createdAt: item.createdAt,
          });
        }
        const ok = await this.send(item).catch(() => true);
        if (!ok) pending = true;
      }
    } finally {
      this.flushing = false;
    }
    if (pending) this.scheduleRetry();
  }

  private update(localId: string, r: ReportPublic): ActiveReport {
    const prev = this.reports.get(localId);
    const next: ActiveReport = {
      localId,
      id: r.id,
      status: r.status,
      statusMessage: r.status_message,
      mode: r.mode,
      category: r.category,
      createdAt: prev?.createdAt ?? r.created_at,
    };
    this.reports.set(localId, next);
    if (!prev || prev.status !== next.status || prev.id !== next.id) this.emit('status', next);
    if (TERMINAL.includes(r.status)) this.stopTracking(localId);
    return next;
  }

  /** Polling status + live location sampai laporan selesai. */
  private track(localId: string) {
    const rep = this.reports.get(localId);
    if (!rep?.id || TERMINAL.includes(rep.status as ReportStatus)) return;
    const id = rep.id;
    this.timers.set(localId, setInterval(() => {
      this.request<ReportPublic>('GET', `/v1/sdk/reports/${id}`).then((r) => this.update(localId, r)).catch(() => {});
    }, this.opts.pollIntervalMs));

    const geo = typeof navigator !== 'undefined' ? navigator.geolocation : undefined;
    if (!this.opts.liveLocation || !geo) return;
    let last = 0;
    this.getConfig()
      .then((c) => c.live_location_interval_s * 1000, () => 15_000)
      .then((interval) => {
        if (!this.timers.has(localId)) return; // sudah selesai
        const w = geo.watchPosition(
          (p) => {
            if (Date.now() - last < interval) return;
            last = Date.now();
            this.request<{ accepted: boolean }>('POST', `/v1/sdk/reports/${id}/locations`, {
              lat: p.coords.latitude, lng: p.coords.longitude, accuracy_m: Math.round(p.coords.accuracy),
              recorded_at: new Date(p.timestamp).toISOString(),
            }).then((r) => { if (!r.accepted) this.stopTracking(localId); }).catch(() => {});
          },
          () => {},
          { enableHighAccuracy: true, maximumAge: 5000 },
        );
        this.watchers.set(localId, w);
      });
  }

  private stopTracking(localId: string) {
    const t = this.timers.get(localId);
    if (t) clearInterval(t);
    this.timers.delete(localId);
    const w = this.watchers.get(localId);
    if (w !== undefined) navigator.geolocation?.clearWatch(w);
    this.watchers.delete(localId);
  }

  /** Batalkan laporan (salah pencet). Hanya bisa selama status masih open. */
  async cancel(idOrLocalId: string, reason?: string): Promise<ActiveReport | null> {
    const entry = [...this.reports.values()].find((r) => r.id === idOrLocalId || r.localId === idOrLocalId);
    if (entry && !entry.id) {
      // belum sempat terkirim: cukup hapus dari antrian
      await this.queue.remove(entry.localId);
      const cancelled = { ...entry, status: 'cancelled' as const, statusMessage: 'Laporan dibatalkan.' };
      this.reports.set(entry.localId, cancelled);
      this.emit('status', cancelled);
      return cancelled;
    }
    const id = entry?.id ?? idOrLocalId;
    const r = await this.request<ReportPublic>('POST', `/v1/sdk/reports/${id}/cancel`, { reason });
    return this.update(entry?.localId ?? id, r);
  }

  /** Ambil status terbaru sebuah laporan dari server. */
  async getReport(id: string): Promise<ReportPublic> {
    return this.request<ReportPublic>('GET', `/v1/sdk/reports/${id}`);
  }

  get activeReports(): ActiveReport[] {
    return [...this.reports.values()].filter((r) => !TERMINAL.includes(r.status as ReportStatus));
  }

  destroy() {
    for (const id of [...this.timers.keys()]) this.stopTracking(id);
    if (this.retryTimer) clearTimeout(this.retryTimer);
    if (hasWindow) window.removeEventListener('online', this.onOnline);
    this.listeners = {};
  }
}

export default SiagaSOS;
