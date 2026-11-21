# Design system — SiagaSOS portal

Dihasilkan dengan skill `ui-ux-pro-max` (gaya *Accessible & Ethical*, density tinggi, motion halus), lalu disesuaikan.
Token ada di [`apps/portal/src/styles.css`](../apps/portal/src/styles.css) (`:root`, mode gelap via `prefers-color-scheme`).

- **Font:** Plus Jakarta Sans (UI), JetBrains Mono (kunci API, koordinat, source_key).
- **Warna:** merah `--sos` *hanya* untuk keadaan darurat (laporan Baru, banner alarm, aksi destruktif). Aksi utama memakai `--ink` (slate gelap). Status laporan: Baru = merah, Diterima = amber, Ditangani = biru, Selesai = hijau, Batal/Alarm palsu = abu.
- **Status tidak hanya warna:** selalu ada label teks (badge) dan rail kiri di daftar.
- **Ikon:** Phosphor (`@phosphor-icons/react`), tanpa emoji.
- **Aksesibilitas:** focus ring 3 px, skip link, label pada semua input, error per field saat blur, `aria-live` untuk status realtime/draf, target sentuh ≥ 40 px, `prefers-reduced-motion` mematikan animasi.
- **Layout:** sidebar 232 px; di bawah 880 px jadi drawer. Dashboard: daftar 340–420 px + peta; di bawah 960 px peta di atas, panel detail jadi bottom sheet. Grid memakai `minmax(0, 1fr)` supaya konten lebar (tabel, kunci) tidak membuat halaman scroll horizontal.
- **Bunyi:** Web Audio (tanpa aset), butuh satu klik pengguna per sesi. Preferensi disimpan di localStorage.
