import { defineConfig } from 'vitest/config';

// Unit test murni: tidak butuh Postgres/Redis sungguhan (redis di-mock per file bila diperlukan).
// Env minimal supaya src/config.ts bisa dimuat. Uji integrasi end-to-end tetap lewat `pnpm smoke`.
export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    env: {
      NODE_ENV: 'test',
      DATABASE_URL: 'postgres://unit:unit@127.0.0.1:1/unit',
      REDIS_URL: 'redis://127.0.0.1:1',
      JWT_SECRET: 'unit-portal-secret-unit-portal-secret-xx',
      ADMIN_JWT_SECRET: 'unit-admin-secret-unit-admin-secret-xxxx',
      SIGNED_URL_SECRET: 'unit-signed-url-secret-unit-signed-xxxx',
      STORAGE_ENCRYPTION_KEY: '11'.repeat(32),
      S3_ENDPOINT: '',
    },
  },
});
