package id.siagasos

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Looper
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Lokasi lewat LocationManager bawaan (tanpa Google Play Services). Mengembalikan null bila izin belum diberikan
 * atau GPS tidak memberi posisi dalam batas waktu; laporan tetap terkirim tanpa lokasi.
 */
class AndroidLocationProvider(context: Context) : LocationProvider {
    private val ctx = context.applicationContext
    private val lm = ctx.getSystemService(Context.LOCATION_SERVICE) as LocationManager

    private fun granted() = ctx.checkCallingOrSelfPermission(android.Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
        ctx.checkCallingOrSelfPermission(android.Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    @SuppressLint("MissingPermission")
    override fun currentLocation(timeoutMs: Long): SosLocation? {
        if (!granted()) return null
        val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER).filter { runCatching { lm.isProviderEnabled(it) }.getOrDefault(false) }
        // posisi terakhir yang masih segar (≤ 60 dtk) langsung dipakai
        providers.mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }
            .filter { System.currentTimeMillis() - it.time < 60_000 }
            .minByOrNull { it.accuracy }?.let { return it.toSos() }
        if (providers.isEmpty()) return null
        val latch = CountDownLatch(1)
        var found: Location? = null
        val listener = object : LocationListener {
            override fun onLocationChanged(location: Location) { found = location; latch.countDown() }
            @Deprecated("Deprecated in Java") override fun onStatusChanged(p: String?, s: Int, e: android.os.Bundle?) {}
            override fun onProviderEnabled(provider: String) {}
            override fun onProviderDisabled(provider: String) {}
        }
        providers.forEach { p -> runCatching { lm.requestLocationUpdates(p, 0L, 0f, listener, Looper.getMainLooper()) } }
        latch.await(timeoutMs, TimeUnit.MILLISECONDS)
        lm.removeUpdates(listener)
        return (found ?: providers.mapNotNull { runCatching { lm.getLastKnownLocation(it) }.getOrNull() }.minByOrNull { it.accuracy })?.toSos()
    }

    private fun Location.toSos() = SosLocation(latitude, longitude, if (hasAccuracy()) accuracy.toDouble() else null)

    internal companion object {
        val sdkInt get() = Build.VERSION.SDK_INT
    }
}
