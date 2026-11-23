import crypto from 'node:crypto';
import { logger } from '../logger.js';

/**
 * Pengirim WhatsApp untuk SOS, pola & nama env sama dengan tata-warga (`PanicOutboundNotifier`) / mkasir supaya
 * konfigurasinya bisa disalin. Template WA (harus APPROVED di provider) dengan 3 parameter body:
 * {{1}} nama pelapor, {{2}} lokasi, {{3}} link Google Maps.
 *
 *   metadev — WA_PROVIDER=metadev (atau PANIC_BUTTON_USE_METADEV=true). MetaDev (bot.mkasir.id), Bearer.
 *             METADEV_API_KEY, METADEV_ACCOUNT_ID, opsional METADEV_BASE_URL, METADEV_EWSBUTTON_TEMPLATE_NAME,
 *             METADEV_EWSBUTTON_LANGUAGE.
 *   qontak  — WA_PROVIDER=qontak. Mekari Qontak broadcast direct, HMAC. PANIC_QONTAK_HMAC_USERNAME,
 *             PANIC_QONTAK_HMAC_SECRET, PANIC_QONTAK_TEMPLATE_ID, PANIC_QONTAK_CHANNEL_INTEGRATION_ID, opsional PANIC_QONTAK_URL.
 *   stub    — selain itu: hanya log, tidak ada panggilan keluar (default dev).
 *
 * Tidak pernah melempar: gagal kirim ke satu nomor tidak boleh mengganggu SOS.
 */

const QONTAK_DEFAULT_URL = 'https://api.mekari.com/qontak/chat/v1/broadcasts/whatsapp/direct';
const TIMEOUT_MS = 8000;

export type WaResult = { status: 'sent' | 'failed' | 'stub'; provider: string; error?: string };

export function waProviderName(env = process.env): string {
  if (String(env.PANIC_BUTTON_USE_METADEV ?? '').toLowerCase() === 'true') return 'metadev';
  return (env.WA_PROVIDER ?? env.PANIC_OUTBOUND_PROVIDER ?? 'stub').toLowerCase();
}

export function mapsLink(lat: number | null | undefined, lng: number | null | undefined): string {
  return lat != null && lng != null ? `https://www.google.com/maps?q=${lat},${lng}` : '-';
}

function qontakHmac(url: string, username: string, secret: string) {
  const { pathname } = new URL(url);
  const date = new Date().toUTCString();
  const signature = crypto.createHmac('sha256', secret).update(`date: ${date}\nPOST ${pathname} HTTP/1.1`).digest('base64');
  return {
    Authorization: `hmac username="${username}", algorithm="hmac-sha256", headers="date request-line", signature="${signature}"`,
    Date: date,
  };
}

type Req = { url: string; headers: Record<string, string>; body: unknown };
const PROVIDERS: Record<string, { configured: (e: NodeJS.ProcessEnv) => boolean; request: (to: string, name: string, params: string[], e: NodeJS.ProcessEnv) => Req }> = {
  metadev: {
    configured: (e) => Boolean(e.METADEV_API_KEY && e.METADEV_ACCOUNT_ID),
    request: (to, _name, params, e) => {
      const base = (e.METADEV_BASE_URL || 'https://api-bot.mkasir.id').replace(/\/$/, '');
      const template = e.METADEV_EWSBUTTON_TEMPLATE_NAME || 'ewsbutton';
      return {
        url: `${base}/v1/templates/${encodeURIComponent(template)}/send-test`,
        headers: { Authorization: `Bearer ${e.METADEV_API_KEY}` },
        body: { account_id: e.METADEV_ACCOUNT_ID, to, language: e.METADEV_EWSBUTTON_LANGUAGE || 'id', body_parameters: params },
      };
    },
  },
  qontak: {
    configured: (e) =>
      Boolean(e.PANIC_QONTAK_HMAC_USERNAME && e.PANIC_QONTAK_HMAC_SECRET && e.PANIC_QONTAK_TEMPLATE_ID && e.PANIC_QONTAK_CHANNEL_INTEGRATION_ID),
    request: (to, name, params, e) => {
      const url = e.PANIC_QONTAK_URL || QONTAK_DEFAULT_URL;
      return {
        url,
        headers: qontakHmac(url, e.PANIC_QONTAK_HMAC_USERNAME!, e.PANIC_QONTAK_HMAC_SECRET!),
        body: {
          to_name: name || 'Penerima',
          to_number: to,
          message_template_id: e.PANIC_QONTAK_TEMPLATE_ID,
          channel_integration_id: e.PANIC_QONTAK_CHANNEL_INTEGRATION_ID,
          language: { code: 'id' },
          parameters: { body: ['nama', 'lokasi', 'maps_link'].map((value, i) => ({ key: String(i + 1), value, value_text: params[i] })) },
        },
      };
    },
  },
};

/** Kirim template SOS ke satu nomor (62xx). params = [nama pelapor, lokasi, link maps]. */
export async function sendSosWhatsApp(
  to: string,
  name: string,
  params: [string, string, string],
  { env = process.env, fetchImpl = globalThis.fetch }: { env?: NodeJS.ProcessEnv; fetchImpl?: typeof fetch } = {},
): Promise<WaResult> {
  const providerName = waProviderName(env);
  const provider = PROVIDERS[providerName];
  if (!provider || !provider.configured(env)) {
    logger.info({ provider: providerName, to, params }, 'WA SOS (stub, tidak dikirim)');
    return { status: 'stub', provider: providerName };
  }
  try {
    const { url, headers, body } = provider.request(to, name, params, env);
    const res = await fetchImpl(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', ...headers },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}: ${(await res.text().catch(() => '')).slice(0, 200)}`);
    return { status: 'sent', provider: providerName };
  } catch (err) {
    logger.warn({ provider: providerName, to, err: (err as Error).message }, 'WA SOS gagal');
    return { status: 'failed', provider: providerName, error: (err as Error).message };
  }
}
