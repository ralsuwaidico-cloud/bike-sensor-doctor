package com.rashed.bikesensordoctor.core

import kotlin.math.max
import kotlin.math.sqrt

/**
 * PORTABLE CORE — no Android imports. The 1 Hz record of a ride and everything the Ride Results page derives
 * from it. Nothing is invented: a missing channel stays null and the analysis says what it could not compute.
 *
 *  - [SeriesPoint]: one second of riding time (paused seconds are not recorded).
 *  - [RideAnalysis.analyze]: overview, heart-rate zones (personal AND an optional reference zone set such as the
 *    Apple Watch bands, kept apart and labelled), power/cadence, speed/elevation, consistency, drift, calories
 *    (always an estimate, method stated), provisional FTP / max-HR suggestions, and the coach's review.
 *
 * Verified by RideAnalysisTest, including the 12 Oct 2026 Apple Fitness fixture.
 */
data class SeriesPoint(
    val tSec: Int,
    val hr: Int? = null, val powerW: Int? = null, val cadRpm: Int? = null,
    val speedKmh: Double? = null, val altM: Double? = null, val distKm: Double = 0.0,
    val lat: Double? = null, val lon: Double? = null,
    val phase: Phase = Phase.MAIN, val inBand: Boolean? = null,
) {
    fun csv(): String = "$tSec,${hr ?: ""},${powerW ?: ""},${cadRpm ?: ""},${speedKmh?.let { f1(it) } ?: ""},${altM?.let { f1(it) } ?: ""},${f3(distKm)},${lat?.let { f6(it) } ?: ""},${lon?.let { f6(it) } ?: ""},${phase.name},${inBand?.let { if (it) 1 else 0 } ?: ""}"
    companion object {
        const val HEADER = "t_sec,hr_bpm,power_w,cadence_rpm,speed_kmh,alt_m,dist_km,lat,lon,phase,in_band"
        fun parse(line: String): SeriesPoint? {
            val p = line.split(','); if (p.size < 7 || p[0].toIntOrNull() == null) return null
            return SeriesPoint(p[0].toInt(), p[1].toIntOrNull(), p[2].toIntOrNull(), p[3].toIntOrNull(), p[4].toDoubleOrNull(), p[5].toDoubleOrNull(), p[6].toDoubleOrNull() ?: 0.0,
                p.getOrNull(7)?.toDoubleOrNull(), p.getOrNull(8)?.toDoubleOrNull(),
                p.getOrNull(9)?.let { n -> runCatching { Phase.valueOf(n) }.getOrNull() } ?: Phase.MAIN,
                p.getOrNull(10)?.let { if (it == "1") true else if (it == "0") false else null })
        }
        private fun f1(v: Double) = String.format(java.util.Locale.US, "%.1f", v)
        private fun f3(v: Double) = String.format(java.util.Locale.US, "%.3f", v)
        private fun f6(v: Double) = String.format(java.util.Locale.US, "%.6f", v)
    }
}

/** A named set of five heart-rate zones by upper bound of Z1..Z4 (Z5 open). */
data class HrZoneSet(val name: String, val upper: IntArray, val source: String) {
    /** 1..5 */
    fun zone(bpm: Int): Int { for (i in upper.indices) if (bpm <= upper[i]) return i + 1; return 5 }
    fun label(z: Int): String = when (z) { 1 -> "≤ ${upper[0]}"; 5 -> "≥ ${upper[3] + 1}"; else -> "${upper[z - 2] + 1}–${upper[z - 1]}" }
    companion object {
        /** Apple Fitness bands read from Rashed's 12 Oct 2026 workout: Z1 < 150 … Z5 ≥ 179 (a reference, never a coaching target). */
        val APPLE_12_OCT = HrZoneSet("Apple Fitness (your watch)", intArrayOf(150, 160, 169, 178), "Apple Watch, app-calculated")
        fun fromSetup(c: CoachSetup) = HrZoneSet("Your coaching zones", intArrayOf(c.hrZoneEdges[0] - 1, c.hrZoneEdges[1] - 1, c.hrZoneEdges[2] - 1, c.hrZoneEdges[3] - 1), c.zoneConfidenceText)
        fun generic(maxHr: Int) = HrZoneSet("Generic (% of max $maxHr)", intArrayOf((maxHr * 0.60).toInt(), (maxHr * 0.70).toInt(), (maxHr * 0.80).toInt(), (maxHr * 0.90).toInt()), "GENERIC")
    }
}

data class ZoneBreakdown(val set: HrZoneSet, val sec: IntArray) { val total get() = sec.sum(); fun pct(z: Int) = if (total == 0) 0 else (sec[z - 1] * 100 + total / 2) / total }

data class Suggestion(val key: String, val title: String, val value: Int, val why: String)

data class AnalysisResult(
    val durationSec: Int, val movingSec: Int, val distanceKm: Double,
    val avgSpeedKmh: Double?, val maxSpeedKmh: Double?, val elevationGainM: Double,
    val avgHr: Int?, val maxHr: Int?, val hrSamples: Int,
    val avgPowerW: Int?, val maxPowerW: Int?, val normalizedPowerW: Int?, val powerSamples: Int,
    val avgCadRpm: Int?, val cadSamples: Int,
    val kcal: Int?, val kcalMethod: String,
    val personalZones: ZoneBreakdown?, val referenceZones: ZoneBreakdown?,
    val powerZoneSec: IntArray, val ftpUsed: Int,
    val inBandPct: Int?, val mainSec: Int, val longestInBandSec: Int,
    val hrConsistencyCv: Double?, val powerConsistencyCv: Double?,
    val driftPct: Int?, val driftNote: String,
    val hrRecovery60: Int?,
    val objectiveMet: Boolean?, val wentWell: List<String>, val improve: List<String>,
    val suggestions: List<Suggestion>,
    val hasRoute: Boolean,
)

object RideAnalysis {
    private fun r(x: Double) = Math.round(x).toInt()

    /**
     * @param personal the rider's coaching zones (null = none set); @param reference e.g. Apple bands (optional)
     * @param ftp FTP used for power zones; @param powerTrusted power meter verified under load (else power is reported but never used for calories/FTP)
     * @param band the workout's main-phase HR band if the ride was coached; @param weightKg for the HR-only calorie estimate
     * @param hrRecovery60 HR 60 s after the finish, if the strap kept reporting
     */
    fun analyze(
        s: List<SeriesPoint>, personal: HrZoneSet?, reference: HrZoneSet?, ftp: Int, powerTrusted: Boolean,
        band: IntRange?, weightKg: Int?, age: Int?, hrRecovery60: Int? = null, rpe: Int? = null,
    ): AnalysisResult {
        val n = s.size
        val hrs = s.mapNotNull { it.hr }.filter { it > 0 }
        val pws = s.mapNotNull { it.powerW }
        val cads = s.mapNotNull { it.cadRpm }.filter { it > 0 }
        val sps = s.mapNotNull { it.speedKmh }
        val moving = s.count { (it.speedKmh ?: 0.0) > 2.0 || (it.cadRpm ?: 0) > 0 }
        val dist = s.lastOrNull()?.distKm ?: 0.0
        val avgSpeed = if (moving > 0 && dist > 0) dist / (moving / 3600.0) else if (sps.isNotEmpty()) sps.average() else null
        var gain = 0.0; var lastAlt: Double? = null
        s.forEach { p -> val a = p.altM ?: return@forEach; val la = lastAlt; if (la == null) lastAlt = a else if (a - la >= 3.0) { gain += a - la; lastAlt = a } else if (a < la) lastAlt = a }

        // normalized power (Coggan): 30 s rolling mean, 4th power, over the loaded seconds
        var np: Int? = null
        if (pws.size >= 60) {
            val win = ArrayDeque<Int>(); var acc = 0.0; var cnt = 0
            s.forEach { p -> val w = p.powerW ?: return@forEach; win.addLast(w); if (win.size > 30) win.removeFirst(); if (win.size == 30) { val m = win.average(); acc += m * m * m * m; cnt++ } }
            if (cnt > 0) np = r(Math.pow(acc / cnt, 0.25))
        }

        // calories: work from a verified meter (kJ ≈ kcal at ~24 % efficiency), else Keytel HR estimate, else nothing
        val kcal: Int?; val method: String
        if (powerTrusted && pws.size >= 60) { kcal = r(pws.sum() / 1000.0); method = "ESTIMATE from measured power (1 kJ ≈ 1 kcal)" }
        else if (hrs.size >= 60 && weightKg != null && age != null) {
            val avg = hrs.average(); val perMin = (-55.0969 + 0.6309 * avg + 0.1988 * weightKg + 0.2017 * age) / 4.184
            kcal = r(perMin * hrs.size / 60.0).coerceAtLeast(0); method = "ESTIMATE from heart rate (Keytel), weight $weightKg kg, age $age"
        } else { kcal = null; method = if (hrs.isEmpty()) "no heart rate or verified power" else "add weight and age in the profile" }

        fun zones(set: HrZoneSet?): ZoneBreakdown? { set ?: return null; val sec = IntArray(5); s.forEach { p -> val h = p.hr ?: return@forEach; if (h > 0) sec[set.zone(h) - 1]++ }; return ZoneBreakdown(set, sec) }
        val pz = IntArray(8); s.forEach { p -> val z = PowerZones.zone(p.powerW, ftp); if (z in 1..7) pz[z]++ }

        // in-band time and the longest continuous block (MAIN phase)
        val main = s.filter { it.phase == Phase.MAIN }
        var inBand = 0; var longest = 0; var run = 0
        main.forEach { p -> val ok = p.inBand ?: (band != null && p.hr != null && p.hr in band); if (ok) { inBand++; run++; if (run > longest) longest = run } else run = 0 }
        val inBandPct = if (main.isNotEmpty() && (band != null || main.any { it.inBand != null })) inBand * 100 / main.size else null

        fun cv(v: List<Double>): Double? { if (v.size < 60) return null; val m = v.average(); if (m <= 0) return null; return sqrt(v.sumOf { (it - m) * (it - m) } / v.size) / m }
        val hrCv = cv(main.mapNotNull { it.hr?.toDouble() })
        val pwCv = cv(main.mapNotNull { it.powerW?.toDouble() }.filter { it > 0 })

        // drift: second half vs first half of the MAIN phase, only when speed/power was comparable (±10 %) → "valid comparable steady effort"
        var drift: Int? = null; var driftNote = "needs ≥ 20 min of main-phase heart rate"
        val mainHr = main.filter { it.hr != null }
        if (mainHr.size >= 1200) {
            val h = mainHr.size / 2; val a = mainHr.subList(0, h); val b = mainHr.subList(h, mainHr.size)
            val ea = a.mapNotNull { it.powerW?.toDouble() ?: it.speedKmh }.average(); val eb = b.mapNotNull { it.powerW?.toDouble() ?: it.speedKmh }.average()
            val comparable = ea.isNaN() || eb.isNaN() || (eb > 0 && Math.abs(ea / eb - 1) <= 0.10)
            if (comparable) { drift = r((b.map { it.hr!! }.average() / a.map { it.hr!! }.average() - 1) * 100); driftNote = "2nd half vs 1st half of the main block at similar effort" }
            else driftNote = "halves not comparable (effort differed > 10 %) — drift not computed"
        }

        // provisional estimates — suggestions only; the rider confirms, measured values are never overwritten
        val sug = ArrayList<Suggestion>()
        if (powerTrusted && pws.size >= 1200) {
            var best = 0.0; var sum = 0.0; val win = ArrayDeque<Int>()
            s.forEach { p -> val w = p.powerW ?: 0; win.addLast(w); sum += w; if (win.size > 1200) sum -= win.removeFirst(); if (win.size == 1200 && sum / 1200 > best) best = sum / 1200 }
            if (best > 60) sug += Suggestion("ftp", "Provisional FTP ${r(best * 0.95)} W", r(best * 0.95), "95 % of your best 20-minute power (${r(best)} W) in this ride. Only a 20-minute test makes it confirmed.")
        }
        hrs.maxOrNull()?.let { mx -> if (personal != null && mx > personal.upper[3] + 1 && (personal.source.startsWith("GENERIC") || personal.source.startsWith("PROVISIONAL"))) sug += Suggestion("maxHr", "Max HR observed $mx bpm", mx, "Higher than the estimate your zones are built on. Update the estimate? (Zones stay PROVISIONAL until a test.)") }

        // coach review
        val well = ArrayList<String>(); val imp = ArrayList<String>()
        val objective: Boolean? = inBandPct?.let { it >= 80 }
        if (inBandPct != null) { if (inBandPct >= 80) well += "Held the target band for $inBandPct % of the main block (goal ≥ 80 %)." else imp += "Only $inBandPct % of the main block was inside the band — most excursions were ${if (main.count { (it.hr ?: 0) > (band?.last ?: Int.MAX_VALUE) } > main.count { (it.hr ?: Int.MAX_VALUE) < (band?.first ?: 0) }) "above (ease earlier)" else "below (a touch more effort)"}." }
        if (longest >= 600) well += "Longest continuous block in band: ${longest / 60} min."
        hrCv?.let { if (it <= 0.05) well += "Very steady heart rate (±${r(it * 100)} %)." else if (it >= 0.10) imp += "Heart rate varied ±${r(it * 100)} % — smoother pacing on the flats would help." }
        pwCv?.let { if (powerTrusted && it <= 0.25) well += "Steady power delivery (±${r(it * 100)} %)." }
        drift?.let { if (it <= 5) well += "Heart-rate drift only $it % — good aerobic durability." else imp += "Heart-rate drift $it % at similar effort: hydration, heat or the ride being long for current fitness." }
        if (cads.isNotEmpty()) { val ac = cads.average(); if (ac < 75) imp += "Average cadence ${r(ac)} rpm is low — an easier gear and a quicker spin shifts load off the legs." }
        if (hrRecovery60 != null && hrs.isNotEmpty()) { val drop = (hrs.takeLast(30).average() - hrRecovery60); if (drop >= 20) well += "Heart rate fell ${r(drop)} bpm in the first minute after the ride." else imp += "Heart rate fell only ${r(drop)} bpm in the first minute — ease the last minutes more." }
        if (rpe != null && inBandPct != null) { if (rpe <= 4 && inBandPct >= 80) well += "Felt easy ($rpe/10) while in zone — ready for a little more." else if (rpe >= 8) imp += "Felt hard ($rpe/10): the next session should be easier." }

        return AnalysisResult(
            durationSec = n, movingSec = moving, distanceKm = dist, avgSpeedKmh = avgSpeed, maxSpeedKmh = sps.maxOrNull(), elevationGainM = gain,
            avgHr = if (hrs.isEmpty()) null else r(hrs.average()), maxHr = hrs.maxOrNull(), hrSamples = hrs.size,
            avgPowerW = if (pws.isEmpty()) null else r(pws.average()), maxPowerW = pws.maxOrNull(), normalizedPowerW = np, powerSamples = pws.size,
            avgCadRpm = if (cads.isEmpty()) null else r(cads.average()), cadSamples = cads.size,
            kcal = kcal, kcalMethod = method, personalZones = zones(personal), referenceZones = zones(reference), powerZoneSec = pz, ftpUsed = ftp,
            inBandPct = inBandPct, mainSec = main.size, longestInBandSec = longest, hrConsistencyCv = hrCv, powerConsistencyCv = pwCv,
            driftPct = drift, driftNote = driftNote, hrRecovery60 = hrRecovery60, objectiveMet = objective, wentWell = well, improve = imp, suggestions = sug,
            hasRoute = s.count { it.lat != null } >= 2,
        )
    }

    /** Downsample a channel to at most [buckets] points (mean per bucket) for drawing. */
    fun downsample(values: List<Int?>, buckets: Int): List<Int?> {
        if (values.size <= buckets) return values
        val out = ArrayList<Int?>(buckets); val step = values.size.toDouble() / buckets
        for (i in 0 until buckets) { val a = (i * step).toInt(); val b = max(a + 1, ((i + 1) * step).toInt()); val xs = values.subList(a, minOf(b, values.size)).filterNotNull(); out += if (xs.isEmpty()) null else r(xs.average()) }
        return out
    }
}
