/**
 * Hitung jam kerja (Senin–Jumat, zona Asia/Jakarta, 24 jam per hari kerja) untuk SLA review.
 * Libur nasional belum dihitung — tambahkan tabel holidays bila SLA mulai ketat.
 */
const WIB_OFFSET_MS = 7 * 3600_000;

const isWeekday = (utcMs: number) => {
  const d = new Date(utcMs + WIB_OFFSET_MS).getUTCDay();
  return d !== 0 && d !== 6;
};

export function businessHoursBetween(from: Date, to: Date): number {
  let ms = 0;
  const step = 15 * 60_000;
  for (let t = from.getTime(); t < to.getTime(); t += step) {
    if (isWeekday(t)) ms += Math.min(step, to.getTime() - t);
  }
  return ms / 3600_000;
}

export function addBusinessDays(from: Date, days: number): Date {
  let t = from.getTime();
  let remaining = days * 24 * 3600_000;
  const step = 15 * 60_000;
  while (remaining > 0) {
    if (isWeekday(t)) remaining -= step;
    t += step;
  }
  return new Date(t);
}
