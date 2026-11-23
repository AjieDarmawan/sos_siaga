import { withTenant } from '../db.js';
import { logger } from '../logger.js';
import { hit } from './rateLimit.js';
import { mapsLink, sendSosWhatsApp, type WaResult } from './whatsapp.js';

export interface WaTarget { name: string; phone: string; source: 'app' | 'source' | 'personal' }

/** Penerima app/source dulu (menang bila nomor sama), lalu kontak darurat pribadi. Nomor ganda dibuang. */
export function mergeTargets(recipients: { name: string; phone: string; source_id: string | null }[], personal: { name?: string; phone: string }[]): WaTarget[] {
  const seen = new Set<string>();
  const out: WaTarget[] = [];
  for (const r of recipients) {
    if (seen.has(r.phone)) continue;
    seen.add(r.phone);
    out.push({ name: r.name, phone: r.phone, source: r.source_id ? 'source' : 'app' });
  }
  for (const p of personal) {
    if (!p.phone || seen.has(p.phone)) continue;
    seen.add(p.phone);
    out.push({ name: p.name?.trim() || 'Kontak darurat', phone: p.phone, source: 'personal' });
  }
  return out;
}

/** Satu nomor maks. 5 WA SOS per jam lintas laporan: pagar bila kunci publishable disalahgunakan untuk spam. */
/** Nomor 0800 (bebas pulsa, bukan nomor seluler WhatsApp) = nomor uji: dicatat tapi tidak pernah dikirimi WA (smoke/QA). */
export const isTestNumber = (phone: string) => phone.startsWith('62800');
const PER_NUMBER_LIMIT = 5;

function outcome(t: WaTarget, r: WaResult | 'limited' | 'test'): string {
  const who = `${t.name} (${t.phone}${t.source === 'personal' ? ', kontak pelapor' : ''})`;
  if (r === 'test') return `WhatsApp ke ${who}: nomor uji 0800, tidak dikirim`;
  if (r === 'limited') return `WhatsApp ke ${who}: dilewati, batas ${PER_NUMBER_LIMIT}/jam per nomor`;
  if (r.status === 'sent') return `WhatsApp ke ${who}: terkirim`;
  if (r.status === 'stub') return `WhatsApp ke ${who}: tidak dikirim, provider WA belum diatur (${r.provider})`;
  return `WhatsApp ke ${who}: gagal (${r.error ?? 'tidak diketahui'})`;
}

/**
 * Kabari Penerima SOS + kontak darurat pelapor lewat WhatsApp. Dipanggil SETELAH laporan tersimpan (commit) dan
 * tidak ditunggu oleh jalur SOS: gagal di sini tidak pernah menggagalkan laporan. Hasil per nomor dicatat di timeline.
 */
export async function dispatchSosWhatsApp(report: any, appName: string): Promise<void> {
  if (report.kind === 'pengaduan') return;
  try {
    const { recipients, sourceLabel } = await withTenant(report.account_id, async (c) => {
      const rec = await c.query(
        `SELECT name, phone, source_id FROM sos_recipients
         WHERE app_id = $1 AND active AND (source_id IS NULL OR source_id = $2)
         ORDER BY source_id NULLS LAST, name`,
        [report.app_id, report.source_id ?? null],
      );
      const src = report.source_id ? await c.query(`SELECT label, source_key FROM sources WHERE id = $1`, [report.source_id]) : { rows: [] };
      return { recipients: rec.rows, sourceLabel: (src.rows[0]?.label || src.rows[0]?.source_key || null) as string | null };
    });
    const targets = mergeTargets(recipients, (report.emergency_contacts ?? []) as { name?: string; phone: string }[]);
    if (!targets.length) return;

    const lines: string[] = [];
    if (report.mode !== 'live') {
      lines.push(`Mode test: WhatsApp tidak dikirim ke ${targets.length} penerima (${targets.map((t) => t.phone).join(', ')})`);
    } else {
      const reporter = report.reporter_name || 'Pelapor';
      const place = [appName, sourceLabel].filter(Boolean).join(' · ');
      const params: [string, string, string] = [reporter, place || 'Lokasi tidak diketahui', mapsLink(report.lat, report.lng)];
      const results = await Promise.all(targets.map(async (t) => {
        if (isTestNumber(t.phone)) return outcome(t, 'test');
        const r = await hit(`wa:${t.phone}`, PER_NUMBER_LIMIT, 3600);
        return outcome(t, r.ok ? await sendSosWhatsApp(t.phone, t.name, params) : 'limited');
      }));
      lines.push(...results);
    }
    await withTenant(report.account_id, async (c) => {
      for (const note of lines) {
        await c.query(`INSERT INTO report_events (report_id, account_id, actor_kind, type, note) VALUES ($1,$2,'system','whatsapp',$3)`,
          [report.id, report.account_id, note]);
      }
    });
  } catch (err) {
    logger.error({ err, reportId: report.id }, 'dispatchSosWhatsApp gagal');
  }
}
