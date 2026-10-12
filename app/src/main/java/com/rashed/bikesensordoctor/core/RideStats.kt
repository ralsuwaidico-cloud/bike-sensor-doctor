package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — no Android imports. Ride statistics from a stream of XdsSample at ~1 Hz.
 *
 * Rules (also in docs/PORTING_SPEC.md):
 * - Only samples received while the ride is RUNNING are counted. PAUSED samples are ignored.
 * - Riding time accumulates only while RUNNING (wall-clock, supplied by the caller — testable).
 * - 3-second power = mean of the samples received in the last 3000 ms (not a fixed count: packets can be lost).
 * - Average power = sum of power samples / number of samples (includes zero-power coasting samples, like Garmin).
 * - Cadence average excludes zero (coasting) samples; max cadence uses magnitude.
 * - A sample is REJECTED (not counted) if !plausible, so a corrupt packet cannot inflate max power.
 * - If no sample has arrived for [STALE_MS], live values are reported as null ("—"), never held or invented.
 */
class RideStats {
    companion object {
        const val WINDOW_3S_MS = 3000L
        const val WINDOW_10S_MS = 10000L
        const val STALE_MS = 4000L
    }

    enum class State { IDLE, RUNNING, PAUSED, FINISHED }

    var state: State = State.IDLE
        private set

    private var runningSinceMs: Long? = null
    private var accumulatedMs: Long = 0
    var startedAtMs: Long? = null
        private set

    private val window = ArrayDeque<Pair<Long, Int>>()  // (timestamp, power)
    private var lastSampleMs: Long? = null
    private var last: XdsSample? = null

    var sampleCount = 0; private set
    var rejectedCount = 0; private set
    private var powerSum = 0L
    var maxPowerW = 0; private set
    private var cadenceSum = 0L
    private var cadenceCount = 0
    var maxCadenceRpm = 0; private set
    var backwardsSamples = 0; private set

    fun start(nowMs: Long) {
        if (state == State.IDLE || state == State.FINISHED) {
            reset(); startedAtMs = nowMs
        }
        if (state != State.RUNNING) { runningSinceMs = nowMs; state = State.RUNNING }
    }

    fun pause(nowMs: Long) {
        if (state == State.RUNNING) { accumulatedMs += nowMs - (runningSinceMs ?: nowMs); runningSinceMs = null; state = State.PAUSED }
    }

    fun resume(nowMs: Long) { if (state == State.PAUSED) start(nowMs) }

    fun finish(nowMs: Long) {
        pause(nowMs); state = State.FINISHED
    }

    fun reset() {
        state = State.IDLE; runningSinceMs = null; accumulatedMs = 0; startedAtMs = null
        window.clear(); lastSampleMs = null; last = null
        sampleCount = 0; rejectedCount = 0; powerSum = 0; maxPowerW = 0; cadenceSum = 0; cadenceCount = 0; maxCadenceRpm = 0; backwardsSamples = 0
    }

    fun elapsedMs(nowMs: Long): Long = accumulatedMs + (runningSinceMs?.let { nowMs - it } ?: 0L)

    /** Feed every decoded sample here, in all states; live display uses it, statistics only while RUNNING. */
    fun onSample(s: XdsSample, nowMs: Long) {
        if (!s.plausible) { rejectedCount++; return }
        last = s; lastSampleMs = nowMs
        window.addLast(nowMs to s.powerW)
        while (window.isNotEmpty() && nowMs - window.first().first > WINDOW_10S_MS) window.removeFirst()
        if (state != State.RUNNING) return
        sampleCount++
        powerSum += s.powerW
        if (s.powerW > maxPowerW) maxPowerW = s.powerW
        if (s.rotating) {
            cadenceSum += s.cadenceRpm; cadenceCount++
            if (s.cadenceRpm > maxCadenceRpm) maxCadenceRpm = s.cadenceRpm
            if (s.backwards) backwardsSamples++
        }
    }

    private fun fresh(nowMs: Long) = lastSampleMs?.let { nowMs - it <= STALE_MS } == true

    /** Live instantaneous power, or null when no fresh sample. */
    fun livePowerW(nowMs: Long): Int? = if (fresh(nowMs)) last?.powerW else null
    fun liveCadenceRpm(nowMs: Long): Int? = if (fresh(nowMs)) last?.cadenceRpm else null
    fun liveBackwards(nowMs: Long): Boolean = fresh(nowMs) && last?.backwards == true
    fun liveCrankAngle(nowMs: Long): Int? = if (fresh(nowMs)) last?.crankAngleDeg else null

    fun power3sW(nowMs: Long): Int? = rollingPower(nowMs, WINDOW_3S_MS)
    fun power10sW(nowMs: Long): Int? = rollingPower(nowMs, WINDOW_10S_MS)

    private fun rollingPower(nowMs: Long, windowMs: Long): Int? {
        if (!fresh(nowMs)) return null
        val recent = window.filter { nowMs - it.first <= windowMs }
        return if (recent.isEmpty()) null else (recent.sumOf { it.second }.toDouble() / recent.size + 0.5).toInt()
    }

    val avgPowerW: Int get() = if (sampleCount == 0) 0 else (powerSum.toDouble() / sampleCount + 0.5).toInt()
    val avgCadenceRpm: Int get() = if (cadenceCount == 0) 0 else (cadenceSum.toDouble() / cadenceCount + 0.5).toInt()

    /** Energy in kJ = Σ(power × Δt). With ~1 Hz samples we use sample count × average as the estimate. */
    fun energyKj(nowMs: Long): Double = avgPowerW * (elapsedMs(nowMs) / 1000.0) / 1000.0

    fun summary(nowMs: Long) = RideSummary(
        startedAtMs = startedAtMs ?: 0L,
        durationMs = elapsedMs(nowMs),
        avgPowerW = avgPowerW, maxPowerW = maxPowerW,
        avgCadenceRpm = avgCadenceRpm, maxCadenceRpm = maxCadenceRpm,
        energyKj = energyKj(nowMs), samples = sampleCount, rejected = rejectedCount, backwardsSamples = backwardsSamples,
    )
}

data class RideSummary(
    val startedAtMs: Long,
    val durationMs: Long,
    val avgPowerW: Int,
    val maxPowerW: Int,
    val avgCadenceRpm: Int,
    val maxCadenceRpm: Int,
    val energyKj: Double,
    val samples: Int,
    val rejected: Int,
    val backwardsSamples: Int,
)
