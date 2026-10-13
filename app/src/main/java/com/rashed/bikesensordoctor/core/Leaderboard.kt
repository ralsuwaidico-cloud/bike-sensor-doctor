package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — no Android imports. Club leaderboard maths.
 *
 * Fair by design: rides are ranked by distance, time, elevation and count — never by watts, speed or heart rate.
 * Only rides whose [BoardRide.source] is DEVICE count on a real board; SAMPLE (fictional club riders) and SIMULATED
 * rides are kept for demonstration and always flagged. Zone 2 discipline compares each rider against their OWN band.
 */
enum class RideSource { DEVICE, SIMULATED, SAMPLE }

data class BoardRide(val riderId: String, val startedAtMs: Long, val km: Double, val sec: Int, val elevM: Double, val inZonePct: Int, val source: RideSource)

data class BoardRider(val id: String, val name: String, val goal: String, val isSample: Boolean)

enum class BoardMetric(val label: String, val short: String, val weekly: Boolean, val unit: String) {
    WEEK_KM("Weekly distance", "Wk km", true, "km"),
    MONTH_KM("Monthly distance", "Mo km", false, "km"),
    TIME("Riding time this month", "Time", false, "h"),
    ELEV("Elevation this month", "Climb", false, "m"),
    RIDES("Rides this month", "Rides", false, "rides"),
    Z2("Zone 2 discipline this month", "Z2 ★", false, "rides ≥80% in band");

    fun score(rides: List<BoardRide>): Double = when (this) {
        WEEK_KM, MONTH_KM -> rides.sumOf { it.km }
        TIME -> rides.sumOf { it.sec } / 3600.0
        ELEV -> rides.sumOf { it.elevM }
        RIDES -> rides.size.toDouble()
        Z2 -> rides.count { it.inZonePct >= 80 }.toDouble()
    }
    fun format(v: Double): String = when (this) {
        WEEK_KM, MONTH_KM, TIME -> String.format(java.util.Locale.US, "%.1f", v)
        else -> Math.round(v).toString()
    }
}

data class BoardRow(val rider: BoardRider, val score: Double, val rank: Int, val rideCount: Int, val hasSimulated: Boolean)

data class Achievement(val key: String, val title: String)

object Leaderboard {
    /** Rides in the current period. Period boundaries are supplied by the caller (platform clock/calendar). */
    fun ridesIn(all: List<BoardRide>, riderId: String, periodStartMs: Long, includeDemo: Boolean): List<BoardRide> =
        all.filter { it.riderId == riderId && it.startedAtMs >= periodStartMs && (includeDemo || it.source == RideSource.DEVICE) }

    /**
     * @param weekStartMs / monthStartMs start of the current week (Monday 00:00) and month.
     * @param includeDemo include SAMPLE/SIMULATED rides (demo board). A real board passes false.
     */
    fun rows(metric: BoardMetric, riders: List<BoardRider>, rides: List<BoardRide>, weekStartMs: Long, monthStartMs: Long, includeDemo: Boolean): List<BoardRow> {
        val t0 = if (metric.weekly) weekStartMs else monthStartMs
        val scored = riders.map { r ->
            val rs = ridesIn(rides, r.id, t0, includeDemo)
            Triple(r, metric.score(rs), rs)
        }.sortedWith(compareByDescending<Triple<BoardRider, Double, List<BoardRide>>> { it.second }.thenBy { it.first.name })
        return scored.mapIndexed { i, (r, v, rs) -> BoardRow(r, v, i + 1, rs.size, rs.any { it.source != RideSource.DEVICE }) }
    }

    fun achievements(riderRides: List<BoardRide>, weekStartMs: Long, monthStartMs: Long): List<Achievement> {
        val out = ArrayList<Achievement>()
        val wk = riderRides.filter { it.startedAtMs >= weekStartMs }; val mo = riderRides.filter { it.startedAtMs >= monthStartMs }
        if (wk.size >= 3) out += Achievement("consistent", "3 rides in a week")
        if (mo.count { it.inZonePct >= 80 } >= 3) out += Achievement("z2", "Zone 2 discipline ×3")
        if (riderRides.any { it.sec >= 2 * 3600 }) out += Achievement("long", "2-hour ride")
        if (riderRides.sumOf { it.km } >= 200) out += Achievement("200", "200 km club")
        if (mo.sumOf { it.elevM } >= 1000) out += Achievement("climb", "1,000 m climbed this month")
        return out
    }
}
