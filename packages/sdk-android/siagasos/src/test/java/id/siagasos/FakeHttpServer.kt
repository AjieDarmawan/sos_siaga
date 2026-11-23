package id.siagasos

import java.io.BufferedInputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import kotlin.concurrent.thread

/** Server HTTP/1.1 minimal untuk unit test (com.sun.net.httpserver tidak ada di classpath unit test Android). */
class FakeHttpServer(private val handler: (method: String, path: String, headers: Map<String, String>, body: String) -> Pair<Int, String>) {
    private val socket = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
    val port: Int get() = socket.localPort
    @Volatile private var running = true

    init {
        thread(isDaemon = true, name = "fake-http") {
            while (running) {
                val s = runCatching { socket.accept() }.getOrNull() ?: break
                thread(isDaemon = true) { serve(s) }
            }
        }
    }

    private fun serve(s: Socket) = s.use {
        val input = BufferedInputStream(s.getInputStream())
        fun line(): String {
            val sb = StringBuilder()
            while (true) {
                val c = input.read()
                if (c == -1 || c == '\n'.code) break
                if (c != '\r'.code) sb.append(c.toChar())
            }
            return sb.toString()
        }
        val (method, target) = line().split(" ").let { it[0] to it[1] }
        val headers = generateSequence { line().takeIf { l -> l.isNotEmpty() } }
            .associate { l -> l.substringBefore(":").trim().lowercase() to l.substringAfter(":").trim() }
        val len = headers["content-length"]?.toIntOrNull() ?: 0
        val body = ByteArray(len).also { b -> var r = 0; while (r < len) { val n = input.read(b, r, len - r); if (n < 0) break; r += n } }
        val (code, out) = handler(method, target.substringBefore("?"), headers, String(body, Charsets.UTF_8))
        val bytes = out.toByteArray()
        s.getOutputStream().apply {
            write("HTTP/1.1 $code X\r\nContent-Type: application/json\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n".toByteArray())
            write(bytes)
            flush()
        }
    }

    fun stop() { running = false; socket.close() }
}
