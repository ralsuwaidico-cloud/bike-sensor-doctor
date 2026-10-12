package com.rashed.bikesensordoctor.ride

import android.content.Context
import com.rashed.bikesensordoctor.core.RideSummary
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/** Local ride history: one JSON file per ride in app-private storage, plus a 1 Hz CSV of samples. */
class RideHistory(context: Context) {
    private val dir = File(context.filesDir, "rides").apply { mkdirs() }

    fun save(summary: RideSummary, samplesCsv: String): File {
        val id = "ride-${summary.startedAtMs}"
        File(dir, "$id.csv").writeText(samplesCsv)
        val f = File(dir, "$id.json")
        f.writeText(JSONObject().apply {
            put("startedAtMs", summary.startedAtMs); put("durationMs", summary.durationMs)
            put("avgPowerW", summary.avgPowerW); put("maxPowerW", summary.maxPowerW)
            put("avgCadenceRpm", summary.avgCadenceRpm); put("maxCadenceRpm", summary.maxCadenceRpm)
            put("energyKj", summary.energyKj); put("samples", summary.samples); put("rejected", summary.rejected)
            put("backwardsSamples", summary.backwardsSamples)
        }.toString())
        return f
    }

    fun list(): List<RideSummary> =
        dir.listFiles { f -> f.name.endsWith(".json") }?.mapNotNull { f ->
            runCatching {
                val o = JSONObject(f.readText())
                RideSummary(o.getLong("startedAtMs"), o.getLong("durationMs"), o.getInt("avgPowerW"), o.getInt("maxPowerW"),
                    o.getInt("avgCadenceRpm"), o.getInt("maxCadenceRpm"), o.getDouble("energyKj"), o.getInt("samples"),
                    o.optInt("rejected"), o.optInt("backwardsSamples"))
            }.getOrNull()
        }?.sortedByDescending { it.startedAtMs } ?: emptyList()

    fun delete(startedAtMs: Long) {
        File(dir, "ride-$startedAtMs.json").delete(); File(dir, "ride-$startedAtMs.csv").delete()
    }

    fun csvFile(startedAtMs: Long): File = File(dir, "ride-$startedAtMs.csv")

    fun exportAllJson(): String {
        val arr = JSONArray(); list().forEach { s ->
            arr.put(JSONObject().apply { put("startedAtMs", s.startedAtMs); put("durationMs", s.durationMs); put("avgPowerW", s.avgPowerW); put("maxPowerW", s.maxPowerW); put("avgCadenceRpm", s.avgCadenceRpm); put("maxCadenceRpm", s.maxCadenceRpm); put("energyKj", s.energyKj) })
        }
        return arr.toString(2)
    }
}
