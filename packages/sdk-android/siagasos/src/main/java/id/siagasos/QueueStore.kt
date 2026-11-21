package id.siagasos

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/** Penyimpanan antrian laporan offline. */
interface QueueStore {
    fun load(): List<JSONObject>
    fun save(items: List<JSONObject>)
}

/** Default di Android: bertahan saat app ditutup / perangkat restart. */
class SharedPrefsQueueStore(context: Context, private val key: String) : QueueStore {
    private val prefs = context.applicationContext.getSharedPreferences("siagasos", Context.MODE_PRIVATE)

    @Synchronized
    override fun load(): List<JSONObject> = try {
        val a = JSONArray(prefs.getString(key, "[]"))
        List(a.length()) { a.getJSONObject(it) }
    } catch (_: Exception) {
        emptyList()
    }

    @Synchronized
    override fun save(items: List<JSONObject>) {
        // commit() (sinkron): laporan darurat tidak boleh hilang bila app langsung dimatikan
        prefs.edit().putString(key, JSONArray(items).toString()).commit()
    }
}

class MemoryQueueStore : QueueStore {
    private var items = listOf<JSONObject>()
    @Synchronized override fun load() = items.toList()
    @Synchronized override fun save(items: List<JSONObject>) { this.items = items.toList() }
}
