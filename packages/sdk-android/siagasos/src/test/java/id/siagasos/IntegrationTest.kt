package id.siagasos

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.net.HttpURLConnection
import java.net.URL
import java.util.Base64

/** Terhadap API lokal + MinIO sungguhan. SIAGASOS_IT=1 ./gradlew :siagasos:testDebugUnitTest (butuh pnpm dev:api + seed:demo). */
class IntegrationTest {
    private val api = "http://localhost:4000"

    private fun http(method: String, url: String, body: String? = null, token: String? = null): Pair<Int, String> {
        val c = URL(url).openConnection() as HttpURLConnection
        c.requestMethod = method
        token?.let { c.setRequestProperty("Authorization", "Bearer $it") }
        if (body != null) { c.doOutput = true; c.setRequestProperty("Content-Type", "application/json"); c.outputStream.use { it.write(body.toByteArray()) } }
        val code = c.responseCode
        return code to ((if (code >= 400) c.errorStream else c.inputStream)?.bufferedReader()?.readText() ?: "")
    }

    @Test fun triggerLampiranDanTampilDiPortal() {
        assumeTrue("set SIAGASOS_IT=1", System.getenv("SIAGASOS_IT") == "1")
        val token = JSONObject(http("POST", "$api/portal/auth/login", """{"email":"demo@siagasos.test","password":"demo12345"}""").second).getString("token")
        val apps = JSONObject(http("GET", "$api/portal/apps", token = token).second).getJSONArray("data")
        val android = (0 until apps.length()).map { apps.getJSONObject(it) }.first { it.getString("name").contains("Android") }
        val keys = android.getJSONArray("keys")
        val pk = (0 until keys.length()).map { keys.getJSONObject(it) }
            .first { it.getString("kind") == "publishable" && it.getString("mode") == "live" && it.getBoolean("active") }.getString("key")

        val sos = SiagaSOS.Builder(pk, "id.demosiaga.kurir").baseUrl(api).queueStore(MemoryQueueStore())
            .user(SosUser(ref = "android-it", name = "Uji Android SDK")).locationProvider { SosLocation(-6.2297, 106.8295, 9.0) }.build()
        assertTrue(sos.getConfigBlocking().appName.contains("Android"))
        val r = sos.triggerBlocking("kecelakaan", "Integrasi Android SDK")
        assertNotNull(r.id)
        val png = Base64.getDecoder().decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")
        assertTrue(sos.attachBlocking(r.localId, png, "image/png").ready)

        val detail = JSONObject(http("GET", "$api/portal/reports/${r.id}", token = token).second)
        val media = detail.getJSONArray("media")
        assertEquals(1, media.length())
        assertEquals("android", detail.getJSONObject("device").getString("platform"))
        assertEquals(200, (URL(media.getJSONObject(0).getString("url")).openConnection() as HttpURLConnection).responseCode)
        assertEquals(SosStatus.CANCELLED, sos.cancelBlocking(r.localId, "uji selesai")!!.status)
        sos.shutdown()
    }
}
