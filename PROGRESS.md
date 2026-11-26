# PROGRESS — SiagaSOS

> **Baca file ini dulu di awal setiap session.** File ini adalah sumber kebenaran untuk "apa yang sudah ada dan apa yang berikutnya".
> Pemetaan per kebutuhan PRD (F-01 s.d. F-29) ada di [`docs/STATUS.md`](docs/STATUS.md).
> Setelah menyelesaikan satu bagian kerja, tambahkan entri di **Log session** paling bawah dan perbarui checklist.

Legenda: ✅ selesai & teruji · 🟡 sebagian · ⬜ belum

---

## Posisi saat ini

- **Fase:** M1 ✅ (API, landing, portal, panel admin), M2 SDK web 🟡 (belum publish npm), M3 🟡 (dashboard + media ✅, web push belum), **M4 SDK mobile 🟡 sedang dikerjakan** (Flutter/Android/iOS teruji, tombol melayang baru Flutter).
- **Prioritas user (2026-11-21): FOKUS MOBILE DULU, web nanti.**
- **Berikutnya, urut:**
  0. 🟡 **Polmas Keamanan = mockup Opsi A, persis sampai datanya** (kode selesai, tinggal cek visual di HP) (keputusan user 2026-11-25). Acuan: [docs/mockups/polmas-digital.html](docs/mockups/polmas-digital.html). Checklist di bagian "Polmas Digital: samakan dengan mockup" di bawah.
  1. ~~Verifikasi SDK iOS~~ ✅ 20/20 (2026-11-23).
  2. **`SOSFloatingButton`**: Flutter ✅ (2026-11-23). **Sisa: Android (`SOSFloatingButtonView`) dan iOS (SwiftUI `.sosFloatingButton()`)** dengan perilaku sama (permintaan user, meniru `DraggableSosMenu` di `tata-warga-mobile/lib/view/widgets/draggable_sos_menu.dart`):
     tombol bulat kecil melayang di pojok kanan bawah, bisa digeser + menempel ke tepi + posisi diingat (SharedPreferences/UserDefaults), area kosong tidak menangkap sentuhan;
     ketuk → menu **Kirim SOS** (tahan N dtk) / **Telepon 110** / **Telepon 112** (nomor & teks dari `/v1/sdk/config`);
     setelah terkirim → panel status + tombol **Foto / Video / Suara** (rekam TKP singkat, mirip `sos_tkp_page.dart`). Pasang sekali di root app → tampil di semua halaman. Tombol besar `SOSButton` tetap ada.
  3. Contoh app mobile (Flutter `example/`) + uji di emulator Android (AVD `Pixel_7_API_35` tersedia).
  4. Baru lanjut daftar penting: (1) web push responder, (2) consent lokasi/kamera/mikrofon (UU PDP) di semua SDK, (3) ~~cron bersihkan media `pending` + retensi~~ ✅, (4) kompresi video di perangkat sebelum upload.
  - Login satpam: **tanpa OTP** (keputusan user 2026-11-23, `POST /v1/sdk/responder/login`). Template WA `kode_otp` tidak perlu dibuat; `/otp` + `/verify` dibiarkan untuk opsi pengetatan.
  5. Sesudahnya: React Native (`@siagasos/js` + opsi `bundleId`), publish SDK (npm, pub, Maven, SPM), lalu urusan web.
- **Branch:** `main` (user commit sendiri `0ea6a5b fix`). Belum di-commit: `packages/sdk-android` (SiagaSOS.kt, SOSButtonView.kt, test/, README), seluruh `packages/sdk-ios/`, dan `SOSFloatingButton` Flutter.

## Milestone (dari PRD)

| Milestone | Status | Catatan |
|---|---|---|
| M1: Backend inti (minggu 1–3) | ✅ | API, portal registrasi, landing page (`/`), panel admin UI (`apps/admin`) |
| M2: SDK web (minggu 3–5) | 🟡 | `@siagasos/js` + `@siagasos/react` ✅, publish npm ⬜, demo React ⬜ (demo vanilla ✅) |
| M3: Dashboard & notifikasi (minggu 5–7) | 🟡 | SSE + email ✅, UI dashboard ✅ (peta + bunyi + notifikasi browser), web push ⬜ |
| M4: SDK mobile (minggu 7–9) | 🟡 | Flutter ✅ teruji, Android native ✅ teruji, iOS ✅ teruji (selftest 20/20), tombol melayang 🟡 (Flutter ✅, Android/iOS ⬜), React Native ⬜ |
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
- ✅ Retensi laporan per app (`apps.retention_days`, migrasi 006, portal **Pengaturan → Penyimpanan data**) + `DELETE /v1/reporters/:ref` hapus data pengguna akhir (UU PDP)
- ✅ Media laporan (foto/video/suara) di MinIO `sos-siaga` (kredensial sama dengan tata-warga-be): presigned PUT langsung dari perangkat, verifikasi HEAD, presigned GET 15 mnt, RLS `report_media` (migrasi 002), realtime `report.media_added`, petugas bisa melampirkan juga
- ⬜ Dokumen onboarding masih di disk lokal terenkripsi (bisa dipindah ke MinIO)
- ✅ Pembersihan media `pending` yang tidak pernah di-complete (`lib/maintenance.ts`, tiap 10 menit, advisory lock) + OTP kedaluwarsa
- 🟡 Unit test API: 31 test vitest (`apps/api/test/`: nomor WA, schema laporan, jam kerja, kunci, tanda tangan, sniff MIME, rate limit fail-open, penerima WA). Belum: route + RLS (masih lewat smoke)
- ⬜ Hari libur nasional di perhitungan jam kerja

### SDK
- ✅ `@siagasos/js`: init, trigger, cancel, on('status'|'queued'|'sent'|'error'), antrian offline IndexedDB → localStorage → memori, retry backoff, polling 4 dtk, live location, build ESM/CJS/IIFE, 3,2 KB gzip, 5 unit test
- ✅ `@siagasos/react`: `SOSProvider`, `useSOS` (+ `attach`, `attachments`), `SOSButton` (tahan N detik, cincin progres, tombol batal, label TEST, teks penerima, `tel:110`), `SOSAttach` (foto/video kamera, rekam suara MediaRecorder, progres)
- ✅ `@siagasos/js` `attach(id, file, { durationS, onProgress })`: menunggu laporan terkirim bila masih offline, upload XHR dengan progres (3,63 KB gzip)
- ⬜ Publish npm (org `@siagasos`, Changesets, GitHub Actions)
- ⬜ Persetujuan lokasi (consent) sebelum izin pertama, sesuai UU PDP
- ✅ Demo React (`examples/react-demo`, :5176): aplikasi pelapor ala mobile dengan SOS + `SOSAttach`
- ✅ Kontrak lintas SDK: [docs/SDK_PROTOCOL.md](docs/SDK_PROTOCOL.md) (header `X-SOS-Bundle` untuk mobile, antrian offline, polling, lokasi live, lampiran)
- ✅ **Flutter** `packages/sdk-flutter` (pub `siagasos`): `SiagaSOS` (trigger, antrian offline SharedPreferences, polling, lokasi live via `locationProvider`, cancel, `attach` dengan progres), widget `SOSButton` + `SOSFloatingButton`. `flutter analyze` bersih, **11/11 test** (10 unit/widget + 1 integrasi ke API & MinIO: `SIAGASOS_IT=1 flutter test`)
- ✅ **Android native** `packages/sdk-android` (Kotlin, tanpa dependency runtime, minSdk 21, AAR ±73 KB): `SiagaSOS.create(context, …)` / `Builder`, callback + versi `*Blocking`, `SharedPrefsQueueStore`, `AndroidLocationProvider` (LocationManager), `SOSButtonView`. **10/10 test JVM** (9 unit + 1 integrasi): `SIAGASOS_IT=1 ./gradlew :siagasos:testDebugUnitTest` (JAVA_HOME JDK 17)
- ✅ **iOS** `packages/sdk-ios` (Swift Package, iOS 15+/macOS 12): `SiagaSOS` async/await, `UserDefaultsQueueStore`, `CoreLocationProvider`, SwiftUI `SOSButton`. **20/20** lewat `SIAGASOS_IT=1 swift run siagasos-selftest` (15 unit dengan mock `URLProtocol` + 5 integrasi ke API lokal & MinIO). Ada warning Swift 6 `NSLock` di selftest (bukan di SDK)
- ✅ `SOSFloatingButton` Flutter: tombol kecil melayang (pasang di `MaterialApp.builder`), geser + tempel tepi + posisi diingat, area kosong tembus sentuhan, menu tahan-kirim / Telepon 110 (`fallback_phone`) / 112, panel status + batal + Foto/Video/Suara lewat callback `onCapture` (SDK tetap tanpa plugin kamera). 1 widget test
- ✅ Laporan pengaduan: `reports.kind` (`sos`|`pengaduan`, migrasi 003), `complaint_categories` di config, Flutter `complain()` + menu ke-4 di `SOSFloatingButton` (gaya tombol gradien tata-warga). Portal: badge Pengaduan tanpa alarm. Polmas: tampil sebagai jenis pengaduan
- ✅ Flutter `SOSFloatingButton` gaya tata-warga + menu **Riwayat laporan** (`SiagaSOS.history()`, riwayat lokal per pengguna)
- ✅ `SOSFloatingButton` Android native (sekali ketuk kirim, diuji di HP Redmi Android 15). ⬜ iOS
- ⬜ React Native, publish pub.dev / Maven / SPM, contoh app mobile + uji emulator

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

### Polmas Keamanan (`apps/polmas-keamanan`, API `/v1/pk`) — app penerima Nomor Darurat, lihat [docs/POLMAS_KEAMANAN.md](docs/POLMAS_KEAMANAN.md)
- ✅ API `/v1/pk` (login nomor+password / buat password dari Nomor Darurat, peran turunan kontak, dashboard, laporan & riwayat, peta, video, berita, detail + tanggapan, inbox panggilan, notifikasi, analisa, evaluasi, demo SOS), migrasi 011 + 012, worker kecamatan dari GPS. Smoke +20 cek
- ✅ App Flutter: splash Merah Putih, login 2 langkah + login cepat, konfirmasi wilayah GPS, Beranda 5 tab, Laporan (daftar/peta), Riwayat, Analisa+Evaluasi (+PDF), Profil, layar panggilan SOS, detail + aksi. `flutter analyze` bersih, 6 test, APK debug ter-build
- 🟡 Belum diuji di HP (butuh `pnpm seed:pk` + `adb reverse`), belum dicek visual
- ⬜ Push FCM saat app tertutup, antrean offline (FR-13), cache peta/tile produksi, ekspor gambar (FR-21 baru PDF)

### Infra / ops
- ✅ `docker-compose.yml` (postgres :5455 + role `siagasos_app`, redis :6380)
- ⬜ CI (ditunda atas permintaan user 2026-11-23)
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
- **Mobile toolchain di mesin ini:** Flutter 3.47, Android SDK (platform 23–36, AVD `Pixel_7_API_35`), JDK 17 untuk Gradle (`JAVA_HOME=$(/usr/libexec/java_home -v 17)`), Gradle 8.13 + AGP 8.11.1 + Kotlin 2.2.21 ter-cache. **Tidak ada Xcode penuh** (hanya Command Line Tools): Swift package bisa `swift build/run` di macOS, tapi tidak ada XCTest/simulator iOS, makanya ada `siagasos-selftest`.
- **Ada HP fisik tersambung USB** (Redmi `ovskso79wkz9aeww`): `adb` tanpa `-s` menargetkannya. Emulator `Pixel_7_API_35` gagal start (system image ps16k tidak lengkap).
- Unit test Android dikompilasi terhadap `android.jar`: `com.sun.net.httpserver` tidak ada, pakai `FakeHttpServer` (ServerSocket). Hindari `java.time` di kode SDK (minSdk 21).
- Data demo mobile: app "Aplikasi Kurir (Android)" bundle `id.demosiaga.kurir`, kunci live di portal → dipakai uji integrasi SDK mobile.
- **Port 5173 dipakai project lain (`sekolahkita`)**, jadi portal jalan di :5174. Saat dev, jalankan API dengan `PORTAL_URL=http://localhost:5174` supaya tautan verifikasi/undangan benar.
- **Route portal baru harus di-mount dengan `app.use(path, portalCors)`**, bukan hanya `app.get(..., portalCors, ...)`, karena preflight OPTIONS dari browser tidak ter-handle (bug ini sempat terjadi di `/portal/me`). Smoke test via fetch Node tidak mendeteksinya.
- Tile peta: OSM standar + CSS filter. CARTO butuh API key.
- **`~/.npm` berisi file milik root** (npx gagal EACCES). Jangan sudo; pakai `npm_config_cache=<scratchpad>/npmcache npx ...` (mis. untuk Lighthouse).
- **MinIO (s3asia01.tip2.co) membalas 403 untuk objek yang belum ada / baru di-PUT** (eventual consistency). Jangan anggap 403 dari HEAD sebagai error izin.
- Uji upload dari browser butuh origin terdaftar di app (demo React :5176 sudah ditambahkan oleh seed). Chrome headless: `--use-fake-device-for-media-stream` untuk mikrofon palsu.
- Grid CSS dengan konten lebar (tabel, kode) wajib `grid-template-columns: minmax(0, 1fr)`; kolom implisit `auto` membuat halaman scroll horizontal di HP.
- Kelas landing jangan memakai nama `.dash*` (bentrok dengan dashboard di `styles.css`); scene hero memakai prefiks `sc-`.
- **`pnpm smoke` berturut-turut cepat bisa gagal acak** (429 di cek SDK mana saja): rate limit SDK 60/menit per IP, satu run sudah mendekati batas. Tunggu ±1 menit antar run.
- Express 5: `req.params.x` bertipe `string | string[]`, bungkus dengan `String()`.
- Bila mengubah perilaku API, jalankan ulang `pnpm smoke`, lalu perbarui README (daftar endpoint) dan `docs/STATUS.md`.

---

## Polmas Digital: samakan dengan mockup (Opsi A v2)

Acuan tunggal: [docs/mockups/polmas-digital.html](docs/mockups/polmas-digital.html) (link pratinjau privat: https://claude.ai/artifact/5kbdvDjHnJ4UG6j1GYDJ9C).
Target: tampilan, teks, urutan, dan **data** sama dengan mockup. Data contoh di mockup (Kec. Menteng, 312 laporan) hanya contoh; di app semua angka dari API.
Status data: ✅ API sudah ada · 🟡 ada tapi perlu diubah · ⬜ belum ada.

**Struktur & navigasi**
- ✅ Navigasi bawah 4 tab (Beranda, Laporan, Analitik, Profil), tanpa tombol SOS; badge Laporan = `open_reports` dari `/inbox`.
- ✅ Splash & Login sesuai mockup (satu kartu nomor + kata sandi; login pertama berubah jadi "Buat kata sandi"; "Ingat di perangkat ini" sungguhan).
- ✅ Layar Riwayat/Berita/Video/Notifikasi/Wilayah dibuang; "Saya" jadi cakupan di filter Laporan. Paket `fl_chart`, `share_plus`, `pdf`, `path_provider` dilepas.
- ✅ Ikon & nama: ikon peluncur Android (adaptif + monokrom) & iOS dari lambang perisai-bintang, ikon notifikasi FCM `ic_stat_polmas`, layar pembuka bawaan navy + lambang (Android 12+ juga), nama tampil "Polmas Digital". Sumber render: SVG → Chrome headless (skrip di luar repo; lambang = `PolmasEmblem` di `lib/widgets/ui.dart`).

**Beranda** ✅ header, kartu merah SOS (SOS baru terbaru; tidak ada → kartu "Tidak ada SOS yang menunggu"), 4 angka (`/dashboard`), Tindak Lanjut Terbaru kartu/tabel.

**Laporan** ✅ kartu 9 kolom (`ReportCard`), tabel 9 kolom (`ReportTable`, otomatis saat HP miring), chip status + jumlah (`counts`), chip ekosistem, cari, filter periode/jenis/cakupan.

**Detail** ✅ header + nomor tiket + langkah status, peta + Rute (Google Maps), info, lampiran (foto/video/suara diputar di tempat), riwayat, bilah "Tulis tindak lanjut…" + Perbarui (pilih status yang diizinkan server).

**Analitik** ✅ 4 tab dari `/analytics/summary` + `/evaluation`, filter periode (7/30/90 hari) + ekosistem. Target garis respons = SLA SOS server (15 menit).

**Profil** ✅ ubah nama (pensil di avatar), label "HP ini menerima SOS", kinerja 30 hari (`/me/stats`), penugasan terkunci (+ ganti peran bila > 1), Notifikasi SOS, Tema gelap, Ubah kata sandi (`/me/password`), Perangkat terdaftar (`/me/devices`, nama HP via `device_info_plus`), Bantuan, Tentang, Keluar.

**Belum**
- ⬜ Cek visual di HP: APK debug sudah terpasang di HP (24117RN76O, `adb reverse tcp:4000`), tapi HP terkunci saat sesi ini. Login demo `0800 111 0002` / `demo1234` setelah `pnpm seed:pk`.
- ⬜ `GoogleService-Info.plist` iOS (push iOS belum aktif).

**Keputusan user (2026-11-25)**
1. Layar Riwayat, Berita, Video, Notifikasi, Wilayah **dibuang** dari app.
2. Status tugas + shift **tidak perlu**: dihapus dari Beranda & Profil (mockup ikut diperbarui).
3. Kategori **mengikuti API** apa adanya (label dari `categoryLabel`), tidak dipetakan ulang.

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

### 2026-11-21 — Session 2 (lanjutan): SDK mobile
- Permintaan user: SDK mobile (Flutter, Android native, dll.) dulu, lalu 4 item penting (web push, consent, retensi media, kompresi video). Kemudian user menegaskan **fokus mobile, web nanti**, dan minta **tombol SOS melayang seperti tatawarga mobile**.
- Selesai & teruji: `docs/SDK_PROTOCOL.md`, SDK Flutter (10/10), SDK Android native (10/10), keduanya termasuk uji integrasi ke API lokal + MinIO (trigger live dengan bundle `id.demosiaga.kurir`, lampiran ready, bundle salah → `bundle_not_allowed`, file terbaca dari portal, batal).
- Ditulis, belum terverifikasi: SDK iOS (`packages/sdk-ios`). Run `swift run siagasos-selftest` terhenti oleh user sebelum hasil keluar.
- Saat ini, memasang SDK **tidak mengubah tampilan apa pun secara otomatis**: developer menaruh `SOSButton` (tombol bulat besar, tahan N dtk) sendiri. Tombol melayang belum ada → pekerjaan berikutnya (lihat "Posisi saat ini").

### 2026-11-23 — Session 3: jalankan bersama polmas, iOS terverifikasi, tombol melayang Flutter
- Permintaan user: jalankan siagasos + polmas (`../polmas`) berdampingan, DB login berjenjang polmas di Postgres :5433 (sama dengan siagasos), lalu lengkapi yang kurang di siagasos.
- polmas (repo terpisah): DB `polmas` + role `polmas_app` di :5433, dev server `npx vite --port 5177` (5173 = sekolahkita, 5174–5176 = siagasos).
- Sempat salah sasaran: login berjenjang dibuat dulu di `tip-media-intelligence` (DB `tip_auth` di :5433, belum di-commit) sebelum user meralat ke polmas.
- Diverifikasi: `pnpm smoke` 67/67 ✅, `pnpm -r typecheck` ✅, SDK iOS selftest 20/20 ✅ (pertama kali lolos), Flutter 11/11 ✅.
- Baru: `packages/sdk-flutter/lib/src/sos_floating_button.dart` + `test/floating_button_test.dart`, README Flutter.
- Jebakan: di widget test, upload `StreamedRequest` lewat `MockClient` tidak selesai di fake-async; harus diselingi `tester.runAsync(...)` + `pump`.
- Belum: `SOSFloatingButton` Android & iOS, contoh app Flutter + uji emulator, lalu daftar penting (web push, consent UU PDP, cron media pending, kompresi video).


### 2026-11-23 — Session 4: rencana integrasi ke Polmas
- Permintaan user: klien memasang SDK/kunci SiagaSOS → laporan masuk DB siagasos → tampil juga di dashboard Polmas per satuan (pilot klien: tata-warga).
- Hasil: rencana [docs/INTEGRASI_POLMAS.md](docs/INTEGRASI_POLMAS.md) (wilayah PostGIS per laporan, `share_polmas` per app, API mitra `/partner/v1` + RLS `withPartner()`, proxy di server Polmas, tata-warga lewat SDK Flutter + webhook ke tata-warga-be). Belum ada kode; 6 keputusan terbuka di §8.
- Temuan: PostGIS 3.5.6 tersedia di :5433. tata-warga-mobile sudah punya SOS sendiri (`/sos`, `/keamanan/sos`) ke tata-warga-be.

### 2026-11-23 · Polmas: konsol SOS memakai data nyata SiagaSOS
- Repo `../polmas`: halaman Laporan & SOS dirombak jadi pusat komando (peta SOS langsung, statistik, strip SOS geser, arus laporan, panel detail dengan kontak pelapor + media TKP dari MinIO). Data contoh tetap ada, ditambah SOS nyata dari DB SiagaSOS lewat proxy server Polmas `/api/sos` → `/v1/reports` (kunci `sk_live_` per app di `polmas/.env.local`), polling 5 dtk + bunyi saat SOS baru.
- Aksi petugas Polmas → `PATCH /v1/reports/:id` (acknowledged / in_progress / resolved / false_alarm + catatan "[satuan · petugas]"). "Teruskan ke 110" = in_progress + catatan (diingat di browser).
- Dibuat 2 kunci secret live baru untuk app demo (kunci lama tetap aktif) dan 3 SOS live contoh di Kota Bogor (Aplikasi Kurir).
- 🟡 (2026-11-26: `/partner/v1` sudah ada, lihat log di bawah; cakupan per satuan belum) API mitra `/partner/v1` dengan cakupan wilayah di server (docs/INTEGRASI_POLMAS.md tahap 1–3). Sekarang cakupan Polsek masih di UI (kecamatan terdekat ±4 km).

### 2026-11-23 · Laporan pengaduan di tombol melayang
- API: migrasi `003_report_kind.sql` (`reports.kind`), `createReportSchema.kind` (pengaduan wajib uraian ≥ 5), `complaint_categories` di `/v1/sdk/config` + portal `sdk_config`, kuota pengaduan terpisah (5/jam per reporter), tanpa email darurat, `/locations` → `accepted:false`, filter `?kind=` di `/v1/reports`. Smoke **72/72** (+5 cek pengaduan).
- Flutter: `SiagaSOS.complain()`, `ReportKind`, `SdkConfig.complaintCategories`; `SOSFloatingButton` jadi 4 tombol gradien (Kirim SOS tahan / Telepon 110 / Telepon 112 / Laporan pengaduan) + lembar form (jenis, uraian, foto opsional, status terkirim/antrian). `flutter analyze` bersih, **12/12** test (11 + integrasi). Perbaikan: nomor laporan pendek tidak lagi crash.
- Portal: badge "Pengaduan", tanpa bunyi/notifikasi browser. Polmas: pengaduan SiagaSOS tampil sebagai jenis pengaduan (tanpa bunyi, tombol "Tidak valid").
- Belum dicek visual di emulator. Android/iOS: `complain()` + menu pengaduan menyusul bersama tombol melayang native.
- Dokumentasi portal `/docs`: bagian baru **SDK Mobile** (tabel Flutter/Android/iOS, contoh kode tiap platform, `SOSFloatingButton` + tabel 4 aksi & props) dan **Laporan pengaduan** (perbandingan SOS vs pengaduan, `complain()`, contoh API); `kind` di payload webhook, filter `kind` di REST, error 422 & batas pengaduan, checklist go-live mobile. Portal Pengaturan app: isian **Jenis pengaduan** (`complaint_categories`). README iOS baru; README Android mencatat menu pengaduan belum ada.

### 2026-11-23 · Polesan tampilan production (skill ui-ux-pro-max)
- Token portal/admin "Soft UI Evolution" (lihat docs/DESIGN.md). Admin: kartu ringkasan berikon & bisa diklik. App & kunci API: ikon app, label Web/Mobile, lencana kunci per mode (`LIVE ×2` saat rotasi, bukan dobel).
- Dashboard: **bug peta** diperbaiki (kontainer setinggi daftar → peta tampak menghadap laut), ringkasan angka, filter jenis, ikon kategori, alarm/banner hanya SOS, tombol "Tampilkan semua laporan".
- Landing: klaim usang dihapus ("segera Android"), kartu tombol melayang + pengaduan, tab kode Flutter/Android/iOS, FAQ platform diperbarui.
- Typecheck semua paket lolos, build portal & admin lolos. Diverifikasi lewat screenshot desktop terang/gelap + mobile 390 px. Flutter SDK tidak diubah di putaran ini.

### 2026-11-23 · Flutter `SOSFloatingButton`: gaya tata-warga + riwayat laporan
- **Bug teks** diperbaiki: lapisan tombol (di `MaterialApp.builder`, di atas Navigator) tidak punya `Material`, jadi teks bilah kirim & keterangan jatuh ke gaya darurat Flutter (monospace + garis bawah kuning). Sekarang dibungkus `Material(type: transparency)`; area kosong tetap tembus sentuhan.
- Tampilan disamakan dengan `DraggableSosMenu` tata-warga: tombol bulat 48 px berikon lonceng, tombol aksi 48 px radius 12 w600, gradien 3 warna 110/112, urutan dari tombol bulat: 112, 110, kirim SOS, Pengaduan, Riwayat. Props baru `sosLabel`, `sosColors`, `callLabel` (commerceOS POS: "EWS Alert" kuning, "Call 110/112"). Default `size` 56 → 48.
- **Riwayat laporan**: `SiagaSOS.history()` + menu ke-5. Laporan yang terkirim dicatat di perangkat (`historyStore`, default SharedPreferences per api key + `user.ref`, maks. 50), status yang belum selesai diperbarui lewat `GET /v1/sdk/reports/:id` saat riwayat dibuka. **Tanpa perubahan API**: tidak ada endpoint "daftar laporan saya" (kunci publishable tidak boleh bisa membaca laporan orang lain).
- `flutter analyze` bersih, **12/12 test** (+1 skip integrasi): test pengaduan memeriksa riwayat; test baru untuk label EWS + gaya teks.
- Belum: sirene lokal & alur rekam TKP ala tata-warga; Android/iOS native belum punya riwayat.
- Lanjutan: menu utama jadi 4 tombol persis tata-warga (atas → bawah: EWS/kirim SOS, Call 110, Call 112, **Laporan**). Laporan membuka sub-menu **Pengaduan / Riwayat laporan / Kembali** (bila hanya satu yang aktif, langsung terbuka). Test memeriksa urutan dan sub-menu; 12/12 lulus.

### 2026-11-23 · Alur EWS tata-warga di `SOSFloatingButton` + catatan pelapor
- **API**: `POST /v1/sdk/reports/:id/notes` `{note}` → event `note` (actor reporter) di timeline + realtime `report.note_added`, tanpa webhook; 422 `invalid_note`, 409 `report_closed`, rate limit 10/10 menit. Tanpa migrasi (pakai `report_events.note`). README + SDK_PROTOCOL diperbarui. `pnpm smoke` **75 cek lolos** (+3 cek catatan), typecheck API lolos.
- **Flutter SDK**: `holdSeconds: 0` = sekali ketuk kirim; `SosSiren` (antarmuka, suara diputar app host) → tombol bulat "SENYAP" selama sirene aktif; setelah terkirim popup **SOS terkirim · Rekam kondisi TKP?** (chip maks. N detik / lokasi otomatis / catatan) → `onCapture(video)` (lapisan SDK disembunyikan selama kamera host terbuka) → catatan → unggah video + `SiagaSOS.addNote()` → "Rekaman TKP terkirim"; batal dengan konfirmasi. `tkpPrompt: false` = panel lama. **13/13 test** (+1 alur EWS lengkap).
- Pemakai pertama: commerceOS POS (sirene `audioplayers` + aset tata-warga, kamera TKP 5 dtk bersuara).
- Perbaikan (uji di HP): saat kamera TKP terbuka, lapisan tombol dilepas dari `Stack` → posisi lapisan lembar bergeser → Overlay-nya dibuat ulang → crash "entry is already present in a different Overlay". Lapisan sekarang selalu ada (disembunyikan dengan `Offstage`) dan diberi key. Test alur EWS kini memakai kamera palsu dengan jeda (mereproduksi crash di kode lama), 13/13 lulus.

### 2026-11-23 · `SOSFloatingButton`: tanpa mode "AKTIF" (persis tata-warga)
- Selama SOS belum selesai, menu tetap EWS / 110 / 112 / Laporan (dulu tombol jadi abu-abu "AKTIF" dan membuka panel status berbeda — membingungkan saat SOS dari antrian offline terkirim belakangan). Status tampil di keterangan menu ("SOS aktif: …"), tombol bulat tetap merah "SOS" dengan titik kuning kecil.
- Batal salah tekan pindah ke **Laporan → Riwayat laporan** (tombol "Batalkan (salah tekan)" pada SOS berstatus `open`). Panel status lama + tombol Foto/Video/Suara di panel dihapus; lampiran lewat alur Rekam TKP.
- 13/13 test (test pertama kini memeriksa menu saat SOS aktif + batal lewat riwayat).

### 2026-11-23 · Penerima SOS + notifikasi WhatsApp (gaya tata-warga)
- **Migrasi 004**: `sos_recipients` (nama, nomor 62xx, per app atau khusus satu source, aktif/nonaktif; RLS `tenant_isolation`) + `reports.emergency_contacts` (kontak darurat pribadi dari SDK).
- **API**: portal `GET|POST /portal/apps/:id/recipients`, `PATCH|DELETE /:recipientId` (owner/admin, audit). SDK `POST /v1/sdk/reports` menerima `emergency_contacts` (maks. 5, hanya SOS). Setelah commit + respons, `dispatchSosWhatsApp` mengirim template WA (nama pelapor, lokasi = app · source, link maps) ke penerima app/source + kontak pribadi, nomor ganda sekali; mode test tidak mengirim. Pagar spam: maks. 5 WA per nomor per jam (Redis, fail-open). Hasil per nomor dicatat di timeline (`type = whatsapp`).
- **Provider WA** (`lib/whatsapp.ts`): MetaDev / Qontak / stub, nama env sama dengan tata-warga (`METADEV_*`, `PANIC_QONTAK_*`, `WA_PROVIDER`). Default stub (tanpa WA keluar).
- **Portal**: tab **Penerima SOS** di detail app (tambah, cakupan source, aktif/nonaktif, hapus); timeline menampilkan event WhatsApp.
- **Flutter SDK**: `SiagaSOS.emergencyContacts()/setEmergencyContacts()` (SharedPreferences per api key + `user.ref`), dikirim otomatis bersama SOS; menu **Laporan → Nomor darurat**.
- Smoke **81 cek lolos** (+6), typecheck semua paket lolos, SDK **14/14 test**.
- Akun WA = akun MetaDev tata-warga (template `ewsbutton`); `.env` lokal sudah diisi (disalin dari tata-warga-be, tidak di-commit). Nomor **0800…** = nomor uji: dicatat, tidak pernah dikirimi WA (smoke memakai ini, jadi aman dijalankan dengan kredensial asli).
- Dokumentasi publik `/docs`: bagian **Penerima SOS & WhatsApp** (portal, nomor darurat SDK, isi pesan & hasil, env MetaDev/Qontak) + baris tabel SOS vs pengaduan + checklist go-live.
- ⬜ Deploy ke `sos.tip2.co` (migrasi 004 + env WA MetaDev yang sama); app commerceOS POS (`com.tip.kasir`) perlu didaftarkan di portal production untuk kunci `pk_live_` yang valid di sana.
- Lanjutan (permintaan: "nomor darurat ada di aplikasi seperti tata-warga, ada CRUD-nya"): `EmergencyContact` kini punya **jabatan** (`role`) dan **aktif/nonaktif**; maks. **5 aktif** (server `MAX_EMERGENCY_CONTACTS` 3 → 5), 10 tersimpan; hanya yang aktif dikirim, nama ke server "Nama (Jabatan)". `setEmergencyContacts` menolak nama kosong / nomor ganda / tidak valid / >5 aktif dengan `ArgumentError` berbahasa Indonesia. Dokumentasi `/docs#wa-kontak` menjelaskan halaman CRUD di app host + contoh kode. SDK **15/15 test**, smoke **82 cek**.
- UI menu SOS dirapikan (masukan user dari HP): keterangan "SOS aktif: …" dihapus (cukup titik di tombol bulat); tombol tidak lagi lebar tetap 172 px, lebarnya = label terpanjang (`IntrinsicWidth`) dan semuanya sama lebar; ikon di lingkaran putih transparan. Sub-menu **Laporan** jadi satu kartu putih ringkas: "← Laporan" lalu Pengaduan / Riwayat laporan / Nomor darurat (ikon berwarna di lingkaran pucat). Keterangan error / MODE TEST tidak ikut melebarkan tombol. SDK 15/15 test (cek: tidak ada teks "SOS aktif", 4 tombol sama lebar).
- **Detail Riwayat laporan**: API `GET /v1/sdk/reports/:id/detail` (uraian, lokasi, timeline dengan nama petugas / "Anda" / "Sistem", ringkasan WA "terkirim ke N penerima", media + URL baca 15 menit; tanpa nomor HP pelapor / penerima, smoke memeriksa). SDK `SiagaSOS.reportDetail()` + `ReportDetail` / `ReportTimelineEntry` / `ReportMediaItem`; di sheet Riwayat, ketuk laporan → detail (kartu status + pesan petugas, waktu dikirim/diterima/selesai, uraian, lokasi + "Buka peta", galeri foto/video, riwayat status bergaya timeline, batal salah tekan). Prop baru `onOpenUrl` (peta & lampiran). Docs `/docs#floating` diperbarui (menu sekarang, Riwayat + detail, props). Smoke **84 cek**, SDK **15/15 test**.

### 2026-11-23 · Login satpam (responder) dari Nomor Darurat + push FCM sirene
- Permintaan user (POS): satpam login dengan nomor yang dimasukkan kasir di Nomor Darurat, lalu dapat FCM + sirene setiap EWS Alert.
- Migrasi `005_responders.sql`: `emergency_contacts` (salinan server Nomor Darurat per `reporter_ref`), `responder_otps`, `responder_sessions` (token `rsp_` hash + `fcm_token`), GIN `reports.emergency_contacts`, actor_kind `responder`.
- API: `/v1/sdk/contacts` (GET/PUT), `/v1/sdk/responder/{otp,verify,me,device,logout,reports,reports/:id,reports/:id/status}` (`src/routes/responder.ts`, `src/lib/responders.ts`).
  - Sesi dicabut otomatis bila nomor dihapus dari semua Nomor Darurat (401 `responder_not_registered`).
  - Satpam hanya melihat SOS yang snapshot `emergency_contacts`-nya memuat nomornya.
- `src/lib/fcm.ts`: FCM HTTP v1 tanpa dependency baru (JWT RS256 via jsonwebtoken), channel Android `siagasos_sos` + suara `sos_siren`, token mati dikosongkan. Dipanggil setelah commit, tidak memblokir jalur SOS; ringkasan di timeline (type `push`).
- OTP WA: `sendOtpWhatsApp` (MetaDev saja, template `METADEV_OTP_TEMPLATE_NAME`, default `kode_otp`). Nomor uji 0800 tidak dikirimi WA.
- SDK Flutter: `SiagaSOS.setEmergencyContacts` kini mengembalikan bool tersinkron + `syncEmergencyContacts()` (dirty/synced, pulihkan di perangkat baru); kelas baru `SiagaSOSResponder` (`lib/src/responder.dart`).
- **Teruji:** smoke 99 cek (15 baru), `pnpm -r typecheck`, SDK Flutter 17 test + analyze bersih.
- **Belum:** template OTP `kode_otp` harus dibuat & APPROVED di MetaDev; `FCM_SERVICE_ACCOUNT` (project `pushnotif-6937d`) di server; deploy migrasi 005 ke `sos.tip2.co`; push SDK ke remote yang dipakai POS (GitLab `dev`). SDK Android/iOS native belum punya klien responder.

### 2026-11-23 · Keandalan: job pembersihan, unit test API
- User: OTP tidak perlu (login satpam langsung dengan nomor sudah ada), lanjut yang penting.
- `apps/api/src/lib/maintenance.ts` + `MAINTENANCE_WORKER` (default true): hapus media `pending` basi (objek MinIO + baris) dan OTP kedaluwarsa, tiap 10 menit, `pg_try_advisory_xact_lock` untuk multi-instance. Smoke +1 cek (ghost media dimundurkan 3 jam → terhapus, media ready tetap).
- Unit test API pertama: `apps/api/vitest.config.ts` (env dummy, tanpa DB/Redis) + `test/{shared,lib,failopen}.test.ts`, **31/31 lolos**.
- CI sempat dibuat lalu dihapus: user minta dilewati dulu.
- Retensi UU PDP: migrasi `006_retention.sql` (`apps.retention_days`, FK webhook → SET NULL, 2 indeks), job pembersihan menghapus laporan tertutup melewati retensi (test: 30 hari), `DELETE /v1/reporters/:ref` (secret key), isian portal **Penyimpanan data**, docs publik + README + STATUS (keputusan 19).
- Teruji: `pnpm smoke` **108 cek** (+7: pending basi, validasi & simpan retensi, retensi live/test/aktif, hapus data dengan kunci test vs live, data benar-benar hilang), `pnpm -r typecheck` lolos, unit test API 31/31. UI portal belum dicek visual.
- Belum: consent lokasi/kamera/mikrofon di SDK, web push, kompresi video, deploy migrasi 006 ke `sos.tip2.co`.

### 2026-11-23 · Android native: client setara Flutter + `SOSFloatingButton` (sedang diuji)
- Urutan dari user: Android native → iOS → consent UU PDP.
- Client Kotlin: `complain()`, `history()`, `reportDetail()`, `addNote()`, Nomor Darurat (`emergencyContacts` / `setEmergencyContacts` / `syncEmergencyContactsBlocking`, penanda dirty berversi), `sourceLabel`, `ReportKind`, model `ReportRecord` / `ReportDetail`, `Iso` parser tanpa java.time. `SiagaSOS.create()` menyimpan riwayat & kontak per api key + `user.ref`.
- `SOSFloatingButton.install(application, sos, Options)`: tanpa AndroidX, lapisan per Activity (ActivityLifecycleCallbacks, dipasang saat resumed), geser + tempel tepi + posisi di SharedPreferences, menu EWS (tahan N dtk / 0 = ketuk) · Telepon 110/112 (default `ACTION_DIAL`) · Laporan → Pengaduan / Riwayat (+ detail, batal salah tekan) / Nomor darurat; lembar Rekam TKP (`MediaCapture` app host) + catatan; `SosSiren` → tombol "SENYAP"; palet gelap/terang.
- Modul `packages/sdk-android/sample` (bundle `id.demosiaga.kurir`, kunci dari `local.properties`: `siagasos.key`, `siagasos.url`), kamera palsu + sirene ToneGenerator.
- Teruji: **17/17 test JVM** (+8 `FeaturesTest`), AAR release ±216 KB (dulu ±73 KB, UI tombol melayang).
- **Belum diuji visual**: emulator `Pixel_7_API_35` gagal start ("No initial system image" untuk image ps16k). `adb install` tanpa `-s` masuk ke HP fisik yang tersambung USB (Redmi 24117RN76O) — app sample terpasang di sana; ke depan selalu pakai `adb -s <serial>`.

- Uji di HP (adb reverse): menu, keterangan status, titik SOS aktif tampil benar; SOS test dari HP masuk API (platform android, Android 15). Atas permintaan user, default `Options.holdSeconds = 0` (sekali ketuk seperti tata-warga). Flutter masih default ikut portal (3 dtk) kecuali diberi `holdSeconds: 0`.

### 2026-11-25 · Input Nomor: dropdown status + wilayah Bhabinkamtibmas (provinsi → desa, isi otomatis dari lokasi)
- Permintaan user (gambar Polmas Lingkungan/Kantor/UMKM/Sekolah/Komunitas): status kontak dipilih dari dropdown (RT, RW, Satpam, Bhabinkamtibmas, Polsek, Koordinator/Pimpinan, Owner, Guru, Orang Tua, Petugas Keamanan, Security, Keluarga, + Lainnya isian bebas). Bhabinkamtibmas wajib wilayah tugas provinsi → kab/kota → kecamatan → desa, terisi otomatis dari lokasi, tetap bisa dipilih ulang.
- **API**: migrasi `009_wilayah.sql` (tabel referensi `wilayah`, 91.599 baris dari seed tata-warga-be, tanpa RLS) + `010_contact_area.sql` (`emergency_contacts.area` jsonb). `GET /v1/sdk/regions[?parent=]`, `GET /v1/sdk/regions/reverse?lat&lng` (`src/lib/regions.ts`, `src/routes/regions.ts`; Nominatim, env `GEOCODER_URL` / `GEOCODER_USER_AGENT`, cache memori 24 jam). `PUT/GET /v1/sdk/contacts` menerima/mengembalikan `area`. Diuji live: Bandung/Coblong/Lebak Siliwangi, Jakarta Pusat/Gambir, Yogyakarta/Danurejan, Denpasar Barat, Bogor, Surabaya semua cocok sampai desa; Kab. Bandung (Pangauban ada 2) berhenti di kabupaten.
- Smoke: helper `call` menunggu jendela menit berikutnya bila kena limit umum `rate_limited` ≤ 60 dtk (smoke kini > 60 panggilan SDK/menit dari satu IP). **114 cek lolos** (+7 wilayah), `pnpm -r typecheck` lolos.
- **Flutter SDK**: `Region`, `RegionArea`, `EmergencyContact.area`, `defaultEmergencyContactRoles`, `defaultAreaContactRoles`; `SiagaSOS.regions()` (cache) + `regionFromLocation()` (pakai `locationProvider`). `SOSFloatingButton(contactRoles:, areaContactRoles:)`. Lembar Input Nomor: dropdown Status (wajib; `DropdownButton` dalam `InputDecorator` agar jalan di Flutter 3.32 app host), bagian "Wilayah tugas" + tombol **Lokasi saya**, pemilih wilayah inline dengan pencarian; ganti level atas mengosongkan level bawah.
- Perbaikan: Navigator lokal lembar dibungkus `HeroControllerScope.none` (assert "HeroController can not be shared by multiple Navigators" yang membuat 2 tes lama gagal).
- Tes Flutter **20 lolos / 1 gagal**: yang gagal tes pengaduan lama (`occurred_at` kini selalu dikirim sejak 05cc770, ekspektasi tes belum diperbarui), bukan dari fitur ini.
- ⬜ Android native (`SOSFloatingButton.kt`) belum punya dropdown status & wilayah. ⬜ Deploy migrasi 009 + 010 ke `sos.tip2.co`.

### 2026-11-25 · Polmas Keamanan: app penerima Nomor Darurat (Flutter + API `/v1/pk`)
- Permintaan user: app Flutter baru dari PRD "Polmas Keamanan" (@Ruki), DB sama dengan siagasos. **Konsep ditegaskan user**: app ini untuk pemilik nomor di menu Nomor Darurat SDK (commerceOS: pemilik toko, satpam; tata-warga: RT/RW, satpam, Bhabinkamtibmas). Nomor itu login → melihat & menanggapi SOS kios/warga yang mencantumkan nomornya. Dicatat di [docs/POLMAS_KEAMANAN.md](docs/POLMAS_KEAMANAN.md) + memori.
- API: migrasi `011_polmas_keamanan.sql` (`apps.polmas_source`, kolom wilayah & `verified_at` di `reports`, `pk_users`, `pk_user_roles`, `pk_sessions`, `pk_responses` RLS tenant, `pk_call_dismissals`, `pk_news`, `pk_audit`, fungsi `pk_norm_phone`) dan `012_polmas_penerima.sql` (peran `penerima`, `from_contact`, `created_via`). `src/lib/polmas.ts`, `src/routes/polmas.ts` (dipasang sebelum `/v1`), worker kecamatan (Nominatim, 5 dtk). Skrip `pnpm seed:pk` (5 app sumber demo, Nomor Darurat demo, ±150 laporan 35 hari di Bogor Tengah, video/foto ffmpeg ke MinIO, berita) dan `pnpm pk:user`.
- Bug ditemukan smoke: daftar `scope=me` mengirim parameter `$3` yang tidak dirujuk → Postgres menolak. Diperbaiki.
- Flutter `apps/polmas-keamanan` (`id.polmas.polmas_keamanan`): design token PRD, animasi §7.4 (hormati kurangi gerakan), mode gelap, a11y label Indonesia. Palet grafik divalidasi skrip dataviz (navy gagal lightness band sebagai seri → seri Laporan biru slot-1). `google_fonts` dipatok 8.x (9.x tidak cocok `TextTheme` Flutter 3.47).
- Teruji: `pnpm smoke` **134 cek** (+20 PK), `pnpm -r typecheck`, `flutter analyze` bersih, `flutter test` 6/6, `flutter build apk --debug` ✅.
- **Belum**: `pnpm seed:pk` belum dijalankan di DB dev (izin eksekusi ditolak otomatis; jalankan manual), uji di HP, push FCM, offline. Jebakan: heredoc berisi teks SQL `DELETE`/`DROP` di Bash ditolak pemeriksa keamanan; tulis file lewat Write/Edit.

- UI disamakan dengan mockup user (2 gambar): logo perisai sirene+pin, splash bendera + kota, login header gelombang merah + ilustrasi rumah/bendera + toast "Berhasil keluar", Profil (avatar inisial, toggle Notifikasi/Mode gelap/Kurangi gerakan, Bantuan, Tentang, dialog Keluar), Beranda (sapaan, kartu berwarna, tab merah, kartu foto+jarak), Konfirmasi Wilayah, Detail (langkah Status Penanganan, 3 tombol aksi), Riwayat (segmen + filter), Analisa (persen vs periode lalu, grafik merah), SOS Masuk. API: `thumb_url` di daftar, `previous_totals` di analisa, `PATCH /v1/pk/me {name}`. Akun uji `pnpm pk:user` 0812-3456-7890 Rina Nuraini (warga, demo1234). `flutter analyze` bersih, test 6/6. Belum dicek di HP (build+install ±5 mnt dihentikan user).

### 2026-11-25 · PRD Polmas Keamanan v2 + eksekusi (5 pilar, FCM menggantikan WA & sirene)
- PRD disimpan di [docs/POLMAS_KEAMANAN.md](docs/POLMAS_KEAMANAN.md) (+ memori). Keputusan user: WA & sirene lokal dihapus; Tindak Lanjut = kolom otomatis + penerima isi Status & catatan; jabatan Nomor Darurat per pilar; Firebase project baru `siagasos-a61e9`; pilar dipilih di portal saat buat app; wilayah hanya untuk Bhabinkamtibmas (diisi di SDK), app tidak membaca wilayah.
- Portal/API: dropdown "Aplikasi ini untuk apa?" (5 pilar) di App baru & Pengaturan app → `apps.polmas_source`; `@siagasos/shared` `PILLARS`, `PILLAR_LABELS`, `PILLAR_CONTACT_ROLES`; `/v1/sdk/config` + `pillar`, `pillar_label`, `contact_roles`.
- API: WA SOS dimatikan (`SOS_WHATSAPP=true` untuk rollback); FCM dua project (`FCM_SERVICE_ACCOUNT` POS, `PK_FCM_SERVICE_ACCOUNT` Polmas Keamanan); migrasi `013_polmas_devices.sql` (`pk_devices`, `pk_push_log`); `dispatchPkPush` (kontak darurat langsung, Bhabinkamtibmas setelah worker mengisi kecamatan); `POST /v1/pk/me/device`, `/me/device/remove`. Kredensial `siagasos-a61e9` dicek ke FCM: auth OK (token palsu → 400 INVALID_ARGUMENT). File service account di-`.gitignore`.
- SDK: Flutter `siren` deprecated & tidak dibunyikan, jabatan dari `contact_roles`; Android `Options.siren` deprecated & tidak dibunyikan (belum dikompilasi ulang). Tes EWS disesuaikan; tes pengaduan lama masih gagal (sudah sebelumnya).
- App: login langsung ke Beranda (tanpa konfirmasi wilayah; polling SOS dulu dilewati selama `needsArea` → diperbaiki), header & app bar navy seragam, baris peran dari Nomor Darurat, tab Kecamatan hanya untuk yang punya wilayah, kolom Tindak Lanjut (kartu/tabel) + Foto/Video, label pilar, luapan teks diperbaiki (test huruf 130%), FCM (`firebase_messaging`, kanal `polmas_sos` + `res/raw/siren`, `getToken` sengaja dipakai).
- Teruji: `pnpm smoke` 136 cek (sebelum restart API dengan kredensial asli), `pnpm -r typecheck`, `flutter analyze` bersih, test app 9/9.
- Perlu: restart API (memuat `PK_FCM_SERVICE_ACCOUNT`), uji ujung-ke-ujung di HP, `GoogleService-Info.plist` untuk iOS.

### 2026-11-25 · Mockup HTML Polmas Digital (3 opsi desain)
- [docs/mockups/polmas-digital.html](docs/mockups/polmas-digital.html): 3 opsi gaya (A Bhayangkara navy-emas, B Komando Malam gelap/peta, C Patroli Terang livery biru-kuning), masing-masing Splash, Login (nomor → kata sandi, sesuai PRD), Beranda, Analitik, ukuran HP 360×760. Lambang perisai-bintang generik, bukan logo resmi Polri.
- User memilih **Opsi A**; versi 2: tombol SOS dihapus dari navigasi (petugas penerima), kartu/tabel memuat semua kolom Tindak Lanjut, layar Detail + Tindak Lanjut, Analitik 4 tab (Ringkasan, Ekosistem, Waktu & Wilayah, Kinerja), layar Profil. Opsi B/C dibuang dari file.
- Belum diterapkan ke `apps/polmas-keamanan`.
- **Keputusan user:** app Polmas Keamanan dibuat sama persis dengan mockup Opsi A v2, termasuk datanya. Daftar selisih UI + API ada di bagian "Polmas Digital: samakan dengan mockup".

### 2026-11-25 · App Polmas Keamanan disamakan dengan mockup Opsi A (+ data API)
- API: migrasi `014_polmas_device_name.sql`; `/analytics/summary` + `source`, `median_response_s`, `by_ecosystem`, `matrix`, `by_kelurahan.prev_n`, `funnel`, `officers`, `weekly.median_response_s`, `patrol_hint`, `sla_min`; `/analytics/evaluation` + `source` + median; `/me/stats`, `/me/devices`, `/me/devices/:id/remove`, `/me/password`; `/me.ecosystems`; laporan + `code`, `video_s`, `audio_s`, `thumb_urls`; `/reports.counts`; `/inbox.open_reports`. Smoke 145/145, `pnpm -r typecheck` ✅. README & STATUS (keputusan 23) diperbarui.
- App: tulis ulang splash, login, shell 4 tab, beranda, laporan (kartu/tabel), detail, analitik 4 tab, profil di atas `lib/widgets/ui.dart`; token warna disamakan mockup; ikon/nama aplikasi baru. `flutter analyze` bersih, test 10/10 (termasuk kartu & tabel tanpa luapan pada huruf 130%).
- Mockup ikut disamakan dengan yang bisa disajikan data asli (Selesai 7 hari, 7 hari terakhir, target 15 menit, alur dari "Masuk", tanpa notifikasi pengaduan, pensil ubah nama). Tautan artifact mockup lama sudah tidak aktif; file lokal tetap acuan.
- Sirene SOS diganti dengan sirene commerceOS (`sos_siren.mp3`, 20 dtk) untuk layar panggilan (`assets/sounds/`) dan push (`res/raw/`). Kanal Android baru `polmas_sos_v2` (suara kanal tidak bisa diubah; `polmas_sos` lama dihapus app), server `PK_FCM` ikut ke `polmas_sos_v2`/`sos_siren`.
- FCM diuji ke HP asli (Xiaomi 24117RN76O, akun 0800 111 0001): server → FCM `sent`, notifikasi tampil di kanal `polmas_sos_v2` dan sistem memutar `raw/sos_siren`. Catatan: setelah `adb install` ulang, app harus dibuka sekali (status "stopped" menahan push); di Xiaomi aktifkan Autostart agar push tetap masuk saat app ditutup.
- **Uji ujung-ke-ujung lokal tata-warga → Polmas (2026-11-25):** SDK tata-warga (bundle `com.tip.rtku`, app lokal "Polmas Warga (Demo)" + kunci live uji) mengisi Nomor Darurat Ajie (Satpam, 0896 9893 0980) → SOS + foto TKP → push FCM sampai di HP Xiaomi (notifikasi "SOS dari Sri Wahyuni", kanal `polmas_sos_v2`, sirene commerceOS) → login Polmas pertama (buat kata sandi) → terima/verifikasi/tangani/selesai → tata-warga melihat `resolved` "Laporan selesai ditangani Ajie." 24/24 cek.
- Bug ditemukan & diperbaiki: label ekosistem `null` untuk app tanpa pilar (API + tab Ekosistem crash), label kartu angka terpotong di tengah kata, kelurahan dobel di kartu, garis langkah status miring, awalan 0 di kolom nomor login. Smoke 146/146.
- Catatan: push SOS yang datang saat app terbuka di depan diserahkan ke app (polling → layar panggilan), bukan ke baki notifikasi; bila app terbuka tapi belum login, tidak ada yang berbunyi. Produksi (`sos.tip2.co`, tempat tata-warga asli) belum memakai API baru: nomor 0896 9893 0980 di sana terdaftar Satpam · Polmas Lingkungan, belum punya kata sandi.
- **Rilis tersambung produksi (2026-11-26):** Polmas: build rilis default `https://sos.tip2.co` (`kReleaseMode`), `usesCleartextTraffic` hanya debug, signing dari `android/key.properties` (belum ada → debug, tidak bisa ke Play Store), versi 2.0.0+2, skrip `scripts/build_release.sh`. API: `GET /v1/pk/status` publik. tata-warga: skrip `scripts/build_release_siagasos.sh` (belum di-commit di repo itu). APK rilis dicek: tanpa `localhost:4000`, cleartext false. Smoke 148/148.
- ⬜ Produksi: deploy commit terbaru (`/v1/pk/status`, `server_push`) + isi `PK_FCM_SERVICE_ACCOUNT` + restart → jalankan ulang uji push dengan app Polmas tertutup.
- ⬜ Kunci unggah Play Store Polmas (`android/key.properties` + keystore) — keputusan pemilik akun Play Console.
- **#7 penanggung jawab & #8 alur Terima (2026-11-26):** migrasi `015_polmas_handler.sql` (aksi `ambil_alih`), `handler` di setiap laporan, aksi dibatasi untuk non-penanggung jawab (409 `handled_by_other`), app: spanduk "Anda menangani / Ditangani oleh X" + Ambil alih di Detail, baris penanggung jawab di kartu, layar panggilan berubah "Sudah diterima oleh X" bila penerima lain lebih dulu. #8: layar panggilan menutup dirinya sendiri lalu membuka Detail; polling mulai dari HomeShell; panggilan berikutnya langsung tampil. Diuji di HP (lokal): Terima → Detail ✅, penerima lain menerima saat berdering → layar berubah ✅ (luapan teks & nama panjang diperbaiki). Smoke 154/154, test app 11/11.
- **Tanpa tulisan demo & nama app mentah (2026-11-26):** label DEMO, "Akun demo", "(demo)" dihapus dari app; laporan dari app tanpa pilar Polmas (mis. POSTIP Kasir) tidak menampilkan chip ekosistem, analitik mengelompokkannya "Lainnya"; akhiran "(Demo)/(Android)/(iOS)" dibuang dari nama app. Smoke 154/154, test 11/11.
- Git: repo GitHub `AjieDarmawan/sos_siaga` **publik**; commit GitLab `ca2e26b` berisi kunci privat Firebase sehingga riwayat GitLab tidak boleh digabung ke GitHub. GitLab `dev` mendapat commit yang sama + penghapusan file kunci; GitHub `dev` tetap tanpa commit kunci. Kunci `siagasos-a61e9` tetap perlu dirotasi.
- **Nama & pilar app (2026-11-26):** seed demo memakai nama sesuai label pilar (Polmas Lingkungan/Perkantoran/UMKM/Pendidikan/Komunitas (Demo)), dicari lewat bundle supaya tidak ganda. Lokal: POSTIP Kasir (`com.tip.kasir`) diberi pilar UMKM. **Produksi:** `commerceos-pos-mobile/env/siagasos.prod.json` menunjuk `https://api.siagasos.id` (NXDOMAIN) dengan kunci lokal (ditolak `sos.tip2.co`) → build produksi POS tidak bisa mengirim SOS. Perlu: daftarkan app POSTIP Kasir (bundle `com.tip.kasir`, pilar UMKM) di portal `sos.tip2.co`, isi kunci `pk_live_` + base URL `https://sos.tip2.co` di file itu.

### 2026-11-26 — Fix: push SOS Polmas tanpa sirene di build rilis
- Penyebab: resource shrinker rilis (default Flutter) membuang `res/raw/sos_siren` karena hanya dirujuk lewat URI string di `MainActivity` → kanal `polmas_sos_v2` tanpa suara. Debug tidak kena (shrinker mati).
- Fix: `apps/polmas-keamanan/android/app/src/main/res/raw/keep.xml` (`tools:keep="@raw/sos_siren"`), plus cek di `scripts/build_release.sh` bahwa paket memuat `res/raw/sos_siren`.
- Terverifikasi `aapt2 dump resources`: tanpa keep.xml `raw/sos_siren` hilang; dengan keep.xml ada.
- Jebakan: HP yang terlanjur memasang APK rusak mungkin perlu uninstall → install ulang bila sirene belum bunyi (kanal menyimpan pengaturan suaranya).

### 2026-11-26 — Polmas Digital disamakan lagi dengan mockup Opsi A v2
- Tab & judul layar ke-3 kembali **Analitik** (sempat tertulis "Dashboard"), judul kolom tabel Tindak Lanjut "Location" → **Lokasi**.
- Cari laporan: placeholder "Cari berita, nama, nomor HP…". API `GET /v1/pk/reports?q=` kini juga mencocokkan nomor HP pelapor (digit saja, `0…` → `62…`, minimal 4 digit) **khusus Bhabinkamtibmas**; penerima lain tidak, karena bagi mereka nomor disamarkan.
- `pnpm smoke` 157 cek lolos (+1: penerima tidak bisa mencari lewat nomor), `pnpm -r typecheck` dan `flutter analyze` bersih. Belum ada cek smoke jalur positif (smoke belum punya akun Bhabinkamtibmas).

### 2026-11-26 — API mitra `/partner/v1`: SOS + lampiran tampil di dashboard Polmas Digital (:5177 `#/sos`)
- Masalah: konsol SOS Polmas hanya membaca app yang kunci `sk_live`-nya ditulis manual di `polmas/.env.local` (3 app); laporan app pilar Polmas (UMKM, Lingkungan, dst.) tidak muncul.
- **API**: migrasi `016_partners.sql` (`partners`, `partner_keys`, policy `partner_read`, actor_kind `partner` di `report_events` & `audit_logs`), `withPartner()` di `src/db.ts`, `src/routes/partner.ts` (list, detail + media/timeline/track, actions), skrip `pnpm partner:create`. Smoke **170 cek lolos** (+13 cek mitra: tanpa pilar tidak dibagikan, test tidak dibagikan, cakupan wilayah, 403 di luar izin, tindakan ke timeline + status SDK).
- **Polmas** (`../polmas`): `server/sos.ts` memakai `SIAGASOS_PARTNER_KEY` (kunci "Polmas Digital", cakupan nasional, sudah diisi di `.env.local`), tetap menggabungkan `SIAGASOS_SECRET_KEYS` untuk app tanpa pilar (dedupe per id); tombol status dikirim sebagai `aksi` mitra; nama app tanpa akhiran (Demo)/(Android). Terverifikasi login `kapolres.bogor-kota`: 227 laporan dari 8 app, detail membawa URL media yang bisa dibuka.
- Jebakan: smoke berulang cepat kena rate limit `pk-setup-ip` (10/jam per IP) → hapus `rl:pk-*-ip:::1:*` di Redis db 9 (dev saja). Smoke yang gagal di tengah bisa meninggalkan app smoke "Gedung Alfa Web" berpilar `umkm` (lalu tampil di Polmas).
- ⬜ `/partner/v1/stream` (SSE) dan `/stats`, `satuan.wilayah_kode` di Polmas → kirim `X-Partner-Scope` per satuan (cakupan sekarang masih dikunci di UI).
