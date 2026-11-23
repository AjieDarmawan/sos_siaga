import { describe, expect, it } from 'vitest';
import { createReportSchema, toWhatsAppNumber } from '@siagasos/shared';

describe('toWhatsAppNumber', () => {
  it.each([
    ['0812-3456-7890', '6281234567890'],
    ['+62 812 3456 7890', '6281234567890'],
    ['6281234567890', '6281234567890'],
    ['81234567890', '6281234567890'],
    ['0800 1111 2222', '6280011112222'],
  ])('%s → %s', (input, out) => expect(toWhatsAppNumber(input)).toBe(out));

  it.each(['', '123', '+1 415 555 0100', '0812', 'bukan nomor'])('menolak %j', (input) => {
    expect(toWhatsAppNumber(input)).toBeNull();
  });
});

describe('createReportSchema', () => {
  it('SOS minimal: kind & category default', () => {
    const r = createReportSchema.parse({});
    expect(r.kind).toBe('sos');
    expect(r.category).toBe('general');
  });

  it('pengaduan wajib berisi uraian', () => {
    expect(createReportSchema.safeParse({ kind: 'pengaduan', message: 'abc' }).success).toBe(false);
    expect(createReportSchema.safeParse({ kind: 'pengaduan', message: 'Parkir liar di depan toko' }).success).toBe(true);
  });

  it('kontak darurat dinormalisasi & dibatasi 5', () => {
    const r = createReportSchema.parse({ emergency_contacts: [{ name: 'Satpam', phone: '0812 1111 2222' }] });
    expect(r.emergency_contacts?.[0].phone).toBe('6281211112222');
    const six = Array.from({ length: 6 }, (_, i) => ({ phone: `081200000${i}0` }));
    expect(createReportSchema.safeParse({ emergency_contacts: six }).success).toBe(false);
    expect(createReportSchema.safeParse({ emergency_contacts: [{ phone: '12' }] }).success).toBe(false);
  });

  it('lokasi di luar rentang ditolak', () => {
    expect(createReportSchema.safeParse({ location: { lat: 91, lng: 0 } }).success).toBe(false);
  });

  it('pengaduan: detail (judul, kronologi, lokasi, waktu, pelaku, saksi) diterima', () => {
    const r = createReportSchema.safeParse({
      kind: 'pengaduan',
      category: 'patroli',
      message: 'Ada motor parkir di gang tiga sejak pagi',
      complaint: {
        title: 'Motor parkir liar',
        description: 'Ada motor parkir di gang tiga sejak pagi',
        location_text: 'Gang 3, Blok C',
        occurred_at: '2026-11-23T07:30:00.000Z',
        suspect: 'Motor merah tanpa plat',
        witness: '0812 3456 7890',
      },
    });
    expect(r.success).toBe(true);
  });

  it('pengaduan: waktu kejadian harus ISO datetime', () => {
    const r = createReportSchema.safeParse({
      kind: 'pengaduan',
      message: 'Uraian pengaduan cukup panjang',
      complaint: { occurred_at: 'kemarin' },
    });
    expect(r.success).toBe(false);
  });
});
