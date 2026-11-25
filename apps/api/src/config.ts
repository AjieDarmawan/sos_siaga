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
  /** Pembersihan berkala (media pending yang tidak pernah selesai, OTP kedaluwarsa). Aman di banyak instance (advisory lock). */
  maintenanceWorker: (process.env.MAINTENANCE_WORKER ?? 'true') === 'true',
  /** Worker Polmas Keamanan: isi kecamatan/kelurahan laporan dari GPS (reverse geocode, async). */
  polmasWorker: (process.env.POLMAS_WORKER ?? 'true') === 'true',

  /** Object storage S3-compatible (MinIO) untuk media laporan. Kosong = fitur media nonaktif (503 media_disabled). */
  s3: {
    endpoint: process.env.S3_ENDPOINT ?? '',
    region: process.env.S3_REGION || 'us-east-1',
    accessKey: process.env.S3_ACCESS_KEY ?? '',
    secretKey: process.env.S3_SECRET_KEY ?? '',
    bucket: process.env.S3_BUCKET ?? 'sos-siaga',
    forcePathStyle: (process.env.S3_FORCE_PATH_STYLE ?? 'true') === 'true',
  },
  media: {
    maxPerReport: 10,
    /** Batas ukuran per jenis (byte). Video pendek TKP; kompres di perangkat untuk durasi lebih panjang. */
    maxBytes: { image: 10 * 1024 * 1024, audio: 15 * 1024 * 1024, video: 60 * 1024 * 1024 } as Record<'image' | 'video' | 'audio', number>,
    uploadUrlTtlS: 900,
    viewUrlTtlS: 900,
    /** Lampiran masih boleh ditambah sampai N menit setelah laporan mencapai status akhir. */
    graceAfterCloseMin: 30,
  },

  /**
   * Reverse geocode untuk isi otomatis wilayah Nomor Darurat (GET /v1/sdk/regions/reverse). API kompatibel
   * Nominatim; kosongkan GEOCODER_URL untuk mematikan. Koordinat dibulatkan ±100 m sebelum dikirim.
   */
  geocoderUrl: process.env.GEOCODER_URL ?? 'https://nominatim.openstreetmap.org/reverse',
  geocoderUserAgent: process.env.GEOCODER_USER_AGENT || 'SiagaSOS-API/0.1 (+https://siagasos.id)',

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
