import nodemailer from 'nodemailer';
import { config } from '../config.js';
import { logger } from '../logger.js';

const transport = config.smtpUrl ? nodemailer.createTransport(config.smtpUrl) : nodemailer.createTransport({ jsonTransport: true });

/** Kirim email tanpa memblokir request. Gagal kirim dicatat, tidak melempar. */
export function sendMail(to: string | string[], subject: string, text: string) {
  transport
    .sendMail({ from: config.mailFrom, to, subject, text })
    .then(() => {
      if (!config.smtpUrl) logger.info({ to, subject, text }, '📧 email (dev, tidak dikirim)');
    })
    .catch((err) => logger.error({ err, to, subject }, 'gagal kirim email'));
}

const STATUS_COPY: Record<string, { subject: string; body: (note?: string | null) => string }> = {
  pending_review: {
    subject: 'Pendaftaran SiagaSOS sedang direview',
    body: () => 'Dokumen perusahaan Anda sudah kami terima. Tim kami akan mereview dalam 1–2 hari kerja.\nSambil menunggu, Anda sudah bisa membuat app dan memakai kunci test.',
  },
  needs_revision: {
    subject: 'Dokumen SiagaSOS perlu diperbaiki',
    body: (n) => `Tim kami meminta perbaikan dokumen.\n\nCatatan: ${n ?? '-'}\n\nUnggah ulang di ${config.portalUrl}/onboarding`,
  },
  approved: {
    subject: 'Perusahaan Anda disetujui di SiagaSOS',
    body: () => `Selamat, verifikasi selesai. Kunci live sudah bisa dibuat.\n\nMasuk: ${config.portalUrl}/login`,
  },
  rejected: {
    subject: 'Pendaftaran SiagaSOS ditolak',
    body: (n) => `Mohon maaf, pendaftaran ditolak.\n\nAlasan: ${n ?? '-'}\n\nAnda dapat mendaftar ulang setelah ${config.reapplyAfterDays} hari.`,
  },
  suspended: {
    subject: 'Akun SiagaSOS dibekukan',
    body: (n) => `Akun perusahaan Anda dibekukan dan semua API key dinonaktifkan.\n\nAlasan: ${n ?? '-'}`,
  },
};

export function sendStatusEmail(to: string, status: string, note?: string | null) {
  const c = STATUS_COPY[status];
  if (c) sendMail(to, c.subject, c.body(note));
}
