package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — no Android imports. The active target bands of a workout, per phase (v0.8 rules from the demo).
 *
 *  - WARMUP: ceiling rises gradually from (Z2 low − 10) to the Z2 top over the warm-up, so heart rate may climb.
 *  - MAIN: the workout band (Z2 low … personal ceiling).
 *  - COOLDOWN: ceiling falls gradually from the Z2 top back to (Z2 low − 10).
 *  - RECOVERY (interval rest): Zone 1.
 * Cadence range is constant. Power bands are null when power is not coached (FTP unknown): nothing is invented.
 */
data class WorkoutPlan(
    val hrLo: Int, val hrHi: Int,
    val pwLo: Int?, val pwHi: Int?,
    val cadLo: Int, val cadHi: Int,
    val ftp: Int,
    val warmupSec: Int, val cooldownSec: Int,
    /** Planned ride length in seconds; null = open-ended (cool-down only when requested). */
    val plannedSec: Int? = null,
    val ramps: Boolean = true,
)

data class ActiveTargets(
    val hrLo: Int, val hrHi: Int,
    val pwLo: Int?, val pwHi: Int?,
    val cadLo: Int, val cadHi: Int,
    val label: String,
)

object WorkoutTargets {
    private fun r(x: Double) = Math.round(x).toInt()

    /**
     * @param elapsedSec riding time; @param cooldownStartSec riding-time at which the cool-down began (for the ramp)
     */
    fun forPhase(p: WorkoutPlan, phase: Phase, elapsedSec: Int, cooldownStartSec: Int?): ActiveTargets {
        val floor = minOf(105, p.hrLo - 10)
        val pwFloor = p.pwLo?.let { r(0.35 * p.ftp) }
        val pwMid = p.pwHi?.let { r(0.5 * p.ftp) }
        return when (phase) {
            Phase.WARMUP -> {
                val u = if (p.ramps && p.warmupSec > 0) (elapsedSec.toDouble() / p.warmupSec).coerceIn(0.0, 1.0) else 0.0
                ActiveTargets(floor, r((p.hrLo - 10) + (p.hrHi - (p.hrLo - 10)) * u),
                    pwFloor, if (pwMid != null && p.pwHi != null) r(pwMid + (p.pwHi - pwMid) * u) else null,
                    p.cadLo, p.cadHi, if (p.ramps) "WARM-UP RAMP" else "WARM-UP Z1")
            }
            Phase.COOLDOWN -> {
                val start = cooldownStartSec ?: elapsedSec
                val u = if (p.ramps && p.cooldownSec > 0) ((elapsedSec - start).toDouble() / p.cooldownSec).coerceIn(0.0, 1.0) else 0.0
                ActiveTargets(floor, r(p.hrHi - (p.hrHi - (p.hrLo - 10)) * u),
                    pwFloor, if (pwMid != null && p.pwHi != null) r(p.pwHi - (p.pwHi - pwMid) * u) else null,
                    p.cadLo, p.cadHi, if (p.ramps) "COOL-DOWN RAMP" else "COOL-DOWN Z1")
            }
            Phase.RECOVERY -> ActiveTargets(floor, p.hrLo - 1, pwFloor, pwMid, p.cadLo, p.cadHi, "RECOVERY Z1")
            Phase.MAIN -> ActiveTargets(p.hrLo, p.hrHi, p.pwLo, p.pwHi, p.cadLo, p.cadHi, "MAIN")
        }
    }

    /** Riding-time at which the cool-down starts for a planned ride, or null when open-ended. */
    fun plannedCooldownStartSec(p: WorkoutPlan): Int? = p.plannedSec?.let { maxOf(p.warmupSec, it - p.cooldownSec) }
}
