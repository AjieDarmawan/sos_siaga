# PROGRESS — SiagaSOS

> **Baca file ini dulu di awal setiap session.** File ini adalah sumber kebenaran untuk "apa yang sudah ada dan apa yang berikutnya".
> Pemetaan per kebutuhan PRD (F-01 s.d. F-29) ada di [`docs/STATUS.md`](docs/STATUS.md).
> Setelah menyelesaikan satu bagian kerja, tambahkan entri di **Log session** paling bawah dan perbarui checklist.

Legenda: ✅ selesai & teruji · 🟡 sebagian · ⬜ belum

---

## Posisi saat ini

- **Fase:** M1 ✅ (API, landing, portal, panel admin), M2 SDK web 🟡 (belum publish npm), M3 🟡 (dashboard ✅, web push belum).
- **Berikutnya:** cocokkan landing dengan PRD asli (belum ada di repo, minta user → `docs/PRD.md`), web push responder, consent lokasi di SDK, demo React, OpenAPI.
- **Branch:** `main`. Commit pertama `49bbba3`.

## Milestone (dari PRD)

| Milestone | Status | Catatan |
|---|---|---|
| M1: Backend inti (minggu 1–3) | ✅ | API, portal registrasi, landing page (`/`), panel admin UI (`apps/admin`) |
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
- ✅ Media laporan (foto/video/suara) di MinIO `sos-siaga` (kredensial sama dengan tata-warga-be): presigned PUT langsung dari perangkat, verifikasi HEAD, presigned GET 15 mnt, RLS `report_media` (migrasi 002), realtime `report.media_added`, petugas bisa melampirkan juga
- ⬜ Dokumen onboarding masih di disk lokal terenkripsi (bisa dipindah ke MinIO)
- ⬜ Pembersihan media `pending` yang tidak pernah di-complete (cron) + retensi media per app
- ⬜ Unit test API (vitest sudah terpasang, belum ada test)
- ⬜ Hari libur nasional di perhitungan jam kerja

### SDK
- ✅ `@siagasos/js`: init, trigger, cancel, on('status'|'queued'|'sent'|'error'), antrian offline IndexedDB → localStorage → memori, retry backoff, polling 4 dtk, live location, build ESM/CJS/IIFE, 3,2 KB gzip, 5 unit test
- ✅ `@siagasos/react`: `SOSProvider`, `useSOS` (+ `attach`, `attachments`), `SOSButton` (tahan N detik, cincin progres, tombol batal, label TEST, teks penerima, `tel:110`), `SOSAttach` (foto/video kamera, rekam suara MediaRecorder, progres)
- ✅ `@siagasos/js` `attach(id, file, { durationS, onProgress })`: menunggu laporan terkirim bila masih offline, upload XHR dengan progres (3,63 KB gzip)
- ⬜ Publish npm (org `@siagasos`, Changesets, GitHub Actions)
- ⬜ Persetujuan lokasi (consent) sebelum izin pertama, sesuai UU PDP
- ✅ Demo React (`examples/react-demo`, :5176): aplikasi pelapor ala mobile dengan SOS + `SOSAttach`
- ⬜ SDK Android, iOS, Flutter, React Native

### Frontend
- ✅ Landing page di `apps/portal` route `/` (F-20): 7 bagian, animasi CSS + IntersectionObserver (dengan fallback scroll), Lighthouse prod 94/100/100/100. **Belum dicocokkan dengan PRD asli.**
- ✅ Dokumentasi publik `/docs`: mulai cepat, cara kerja, SDK React & JS, lokasi/UU PDP, source, webhook (+ verifikasi Node/PHP), REST API, kode error, checklist go-live
- ✅ `apps/portal` (Vite + React 18 + TS, :5174): registrasi 3 langkah + autosave draf, verifikasi email, status + unggah/unggah ulang dokumen + ajukan, App & kunci (buat, rotasi dengan masa tenggang, cabut, secret tampil sekali), pengaturan origin/bundle/webhook/tampilan tombol, source, log webhook, tim (undang, ubah peran, nonaktifkan) (F-21, F-22)
- ✅ Dashboard responder di `apps/portal` `/dashboard`: daftar + peta Leaflet realtime (SSE), bunyi alert Web Audio + pengingat 20 dtk, banner & judul tab, notifikasi browser, ubah status, catatan, timeline, jejak lokasi live, filter periode/mode/status, ekspor CSV (F-13, F-14, F-15)
- ✅ `pnpm seed:demo`: data demo lewat API sungguhan
- ✅ Tema terang/gelap/sistem + 5 warna aksen di landing, docs, portal, dashboard, admin (tanpa kedip saat load)
- ✅ `apps/admin` (:5175): login password + TOTP, ringkasan (status akun, SLA, laporan 30 hari), antrean review, semua perusahaan (tab status + cari), detail (data, pengguna, dokumen + pratinjau, tandai sesuai/tolak, checklist, keputusan, riwayat, nonaktifkan app) (F-19, F-23, F-24)
- ⬜ Kelola admin platform dari UI (sekarang `pnpm create-admin`)
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
pnpm dev:portal                 # :5174 landing + docs + portal
pnpm dev:admin                  # :5175 panel admin
pnpm seed:demo                  # demo@siagasos.test / demo12345, admin@siagasos.test / admin-demo-12345
pnpm admin:otp                  # kode 2FA superadmin dev
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
- **`~/.npm` berisi file milik root** (npx gagal EACCES). Jangan sudo; pakai `npm_config_cache=<scratchpad>/npmcache npx ...` (mis. untuk Lighthouse).
- **MinIO (s3asia01.tip2.co) membalas 403 untuk objek yang belum ada / baru di-PUT** (eventual consistency). Jangan anggap 403 dari HEAD sebagai error izin.
- Uji upload dari browser butuh origin terdaftar di app (demo React :5176 sudah ditambahkan oleh seed). Chrome headless: `--use-fake-device-for-media-stream` untuk mikrofon palsu.
- Grid CSS dengan konten lebar (tabel, kode) wajib `grid-template-columns: minmax(0, 1fr)`; kolom implisit `auto` membuat halaman scroll horizontal di HP.
- Kelas landing jangan memakai nama `.dash*` (bentrok dengan dashboard di `styles.css`); scene hero memakai prefiks `sc-`.
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

### 2026-11-21 — Session 2 (lanjutan): landing, dokumentasi, panel admin
- PRD asli tidak ditemukan di repo/disk; user minta lanjut. Landing dibuat dengan 7 bagian usulan → perlu dicocokkan dengan PRD.
- Baru: `Landing.tsx` + `landing.css` (hero animasi alur SOS 9 dtk murni CSS/SMIL, reveal on scroll, count-up, bento, tab kode, FAQ), `Docs.tsx` + `docs.css` (scrollspy TOC), `apps/admin` (5 halaman), `scripts/admin-otp.ts`.
- API: `GET /admin/accounts` mendukung `status=all`, cari email PIC, `counts` per status (termasuk `drafting`), dan menyembunyikan akun terarsip.
- Seed: superadmin dev (TOTP tetap), 5 perusahaan prospek (3 di antrean, 1 lewat SLA, 1 melengkapi dokumen, 1 belum verifikasi email); laporan demo tidak diduplikasi saat seed diulang.
- `PORTAL_ORIGINS` ditambah `:5175`.
- Diuji: smoke 59/59 ✅, typecheck 6 paket ✅, build portal & admin ✅, E2E admin (login 2FA → antrean → pratinjau → tolak dokumen → minta revisi → setujui) ✅, tanpa error konsol & tanpa scroll horizontal 390 px, Lighthouse landing 94–95/100/100/100.
- Catatan: DB dev berisi akun sisa smoke/E2E (PT Alfa/Bravo Sejahtera, PT Uji Siaga) yang ikut tampil di panel admin.

### 2026-11-21 — Session 2 (lanjutan): media SOS di MinIO + tema
- Media: migrasi `002_report_media.sql` (RLS), `lib/objectStorage.ts` (AWS SDK v3 ke MinIO), `lib/media.ts`, endpoint SDK/portal/v1, galeri di dashboard (lightbox foto, pemutar video/suara, badge jumlah di daftar, unggah oleh petugas), `attach()` + `SOSAttach`, `examples/react-demo`.
- `.env` API: `S3_*` disalin dari tata-warga-be (`MINIO_*`), bucket `sos-siaga`. Bucket sudah ada, privat, CORS MinIO mengizinkan origin browser.
- Tema: `lib/theme.ts`, `ThemeMenu`, token gelap kini di `:root[data-theme='dark']` (bukan media query), aksen via `data-accent`.
- Bug ditemukan & diperbaiki: HEAD MinIO 403 sesaat setelah PUT (retry), tombol/banner merah kurang kontras di mode gelap.
- Diuji: smoke 67/67 ✅ (8 cek media baru, ke MinIO sungguhan), typecheck 7 paket ✅, build ✅, E2E browser: pelapor (demo :5176) kirim foto + MP4 + rekaman mic → dashboard menampilkan & memutar ketiganya; E2E tema (klik menu, persist, tanpa kedip, mode sistem).
