import { afterEach, describe, expect, it, vi } from 'vitest';
import { SiagaSOS, SiagaSOSError } from '../src/index';

const report = (over: Record<string, unknown> = {}) => ({
  id: '11111111-1111-4111-8111-111111111111', status: 'open', mode: 'test', category: 'medis',
  created_at: new Date().toISOString(), acknowledged_at: null, resolved_at: null, status_message: 'Laporan terkirim.', ...over,
});

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

afterEach(() => vi.unstubAllGlobals());

describe('@siagasos/js', () => {
  it('menolak kunci yang bukan publishable', () => {
    expect(() => SiagaSOS.init({ apiKey: 'sk_live_xxx' })).toThrow(SiagaSOSError);
    expect(SiagaSOS.init({ apiKey: 'pk_test_abc', liveLocation: false }).mode).toBe('test');
  });

  it('mengirim laporan dengan Idempotency-Key dan X-SOS-Key', async () => {
    const fetchMock = vi.fn(async () => json(201, report()));
    vi.stubGlobal('fetch', fetchMock);
    const sos = SiagaSOS.init({ apiKey: 'pk_test_abc', baseUrl: 'http://api', sourceKey: 'web', liveLocation: false, pollIntervalMs: 60_000 });
    const r = await sos.trigger({ category: 'medis' });
    expect(r.id).toBe(report().id);
    const post = (fetchMock.mock.calls as unknown as [string, RequestInit][]).find(([, i]) => i.method === 'POST')!;
    const headers = post[1].headers as Record<string, string>;
    expect(headers['X-SOS-Key']).toBe('pk_test_abc');
    expect(headers['Idempotency-Key']).toMatch(/^[0-9a-f-]{36}$/);
    expect(JSON.parse(post[1].body as string)).toMatchObject({ source_key: 'web', category: 'medis', device: { platform: 'web' } });
    sos.destroy();
  });

  it('antrian offline: gagal jaringan → queued → retry memakai Idempotency-Key yang sama', async () => {
    vi.useFakeTimers();
    const keys: string[] = [];
    let n = 0;
    vi.stubGlobal('fetch', vi.fn(async (url: string, init: RequestInit) => {
      if (init.method === 'POST') {
        keys.push((init.headers as Record<string, string>)['Idempotency-Key']!);
        if (n++ === 0) throw new TypeError('Failed to fetch');
        return json(201, report());
      }
      return json(200, report());
    }));
    const sos = SiagaSOS.init({ apiKey: 'pk_test_abc', baseUrl: 'http://api', liveLocation: false, pollIntervalMs: 60_000 });
    const sent = vi.fn();
    sos.on('sent', sent);
    const r = await sos.trigger();
    expect(r.status).toBe('queued');
    expect(r.id).toBeNull();
    await vi.advanceTimersByTimeAsync(2100);
    expect(sent).toHaveBeenCalledOnce();
    expect(keys).toHaveLength(2);
    expect(keys[0]).toBe(keys[1]);
    sos.destroy();
    vi.useRealTimers();
  });

  it('error permanen (4xx) dilempar dan tidak di-retry', async () => {
    vi.stubGlobal('fetch', vi.fn(async () => json(403, { error: { code: 'origin_not_allowed', message: 'x' } })));
    const sos = SiagaSOS.init({ apiKey: 'pk_test_abc', baseUrl: 'http://api', liveLocation: false });
    await expect(sos.trigger()).rejects.toMatchObject({ code: 'origin_not_allowed', status: 403 });
    expect(sos.activeReports).toHaveLength(0);
    sos.destroy();
  });

  it('polling meneruskan perubahan status lewat event "status"', async () => {
    vi.useFakeTimers();
    vi.stubGlobal('fetch', vi.fn(async (_u: string, init: RequestInit) =>
      init.method === 'POST' ? json(201, report()) : json(200, report({ status: 'acknowledged', status_message: 'Tim menuju lokasi' }))));
    const sos = SiagaSOS.init({ apiKey: 'pk_test_abc', baseUrl: 'http://api', liveLocation: false, pollIntervalMs: 4000 });
    const statuses: string[] = [];
    sos.on('status', (r) => statuses.push(r.status));
    await sos.trigger();
    await vi.advanceTimersByTimeAsync(4100);
    expect(statuses).toEqual(['open', 'acknowledged']);
    sos.destroy();
    vi.useRealTimers();
  });
});
