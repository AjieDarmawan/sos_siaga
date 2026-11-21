import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';

const B62 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';

export function randomBase62(len: number): string {
  // rejection sampling agar distribusi rata
  let out = '';
  while (out.length < len) {
    for (const b of randomBytes(len * 2)) {
      if (b < 248) out += B62[b % 62];
      if (out.length === len) break;
    }
  }
  return out;
}

export const sha256 = (s: string | Buffer) => createHash('sha256').update(s).digest('hex');
export const hmac = (secret: string, data: string) => createHmac('sha256', secret).update(data).digest('hex');
export const randomToken = (bytes = 32) => randomBytes(bytes).toString('base64url');

export function safeEqual(a: string, b: string) {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
}
