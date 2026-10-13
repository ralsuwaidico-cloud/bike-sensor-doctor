package com.rashed.bikesensordoctor.core

import kotlin.math.pow

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
        const val WINDOW_30S_MS = 30000L
        const val STALE_MS = 4000L
    }

    enum class State { IDLE, RUNNING, PAUSED, FINISHED }

    /**
     * P0: distinguishes a VALID zero from missing data.
     *  FRESH    packet ≤ STALE_MS old and the rider is producing power or turning the cranks
     *  COASTING packet ≤ STALE_MS old, 0 W and cranks still — a real, trustworthy zero
     *  STALE    last packet older than STALE_MS — values must be shown as "—", never held
     *  NONE     no packet ever received in this session
     */
    enum class SignalState { FRESH, COASTING, STALE, NONE }

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

    // Normalized Power (Coggan): 30 s rolling mean of power, raised to the 4th power, averaged, 4th root.
    // Accumulated once per RUNNING sample after the first 30 s of data exist. VI = NP / average power.
    private val np30 = ArrayDeque<Pair<Long, Int>>()
    private var npSum4 = 0.0
    private var npCount = 0L

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
        np30.clear(); npSum4 = 0.0; npCount = 0
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
        // normalized-power accumulator: 30 s rolling mean^4, once the window is full
        np30.addLast(nowMs to s.powerW)
        while (np30.isNotEmpty() && nowMs - np30.first().first > WINDOW_30S_MS) np30.removeFirst()
        if (nowMs - np30.first().first >= WINDOW_30S_MS - 1500) {   // window spans ~30 s (allows 1 Hz jitter)
            val mean = np30.sumOf { it.second }.toDouble() / np30.size
            npSum4 += mean * mean * mean * mean; npCount++
        }
        if (s.rotating) {
            cadenceSum += s.cadenceRpm; cadenceCount++
            if (s.cadenceRpm > maxCadenceRpm) maxCadenceRpm = s.cadenceRpm
            if (s.backwards) backwardsSamples++
        }
    }

    private fun fresh(nowMs: Long) = lastSampleMs?.let { nowMs - it <= STALE_MS } == true

    fun signalState(nowMs: Long): SignalState {
        val l = last ?: return SignalState.NONE
        if (!fresh(nowMs)) return SignalState.STALE
        return if (l.powerW > 0 || l.rotating) SignalState.FRESH else SignalState.COASTING
    }

    /** Milliseconds since the last accepted packet, or null if none yet. */
    fun sinceLastSampleMs(nowMs: Long): Long? = lastSampleMs?.let { nowMs - it }

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

    /** Normalized Power in W, or null until 30 s of running data exist. */
    val normalizedPowerW: Int? get() = if (npCount == 0L) null else ((npSum4 / npCount).pow(0.25) + 0.5).toInt()

    /** Variability Index = NP / average power (1.00 = perfectly steady). null until NP exists or avg is 0. */
    val variabilityIndex: Double? get() {
        val np = normalizedPowerW ?: return null
        return if (avgPowerW <= 0) null else np.toDouble() / avgPowerW
    }

    /** Energy in kJ = Σ(power × Δt). With ~1 Hz samples we use sample count × average as the estimate. */
    fun energyKj(nowMs: Long): Double = avgPowerW * (elapsedMs(nowMs) / 1000.0) / 1000.0

    /**
     * P0: serialise everything needed to continue this ride after an app restart. Plain key=value lines so the
     * ESP32 port can use the same format in flash. Rolling windows (3 s/10 s/30 s) are intentionally not saved —
     * they rebuild within 30 s and must not be reconstructed from stale data.
     */
    fun snapshot(nowMs: Long): String {
        val running = state == State.RUNNING
        return listOf(
            "v=1", "state=${if (running) State.PAUSED else state}",   // always restore PAUSED: the rider confirms resume
            "accumulatedMs=${elapsedMs(nowMs)}", "startedAtMs=${startedAtMs ?: -1}",
            "sampleCount=$sampleCount", "rejectedCount=$rejectedCount", "powerSum=$powerSum", "maxPowerW=$maxPowerW",
            "cadenceSum=$cadenceSum", "cadenceCount=$cadenceCount", "maxCadenceRpm=$maxCadenceRpm", "backwardsSamples=$backwardsSamples",
            "npSum4=$npSum4", "npCount=$npCount",
        ).joinToString("\n")
    }

    /** Restores a [snapshot]. Returns false (and leaves this object untouched) if the text is not a valid snapshot. */
    fun restore(text: String): Boolean {
        val m = text.lines().mapNotNull { l -> l.indexOf('=').takeIf { it > 0 }?.let { l.substring(0, it) to l.substring(it + 1) } }.toMap()
        if (m["v"] != "1") return false
        val st = runCatching { State.valueOf(m["state"] ?: "") }.getOrNull() ?: return false
        if (st == State.IDLE) return false
        reset()
        state = st; runningSinceMs = null
        accumulatedMs = m["accumulatedMs"]?.toLongOrNull() ?: 0
        startedAtMs = m["startedAtMs"]?.toLongOrNull()?.takeIf { it >= 0 }
        sampleCount = m["sampleCount"]?.toIntOrNull() ?: 0; rejectedCount = m["rejectedCount"]?.toIntOrNull() ?: 0
        powerSum = m["powerSum"]?.toLongOrNull() ?: 0; maxPowerW = m["maxPowerW"]?.toIntOrNull() ?: 0
        cadenceSum = m["cadenceSum"]?.toLongOrNull() ?: 0; cadenceCount = m["cadenceCount"]?.toIntOrNull() ?: 0
        maxCadenceRpm = m["maxCadenceRpm"]?.toIntOrNull() ?: 0; backwardsSamples = m["backwardsSamples"]?.toIntOrNull() ?: 0
        npSum4 = m["npSum4"]?.toDoubleOrNull() ?: 0.0; npCount = m["npCount"]?.toLongOrNull() ?: 0
        return true
    }

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
    // ---- v0.8: what the leaderboard and post-ride analysis need (defaults keep old files readable) ----
    val distanceKm: Double = 0.0,
    val elevationGainM: Double = 0.0,
    val avgHr: Int = 0,
    val inZonePct: Int = -1,              // -1 = no target band was active
    val source: RideSource = RideSource.DEVICE,
    val riderId: String = "",
)
