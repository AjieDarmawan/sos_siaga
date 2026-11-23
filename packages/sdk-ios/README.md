# SiagaSOS iOS (Swift)

Tombol darurat SiagaSOS untuk aplikasi iOS (iOS 15+, juga macOS 12 untuk uji). Swift Package tanpa dependency, `async/await`. Kontrak lintas platform: [`docs/SDK_PROTOCOL.md`](../../docs/SDK_PROTOCOL.md).

## Pasang

Xcode → File → Add Package Dependencies → URL repo, path `packages/sdk-ios` (sementara dari repo; rilis SPM menyusul).
Daftarkan **bundle identifier** aplikasi Anda di portal → App & kunci API → Bundle id Android / iOS.

## Pakai

```swift
import SiagaSOS

let sos = try SiagaSOS(apiKey: "pk_test_...",            // pk_live_ setelah perusahaan disetujui
                       user: SosUser(ref: user.id, name: user.name, phone: user.phone),
                       locationProvider: CoreLocationProvider())

// SwiftUI: tahan N detik (dari portal), status, batal
SOSButton(client: sos, category: "kriminal")

// Atau UI sendiri
let r = try await sos.trigger(category: "medis", message: "Rekan pingsan")
let id = sos.addListener(SosListener(onStatus: { r in render(r.status, r.statusMessage) },
                                     onQueued: { _ in toast("Tidak ada sinyal. Laporan dikirim otomatis.") }))
_ = try await sos.cancel(r.localId, reason: "Salah tekan")

// Lampiran foto / video / suara
try await sos.attach(r.localId, data: jpegData, contentType: "image/jpeg")
```

- `bundleId` default `Bundle.main.bundleIdentifier`; antrian offline di `UserDefaults` (bertahan saat app ditutup).
- `Info.plist`: `NSLocationWhenInUseUsageDescription` (+ `NSCameraUsageDescription`, `NSMicrophoneUsageDescription` untuk lampiran). Jelaskan ke pengguna bahwa data dibagikan ke tim responder (UU PDP).
- Panggil `await sos.flush()` saat app kembali ke foreground, `sos.shutdown()` saat logout.
- Belum ada: tombol melayang dan menu **Laporan pengaduan** (sudah ada di Flutter, lihat `packages/sdk-flutter`).

## Test

```bash
swift run siagasos-selftest                                 # unit (URLProtocol palsu)
SIAGASOS_IT=1 swift run siagasos-selftest                   # + integrasi ke API lokal & MinIO
```
