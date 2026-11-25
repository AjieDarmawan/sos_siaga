# PRD Polmas Keamanan v2: aplikasi penerima SOS untuk Nomor Darurat

> Disusun dari arahan user 25 Nov 2026 (menggantikan v1 di file ini). PRD awal: "PRD Polmas Keamanan" (@Ruki).
> Kode: Flutter `apps/polmas-keamanan`, API `/v1/pk/*` di `apps/api`, DB `siagasos` yang sama.
> Status: **disetujui konsepnya, menunggu jawaban pertanyaan §9 sebelum eksekusi.**

## 1. Gambaran besar

**SiagaSOS** = SDK + platform SaaS yang dipasang klien di aplikasinya. Klien dikelompokkan dalam **5 pilar**:

| Pilar | Contoh aplikasi klien | `apps.polmas_source` (kode) |
|---|---|---|
| UMKM | commerceOS (POS kios/toko) | `umkm` |
| Lingkungan | polmas / tata-warga mobile | `warga` → ditampilkan "Lingkungan" |
| Perkantoran | (klien kantor) | `kantor` → "Perkantoran" |
| Pendidikan | (klien sekolah) | `sekolah` → "Pendidikan" |
| Komunitas | (klien komunitas) | `komunitas` |

SDK di aplikasi klien punya tiga aksi: **EWS Alert / Emergency** (SOS), **Call 110**, dan **Laporan Kejadian**.
Di dalam Laporan Kejadian ada menu **Nomor Darurat** (nama, jabatan, nomor, wilayah tugas), yang dipetakan ke pilar
aplikasinya.

**Polmas Keamanan** = aplikasi **penerima** untuk pemilik Nomor Darurat (pemilik toko, satpam, ketua RT/RW,
Bhabinkamtibmas, guru, dst.).

## 2. Perubahan alur SOS (inti)

| | Sebelum | Sesudah (Polmas Keamanan) |
|---|---|---|
| Pelapor tekan Emergency | sirene di HP pelapor + WhatsApp ke Nomor Darurat | **push FCM + sirene di HP penerima** (app Polmas Keamanan) |
| Penerima | hanya membaca WA | login di app, layar panggilan SOS, lihat bukti, tindak lanjut |
| Status ke pelapor | tidak ada | tindak lanjut tampil di SDK pelapor (riwayat laporan) |

Prinsip tetap: jalur `POST /v1/sdk/reports` tidak bergantung pada FCM/WA (dikirim async setelah tersimpan).

## 3. Siapa yang login

- Nomor yang terdaftar sebagai **Nomor Darurat** di aplikasi klien mana pun (`emergency_contacts`). Tanpa daftar mandiri.
- Login: nomor → password (login pertama = buat password). Nomor & password diingat di perangkat (login cepat).
- **Peran & wilayah TIDAK diambil dari GPS saat login.** Keduanya diambil dari isian Nomor Darurat:
  - peran = jabatan kontak (Satpam, Pemilik toko, Ketua RT, Bhabinkamtibmas, Guru, …),
  - pilar = pilar aplikasi yang mendaftarkan nomor itu,
  - wilayah = `emergency_contacts.area` (wajib untuk Bhabinkamtibmas, opsional untuk lainnya).
  → Langkah "Konfirmasi wilayah" di login **dihapus**.
- Satu nomor bisa terdaftar di banyak kios/warga/pilar → semua SOS yang memanggil nomornya masuk ke app yang sama;
  peran ditampilkan per sumber.

## 4. Fitur

### 4.1 Panggilan SOS masuk (FCM + sirene)
- SOS yang mencantumkan nomor penerima → push FCM prioritas tinggi (kanal `polmas_sos_v2`, suara sirene commerceOS `sos_siren`), juga saat app
  tertutup / layar terkunci → layar panggilan penuh (Terima / Abaikan).
- Bhabinkamtibmas juga menerima SOS dari kecamatan wilayah tugasnya.
- Saat app terbuka: polling 4 dtk tetap ada sebagai cadangan.

### 4.2 Beranda (homepage)
- Header sama di semua layar (navy + gelombang merah): sapaan, **peran penerima** (mis. "Satpam · Toko Roti Sinar Jaya",
  "Bhabinkamtibmas · Kec. Bogor Tengah"), pilar, lonceng.
- Kartu angka: SOS hari ini, Laporan baru, Dalam penanganan, Selesai.
- **Daftar Tindak Lanjut** berisi kolom (tampilan kartu di HP, tabel geser bila dipilih):

| Kolom | Isi | Sumber |
|---|---|---|
| Berita | judul/uraian kejadian | SOS/laporan |
| No HP | nomor pelapor (ketuk = telepon) | SOS |
| Ekosistem | pilar + aplikasi asal (mis. "UMKM · commerceOS") | app sumber |
| Dari Siapa | nama pelapor + tempat (kios/rumah) | SOS |
| Foto/Video | gambar mini bukti, putar video | media laporan |
| Location | alamat/kelurahan + jarak, ketuk = peta | GPS laporan |
| Waktu | waktu kejadian / SOS | SOS |
| Status | Darurat / Diproses / Selesai | laporan |
| Tindak Lanjut | tanggapan terakhir penerima + catatan | penerima |

### 4.3 Detail & tindak lanjut
- Peta, bukti foto/video/suara, langkah status (Diterima → Diverifikasi → Ditangani → Selesai), tombol aksi.
- Setiap tindak lanjut tercatat (siapa, kapan, catatan) dan kembali ke pelapor + dashboard klien.

### 4.4 Riwayat & Analisa
- Riwayat: Saya / Wilayah, cari & filter.
- Analisa: tren harian, per kelurahan, per pilar, jenis kejadian, jam rawan, waktu respons, % selesai, perbandingan
  periode sebelumnya, ekspor PDF.

## 5. Perubahan di SDK & API (akibat §2)
- API: kirim FCM ke perangkat Polmas Keamanan milik nomor yang dipanggil (`pk_sessions.fcm_token`), catat di timeline.
- WA SOS & sirene lokal di SDK: lihat pertanyaan §9.
- Nomor Darurat di SDK: jabatan & wilayah sesuai pilar (lihat §9).

## 6. Tampilan
- Mengikuti mockup user (splash, login, beranda, detail, riwayat, analisa, SOS masuk, profil).
- Header/app bar seragam di semua layar.

## 7. Sudah ada (v1, 25 Nov 2026)
API `/v1/pk` + migrasi 011/012, login dari Nomor Darurat, peran `penerima`, panggilan via polling, beranda/detail/
riwayat/analisa/profil sesuai mockup, smoke 134 cek.

## 8. Belum / akan dikerjakan
FCM + sirene saat app tertutup, hapus langkah wilayah GPS, peran & wilayah dari Nomor Darurat di header, kolom
Tindak Lanjut lengkap + foto, label pilar baru, header seragam, perbaikan luapan teks kartu/tabel.

## 9. Keputusan user (25 Nov 2026)

1. **WhatsApp & sirene lokal dihapus total.** Emergency tidak lagi mengirim WA ke Nomor Darurat dan tidak membunyikan
   sirene di HP pelapor. Satu-satunya kanal = push FCM + sirene di app Polmas Keamanan. (Nomor darurat yang belum
   pasang/login app tidak mendapat kabar: konsekuensi yang diterima.)
2. **Tindak Lanjut**: Berita, No HP, Ekosistem, Dari Siapa, Foto/Video, Location, Waktu terisi **otomatis** dari SOS.
   Penerima mengisi **Status** + catatan **Tindak Lanjut** (boleh melampirkan foto/video dari HP-nya).
3. **Jabatan Nomor Darurat dibatasi per pilar** (dropdown di SDK):

   | Pilar | Jabatan |
   |---|---|
   | UMKM | Pemilik toko, Karyawan, Satpam, Bhabinkamtibmas |
   | Lingkungan | Ketua RT, Ketua RW, Satpam, Bhabinkamtibmas |
   | Perkantoran | Pimpinan, Koordinator keamanan, Satpam, Polsek |
   | Pendidikan | Orang tua, Guru, Satpam, Kepala sekolah |
   | Komunitas | Bhabinkamtibmas, Keamanan, Security, Ketua komunitas |

   Tanpa pilihan "Lainnya"/isian bebas dan tanpa "Keluarga"; teks batas "maks. 5 aktif" tidak ditampilkan di form.
4. **FCM memakai project Firebase baru** khusus Polmas Keamanan. Kode disiapkan sekarang; file konfigurasi
   (`google-services.json`, `GoogleService-Info.plist`, service account untuk API) dikirim user.
5. **Pilar dipilih saat membuat app di portal SiagaSOS** (saran user): form "Buat app / API key" punya dropdown
   "Aplikasi ini untuk apa?" → UMKM / Lingkungan / Perkantoran / Pendidikan / Komunitas, disimpan di
   `apps.polmas_source`. Dipakai untuk kolom Ekosistem, daftar jabatan Nomor Darurat di SDK, dan analitik per pilar.

6. **Wilayah hanya untuk Nomor Darurat berjabatan Bhabinkamtibmas** (klarifikasi user): saat jabatan itu dipilih di
   SDK, muncul pemilih provinsi → desa yang terisi otomatis dari lokasi HP pelapor (sudah ada di SDK). App Polmas
   Keamanan **tidak membaca wilayah lagi**: Bhabinkamtibmas memakai wilayah dari isian itu, penerima lain (satpam,
   pemilik toko, RT, dll.) tidak punya wilayah dan hanya menerima SOS yang memanggil nomornya. Lokasi HP penerima hanya
   dipakai untuk menghitung jarak ke SOS ("± 350 m").

## 10. Urutan eksekusi
1. Portal + API: dropdown pilar di app, `pillar` + daftar jabatan di `/v1/sdk/config`.
2. API: hentikan WA SOS; FCM ke perangkat Polmas Keamanan (`POST /v1/pk/me/device`, env `PK_FCM_SERVICE_ACCOUNT`).
3. SDK Flutter (+ Android): sirene lokal tidak lagi dibunyikan; dropdown jabatan per pilar.
Status 25 Nov 2026: 1 ✅, 2 ✅ (Firebase `siagasos-a61e9`, service account di `apps/api/.env` `PK_FCM_SERVICE_ACCOUNT`,
`google-services.json` di app), 3 ✅ Flutter + Android (sirene lokal dimatikan; dropdown jabatan dari `contact_roles`),
4 ✅ (lihat PROGRESS.md). iOS app belum punya `GoogleService-Info.plist`.

4. App: hapus langkah wilayah GPS, header peran dari Nomor Darurat, header/app bar seragam, kolom Tindak Lanjut + foto,
   label pilar, FCM (aktif setelah file Firebase ada), perbaikan luapan teks.
