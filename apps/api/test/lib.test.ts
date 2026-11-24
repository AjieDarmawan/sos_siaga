import { describe, expect, it } from 'vitest';
import { addBusinessDays, businessHoursBetween } from '../src/lib/businessTime.js';
import { generateKey, parseKeyPrefix } from '../src/lib/keys.js';
import { hmac, safeEqual } from '../src/lib/crypto.js';
import { signToken, sniffMime, verifyToken } from '../src/lib/storage.js';
import { signPayload } from '../src/lib/webhooks.js';

// Waktu WIB = UTC+7. 2026-11-20 = Jumat.
const wib = (s: string) => new Date(`${s}+07:00`);

describe('jam kerja (SLA review)', () => {
  it('Jumat 12:00 → Senin 12:00 = 24 jam kerja (akhir pekan tidak dihitung)', () => {
    expect(businessHoursBetween(wib('2026-11-20T12:00:00'), wib('2026-11-23T12:00:00'))).toBe(24);
  });
  it('hari kerja penuh = 24 jam', () => {
    expect(businessHoursBetween(wib('2026-11-17T00:00:00'), wib('2026-11-18T00:00:00'))).toBe(24);
  });
  it('tambah 1 hari kerja dari Jumat siang jatuh di Senin siang', () => {
    expect(addBusinessDays(wib('2026-11-20T12:00:00'), 1).toISOString()).toBe(wib('2026-11-23T12:00:00').toISOString());
  });
});

describe('kunci API', () => {
  it('format & prefix sesuai jenis/mode', () => {
    for (const [kind, mode] of [['publishable', 'live'], ['secret', 'test']] as const) {
      const k = generateKey(kind, mode);
      expect(parseKeyPrefix(k.key)).toEqual({ kind, mode });
      expect(k.key.startsWith(k.prefix)).toBe(true);
      expect(k.hash).toMatch(/^[0-9a-f]{64}$/);
    }
  });
  it('kunci acak tidak pernah sama', () => {
    expect(generateKey('publishable', 'live').key).not.toBe(generateKey('publishable', 'live').key);
  });
  it.each(['', 'pk_live_short', 'xk_live_' + 'a'.repeat(32), 'pk_prod_' + 'a'.repeat(32), 'pk_live_' + 'a'.repeat(31) + '!'])(
    'menolak %j', (k) => expect(parseKeyPrefix(k)).toBeNull(),
  );
});

describe('tanda tangan', () => {
  it('webhook: t=<ts>,v1=hmac(secret, "<ts>.<body>")', () => {
    const body = JSON.stringify({ event: 'report.created' });
    expect(signPayload('whsec_x', body, 1700000000)).toBe(`t=1700000000,v1=${hmac('whsec_x', `1700000000.${body}`)}`);
  });
  it('safeEqual', () => {
    expect(safeEqual('abc', 'abc')).toBe(true);
    expect(safeEqual('abc', 'abd')).toBe(false);
    expect(safeEqual('abc', 'abcd')).toBe(false);
  });
  it('tautan bertanda tangan: valid, diubah → 403, kedaluwarsa → 410', () => {
    const t = signToken({ doc: 'd1' }, 60);
    expect(verifyToken<{ doc: string }>(t).doc).toBe('d1');
    const [body, sig] = t.split('.');
    const forged = Buffer.from(JSON.stringify({ doc: 'd2', exp: 9e9 })).toString('base64url');
    expect(() => verifyToken(`${forged}.${sig}`)).toThrow(expect.objectContaining({ status: 403 }));
    expect(() => verifyToken(`${body}.`)).toThrow(expect.objectContaining({ status: 403 }));
    expect(() => verifyToken(signToken({ doc: 'd1' }, -10))).toThrow(expect.objectContaining({ status: 410 }));
  });
});

describe('sniffMime (dokumen onboarding)', () => {
  it('mengenali magic bytes, bukan ekstensi', () => {
    expect(sniffMime(Buffer.from('%PDF-1.7\n'))).toBe('application/pdf');
    expect(sniffMime(Buffer.from([0xff, 0xd8, 0xff, 0xe0]))).toBe('image/jpeg');
    expect(sniffMime(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0]))).toBe('image/png');
    expect(sniffMime(Buffer.from('MZ\x90\x00'))).toBeNull();
    expect(sniffMime(Buffer.from('<?php echo 1;'))).toBeNull();
  });
});
