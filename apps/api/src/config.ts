function req(name: string, fallback?: string): string {
  const v = process.env[name] ?? fallback;
  if (v === undefined || v === '') throw new Error(`env ${name} wajib diisi`);
  return v;
}

const nodeEnv = process.env.NODE_ENV ?? 'development';

export const config = {
  env: nodeEnv,
  isProd: nodeEnv === 'production',
  port: Number(process.env.PORT ?? 4000),
  publicApiUrl: req('PUBLIC_API_URL', 'http://localhost:4000'),
  portalUrl: req('PORTAL_URL', 'http://localhost:5173'),
  databaseUrl: req('DATABASE_URL'),
  redisUrl: req('REDIS_URL', 'redis://localhost:6379'),
  jwtSecret: req('JWT_SECRET'),
  adminJwtSecret: req('ADMIN_JWT_SECRET'),
  signedUrlSecret: req('SIGNED_URL_SECRET'),
  storageKey: Buffer.from(req('STORAGE_ENCRYPTION_KEY'), 'hex'),
  storageDir: req('STORAGE_DIR', './storage/private'),
  smtpUrl: process.env.SMTP_URL ?? '',
  mailFrom: req('MAIL_FROM', 'SiagaSOS <no-reply@siagasos.local>'),
  portalOrigins: (process.env.PORTAL_ORIGINS ?? '').split(',').map((s) => s.trim()).filter(Boolean),
  webhookWorker: (process.env.WEBHOOK_WORKER ?? 'true') === 'true',

  // Aturan bisnis (PRD). Bisa dipindah ke tabel plans saat billing masuk.
  testReportsPerDay: 50,
  keyCacheTtlMs: 30_000, // revoke/suspend berlaku ≤ 60 detik (F-05, F-28)
  reapplyAfterDays: 30,
  maxUploadBytes: 5 * 1024 * 1024,
  reviewSlaWarnHours: 36,
};

if (config.storageKey.length !== 32) throw new Error('STORAGE_ENCRYPTION_KEY harus 32 byte hex (64 karakter)');
if (config.isProd && /^0+$/.test(process.env.STORAGE_ENCRYPTION_KEY ?? '')) {
  throw new Error('STORAGE_ENCRYPTION_KEY default tidak boleh dipakai di production');
}
