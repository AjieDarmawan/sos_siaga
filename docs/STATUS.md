# Status implementasi vs PRD

Terakhir diperbarui: 2026-11-21. Cakupan sesi pertama: **M1 (backend inti) + SDK web (`@siagasos/js`, `@siagasos/react`)**.
Verifikasi: `pnpm smoke` (59 cek end-to-end terhadap API sungguhan + Postgres + Redis) dan `pnpm --filter @siagasos/js test` (5 unit test).

## Kebutuhan fungsional

| ID | Ringkas | Status | Di mana |
|---|---|---|---|
| F-01 | Registrasi perusahaan + dokumen, bcrypt, belum login sampai verifikasi | ✔ API | `routes/portal/auth.ts`, `onboarding.ts` |
| F-02 | Undang responder (admin/responder), bisa dicabut | ✔ API | `routes/portal/team.ts` |
| F-03 | Buat app → kunci test (+ live bila approved); secret tampil sekali | ✔ | `routes/portal/apps.ts` |
| F-04 | Batasi ke origin / bundle id → 403 | ✔ | `middleware/keyAuth.ts` |
| F-05 | Rotate (dengan masa tenggang opsional) & revoke ≤ 60 dtk | ✔ cache 30 dtk | `apps.ts`, `keyAuth.ts` |
| F-06 | Source per app, filter laporan per source | ✔ (auto-create bisa dimatikan) | `apps.ts`, `reportQuery.ts` |
| F-07 | SDK web npm + 3 baris kode | ✔ belum dipublish | `packages/sdk-js`, `sdk-react` |
| F-08 | SDK Android | ✘ M4 | — |
| F-09 | Tahan 3 dtk, batal bila dilepas | ✔ `<SOSButton>` | `sdk-react/src/index.tsx` |
| F-10 | Antrian offline + idempotency | ✔ IndexedDB → localStorage → memori | `sdk-js/src/queue.ts` |
| F-11 | Status ke pengguna ≤ 5 dtk | ✔ polling 4 dtk | `sdk-js/src/index.ts` |
| F-12 | Live location tiap 15 dtk, berhenti saat selesai | ✔ | SDK + `POST /v1/sdk/reports/:id/locations` |
| F-13 | Daftar + peta realtime dengan bunyi | ◐ backend SSE siap (`/portal/reports/stream`); UI belum | `lib/realtime.ts` |
| F-14 | Ubah status + catatan, timeline | ✔ API | `lib/reports.ts#changeReport` |
| F-15 | Filter periode & ekspor CSV | ✔ API | `routes/portal/reports.ts` |
| F-16 | Email + web push ≤ 10 dtk | ◐ email ✔, web push belum | `lib/notify.ts` |
| F-17 | Webhook HMAC + retry 24 jam + log | ✔ worker di proses API | `lib/webhooks.ts` |
| F-18 | `/v1/reports` dengan secret key | ✔ (OpenAPI belum) | `routes/v1.ts` |
| F-19 | Admin menonaktifkan app | ✔ | `routes/admin.ts` |
| F-20 | Landing page | ✘ M1-frontend | — |
| F-21 | Formulir 3 langkah, draf otomatis | ◐ API ✔, draf disimpan di frontend | — |
| F-22 | Halaman status + perkiraan waktu | ✔ API | `GET /portal/onboarding/status` |
| F-23 | Antrean review terlama dulu, pratinjau, checklist | ✔ API | `routes/admin.ts` |
| F-24 | Approve / revisi / tolak + alasan + audit | ✔ | `POST /admin/accounts/:id/decision` |
| F-25 | Email tiap status berubah | ✔ | `lib/mailer.ts` |
| F-26 | Unggah ulang hanya dokumen yang ditandai | ✔ | `PATCH /admin/documents/:id` + onboarding |
| F-27 | Pengingat review > 36 jam kerja | ◐ `sla_warning` di antrean; notifikasi aktif belum | `lib/businessTime.ts` |
| F-28 | Suspend → semua kunci ditolak ≤ 60 dtk | ✔ | decision `suspended` |
| F-29 | Kunci test ≤ 1 menit setelah verifikasi; pk_live 403 | ✔ | `keyAuth.ts` |

## Keputusan desain yang menyimpang / menambah dari dokumen konsep

1. **Express 5 + TypeScript, tanpa ORM.** SQL langsung via `pg`, transaksi per request lewat `withTenant()` / `withPlatform()`.
2. **RLS dengan `account_id`, bukan `app_id`.** Kolom `account_id` didenormalisasi ke `reports`, `report_locations`, `report_events`, `sources`, `webhook_deliveries`, `account_documents`, sehingga policy tidak perlu join. Konteks di-set via `set_config('app.account_id', …, true)`. Tabel yang dicari sebelum tenant diketahui (`accounts`, `users`, `apps`, `api_keys`) diisolasi di repository.
3. **API wajib role non-superuser** (`siagasos_app`, `NOBYPASSRLS`). Smoke test memverifikasi bahwa query tanpa konteks melihat 0 laporan.
4. **Kolom tambahan** di luar skema konsep: `accounts.status_note/risk_flags/pic_is_director/rejected_at`, `account_documents.sha256/superseded_at`, `api_keys.plain_key/expires_at`, `apps.sdk_config/webhook_secret/disabled_at/auto_create_sources`, `reports.account_id/status_message/ip/client_created_at/acknowledged_at`, plus tabel `email_tokens` dan `audit_logs`.
5. **Rate limit fail-open.** Bila Redis mati, laporan tetap diterima. Kehilangan laporan darurat lebih buruk daripada spam sesaat.
6. **Pembatalan oleh pengguna hanya saat `open`.** Setelah petugas acknowledge, pembatalan harus lewat responder.
7. **Live tanpa `Origin` / `X-SOS-Bundle` ditolak.** Kunci test dengan `allowed_origins` kosong menerima semua origin, agar curl dan localhost langsung jalan.
8. **Dokumen dienkripsi AES-256-GCM di storage lokal.** Antarmuka `putPrivate/getPrivate` siap diganti S3/GCS/MinIO.
9. **Webhook worker berjalan di proses API** (`FOR UPDATE SKIP LOCKED`, aman multi-instance). BullMQ bisa menggantikannya saat volume naik.
10. **Re-registrasi setelah ditolak** tidak menghapus akun lama. NIB/email lama diarsipkan agar riwayat review tetap ada untuk audit.

## Belum dikerjakan (urut prioritas)

1. Frontend: landing (F-20), portal registrasi 3 langkah + kelola app/kunci, panel admin, dashboard responder dengan peta + bunyi (F-13). Semuanya di `apps/*` sebagai Vite + React.
2. Web push untuk responder (F-16), dengan VAPID dan tabel `push_subscriptions`.
3. OpenAPI spec untuk `/v1` (F-18) + quickstart per platform.
4. Pemindaian antivirus (ClamAV) saat unggah dokumen, dan penghapusan otomatis dokumen akun ditolak setelah 90 hari.
5. Notifikasi aktif SLA review (F-27), retensi / anonimisasi data per app (UU PDP).
6. Publish npm via Changesets + GitHub Actions, CI (typecheck, unit test, smoke dengan service container).
7. M4: SDK Android (Kotlin, WorkManager, FusedLocation).
