package com.rashed.bikesensordoctor.ride

import com.rashed.bikesensordoctor.core.XdsSample
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlin.math.PI
import kotlin.math.sin

/**
 * SIMULATED sensor source for testing the whole app without hardware: a scripted 60-minute ride (power, cadence,
 * heart rate) fed through the real sample path at 1 Hz of *engine* time. With the engine clock accelerated the
 * ride plays faster. Every ride recorded this way is tagged SIMULATED and never counts on a real leaderboard.
 * This proves the app's logic and screens, not the XDS meter or an HR strap.
 */
class RideSimulator(private val engine: RideEngine, val profile: Profile) {
    enum class Profile(val label: String) {
        STEADY_Z2("Steady Zone 2 ride"),          // mostly inside the band, a few excursions
        HARD_START("Hard start, then settles"),    // above target for the first 10 min
        DROPOUTS("Sensor drop-outs"),              // power/cadence gaps and an HR loss
        NO_HR("No heart-rate strap"),             // power-only
        EXTREMES("Layout test: 999 W · 199 bpm · 120 rpm"),   // biggest values the gauges must still show cleanly
        CADENCE_ONLY("Cadence only (no power, no strap)"),     // v0.11: a cadence sensor without power — the coach must still work from cadence, speed and time
        POWER_ONLY("Power + cadence, no strap"),               // v0.11: Rashed's current setup — relative-effort coaching, FTP only an assumption
    }

    private var job: Job? = null
    @Volatile private var tSec = 0
    private var startVirtualMs = 0L

    /** Emits exactly one sample per second of ENGINE time, catching up after scheduler jitter, so the link monitor never sees false gaps at high speed. */
    fun start() {
        startVirtualMs = engine.now()
        engine.simNoPower = profile == Profile.CADENCE_ONLY
        job = engine.scope.launch {
            while (isActive) {
                val target = ((engine.now() - startVirtualMs) / 1000).toInt()
                var n = 0
                while (tSec <= target && n < 120) { step(tSec, startVirtualMs + tSec * 1000L); tSec++; n++ }
                delay(if (engine.clockSpeed > 1) 40 else 250)
            }
        }
    }
    fun stop() { job?.cancel(); job = null; engine.simulatedHr = null; engine.simNoPower = false }
    /** Ride started: the script restarts from minute 0 so the planned hour lines up with the ride clock. */
    fun restart() { tSec = 0; startVirtualMs = engine.now() }

    /** Deterministic curves; values depend only on the second so tests are repeatable. */
    private fun step(t: Int, now: Long) {
        val m = t / 60.0
        val p = engine.setup
        val hrLo = p?.hrTargetLo ?: 111; val hrHi = p?.hrCap ?: 129
        val ftp = p?.ftp ?: 200
        var power: Int; var cad: Int; var hr: Int?
        when (profile) {
            Profile.STEADY_Z2 -> {
                val ramp = if (m < 6) m / 6 else 1.0
                val base = (hrLo + hrHi) / 2.0 + 3 * sin(2 * PI * m / 7)
                hr = (95 + (base - 95) * ramp + (if (m in 25.0..28.0) 12 else 0)).toInt()
                power = ((0.65 * ftp) * (0.75 + 0.25 * ramp) + 12 * sin(2 * PI * t / 40.0)).toInt()
                cad = 86 + (4 * sin(2 * PI * t / 23.0)).toInt() + (if (m in 40.0..42.0) -14 else 0)
            }
            Profile.HARD_START -> {
                hr = (if (m < 10) hrHi + 12 else if (m < 50) (hrLo + hrHi) / 2 else hrLo + 2).toInt() + (2 * sin(2 * PI * m / 3)).toInt()
                power = (if (m < 10) 0.95 * ftp else 0.65 * ftp).toInt() + (10 * sin(2 * PI * t / 30.0)).toInt()
                cad = 90 + (3 * sin(2 * PI * t / 19.0)).toInt()
            }
            Profile.DROPOUTS -> {
                // meter silent 2:00–2:30, 15:00–15:30 and 33:00–34:00 (power AND cadence missing — one device); strap silent 3:30–4:00 and 20:00–23:00
                val gap = (m in 2.0..2.5) || (m in 15.0..15.5) || (m in 33.0..34.0)
                if (gap) { engine.simulatedHr = ((hrLo + hrHi) / 2 + 2 * sin(2 * PI * m / 5)).toInt(); return }   // no packets at all: the link monitor must record a gap, the app must not crash
                hr = if (m in 3.5..4.0 || m in 20.0..23.0) null else ((hrLo + hrHi) / 2 + 2 * sin(2 * PI * m / 5)).toInt()
                power = (0.62 * ftp + 15 * sin(2 * PI * t / 37.0)).toInt()
                cad = if (m in 45.0..46.0) 0 else 84
            }
            Profile.NO_HR -> {
                hr = null
                power = (if (m < 5) 0.4 * ftp else if (m in 30.0..35.0) 0.85 * ftp else 0.65 * ftp).toInt() + (8 * sin(2 * PI * t / 29.0)).toInt()
                cad = 88
            }
            Profile.EXTREMES -> { hr = 199; power = 999; cad = 120 }
            Profile.CADENCE_ONLY -> { hr = null; power = 0; cad = 84 + (3 * sin(2 * PI * t / 23.0)).toInt() + (if (m in 12.0..14.0) -20 else 0) }   // power is dropped by the engine (simNoPower)
            Profile.POWER_ONLY -> { hr = null; power = (if (m < 6) 0.5 * ftp else if (m in 25.0..29.0) 0.52 * ftp else 0.68 * ftp).toInt() + (8 * sin(2 * PI * t / 31.0)).toInt() + (if (m in 40.0..40.2) 160 else 0); cad = 86 + (3 * sin(2 * PI * t / 19.0)).toInt() }
        }
        // motion for the top strip and the results page (SIMULATED): rolling speed with the same coasts, tiny rollers
        val moving = if (profile == Profile.CADENCE_ONLY) cad > 0 else (power > 0 && cad > 0)   // cadence-only: no watts, but the bike is moving while the cranks turn
        val speed = if (profile == Profile.EXTREMES) 59.9 else if (!moving) 0.0 else 24.0 + 4 * sin(2 * PI * m / 6.5) + 2 * sin(2 * PI * t / 41.0)
        engine.simMotion(if (m >= 60 && profile != Profile.EXTREMES) 0.0 else speed, 0.08 * sin(2 * PI * m / 9.0))
        if (m >= 60) { power = 0; cad = 0 }   // the planned hour is over: coasting
        if (t % 300 == 299) { power = 0; cad = 0 }   // a short coast every 5 min (0 W must read as COASTING, not "below target")
        val angle = (t * 7) % 360
        engine.simulatedHr = hr
        engine.injectSample(XdsSample(powerW = power.coerceAtLeast(0), leftW = power / 2, rightW = power - power / 2, cadenceSignedRpm = cad, crankAngleDeg = angle, errorCode = 0), now)
    }
}
