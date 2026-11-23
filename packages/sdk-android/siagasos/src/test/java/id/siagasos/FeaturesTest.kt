package id.siagasos

import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import java.util.Collections

/** Fitur yang dipakai SOSFloatingButton: pengaduan, riwayat, detail, catatan, Nomor Darurat. */
class FeaturesTest {
    data class Req(val method: String, val path: String, val body: String)

    private lateinit var server: FakeHttpServer
    private val reqs = Collections.synchronizedList(mutableListOf<Req>())
    @Volatile private var status = "open"
    @Volatile private var remoteContacts = "[]"
    @Volatile private var contactsDown = false

    @Before fun start() {
        server = FakeHttpServer { method, path, _, body ->
            reqs.add(Req(method, path, body))
            when {
                path == "/v1/sdk/reports" -> {
                    val kind = JSONObject(body).optString("kind", "sos")
                    201 to """{"id":"${if (kind == "pengaduan") "pg-1" else "rep-1"}","status":"open","kind":"$kind","status_message":null}"""
                }
                path == "/v1/sdk/reports/rep-1" || path == "/v1/sdk/reports/pg-1" ->
                    200 to """{"id":"rep-1","status":"$status","status_message":"Petugas menuju lokasi","acknowledged_at":"2026-11-23T03:00:05.123456Z","resolved_at":null}"""
                path == "/v1/sdk/reports/rep-1/notes" -> 201 to """{"id":"rep-1","status":"open"}"""
                path == "/v1/sdk/reports/rep-1/detail" -> 200 to """{"id":"rep-1","kind":"sos","category":"general","status":"acknowledged",
                    "status_message":"Petugas menuju lokasi","message":null,"location":{"lat":-6.2,"lng":106.8,"accuracy_m":12},
                    "created_at":"2026-11-23T10:00:00+07:00","acknowledged_at":"2026-11-23T03:00:05Z","resolved_at":null,
                    "timeline":[{"type":"created","actor":"Anda","to_status":"open","note":null,"created_at":"2026-11-23T03:00:00Z"},
                                {"type":"whatsapp","actor":"Sistem","to_status":null,"note":"Terkirim ke 2 penerima","created_at":"2026-11-23T03:00:01Z"}],
                    "media":[{"id":"m1","kind":"video","content_type":"video/mp4","uploaded_by":"reporter","url":"https://s3/x?sig","duration_s":5}]}"""
                path.startsWith("/v1/sdk/contacts") && contactsDown -> 503 to """{"error":{"code":"down","message":"down"}}"""
                path.startsWith("/v1/sdk/contacts") && method == "PUT" -> 200 to """{"ok":true}"""
                path.startsWith("/v1/sdk/contacts") -> 200 to """{"contacts":$remoteContacts}"""
                else -> 404 to "{}"
            }
        }
    }

    @After fun stop() = server.stop()

    private fun client(history: QueueStore = MemoryQueueStore(), contacts: QueueStore = MemoryQueueStore(), sync: QueueStore = MemoryQueueStore()) =
        SiagaSOS.Builder("pk_test_abcdefghijklmnop", "com.demo.app").baseUrl("http://127.0.0.1:${server.port}")
            .user(SosUser(ref = "kasir-1", name = "Kasir Satu")).sourceKey("kios-a").sourceLabel("Kios A").pollIntervalMs(60_000)
            .historyStore(history).contactsStore(contacts, sync).build()

    private fun lastReportBody() = JSONObject(reqs.last { it.path == "/v1/sdk/reports" }.body)

    @Test fun pengaduanWajibUraianDanTanpaKontakDarurat() {
        val sos = client()
        try { sos.complainBlocking("kebisingan", "abc"); fail() } catch (e: SiagaSOSException) { assertEquals("validation_failed", e.code) }
        sos.setEmergencyContactsBlocking(listOf(EmergencyContact("Adik", "0812 1111 2222")))
        val r = sos.complainBlocking("kebisingan", "  Hajatan sampai jam 2 pagi  ")
        assertEquals(ReportKind.PENGADUAN, r.kind)
        val body = lastReportBody()
        assertEquals("pengaduan", body.getString("kind"))
        assertEquals("Hajatan sampai jam 2 pagi", body.getString("message"))
        assertFalse("pengaduan tidak membawa kontak darurat", body.has("emergency_contacts"))
        assertEquals("Kios A", body.getString("source_label"))
        sos.shutdown()
    }

    @Test fun sosMembawaKontakAktifSaja() {
        val sos = client()
        assertTrue(sos.setEmergencyContactsBlocking(listOf(
            EmergencyContact("Satpam", "+62 813-0000-1111", role = "Satpam"),
            EmergencyContact("Ibu", "081300002222", active = false),
        )))
        sos.triggerBlocking()
        val ec = lastReportBody().getJSONArray("emergency_contacts")
        assertEquals(1, ec.length())
        assertEquals("Satpam (Satpam)", ec.getJSONObject(0).getString("name"))
        assertEquals("6281300001111", ec.getJSONObject(0).getString("phone"))
        sos.shutdown()
    }

    @Test fun nomorDaruratDivalidasiDanDisinkron() {
        val sos = client()
        listOf(
            listOf(EmergencyContact("A", "123")),
            listOf(EmergencyContact(" ", "081211112222")),
            listOf(EmergencyContact("A", "081211112222"), EmergencyContact("B", "+6281211112222")),
            List(6) { EmergencyContact("K$it", "08121111000$it") },
        ).forEach { bad -> try { sos.setEmergencyContactsBlocking(bad); fail(bad.toString()) } catch (_: IllegalArgumentException) {} }
        assertTrue(sos.setEmergencyContactsBlocking(listOf(EmergencyContact(" Adik ", "0812 1111 2222", role = " "))))
        assertEquals(listOf(EmergencyContact("Adik", "6281211112222")), sos.emergencyContacts())
        val put = JSONObject(reqs.last { it.method == "PUT" }.body)
        assertEquals("kasir-1", put.getJSONObject("reporter").getString("ref"))
        assertEquals("kios-a", put.getString("source_key"))
        assertEquals("6281211112222", put.getJSONArray("contacts").getJSONObject(0).getString("phone"))
        sos.shutdown()
    }

    @Test fun nomorDaruratOfflineTersimpanLaluTersinkronNanti() {
        contactsDown = true
        val contacts = MemoryQueueStore(); val sync = MemoryQueueStore()
        val a = client(contacts = contacts, sync = sync)
        assertFalse(a.setEmergencyContactsBlocking(listOf(EmergencyContact("Adik", "081211112222"))))
        assertEquals(1, a.emergencyContacts().size)
        a.shutdown()
        contactsDown = false
        val b = client(contacts = contacts, sync = sync)
        assertTrue(b.syncEmergencyContactsBlocking())
        assertTrue(reqs.any { it.method == "PUT" && it.body.contains("6281211112222") })
        b.shutdown()
    }

    @Test fun perangkatBaruMemulihkanNomorDariServer() {
        remoteContacts = """[{"name":"Satpam","role":null,"phone":"6281300001111","active":true}]"""
        val sos = client()
        assertTrue(sos.syncEmergencyContactsBlocking())
        assertEquals(listOf(EmergencyContact("Satpam", "6281300001111")), sos.emergencyContacts())
        sos.shutdown()
    }

    @Test fun riwayatTercatatDanDiperbarui() {
        val history = MemoryQueueStore()
        val sos = client(history = history)
        sos.triggerBlocking()
        sos.complainBlocking("parkir_liar", "Parkir liar di depan toko")
        var list = sos.historyBlocking(refresh = false)
        assertEquals(listOf("pg-1", "rep-1"), list.map { it.id })
        assertEquals("Parkir liar di depan toko", list[0].message)
        status = "acknowledged"
        list = sos.historyBlocking()
        val sosRec = list.first { it.id == "rep-1" }
        assertEquals(SosStatus.ACKNOWLEDGED, sosRec.status)
        assertEquals("Petugas menuju lokasi", sosRec.statusMessage)
        assertEquals(Iso.parse("2026-11-23T03:00:05.123Z"), sosRec.acknowledgedAtMs)
        // tersimpan: sesi berikutnya melihat status terbaru tanpa jaringan
        val again = client(history = history).historyBlocking(refresh = false)
        assertEquals(SosStatus.ACKNOWLEDGED, again.first { it.id == "rep-1" }.status)
        sos.shutdown()
    }

    @Test fun detailDanCatatan() {
        val sos = client()
        val r = sos.triggerBlocking()
        sos.addNoteBlocking(r.localId, "  Orang mencurigakan  ")
        assertEquals("Orang mencurigakan", JSONObject(reqs.last { it.path.endsWith("/notes") }.body).getString("note"))
        val d = sos.reportDetailBlocking("rep-1")
        assertEquals(SosStatus.ACKNOWLEDGED, d.status)
        assertEquals(106.8, d.location!!.lng, 0.0)
        assertEquals(Iso.parse("2026-11-23T03:00:00Z"), d.createdAtMs) // +07:00 dinormalisasi
        assertEquals(listOf("created", "whatsapp"), d.timeline.map { it.type })
        assertNull(d.timeline[1].toStatus)
        assertEquals(MediaKind.VIDEO, d.media[0].kind)
        assertEquals(5.0, d.media[0].durationS!!, 0.0)
        sos.shutdown()
    }

    @Test fun nomorWhatsApp() {
        assertEquals("6281211112222", toWhatsAppNumber("0812-1111-2222"))
        assertEquals("6281211112222", toWhatsAppNumber("81211112222"))
        assertNull(toWhatsAppNumber("+1 415 555 0100"))
        assertEquals("Parkir liar", complaintCategoryLabel("parkir_liar"))
        assertEquals("Banjir lokal", complaintCategoryLabel("banjir_lokal"))
    }
}
