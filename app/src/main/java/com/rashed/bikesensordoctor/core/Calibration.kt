package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — no Android imports. Automatic fitness calibration with evidence rules (v3):
 *  - FTP: 95 % of the best 20-minute power, but only from a VERIFIED meter and only once two rides agree (±5 %).
 *    A single ride is evidence, never proof. Measured (tested) values are never overwritten.
 *  - Threshold HR: from the guided 20-minute test (average HR of the test block). One test → PROVISIONAL;
 *    a second test within 3 bpm → CONFIRMED. Ordinary rides never set a threshold (no HR-to-power inference).
 *  - Max HR: the highest reliable reading can only raise a GENERIC/PROVISIONAL estimate, after confirmation.
 *  - Continuous evaluation: if the last three coached rides were all above the band at easy perceived effort,
 *    the zones are probably too low — the coach says so and offers the test instead of silently moving zones.
 */
object Calibration {
    data class Evidence(val label: String, val value: Int?, val confidence: ZoneConfidence?, val detail: String, val ready: Boolean)

    /** @param best20 per-ride best 20-min power from verified rides (most recent last). */
    fun ftp(best20: List<Int>): Evidence {
        if (best20.isEmpty()) return Evidence("FTP", null, null, "No verified 20-minute power efforts yet.", false)
        if (best20.size == 1) return Evidence("FTP", Math.round(best20[0] * 0.95).toInt(), null, "1 of 2 rides collected (${best20[0]} W best 20 min). One ride is evidence, not proof — one more ride with a similar effort makes it provisional.", false)
        val a = best20[best20.size - 1]; val b = best20[best20.size - 2]
        val agree = Math.abs(a - b).toDouble() / maxOf(a, b) <= 0.05
        val v = Math.round(maxOf(a, b) * 0.95).toInt()
        return if (agree) Evidence("FTP", v, ZoneConfidence.PROVISIONAL, "Two rides agree within 5 % ($b W, $a W best 20 min) → provisional FTP $v W. A guided 20-minute test makes it confirmed.", true)
        else Evidence("FTP", v, null, "Last two rides differ by more than 5 % ($b W vs $a W). Waiting for a consistent effort.", false)
    }

    /** @param tests average HR of completed guided test blocks (most recent last). */
    fun lthr(tests: List<Int>): Evidence {
        if (tests.isEmpty()) return Evidence("Threshold HR", null, null, "No guided test yet.", false)
        if (tests.size == 1) return Evidence("Threshold HR", tests[0], ZoneConfidence.PROVISIONAL, "From one guided 20-minute test (${tests[0]} bpm). A second test within 3 bpm confirms it.", true)
        val a = tests.last(); val b = tests[tests.size - 2]
        return if (Math.abs(a - b) <= 3) Evidence("Threshold HR", Math.round((a + b) / 2.0).toInt(), ZoneConfidence.CONFIRMED, "Two guided tests agree ($b, $a bpm) → confirmed.", true)
        else Evidence("Threshold HR", a, ZoneConfidence.PROVISIONAL, "Tests differ ($b vs $a bpm) — the newer one is used provisionally.", true)
    }

    /** Zones too low? Three coached rides in a row mostly above the band while feeling easy. */
    fun zonesTooLow(log: List<RideFeedback>): Boolean {
        val last = log.takeLast(3); if (last.size < 3) return false
        return last.all { it.inZonePct < 50 && (it.rpe ?: 10) <= 4 }
    }

    /** What the coach has learned from the rides it has seen (plain facts, each with its evidence count). */
    data class Learned(val naturalCadence: Int?, val sustainablePowerW: Int?, val hrAtTypicalEffort: Int?, val longestRideMin: Int?, val inBandTrend: String?, val recoveryBpm: Int?, val rides: Int)
    fun learn(cadences: List<Int>, best20: List<Int>, avgHrs: List<Int>, durationsMin: List<Int>, inBandPcts: List<Int>, recoveries: List<Int>): Learned {
        fun median(v: List<Int>): Int? = if (v.isEmpty()) null else v.sorted()[v.size / 2]
        val trend = if (inBandPcts.size >= 3) { val a = inBandPcts.takeLast(3).average(); val b = inBandPcts.dropLast(3).takeLast(3).let { if (it.isEmpty()) null else it.average() }; if (b == null) "${Math.round(a)} % in band over the last 3 rides" else if (a - b >= 5) "improving (${Math.round(b)} → ${Math.round(a)} % in band)" else if (b - a >= 5) "slipping (${Math.round(b)} → ${Math.round(a)} % in band)" else "steady (~${Math.round(a)} % in band)" } else null
        return Learned(median(cadences), best20.maxOrNull(), median(avgHrs), durationsMin.maxOrNull(), trend, median(recoveries), maxOf(cadences.size, avgHrs.size, durationsMin.size))
    }
}
