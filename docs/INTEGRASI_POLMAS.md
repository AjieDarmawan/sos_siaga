# Rencana integrasi: klien SiagaSOS → Polmas Digital

> Status: DRAFT v0.1 (23 Nov 2026). Belum ada kode. Keputusan terbuka di §8 perlu dijawab dulu.
> **Update 26 Nov 2026:** `/partner/v1` list, detail (+ media, timeline, track), actions sudah jalan (migrasi 016, lihat README §Mitra dan STATUS keputusan 25). Berbagi memakai pilar app (`apps.polmas_source`), wilayah dari `reports.kecamatan_code`. `satuan.wilayah_kode` + `X-Partner-Scope` di Polmas ✅ (cakupan ditegakkan di server). Belum: `/stream`, `/stats`.
> Repo terkait: `siagasos` (repo ini), `../polmas` (dashboard Polri), `../tata-warga-mobile` + `../tata-warga-be` (klien pilot pertama).

## 1. Alur yang dituju

```
 Aplikasi klien (tata-warga, kurir, kantor, ...)
   │  pasang SDK SiagaSOS (Flutter / Android / iOS / web), kunci pk_live_
   ▼
 SiagaSOS API ──► DB siagasos (reports, lokasi, media)       ← sumber kebenaran
   │   │
   │   ├─► dashboard tenant (portal :5174): petugas internal klien
   │   ├─► webhook ke backend klien (mis. tata-warga-be → alarm pengurus RT)
   │   │
   │   └─► [BARU] Feed mitra Polri: laporan yang dibagikan + kode wilayah
   │                │
   ▼                ▼
 Pengguna akhir   Polmas Digital (:5177)
 melihat status   server Polmas → konsol SOS, peta, KPI per Polda/Polres/Polsek
 "Polsek X        └─ tindakan petugas (diterima, diteruskan 110, ditangani)
  menangani"         dikirim balik ke SiagaSOS → tampil di SDK & portal klien
```

Prinsipnya:
- **SiagaSOS tetap satu-satunya tempat laporan disimpan.** Polmas tidak punya salinan permanen, hanya membaca lewat API (boleh cache agregat).
- **Polmas diperlakukan sebagai "mitra" lintas tenant**, bukan tenant biasa. Klien tidak perlu mengatur apa pun per Polsek.
- **Jalur SOS tidak berubah.** Penentuan wilayah dan penerusan ke Polmas berjalan async setelah laporan tersimpan (aturan CLAUDE.md). Bila Polmas mati, laporan tetap masuk dan tetap terlihat di portal klien.

## 2. Bagian 1: klien memasang SiagaSOS (sebagian besar sudah ada)

| Langkah klien | Status |
|---|---|
| Daftar perusahaan di portal, unggah dokumen, ditinjau admin | ✅ |
| Buat app, daftarkan bundle id / origin, ambil `pk_test_` lalu `pk_live_` | ✅ |
| Pasang SDK: Flutter ✅, Android ✅, iOS ✅, web/React ✅ | ✅ (publish ke pub/Maven/SPM/npm ⬜) |
| Tombol melayang `SOSFloatingButton` | Flutter ✅, Android/iOS ⬜ |
| Webhook ke backend klien | ✅ |
| **Halaman "Panduan integrasi" per platform** di landing/portal: instalasi, kode minimal, izin lokasi/kamera, uji pakai `pk_test_`, checklist go-live | ⬜ (README per SDK sudah ada, belum dirangkum untuk klien) |
| **Centang "Teruskan ke Polri (Polmas)" per app** + teks persetujuan untuk pengguna akhir | ⬜ baru |

## 3. Bagian 2: perubahan di SiagaSOS

### 3a. Wilayah per laporan (migrasi `003_wilayah.sql`)
- Aktifkan `postgis` (tersedia di server dev :5433, versi 3.5.6).
- Tabel platform `wilayah` (tanpa RLS, data publik): `kode` Kemendagri (provinsi `32`, kab/kota `32.71`, kecamatan `32.71.01`, kelurahan `32.71.01.1001`), `nama`, `tingkat`, `geom` (MultiPolygon). Pilot: batas kecamatan & kelurahan **Kota Bogor** (sama dengan data contoh Polmas), lalu Jabar, Metro Jaya, Jatim.
- Kolom baru `reports.wilayah_kode` + `reports.wilayah_sumber` (`gps` | `manual` | `null`), diisi worker setelah insert (point-in-polygon), bukan di request SOS. Lokasi live yang pindah kecamatan tidak mengubah wilayah awal, cukup dicatat sebagai event.
- Laporan tanpa GPS: `wilayah_kode` kosong, tetap dikirim ke Polmas tingkat polda/nasional sebagai "lokasi tidak diketahui" hanya bila app klien punya wilayah bawaan (`apps.default_wilayah_kode`, mis. lokasi kantor).

### 3b. Persetujuan berbagi
- `apps.share_polmas boolean DEFAULT false` + `share_polmas_since`. Hanya laporan `mode='live'` dari app yang mencentang yang bisa dilihat Polmas. Laporan test tidak pernah dibagikan.
- `/v1/sdk/config` mengembalikan `share_polmas` + teks pemberitahuan ("Laporan dan lokasi Anda diteruskan ke Polsek terdekat"), lalu SDK menampilkannya di layar persetujuan pertama (sejalan dengan item consent UU PDP yang memang belum dikerjakan).

### 3c. API mitra `/partner/v1` (baru)
- Auth: `Authorization: Bearer ptk_live_...` (kunci mitra, hash di tabel `partners` + `partner_keys`), dipanggil **hanya oleh server Polmas**, tidak pernah dari browser.
- Cakupan: server Polmas mengirim `X-Partner-Scope: 32.71.01` (kode wilayah satuan pengguna yang sedang login). SiagaSOS membatasi ke `wilayah_kode LIKE scope || '%'`, dan scope itu harus berada di dalam `partners.max_scope`.
- RLS: policy baru `partner_read` di `reports`, `report_locations`, `report_events`, `report_media` dengan syarat `share_polmas` + `mode='live'` + prefiks wilayah dari `current_setting('app.partner_scope')`. Akses lewat helper baru `withPartner(partnerId, scope, fn)` di `src/db.ts`, setara `withTenant()`.
- Endpoint:

| Method | Path | Isi |
|---|---|---|
| GET | `/partner/v1/reports?status=&since=&cursor=` | daftar laporan dalam cakupan |
| GET | `/partner/v1/reports/:id` | detail + lokasi live + media (URL baca 15 mnt) + timeline |
| GET | `/partner/v1/stream` | SSE `report.created`, `report.updated`, `report.location`, `report.media_added` dalam cakupan |
| GET | `/partner/v1/stats?from=&to=&group=kecamatan` | agregat untuk KPI & heatmap (jumlah, median respons, per kategori/jam) |
| POST | `/partner/v1/reports/:id/actions` | tindakan petugas: `acknowledge`, `forward_110`, `dispatch` (unit/nama petugas), `resolve`, `false_alarm`, `note` |

- Tindakan mitra dicatat di `report_events` dengan `actor_kind='partner'` (perlu ubah CHECK lewat migrasi) dan ikut ke webhook klien, dashboard tenant, dan status di SDK (mis. "Polsek Bogor Tengah menuju lokasi").
- Setiap baca detail oleh mitra masuk `audit_logs` (siapa di Polmas, satuan apa, kapan). Server Polmas mengirim `X-Partner-Actor: <id pengguna polmas>`.

### 3c-2. Pengaduan
Laporan `kind='pengaduan'` (menu "Laporan pengaduan" di tombol melayang) ikut dibagikan dengan aturan yang sama, tetapi tampil di Polmas sebagai jenis *pengaduan* (tanpa bunyi, tidak dihitung SOS aktif). Sudah berjalan lewat jembatan `/v1/reports` sementara.

### 3d. Data yang terlihat oleh Polmas (usulan, lihat §8)
Kategori, waktu, status, lokasi + lokasi live, pesan, media, nama app/klien, **nama & nomor telepon pelapor** (dibutuhkan untuk menelepon balik saat darurat). `reporter_ref`, IP, dan device tidak dibagikan.

## 4. Bagian 3: perubahan di Polmas

- **Pemetaan satuan → wilayah:** kolom `satuan.wilayah_kode` (migrasi `002_wilayah.sql` di polmas). Polsek Bogor Tengah = `32.71.01`, Polresta Bogor Kota = `32.71`, Polda Jabar = `32`, nasional = kosong.
- **Server data `/api/sos/*`** (middleware di server Polmas, sama seperti `/api/auth`): cek sesi, ambil `wilayah_kode` satuan pengguna, lalu meneruskan ke `/partner/v1` dengan kunci mitra dari `.env.local` (`SIAGASOS_PARTNER_KEY`, `SIAGASOS_API_URL`). Browser tidak pernah memegang kunci.
- **Konsol SOS (`#/sos`)**: data contoh `jenis: 'sos'` diganti data nyata dari SiagaSOS (laporan lain tetap data contoh sampai ada sumbernya). SSE diteruskan ke browser, bunyi + notifikasi, peta lokasi live, foto/video, tombol Terima / Teruskan 110 / Kirim unit / Selesai.
- **KPI & peta**: "SOS aktif", "Waktu respons SOS", pin SOS di peta, heatmap kerawanan, dan konteks asisten AI ikut membaca `/partner/v1/stats`. Tanpa `SIAGASOS_PARTNER_KEY`, Polmas tetap berjalan dengan data contoh (seperti sekarang tanpa DB).
- Penanda sumber: setiap laporan menampilkan nama klien/app ("Tata Warga", "Aplikasi Kurir") supaya petugas tahu asal laporan.

## 5. Bagian 4: tata-warga sebagai klien pilot

Temuan: tata-warga-mobile **sudah punya SOS sendiri** (`/sos`, `/keamanan/sos`, `draggable_sos_menu.dart`, `sos_tkp_page.dart`, `sos_alarm_service.dart`) ke tata-warga-be, dipakai untuk alarm pengurus RT.

Usulan (paling sedikit merusak):
1. Daftarkan "Tata Warga" sebagai tenant + app (bundle id Android & iOS), centang `share_polmas`.
2. Di mobile: `DraggableSosMenu` memanggil `SiagaSOS.trigger()` (paket `siagasos` Flutter) **menggantikan** POST `/sos`, atau dipakai langsung `SOSFloatingButton`. Foto/Video/Suara lewat `attach()`.
3. Di tata-warga-be: endpoint webhook SiagaSOS (`report.created`, `report.updated`) yang membuat/memperbarui data `keamanan/sos` lama, sehingga **alarm pengurus RT dan halaman laporan keamanan tetap berjalan tanpa perubahan besar**. Webhook membawa `reporter_ref` = id warga tata-warga.
4. Masa transisi: flag `useSiagaSOS` di `app_config.dart` agar bisa kembali ke jalur lama.

## 6. Tahapan kerja

| # | Tahap | Repo | Hasil yang bisa diuji |
|---|---|---|---|
| 1 | Migrasi wilayah + PostGIS + impor batas Kota Bogor + worker penentu wilayah | siagasos | Laporan dengan GPS di Bogor Tengah mendapat `wilayah_kode=32.71.01` dalam < 2 dtk |
| 2 | `share_polmas` per app (portal: centang + teks) + `/v1/sdk/config` | siagasos | Smoke: app tanpa centang tidak pernah muncul di feed mitra |
| 3 | Tabel mitra, kunci `ptk_`, `withPartner()`, policy RLS, `/partner/v1` (list, detail, stream, stats, actions) + audit | siagasos | Smoke baru: scope `32.71.01` tidak bisa melihat laporan `32.71.02`; tindakan mitra muncul di portal klien & status SDK |
| 4 | Polmas: `satuan.wilayah_kode`, proxy `/api/sos/*`, konsol SOS + KPI + peta dari data nyata | polmas | Login `kapolsek.bogor-tengah@…` melihat SOS dari demo app; `kapolsek.bogor-utara@…` tidak |
| 5 | Panduan integrasi klien (landing/portal) | siagasos | Klien baru bisa memasang dari `pk_test_` sampai go-live tanpa tanya |
| 6 | tata-warga: SDK Flutter di mobile + webhook di tata-warga-be | tata-warga-* | Tekan SOS di emulator → muncul di portal tenant, alarm pengurus RT, dan konsol Polsek |
| 7 | Uji ujung-ke-ujung + uji beban ringan + catat di PROGRESS/STATUS | semua | Skenario §7 lolos |

Tahap 1–3 tidak bergantung pada Polmas dan bisa diuji dengan smoke test. Tahap 4 dan 6 bisa dikerjakan paralel setelah tahap 3.

## 7. Skenario uji ujung-ke-ujung
1. Warga tata-warga di Bogor Tengah menahan tombol SOS 3 detik, lalu mengirim foto.
2. Dalam 2 detik: portal klien Tata Warga menerima SSE, tata-warga-be menerima webhook (alarm pengurus RT), konsol SOS Polsek Bogor Tengah berbunyi dengan lokasi + foto.
3. Kapolsek Bogor Utara dan pengguna klien lain tidak melihat laporan itu. Polresta Bogor Kota dan Polda Jabar melihatnya.
4. Petugas Polsek menekan "Kirim unit" → SDK warga menampilkan "Polsek Bogor Tengah menuju lokasi", portal klien menampilkan event dari mitra.
5. Matikan server Polmas → SOS tetap tersimpan, portal klien tetap jalan, dan begitu Polmas hidup laporan muncul lewat `since=`.

## 8. Keputusan yang perlu dari Anda
1. **Berbagi ke Polri:** opt-in per app (usulan) atau otomatis untuk semua klien live?
2. **Data pelapor ke Polri:** nama + nomor telepon ikut (usulan), atau hanya lokasi + kategori sampai petugas menekan "buka kontak" (tercatat di audit)?
3. **Siapa boleh mengubah status:** Polri dan petugas klien sama-sama boleh (usulan, semua tercatat di timeline), atau status "selesai" hanya dari satu pihak?
4. **Wilayah pilot:** Kota Bogor dulu (cocok dengan akun dummy Polmas), atau langsung Jabar/Metro Jaya/Jatim?
5. **tata-warga:** SOS lama diganti SiagaSOS + webhook ke tata-warga-be (usulan), atau berjalan berdampingan dulu?
6. **Urutan terhadap prioritas "fokus mobile":** kerjakan integrasi ini sekarang, atau setelah `SOSFloatingButton` Android/iOS selesai?
