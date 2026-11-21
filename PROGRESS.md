# PROGRESS — SiagaSOS

> **Baca file ini dulu di awal setiap session.** File ini adalah sumber kebenaran untuk "apa yang sudah ada dan apa yang berikutnya".
> Pemetaan per kebutuhan PRD (F-01 s.d. F-29) ada di [`docs/STATUS.md`](docs/STATUS.md).
> Setelah menyelesaikan satu bagian kerja, tambahkan entri di **Log session** paling bawah dan perbarui checklist.

Legenda: ✅ selesai & teruji · 🟡 sebagian · ⬜ belum

---

## Posisi saat ini

- **Fase:** M1 backend ✅, M2 SDK web 🟡 (belum publish npm), M3 portal + dashboard responder ✅ (web push belum).
- **Berikutnya:** panel admin UI (`apps/admin`: antrean review, pratinjau dokumen, keputusan), lalu landing page, lalu web push.
- **Branch:** `main`. Commit pertama `49bbba3`.

## Milestone (dari PRD)

| Milestone | Status | Catatan |
|---|---|---|
| M1: Backend inti (minggu 1–3) | 🟡 | API ✅, portal registrasi ✅, landing page ⬜, panel admin UI ⬜ (API admin sudah ✅) |
| M2: SDK web (minggu 3–5) | 🟡 | `@siagasos/js` + `@siagasos/react` ✅, publish npm ⬜, demo React ⬜ (demo vanilla ✅) |
| M3: Dashboard & notifikasi (minggu 5–7) | 🟡 | SSE + email ✅, UI dashboard ✅ (peta + bunyi + notifikasi browser), web push ⬜ |
| M4: SDK Android (minggu 7–9) | ⬜ | |
| M5: Pilot (minggu 10–12) | ⬜ | Uji beban, dokumentasi, 2–3 klien pilot |

## Checklist rinci

### Backend `apps/api`
- ✅ Skema Postgres + RLS + `COMMENT ON` ([migrations/001_init.sql](apps/api/migrations/001_init.sql))
- ✅ Runner migrasi (`pnpm migrate`), tsup build ke `dist/`
- ✅ Registrasi perusahaan, verifikasi email, kirim ulang verifikasi, login, `/portal/me`
- ✅ Unggah dokumen: maks 5 MB, cek magic bytes PDF/JPG/PNG, enkripsi AES-256-GCM, versi lama disimpan (`superseded_at`)
- ✅ Submit ke review dengan validasi dokumen wajib per bentuk usaha (PT/Yayasan butuh akta + SK; PIC bukan direksi butuh surat kuasa)
- ✅ Panel admin API: login password + TOTP, antrean + `sla_warning` 36 jam kerja, detail + checklist, signed URL 5 menit, tandai dokumen, keputusan, disable/enable app, stats
- ✅ Email setiap status berubah (tanpa `SMTP_URL`, email hanya ditulis ke log)
- ✅ Daftar ulang setelah ditolak > 30 hari (akun lama diarsipkan, tidak dihapus)
- ✅ App CRUD, kunci pk/sk live/test, rotate (masa tenggang 0–72 jam), revoke, source, log webhook
- ✅ Mode test: hanya kunci test sebelum approved, 50 laporan/hari, `pk_live_` → 403 `account_not_approved`
- ✅ SDK API: config, create report (idempotency), status, live location, cancel
- ✅ Cek Origin / `X-SOS-Bundle`, rate limit per key / IP / reporter_ref (fail-open)
- ✅ Secret-key API `/v1/reports`, `/v1/webhooks/test`
- ✅ Webhook HMAC + worker retry eksponensial hingga 24 jam
- ✅ Realtime SSE `/portal/reports/stream` lewat Redis pub/sub (multi-instance)
- ✅ Timeline laporan, ekspor CSV (aman dari formula injection), audit log akses detail laporan
- ✅ Undang tim (admin/responder), terima undangan, ubah role/nonaktifkan
- ✅ Smoke test end-to-end 59 cek ([src/scripts/smoke.ts](apps/api/src/scripts/smoke.ts))
- ⬜ Web push responder (VAPID + tabel `push_subscriptions`)
- ⬜ OpenAPI spec untuk `/v1` dan `/v1/sdk`
- ⬜ Antivirus (ClamAV) saat unggah, hapus otomatis dokumen akun ditolak setelah 90 hari
- ⬜ Notifikasi aktif ke admin saat review > 36 jam kerja (sekarang baru flag di antrean)
- ⬜ Retensi / anonimisasi laporan per app (UU PDP), endpoint hapus data pengguna akhir
- ⬜ Storage driver S3/GCS/MinIO (sekarang disk lokal terenkripsi)
- ⬜ Unit test API (vitest sudah terpasang, belum ada test)
- ⬜ Hari libur nasional di perhitungan jam kerja

### SDK
- ✅ `@siagasos/js`: init, trigger, cancel, on('status'|'queued'|'sent'|'error'), antrian offline IndexedDB → localStorage → memori, retry backoff, polling 4 dtk, live location, build ESM/CJS/IIFE, 3,2 KB gzip, 5 unit test
- ✅ `@siagasos/react`: `SOSProvider`, `useSOS`, `SOSButton` (tahan N detik, cincin progres, tombol batal, label TEST, teks penerima, `tel:110`)
- ⬜ Publish npm (org `@siagasos`, Changesets, GitHub Actions)
- ⬜ Persetujuan lokasi (consent) sebelum izin pertama, sesuai UU PDP
- ⬜ Demo React (`examples/react-demo`)
- ⬜ SDK Android, iOS, Flutter, React Native

### Frontend
- ⬜ `apps/landing`: 7 bagian PRD, Lighthouse ≥ 90 (F-20)
- ✅ `apps/portal` (Vite + React 18 + TS, :5174): registrasi 3 langkah + autosave draf, verifikasi email, status + unggah/unggah ulang dokumen + ajukan, App & kunci (buat, rotasi dengan masa tenggang, cabut, secret tampil sekali), pengaturan origin/bundle/webhook/tampilan tombol, source, log webhook, tim (undang, ubah peran, nonaktifkan) (F-21, F-22)
- ✅ Dashboard responder di `apps/portal` `/dashboard`: daftar + peta Leaflet realtime (SSE), bunyi alert Web Audio + pengingat 20 dtk, banner & judul tab, notifikasi browser, ubah status, catatan, timeline, jejak lokasi live, filter periode/mode/status, ekspor CSV (F-13, F-14, F-15)
- ✅ `pnpm seed:demo`: data demo lewat API sungguhan
- ⬜ `apps/admin`: antrean review, pratinjau dokumen, checklist, keputusan (F-23, F-24)
- ⬜ Test E2E Playwright di repo (sementara hanya skrip ad-hoc di luar repo)

### Infra / ops
- ✅ `docker-compose.yml` (postgres :5455 + role `siagasos_app`, redis :6380)
- ⬜ CI: typecheck + unit test + smoke dengan service container
- ⬜ Deploy minimal 2 instance API, Postgres terkelola, backup harian + PITR 7 hari
- ⬜ Monitoring uptime, alert bila error > 1% selama 5 menit, status page

---

## Cara menjalankan (ringkas)

```bash
docker compose up -d            # atau Postgres.app; lihat catatan di bawah
cp apps/api/.env.example apps/api/.env
pnpm install && pnpm migrate
pnpm dev:api                    # :4000
pnpm dev:portal                 # :5174
pnpm seed:demo                  # demo@siagasos.test / demo12345
pnpm smoke                      # API harus sedang jalan
pnpm --filter @siagasos/js test
pnpm -r typecheck
```

## Catatan penting / jebakan

- **API wajib konek sebagai `siagasos_app`** (non-superuser, `NOBYPASSRLS`). Superuser selalu melewati RLS, jadi isolasi tenant diam-diam tidak berlaku.
- **Mesin dev ini tidak punya Docker. DB dev = server Postgres.app utama di :5433** (`var-17`, dipakai bersama KaryawanAI & sekolahkita), database `siagasos`, role `siagasos_app` (non-superuser, `NOBYPASSRLS`). Superuser `postgres` hanya untuk membuat role/DB, jangan dipakai API. Port 5434 milik `commerceos`, jangan disentuh. `docker-compose.yml` / `.env.example` tetap memakai :5455 untuk mesin dengan Docker.
- **Redis lokal (:6379) dipakai bersama project lain**, jadi `.env` dev memakai `redis://localhost:6379/9`. Pub/sub tidak terpisah per DB index, tapi channel `rt:acc:*` cukup unik.
- Konteks tenant: semua akses ke tabel ber-RLS harus lewat `withTenant(accountId, fn)`. Admin/job lintas tenant memakai `withPlatform(fn)`.
- Cache kunci in-process 30 detik. `invalidateKeyCache()` hanya membersihkan instance lokal; instance lain mengikuti TTL (tetap ≤ 60 detik sesuai PRD).
- **Port 5173 dipakai project lain (`sekolahkita`)**, jadi portal jalan di :5174. Saat dev, jalankan API dengan `PORTAL_URL=http://localhost:5174` supaya tautan verifikasi/undangan benar.
- **Route portal baru harus di-mount dengan `app.use(path, portalCors)`**, bukan hanya `app.get(..., portalCors, ...)`, karena preflight OPTIONS dari browser tidak ter-handle (bug ini sempat terjadi di `/portal/me`). Smoke test via fetch Node tidak mendeteksinya.
- Tile peta: OSM standar + CSS filter. CARTO butuh API key.
- Express 5: `req.params.x` bertipe `string | string[]`, bungkus dengan `String()`.
- Bila mengubah perilaku API, jalankan ulang `pnpm smoke`, lalu perbarui README (daftar endpoint) dan `docs/STATUS.md`.

---

## Log session

### 2026-11-21 — Session 1: scaffold + M1 backend + SDK web
- Membuat monorepo pnpm baru `siagasos` dari PRD + Konsep Teknis.
- Selesai: seluruh API M1 (lihat checklist), `@siagasos/shared`, `@siagasos/js`, `@siagasos/react`, demo vanilla, README, `docs/STATUS.md`.
- Diuji: smoke 59/59 ✅, unit test SDK 5/5 ✅, typecheck semua package ✅, latensi SSE ~19 ms, POST report ~23 ms.
- Bug yang ditemukan & diperbaiki: subscriber Redis gagal `psubscribe` saat startup karena offline queue dimatikan; `access_token` SSE tercatat di log (sekarang URL dicatat tanpa query).
- Keputusan desain (RLS per `account_id`, rate limit fail-open, cancel hanya saat `open`, dll.) dicatat di `docs/STATUS.md`.
- Belum: frontend, web push, OpenAPI, publish npm, CI, SDK Android.

### 2026-11-21 — Session 2: portal + dashboard responder (UI)
- Design system dari skill `ui-ux-pro-max` → [docs/DESIGN.md](docs/DESIGN.md) (Plus Jakarta Sans, merah hanya untuk darurat, a11y, light/dark).
- Baru: `apps/portal` (satu app untuk portal + dashboard; keputusan dicatat di `docs/STATUS.md`), `apps/api/src/scripts/seed-demo.ts` (`pnpm seed:demo`).
- Bug API diperbaiki: preflight CORS `/portal/me` tidak dijawab (route dipasang dengan `app.get`), jadi login dari browser gagal.
- Diuji: smoke 59/59 ✅, `pnpm -r typecheck` ✅, `vite build` ✅ (bundle utama 74 KB gzip, Leaflet di-lazy-load), E2E Playwright + Chrome headless (registrasi → verifikasi → unggah → app/kunci → SOS realtime → terima + catatan → undang tim, plus 375 px dark mode) tanpa error konsol dan tanpa scroll horizontal.
- Belum: panel admin UI, landing, web push, test E2E di repo/CI, publish npm.
- DB dev dipindah dari cluster sementara :5455 ke Postgres.app :5433 (pg_dump/pg_restore, data demo ikut). Smoke 59/59 ✅ di :5433.
