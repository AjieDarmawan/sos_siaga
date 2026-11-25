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
| F-08 | SDK Android | ✔ native Kotlin + Flutter + iOS Swift (semua teruji, termasuk integrasi); tombol melayang ✔ Flutter (`SOSFloatingButton`, 4 aksi termasuk **Laporan pengaduan** `kind='pengaduan'`), Android/iOS belum | `packages/sdk-android`, `packages/sdk-flutter`, `packages/sdk-ios` |
| F-09 | Tahan 3 dtk, batal bila dilepas | ✔ `<SOSButton>` | `sdk-react/src/index.tsx` |
| F-10 | Antrian offline + idempotency | ✔ IndexedDB → localStorage → memori | `sdk-js/src/queue.ts` |
| F-11 | Status ke pengguna ≤ 5 dtk | ✔ polling 4 dtk | `sdk-js/src/index.ts` |
| F-12 | Live location tiap 15 dtk, berhenti saat selesai | ✔ | SDK + `POST /v1/sdk/reports/:id/locations` |
| F-13 | Daftar + peta realtime dengan bunyi | ✔ SSE + Leaflet/OSM + alarm Web Audio (ulang tiap 20 dtk selama ada laporan Baru) + notifikasi browser | `apps/portal/src/pages/Dashboard.tsx` |
| F-14 | Ubah status + catatan, timeline | ✔ API + UI panel detail | `lib/reports.ts#changeReport`, `Dashboard.tsx` |
| F-15 | Filter periode & ekspor CSV | ✔ API + UI (24 jam/7/30 hari, live/test, ekspor) | `routes/portal/reports.ts`, `Dashboard.tsx` |
| F-16 | Email + web push ≤ 10 dtk | ◐ email ✔, web push belum | `lib/notify.ts` |
| F-17 | Webhook HMAC + retry 24 jam + log | ✔ worker di proses API | `lib/webhooks.ts` |
| F-18 | `/v1/reports` dengan secret key | ✔ (OpenAPI belum) | `routes/v1.ts` |
| F-19 | Admin menonaktifkan app | ✔ | `routes/admin.ts` |
| F-20 | Landing page | ✔ 7 bagian, animasi CSS, Lighthouse 94/100/100/100 (prod build) | `apps/portal/src/pages/Landing.tsx` |
| F-21 | Formulir 3 langkah, draf otomatis | ✔ draf di localStorage (tanpa password), validasi saat blur | `apps/portal/src/pages/Register.tsx` |
| F-22 | Halaman status + perkiraan waktu | ✔ API + UI (unggah/unggah ulang dokumen, ajukan) | `apps/portal/src/pages/Onboarding.tsx` |
| F-23 | Antrean review terlama dulu, pratinjau, checklist | ✔ API + UI (pratinjau PDF/gambar via signed URL → blob) | `routes/admin.ts`, `apps/admin` |
| F-24 | Approve / revisi / tolak + alasan + audit | ✔ API + UI | `POST /admin/accounts/:id/decision`, `apps/admin/src/pages/AccountDetail.tsx` |
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
11. **Portal dan dashboard responder satu app** (`apps/portal`), bukan `apps/dashboard` terpisah: login JWT, origin, dan data sama. Responder otomatis diarahkan ke `/dashboard` dan tidak melihat menu App/Tim.
13. **Panel admin app terpisah** (`apps/admin`, origin & token sendiri di sessionStorage) supaya XSS di portal klien tidak bisa mencuri sesi admin. Komponen UI dipakai bersama lewat alias `@portal`.
14. **Landing & docs di dalam `apps/portal`** (route publik `/`, `/docs`), bukan `apps/landing` terpisah: satu deploy, header login konsisten, Lighthouse tetap ≥ 90.
15. **Media laporan (foto/video/suara) diunggah langsung ke MinIO lewat presigned PUT**, bukan lewat API. `ContentLength` ikut ditandatangani (file lebih besar ditolak storage), `complete` memverifikasi objek dengan HEAD. Bucket `sos-siaga` privat; dibaca lewat presigned GET 15 menit. Jalur `POST /v1/sdk/reports` tetap tidak bergantung pada storage.
16. **MinIO membalas 403 (bukan 404) untuk objek yang belum ada** dan kadang belum melihat objek sesaat setelah PUT. `headObject` menganggap 403/404 sebagai "belum ada" dan mencoba ulang ±3 dtk.
17. **Tema** disimpan per browser (localStorage `siagasos.theme`) dan dipasang skrip inline sebelum render. Warna aksen tidak menawarkan merah (dicadangkan untuk darurat).
12. **Peta memakai tile OSM standar** yang diredam lewat CSS filter (tanpa API key). Basemap CARTO kini butuh API key. Untuk produksi bervolume tinggi, ganti ke penyedia tile berbayar (kebijakan tile OSM).
18. **Pembersihan berkala di proses API** (`lib/maintenance.ts`, tiap 10 menit): media `pending` > URL upload (15 mnt) + 1 jam dihapus dari bucket lalu DB; OTP responder kedaluwarsa > 1 hari dibuang. `pg_try_advisory_xact_lock` memastikan satu instance per putaran.
19. **Retensi = hapus permanen, bukan anonimisasi** (migrasi 006). `apps.retention_days` (NULL = tanpa batas, 30–3650) berlaku untuk laporan live berstatus akhir, dihitung dari `resolved_at`; laporan test 30 hari. SOS yang belum ditutup tidak pernah dihapus. `DELETE /v1/reporters/:ref` (secret key, per mode kunci) menghapus laporan + `emergency_contacts`; audit log menyimpan hash ref, bukan ref polos. Objek MinIO dihapus setelah commit (gagal → objek yatim, data DB tetap terhapus). `webhook_deliveries.report_id` jadi `ON DELETE SET NULL`.
20. **Wilayah Indonesia disimpan di tabel `wilayah` sendiri** (migrasi 009, 91.599 baris, cahyadsn/wilayah MIT, Kepmendagri 2025, sama dengan tata-warga), bukan API pihak ketiga, supaya pemilih provinsi → desa di SDK tidak bergantung layanan luar. Reverse geocode lokasi → wilayah memakai Nominatim (bisa diganti lewat `GEOCODER_URL`) lalu nama dicocokkan ke kode `wilayah` level demi level; koordinat dibulatkan 3 desimal sebelum keluar server. Gagal/ambigu → sebagian level `null`, pengguna memilih manual. Wilayah tugas kontak disimpan di `emergency_contacts.area` (migrasi 010).
21. **Polmas Keamanan = app penerima Nomor Darurat** (konsep user 2026-11-25, [POLMAS_KEAMANAN.md](POLMAS_KEAMANAN.md)). Nomor yang diisi di menu Nomor Darurat SDK (`emergency_contacts`) bisa login; login pertama membuat password sendiri tanpa OTP (PRD: tanpa WA/SMS; sama dengan keputusan login satpam). Peran `penerima`/`bhabinkamtibmas` diturunkan dari isian kontak setiap login (`pk_user_roles.from_contact`, migrasi 012). API `/v1/pk` di proses API yang sama (bukan layanan terpisah), membaca lintas tenant dengan `withPlatform()`; tabel `pk_*` platform ber-RLS `platform_only`, `pk_responses` ber-RLS `tenant_isolation` (migrasi 011). SOS yang memanggil nomor pengguna selalu terlihat; tampilan per kecamatan hanya dari app bertanda `apps.polmas_source`. Kecamatan laporan diisi worker async (Nominatim, ±1 req/dtk), bukan di jalur SOS. Identitas & lokasi persis pelapor hanya untuk penerima yang dipanggil, Bhabinkamtibmas, dan pelapor sendiri; peran lain melihat nama disamarkan & lokasi ±100 m. Panggilan masuk lewat polling 4 dtk saat app terbuka (FCM menyusul).
22. **Kanal SOS = push FCM + sirene di app Polmas Keamanan; WA & sirene lokal dimatikan** (keputusan user 2026-11-25). `dispatchSosWhatsApp` hanya jalan bila `SOS_WHATSAPP=true` (rollback). FCM dua project: `FCM_SERVICE_ACCOUNT` (satpam di app klien/POS) dan `PK_FCM_SERVICE_ACCOUNT` (Polmas Keamanan, kanal Android `polmas_sos_v2` bersuara `sos_siren` = sirene commerceOS; v1 `polmas_sos` dihapus app karena suara kanal tidak bisa diganti). Token perangkat di `pk_devices` (migrasi 013), tidak ikut sesi 12 jam; penerima per SOS dicatat di `pk_push_log` (kontak darurat dulu, Bhabinkamtibmas kecamatan setelah worker mengisi wilayah). App memakai `getToken()` FCM (bukan `register()`/FID baru) karena server mengirim via HTTP v1 `message.token`. Pilar app dipilih di portal (`apps.polmas_source`, label UMKM/Lingkungan/Perkantoran/Pendidikan/Komunitas di `@siagasos/shared`); jabatan Nomor Darurat per pilar dikirim lewat `/v1/sdk/config.contact_roles`.
23. **App Polmas Keamanan mengikuti mockup Opsi A** (keputusan user 2026-11-25, [mockups/polmas-digital.html](mockups/polmas-digital.html)): layar Riwayat, Berita, Video, Notifikasi, Wilayah dibuang; tidak ada status tugas/shift; kategori apa adanya dari API. Data mockup dari `/v1/pk/analytics/summary` (ekosistem = pilar + nama app, median waktu respons = `percentile_cont` dari `acknowledged_at`, alur status, per petugas, saran patroli dihitung server), `/me/stats`, `/me/devices` (nama HP, migrasi 014), `/me/password`. Nomor tiket `SOS-YYMM-XXXX` diturunkan dari id, bukan kolom baru.
10. **Re-registrasi setelah ditolak** tidak menghapus akun lama. NIB/email lama diarsipkan agar riwayat review tetap ada untuk audit.

## Belum dikerjakan (urut prioritas)

1. Isi PRD asli belum ada di repo: landing dibuat dengan 7 bagian usulan (hero, masalah + untuk siapa, cara kerja, fitur, developer, verifikasi & paket, FAQ + CTA). Cocokkan begitu PRD tersedia (simpan sebagai `docs/PRD.md`).
2. Web push untuk responder (F-16), dengan VAPID dan tabel `push_subscriptions`.
3. OpenAPI spec untuk `/v1` (F-18) + quickstart per platform.
4. Pemindaian antivirus (ClamAV) saat unggah dokumen, dan penghapusan otomatis dokumen akun ditolak setelah 90 hari.
5. Notifikasi aktif SLA review (F-27), retensi / anonimisasi data per app (UU PDP).
6. Publish npm via Changesets + GitHub Actions, CI (typecheck, unit test, smoke dengan service container).
7. M4: SDK Android (Kotlin, WorkManager, FusedLocation).
