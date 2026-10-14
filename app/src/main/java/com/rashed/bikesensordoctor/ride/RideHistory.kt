package com.rashed.bikesensordoctor.ride

import android.content.Context
import com.rashed.bikesensordoctor.core.RideSummary
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.Locale

/** Local ride history: one JSON file per ride in app-private storage, plus a 1 Hz CSV of samples. */
class RideHistory(val dir: File) {
    constructor(context: Context) : this(File(context.filesDir, "rides"))
    init { dir.mkdirs() }

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
            put("distanceKm", summary.distanceKm); put("elevationGainM", summary.elevationGainM); put("avgHr", summary.avgHr)
            put("inZonePct", summary.inZonePct); put("source", summary.source.name); put("riderId", summary.riderId)
        }.toString())
        return f
    }

    fun list(): List<RideSummary> =
        dir.listFiles { f -> f.name.endsWith(".json") }?.mapNotNull { f ->
            runCatching {
                val o = JSONObject(f.readText())
                RideSummary(o.getLong("startedAtMs"), o.getLong("durationMs"), o.getInt("avgPowerW"), o.getInt("maxPowerW"),
                    o.getInt("avgCadenceRpm"), o.getInt("maxCadenceRpm"), o.getDouble("energyKj"), o.getInt("samples"),
                    o.optInt("rejected"), o.optInt("backwardsSamples"),
                    o.optDouble("distanceKm", 0.0), o.optDouble("elevationGainM", 0.0), o.optInt("avgHr", 0), o.optInt("inZonePct", -1),
                    runCatching { com.rashed.bikesensordoctor.core.RideSource.valueOf(o.optString("source", "DEVICE")) }.getOrDefault(com.rashed.bikesensordoctor.core.RideSource.DEVICE),
                    o.optString("riderId", ""))
            }.getOrNull()
        }?.sortedByDescending { it.startedAtMs } ?: emptyList()

    fun delete(startedAtMs: Long) {
        File(dir, "ride-$startedAtMs.json").delete(); File(dir, "ride-$startedAtMs.csv").delete()
        File(dir, "ride-$startedAtMs-report.json").delete(); File(dir, "ride-$startedAtMs.gpx").delete()
        File(dir, "ride-$startedAtMs-series.csv").delete(); File(dir, "ride-$startedAtMs-meta.json").delete()
    }

    fun csvFile(startedAtMs: Long): File = File(dir, "ride-$startedAtMs.csv")
    fun reportFile(startedAtMs: Long): File = File(dir, "ride-$startedAtMs-report.json")

    /** Extra analysis stored alongside the ride: seconds in each power/HR zone, HR avg/max. */
    fun saveReport(startedAtMs: Long, powerZoneSec: IntArray, hrZoneSec: IntArray, avgHr: Int, maxHr: Int,
                   link: com.rashed.bikesensordoctor.core.LinkReport? = null) {
        val o = JSONObject()
        o.put("powerZoneSec", JSONArray(powerZoneSec.toList()))
        o.put("hrZoneSec", JSONArray(hrZoneSec.toList()))
        o.put("avgHr", avgHr); o.put("maxHr", maxHr)
        if (link != null) {
            // P0: sensor-quality and connection-gap record
            o.put("linkPackets", link.packets); o.put("linkQualityPct", link.qualityPct)
            o.put("linkGapCount", link.gapCount); o.put("linkLostMs", link.lostMs)
            o.put("linkVerdict", link.verdict())
            o.put("linkGaps", JSONArray(link.gaps.map { g ->
                JSONObject().put("startMs", g.startMs).put("endMs", g.endMs).put("reason", g.reason)
                    .put("rotatingBefore", g.rotatingBefore).put("poweredBefore", g.poweredBefore)
                    .put("lastCadenceRpm", g.lastCadenceRpm).put("lastPowerW", g.lastPowerW)
            }))
        }
        reportFile(startedAtMs).writeText(o.toString())
    }

    data class GapInfo(val startMs: Long, val endMs: Long, val reason: String, val rotatingBefore: Boolean, val poweredBefore: Boolean)
    data class Report(
        val powerZoneSec: List<Int>, val hrZoneSec: List<Int>, val avgHr: Int, val maxHr: Int,
        val linkQualityPct: Int? = null, val linkGapCount: Int = 0, val linkLostMs: Long = 0, val linkVerdict: String? = null,
        val gaps: List<GapInfo> = emptyList(),
    )
    fun readReport(startedAtMs: Long): Report? {
        val f = reportFile(startedAtMs); if (!f.exists()) return null
        return runCatching {
            val o = JSONObject(f.readText())
            fun arr(k: String) = o.getJSONArray(k).let { a -> (0 until a.length()).map { a.getInt(it) } }
            val gaps = o.optJSONArray("linkGaps")?.let { a -> (0 until a.length()).map { i -> val g = a.getJSONObject(i)
                GapInfo(g.getLong("startMs"), g.getLong("endMs"), g.optString("reason"), g.optBoolean("rotatingBefore"), g.optBoolean("poweredBefore")) } } ?: emptyList()
            Report(arr("powerZoneSec"), arr("hrZoneSec"), o.optInt("avgHr"), o.optInt("maxHr"),
                if (o.has("linkQualityPct")) o.getInt("linkQualityPct") else null, o.optInt("linkGapCount"), o.optLong("linkLostMs"),
                if (o.has("linkVerdict")) o.getString("linkVerdict") else null, gaps)
        }.getOrNull()
    }
    fun gpxFile(startedAtMs: Long): File = File(dir, "ride-$startedAtMs.gpx")

    // ---- v0.9: 1 Hz ride series + small meta record for the Ride Results page ----
    fun seriesFile(startedAtMs: Long): File = File(dir, "ride-$startedAtMs-series.csv")
    fun saveSeries(startedAtMs: Long, series: List<com.rashed.bikesensordoctor.core.SeriesPoint>) {
        seriesFile(startedAtMs).bufferedWriter().use { w -> w.write(com.rashed.bikesensordoctor.core.SeriesPoint.HEADER); w.newLine(); series.forEach { w.write(it.csv()); w.newLine() } }
    }
    fun readSeries(startedAtMs: Long): List<com.rashed.bikesensordoctor.core.SeriesPoint> {
        val f = seriesFile(startedAtMs); if (!f.exists()) return emptyList()
        return f.useLines { lines -> lines.mapNotNull { com.rashed.bikesensordoctor.core.SeriesPoint.parse(it) }.toList() }
    }
    fun metaFile(startedAtMs: Long): File = File(dir, "ride-$startedAtMs-meta.json")
    /** Merge key/values into the ride's meta record (workout, band, FTP used, rider answers after the ride, HR recovery …). */
    fun updateMeta(startedAtMs: Long, values: Map<String, Any?>) {
        val o = runCatching { JSONObject(metaFile(startedAtMs).readText()) }.getOrDefault(JSONObject())
        values.forEach { (k, v) -> if (v == null) o.remove(k) else o.put(k, v) }
        metaFile(startedAtMs).writeText(o.toString())
    }
    fun readMeta(startedAtMs: Long): Map<String, Any> {
        val f = metaFile(startedAtMs); if (!f.exists()) return emptyMap()
        return runCatching { val o = JSONObject(f.readText()); o.keys().asSequence().associateWith { o.get(it) } }.getOrDefault(emptyMap())
    }
    fun hasGpx(startedAtMs: Long): Boolean = gpxFile(startedAtMs).exists()

    /** Writes a standard GPX 1.1 track with Garmin power/cadence/hr extensions. Returns null if no points. */
    fun saveGpx(startedAtMs: Long, points: List<TrackPoint>, samplesAt: (Long) -> Triple<Int?, Int?, Int?>): File? {
        if (points.isEmpty()) return null
        val iso = java.text.SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = java.util.TimeZone.getTimeZone("UTC")
        }
        val sb = StringBuilder()
        sb.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        sb.append("<gpx version=\"1.1\" creator=\"Bike Computer\" xmlns=\"http://www.topografix.com/GPX/1/1\" ")
        sb.append("xmlns:gpxtpx=\"http://www.garmin.com/xmlschemas/TrackPointExtension/v1\">\n")
        sb.append("<trk><name>Ride ").append(iso.format(java.util.Date(startedAtMs))).append("</name><trkseg>\n")
        for (p in points) {
            sb.append("<trkpt lat=\"").append(p.lat).append("\" lon=\"").append(p.lon).append("\">")
            p.altM?.let { sb.append("<ele>").append(it).append("</ele>") }
            sb.append("<time>").append(iso.format(java.util.Date(p.timeMs))).append("</time>")
            val (pw, cad, hr) = samplesAt(p.timeMs)
            if (pw != null) sb.append("<extensions><power>").append(pw).append("</power>")
            if (cad != null || hr != null) {
                if (pw == null) sb.append("<extensions>")
                sb.append("<gpxtpx:TrackPointExtension>")
                cad?.let { sb.append("<gpxtpx:cad>").append(it).append("</gpxtpx:cad>") }
                hr?.let { sb.append("<gpxtpx:hr>").append(it).append("</gpxtpx:hr>") }
                sb.append("</gpxtpx:TrackPointExtension>")
                sb.append("</extensions>")
            } else if (pw != null) sb.append("</extensions>")
            sb.append("</trkpt>\n")
        }
        sb.append("</trkseg></trk></gpx>\n")
        val f = gpxFile(startedAtMs)
        f.writeText(sb.toString())
        return f
    }

    fun exportAllJson(): String {
        val arr = JSONArray(); list().forEach { s ->
            arr.put(JSONObject().apply { put("startedAtMs", s.startedAtMs); put("durationMs", s.durationMs); put("avgPowerW", s.avgPowerW); put("maxPowerW", s.maxPowerW); put("avgCadenceRpm", s.avgCadenceRpm); put("maxCadenceRpm", s.maxCadenceRpm); put("energyKj", s.energyKj) })
        }
        return arr.toString(2)
    }
}
