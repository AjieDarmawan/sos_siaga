# Polmas Keamanan (Flutter)

Aplikasi **penerima SOS** untuk pemilik Nomor Darurat. Aplikasi klien SiagaSOS (5 pilar: UMKM, Lingkungan, Perkantoran,
Pendidikan, Komunitas) punya menu Nomor Darurat. Nomor yang didaftarkan di sana (pemilik toko, satpam, ketua RT/RW,
Bhabinkamtibmas, guru, …) login di app ini, menerima **push FCM + sirene** saat Emergency ditekan, melihat bukti, lalu
mengisi Status & Tindak Lanjut yang kembali ke pelapor. Emergency tidak lagi mengirim WA / membunyikan sirene di HP
pelapor.

PRD & keputusan: [`docs/POLMAS_KEAMANAN.md`](../../docs/POLMAS_KEAMANAN.md). API: `/v1/pk` di `apps/api` (DB `siagasos`).

## Menjalankan

```bash
# dari root repo
pnpm migrate && pnpm dev:api      # restart API setelah mengubah .env (PK_FCM_SERVICE_ACCOUNT)
pnpm seed:pk                      # data demo (butuh pnpm seed:demo sebelumnya)

# HP Android via USB (API di laptop)
adb reverse tcp:4000 tcp:4000     # ulangi setiap kabel dicabut / HP restart
cd apps/polmas-keamanan
flutter run                       # default API_URL=http://localhost:4000
flutter run --dart-define=API_URL=https://sos.tip2.co
```

Tanpa kabel: `flutter run --dart-define=API_URL=http://<IP-laptop>:4000` (HP & laptop satu Wi-Fi).

## Alur

Splash → Masuk (nomor dari Nomor Darurat → password; login pertama = buat password) → Beranda.
**Tidak ada langkah wilayah.** Peran & wilayah berasal dari isian Nomor Darurat: wilayah hanya untuk jabatan
Bhabinkamtibmas (dipilih di SDK, default dari lokasi HP). Lokasi HP penerima hanya dipakai untuk jarak "± 350 m".

Beranda: kartu angka + tab Berita / Laporan / Video / Lokasi / Waktu. Tab Laporan menampilkan kolom Berita, No HP,
Ekosistem, Dari Siapa, Foto/Video, Lokasi, Waktu, Status, Tindak Lanjut (tampilan kartu atau tabel).

## Push FCM (project Firebase `siagasos-a61e9`)

| Bagian | File / env |
|---|---|
| App Android | `android/app/google-services.json` (package `id.polmas.polmas_keamanan`), plugin `com.google.gms.google-services` |
| Kanal sirene | `MainActivity.kt` membuat kanal `polmas_sos` bersuara `res/raw/siren.wav` (prioritas tinggi, tembus Jangan Ganggu) |
| Server | `apps/api/.env` `PK_FCM_SERVICE_ACCOUNT=<path/isi JSON service account>` (jangan di-commit) |
| iOS | belum: perlu `ios/Runner/GoogleService-Info.plist` + APNs key di Firebase |

Setelah login, app mendaftarkan token FCM (`POST /v1/pk/me/device`); saat keluar token dilepas. Push SOS sampai bila
nomor penerima ada di Nomor Darurat SOS itu dan HP-nya pernah login + mengizinkan notifikasi.

## Akun demo (`pnpm seed:pk`, password `demo1234`)

| Nomor | Siapa |
|---|---|
| 0800 111 0002 | Aiptu Rahmat, Bhabinkamtibmas Bogor Tengah (+ Nomor Darurat kios & warga) |
| 0800 111 0004 | Hendra, pemilik Toko Roti Sinar Jaya (UMKM) |
| 0800 111 0001 | Budi, Ketua RT 03 (Lingkungan) |
| 0800 111 0006 | Agus, satpam, belum punya akun → login pertama membuat password |

Profil → **Simulasi SOS masuk** (akun demo) memunculkan layar panggilan ±5 dtk.

## Struktur

```
lib/core/     api.dart, app_state.dart (sesi, login cepat, polling, FCM), push.dart, models.dart, format.dart
lib/theme/    tokens.dart (design token PRD), app_theme.dart (app bar navy seragam)
lib/widgets/  brand.dart (logo, header gelombang), common.dart, report_table.dart (kolom Tindak Lanjut),
              report_list.dart, search_filter.dart, charts.dart, incident_map.dart, map_widgets.dart
lib/screens/  splash, login, home_shell, dashboard, reports, history, analytics, profile, incident, sos_call, …
```
