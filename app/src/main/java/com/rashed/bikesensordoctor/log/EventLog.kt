package com.rashed.bikesensordoctor.log

import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

enum class EventType { SCAN, CONNECTION, SERVICE, READ, NOTIFY, WRITE, ERROR, TEST, INFO }

data class LogEntry(
    val seq: Long,
    val timestampMs: Long,
    val type: EventType,
    val device: String,
    val uuid: String,
    val hex: String,
    val note: String,
) {
    val timeText: String get() = TIME_FMT.format(Date(timestampMs))

    companion object {
        val TIME_FMT = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)
    }
}

/** In-memory ring log (last [MAX] entries) with per-type and per-UUID counters and CSV/JSON export. */
class EventLog {
    companion object { const val MAX = 5000 }

    private var seq = 0L
    private val _entries = MutableStateFlow<List<LogEntry>>(emptyList())
    val entries: StateFlow<List<LogEntry>> = _entries

    private val _counts = MutableStateFlow<Map<String, Int>>(emptyMap())
    /** Count of NOTIFY events per characteristic UUID string. */
    val notifyCounts: StateFlow<Map<String, Int>> = _counts

    @Synchronized
    fun add(type: EventType, device: String = "", uuid: String = "", bytes: ByteArray? = null, note: String = "") {
        val hex = bytes?.joinToString(" ") { String.format("%02X", it) } ?: ""
        val e = LogEntry(++seq, System.currentTimeMillis(), type, device, uuid, hex, note)
        _entries.update { old -> (old + e).takeLast(MAX) }
        if (type == EventType.NOTIFY && uuid.isNotEmpty()) {
            _counts.update { it + (uuid to ((it[uuid] ?: 0) + 1)) }
        }
    }

    @Synchronized
    fun clear() {
        _entries.value = emptyList()
        _counts.value = emptyMap()
    }

    fun toCsv(): String {
        val sb = StringBuilder("seq,timestamp_ms,time,type,device,uuid,hex,note\n")
        for (e in _entries.value) {
            sb.append(e.seq).append(',').append(e.timestampMs).append(',').append(e.timeText).append(',')
                .append(e.type).append(',').append(csv(e.device)).append(',').append(csv(e.uuid)).append(',')
                .append(csv(e.hex)).append(',').append(csv(e.note)).append('\n')
        }
        return sb.toString()
    }

    fun toJson(): String {
        val arr = JSONArray()
        for (e in _entries.value) {
            arr.put(JSONObject().apply {
                put("seq", e.seq); put("timestamp_ms", e.timestampMs); put("time", e.timeText)
                put("type", e.type.name); put("device", e.device); put("uuid", e.uuid)
                put("hex", e.hex); put("note", e.note)
            })
        }
        return JSONObject().apply {
            put("exported_at", System.currentTimeMillis())
            put("entry_count", arr.length())
            put("notify_counts", JSONObject(_counts.value as Map<*, *>))
            put("entries", arr)
        }.toString(2)
    }

    private fun csv(s: String): String =
        if (s.contains(',') || s.contains('"') || s.contains('\n')) "\"" + s.replace("\"", "\"\"") + "\"" else s

    /** Writes the export to cache and opens the system share sheet. Returns the file written. */
    fun share(context: Context, json: Boolean): File {
        val dir = File(context.cacheDir, "exports").apply { mkdirs() }
        val stamp = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())
        val file = File(dir, "bikesensordoctor-$stamp." + if (json) "json" else "csv")
        file.writeText(if (json) toJson() else toCsv())
        val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            this.type = if (json) "application/json" else "text/csv"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, file.name)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "Export log").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        return file
    }
}
