# Polmas Keamanan (Flutter)

Aplikasi **penerima** untuk pemilik Nomor Darurat. Nomor yang dimasukkan di menu Nomor Darurat aplikasi yang memasang
SDK SiagaSOS (commerceOS POS → pemilik toko, satpam; tata-warga → ketua RT/RW, satpam, Bhabinkamtibmas) bisa login di
sini, menerima panggilan SOS, melihat bukti foto/video, lalu menanggapi. Status tanggapan kembali ke SDK pelapor.

Konsep & aturan akses: [`docs/POLMAS_KEAMANAN.md`](../../docs/POLMAS_KEAMANAN.md). API: `/v1/pk` di `apps/api` (DB `siagasos`).

## Menjalankan

```bash
# API + data demo (dari root repo)
pnpm migrate && pnpm dev:api
pnpm seed:pk                      # butuh pnpm seed:demo sebelumnya

# HP Android via USB (API di laptop)
adb reverse tcp:4000 tcp:4000
cd apps/polmas-keamanan
flutter run                       # default API_URL=http://localhost:4000
flutter run --dart-define=API_URL=https://sos.tip2.co   # server lain
```

Akun demo (password `demo1234`):

| Nomor | Siapa | Uji |
|---|---|---|
| 0800 111 0002 | Aiptu Rahmat, Bhabinkamtibmas Bogor Tengah (+ penerima di kios & warga) | semua laporan kecamatan, tanggapi, evaluasi |
| 0800 111 0004 | Hendra, pemilik Toko Roti Sinar Jaya | SOS dari kiosnya |
| 0800 111 0001 | Budi, Ketua RT 03 | SOS warga, riwayat Saya |
| 0800 111 0006 | Agus, satpam (tanpa akun) | **login pertama = buat password** |

Profil → **Simulasi SOS masuk** (akun demo) membuat SOS fiktif yang memanggil nomor Anda → layar panggilan muncul ±5 dtk.

## Struktur

```
lib/
  core/       api.dart (klien /v1/pk), app_state.dart (sesi, login cepat, polling SOS), models.dart, format.dart
  theme/      tokens.dart (design token PRD §7.1), app_theme.dart (Plus Jakarta Sans, terang/gelap)
  widgets/    common.dart (tombol, kolom, kartu insiden, lencana, toast, animasi), charts.dart, incident_map.dart,
              report_list.dart, report_filters.dart, map_widgets.dart
  screens/    splash → login (nomor → password / buat password) → area (GPS) → home_shell
              (Beranda 5 tab · Laporan · Riwayat · Analisa · Profil), incident, sos_call, notifications, news, video
assets/sounds/siren.wav   sirene sintetis (dibuat skrip, tanpa aset pihak ketiga)
```

## Catatan

- Panggilan SOS masuk memakai polling `/v1/pk/inbox` tiap 4 dtk **saat app terbuka**. Push FCM (app tertutup) belum.
- Nomor & password login cepat disimpan di `flutter_secure_storage` (Keystore/Keychain); "Lupakan perangkat" menghapusnya.
- Semua animasi mengikuti "kurangi gerakan" perangkat. Warna grafik divalidasi (CVD/kontras) untuk terang & gelap.
- Peta: tile OpenStreetMap (tanpa API key). Untuk produksi bervolume tinggi pakai penyedia tile berbayar.
