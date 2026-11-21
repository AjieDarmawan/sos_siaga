# PROGRESS — SiagaSOS

> **Baca file ini dulu di awal setiap session.** File ini adalah sumber kebenaran untuk "apa yang sudah ada dan apa yang berikutnya".
> Pemetaan per kebutuhan PRD (F-01 s.d. F-29) ada di [`docs/STATUS.md`](docs/STATUS.md).
> Setelah menyelesaikan satu bagian kerja, tambahkan entri di **Log session** paling bawah dan perbarui checklist.

Legenda: ✅ selesai & teruji · 🟡 sebagian · ⬜ belum

---

## Posisi saat ini

- **Fase:** M1 (backend inti) ✅ + M2 (SDK web) 🟡. Kodenya selesai, tapi belum dipublish ke npm.
- **Berikutnya:** frontend di `apps/*`, dimulai dari portal (registrasi 3 langkah + kelola app/kunci) dan dashboard responder (daftar + peta realtime + bunyi).
- **Branch:** `main`. Commit pertama `49bbba3`.

## Milestone (dari PRD)

| Milestone | Status | Catatan |
|---|---|---|
| M1: Backend inti (minggu 1–3) | 🟡 | API ✅, landing page ⬜, panel admin UI ⬜ (API admin sudah ✅) |
| M2: SDK web (minggu 3–5) | 🟡 | `@siagasos/js` + `@siagasos/react` ✅, publish npm ⬜, demo React ⬜ (demo vanilla ✅) |
| M3: Dashboard & notifikasi (minggu 5–7) | 🟡 | SSE + email ✅, UI dashboard ⬜, web push ⬜ |
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

### Frontend (semua ⬜)
- ⬜ `apps/landing`: 7 bagian PRD, Lighthouse ≥ 90 (F-20)
- ⬜ `apps/portal`: registrasi 3 langkah + autosave draf, halaman status, unggah ulang, kelola app/kunci/source/tim, webhook log (F-21, F-22)
- ⬜ `apps/admin`: antrean review, pratinjau dokumen, checklist, keputusan (F-23, F-24)
- ⬜ `apps/dashboard`: daftar + peta realtime + bunyi alert, ubah status, timeline, filter, ekspor (F-13, F-14, F-15)

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
pnpm smoke                      # API harus sedang jalan
pnpm --filter @siagasos/js test
pnpm -r typecheck
```

## Catatan penting / jebakan

- **API wajib konek sebagai `siagasos_app`** (non-superuser, `NOBYPASSRLS`). Superuser selalu melewati RLS, jadi isolasi tenant diam-diam tidak berlaku.
- **Mesin dev ini tidak punya Docker.** Postgres.app (v17) ada di `/Applications/Postgres.app/Contents/Versions/latest/bin`. Port 5433/5434 milik project lain, jangan dipakai. Saat uji, cluster sementara dibuat dengan `initdb` di port 5455, pakai `-k ''` karena path socket terlalu panjang.
- **Redis lokal (:6379) dipakai bersama project lain**, jadi `.env` dev memakai `redis://localhost:6379/9`. Pub/sub tidak terpisah per DB index, tapi channel `rt:acc:*` cukup unik.
- Konteks tenant: semua akses ke tabel ber-RLS harus lewat `withTenant(accountId, fn)`. Admin/job lintas tenant memakai `withPlatform(fn)`.
- Cache kunci in-process 30 detik. `invalidateKeyCache()` hanya membersihkan instance lokal; instance lain mengikuti TTL (tetap ≤ 60 detik sesuai PRD).
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
