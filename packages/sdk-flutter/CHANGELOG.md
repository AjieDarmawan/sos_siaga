## Unreleased
- Pengaduan disamakan dengan Lapor Keamanan tata-warga: foto (maks. 5) & video (maks. 2) bukti wajib minimal 1, jenis, judul, kronologi, lokasi & waktu kejadian, ciri pelaku, dan saksi. Dikirim lewat `ComplaintDetails` (`complain(details: ...)`).
- `SOSFloatingButton.complaintLabel`: judul menu & form pengaduan (mis. 'Pengaduan 110'). Default 'Pengaduan'.
- `SOSFloatingButton.captureKinds`: pilih jenis lampiran yang ditawarkan (mis. foto & video saja).
- `SOSFloatingButton`: menu jadi 4 tombol gradien bertumpuk (Kirim SOS, Telepon 110, Telepon 112, **Laporan pengaduan**).
- Laporan pengaduan: lembar form (jenis, uraian, foto opsional), `SiagaSOS.complain()`, `ReportKind`, `SdkConfig.complaintCategories`, `complaintCategoryLabel()`.
- Pengaduan dipolling 8× lebih jarang dan tanpa lokasi live.

## 0.1.0
- Rilis awal: trigger, antrian offline persisten, polling status, lokasi live, batal, lampiran foto/video/suara, widget `SOSButton`.
