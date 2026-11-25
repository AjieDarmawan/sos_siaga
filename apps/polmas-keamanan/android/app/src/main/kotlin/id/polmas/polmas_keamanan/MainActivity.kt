package id.polmas.polmas_keamanan

import android.app.NotificationChannel
import android.app.NotificationManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createSosChannel()
    }

    /**
     * Kanal notifikasi SOS: prioritas tertinggi, suara sirene res/raw/sos_siren (sama dengan commerceOS POS), getar,
     * tampil di layar kunci. Server mengirim push FCM ke kanal `polmas_sos_v2` (apps/api/src/lib/fcm.ts, PK_FCM) supaya
     * sirene tetap bunyi walau app ditutup. Suara kanal tidak bisa diubah setelah dibuat; ganti id kanal bila suaranya
     * diganti (v1 `polmas_sos` = sirene lama, dihapus di sini).
     */
    private fun createSosChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel("polmas_sos") != null) nm.deleteNotificationChannel("polmas_sos")
        if (nm.getNotificationChannel("polmas_sos_v2") != null) return
        val sound = Uri.parse("android.resource://$packageName/raw/sos_siren")
        val attrs = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val ch = NotificationChannel("polmas_sos_v2", "Panggilan SOS", NotificationManager.IMPORTANCE_HIGH).apply {
            description = "SOS dari toko, warga, kantor, sekolah, atau komunitas yang mencantumkan nomor Anda"
            setSound(sound, attrs)
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 800, 400, 800, 400, 800)
            lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            setBypassDnd(true)
        }
        nm.createNotificationChannel(ch)
    }
}
