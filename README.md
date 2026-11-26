# SiagaSOS

Platform tombol darurat siap pasang. Perusahaan mendaftar, diverifikasi admin (1–2 hari kerja), mengambil API key, lalu memasang SDK. Laporan SOS masuk ke dashboard responder secara realtime, lengkap dengan lokasi.

> Layanan ini **tidak** tersambung ke 110/112. Responder adalah tim keamanan milik klien.

## Isi monorepo

| Path | Isi | Status |
|---|---|---|
| `apps/api` | Express 5 + TypeScript + PostgreSQL (RLS) + Redis | M1 selesai |
| `packages/shared` | Tipe & skema zod bersama API dan SDK | ✔ |
| `packages/sdk-js` | `@siagasos/js`: core tanpa framework, 3,2 KB gzip | M2 0.1.0 |
| `packages/sdk-react` | `@siagasos/react`: `<SOSProvider>`, `<SOSButton>`, `useSOS()` | M2 0.1.0 |
| `examples/vanilla-demo` | Demo HTML tanpa bundler | ✔ |
| `apps/portal` | Landing page (`/`), dokumentasi (`/docs`), portal klien, dashboard responder (Vite + React) | ✅ |
| `apps/admin` | Panel admin platform: review pendaftaran, keputusan, app (Vite + React, :5175) | ✅ |
| `packages/sdk-android` | Kotlin, Maven Central | belum (M4) |
| `apps/polmas-keamanan` | **Polmas Keamanan** (Flutter): app penerima untuk pemilik Nomor Darurat (pemilik toko, satpam, RT/RW, Bhabinkamtibmas). Konsep: [`docs/POLMAS_KEAMANAN.md`](docs/POLMAS_KEAMANAN.md) | 🟡 fase 1 |

Pemetaan F-ID ke kode, dan apa yang belum dikerjakan, ada di [`docs/STATUS.md`](docs/STATUS.md).

## Menjalankan lokal

```bash
docker compose up -d                       # postgres :5455 (role siagasos_app non-superuser), redis :6380
cp apps/api/.env.example apps/api/.env      # isi secret; lihat komentar di file
pnpm install
pnpm migrate
pnpm dev:api                                # http://localhost:4000
pnpm smoke                                  # 102 cek end-to-end (API harus sedang jalan)
pnpm --filter @siagasos/api test            # unit test API (vitest, tanpa DB/Redis)
pnpm --filter @siagasos/api create-admin reviewer@siagasos.id 'password-min-12' superadmin
```

> API **wajib** konek sebagai role non-superuser tanpa `BYPASSRLS`. Superuser Postgres selalu melewati Row Level Security, sehingga isolasi tenant tidak berlaku.

API juga menjalankan job pembersihan tiap 10 menit (`MAINTENANCE_WORKER=true`, aman multi-instance): media `pending` yang tidak di-complete > 75 menit dihapus dari bucket & DB, laporan tertutup melewati retensi app dihapus, OTP responder kedaluwarsa dibuang.

Di mode non-production, `register` dan undangan mengembalikan `dev_verification_token` / `dev_invite_token`, dan email ditulis ke log (bukan dikirim) bila `SMTP_URL` kosong.

### Frontend

```bash
pnpm dev:api                 # :4000
pnpm dev:portal              # :5174  landing /, docs /docs, portal & dashboard
pnpm dev:admin               # :5175  panel admin
pnpm seed:demo               # data demo (idempoten): akun approved + 16 laporan, responder, 5 perusahaan di antrean, superadmin
pnpm admin:otp               # kode 2FA superadmin dev saat ini
pnpm --filter @siagasos/react-demo dev   # :5176 contoh aplikasi pelapor (SOS + foto/video/suara)
```

| Login demo | Email | Password |
|---|---|---|
| Owner (portal) | `demo@siagasos.test` | `demo12345` |
| Responder (portal) | `satpam@siagasos.test` | `demo12345` |
| Superadmin (admin, + kode `pnpm admin:otp`) | `admin@siagasos.test` | `admin-demo-12345` |
Tema: terang / gelap / ikut sistem + 5 warna aksen (menu "Tampilan" di semua aplikasi).
Media laporan disimpan di MinIO/S3 (`S3_*` di `apps/api/.env`, bucket privat `sos-siaga`).

Halaman: registrasi 3 langkah, verifikasi email, status verifikasi + unggah dokumen, App & kunci API (rotasi/cabut, origin, webhook, tampilan tombol, source, log webhook), Tim, dan Dashboard laporan (daftar + peta realtime + bunyi alert + timeline).

## Tiga kelompok API

| Prefix | Auth | Dipanggil oleh |
|---|---|---|
| `/v1/sdk` | `X-SOS-Key: pk_...` + cek `Origin` / `X-SOS-Bundle` | SDK web & mobile |
| `/v1` | `Authorization: Bearer sk_...` | Backend klien |
| `/portal`, `/admin` | JWT login (admin: password + TOTP) | Portal, dashboard, panel admin |
| `/v1/pk` | `Authorization: Bearer pks_...` (nomor HP + password, 12 jam) | App Polmas Keamanan |

### SDK
| Method | Path | |
|---|---|---|
| GET | `/v1/sdk/config` | kategori SOS & pengaduan (`complaint_categories`), teks tombol, durasi tahan, teks penerima |
| POST | `/v1/sdk/reports` | buat laporan (wajib `Idempotency-Key`); `kind: 'pengaduan'` = laporan non-darurat (uraian wajib, tanpa alarm & lokasi live); `emergency_contacts` (maks. 5 `{name, phone}`) = kontak darurat pribadi yang ikut dikabari WhatsApp saat SOS |
| GET | `/v1/sdk/reports/:id` | status untuk pengguna |
| POST | `/v1/sdk/reports/:id/locations` | live location; balasan `accepted:false` = berhenti |
| POST | `/v1/sdk/reports/:id/cancel` | batal, hanya selama `open` |
| GET | `/v1/sdk/reports/:id/detail` | detail untuk riwayat di perangkat: uraian, lokasi, timeline (catatan petugas, ringkasan WA), media + URL baca 15 menit; tanpa data pribadi pelapor / nomor penerima |
| POST | `/v1/sdk/reports/:id/notes` | catatan pelapor `{note}` (mis. keterangan rekaman TKP) → timeline `note`; 409 bila laporan sudah ditutup |
| GET/PUT | `/v1/sdk/contacts` | Nomor Darurat pelapor (`?reporter_ref=` / `{reporter, source_key?, contacts[]}`, tiap kontak boleh membawa `area` wilayah tugas `{province, regency, district, village}`, ganti total). Nomor di sini yang boleh login sebagai satpam |
| GET | `/v1/sdk/regions` | Wilayah Kemendagri: tanpa `parent` = provinsi; `?parent=32` → kab/kota, `32.73` → kecamatan, `32.73.02` → desa/kelurahan. `{parent, regions:[{code,name}]}` |
| GET | `/v1/sdk/regions/reverse` | `?lat&lng` → `{province, regency, district, village}` (level yang tak terbaca `null`) untuk isi otomatis. Geocoder Nominatim (`GEOCODER_URL`, kosong = nonaktif → 503 `geocoder_unavailable`), koordinat dibulatkan ±100 m, 20 req/10 mnt |
| POST | `/v1/sdk/responder/otp` | `{phone}` → OTP WhatsApp (template `METADEV_OTP_TEMPLATE_NAME`). 404 `responder_not_registered` bila nomor tidak ada di Nomor Darurat. Kunci test / server dev: `dev_code` |
| POST | `/v1/sdk/responder/verify` | `{phone, code, device:{platform, fcm_token}}` → `{token: rsp_..., responder}` |
| GET | `/v1/sdk/responder/me` · `/reports` · `/reports/:id` | header `X-SOS-Responder`. SOS 7 hari terakhir yang mencantumkan nomor satpam |
| POST | `/v1/sdk/responder/reports/:id/status` | `{status: acknowledged\|in_progress\|resolved\|false_alarm, note?}` → timeline actor `responder` |
| PUT/POST | `/v1/sdk/responder/device` · `/logout` | perbarui token FCM · akhiri sesi |
| POST | `/v1/sdk/reports/:id/media` | minta presigned PUT untuk foto/video/suara (`content_type`, `size_bytes`) |
| POST | `/v1/sdk/reports/:id/media/:mediaId/complete` | konfirmasi upload; server HEAD objek lalu tampil realtime |

### Server klien
`GET /v1/reports` (`?kind=sos|pengaduan`), `GET|PATCH /v1/reports/:id`, `POST /v1/webhooks/test`, `DELETE /v1/reporters/:ref` (hapus permanen semua laporan + Nomor Darurat satu pengguna akhir, UU PDP; → `{deleted:{reports,media,emergency_contacts}}`, 30/jam per app). Kunci test hanya melihat/menghapus data test.

Pilar app: `POST|PATCH /portal/apps {pillar: umkm|warga|kantor|sekolah|komunitas}` (dropdown "Aplikasi ini untuk apa?" di portal; UMKM, Lingkungan, Perkantoran, Pendidikan, Komunitas). `/v1/sdk/config` mengembalikan `pillar`, `pillar_label`, `contact_roles` (jabatan Nomor Darurat per pilar).

Emergency tidak lagi mengirim WhatsApp (set `SOS_WHATSAPP=true` hanya untuk rollback); penerima mendapat push FCM + sirene di app Polmas Keamanan.

Retensi: `PATCH /portal/apps/:id {retention_days: 30..3650 | null}`. Job pembersihan menghapus laporan live yang sudah ditutup lebih lama dari itu, dan laporan test 30 hari setelah ditutup.

### Portal
- Auth: `POST /portal/auth/{register,verify-email,resend-verification,login,accept-invite}`, `GET /portal/me`
- Onboarding: `GET /portal/onboarding/status`, `POST /portal/onboarding/documents` (multipart `doc_type` + `file`), `POST /portal/onboarding/submit`
- App & kunci: `/portal/apps` (CRUD), `/portal/apps/:id/keys` (buat, `/:keyId/rotate`, `/:keyId/revoke`), `/portal/apps/:id/sources`, `/portal/apps/:id/recipients` (Penerima SOS WhatsApp: GET/POST, `PATCH|DELETE /:recipientId`; `source_id` null = semua source), `/portal/apps/:id/webhooks`
- Laporan: `GET /portal/reports` (+ `media_count`), `GET|PATCH /portal/reports/:id` (+ `media[]` dengan URL baca 15 menit), `POST /portal/reports/:id/media` + `/:mediaId/complete` (lampiran petugas), `GET /portal/reports/export.csv`, `GET /portal/reports/stream` (SSE, `?access_token=`)
- Tim: `GET /portal/team`, `POST /portal/team/invites`, `PATCH /portal/team/:userId`

### Polmas Keamanan (`/v1/pk`)
Login dengan nomor yang ada di Nomor Darurat app sumber mana pun (atau akun `pnpm pk:user`). Data lintas tenant lewat `withPlatform()`, dibatasi ke: SOS/laporan yang memanggil nomor pengguna, laporan pengguna sendiri, yang pernah ditanggapinya, dan laporan di kecamatannya dari app bertanda `apps.polmas_source`.
- Status publik: `GET /status` → `{server_push, fcm_project, fcm_channel}` (tanpa login; dipakai skrip build rilis untuk memastikan push SOS aktif).
- Auth: `POST /auth/check {phone}` → `{has_password, name, contacts[]}` (404 `phone_not_registered`), `POST /auth/setup {phone,password≥8}` (login pertama dari Nomor Darurat, 409 bila sudah punya password), `POST /auth/login`, `POST /auth/logout`. Salah 5× → kunci 15 menit (423).
- Perangkat: `POST /me/device {fcm_token, platform, device_name?}` (push SOS via FCM project Polmas Keamanan, env `PK_FCM_SERVICE_ACCOUNT`), `POST /me/device/remove {fcm_token}` (logout), `GET /me/devices` (nama HP + `token_tail`, token tidak dikirim), `POST /me/devices/:id/remove`.
- Profil: `GET /me` (peran, wilayah, `ecosystems[]`, `can_respond`), `PATCH /me {name}`, `GET /me/stats?days=30` (ditangani, selesai, median respons saya), `POST /me/password {current_password, new_password≥8}` (sesi lain dicabut), `POST /me/role {role_id}`, `GET /me/area?lat&lng` (usulan wilayah dari GPS), `PUT /me/area`, `GET /regions?parent=`
- Data: `GET /dashboard`, `GET /reports` & `GET /history` (`scope=kecamatan|me`, `kind=sos|laporan`, `status=baru|diproses|…`, `kelurahan`, `q`, `from`, `to`, `before`, `limit`), `GET /reports/:id` (media URL 15 mnt, timeline, `actions`). Tiap laporan: `code` (tiket pendek, mis. `SOS-2511-3F9A`), `video_s`, `audio_s`; daftar juga `thumb_urls[]` (≤ 3 foto), dan `counts {semua, baru, diproses, selesai}` untuk chip status (halaman pertama), `GET /map?days&kind`, `GET /videos`, `GET /news`
- Tanggapan: `POST /reports/:id/responses {action: terima|hubungi|verifikasi|tangani|selesai|tidak_valid|catatan|ambil_alih, note}`. Satu laporan punya satu penanggung jawab (`handler {name, is_me, since}` = Terima/Ambil alih terakhir): penerima lain hanya `hubungi`, `catatan`, `ambil_alih` (aksi lain → 409 `handled_by_other` dengan nama penanggung jawab); Bhabinkamtibmas tetap penuh. Migrasi 015.: penerima untuk laporan yang memanggil nomornya, Bhabinkamtibmas untuk kecamatannya. Lewat `changeReport` → timeline, realtime, webhook, `status_message` di SDK pelapor.
- Panggilan: `GET /inbox` (SOS terbuka ≤ 30 mnt untuk saya + jumlah belum dibaca + `open_reports` untuk badge tab Laporan, dipolling app tiap 4 dtk), `POST /reports/:id/call {accepted|ignored}`, `GET /notifications`, `POST /notifications/read-all`
- Analisa: `GET /analytics/summary?period=7d|30d|90d|custom&from&to&source=umkm|warga|kantor|sekolah|komunitas` (total + `median_response_s`, tren, kategori, `by_ecosystem` (pilar + nama app, %, median respons, kategori teratas), `matrix` ekosistem × kategori, `by_kelurahan` + `prev_n`, `funnel`, `officers`, heatmap, `by_hour`, `weekly` + median, `patrol_hint`), `GET /analytics/evaluation?period=…&source=…` (waktu respons rata-rata & median, % selesai, tertunda, periode sebelumnya, daftar belum ditanggapi)
- Demo: `POST /demo/sos {source}` (akun `is_demo` saja). Data demo: `pnpm seed:pk`; akun manual: `PK_PASSWORD=… pnpm pk:user <nomor> "<nama>" <peran> [kecamatan] ["unit"]`.

### Admin
`POST /admin/auth/login`, `GET /admin/accounts?status=pending_review|all|…&search=` (+ `counts` per status, `drafting` = belum mengajukan), `GET /admin/accounts/:id`, `GET /admin/documents/:id/url` (signed URL 5 menit), `PATCH /admin/documents/:id`, `POST /admin/accounts/:id/decision`, `POST /admin/apps/:id/{disable,enable}`, `GET /admin/stats`.

## Pemakaian SDK

```ts
import { SiagaSOS } from '@siagasos/js';

const sos = SiagaSOS.init({ apiKey: 'pk_test_...', sourceKey: 'kantor-jakarta-web' });
const report = await sos.trigger({ category: 'kriminal', message: 'Ada orang mencurigakan' });
sos.on('status', (r) => console.log(r.status, r.statusMessage));
```

```tsx
import { SOSProvider, SOSButton } from '@siagasos/react';

<SOSProvider apiKey="pk_test_..." sourceKey="kantor-jakarta-web">
  <SOSButton category="kriminal" holdToConfirm={3} onSent={() => toast('Laporan terkirim')} />
</SOSProvider>
```

Ganti `pk_test_` ke `pk_live_` setelah perusahaan disetujui. Kode lain tidak perlu diubah.

## Webhook

Event: `report.created`, `report.status_changed`, `report.cancelled`. Header `X-SOS-Signature: t=<unix>,v1=<hex>`, dengan `v1 = HMAC_SHA256(webhook_secret, "<t>.<raw body>")`. Retry eksponensial (30 dtk → maks 6 jam per jeda) hingga 24 jam.

## Kunci Firebase & dua remote

GitLab (`origin`, privat) boleh menyimpan kunci FCM Polmas `apps/api/siagasos-a61e9-*.json` sementara agar deploy produksi bisa mengirim push SOS. GitHub (`github`) **publik**: pasang pengaman sekali per laptop, `git config core.hooksPath scripts/git-hooks`. Hook `pre-push` menolak push ke GitHub bila ada commit yang memuat file kunci. Solusi permanen: jadikan repo GitHub privat, atau isi `PK_FCM_SERVICE_ACCOUNT=base64:<JSON>` di env server lalu keluarkan file kunci dari repo.

## Build rilis app mobile (pasti tersambung ke produksi)

- **Polmas Digital** (penerima SOS): `apps/polmas-keamanan/scripts/build_release.sh aab|apk`. Build rilis selalu ke `https://sos.tip2.co`, HTTP biasa dimatikan, tanda tangan dari `android/key.properties`. Skrip menolak build bila server produksi belum bisa mengirim push (`/v1/pk/status`), project Firebase server ≠ `google-services.json`, atau (untuk `aab`) kunci unggah belum ada.
- **tata-warga** (pelapor SOS, repo `polmas-tatawarga-mobile`): `scripts/build_release_siagasos.sh aab|apk`. Memakai `env/siagasos.prod.json` (tidak ikut git) dan mengecek kunci `pk_live_` diterima produksi untuk bundle `com.tip.rtku`, pilar Polmas terisi, dan push ke Polmas Digital aktif.
- Server produksi wajib punya `PK_FCM_SERVICE_ACCOUNT` (isi JSON, `base64:<JSON>` satu baris, atau path file di luar repo) untuk service account Firebase `siagasos-a61e9`, lalu restart API. Cek: `GET /v1/pk/status` → `server_push: true`.
