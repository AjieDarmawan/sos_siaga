import { createCipheriv, createDecipheriv, randomBytes, randomUUID } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { config } from '../config.js';
import { ApiError } from './errors.js';
import { hmac, safeEqual } from './crypto.js';

/**
 * Storage privat terenkripsi (AES-256-GCM). Driver lokal untuk MVP; antarmuka sama
 * bisa diganti S3/GCS/MinIO dengan SSE tanpa mengubah route.
 */
export async function putPrivate(prefix: string, data: Buffer): Promise<string> {
  const key = `${prefix}/${randomUUID()}`;
  const iv = randomBytes(12);
  const c = createCipheriv('aes-256-gcm', config.storageKey, iv);
  const enc = Buffer.concat([c.update(data), c.final()]);
  const file = path.join(config.storageDir, key);
  await mkdir(path.dirname(file), { recursive: true });
  await writeFile(file, Buffer.concat([iv, c.getAuthTag(), enc]), { mode: 0o600 });
  return key;
}

export async function getPrivate(key: string): Promise<Buffer> {
  if (key.includes('..')) throw new ApiError(400, 'bad_key', 'storage key tidak valid');
  const raw = await readFile(path.join(config.storageDir, key));
  const d = createDecipheriv('aes-256-gcm', config.storageKey, raw.subarray(0, 12));
  d.setAuthTag(raw.subarray(12, 28));
  return Buffer.concat([d.update(raw.subarray(28)), d.final()]);
}

/** Tanda tangan tautan sementara: base64url(json).hmac */
export function signToken(payload: Record<string, unknown>, ttlSec: number): string {
  const body = Buffer.from(JSON.stringify({ ...payload, exp: Math.floor(Date.now() / 1000) + ttlSec })).toString('base64url');
  return `${body}.${hmac(config.signedUrlSecret, body)}`;
}

export function verifyToken<T>(token: string): T {
  const [body, sig] = token.split('.');
  if (!body || !sig || !safeEqual(sig, hmac(config.signedUrlSecret, body))) {
    throw new ApiError(403, 'invalid_signature', 'Tautan tidak valid');
  }
  const data = JSON.parse(Buffer.from(body, 'base64url').toString()) as T & { exp: number };
  if (data.exp < Date.now() / 1000) throw new ApiError(410, 'link_expired', 'Tautan sudah kedaluwarsa');
  return data;
}

/** Deteksi tipe dari magic bytes, bukan ekstensi. */
export function sniffMime(buf: Buffer): 'application/pdf' | 'image/jpeg' | 'image/png' | null {
  if (buf.subarray(0, 5).toString('latin1') === '%PDF-') return 'application/pdf';
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  return null;
}
