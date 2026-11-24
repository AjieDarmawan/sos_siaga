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

/** SOS darurat atau pengaduan (non-darurat, tanpa lokasi live dan tanpa WhatsApp darurat). */
enum class ReportKind(val api: String) {
    SOS("sos"), PENGADUAN("pengaduan");
    companion object { fun fromApi(s: String?): ReportKind = if (s == "pengaduan") PENGADUAN else SOS }
}

/** Label kategori pengaduan bawaan (sama dengan SDK Flutter & portal). */
val complaintCategoryLabels: Map<String, String> = linkedMapOf(
    "ketertiban" to "Gangguan ketertiban",
    "kebisingan" to "Kebisingan",
    "parkir_liar" to "Parkir liar",
    "pungli" to "Pungutan liar",
    "kehilangan" to "Kehilangan barang/dokumen",
    "patroli" to "Minta patroli",
    "lainnya" to "Lainnya",
)

fun complaintCategoryLabel(slug: String): String =
    complaintCategoryLabels[slug] ?: slug.replace('_', ' ').replaceFirstChar { it.uppercase() }

/** Maks. kontak aktif yang dikabari per SOS (sama dengan server). */
const val MAX_ACTIVE_EMERGENCY_CONTACTS = 5
/** Maks. kontak tersimpan (aktif + nonaktif). */
const val MAX_EMERGENCY_CONTACTS = 10

/** 08xx / +62xx / 62xx / 8xx → 62xx. Null bila bukan nomor Indonesia yang masuk akal (sama dengan server). */
fun toWhatsAppNumber(phone: String): String? {
    var d = phone.filter { it.isDigit() }
    if (d.startsWith("0")) d = "62" + d.substring(1) else if (d.startsWith("8")) d = "62$d"
    return if (Regex("^62[0-9]{8,13}$").matches(d)) d else null
}

/**
 * Nomor Darurat pribadi pelapor: yang [active] dikabari WhatsApp setiap SOS. Nomor di sini juga yang boleh
 * login sebagai satpam (responder). [phone] ternormalisasi 62xx.
 */
data class EmergencyContact(val name: String, val phone: String, val role: String? = null, val active: Boolean = true) {
    internal fun toJson(): JSONObject = JSONObject().put("name", name).put("phone", phone).put("active", active).apply { role?.let { put("role", it) } }
    internal fun toReportJson(): JSONObject = JSONObject().put("name", if (role.isNullOrBlank()) name else "$name ($role)").put("phone", phone)
    internal companion object {
        fun from(j: JSONObject) = EmergencyContact(
            name = j.optString("name"),
            phone = j.optString("phone"),
            role = j.optString("role").trim().ifEmpty { null }.takeUnless { j.isNull("role") },
            active = j.optBoolean("active", true),
        )
    }
}

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
    val kind: ReportKind = ReportKind.SOS,
)

data class SdkConfig(
    val appName: String,
    val categories: List<String>,
    val complaintCategories: List<String>,
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
            complaintCategories = j.optJSONArray("complaint_categories")?.let { a -> List(a.length()) { a.getString(it) } }
                ?: complaintCategoryLabels.keys.toList(),
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

/** Laporan di riwayat perangkat ([SiagaSOS.history]): yang pernah terkirim dari perangkat ini oleh pengguna yang sama. */
data class ReportRecord(
    val id: String,
    val kind: ReportKind,
    val category: String,
    val status: SosStatus,
    val createdAtMs: Long,
    val message: String? = null,
    val statusMessage: String? = null,
    val acknowledgedAtMs: Long? = null,
    val resolvedAtMs: Long? = null,
) {
    /** Gabungkan jawaban `GET /v1/sdk/reports/:id`. */
    internal fun withServer(j: JSONObject) = copy(
        status = SosStatus.fromApi(j.optString("status", "open")),
        statusMessage = j.optStringOrNull("status_message"),
        acknowledgedAtMs = Iso.parse(j.optStringOrNull("acknowledged_at")),
        resolvedAtMs = Iso.parse(j.optStringOrNull("resolved_at")),
    )

    internal fun toJson(): JSONObject = JSONObject().put("id", id).put("kind", kind.api).put("category", category)
        .put("status", status.api).put("created_at", Iso.format(createdAtMs)).apply {
            message?.let { put("message", it) }
            statusMessage?.let { put("status_message", it) }
            acknowledgedAtMs?.let { put("acknowledged_at", Iso.format(it)) }
            resolvedAtMs?.let { put("resolved_at", Iso.format(it)) }
        }

    internal companion object {
        fun from(j: JSONObject) = ReportRecord(
            id = j.getString("id"),
            kind = ReportKind.fromApi(j.optStringOrNull("kind")),
            category = j.optString("category"),
            status = SosStatus.fromApi(j.optString("status", "open")),
            createdAtMs = Iso.parse(j.optStringOrNull("created_at")) ?: System.currentTimeMillis(),
            message = j.optStringOrNull("message"),
            statusMessage = j.optStringOrNull("status_message"),
            acknowledgedAtMs = Iso.parse(j.optStringOrNull("acknowledged_at")),
            resolvedAtMs = Iso.parse(j.optStringOrNull("resolved_at")),
        )
    }
}

/** Satu baris riwayat status di [ReportDetail]. [type]: created | status_changed | cancelled | note | media | whatsapp. */
data class ReportTimelineEntry(val type: String, val actor: String, val createdAtMs: Long, val toStatus: SosStatus? = null, val note: String? = null)

/** Lampiran di detail laporan. [url] = URL baca sementara (± 15 menit). [uploadedBy]: reporter | user | server. */
data class ReportMediaItem(val id: String, val kind: MediaKind, val contentType: String, val uploadedBy: String, val url: String?, val durationS: Double?)

/** Detail laporan untuk halaman riwayat ([SiagaSOS.reportDetail]). */
data class ReportDetail(
    val id: String,
    val kind: ReportKind,
    val category: String,
    val status: SosStatus,
    val createdAtMs: Long,
    val statusMessage: String?,
    val message: String?,
    val location: SosLocation?,
    val acknowledgedAtMs: Long?,
    val resolvedAtMs: Long?,
    val timeline: List<ReportTimelineEntry>,
    val media: List<ReportMediaItem>,
) {
    internal companion object {
        fun from(j: JSONObject): ReportDetail {
            val loc = j.optJSONObject("location")
            val tl = j.optJSONArray("timeline")
            val md = j.optJSONArray("media")
            return ReportDetail(
                id = j.getString("id"),
                kind = ReportKind.fromApi(j.optStringOrNull("kind")),
                category = j.optString("category"),
                status = SosStatus.fromApi(j.optString("status", "open")),
                createdAtMs = Iso.parse(j.optStringOrNull("created_at")) ?: System.currentTimeMillis(),
                statusMessage = j.optStringOrNull("status_message"),
                message = j.optStringOrNull("message"),
                location = loc?.let { SosLocation(it.getDouble("lat"), it.getDouble("lng"), if (it.isNull("accuracy_m")) null else it.optDouble("accuracy_m")) },
                acknowledgedAtMs = Iso.parse(j.optStringOrNull("acknowledged_at")),
                resolvedAtMs = Iso.parse(j.optStringOrNull("resolved_at")),
                timeline = if (tl == null) emptyList() else List(tl.length()) { i ->
                    val e = tl.getJSONObject(i)
                    ReportTimelineEntry(e.optString("type"), e.optString("actor", "Sistem"),
                        Iso.parse(e.optStringOrNull("created_at")) ?: 0L, e.optStringOrNull("to_status")?.let { SosStatus.fromApi(it) }, e.optStringOrNull("note"))
                },
                media = if (md == null) emptyList() else List(md.length()) { i ->
                    val m = md.getJSONObject(i)
                    ReportMediaItem(m.getString("id"), runCatching { MediaKind.valueOf(m.getString("kind").uppercase()) }.getOrDefault(MediaKind.IMAGE),
                        m.optString("content_type"), m.optString("uploaded_by", "reporter"), m.optStringOrNull("url"),
                        if (m.isNull("duration_s")) null else m.optDouble("duration_s"))
                },
            )
        }
    }
}

internal fun JSONObject.optStringOrNull(key: String): String? = if (!has(key) || isNull(key)) null else optString(key).ifEmpty { null }

/** ISO-8601 tanpa java.time (minSdk 21). */
internal object Iso {
    private fun fmt(pattern: String) = java.text.SimpleDateFormat(pattern, java.util.Locale.US).apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
    fun format(ms: Long): String = fmt("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'").format(java.util.Date(ms))
    fun parse(s: String?): Long? {
        if (s.isNullOrEmpty()) return null
        // Normalisasi: pecahan detik 0–9 digit → 3 digit, zona Z / +07:00 → +0000 / +0700.
        val m = Regex("^(\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2})(?:\\.(\\d+))?(Z|[+-]\\d{2}:?\\d{2})?$").find(s.trim()) ?: return null
        val frac = (m.groupValues[2] + "000").take(3)
        val zone = m.groupValues[3].let { z -> if (z.isEmpty() || z == "Z") "+0000" else z.replace(":", "") }
        return runCatching { fmt("yyyy-MM-dd'T'HH:mm:ss.SSSZ").parse("${m.groupValues[1]}.$frac$zone")?.time }.getOrNull()
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
