# Design system — SiagaSOS portal

Dihasilkan dengan skill `ui-ux-pro-max` (gaya *Accessible & Ethical*, density tinggi, motion halus), lalu disesuaikan.
Token ada di [`apps/portal/src/styles.css`](../apps/portal/src/styles.css) (`:root`, mode gelap via `prefers-color-scheme`).

- **Font:** Plus Jakarta Sans (UI), JetBrains Mono (kunci API, koordinat, source_key).
- **Warna:** merah `--sos` *hanya* untuk keadaan darurat (laporan Baru, banner alarm, aksi destruktif). Aksi utama memakai `--ink` (slate gelap). Status laporan: Baru = merah, Diterima = amber, Ditangani = biru, Selesai = hijau, Batal/Alarm palsu = abu.
- **Status tidak hanya warna:** selalu ada label teks (badge) dan rail kiri di daftar.
- **Ikon:** Phosphor (`@phosphor-icons/react`), tanpa emoji.
- **Aksesibilitas:** focus ring 3 px, skip link, label pada semua input, error per field saat blur, `aria-live` untuk status realtime/draf, target sentuh ≥ 40 px, `prefers-reduced-motion` mematikan animasi.
- **Layout:** sidebar 232 px; di bawah 880 px jadi drawer. Dashboard: daftar 340–420 px + peta; di bawah 960 px peta di atas, panel detail jadi bottom sheet. Grid memakai `minmax(0, 1fr)` supaya konten lebar (tabel, kunci) tidak membuat halaman scroll horizontal.
- **Soft UI Evolution (2026-11-23, skill `ui-ux-pro-max`):** radius 14/10 px, bayangan berlapis halus (`--shadow`, `--shadow-hover`, `--shadow-lg`), easing `--ease`, header tabel berlatar `--surface-2`, menu aktif = latar `--accent-soft` + garis kiri `--ink`, logo bergradien merah. Kartu yang bisa diklik naik bayangannya saat hover (tanpa menggeser layout).
- **Dashboard:** tinggi dikunci ke viewport (`.dash-shell`), daftar scroll di panelnya sendiri; tanpa ini peta ikut setinggi daftar dan titik tengahnya jatuh di luar layar. Ringkasan 4 angka (SOS baru, ditangani, pengaduan, median respons), filter jenis, ikon kategori per laporan. Banner merah & bunyi berulang **hanya SOS**; pengaduan berwarna biru/info tanpa alarm. Tombol peta "Tampilkan semua laporan".
- **Bunyi:** Web Audio (tanpa aset), butuh satu klik pengguna per sesi. Preferensi disimpan di localStorage.

## Landing & docs

- Hero gelap (`--night` #0a1020) dengan glow merah/biru, sisanya mengikuti token terang/gelap.
- Animasi: CSS + IntersectionObserver (tanpa GSAP) demi Lighthouse. Elemen hero memakai `.rise` (hanya transform, opacity tetap 1 supaya LCP tidak tertunda); bagian lain `.reveal` (fade + naik) dengan fallback scroll untuk loncatan anchor.
- Scene hero: loop 9 dtk (tahan tombol → sinyal → laporan masuk + alarm → diterima). `prefers-reduced-motion` menampilkan keadaan akhir statis.
- Tidak ada testimoni/logo klien fiktif; angka di landing berasal dari kode (SDK 3,2 KB, status ≤ 5 dtk, retry 24 jam).
- Panel admin memakai token yang sama, aksen ikon perisai merah di atas slate.
