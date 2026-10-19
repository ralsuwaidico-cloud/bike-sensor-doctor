package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — automatic power-meter verification (v0.11).
 *
 * Establishes DATA CONSISTENCY of the meter, not measurement accuracy, and is independent of FTP: a meter can be VERIFIED
 * while FTP is UNKNOWN. Fed once per second with the current readings; never fed from a simulated source. Criteria:
 *  - ≥ 10 min of plausible pedalling packets (20–1500 W with 30–150 rpm),
 *  - ≥ 3 coasting episodes (0 W and 0 rpm for ≥ 3 s) that follow pedalling — the zero behaviour is correct,
 *  - pedalling consistency: when the cranks turn ≥ 40 rpm, power is > 0 on ≥ 95 % of seconds,
 *  - continuity: link quality ≥ 90 % over the observation, at most 3 disconnections,
 *  - no impossible values (> 2500 W, > 220 rpm, negative).
 * An impossible value or a run of silent cranks resets the pedalling count (consistency is judged on fresh evidence).
 */
class MeterVerification {
    var pedallingSec = 0; private set
    var coastEpisodes = 0; private set
    var impossible = 0; private set
    var disconnects = 0; private set
    private var crankSec = 0; private var crankWithPowerSec = 0
    private var coastRun = 0; private var pedalledSinceCoast = false
    var verified = false; private set
    var reason = "collecting evidence"; private set

    /** @param powerW null = missing this second; @param cadRpm null = missing; @param linkQualityPct current link quality. */
    fun tick(powerW: Int?, cadRpm: Int?, linkQualityPct: Int?, simulated: Boolean) {
        if (simulated || verified) return
        if (powerW == null || cadRpm == null) { coastRun = 0; return }
        if (powerW > 2500 || powerW < 0 || cadRpm > 220 || cadRpm < 0) { impossible++; pedallingSec = 0; reason = "impossible value ($powerW W, $cadRpm rpm)"; coastRun = 0; return }
        if (powerW in 20..1500 && cadRpm in 30..150) { pedallingSec++; pedalledSinceCoast = true }
        if (cadRpm >= 40) { crankSec++; if (powerW > 0) crankWithPowerSec++ }
        if (powerW == 0 && cadRpm == 0) { coastRun++; if (coastRun == 3 && pedalledSinceCoast) { coastEpisodes++; pedalledSinceCoast = false } } else coastRun = 0
        val consistency = if (crankSec >= 60) crankWithPowerSec.toDouble() / crankSec else 1.0
        if (crankSec >= 60 && consistency < 0.95) { reason = "power missing while pedalling (${Math.round(consistency * 100)} %)"; return }
        val lq = linkQualityPct ?: 100
        reason = when {
            pedallingSec < 600 -> "pedalling evidence ${pedallingSec / 60} of 10 min"
            coastEpisodes < 3 -> "coasting checks $coastEpisodes of 3"
            lq < 90 -> "link quality $lq % (needs ≥ 90 %)"
            disconnects > 3 -> "$disconnects disconnections"
            else -> "consistent data: ${pedallingSec / 60} min pedalling, $coastEpisodes clean coasts, link $lq %"
        }
        if (pedallingSec >= 600 && coastEpisodes >= 3 && lq >= 90 && disconnects <= 3 && impossible == 0) verified = true
    }
    fun onDisconnect() { disconnects++ }
    fun reset() { pedallingSec = 0; coastEpisodes = 0; impossible = 0; disconnects = 0; crankSec = 0; crankWithPowerSec = 0; coastRun = 0; pedalledSinceCoast = false; verified = false; reason = "collecting evidence" }
}
