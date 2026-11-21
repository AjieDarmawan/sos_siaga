package id.siagasos

import org.json.JSONObject
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

internal class HttpTransport(private val baseUrl: String, private val headers: Map<String, String>) {

    fun json(method: String, path: String, body: JSONObject? = null, extra: Map<String, String> = emptyMap()): JSONObject {
        val c = (URL(baseUrl + path).openConnection() as HttpURLConnection)
        try {
            c.requestMethod = method
            c.connectTimeout = 15_000
            c.readTimeout = 20_000
            (headers + extra).forEach { (k, v) -> c.setRequestProperty(k, v) }
            if (body != null) {
                val bytes = body.toString().toByteArray(Charsets.UTF_8)
                c.doOutput = true
                c.setRequestProperty("Content-Type", "application/json")
                c.setFixedLengthStreamingMode(bytes.size)
                c.outputStream.use { it.write(bytes) }
            }
            val code = c.responseCode
            val text = (if (code >= 400) c.errorStream else c.inputStream)?.bufferedReader()?.use { it.readText() }.orEmpty()
            val data = if (text.isBlank()) JSONObject() else JSONObject(text)
            if (code >= 400) {
                val e = data.optJSONObject("error")
                throw SiagaSOSException(code, e?.optString("code").takeUnless { it.isNullOrEmpty() } ?: "http_error", e?.optString("message") ?: "HTTP $code")
            }
            return data
        } catch (e: IOException) {
            throw SiagaSOSException(0, "network_error", "Tidak ada koneksi: ${e.message}")
        } finally {
            c.disconnect()
        }
    }

    /** PUT langsung ke object storage (URL bertanda tangan). Tidak membawa X-SOS-Key. */
    fun putBytes(url: String, headers: Map<String, String>, bytes: ByteArray, progress: ((Double) -> Unit)?) {
        val c = URL(url).openConnection() as HttpURLConnection
        try {
            c.requestMethod = "PUT"
            c.doOutput = true
            c.connectTimeout = 15_000
            c.readTimeout = 120_000
            headers.forEach { (k, v) -> c.setRequestProperty(k, v) }
            c.setFixedLengthStreamingMode(bytes.size)
            c.outputStream.use { out ->
                var i = 0
                val chunk = 64 * 1024
                while (i < bytes.size) {
                    val n = minOf(chunk, bytes.size - i)
                    out.write(bytes, i, n)
                    i += n
                    progress?.invoke(i.toDouble() / bytes.size)
                }
            }
            val code = c.responseCode
            if (code >= 300) throw SiagaSOSException(code, "upload_failed", "Upload gagal ($code)")
        } catch (e: IOException) {
            throw SiagaSOSException(0, "network_error", "Upload gagal: ${e.message}")
        } finally {
            c.disconnect()
        }
    }
}
