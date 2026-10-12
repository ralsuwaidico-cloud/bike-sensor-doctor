package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — no Android imports. Training zones, computed offline from the rider's FTP and max HR.
 * Reusable verbatim on the ESP32-S3.
 */

/** Coggan 7-zone power model, as % of FTP. Zone 2 (endurance) is the 56–75% band. */
object PowerZones {
    // upper bound of each zone as a fraction of FTP; Z7 is open-ended
    private val upper = doubleArrayOf(0.55, 0.75, 0.90, 1.05, 1.20, 1.50)
    val names = arrayOf("Z1 Recovery", "Z2 Endurance", "Z3 Tempo", "Z4 Threshold", "Z5 VO2", "Z6 Anaerobic", "Z7 Neuro")

    /** 1..7. Returns 0 when power is null/0 (coasting) so the UI can show a neutral state. */
    fun zone(powerW: Int?, ftpW: Int): Int {
        if (powerW == null || powerW <= 0 || ftpW <= 0) return 0
        val frac = powerW.toDouble() / ftpW
        for (i in upper.indices) if (frac <= upper[i]) return i + 1
        return 7
    }

    fun name(zone: Int): String = if (zone in 1..7) names[zone - 1] else "—"
    fun isZone2(powerW: Int?, ftpW: Int): Boolean = zone(powerW, ftpW) == 2

    /** Watt range of a zone for display, e.g. Z2 at FTP 200 → 110..150 W. null high = open-ended. */
    fun range(zone: Int, ftpW: Int): Pair<Int, Int?> {
        if (zone !in 1..7 || ftpW <= 0) return 0 to null
        val lo = if (zone == 1) 0 else (upper[zone - 2] * ftpW + 0.5).toInt()
        val hi = if (zone == 7) null else (upper[zone - 1] * ftpW + 0.5).toInt()
        return lo to hi
    }
}

/** 5-zone heart-rate model as % of max HR (common Garmin/BCF scheme). */
object HrZones {
    private val upper = doubleArrayOf(0.60, 0.70, 0.80, 0.90)  // Z1..Z4 upper; Z5 open
    val names = arrayOf("Z1 Easy", "Z2 Fat-burn", "Z3 Aerobic", "Z4 Threshold", "Z5 Max")

    fun zone(hr: Int?, maxHr: Int): Int {
        if (hr == null || hr <= 0 || maxHr <= 0) return 0
        val frac = hr.toDouble() / maxHr
        for (i in upper.indices) if (frac <= upper[i]) return i + 1
        return 5
    }
    fun name(zone: Int): String = if (zone in 1..5) names[zone - 1] else "—"
    fun isZone2(hr: Int?, maxHr: Int): Boolean = zone(hr, maxHr) == 2
}
