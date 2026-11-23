import type { AccountStatus, DocType, ReportStatus } from './types';

const dtf = new Intl.DateTimeFormat('id-ID', { dateStyle: 'medium', timeStyle: 'short' });
const tf = new Intl.DateTimeFormat('id-ID', { hour: '2-digit', minute: '2-digit', second: '2-digit' });
export const fmtDate = (s?: string | null) => (s ? dtf.format(new Date(s)) : '—');
export const fmtTime = (s?: string | null) => (s ? tf.format(new Date(s)) : '—');

const rtf = new Intl.RelativeTimeFormat('id-ID', { numeric: 'auto' });
export function fmtAgo(s: string, now = Date.now()) {
  const sec = Math.round((new Date(s).getTime() - now) / 1000);
  const abs = Math.abs(sec);
  if (abs < 45) return 'baru saja';
  if (abs < 3600) return rtf.format(Math.round(sec / 60), 'minute');
  if (abs < 86400) return rtf.format(Math.round(sec / 3600), 'hour');
  return rtf.format(Math.round(sec / 86400), 'day');
}

export const fmtBytes = (n: number) => (n < 1024 * 1024 ? `${Math.round(n / 1024)} KB` : `${(n / 1024 / 1024).toFixed(1)} MB`);

export type Tone = 'sos' | 'warn' | 'ok' | 'info' | 'muted';

export const REPORT_STATUS: Record<ReportStatus, { label: string; tone: Tone }> = {
  open: { label: 'Baru', tone: 'sos' },
  acknowledged: { label: 'Diterima', tone: 'warn' },
  in_progress: { label: 'Ditangani', tone: 'info' },
  resolved: { label: 'Selesai', tone: 'ok' },
  cancelled: { label: 'Dibatalkan', tone: 'muted' },
  false_alarm: { label: 'Alarm palsu', tone: 'muted' },
};

export const ACCOUNT_STATUS: Record<AccountStatus, { label: string; tone: Tone }> = {
  pending_email: { label: 'Menunggu verifikasi email', tone: 'warn' },
  pending_review: { label: 'Menunggu review', tone: 'warn' },
  needs_revision: { label: 'Perlu perbaikan', tone: 'sos' },
  approved: { label: 'Disetujui', tone: 'ok' },
  rejected: { label: 'Ditolak', tone: 'sos' },
  suspended: { label: 'Dibekukan', tone: 'sos' },
};

export const DOC_LABEL: Record<DocType, { label: string; hint: string }> = {
  nib: { label: 'NIB (OSS)', hint: 'Cetak NIB dari oss.go.id' },
  npwp: { label: 'NPWP badan usaha', hint: 'Kartu atau surat keterangan terdaftar' },
  akta: { label: 'Akta pendirian / perubahan terakhir', hint: 'Halaman yang memuat nama & susunan direksi' },
  sk_kemenkumham: { label: 'SK Kemenkumham', hint: 'Pengesahan badan hukum' },
  ktp_pic: { label: 'KTP penanggung jawab (PIC)', hint: 'Foto jelas, tidak terpotong' },
  surat_kuasa: { label: 'Surat kuasa dari direksi', hint: 'Wajib bila PIC bukan direksi' },
  lainnya: { label: 'Dokumen pendukung lain', hint: 'Opsional' },
};

export const CATEGORY_LABEL: Record<string, string> = {
  general: 'Darurat umum', kriminal: 'Kriminal', medis: 'Medis', kebakaran: 'Kebakaran', bencana: 'Bencana', kecelakaan: 'Kecelakaan',
  // kategori pengaduan (menu "Laporan pengaduan" di tombol melayang SDK)
  ketertiban: 'Gangguan ketertiban', kebisingan: 'Kebisingan', parkir_liar: 'Parkir liar', pungli: 'Pungutan liar',
  kehilangan: 'Kehilangan barang/dokumen', patroli: 'Minta patroli', lainnya: 'Lainnya',
};
export const catLabel = (c: string) => CATEGORY_LABEL[c] ?? c;

export const ENTITY_LABEL = { pt: 'PT', cv: 'CV', yayasan: 'Yayasan', koperasi: 'Koperasi', lainnya: 'Lainnya' } as const;
