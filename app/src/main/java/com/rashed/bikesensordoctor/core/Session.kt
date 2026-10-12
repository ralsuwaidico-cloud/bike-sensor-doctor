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
    val cooldownSec: Int = 300,     // length of the cool-down once requested (informational)
)

object Session {
    /**
     * @param elapsedMs riding time (paused time excluded)
     * @param cooldownRequestedAtMs riding-time at which the rider pressed "Cool down", or null
     */
    fun phaseAt(plan: SessionPlan, elapsedMs: Long, cooldownRequestedAtMs: Long?): Phase = when {
        cooldownRequestedAtMs != null && elapsedMs >= cooldownRequestedAtMs -> Phase.COOLDOWN
        elapsedMs < plan.warmupSec * 1000L -> Phase.WARMUP
        else -> Phase.MAIN
    }

    /** Seconds left in the warm-up, or 0. */
    fun warmupRemainingSec(plan: SessionPlan, elapsedMs: Long): Int =
        ((plan.warmupSec * 1000L - elapsedMs) / 1000).coerceAtLeast(0).toInt()
}
