## Unreleased
- `SOSFloatingButton.captureKinds`: pilih jenis lampiran yang ditawarkan (mis. foto & video saja).
- `SOSFloatingButton`: menu jadi 4 tombol gradien bertumpuk (Kirim SOS, Telepon 110, Telepon 112, **Laporan pengaduan**).
- Laporan pengaduan: lembar form (jenis, uraian, foto opsional), `SiagaSOS.complain()`, `ReportKind`, `SdkConfig.complaintCategories`, `complaintCategoryLabel()`.
- Pengaduan dipolling 8× lebih jarang dan tanpa lokasi live.

## 0.1.0
- Rilis awal: trigger, antrian offline persisten, polling status, lokasi live, batal, lampiran foto/video/suara, widget `SOSButton`.
