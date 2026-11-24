package id.siagasos

import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import org.json.JSONObject
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CopyOnWriteArraySet
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * Klien SiagaSOS untuk Android. Satu instance per aplikasi; panggil [shutdown] saat logout.
 *
 * ```kotlin
 * val sos = SiagaSOS.create(context, apiKey = "pk_test_...", user = SosUser(ref = uid, name = nama))
 * sos.addListener(object : SosListener { override fun onStatus(report: ActiveReport) { render(report) } })
 * sos.trigger("kriminal") { result -> result.onSuccess { r -> ... } }
 * sos.attach(report.localId, bytes, "image/jpeg") { ... }
 * ```
 * Kontrak lintas platform: docs/SDK_PROTOCOL.md.
 */
class SiagaSOS private constructor(b: Builder) {
    val apiKey: String = b.apiKey
    /** Package name aplikasi; harus terdaftar di allowed_bundle_ids app di portal. */
    val bundleId: String = b.bundleId
    val mode: SosMode
    private val sourceKey = b.sourceKey
    private val sourceLabel = b.sourceLabel
    val user: SosUser? = b.user
    private val liveLocation = b.liveLocation
    private val pollIntervalMs = b.pollIntervalMs
    private val locationTimeoutMs = b.locationTimeoutMs
    private val location = b.locationProvider
    private val queue: QueueStore = b.queueStore ?: MemoryQueueStore()
    private val historyStore: QueueStore = b.historyStore ?: MemoryQueueStore()
    private val contactsStore: QueueStore = b.contactsStore ?: MemoryQueueStore()
    private val contactsSyncStore: QueueStore = b.contactsSyncStore ?: MemoryQueueStore()
    private val historyLock = Any()
    private val contactsLock = Any()
    private val callbacks: Executor = b.callbackExecutor ?: Executor { it.run() }
    private val http = HttpTransport(b.baseUrl.trimEnd('/'), mapOf("X-SOS-Key" to b.apiKey, "X-SOS-Bundle" to b.bundleId))

    private val io = Executors.newCachedThreadPool { r -> Thread(r, "siagasos-io").apply { isDaemon = true } }
    private val timers = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "siagasos-timer").apply { isDaemon = true } }
    private val reports = ConcurrentHashMap<String, ActiveReport>()
    private val pollers = ConcurrentHashMap<String, ScheduledFuture<*>>()
    private val locators = ConcurrentHashMap<String, ScheduledFuture<*>>()
    private val listeners = CopyOnWriteArraySet<SosListener>()
    private val queueLock = Any()
    @Volatile private var config: SdkConfig? = null
    @Volatile private var retry: ScheduledFuture<*>? = null
    @Volatile private var retryDelayMs = 2_000L
    @Volatile private var flushing = false
    @Volatile private var closed = false

    init {
        val m = Regex("^pk_(live|test)_").find(apiKey)
            ?: throw SiagaSOSException(0, "invalid_api_key", "apiKey harus publishable key (pk_live_... / pk_test_...)")
        mode = if (m.groupValues[1] == "live") SosMode.LIVE else SosMode.TEST
        io.execute { flushBlocking() } // kirim sisa antrian dari sesi sebelumnya
        // Nomor Darurat: kirim perubahan yang belum tersinkron, atau pulihkan dari server di perangkat baru.
        io.execute { runCatching { syncEmergencyContactsBlocking() } }
    }

    val activeReports: List<ActiveReport> get() = reports.values.filter { !it.status.isTerminal }

    fun addListener(l: SosListener) { listeners.add(l) }
    fun removeListener(l: SosListener) { listeners.remove(l) }

    private fun emit(block: (SosListener) -> Unit) = listeners.forEach { l -> callbacks.execute { runCatching { block(l) } } }
    private fun <T> async(cb: SosCallback<T>?, work: () -> T) = io.execute {
        val r = runCatching(work).recoverCatching { e -> throw (e as? SiagaSOSException ?: SiagaSOSException(0, "unknown", e.toString())) }
        cb?.let { callbacks.execute { it.onResult(r) } }
    }

    // ------------------------------------------------------------------ config
    /** Konfigurasi tombol dari portal (di-cache). Blocking: panggil dari thread latar. */
    fun getConfigBlocking(): SdkConfig = config ?: SdkConfig.from(http.json("GET", "/v1/sdk/config")).also { config = it }
    fun getConfig(callback: SosCallback<SdkConfig>) = async(callback) { getConfigBlocking() }

    // ------------------------------------------------------------------ trigger + antrian offline
    /**
     * Kirim SOS. Bila offline, laporan masuk antrian persisten (status [SosStatus.QUEUED]) dan dikirim otomatis.
     * Error permanen (kunci/bundle salah) dikembalikan sebagai kegagalan.
     */
    fun trigger(category: String = "general", message: String? = null, metadata: Map<String, Any?>? = null, callback: SosCallback<ActiveReport>? = null) =
        async(callback) { triggerBlocking(category, message, metadata) }

    fun triggerBlocking(category: String = "general", message: String? = null, metadata: Map<String, Any?>? = null): ActiveReport =
        submit(ReportKind.SOS, category, message, metadata)

    /**
     * Kirim laporan pengaduan (non-darurat). [message] wajib (min. 5 karakter). Antrian offline sama dengan [trigger],
     * tetapi tanpa lokasi live dan tanpa WhatsApp darurat. Lokasi saat dikirim tetap disertakan bila tersedia.
     */
    fun complain(category: String, message: String, metadata: Map<String, Any?>? = null, callback: SosCallback<ActiveReport>? = null) =
        async(callback) { complainBlocking(category, message, metadata) }

    fun complainBlocking(category: String, message: String, metadata: Map<String, Any?>? = null): ActiveReport {
        if (message.trim().length < 5) throw SiagaSOSException(422, "validation_failed", "Uraian pengaduan minimal 5 karakter")
        return submit(ReportKind.PENGADUAN, category, message.trim(), metadata)
    }

    private fun submit(kind: ReportKind, category: String, message: String?, metadata: Map<String, Any?>?): ActiveReport {
        val loc = runCatching { location?.currentLocation(locationTimeoutMs) }.getOrNull()
        // Kontak darurat hanya untuk SOS. Gagal baca → SOS tetap jalan tanpa kontak.
        val contacts = if (kind == ReportKind.SOS) runCatching { emergencyContacts() }.getOrDefault(emptyList())
            .filter { it.active }.take(MAX_ACTIVE_EMERGENCY_CONTACTS) else emptyList()
        val now = System.currentTimeMillis()
        val body = JSONObject().put("category", category)
            .put("device", JSONObject().put("platform", "android").put("sdk_version", "android-${BuildConfig.SDK_VERSION}").put("os", "Android ${Build.VERSION.RELEASE ?: ""}".trim()))
            .put("client_created_at", Iso.format(now))
        if (kind == ReportKind.PENGADUAN) body.put("kind", kind.api)
        message?.let { body.put("message", it) }
        sourceKey?.let { body.put("source_key", it) }
        if (sourceKey != null && !sourceLabel.isNullOrBlank()) body.put("source_label", sourceLabel.trim())
        loc?.let { body.put("location", it.toJson()) }
        user?.let { body.put("reporter", it.toJson()) }
        metadata?.let { body.put("metadata", JSONObject(metadata)) }
        if (contacts.isNotEmpty()) body.put("emergency_contacts", org.json.JSONArray(contacts.map { it.toReportJson() }))
        val item = JSONObject().put("localId", uuid()).put("idem", uuid()).put("createdAt", now).put("body", body)
        val queued = ActiveReport(item.getString("localId"), null, SosStatus.QUEUED, "Menunggu sinyal, laporan akan dikirim otomatis.", mode, category, now, kind)
        reports[queued.localId] = queued
        synchronized(queueLock) { queue.save(queue.load() + item) }
        return try {
            send(item)
        } catch (e: SiagaSOSException) {
            if (!e.isRetryable) {
                removeFromQueue(queued.localId)
                reports.remove(queued.localId)
                emit { it.onError(e) }
                throw e
            }
            emit { it.onQueued(queued) }
            emit { it.onStatus(queued) }
            scheduleRetry()
            queued
        }
    }

    private fun send(item: JSONObject): ActiveReport {
        val data = http.json("POST", "/v1/sdk/reports", item.getJSONObject("body"), mapOf("Idempotency-Key" to item.getString("idem")))
        val localId = item.getString("localId")
        removeFromQueue(localId)
        val body = item.getJSONObject("body")
        val r = ActiveReport(localId, data.getString("id"), SosStatus.fromApi(data.getString("status")), data.optStringOrNull("status_message"),
            mode, body.getString("category"), reports[localId]?.createdAtMs ?: item.optLong("createdAt"), kindOf(item))
        reports[localId] = r
        remember(ReportRecord(r.id!!, r.kind, r.category, r.status, r.createdAtMs, body.optStringOrNull("message"), r.statusMessage))
        emit { it.onSent(r) }
        emit { it.onStatus(r) }
        track(r)
        return r
    }

    private fun removeFromQueue(localId: String) = synchronized(queueLock) { queue.save(queue.load().filter { it.optString("localId") != localId }) }

    /** Kirim ulang antrian sekarang. Otomatis dengan backoff; panggil juga saat app kembali online / foreground. */
    fun flush() = io.execute { flushBlocking() }

    fun flushBlocking() {
        if (flushing || closed) return
        flushing = true
        try {
            for (item in synchronized(queueLock) { queue.load() }) {
                val localId = item.getString("localId")
                reports.putIfAbsent(localId, ActiveReport(localId, null, SosStatus.QUEUED, null, mode,
                    item.getJSONObject("body").optString("category", "general"), item.optLong("createdAt"), kindOf(item)))
                try {
                    send(item)
                    retryDelayMs = 2_000
                } catch (e: SiagaSOSException) {
                    if (e.isRetryable) { scheduleRetry(); return }
                    removeFromQueue(localId)
                    reports.remove(localId)
                    emit { it.onError(e) }
                }
            }
        } finally {
            flushing = false
        }
    }

    private fun scheduleRetry() {
        if (closed || retry?.isDone == false) return
        retry = timers.schedule({ io.execute { flushBlocking() } }, retryDelayMs, TimeUnit.MILLISECONDS)
        retryDelayMs = minOf(retryDelayMs * 2, 60_000)
    }

    // ------------------------------------------------------------------ status + lokasi live
    private fun track(r: ActiveReport) {
        if (r.status.isTerminal || closed) return
        // Pengaduan bisa terbuka berhari-hari: polling jarang, tanpa lokasi live.
        val complaint = r.kind == ReportKind.PENGADUAN
        val every = if (complaint) pollIntervalMs * 8 else pollIntervalMs
        pollers.computeIfAbsent(r.localId) {
            timers.scheduleWithFixedDelay({ io.execute { poll(r.localId) } }, every, every, TimeUnit.MILLISECONDS)
        }
        if (!complaint && liveLocation && location != null && !locators.containsKey(r.localId)) io.execute {
            val interval = runCatching { getConfigBlocking().liveLocationIntervalS }.getOrDefault(15).toLong()
            if (!closed) locators.computeIfAbsent(r.localId) {
                timers.scheduleWithFixedDelay({ io.execute { sendLocation(r.localId) } }, interval, interval, TimeUnit.SECONDS)
            }
        }
    }

    private fun poll(localId: String) {
        val id = reports[localId]?.id ?: return
        runCatching { update(localId, http.json("GET", "/v1/sdk/reports/$id")) }
    }

    private fun sendLocation(localId: String) {
        val id = reports[localId]?.id ?: return
        val loc = runCatching { location?.currentLocation(locationTimeoutMs) }.getOrNull() ?: return
        runCatching {
            val res = http.json("POST", "/v1/sdk/reports/$id/locations", loc.toJson().put("recorded_at", Iso.format(System.currentTimeMillis())))
            if (!res.optBoolean("accepted", true)) locators.remove(localId)?.cancel(false)
        }
    }

    private fun update(localId: String, data: JSONObject): ActiveReport {
        val cur = reports.getValue(localId)
        val next = cur.copy(id = data.optString("id").ifEmpty { cur.id }, status = SosStatus.fromApi(data.getString("status")),
            statusMessage = data.optStringOrNull("status_message"))
        reports[localId] = next
        if (next.status != cur.status || next.statusMessage != cur.statusMessage) emit { it.onStatus(next) }
        if (next.status.isTerminal) stop(localId)
        return next
    }

    private fun stop(localId: String) {
        pollers.remove(localId)?.cancel(false)
        locators.remove(localId)?.cancel(false)
    }

    private fun find(idOrLocalId: String) = reports[idOrLocalId] ?: reports.values.firstOrNull { it.id == idOrLocalId }

    // ------------------------------------------------------------------ batal
    /** Batalkan (salah tekan). Hanya saat status `open`; gagal dengan `cannot_cancel` bila sudah diterima petugas. */
    fun cancel(idOrLocalId: String, reason: String? = null, callback: SosCallback<ActiveReport?>? = null) = async(callback) { cancelBlocking(idOrLocalId, reason) }

    fun cancelBlocking(idOrLocalId: String, reason: String? = null): ActiveReport? {
        val entry = find(idOrLocalId)
        if (entry != null && entry.id == null) {
            removeFromQueue(entry.localId)
            val c = entry.copy(status = SosStatus.CANCELLED, statusMessage = "Laporan dibatalkan.")
            reports[entry.localId] = c
            emit { it.onStatus(c) }
            return c
        }
        val data = http.json("POST", "/v1/sdk/reports/${entry?.id ?: idOrLocalId}/cancel", JSONObject().apply { reason?.let { put("reason", it) } })
        return entry?.let { update(it.localId, data) }
    }

    /** Status laporan dari server (mentah). */
    fun getReportBlocking(id: String): JSONObject = http.json("GET", "/v1/sdk/reports/$id")

    /** Detail laporan untuk halaman riwayat: uraian, lokasi, riwayat status (termasuk catatan petugas), lampiran. */
    fun reportDetail(id: String, callback: SosCallback<ReportDetail>) = async(callback) { reportDetailBlocking(id) }
    fun reportDetailBlocking(id: String): ReportDetail = ReportDetail.from(http.json("GET", "/v1/sdk/reports/$id/detail"))

    /**
     * Catatan pelapor untuk petugas (mis. keterangan rekaman TKP), tampil di timeline dashboard.
     * Bila laporan masih di antrian offline, menunggu sampai terkirim (maks. [waitTimeoutMs]).
     */
    fun addNote(idOrLocalId: String, note: String, waitTimeoutMs: Long = 120_000, callback: SosCallback<Unit>? = null) =
        async(callback) { addNoteBlocking(idOrLocalId, note, waitTimeoutMs) }
    fun addNoteBlocking(idOrLocalId: String, note: String, waitTimeoutMs: Long = 120_000) {
        val id = waitForServerId(idOrLocalId, waitTimeoutMs)
        http.json("POST", "/v1/sdk/reports/$id/notes", JSONObject().put("note", note.trim()))
    }

    // ------------------------------------------------------------------ riwayat
    private fun remember(rec: ReportRecord) = runCatching {
        synchronized(historyLock) {
            val items = historyStore.load().filter { it.optString("id") != rec.id }
            historyStore.save((listOf(rec.toJson()) + items).take(HISTORY_LIMIT))
        }
    } // riwayat tidak boleh mengganggu jalur SOS

    /**
     * Laporan (SOS & pengaduan) yang pernah terkirim dari perangkat ini oleh [user], terbaru dulu.
     * [refresh] = ambil status terbaru dari server untuk yang belum selesai; gagal jaringan → status tersimpan.
     */
    fun history(refresh: Boolean = true, callback: SosCallback<List<ReportRecord>>) = async(callback) { historyBlocking(refresh) }
    fun historyBlocking(refresh: Boolean = true): List<ReportRecord> {
        val list = runCatching { synchronized(historyLock) { historyStore.load() }.map { ReportRecord.from(it) } }.getOrElse { return emptyList() }
        if (!refresh || list.isEmpty()) return list
        val fresh = list.map { r -> if (r.status.isTerminal) r else runCatching { r.withServer(getReportBlocking(r.id)) }.getOrDefault(r) }
        runCatching {
            synchronized(historyLock) {
                // Gabung dengan isi terbaru (laporan baru bisa masuk selama refresh berjalan).
                val byId = fresh.associateBy { it.id }
                historyStore.save(historyStore.load().map { j -> byId[j.optString("id")]?.toJson() ?: j })
            }
        }
        return fresh
    }

    // ------------------------------------------------------------------ Nomor Darurat
    /** Nomor Darurat pribadi pengguna ini (per perangkat + [user]). Yang aktif ikut dikabari WhatsApp setiap SOS. */
    fun emergencyContacts(): List<EmergencyContact> =
        runCatching { synchronized(contactsLock) { contactsStore.load() }.map { EmergencyContact.from(it) }.filter { it.phone.isNotEmpty() } }
            .getOrDefault(emptyList())

    /**
     * Simpan seluruh daftar (ganti total). Nomor dinormalisasi ke 62xx. [IllegalArgumentException] bila nomor tidak valid,
     * nama kosong, nomor ganda, > [MAX_EMERGENCY_CONTACTS] kontak, atau > [MAX_ACTIVE_EMERGENCY_CONTACTS] aktif.
     * Selalu tersimpan di perangkat dulu, lalu disinkronkan ke server. Hasil: true = sudah di server; false = belum
     * (offline / tanpa [SosUser.ref]), dicoba lagi otomatis.
     */
    fun setEmergencyContacts(contacts: List<EmergencyContact>, callback: SosCallback<Boolean>? = null) =
        async(callback) { setEmergencyContactsBlocking(contacts) }

    fun setEmergencyContactsBlocking(contacts: List<EmergencyContact>): Boolean {
        require(contacts.size <= MAX_EMERGENCY_CONTACTS) { "Maksimal $MAX_EMERGENCY_CONTACTS nomor darurat" }
        require(contacts.count { it.active } <= MAX_ACTIVE_EMERGENCY_CONTACTS) { "Maksimal $MAX_ACTIVE_EMERGENCY_CONTACTS nomor darurat aktif" }
        val out = mutableListOf<EmergencyContact>()
        for (c in contacts) {
            val n = toWhatsAppNumber(c.phone) ?: throw IllegalArgumentException("Nomor WhatsApp tidak valid: ${c.phone}")
            require(c.name.isNotBlank()) { "Nama kontak wajib diisi" }
            require(out.none { it.phone == n }) { "Nomor +$n sudah ada di daftar" }
            out += EmergencyContact(c.name.trim(), n, c.role?.trim()?.ifEmpty { null }, c.active)
        }
        synchronized(contactsLock) {
            contactsStore.save(out.map { it.toJson() })
            contactsSyncStore.save(listOf(JSONObject().put("state", "dirty").put("v", uuid())))
        }
        return runCatching { syncEmergencyContactsBlocking() }.getOrDefault(false)
    }

    /**
     * Samakan Nomor Darurat perangkat dengan server: ada perubahan lokal → PUT (ganti total); belum pernah sinkron dan
     * lokal kosong → ambil dari server (perangkat baru). true bila sudah sama. Butuh [SosUser.ref].
     */
    fun syncEmergencyContactsBlocking(): Boolean {
        val ref = user?.ref
        if (ref.isNullOrEmpty() || closed) return false
        val snapshot = synchronized(contactsLock) { contactsSyncStore.load() }.firstOrNull()
        val state = snapshot?.optString("state")
        if (state == "synced") return true
        val local = emergencyContacts()
        if (state == "dirty" || local.isNotEmpty()) {
            http.json("PUT", "/v1/sdk/contacts", JSONObject()
                .put("reporter", JSONObject().put("ref", ref).apply { user.name?.let { put("name", it) } })
                .apply { sourceKey?.let { put("source_key", it) } }
                .put("contacts", org.json.JSONArray(local.map { it.toJson() })))
        } else {
            val data = http.json("GET", "/v1/sdk/contacts?reporter_ref=" + java.net.URLEncoder.encode(ref, "UTF-8"))
            val arr = data.optJSONArray("contacts")
            val remote = if (arr == null) emptyList() else List(arr.length()) { EmergencyContact.from(arr.getJSONObject(it)) }
            synchronized(contactsLock) {
                // Pengguna bisa saja sempat mengisi daftar selama request berjalan: jangan timpa.
                if (remote.isNotEmpty() && contactsStore.load().isEmpty()) contactsStore.save(remote.map { it.toJson() })
            }
        }
        synchronized(contactsLock) {
            // Ada simpanan baru selama request (versi berubah) → biarkan dirty supaya dikirim lagi.
            if (contactsSyncStore.load().firstOrNull()?.toString() == snapshot?.toString()) {
                contactsSyncStore.save(listOf(JSONObject().put("state", "synced")))
            }
        }
        return true
    }

    // ------------------------------------------------------------------ lampiran
    /**
     * Lampirkan foto/video/suara. File diunggah langsung ke storage (URL bertanda tangan), lalu tampil realtime di dashboard.
     * Bila laporan masih di antrian offline, menunggu sampai terkirim (maks. [waitTimeoutMs]).
     */
    fun attach(idOrLocalId: String, bytes: ByteArray, contentType: String, durationS: Double? = null,
               progress: ((Double) -> Unit)? = null, waitTimeoutMs: Long = 120_000, callback: SosCallback<MediaPublic>? = null) =
        async(callback) { attachBlocking(idOrLocalId, bytes, contentType, durationS, progress, waitTimeoutMs) }

    fun attachBlocking(idOrLocalId: String, bytes: ByteArray, contentType: String, durationS: Double? = null,
                       progress: ((Double) -> Unit)? = null, waitTimeoutMs: Long = 120_000): MediaPublic {
        val id = waitForServerId(idOrLocalId, waitTimeoutMs)
        val out = http.json("POST", "/v1/sdk/reports/$id/media",
            JSONObject().put("content_type", contentType).put("size_bytes", bytes.size).apply { durationS?.let { put("duration_s", it) } })
        val up = out.getJSONObject("upload")
        val h = up.getJSONObject("headers").let { j -> j.keys().asSequence().associateWith { j.getString(it) } }
        http.putBytes(up.getString("url"), h, bytes) { r -> progress?.let { p -> callbacks.execute { p(r) } } }
        return MediaPublic.from(http.json("POST", "/v1/sdk/reports/$id/media/${out.getJSONObject("media").getString("id")}/complete"))
    }

    private fun waitForServerId(idOrLocalId: String, timeoutMs: Long): String {
        val r = find(idOrLocalId) ?: return idOrLocalId // id server dari sesi lain
        r.id?.let { return it }
        val latch = CountDownLatch(1)
        val l = object : SosListener { override fun onSent(report: ActiveReport) { if (report.localId == r.localId) latch.countDown() } }
        listeners.add(l)
        try {
            reports[r.localId]?.id?.let { return it }
            if (!latch.await(timeoutMs, TimeUnit.MILLISECONDS)) throw SiagaSOSException(0, "not_sent", "Laporan belum terkirim; lampiran dibatalkan")
        } finally {
            listeners.remove(l)
        }
        return reports.getValue(r.localId).id!!
    }

    /** Hentikan polling, lokasi live, dan retry. Antrian tetap tersimpan untuk sesi berikutnya. */
    fun shutdown() {
        closed = true
        retry?.cancel(false)
        (pollers.keys + locators.keys).forEach { stop(it) }
        timers.shutdownNow()
        io.shutdown()
        listeners.clear()
    }

    class Builder(internal val apiKey: String, internal val bundleId: String) {
        internal var sourceKey: String? = null
        internal var sourceLabel: String? = null
        internal var historyStore: QueueStore? = null
        internal var contactsStore: QueueStore? = null
        internal var contactsSyncStore: QueueStore? = null
        internal var user: SosUser? = null
        internal var baseUrl = "https://api.siagasos.id"
        internal var liveLocation = true
        internal var pollIntervalMs = 4_000L
        internal var locationTimeoutMs = 8_000L
        internal var locationProvider: LocationProvider? = null
        internal var queueStore: QueueStore? = null
        internal var callbackExecutor: Executor? = null

        fun sourceKey(v: String?) = apply { sourceKey = v }
        /** Nama tampilan [sourceKey] (mis. nama kios); dipakai di pesan WA SOS. */
        fun sourceLabel(v: String?) = apply { sourceLabel = v }
        /** Riwayat laporan perangkat ([history]). */
        fun historyStore(v: QueueStore) = apply { historyStore = v }
        /** Nomor Darurat + status sinkronnya. */
        fun contactsStore(contacts: QueueStore, sync: QueueStore) = apply { contactsStore = contacts; contactsSyncStore = sync }
        fun user(v: SosUser?) = apply { user = v }
        fun baseUrl(v: String) = apply { baseUrl = v }
        fun liveLocation(v: Boolean) = apply { liveLocation = v }
        fun pollIntervalMs(v: Long) = apply { pollIntervalMs = v }
        fun locationTimeoutMs(v: Long) = apply { locationTimeoutMs = v }
        fun locationProvider(v: LocationProvider?) = apply { locationProvider = v }
        fun queueStore(v: QueueStore) = apply { queueStore = v }
        /** Thread untuk callback & listener. [SiagaSOS.create] memakai main thread. */
        fun callbackExecutor(v: Executor) = apply { callbackExecutor = v }
        fun build() = SiagaSOS(this)
    }

    companion object {
        const val SDK_VERSION = BuildConfig.SDK_VERSION

        /** Default Android: antrian di SharedPreferences, lokasi via LocationManager, callback di main thread, bundle = package name. */
        @JvmStatic @JvmOverloads
        fun create(context: Context, apiKey: String, user: SosUser? = null, sourceKey: String? = null,
                   baseUrl: String = "https://api.siagasos.id", bundleId: String = context.packageName, sourceLabel: String? = null): SiagaSOS {
            val main = Handler(Looper.getMainLooper())
            // Riwayat & Nomor Darurat per pengguna: kasir lain yang login di perangkat sama tidak melihat milik orang lain.
            val per = "${apiKey.take(16)}.${user?.ref ?: "-"}"
            return Builder(apiKey, bundleId).user(user).sourceKey(sourceKey).sourceLabel(sourceLabel).baseUrl(baseUrl)
                .queueStore(SharedPrefsQueueStore(context, "queue.${apiKey.take(16)}"))
                .historyStore(SharedPrefsQueueStore(context, "history.$per"))
                .contactsStore(SharedPrefsQueueStore(context, "contacts.$per"), SharedPrefsQueueStore(context, "contacts_sync.$per"))
                .locationProvider(AndroidLocationProvider(context))
                .callbackExecutor { main.post(it) }
                .build()
        }

        private const val HISTORY_LIMIT = 50
        private fun uuid() = UUID.randomUUID().toString()
        private fun kindOf(item: JSONObject) = ReportKind.fromApi(item.getJSONObject("body").optStringOrNull("kind"))
    }
}
