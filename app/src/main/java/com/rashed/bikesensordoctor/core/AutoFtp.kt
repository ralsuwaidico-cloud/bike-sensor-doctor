package com.rashed.bikesensordoctor.core

import kotlin.math.sqrt

/*
 * PORTABLE CORE — automatic FTP (v0.11).
 *
 *  StartingFtp        the onboarding STARTING ASSUMPTION: weight × experience W/kg (an approximate assumption, never a measurement)
 *  MmpTracker         rolling maximum mean power over the standard durations, from a ride's 1 Hz power
 *  QualifyingEffort   which sustained efforts count as FTP evidence (an ordinary endurance ride does NOT)
 *  FtpPolicy          when an estimate replaces the assumption automatically, when it is only proposed, and the plain-language history line
 *  LearningStage      Learning → Understanding → Personalised, from the number of real rides
 *  WindowAverages     time-weighted averages for the graph window (valid 0 W counted, missing seconds excluded; cadence elapsed vs pedalling)
 */

object StartingFtp {
    /** Experience level → W/kg (onboarding assumption). Keys are the profile's "experience" answers. */
    val WKG = linkedMapOf("new" to 1.75, "returning" to 2.25, "recreational" to 3.00, "experienced" to 4.00, "competitive" to 5.00)
    val LABEL = mapOf("new" to "Beginner", "returning" to "Novice", "recreational" to "Intermediate", "experienced" to "Advanced", "competitive" to "Competitive")
    const val HOW = "assumed"   // metric.how value that marks a STARTING ASSUMPTION

    /** Starting FTP (W) = weight (kg) × W/kg for the experience level; null when either is unknown. */
    fun watts(weightKg: Int?, experience: String?): Int? {
        val w = weightKg ?: return null; val k = WKG[experience ?: return null] ?: return null
        if (w < 30 || w > 200) return null
        return Math.round(w * k).toInt()
    }

    /** Applies the assumption to a profile that has no credible FTP (none, or an earlier assumption). A tested/estimated/app value is preserved. */
    fun applyIfMissing(a: RiderAnswers): Boolean {
        val current = a.metric("ftp")
        if (current != null && current.how != HOW) return false
        val v = watts(a.int("weightKg"), a["experience"]) ?: return false
        if (current?.value == v) return false
        a.setMetric("ftp", v, HOW)
        if (current == null) FtpHistory.append(a, "Starting FTP $v W — assumption from ${a.int("weightKg")} kg × ${WKG[a["experience"]]} W/kg (${LABEL[a["experience"]]}).")
        return true
    }
}

/** The FTP change log kept in the profile ("ftp.history", one line per change, newest last, capped). */
object FtpHistory {
    private const val KEY = "ftp.history"
    fun lines(a: RiderAnswers): List<String> = a[KEY]?.split('\u001F')?.filter { it.isNotEmpty() } ?: emptyList()
    fun append(a: RiderAnswers, line: String) { val l = (lines(a) + line).takeLast(20); a[KEY] = l.joinToString("\u001F") }
}

/** Rolling maximum mean power over the standard durations. Missing seconds break a window (no interpolation); 0 W while coasting counts. */
class MmpTracker(val durationsSec: IntArray = intArrayOf(60, 180, 300, 480, 720, 1200, 1800, 3600)) {
    data class Best(val durationSec: Int, val meanW: Int, val startIndex: Int, val cv: Double)

    /** @param power 1 Hz, null = missing. @return best window per duration (only durations the ride covers). */
    fun compute(power: List<Int?>): List<Best> {
        val out = ArrayList<Best>()
        for (d in durationsSec) {
            if (power.size < d) continue
            var sum = 0.0; var sumSq = 0.0; var valid = 0; var bestMean = -1.0; var bestStart = -1; var bestCv = 0.0
            for (i in power.indices) {
                val v = power[i]
                if (v != null) { sum += v; sumSq += v.toDouble() * v; valid++ }
                if (i >= d) { val o = power[i - d]; if (o != null) { sum -= o; sumSq -= o.toDouble() * o; valid-- } }
                if (i >= d - 1 && valid >= (d * 0.95).toInt()) {
                    val mean = sum / valid
                    if (mean > bestMean) { bestMean = mean; bestStart = i - d + 1; val varc = (sumSq / valid - mean * mean).coerceAtLeast(0.0); bestCv = if (mean > 0) sqrt(varc) / mean else 0.0 }
                }
            }
            if (bestMean >= 0) out += Best(d, Math.round(bestMean).toInt(), bestStart, bestCv)
        }
        return out
    }
}

object QualifyingEffort {
    /**
     * Does a 20-minute window count as FTP evidence? It must be a genuine sustained effort, not the ride's cruise:
     *  - steady (CV ≤ 15 % inside the window),
     *  - clearly harder than the rest of the ride (window mean ≥ 1.15 × the mean of the other riding seconds, which must exist),
     *  - at least 60 W.
     * An ordinary endurance ride (window ≈ rest of ride) therefore yields nothing, by design.
     */
    fun ftp20(best: MmpTracker.Best?, power: List<Int?>): Boolean {
        best ?: return false
        if (best.durationSec != 1200 || best.meanW < 60 || best.cv > 0.15) return false
        val rest = power.filterIndexed { i, v -> v != null && (i < best.startIndex || i >= best.startIndex + 1200) }.map { it!! }
        if (rest.size < 600) return false
        val restMean = rest.average()
        return restMean > 0 && best.meanW >= restMean * 1.15
    }
}

object FtpPolicy {
    enum class Decision { NONE, AUTO_APPLY, PROPOSE }

    /**
     * What to do with a new estimate against the profile's FTP:
     *  - no FTP or a STARTING ASSUMPTION → apply automatically once the estimate is at least PROVISIONAL and differs meaningfully;
     *  - a tested / rider-entered / app-calculated value → propose for approval (never silently overwritten);
     *  - otherwise nothing.
     */
    fun decide(current: Metric?, est: Estimate?): Decision {
        est ?: return Decision.NONE
        if (est.status < EstimateStatus.PROVISIONAL) return Decision.NONE
        if (!Performance.meaningfullyDiffers(MetricKind.FTP, current?.value, est.value)) return Decision.NONE
        return if (current == null || current.how == StartingFtp.HOW || current.how == "auto") Decision.AUTO_APPLY else Decision.PROPOSE
    }

    /** Plain-language line for the change log and the rider. */
    fun explain(previous: Metric?, est: Estimate): String {
        val from = when { previous == null -> "no FTP"; previous.how == StartingFtp.HOW -> "starting FTP ${previous.value} W (assumption)"; else -> "FTP ${previous.value} W (${previous.how})" }
        val dir = if (previous != null && est.value < previous.value) "lower" else "higher"
        return "Your $from → estimated FTP is now ${est.value} W ($dir), ${est.label} from ${est.evidenceIds.size} sustained effort${if (est.evidenceIds.size == 1) "" else "s"} (${est.method.label})."
    }

    /** Applies an automatic update and records it. */
    fun apply(a: RiderAnswers, est: Estimate) {
        val prev = a.metric("ftp")
        a.setMetric("ftp", est.value, "auto")
        FtpHistory.append(a, explain(prev, est))
    }
}

enum class LearningStage(val label: String, val minRides: Int) {
    LEARNING("Learning", 0), UNDERSTANDING("Understanding", 3), PERSONALISED("Personalised", 8);
    companion object { fun of(realRides: Int) = values().last { realRides >= it.minRides } }
}

/** Time-weighted averages over a window of 1 Hz samples. */
data class WindowAverages(val powerW: Int?, val powerSec: Int, val cadElapsedRpm: Int?, val cadPedallingRpm: Int?, val cadSec: Int, val hrBpm: Int?, val hrSec: Int, val windowSec: Int) {
    companion object {
        fun of(power: List<Int?>, cad: List<Int?>, hr: List<Int?>): WindowAverages {
            val p = power.filterNotNull(); val c = cad.filterNotNull(); val cp = c.filter { it > 0 }; val h = hr.filterNotNull().filter { it > 0 }
            fun m(x: List<Int>) = if (x.isEmpty()) null else Math.round(x.average()).toInt()
            return WindowAverages(m(p), p.size, m(c), m(cp), c.size, m(h), h.size, power.size)
        }
    }
}
