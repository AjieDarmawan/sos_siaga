package id.siagasos.sample

import android.app.Application
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import id.siagasos.CapturedMedia
import id.siagasos.MediaCapture
import id.siagasos.SOSFloatingButton
import id.siagasos.SiagaSOS
import id.siagasos.SosSiren
import id.siagasos.SosUser

/** Contoh pemasangan: satu kali di Application → tombol SOS melayang di semua Activity. */
class SampleApp : Application() {
    lateinit var sos: SiagaSOS
    lateinit var fab: SOSFloatingButton

    override fun onCreate() {
        super.onCreate()
        sos = SiagaSOS.create(this, apiKey = BuildConfig.SOS_KEY, user = SosUser(ref = "sample-android", name = "Kurir Contoh"),
            baseUrl = BuildConfig.SOS_URL, sourceKey = "sample-android", sourceLabel = "Sample Android")
        fab = SOSFloatingButton.install(this, sos, SOSFloatingButton.Options().apply {
            siren = ToneSiren()
            // Kamera palsu: app sungguhan membuka kamera (CameraX / MediaStore) lalu memanggil done(...).
            onCapture = MediaCapture { _, kind, done ->
                Handler(Looper.getMainLooper()).postDelayed({
                    done(CapturedMedia(ByteArray(2048) { (it % 251).toByte() }, if (kind.name == "VIDEO") "video/mp4" else "image/jpeg", 5.0))
                }, 600)
            }
        })
    }
}

/** Sirene sederhana dari ToneGenerator (app sungguhan memutar audio sirene sendiri). */
class ToneSiren : SosSiren {
    private var tone: ToneGenerator? = null
    private var listener: ((Boolean) -> Unit)? = null
    override val isActive get() = tone != null
    override fun start() {
        if (tone != null) return
        tone = runCatching { ToneGenerator(AudioManager.STREAM_ALARM, 80).apply { startTone(ToneGenerator.TONE_CDMA_EMERGENCY_RINGBACK, 30_000) } }.getOrNull()
        listener?.invoke(isActive)
    }
    override fun stop() { tone?.release(); tone = null; listener?.invoke(false) }
    override fun setOnActiveChanged(listener: ((Boolean) -> Unit)?) { this.listener = listener }
}
