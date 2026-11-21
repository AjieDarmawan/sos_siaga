package id.siagasos

import org.json.JSONObject

/** Status laporan dari sisi perangkat. [QUEUED] = belum terkirim (tidak ada sinyal). */
enum class SosStatus(val api: String) {
    QUEUED("queued"), OPEN("open"), ACKNOWLEDGED("acknowledged"), IN_PROGRESS("in_progress"),
    RESOLVED("resolved"), CANCELLED("cancelled"), FALSE_ALARM("false_alarm");

    val isTerminal: Boolean get() = this == RESOLVED || this == CANCELLED || this == FALSE_ALARM

    companion object {
        fun fromApi(s: String): SosStatus = entries.firstOrNull { it.api == s } ?: OPEN
    }
}

enum class SosMode { LIVE, TEST }

data class SosLocation(val lat: Double, val lng: Double, val accuracyM: Double? = null) {
    internal fun toJson(): JSONObject = JSONObject().put("lat", lat).put("lng", lng).apply { accuracyM?.let { put("accuracy_m", it) } }
}

/** [ref] = ID pengguna di sistem Anda (juga dipakai untuk rate limit per pengguna). */
data class SosUser(val ref: String? = null, val name: String? = null, val phone: String? = null) {
    internal fun toJson(): JSONObject = JSONObject().apply {
        ref?.let { put("ref", it) }; name?.let { put("name", it) }; phone?.let { put("phone", it) }
    }
}

/** Laporan dari sudut pandang perangkat. [id] null selama masih di antrian offline. */
data class ActiveReport(
    val localId: String,
    val id: String?,
    val status: SosStatus,
    val statusMessage: String?,
    val mode: SosMode,
    val category: String,
    val createdAtMs: Long,
)

data class SdkConfig(
    val appName: String,
    val categories: List<String>,
    val buttonText: String,
    val holdSeconds: Int,
    val recipientText: String,
    val fallbackPhone: String,
    val liveLocationIntervalS: Int,
) {
    internal companion object {
        fun from(j: JSONObject) = SdkConfig(
            appName = j.optString("app_name"),
            categories = j.optJSONArray("categories")?.let { a -> List(a.length()) { a.getString(it) } } ?: emptyList(),
            buttonText = j.optString("button_text", "SOS"),
            holdSeconds = j.optInt("hold_seconds", 3),
            recipientText = j.optString("recipient_text"),
            fallbackPhone = j.optString("fallback_phone", "110"),
            liveLocationIntervalS = j.optInt("live_location_interval_s", 15),
        )
    }
}

enum class MediaKind { IMAGE, VIDEO, AUDIO }

data class MediaPublic(val id: String, val kind: MediaKind, val contentType: String, val sizeBytes: Long, val ready: Boolean) {
    internal companion object {
        fun from(j: JSONObject) = MediaPublic(
            id = j.getString("id"),
            kind = MediaKind.valueOf(j.getString("kind").uppercase()),
            contentType = j.getString("content_type"),
            sizeBytes = j.getLong("size_bytes"),
            ready = j.optString("status") == "ready",
        )
    }
}

/** [status] = HTTP status, 0 = jaringan. */
class SiagaSOSException(val status: Int, val code: String, message: String) : Exception(message) {
    /** Gagal sementara (jaringan, 5xx, rate limit) → layak diulang. */
    val isRetryable: Boolean get() = status == 0 || status >= 500 || status == 429
    override fun toString() = "SiagaSOSException($status, $code): $message"
}

/** Callback hasil operasi async. Dipanggil di [SiagaSOS.Builder.callbackExecutor] (default: main thread). */
fun interface SosCallback<T> {
    fun onResult(result: Result<T>)
}

/** Event laporan. Semua method opsional. */
interface SosListener {
    fun onStatus(report: ActiveReport) {}
    fun onQueued(report: ActiveReport) {}
    fun onSent(report: ActiveReport) {}
    fun onError(error: SiagaSOSException) {}
}

/** Mengambil lokasi saat SOS ditekan & selama laporan aktif. Boleh mengembalikan null. Dipanggil di thread latar. */
fun interface LocationProvider {
    fun currentLocation(timeoutMs: Long): SosLocation?
}
