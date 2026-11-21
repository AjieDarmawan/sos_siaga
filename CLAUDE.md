# CLAUDE.md

SiagaSOS: platform tombol darurat (SOS-as-a-Service). Monorepo pnpm: `apps/api` (Express 5 + Postgres RLS + Redis), `packages/shared`, `packages/sdk-js`, `packages/sdk-react`.

## Wajib di awal session
1. Baca [`PROGRESS.md`](PROGRESS.md): posisi saat ini, checklist selesai/belum, jebakan lingkungan dev.
2. Baca [`docs/STATUS.md`](docs/STATUS.md) hanya bila menyentuh kebutuhan PRD tertentu (F-xx) atau keputusan desain.
3. Jangan scan ulang seluruh repo. README berisi daftar endpoint.

## Wajib setelah kerja
- Tambahkan entri di "Log session" `PROGRESS.md` dan perbarui checklist (✅/🟡/⬜).
- Perubahan API: jalankan `pnpm smoke` (API harus jalan) dan `pnpm -r typecheck`, lalu perbarui README dan `docs/STATUS.md`.
- Migrasi baru: file baru `apps/api/migrations/NNN_*.sql` (jangan edit `001`), dengan `COMMENT ON` untuk kolom yang tidak jelas, dan RLS + policy `tenant_isolation` untuk tabel data tenant.

## Aturan arsitektur
- Tabel ber-RLS hanya diakses lewat `withTenant()` / `withPlatform()` (`src/db.ts`). API konek sebagai `siagasos_app`, jangan pernah superuser.
- Jalur SOS (`/v1/sdk/reports`) tidak boleh bergantung pada Redis, email, atau webhook. Semuanya async atau fail-open.
- SDK core tanpa dependency runtime, < 10 KB gzip (`pnpm --filter @siagasos/js size`). Impor dari `@siagasos/shared` hanya `import type`.
