package id.siagasos

import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

class SiagaSOSTest {
    data class Req(val method: String, val path: String, val headers: Map<String, String>, val body: String)

    private lateinit var server: FakeHttpServer
    private val reqs = Collections.synchronizedList(mutableListOf<Req>())
    private val failReports = AtomicInteger(0)
    @Volatile private var status = "open"
    private lateinit var base: String

    @Before fun start() {
        server = FakeHttpServer { method, path, h, body ->
            reqs.add(Req(method, path, h, body))
            when {
                path == "/v1/sdk/config" -> 200 to """{"app_name":"Demo","mode":"test","categories":["general"],"button_text":"SOS","hold_seconds":2,"recipient_text":"Ke satpam","fallback_phone":"110","live_location_interval_s":15}"""
                path == "/v1/sdk/reports" && failReports.getAndDecrement() > 0 -> 503 to """{"error":{"code":"unavailable","message":"down"}}"""
                path == "/v1/sdk/reports" && h["x-sos-bundle"] == "com.jahat.app" -> 403 to """{"error":{"code":"bundle_not_allowed","message":"no"}}"""
                path == "/v1/sdk/reports" -> 201 to """{"id":"rep-1","status":"open","mode":"test","category":"medis","status_message":null}"""
                path == "/v1/sdk/reports/rep-1" -> 200 to """{"id":"rep-1","status":"$status","status_message":null}"""
                path == "/v1/sdk/reports/rep-1/media" -> 201 to """{"media":{"id":"m-1"},"upload":{"method":"PUT","url":"$base/storage/put?sig=1","headers":{"Content-Type":"image/jpeg"}}}"""
                path == "/storage/put" -> 200 to ""
                path == "/v1/sdk/reports/rep-1/media/m-1/complete" -> 200 to """{"id":"m-1","kind":"image","content_type":"image/jpeg","size_bytes":3,"status":"ready"}"""
                else -> 404 to "{}"
            }
        }
        base = "http://127.0.0.1:${server.port}"
    }

    @After fun stop() = server.stop()

    private fun client(store: QueueStore = MemoryQueueStore(), bundle: String = "com.demo.app") =
        SiagaSOS.Builder("pk_test_abcdefghijklmnop", bundle).baseUrl(base).queueStore(store)
            .user(SosUser(ref = "u1", name = "Budi")).pollIntervalMs(50)
            .locationProvider { SosLocation(-6.2, 106.8, 10.0) }.build()

    @Test fun menolakKunciSalah() {
        try { SiagaSOS.Builder("sk_test_x", "a.b").build(); fail() } catch (e: SiagaSOSException) { assertEquals("invalid_api_key", e.code) }
    }

    @Test fun triggerMengirimHeaderMobileDanBody() {
        val sos = client()
        val r = sos.triggerBlocking("medis", "pingsan")
        assertEquals("rep-1", r.id)
        assertEquals(SosStatus.OPEN, r.status)
        val post = reqs.first { it.path == "/v1/sdk/reports" }
        assertEquals("pk_test_abcdefghijklmnop", post.headers["x-sos-key"])
        assertEquals("com.demo.app", post.headers["x-sos-bundle"])
        assertTrue(post.headers["idempotency-key"]!!.matches(Regex("^[0-9a-f-]{36}$")))
        val body = JSONObject(post.body)
        assertEquals(-6.2, body.getJSONObject("location").getDouble("lat"), 0.0)
        assertEquals("u1", body.getJSONObject("reporter").getString("ref"))
        assertEquals("android", body.getJSONObject("device").getString("platform"))
        sos.shutdown()
    }

    @Test fun offlineMasukAntrianLaluTerkirimDenganIdempotencyKeySama() {
        failReports.set(1)
        val store = MemoryQueueStore()
        val sos = client(store)
        val sent = CountDownLatch(1)
        val queued = AtomicInteger()
        sos.addListener(object : SosListener {
            override fun onQueued(report: ActiveReport) { queued.incrementAndGet() }
            override fun onSent(report: ActiveReport) { sent.countDown() }
        })
        val r = sos.triggerBlocking("kriminal")
        assertEquals(SosStatus.QUEUED, r.status)
        assertNull(r.id)
        assertEquals(1, store.load().size)
        assertTrue("terkirim ulang otomatis", sent.await(6, TimeUnit.SECONDS))
        assertEquals(1, queued.get())
        assertTrue(store.load().isEmpty())
        val keys = reqs.filter { it.path == "/v1/sdk/reports" }.map { it.headers["idempotency-key"] }.toSet()
        assertEquals("retry memakai idempotency key yang sama", 1, keys.size)
        sos.shutdown()
    }

    @Test fun errorPermanenTidakDiantrikan() {
        val store = MemoryQueueStore()
        val sos = client(store, bundle = "com.jahat.app")
        try { sos.triggerBlocking(); fail() } catch (e: SiagaSOSException) { assertEquals("bundle_not_allowed", e.code) }
        assertTrue(store.load().isEmpty())
        sos.shutdown()
    }

    @Test fun antrianBertahanAntarSesi() {
        failReports.set(99)
        val store = MemoryQueueStore()
        val a = client(store)
        a.triggerBlocking()
        a.shutdown()
        assertEquals(1, store.load().size)
        failReports.set(0)
        val b = client(store)
        val sent = CountDownLatch(1)
        b.addListener(object : SosListener { override fun onSent(report: ActiveReport) { sent.countDown() } })
        b.flushBlocking()
        assertTrue(sent.await(3, TimeUnit.SECONDS) || store.load().isEmpty())
        assertTrue(store.load().isEmpty())
        b.shutdown()
    }

    @Test fun pollingBerhentiDiStatusAkhir() {
        val sos = client()
        val seen = Collections.synchronizedList(mutableListOf<SosStatus>())
        sos.addListener(object : SosListener { override fun onStatus(report: ActiveReport) { seen.add(report.status) } })
        sos.triggerBlocking()
        status = "acknowledged"; Thread.sleep(200)
        status = "resolved"; Thread.sleep(200)
        val n = reqs.count { it.path == "/v1/sdk/reports/rep-1" }
        Thread.sleep(250)
        assertTrue(seen.toString(), seen.containsAll(listOf(SosStatus.OPEN, SosStatus.ACKNOWLEDGED, SosStatus.RESOLVED)))
        assertEquals("tidak polling lagi", n, reqs.count { it.path == "/v1/sdk/reports/rep-1" })
        sos.shutdown()
    }

    @Test fun attachMintaUrlPutTanpaKunciLaluComplete() {
        val sos = client()
        val r = sos.triggerBlocking()
        val progress = Collections.synchronizedList(mutableListOf<Double>())
        val m = sos.attachBlocking(r.localId, byteArrayOf(1, 2, 3), "image/jpeg", progress = { progress.add(it) })
        assertTrue(m.ready)
        assertEquals(MediaKind.IMAGE, m.kind)
        val put = reqs.first { it.path == "/storage/put" }
        assertNull("PUT ke storage tidak membawa X-SOS-Key", put.headers["x-sos-key"])
        assertEquals("image/jpeg", put.headers["content-type"])
        assertEquals(3, JSONObject(reqs.first { it.path.endsWith("/media") }.body).getInt("size_bytes"))
        Thread.sleep(50)
        assertEquals(1.0, progress.last(), 0.0)
        sos.shutdown()
    }

    @Test fun batalSaatMasihAntrian() {
        failReports.set(99)
        val store = MemoryQueueStore()
        val sos = client(store)
        val r = sos.triggerBlocking()
        val c = sos.cancelBlocking(r.localId)
        assertEquals(SosStatus.CANCELLED, c!!.status)
        assertTrue(store.load().isEmpty())
        sos.shutdown()
    }

    @Test fun callbackAsync() {
        val sos = client()
        val latch = CountDownLatch(1)
        var got: ActiveReport? = null
        sos.trigger("medis") { res -> got = res.getOrNull(); latch.countDown() }
        assertTrue(latch.await(3, TimeUnit.SECONDS))
        assertNotNull(got?.id)
        sos.shutdown()
    }
}
