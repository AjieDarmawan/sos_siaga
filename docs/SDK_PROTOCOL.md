# Kontrak SDK SiagaSOS (semua platform)

Setiap SDK (web, React, React Native, Flutter, Android, iOS) wajib mengikuti kontrak ini supaya perilakunya sama.
Referensi implementasi: [`packages/sdk-js/src/index.ts`](../packages/sdk-js/src/index.ts).

## Identitas & header

| Header | Nilai | Keterangan |
|---|---|---|
| `X-SOS-Key` | `pk_live_…` / `pk_test_…` | Wajib. Mode dibaca dari prefix. Tolak `sk_` di sisi SDK. |
| `X-SOS-Bundle` | `com.klien.app` | **Wajib untuk mobile** (tidak ada `Origin`). Dicek terhadap `allowed_bundle_ids`. Kunci live tanpa Origin/Bundle → 403 `origin_required`. |
| `Idempotency-Key` | UUID v4 | Wajib di `POST /v1/sdk/reports`. Dibuat **sekali per laporan** dan dipakai ulang di setiap retry. |
| `Content-Type` | `application/json` | Untuk body JSON. |

Base URL default: `https://api.siagasos.id` (bisa dioverride untuk staging / lokal).

## Alur

1. `GET /v1/sdk/config` → `{ app_name, mode, categories[], complaint_categories[], button_text, hold_seconds, recipient_text, fallback_phone, live_location_interval_s }`. Cache di memori.
2. **Trigger**: ambil lokasi (timeout default 8 dtk, boleh gagal), lalu `POST /v1/sdk/reports`
   `{ kind?, category, message?, source_key?, location?{lat,lng,accuracy_m}, reporter?{ref,name,phone}, device?{platform,sdk_version,os}, metadata?, client_created_at, emergency_contacts?[{name,phone}] }`
   `emergency_contacts` (hanya SOS, maks. 3, nomor dinormalisasi ke `62xx`, tidak valid → 422): kontak darurat pribadi yang disimpan SDK di perangkat per pengguna. Server mengabari mereka + Penerima SOS app lewat WhatsApp setelah laporan tersimpan (async, tidak menunda respons; hasil per nomor di timeline `whatsapp`).
   → 201 (baru) / 200 + `Idempotent-Replayed: true` (ulangan) → `ReportPublic { id, kind, status, mode, category, created_at, acknowledged_at, resolved_at, status_message }`.
3. **Offline**: bila gagal jaringan atau 5xx/429, simpan item ke antrian **persisten** (`localId`, `idempotencyKey`, body) dan emit `queued`. Kirim ulang dengan backoff eksponensial (2 dtk → maks 60 dtk) dan saat koneksi kembali. Error 4xx lain (kunci salah, origin) = permanen: emit `error`, buang dari antrian.
4. **Status**: polling `GET /v1/sdk/reports/:id` tiap 4 dtk sampai status akhir (`resolved`, `cancelled`, `false_alarm`). Emit `status` hanya bila berubah.
5. **Lokasi live** (default aktif): `POST /v1/sdk/reports/:id/locations` `{lat,lng,accuracy_m,recorded_at}` tiap `live_location_interval_s`. Berhenti bila balasan `accepted:false` atau status akhir.
6. **Batal**: `POST /v1/sdk/reports/:id/cancel` `{reason}`. Bila laporan masih di antrian, cukup hapus dari antrian. 409 `cannot_cancel` bila sudah diterima petugas.
7. **Lampiran** (foto/video/suara):
   1. `POST /v1/sdk/reports/:id/media` `{content_type, size_bytes, duration_s?}` → `{ media{id,…}, upload{ method:'PUT', url, headers, expires_in } }`
   2. `PUT upload.url` dengan **persis** `upload.headers` dan body file (ukuran harus sama dengan `size_bytes`). Ini langsung ke object storage, bukan ke API; jangan kirim `X-SOS-Key`.
   3. `POST /v1/sdk/reports/:id/media/:mediaId/complete` → `MediaPublic { id, kind, content_type, size_bytes, status:'ready' }`.
   Bila laporan masih di antrian, tunggu sampai terkirim (event `sent`) dulu.
   Batas: foto 10 MB, video 60 MB, suara 15 MB, 10 lampiran per laporan. MIME: lihat `apps/api/src/lib/media.ts`.
8. **Catatan pelapor**: `POST /v1/sdk/reports/:id/notes` `{note}` (1–1000 karakter) → `201` + status publik. Dipakai setelah rekam TKP; tampil di timeline dashboard. 409 `report_closed` bila status sudah akhir, 422 `invalid_note`.
9. **Pengaduan** (non-darurat, menu "Laporan pengaduan" di tombol melayang): sama dengan trigger, body `kind: 'pengaduan'`,
   `category` dari `complaint_categories`, `message` **wajib** (≥ 5 karakter, 422 bila kurang). Server tidak mengirim email darurat
   ke responder, kuota per pengguna terpisah dari SOS (5/jam), dan `/locations` selalu `accepted:false` (jangan kirim lokasi live).
   SDK boleh polling lebih jarang (Flutter: 8× `pollInterval`). Dashboard tenant & Polmas menampilkannya sebagai pengaduan tanpa alarm.

## Error

Body selalu `{ "error": { "code", "message", "details"? } }`. SDK membungkusnya menjadi `SiagaSOSError(status, code, message)`.
Kode penting: `invalid_api_key`, `wrong_key_type`, `origin_not_allowed`, `bundle_not_allowed`, `origin_required`, `account_not_approved`, `rate_limited`, `reporter_rate_limited`, `test_quota_exceeded`, `cannot_cancel`, `unknown_source`, `media_too_large`, `unsupported_media_type`, `upload_missing`, `report_closed`, `invalid_note`.

## API publik minimal per SDK

| Kemampuan | JS | Flutter | Android | iOS | React Native |
|---|---|---|---|---|---|
| init(apiKey, bundleId/origin, sourceKey, user, baseUrl) | `SiagaSOS.init` | `SiagaSOS(...)` | `SiagaSOS.init` | `SiagaSOS(config:)` | `@siagasos/js` + `bundleId` |
| getConfig / trigger / cancel / getReport / attach / flush / dispose | ✔ | ✔ | ✔ | ✔ | ✔ |
| Event `queued`, `sent`, `status`, `error` | `on()` | `Stream` | listener | delegate/closure | `on()` |
| Antrian offline persisten | IndexedDB/localStorage | SharedPreferences | SharedPreferences | UserDefaults | AsyncStorage (opsional) |
| Pengaduan `complain()` / `kind:'pengaduan'` | ⬜ | ✔ | ⬜ | ⬜ | ⬜ |
| Komponen tombol tahan N detik | `SOSButton` (React) | `SOSButton` widget | `SOSButtonView` | SwiftUI `SOSButton` | `SOSButton` |
