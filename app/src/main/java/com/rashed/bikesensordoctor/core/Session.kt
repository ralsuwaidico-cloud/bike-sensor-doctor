package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — no Android imports. Workout phase model (P1/P2).
 *
 * WARMUP → MAIN → COOLDOWN, driven by ride elapsed time and an explicit "cool down now" request.
 * Interval work/rest (MAIN ↔ RECOVERY) is decided inside CoachEngine from its IntervalPlan, because only the
 * engine knows when the plan started. Deterministic: same inputs → same phase.
 */
enum class Phase { WARMUP, MAIN, RECOVERY, COOLDOWN }

data class SessionPlan(
    val warmupSec: Int = 300,       // 0 disables the warm-up phase
    val cooldownSec: Int = 300,     // length of the cool-down once requested / at the end of a planned ride
    val plannedSec: Int? = null,    // planned ride length; the cool-down starts automatically cooldownSec before it
)

object Session {
    /**
     * @param elapsedMs riding time (paused time excluded)
     * @param cooldownRequestedAtMs riding-time at which the rider pressed "Cool down", or null
     */
    fun phaseAt(plan: SessionPlan, elapsedMs: Long, cooldownRequestedAtMs: Long?): Phase = when {
        cooldownStartMs(plan, cooldownRequestedAtMs)?.let { elapsedMs >= it } == true -> Phase.COOLDOWN
        elapsedMs < plan.warmupSec * 1000L -> Phase.WARMUP
        else -> Phase.MAIN
    }

    /** Riding-time (ms) at which the cool-down starts: the earlier of a manual request and the planned end minus cooldownSec. */
    fun cooldownStartMs(plan: SessionPlan, cooldownRequestedAtMs: Long?): Long? {
        val planned = plan.plannedSec?.let { maxOf(plan.warmupSec, it - plan.cooldownSec) * 1000L }
        return listOfNotNull(cooldownRequestedAtMs, planned).minOrNull()
    }

    /** Seconds left in the warm-up, or 0. */
    fun warmupRemainingSec(plan: SessionPlan, elapsedMs: Long): Int =
        ((plan.warmupSec * 1000L - elapsedMs) / 1000).coerceAtLeast(0).toInt()
}
