package com.rashed.bikesensordoctor.ride

import android.content.Context
import com.rashed.bikesensordoctor.core.BoardRide
import com.rashed.bikesensordoctor.core.BoardRider
import com.rashed.bikesensordoctor.core.RideSource
import com.rashed.bikesensordoctor.core.RiderAnswers
import com.rashed.bikesensordoctor.core.RiderProfile
import java.util.Calendar

/**
 * DEMO club: four fictional riders with SAMPLE rides, stored on the phone only. There is no cloud account, no
 * server and no real invite system yet — the Club screen says so. Sample rides are tagged [RideSource.SAMPLE] and
 * can never appear on a real (device-only) board.
 */
object DemoClub {
    const val NAME = "Dawn Riders"
    const val CODE = "DAWN-7Q2K"
    val SAMPLE_IDS = listOf("omar", "layla", "sami", "noor")

    private fun answers(vararg kv: Pair<String, String>) = RiderAnswers(mapOf(*kv))

    private val profiles = mapOf(
        "omar" to ("Omar" to answers("age" to "38", "heightCm" to "178", "weightKg" to "76", "experience" to "experienced", "primary" to "endurance", "goals" to "endurance", "success" to "z2_90pct",
            "ridesNow" to "4", "daysAvail" to "5", "typicalMin" to "90", "longestMin" to "150", "other" to "none", "hrMode" to "know", "maxHr.value" to "186", "maxHr.how" to "measured",
            "restHr.value" to "52", "restHr.how" to "measured", "lthr.value" to "168", "lthr.how" to "measured", "pwMode" to "know", "ftp.value" to "245", "ftp.how" to "measured",
            "cadence.value" to "88", "cadence.how" to "measured", "voice" to "voice", "freq" to "important", "env" to "flat,hills", "cadAdvice" to "yes", "heat" to "yes", "tone" to "technical", "detail" to "detailed")),
        "layla" to ("Layla" to answers("age" to "31", "heightCm" to "165", "weightKg" to "58", "experience" to "experienced", "primary" to "ftp", "goals" to "ftp,climb", "success" to "ftp5",
            "ridesNow" to "3", "daysAvail" to "4", "typicalMin" to "75", "longestMin" to "120", "other" to "weights", "otherDays" to "Tue,Fri", "hrMode" to "know", "maxHr.value" to "190", "maxHr.how" to "estimated",
            "lthr.value" to "172", "lthr.how" to "app", "pwMode" to "know", "ftp.value" to "210", "ftp.how" to "measured", "voice" to "voice", "freq" to "frequent", "env" to "hills,indoor", "cadAdvice" to "yes", "heat" to "no", "tone" to "encouraging", "detail" to "simple")),
        "sami" to ("Sami" to answers("age" to "47", "heightCm" to "182", "weightKg" to "88", "experience" to "recreational", "primary" to "longer", "goals" to "longer,event", "success" to "long20",
            "ridesNow" to "2", "daysAvail" to "3", "typicalMin" to "120", "longestMin" to "180", "other" to "swim", "hrMode" to "estimate", "pwMode" to "unknown", "voice" to "screen", "freq" to "important", "env" to "flat", "cadAdvice" to "no", "heat" to "yes")),
        "noor" to ("Noor" to answers("age" to "27", "experience" to "new", "primary" to "fitness", "goals" to "fitness,weight", "success" to "fit3", "ridesNow" to "2", "daysAvail" to "3", "typicalMin" to "45", "longestMin" to "60",
            "other" to "running", "otherDays" to "Wed", "hrMode" to "later", "pwMode" to "unknown", "voice" to "voice", "freq" to "frequent", "env" to "flat", "cadAdvice" to "yes", "heat" to "yes", "tone" to "encouraging", "detail" to "simple")),
    )

    // days ago, km, minutes, elevation m, % in own Zone 2 band
    private val sampleRides = mapOf(
        "omar" to listOf(arrayOf(1, 42.3, 95, 95, 84), arrayOf(3, 31.0, 70, 55, 88), arrayOf(5, 55.2, 125, 160, 81), arrayOf(9, 38.4, 85, 80, 79), arrayOf(12, 61.0, 140, 195, 86), arrayOf(16, 29.9, 65, 45, 90), arrayOf(20, 44.1, 98, 100, 83), arrayOf(24, 36.0, 80, 73, 85)),
        "layla" to listOf(arrayOf(0, 28.6, 65, 216, 55), arrayOf(4, 24.0, 55, 158, 48), arrayOf(7, 36.5, 80, 299, 52), arrayOf(11, 22.8, 50, 131, 60), arrayOf(14, 40.2, 90, 341, 50), arrayOf(18, 26.1, 60, 183, 58), arrayOf(23, 33.0, 72, 262, 54)),
        "sami" to listOf(arrayOf(0, 68.0, 165, 128, 66), arrayOf(6, 52.4, 130, 91, 70), arrayOf(13, 74.5, 185, 146, 62), arrayOf(19, 47.0, 115, 79, 71), arrayOf(26, 58.3, 145, 107, 68)),
        "noor" to listOf(arrayOf(1, 18.2, 45, 27, 58), arrayOf(2, 15.6, 40, 21, 63), arrayOf(4, 20.1, 50, 34, 61), arrayOf(8, 16.9, 42, 24, 66), arrayOf(10, 19.4, 48, 29, 72), arrayOf(15, 14.8, 38, 18, 69), arrayOf(17, 21.0, 52, 37, 70), arrayOf(22, 17.5, 44, 26, 74)),
    )

    fun seed(store: RiderStore) {
        profiles.forEach { (id, p) ->
            if (store.load(id) != null) return@forEach
            val r = store.create(p.first, null, isSample = true, id = id)
            p.second.toMap().forEach { (k, v) -> r.answers[k] = v }
            r.completed = true; r.page = 5
            store.save(r)
        }
    }

    private fun daysAgo(n: Int): Long { val c = Calendar.getInstance(); c.add(Calendar.DAY_OF_YEAR, -n); c.set(Calendar.HOUR_OF_DAY, 7); c.set(Calendar.MINUTE, 0); c.set(Calendar.SECOND, 0); c.set(Calendar.MILLISECOND, 0); return c.timeInMillis }

    /** SAMPLE rides for the fictional riders (dates relative to today so the weekly/monthly boards always have content). */
    fun rides(): List<BoardRide> = sampleRides.flatMap { (id, rs) ->
        rs.map { r -> BoardRide(id, daysAgo(r[0] as Int), r[1] as Double, (r[2] as Int) * 60, (r[3] as Int).toDouble(), r[4] as Int, RideSource.SAMPLE) }
    }

    /** Club membership: sample riders are members; real riders join with the invite code (stored locally). */
    private const val MEMBERS = "club_members"
    fun members(ctx: Context): Set<String> {
        val sp = ctx.getSharedPreferences("bike_accounts", Context.MODE_PRIVATE)
        val stored = sp.getStringSet(MEMBERS, null) ?: emptySet()
        // sample riders are club members only in Developer / Test mode; real members are whoever joined with the code
        return if (sp.getBoolean("dev_mode", false)) stored + SAMPLE_IDS else stored - SAMPLE_IDS.toSet()
    }
    fun join(ctx: Context, riderId: String) { val m = members(ctx).toMutableSet(); m += riderId; ctx.getSharedPreferences("bike_accounts", Context.MODE_PRIVATE).edit().putStringSet(MEMBERS, m).apply() }
    fun leave(ctx: Context, riderId: String) { val m = members(ctx).toMutableSet(); m -= riderId; ctx.getSharedPreferences("bike_accounts", Context.MODE_PRIVATE).edit().putStringSet(MEMBERS, m).apply() }

    fun boardRider(r: Rider): BoardRider = BoardRider(r.id, r.name, RiderAnswers.GOAL_SHORT[RiderProfile.primaryGoal(r.answers)] ?: "—", r.isSample)

    /** All rides that may appear on the DEMO board: device/simulated rides from each account's history + sample rides. */
    fun allRides(store: RiderStore, riders: List<Rider>): List<BoardRide> {
        val out = ArrayList<BoardRide>()
        riders.forEach { r ->
            RideHistory(store.ridesDir(r.id)).list().forEach { s ->
                out += BoardRide(r.id, s.startedAtMs, s.distanceKm, (s.durationMs / 1000).toInt(), s.elevationGainM, s.inZonePct, s.source)
            }
        }
        out += rides().filter { r -> riders.any { it.id == r.riderId && it.isSample } }   // SAMPLE rides exist only for listed sample riders (dev mode)
        return out
    }

    fun weekStartMs(): Long { val c = Calendar.getInstance(); c.set(Calendar.HOUR_OF_DAY, 0); c.set(Calendar.MINUTE, 0); c.set(Calendar.SECOND, 0); c.set(Calendar.MILLISECOND, 0)
        val dow = (c.get(Calendar.DAY_OF_WEEK) + 5) % 7; c.add(Calendar.DAY_OF_YEAR, -dow); return c.timeInMillis }
    fun monthStartMs(): Long { val c = Calendar.getInstance(); c.set(Calendar.DAY_OF_MONTH, 1); c.set(Calendar.HOUR_OF_DAY, 0); c.set(Calendar.MINUTE, 0); c.set(Calendar.SECOND, 0); c.set(Calendar.MILLISECOND, 0); return c.timeInMillis }
    fun weekEndMs(): Long = weekStartMs() + 7 * 86_400_000L
    fun monthEndMs(): Long { val c = Calendar.getInstance(); c.timeInMillis = monthStartMs(); c.add(Calendar.MONTH, 1); return c.timeInMillis }
}
