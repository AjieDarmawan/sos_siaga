# Polmas Keamanan: aplikasi penerima Nomor Darurat

> Konsep dari user (25 Nov 2026), jangan diubah tanpa konfirmasi. PRD lengkap: "PRD Polmas Keamanan" (@Ruki, 25 Nov 2026).
> Kode: Flutter `apps/polmas-keamanan`, API `/v1/pk/*` di `apps/api` (`src/routes/polmas.ts`, `src/lib/polmas.ts`), DB `siagasos` yang sama.

## 1. Inti konsep

Aplikasi klien yang memasang SDK SiagaSOS punya tombol SOS **dan menu Nomor Darurat**. Polmas Keamanan adalah
**aplikasi untuk pemilik nomor-nomor darurat itu**: mereka login dengan nomor tersebut, lalu menerima dan menanggapi
SOS dari kios/warga yang mencantumkan nomornya.

```
 App sumber (pasang SDK SiagaSOS)            Nomor Darurat yang diisi            Login di Polmas Keamanan
 ─────────────────────────────────           ────────────────────────            ────────────────────────
 commerceOS POS (kios/kasir)          ──►    pemilik toko, satpam          ──►   lihat SOS kios tsb, terima, tangani
 polmas / tata-warga mobile (warga)   ──►    ketua RT, RW, satpam,         ──►   lihat SOS warga tsb + laporan
                                             Bhabinkamtibmas (berwilayah)        kecamatan (Bhabinkamtibmas)
 app lain (kantor, sekolah, UMKM, …)  ──►    koordinator, guru, orang tua  ──►   sama
```

1. Kasir/warga mengisi Nomor Darurat di app sumber → SDK menyinkronkan ke `emergency_contacts` (`PUT /v1/sdk/contacts`,
   termasuk `role` dan `area` wilayah tugas, migrasi 010).
2. Kasir/warga menekan SOS → `reports.emergency_contacts` menyimpan snapshot nomor yang dipanggil.
3. Pemilik nomor membuka Polmas Keamanan → login dengan nomor itu → layar panggilan SOS masuk, daftar, detail, peta,
   bukti foto/video, lalu aksi Terima / Hubungi / Verifikasi / Tangani / Selesai.
4. Setiap tanggapan lewat `changeReport` → timeline, realtime dashboard tenant, webhook, dan status di SDK pelapor
   ("Satpam Agus sedang menangani…").

## 2. Siapa boleh login

| Sumber nomor | Boleh login | Catatan |
|---|---|---|
| Ada di `emergency_contacts` aktif, app mana pun | ✅ | jalur utama |
| Akun `pk_users` dibuat admin (`pnpm pk:user`) | ✅ | untuk Bhabinkamtibmas / warga tanpa kontak, dan data demo |
| Nomor lain | ❌ | "Nomor belum terdaftar sebagai Nomor Darurat" (tanpa daftar mandiri, sesuai PRD) |

- Login: nomor → password. **Login pertama** nomor dari Nomor Darurat = membuat password (akun `pk_users` dibuat
  otomatis). Berikutnya login biasa; nomor & password tersimpan terenkripsi di perangkat (login cepat).
- Tanpa OTP/WA (PRD: tanpa WhatsApp/SMS API; sejalan dengan keputusan login satpam tanpa OTP 2026-11-23). Risiko: orang
  yang tahu nomor bisa mengklaim lebih dulu → dibatasi rate limit, dicatat di `pk_audit`. Opsi pengetatan nanti: OTP
  lewat push/WA, atau konfirmasi pemilik kios.
- Sesi 12 jam (`pks_…`, hanya hash di DB).

## 3. Peran & hak

Peran diturunkan dari isian Nomor Darurat (disinkron ke `pk_user_roles` setiap login) + peran buatan admin.

| Peran | Dari | Melihat | Menanggapi |
|---|---|---|---|
| `penerima` (pemilik toko, satpam, RT, RW, keluarga, …) | `emergency_contacts.role` bebas | SOS & laporan yang mencantumkan nomornya | ✅ laporan yang mencantumkan nomornya |
| `bhabinkamtibmas` | `role` mengandung "bhabin", wilayah dari `area.district` | + semua laporan di kecamatannya | ✅ semua di kecamatannya |
| `warga` / `kantor` / `umkm` / `sekolah` / `komunitas` | admin | laporan kecamatannya (identitas disamarkan) | ❌ |

- Satu nomor bisa punya beberapa peran/wilayah (mis. satpam di 2 kios + warga) → pindah peran di Profil.
- Laporan yang memanggil nomor pengguna **selalu** terlihat (tidak perlu `apps.polmas_source`).
- Tampilan per kecamatan hanya memuat laporan dari app yang ditandai `apps.polmas_source` (persetujuan berbagi).
- Identitas & lokasi persis pelapor hanya untuk penerima yang dipanggil, Bhabinkamtibmas, dan pelapor sendiri.

## 4. Alur layar (PRD §4, §7.3)

Splash Merah Putih → Login nomor → Password (atau Buat password di login pertama) → Konfirmasi wilayah (GPS, isi
otomatis, bisa dikoreksi) → Beranda (kartu angka + tab Berita/Laporan/Video/Lokasi/Waktu) · Laporan · Riwayat (Saya /
Kecamatan) · Analisa (+ Evaluasi) · Profil. Panggilan SOS masuk = layar penuh merah (polling `/v1/pk/inbox` tiap 4 dtk
saat app terbuka; push FCM menyusul).

## 5. Status

- API `/v1/pk` + migrasi 011 (+ 012 untuk peran `penerima` & login dari Nomor Darurat), seed demo `pnpm seed:pk`.
- Flutter: sedang dibangun. Lihat log di `PROGRESS.md`.
- Belum: push FCM (app tertutup), antrean offline (FR-13), ekspor PDF (FR-21).
