# SiagaSOS Android (Kotlin / Java)

Tombol darurat SiagaSOS untuk aplikasi Android native. **Tanpa dependency runtime** (HttpURLConnection + org.json bawaan), minSdk 21, AAR ±73 KB. Kontrak lintas platform: [`docs/SDK_PROTOCOL.md`](../../docs/SDK_PROTOCOL.md).

## Pasang

```kotlin
// settings.gradle.kts (sementara dari repo; Maven Central menyusul)
includeBuild("path/ke/sos_siaga/packages/sdk-android")
// app/build.gradle.kts
implementation("id.siagasos:siagasos-android:0.1.0")
```

Atau `./gradlew :siagasos:assembleRelease` lalu salin `siagasos/build/outputs/aar/siagasos-release.aar`.
Daftarkan **package name** aplikasi Anda di portal → App & kunci API → Bundle id Android / iOS.

## Pakai

```kotlin
val sos = SiagaSOS.create(context, apiKey = "pk_test_...",
    user = SosUser(ref = user.id, name = user.name, phone = user.phone), sourceKey = "armada-android")

// Tombol siap pakai (XML: <id.siagasos.SOSButtonView android:layout_width="200dp" android:layout_height="200dp"/>)
binding.sosButton.bind(sos, category = "kriminal") { result ->
    result.onFailure { showError(it.message) }
}

// Atau UI sendiri
sos.addListener(object : SosListener {
    override fun onStatus(report: ActiveReport) = render(report.status, report.statusMessage)
    override fun onQueued(report: ActiveReport) = toast("Tidak ada sinyal. Laporan dikirim otomatis.")
})
sos.trigger("medis", "Rekan pingsan") { it.onSuccess { r -> current = r } }
sos.cancel(current.localId, "Salah tekan")

// Lampiran foto / video / suara (byte dari kamera, MediaRecorder, dll.)
sos.attach(current.localId, bytes, "image/jpeg", progress = { p -> bar.progress = (p * 100).toInt() }) { ... }
sos.attach(current.localId, File(audioPath).readBytes(), "audio/mp4", durationS = 12.0)
```

- `SiagaSOS.create` memakai: antrian di SharedPreferences (bertahan saat app ditutup), lokasi via `LocationManager` (tanpa Google Play Services), callback di main thread, bundle = `context.packageName`.
- Kustom: `SiagaSOS.Builder(apiKey, bundleId).locationProvider { timeoutMs -> ... }.queueStore(...).callbackExecutor(...).build()` (mis. pakai FusedLocationProvider).
- Setiap operasi punya versi `*Blocking` untuk dipanggil dari thread latar / coroutine (`withContext(Dispatchers.IO) { sos.triggerBlocking("medis") }`).
- Minta izin `ACCESS_FINE_LOCATION` (dan `CAMERA` / `RECORD_AUDIO` untuk lampiran) di app Anda dengan penjelasan bahwa data dibagikan ke tim responder (UU PDP). Tanpa izin lokasi laporan tetap terkirim.
- Panggil `sos.flush()` saat koneksi kembali / app ke foreground, dan `sos.shutdown()` saat logout.

- Belum ada: tombol melayang dan menu **Laporan pengaduan** (sudah ada di Flutter, lihat `packages/sdk-flutter`).

## Tombol SOS melayang (`SOSFloatingButton`)

Pasang sekali di `Application.onCreate`, tombol tampil di semua Activity (gaya EWS tata-warga):

```kotlin
class App : Application() {
    override fun onCreate() {
        super.onCreate()
        val sos = SiagaSOS.create(this, apiKey = "pk_live_...", user = SosUser(ref = uid, name = nama),
            sourceKey = "kios-12", sourceLabel = "Kios 12")
        SOSFloatingButton.install(this, sos, SOSFloatingButton.Options().apply {
            onCapture = MediaCapture { activity, kind, done -> /* buka kamera, lalu */ done(CapturedMedia(bytes, "video/mp4", 5.0)) }
            siren = mySiren          // opsional, implementasi SosSiren (suara diputar app)
            hideIn = { it is LoginActivity }
        })
    }
}
```

- Ketuk tombol bulat → **Kirim SOS** (sekali ketuk; `holdSeconds = 3` untuk tahan dulu), **Telepon 110** (`fallback_phone` portal) & **112** (default buka dialer), **Laporan** → Pengaduan / Riwayat laporan (+ detail, batal salah tekan) / Nomor darurat.
- Setelah SOS terkirim: sirene (tombol jadi **SENYAP**) dan ajakan **Rekam kondisi TKP?** → `onCapture` video → catatan → dikirim ke petugas.
- Bisa digeser, menempel ke tepi, posisi diingat; area kosong tidak menangkap sentuhan. Tanpa AndroidX, mengikuti mode gelap.
- API di baliknya juga bisa dipakai langsung: `complain()`, `history()`, `reportDetail()`, `addNote()`, `setEmergencyContacts()`.

Contoh app: modul `sample` (bundle `id.demosiaga.kurir`). Isi `local.properties`: `siagasos.key=pk_test_...` dan `siagasos.url=http://10.0.2.2:4000` (emulator) atau `http://127.0.0.1:4000` + `adb reverse tcp:4000 tcp:4000` (HP via USB), lalu `./gradlew :sample:installDebug`.

## Test

```bash
./gradlew :siagasos:testDebugUnitTest                         # unit (server palsu)
SIAGASOS_IT=1 ./gradlew :siagasos:testDebugUnitTest           # + integrasi ke API lokal & MinIO (pnpm dev:api, pnpm seed:demo)
```
