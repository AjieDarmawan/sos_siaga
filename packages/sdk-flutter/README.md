# siagasos (Flutter)

Tombol darurat SiagaSOS untuk aplikasi Flutter (Android & iOS): kirim SOS dengan lokasi, antrian offline yang bertahan saat app ditutup, status realtime ke pelapor, lokasi live, dan lampiran foto/video/suara. Kontrak lintas platform: [`docs/SDK_PROTOCOL.md`](../../docs/SDK_PROTOCOL.md).

## Pasang

```yaml
dependencies:
  siagasos:
    git: { url: git@gitlab.com:technosoft-indo-prima/sos_siaga.git, path: packages/sdk-flutter }
```

Di portal SiagaSOS → **App & kunci API**, daftarkan package name / bundle id aplikasi Anda (mis. `com.perusahaan.app`) di **Bundle id Android / iOS**.

## Pakai

```dart
import 'package:siagasos/siagasos.dart';

final sos = SiagaSOS(
  apiKey: 'pk_test_...',                 // ganti pk_live_ setelah perusahaan disetujui
  bundleId: 'com.perusahaan.app',        // wajib, harus terdaftar di app
  sourceKey: 'armada-android',
  user: SosUser(ref: user.id, name: user.name, phone: user.phone),
  locationProvider: () async {           // contoh dengan paket geolocator
    final p = await Geolocator.getCurrentPosition();
    return SosLocation(lat: p.latitude, lng: p.longitude, accuracyM: p.accuracy);
  },
);

// Widget siap pakai: tahan N detik (dari portal), cincin progres, status, batal
SOSButton(client: sos, category: 'kriminal', onCallFallback: (tel) => launchUrl(Uri.parse('tel:$tel')));

// Atau UI sendiri
final report = await sos.trigger(category: 'medis', message: 'Rekan pingsan');
sos.status.listen((r) => print('${r.status} ${r.statusMessage}'));
sos.queued.listen((_) => showSnack('Tidak ada sinyal. Laporan dikirim otomatis.'));
await sos.cancel(report.localId, reason: 'Salah tekan');
```

### Lampiran foto / video / suara

SDK tidak memaksa paket kamera/mikrofon tertentu; kirim byte file dari paket pilihan Anda.

```dart
// foto atau video (image_picker)
final x = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 80);
await sos.attach(report.localId, await x!.readAsBytes(), contentType: 'image/jpeg',
    onProgress: (r) => setState(() => progress = r));

final v = await ImagePicker().pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 30));
await sos.attach(report.localId, await v!.readAsBytes(), contentType: 'video/mp4');

// suara (record)
await recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
final file = await recorder.stop();
await sos.attach(report.localId, await File(file!).readAsBytes(), contentType: 'audio/mp4', durationS: secs.toDouble());
```

Batas: foto 10 MB, video 60 MB, suara 15 MB, 10 lampiran per laporan. Bila laporan masih di antrian offline, `attach` menunggu sampai terkirim.

### Izin

- Android `AndroidManifest.xml`: `INTERNET`, `ACCESS_FINE_LOCATION` (+ `CAMERA`, `RECORD_AUDIO` bila memakai lampiran).
- iOS `Info.plist`: `NSLocationWhenInUseUsageDescription` (+ `NSCameraUsageDescription`, `NSMicrophoneUsageDescription`).
- Jelaskan ke pengguna sebelum izin pertama bahwa lokasi & rekaman dibagikan ke tim responder (UU PDP).

Panggil `sos.flush()` saat app kembali ke foreground / online untuk mempercepat pengiriman antrian, dan `sos.dispose()` saat logout.

## Test

```bash
flutter test                                              # unit + widget (server palsu)
SIAGASOS_IT=1 flutter test test/integration_test.dart     # terhadap API lokal + MinIO (pnpm dev:api, pnpm seed:demo)
```
