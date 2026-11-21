import { q } from '../db.js';
import { config } from '../config.js';
import { sendMail } from './mailer.js';
import { logger } from '../logger.js';

/**
 * Notifikasi responder untuk laporan live (F-16). MVP: email ke semua user aktif akun.
 * Web push menyusul di M3 (butuh subscription dari dashboard). Laporan test tidak memicu notifikasi.
 */
export function notifyResponders(accountId: string, report: any, appName: string) {
  q<{ email: string }>(`SELECT email FROM users WHERE account_id = $1 AND disabled_at IS NULL AND email_verified_at IS NOT NULL`, [accountId])
    .then(({ rows }) => {
      if (!rows.length) return;
      const loc = report.location ? `https://maps.google.com/?q=${report.location.lat},${report.location.lng} (±${report.location.accuracy_m ?? '?'} m)` : 'tidak tersedia';
      sendMail(
        rows.map((r) => r.email),
        `🚨 SOS ${report.category.toUpperCase()} — ${appName}`,
        [
          `Laporan SOS baru (${report.source_key ?? 'tanpa source'})`,
          `Pesan: ${report.message ?? '-'}`,
          `Pelapor: ${report.reporter?.name ?? '-'} ${report.reporter?.phone ?? ''}`,
          `Lokasi: ${loc}`,
          '',
          `Buka dashboard: ${config.portalUrl}/reports/${report.id}`,
        ].join('\n'),
      );
    })
    .catch((err) => logger.error({ err }, 'notifyResponders gagal'));
}
