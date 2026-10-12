package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — no Android imports. The adaptive coaching engine.
 *
 * Design rules (from the brief, all enforced here and covered by tests):
 *  - Cadence instructions use cadence only; effort instructions use HR or verified power only — never confuse the two.
 *  - Measurements are smoothed (rolling mean) before any decision.
 *  - Heart rate lags effort, so an effort cue requires the smoothed value to stay out of band for [effortHoldMs].
 *  - A minimum interval [minAlertMs] separates spoken/changed cues, and the same cue is not repeated needlessly.
 *  - Nothing is invented: if the signal a mode needs is absent, the engine says so (NO_HR / NO_POWER) rather than guessing.
 *  - Power is only used when > 0 (a power meter reads 0 unloaded), so coasting never drives an effort cue.
 */
enum class CoachMode { FREE, CADENCE, ZONE2, ENDURANCE, INTERVAL }

enum class EffortSource { AUTO, HEART_RATE, POWER }

enum class CueType { NONE, KEEP_IT_UP, PEDAL_FASTER, PEDAL_SLOWER, EASE_OFF, PUSH_HARDER, RECOVER, WORK, NO_HR, NO_POWER, WARMUP }

data class CoachCue(val type: CueType, val headline: String, val detail: String, val spoken: String) {
    companion object { val NONE = CoachCue(CueType.NONE, "", "", "") }
}

data class CoachConfig(
    val mode: CoachMode = CoachMode.FREE,
    val cadenceLow: Int = 85,
    val cadenceHigh: Int = 95,
    val effortSource: EffortSource = EffortSource.AUTO,
    val targetPowerZone: Int = 2,     // for ZONE2/ENDURANCE when using power
    val targetHrZone: Int = 2,
    val ftpW: Int = 200,
    val maxHr: Int = 185,
    val minAlertMs: Long = 10_000,
    val effortHoldMs: Long = 8_000,   // HR must stay out of band this long before an effort cue (HR lag)
    val smoothingMs: Long = 5_000,
)

/** Work/rest interval plan; times in seconds. targetZone applies during work. */
data class IntervalPlan(val workSec: Int = 240, val restSec: Int = 120, val repeats: Int = 4)

class CoachEngine(var config: CoachConfig = CoachConfig()) {
    private val cadWin = ArrayDeque<Pair<Long, Int>>()
    private val effortWin = ArrayDeque<Pair<Long, Int>>()   // HR or power, whichever drives effort
    private var lastCueAtMs = 0L
    private var lastType = CueType.NONE
    private var outOfBandSinceMs: Long? = null
    private var lastDirection = 0   // -1 ease, +1 push, 0 in-band

    var interval: IntervalPlan = IntervalPlan()
    private var intervalStartMs: Long? = null

    fun reset() {
        cadWin.clear(); effortWin.clear(); lastCueAtMs = 0; lastType = CueType.NONE
        outOfBandSinceMs = null; lastDirection = 0; intervalStartMs = null
    }

    private fun roll(win: ArrayDeque<Pair<Long, Int>>, now: Long, v: Int): Int {
        win.addLast(now to v)
        while (win.isNotEmpty() && now - win.first().first > config.smoothingMs) win.removeFirst()
        return (win.sumOf { it.second }.toDouble() / win.size + 0.5).toInt()
    }

    /** Call ~1 Hz with the latest readings (null = not available). Returns a cue to SHOW, or CoachCue.NONE. */
    fun update(nowMs: Long, cadenceRpm: Int?, hr: Int?, powerW: Int?): CoachCue {
        if (config.mode == CoachMode.FREE) return CoachCue.NONE

        // Interval mode: decide work vs rest by elapsed time, then coach effort toward the work target.
        var effectiveMode = config.mode
        var inRest = false
        if (config.mode == CoachMode.INTERVAL) {
            if (intervalStartMs == null) intervalStartMs = nowMs
            val t = ((nowMs - (intervalStartMs ?: nowMs)) / 1000).toInt()
            val cycle = interval.workSec + interval.restSec
            inRest = cycle > 0 && (t % cycle) >= interval.workSec
            effectiveMode = CoachMode.ZONE2   // reuse effort logic; target handled below
        }

        // --- cadence branch (CADENCE mode) ---
        if (config.mode == CoachMode.CADENCE) {
            if (cadenceRpm == null || cadenceRpm <= 0) return hold()
            val c = roll(cadWin, nowMs, cadenceRpm)
            return when {
                c < config.cadenceLow -> emit(nowMs, CueType.PEDAL_FASTER, "PEDAL FASTER", "Lift cadence toward ${config.cadenceLow}-${config.cadenceHigh} rpm", "Pedal faster", +1)
                c > config.cadenceHigh -> emit(nowMs, CueType.PEDAL_SLOWER, "PEDAL SLOWER", "Ease cadence toward ${config.cadenceLow}-${config.cadenceHigh} rpm", "Pedal slower", -1)
                else -> emit(nowMs, CueType.KEEP_IT_UP, "KEEP IT UP", "Cadence on target (${c} rpm)", "Keep it up", 0)
            }
        }

        // --- effort branch (ZONE2 / ENDURANCE / INTERVAL) ---
        val useHr = when (config.effortSource) {
            EffortSource.HEART_RATE -> true
            EffortSource.POWER -> false
            EffortSource.AUTO -> hr != null && hr > 0
        }
        if (useHr) {
            if (hr == null || hr <= 0) return info(nowMs, CueType.NO_HR, "NO HEART RATE", "Connect a heart-rate sensor for Zone 2 coaching", "")
            val h = roll(effortWin, nowMs, hr)
            val z = HrZones.zone(h, config.maxHr)
            val target = if (config.mode == CoachMode.ENDURANCE) 3 else config.targetHrZone
            return effortCue(nowMs, z, target, inRest, byHr = true)
        } else {
            if (powerW == null || powerW <= 0) {
                // Power unavailable or coasting: can't judge effort honestly.
                return if (config.effortSource == EffortSource.POWER)
                    info(nowMs, CueType.NO_POWER, "PEDAL UNDER LOAD", "Power reads 0 with no load — effort coaching needs pedaling resistance", "")
                else info(nowMs, CueType.NO_HR, "NO EFFORT SIGNAL", "Connect a heart-rate sensor, or pedal under load for power-based coaching", "")
            }
            val p = roll(effortWin, nowMs, powerW)
            val z = PowerZones.zone(p, config.ftpW)
            val target = if (config.mode == CoachMode.ENDURANCE) 3 else config.targetPowerZone
            return effortCue(nowMs, z, target, inRest, byHr = false)
        }
    }

    private fun effortCue(now: Long, zone: Int, target: Int, inRest: Boolean, byHr: Boolean): CoachCue {
        if (inRest) { outOfBandSinceMs = null; return emit(now, CueType.RECOVER, "RECOVER", "Easy spin — recovery interval", "Recover", 0) }
        val dir = when { zone > target -> -1; zone < target -> +1; else -> 0 }
        if (dir == 0) { outOfBandSinceMs = null; return emit(now, CueType.KEEP_IT_UP, "KEEP IT UP", "Effort on target (zone $zone)", "Keep it up", 0) }
        // HR lags, so require the out-of-band condition to persist before alerting.
        if (outOfBandSinceMs == null || dir != lastDirection) { outOfBandSinceMs = now; lastDirection = dir }
        val held = now - (outOfBandSinceMs ?: now)
        val holdNeeded = if (byHr) config.effortHoldMs else 2_000L
        if (held < holdNeeded) return hold()
        return if (dir < 0) emit(now, CueType.EASE_OFF, "EASE OFF", "Above target — zone $zone, aim for $target", "Ease off", -1)
        else emit(now, CueType.PUSH_HARDER, "PUSH A LITTLE HARDER", "Below target — zone $zone, aim for $target", "Push a little harder", +1)
    }

    /** Keep showing the last cue without resetting its timer (no new alert). */
    private fun hold(): CoachCue = CoachCue.NONE

    private fun info(now: Long, type: CueType, head: String, detail: String, spoken: String): CoachCue {
        if (type == lastType && now - lastCueAtMs < minInfoRepeatMs) return CoachCue.NONE
        lastType = type; lastCueAtMs = now
        return CoachCue(type, head, detail, spoken)
    }

    private fun emit(now: Long, type: CueType, head: String, detail: String, spoken: String, dir: Int): CoachCue {
        lastDirection = dir
        // Suppress repeats and respect the minimum interval between changed cues.
        if (type == lastType && now - lastCueAtMs < minSameRepeatMs) return CoachCue.NONE
        if (type != lastType && now - lastCueAtMs < config.minAlertMs) return CoachCue.NONE
        lastType = type; lastCueAtMs = now
        return CoachCue(type, head, detail, spoken)
    }

    companion object { const val minSameRepeatMs = 20_000L; const val minInfoRepeatMs = 30_000L }
}
