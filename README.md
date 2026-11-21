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
| `apps/landing`, `apps/portal`, `apps/admin`, `apps/dashboard` | Frontend React | belum (M3) |
| `packages/sdk-android` | Kotlin, Maven Central | belum (M4) |

Pemetaan F-ID ke kode, dan apa yang belum dikerjakan, ada di [`docs/STATUS.md`](docs/STATUS.md).

## Menjalankan lokal

```bash
docker compose up -d                       # postgres :5455 (role siagasos_app non-superuser), redis :6380
cp apps/api/.env.example apps/api/.env      # isi secret; lihat komentar di file
pnpm install
pnpm migrate
pnpm dev:api                                # http://localhost:4000
pnpm smoke                                  # 59 cek end-to-end (API harus sedang jalan)
pnpm --filter @siagasos/api create-admin reviewer@siagasos.id 'password-min-12' superadmin
```

> API **wajib** konek sebagai role non-superuser tanpa `BYPASSRLS`. Superuser Postgres selalu melewati Row Level Security, sehingga isolasi tenant tidak berlaku.

Di mode non-production, `register` dan undangan mengembalikan `dev_verification_token` / `dev_invite_token`, dan email ditulis ke log (bukan dikirim) bila `SMTP_URL` kosong.

### Portal & dashboard (`apps/portal`)

```bash
pnpm dev:api                 # :4000
pnpm dev:portal              # :5174 (Vite), VITE_API_URL default http://localhost:4000
pnpm seed:demo               # data demo: akun approved, 2 app, responder, 16 laporan
```

Login demo: `demo@siagasos.test` / `demo12345` (owner), `satpam@siagasos.test` / `demo12345` (responder).
Halaman: registrasi 3 langkah, verifikasi email, status verifikasi + unggah dokumen, App & kunci API (rotasi/cabut, origin, webhook, tampilan tombol, source, log webhook), Tim, dan Dashboard laporan (daftar + peta realtime + bunyi alert + timeline).

## Tiga kelompok API

| Prefix | Auth | Dipanggil oleh |
|---|---|---|
| `/v1/sdk` | `X-SOS-Key: pk_...` + cek `Origin` / `X-SOS-Bundle` | SDK web & mobile |
| `/v1` | `Authorization: Bearer sk_...` | Backend klien |
| `/portal`, `/admin` | JWT login (admin: password + TOTP) | Portal, dashboard, panel admin |

### SDK
| Method | Path | |
|---|---|---|
| GET | `/v1/sdk/config` | kategori, teks tombol, durasi tahan, teks penerima |
| POST | `/v1/sdk/reports` | buat laporan (wajib `Idempotency-Key`) |
| GET | `/v1/sdk/reports/:id` | status untuk pengguna |
| POST | `/v1/sdk/reports/:id/locations` | live location; balasan `accepted:false` = berhenti |
| POST | `/v1/sdk/reports/:id/cancel` | batal, hanya selama `open` |

### Server klien
`GET /v1/reports`, `GET|PATCH /v1/reports/:id`, `POST /v1/webhooks/test`. Kunci test hanya melihat data test.

### Portal
- Auth: `POST /portal/auth/{register,verify-email,resend-verification,login,accept-invite}`, `GET /portal/me`
- Onboarding: `GET /portal/onboarding/status`, `POST /portal/onboarding/documents` (multipart `doc_type` + `file`), `POST /portal/onboarding/submit`
- App & kunci: `/portal/apps` (CRUD), `/portal/apps/:id/keys` (buat, `/:keyId/rotate`, `/:keyId/revoke`), `/portal/apps/:id/sources`, `/portal/apps/:id/webhooks`
- Laporan: `GET /portal/reports`, `GET|PATCH /portal/reports/:id`, `GET /portal/reports/export.csv`, `GET /portal/reports/stream` (SSE, `?access_token=`)
- Tim: `GET /portal/team`, `POST /portal/team/invites`, `PATCH /portal/team/:userId`

### Admin
`POST /admin/auth/login`, `GET /admin/accounts?status=pending_review`, `GET /admin/accounts/:id`, `GET /admin/documents/:id/url` (signed URL 5 menit), `PATCH /admin/documents/:id`, `POST /admin/accounts/:id/decision`, `POST /admin/apps/:id/{disable,enable}`, `GET /admin/stats`.

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
