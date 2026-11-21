import type { KeyMode } from '@siagasos/shared';
import { randomBase62, sha256 } from './crypto.js';

export type KeyKind = 'publishable' | 'secret';

export interface GeneratedKey {
  kind: KeyKind;
  mode: KeyMode;
  key: string;
  prefix: string;
  hash: string;
}

/** Format: pk_live_<32 base62>, sk_test_<40 base62>. Pola Stripe: prefix menyatakan jenis & mode. */
export function generateKey(kind: KeyKind, mode: KeyMode): GeneratedKey {
  const head = `${kind === 'publishable' ? 'pk' : 'sk'}_${mode}_`;
  const key = head + randomBase62(kind === 'publishable' ? 32 : 40);
  return { kind, mode, key, prefix: key.slice(0, head.length + 4), hash: sha256(key) };
}

export function parseKeyPrefix(key: string): { kind: KeyKind; mode: KeyMode } | null {
  const m = /^(pk|sk)_(live|test)_[0-9A-Za-z]{32,40}$/.exec(key);
  if (!m) return null;
  return { kind: m[1] === 'pk' ? 'publishable' : 'secret', mode: m[2] as KeyMode };
}
