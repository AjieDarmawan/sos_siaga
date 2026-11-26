import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import jwt from 'jsonwebtoken';
import { logger } from '../logger.js';

/**
 * Pengirim Firebase Cloud Messaging (HTTP v1) untuk alarm SOS ke HP satpam.
 *
 * Env: FCM_SERVICE_ACCOUNT = isi JSON service account, atau path ke file JSON-nya. Harus dari project Firebase yang
 * sama dengan app klien (POS: `pushnotif-6937d`). Kosong = stub (hanya log), sama seperti WA tanpa provider.
 *
 * Push Android memakai channel `siagasos_sos` (dibuat app dengan suara sirene res/raw/sos_siren), prioritas HIGH,
 * supaya tetap berbunyi saat app di latar belakang / ditutup. Tidak pernah melempar.
 */

const TIMEOUT_MS = 8000;
export const SOS_CHANNEL_ID = 'siagasos_sos';

/**
 * Dua project Firebase: `pos` = app klien (satpam di POS, env FCM_SERVICE_ACCOUNT), `pk` = app Polmas Keamanan
 * (project baru, env PK_FCM_SERVICE_ACCOUNT, channel `polmas_sos_v2` + suara `sos_siren`, sama dengan commerceOS).
 */
export interface FcmProfile { env: string; channel: string; sound: string }
export const POS_FCM: FcmProfile = { env: 'FCM_SERVICE_ACCOUNT', channel: SOS_CHANNEL_ID, sound: 'sos_siren' };
export const PK_FCM: FcmProfile = { env: 'PK_FCM_SERVICE_ACCOUNT', channel: 'polmas_sos_v2', sound: 'sos_siren' };

interface ServiceAccount { project_id: string; client_email: string; private_key: string; token_uri?: string }

const accounts = new Map<string, ServiceAccount>();
/** Gagal baca terakhir per env: dicoba ulang setelah 30 dtk (file bisa baru muncul setelah deploy / env baru dipasang). */
const failures = new Map<string, { at: number; reason: string }>();
const tokens = new Map<string, { token: string; exp: number }>();
const RETRY_MS = 30_000;

function loadAccount(profile: FcmProfile = POS_FCM, env = process.env): ServiceAccount | null {
  const ok = accounts.get(profile.env);
  if (ok) return ok;
  const failed = failures.get(profile.env);
  if (failed && Date.now() - failed.at < RETRY_MS) return null;
  const raw = (env[profile.env] ?? '').trim();
  let reason: string;
  try {
    if (!raw) throw new Error(`env ${profile.env} kosong`);
    // Tiga bentuk nilai env: isi JSON langsung, `base64:<JSON di-base64>` (satu baris, aman ditempel di panel hosting),
    // atau path file JSON di server (relatif terhadap folder kerja proses API).
    let json: string;
    if (raw.startsWith('{')) json = raw;
    else if (raw.startsWith('base64:')) json = Buffer.from(raw.slice(7), 'base64').toString('utf8');
    else {
      const path = resolve(raw);
      if (!existsSync(path)) throw new Error(`file tidak ditemukan: ${path}`);
      json = readFileSync(path, 'utf8');
    }
    let account: ServiceAccount;
    try {
      account = JSON.parse(json) as ServiceAccount;
    } catch {
      throw new Error('isi bukan JSON service account yang valid');
    }
    if (!(account.project_id && account.client_email && account.private_key)) throw new Error('field service account tidak lengkap');
    accounts.set(profile.env, account);
    failures.delete(profile.env);
    return account;
  } catch (err) {
    reason = (err as Error).message;
  }
  if (failures.get(profile.env)?.reason !== reason) {
    logger.error({ err: reason, env: profile.env }, 'service account FCM tidak bisa dibaca, push SOS nonaktif');
  }
  failures.set(profile.env, { at: Date.now(), reason });
  return null;
}

/** Alasan kredensial FCM belum terbaca (tanpa rahasia), untuk /v1/pk/status; null bila siap. */
export function fcmProblem(profile: FcmProfile = POS_FCM): string | null {
  return loadAccount(profile) ? null : failures.get(profile.env)?.reason ?? 'belum dibaca';
}

export const fcmConfigured = (profile: FcmProfile = POS_FCM) => loadAccount(profile) !== null;

/** project_id Firebase yang dipakai server (bukan rahasia): dicocokkan dengan google-services.json app saat build rilis. */
export const fcmProject = (profile: FcmProfile = POS_FCM) => loadAccount(profile)?.project_id ?? null;

async function accessToken(sa: ServiceAccount): Promise<string> {
  const cached = tokens.get(sa.client_email);
  if (cached && cached.exp - 60_000 > Date.now()) return cached.token;
  const tokenUri = sa.token_uri || 'https://oauth2.googleapis.com/token';
  const now = Math.floor(Date.now() / 1000);
  const assertion = jwt.sign(
    { iss: sa.client_email, scope: 'https://www.googleapis.com/auth/firebase.messaging', aud: tokenUri, iat: now, exp: now + 3600 },
    sa.private_key,
    { algorithm: 'RS256' },
  );
  const res = await fetch(tokenUri, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`OAuth HTTP ${res.status}: ${(await res.text().catch(() => '')).slice(0, 200)}`);
  const body = (await res.json()) as { access_token: string; expires_in: number };
  tokens.set(sa.client_email, { token: body.access_token, exp: Date.now() + body.expires_in * 1000 });
  return body.access_token;
}

export type PushResult = 'sent' | 'stub' | 'unregistered' | 'failed';

export interface SosPush {
  title: string;
  body: string;
  /** Semua nilai string (syarat FCM data message). */
  data: Record<string, string>;
}

/** Kirim satu push SOS ke satu token FCM. 'unregistered' = token mati, pemanggil sebaiknya menghapusnya. */
export async function sendSosPush(token: string, msg: SosPush, profile: FcmProfile = POS_FCM): Promise<PushResult> {
  const sa = loadAccount(profile);
  if (!sa) {
    logger.info({ title: msg.title, data: msg.data, env: profile.env }, 'Push SOS (stub, service account FCM kosong)');
    return 'stub';
  }
  try {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${await accessToken(sa)}` },
      body: JSON.stringify({
        message: {
          token,
          notification: { title: msg.title, body: msg.body },
          data: msg.data,
          android: {
            priority: 'HIGH',
            ttl: '600s',
            notification: {
              channel_id: profile.channel,
              sound: profile.sound,
              notification_priority: 'PRIORITY_MAX',
              visibility: 'PUBLIC',
              default_vibrate_timings: true,
            },
          },
          apns: {
            headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
            payload: { aps: { sound: 'default', 'interruption-level': 'time-sensitive' } },
          },
        },
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (res.ok) return 'sent';
    const text = await res.text().catch(() => '');
    if (res.status === 404 || /UNREGISTERED|registration-token-not-registered/.test(text)) return 'unregistered';
    logger.warn({ status: res.status, body: text.slice(0, 300) }, 'Push SOS gagal');
    return 'failed';
  } catch (err) {
    logger.warn({ err: (err as Error).message }, 'Push SOS gagal');
    return 'failed';
  }
}
