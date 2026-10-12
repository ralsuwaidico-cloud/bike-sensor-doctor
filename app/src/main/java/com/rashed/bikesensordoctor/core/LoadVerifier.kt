package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — no Android imports. P0 "power under load" verification.
 *
 * The XDS reports 0 W whenever the cranks turn without resistance, so until real load has been seen the app
 * must treat power as UNVERIFIED. This test passes only on evidence, never on assumption:
 *   PASS ⇔ within a [WINDOW_MS] window there are ≥ [MIN_PACKETS] plausible packets with cadence > [MIN_CADENCE]
 *          AND power ≥ [MIN_POWER_W] at the same time (same packet).
 * Spinning at 0 W for any length of time can never pass. The result records the max watts seen so the rider can
 * judge whether the number is credible for the effort made.
 */
class LoadVerifier(private val startMs: Long) {
    companion object {
        const val WINDOW_MS = 60_000L
        const val MIN_PACKETS = 10
        const val MIN_CADENCE = 30
        const val MIN_POWER_W = 40
    }

    enum class Status { WAITING, SPINNING_NO_LOAD, PASS, TIMEOUT }

    data class Result(val status: Status, val loadedPackets: Int, val totalPackets: Int, val maxPowerW: Int, val maxCadenceRpm: Int, val elapsedMs: Long) {
        val passed get() = status == Status.PASS
        fun message(): String = when (status) {
            Status.WAITING -> "Waiting for pedaling… turn the cranks against real resistance."
            Status.SPINNING_NO_LOAD -> "Cranks are turning but power is 0 W — add resistance (ride on the road or a trainer, not free-spinning)."
            Status.PASS -> "PASS — $loadedPackets packets under load, max $maxPowerW W at up to $maxCadenceRpm rpm."
            Status.TIMEOUT -> "Not verified: in 60 s only $loadedPackets packet(s) showed power ≥ $MIN_POWER_W W while pedaling (max seen $maxPowerW W)."
        }
    }

    private var total = 0
    private var loaded = 0
    private var maxP = 0
    private var maxC = 0

    fun onSample(s: XdsSample, nowMs: Long) {
        if (!s.plausible || nowMs - startMs > WINDOW_MS) return
        total++
        if (s.powerW > maxP) maxP = s.powerW
        if (s.cadenceRpm > maxC) maxC = s.cadenceRpm
        if (s.cadenceRpm > MIN_CADENCE && s.powerW >= MIN_POWER_W) loaded++
    }

    fun result(nowMs: Long): Result {
        val el = nowMs - startMs
        val status = when {
            loaded >= MIN_PACKETS -> Status.PASS
            el > WINDOW_MS -> Status.TIMEOUT
            maxC > MIN_CADENCE && maxP < MIN_POWER_W -> Status.SPINNING_NO_LOAD
            else -> Status.WAITING
        }
        return Result(status, loaded, total, maxP, maxC, el)
    }
}
