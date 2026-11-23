import { describe, expect, it, vi } from 'vitest';

// Redis mati: setiap perintah gagal. Jalur SOS tidak boleh ikut gagal (CLAUDE.md: fail-open).
vi.mock('../src/redis.js', () => ({
  redis: {
    multi: () => ({ incr: () => ({ expire: () => ({ exec: () => Promise.reject(new Error('ECONNREFUSED')) }) }) }),
  },
  subscriber: () => { throw new Error('tidak dipakai di test ini'); },
}));

const { enforce, hit } = await import('../src/lib/rateLimit.js');
const { isTestNumber, mergeTargets } = await import('../src/lib/sosRecipients.js');

describe('rate limit fail-open', () => {
  it('Redis error → permintaan tetap diizinkan', async () => {
    await expect(hit('sdk:test', 1, 60)).resolves.toEqual({ ok: true, count: 0 });
    await expect(enforce('sdk:test', 1, 60)).resolves.toBeUndefined();
  });
});

describe('penerima WhatsApp SOS', () => {
  it('penerima app/source menang atas kontak pribadi bila nomor sama; nomor ganda dibuang', () => {
    const out = mergeTargets(
      [
        { name: 'Pos Satpam', phone: '6281100000001', source_id: null },
        { name: 'Kios A', phone: '6281100000002', source_id: 's1' },
        { name: 'Duplikat', phone: '6281100000001', source_id: 's1' },
      ],
      [{ name: 'Ibu', phone: '6281100000002' }, { phone: '6281100000003' }, { name: 'Kosong', phone: '' }],
    );
    expect(out).toEqual([
      { name: 'Pos Satpam', phone: '6281100000001', source: 'app' },
      { name: 'Kios A', phone: '6281100000002', source: 'source' },
      { name: 'Kontak darurat', phone: '6281100000003', source: 'personal' },
    ]);
  });
  it('nomor 0800 = nomor uji', () => {
    expect(isTestNumber('6280011112222')).toBe(true);
    expect(isTestNumber('6281211112222')).toBe(false);
  });
});
