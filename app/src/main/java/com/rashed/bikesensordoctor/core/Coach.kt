package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — no Android imports. P1 multi-signal, deterministic coaching engine (v2).
 *
 * Specification: docs/ARCHITECTURE_V2.md §3. Verified by testvectors/coach (one .txt per scenario) (CoachVectorTest) — the same
 * vectors the ESP32-S3 C++ re-implementation must pass.
 *
 * Principles
 *  - Heart rate is the authority on effort when it is available; power confirms or anticipates it; cadence is a
 *    secondary hint that is only given when effort is in order. The three never contradict each other because a
 *    single priority ladder decides one cue per tick.
 *  - Never ask for MORE effort when HR is above target, when HR is below target but power is already on/above
 *    target (HR lag), during warm-up or cool-down, or on stale/absent data.
 *  - Smoothing (5 s), hold times (HR 8 s / power 2 s / cadence 5 s) and hysteresis (±2 % of max, ±3 rpm) stop
 *    flapping; emission spacing stops nagging.
 *  - Nothing is invented: a stale (> 4 s) or absent signal is simply unavailable.
 */
enum class CoachMode { FREE, CADENCE, ZONE2, ENDURANCE, INTERVAL }

/** Kept for settings compatibility: AUTO = HR when present else power; the v2 engine always uses both when it can. */
enum class EffortSource { AUTO, HEART_RATE, POWER }

enum class CueType { NONE, KEEP_IT_UP, PEDAL_FASTER, PEDAL_SLOWER, EASE_OFF, PUSH_HARDER, RECOVER, WORK, NO_HR, NO_POWER, WARMUP, COOLDOWN, QUIET }

/** @param reason machine-readable cause (e.g. HR_ABOVE, HR_LAG_HOLD) for logs and tests. */
data class CoachCue(val type: CueType, val headline: String, val detail: String, val spoken: String, val reason: String = "") {
    companion object { val NONE = CoachCue(CueType.NONE, "", "", "", "") }
}

data class CoachConfig(
    val mode: CoachMode = CoachMode.FREE,
    val cadenceEnabled: Boolean = true,
    val cadenceLow: Int = 85,
    val cadenceHigh: Int = 95,
    val effortSource: EffortSource = EffortSource.AUTO,
    val targetPowerZone: Int = 2,
    val targetHrZone: Int = 2,
    val ftpW: Int = 200,
    val maxHr: Int = 185,
    /** HR zone upper bounds as fractions of max HR (Z1..Z4; Z5 open). Editable in P2. */
    val hrZoneBounds: DoubleArray = doubleArrayOf(0.60, 0.70, 0.80, 0.90),
    val minAlertMs: Long = 10_000,      // a CHANGED cue needs this much time since the previous emission
    val sameRepeatMs: Long = 45_000,    // the SAME cue is not repeated sooner than this
    val keepRepeatMs: Long = 90_000,    // KEEP IT UP is the least urgent
    val keepHoldMs: Long = 5_000,       // ... and only after being on target this long (no cue while passing through)
    val infoRepeatMs: Long = 30_000,
    val effortHoldMs: Long = 8_000,     // HR must stay out of band this long (HR lag)
    val powerHoldMs: Long = 2_000,
    val surgeHoldMs: Long = 6_000,      // HR on target but power ≥ 1 zone above, this long → ease
    val cadenceHoldMs: Long = 5_000,
    val smoothingMs: Long = 5_000,
    val staleMs: Long = 4_000,
    val hysteresisFrac: Double = 0.02,  // ±2 % of max HR / FTP around a band edge
    val cadenceHysteresis: Int = 3,
    // ---- v0.8 (profile-driven) ----
    /** false ⇒ power is shown but never coached (FTP unknown). HR remains the authority. */
    val powerCoaching: Boolean = true,
    /** After entering MAIN from the warm-up, no PUSH for this long: heart rate is still responding. 0 = off. */
    val graceMs: Long = 0,
    /** After 3 unheeded repeats of the same cue, go QUIET until the cue changes or quietMs pass. */
    val backoff: Boolean = false,
    val quietMs: Long = 300_000,
)

/** Work/rest interval plan; times in seconds. targetZone applies during work. */
data class IntervalPlan(val workSec: Int = 240, val restSec: Int = 120, val repeats: Int = 4)

/** One reading with its freshness. value == null or fresh == false ⇒ unavailable. */
data class Signal(val value: Int?, val fresh: Boolean = true) {
    val available get() = fresh && value != null
    companion object { val NONE = Signal(null, false) }
}

data class CoachInput(
    val nowMs: Long,
    val phase: Phase = Phase.MAIN,
    val cadence: Signal = Signal.NONE,
    val hr: Signal = Signal.NONE,
    val power: Signal = Signal.NONE,
    /** Absolute target bands for this tick (workout + phase ramps). null ⇒ zone-based targets from the config. */
    val targets: ActiveTargets? = null,
)

class CoachEngine(var config: CoachConfig = CoachConfig()) {
    private enum class Band { BELOW, ON, ABOVE }

    /** Rolling-mean smoother that forgets everything when its signal goes stale. */
    private inner class Smoother {
        private val win = ArrayDeque<Pair<Long, Int>>()
        fun feed(now: Long, s: Signal): Int? {
            if (!s.available) { win.clear(); return null }
            win.addLast(now to s.value!!)
            while (win.isNotEmpty() && now - win.first().first > config.smoothingMs) win.removeFirst()
            return (win.sumOf { it.second }.toDouble() / win.size + 0.5).toInt()
        }
        fun clear() = win.clear()
    }

    /** Band tracker with hysteresis: a band only changes once the value is clearly past the edge. */
    private inner class BandTracker {
        var band: Band? = null; private set
        var sinceMs: Long = 0; private set
        fun update(now: Long, frac: Double?, lo: Double, hi: Double): Band? {
            if (frac == null) { band = null; return null }
            val h = config.hysteresisFrac
            val next = when (band) {
                null -> when { frac < lo -> Band.BELOW; frac > hi -> Band.ABOVE; else -> Band.ON }
                Band.BELOW -> if (frac >= lo + h) (if (frac > hi) Band.ABOVE else Band.ON) else Band.BELOW
                Band.ABOVE -> if (frac <= hi - h) (if (frac < lo) Band.BELOW else Band.ON) else Band.ABOVE
                Band.ON -> when { frac < lo - h -> Band.BELOW; frac > hi + h -> Band.ABOVE; else -> Band.ON }
            }
            if (next != band) { band = next; sinceMs = now }
            return next
        }
        fun held(now: Long, ms: Long) = band != null && now - sinceMs >= ms
        fun clear() { band = null }
    }

    private val cadS = Smoother(); private val hrS = Smoother(); private val pwS = Smoother()
    private val hrBand = BandTracker(); private val pwBand = BandTracker()
    private var cadState: Band? = null; private var cadSince = 0L

    private var lastType = CueType.NONE
    private var lastEmitMs = Long.MIN_VALUE / 2
    private var allGoodSince: Long? = null
    private var keepArmed = true          // KEEP IT UP fires on entering "all good"
    private var announcedPhase: Phase? = null
    private var surgeSince: Long? = null
    private var phaseSeen: Phase? = null; private var phaseSinceMs = 0L
    private var repeatCount = 0; private var quietSinceMs = 0L

    var interval: IntervalPlan = IntervalPlan()
    private var intervalStartMs: Long? = null

    fun reset() {
        cadS.clear(); hrS.clear(); pwS.clear(); hrBand.clear(); pwBand.clear(); cadState = null
        lastType = CueType.NONE; lastEmitMs = Long.MIN_VALUE / 2; allGoodSince = null; keepArmed = true
        announcedPhase = null; surgeSince = null; intervalStartMs = null
        phaseSeen = null; phaseSinceMs = 0; repeatCount = 0; quietSinceMs = 0
    }

    /** Compatibility entry point (MAIN phase, all signals fresh). */
    fun update(nowMs: Long, cadenceRpm: Int?, hr: Int?, powerW: Int?): CoachCue =
        update(CoachInput(nowMs, Phase.MAIN, Signal(cadenceRpm), Signal(hr), Signal(powerW)))

    /** Call ~1 Hz. Returns a cue to SHOW/SPEAK, or CoachCue.NONE when there is nothing new to say. */
    fun update(input: CoachInput): CoachCue {
        val c = config
        if (c.mode == CoachMode.FREE) return CoachCue.NONE
        val now = input.nowMs

        // ---- 1. smoothing (stale ⇒ unavailable) ----
        val cad = cadS.feed(now, input.cadence)
        val hrRaw = hrS.feed(now, input.hr)
        // 0 W is a valid COASTING reading but carries no effort information: it must neither drive a cue nor
        // drag the rolling mean down (otherwise the first loaded seconds after coasting read as "below target").
        val coasting = input.power.available && input.power.value == 0
        val pwRaw = pwS.feed(now, if (coasting) Signal.NONE else input.power)
        val useHr = when (c.effortSource) { EffortSource.HEART_RATE -> true; EffortSource.POWER -> false; EffortSource.AUTO -> true }
        val usePw = c.effortSource != EffortSource.HEART_RATE && c.powerCoaching
        val hr = if (useHr) hrRaw else null
        val pw = if (usePw && pwRaw != null && pwRaw > 0) pwRaw else null

        // ---- 2. phase (intervals split MAIN into work / rest) ----
        var phase = input.phase
        if (c.mode == CoachMode.INTERVAL && phase == Phase.MAIN) {
            if (intervalStartMs == null) intervalStartMs = now
            val t = ((now - intervalStartMs!!) / 1000).toInt()
            val cycle = interval.workSec + interval.restSec
            val done = cycle > 0 && interval.repeats > 0 && t >= cycle * interval.repeats
            phase = when {
                done -> Phase.COOLDOWN
                cycle > 0 && (t % cycle) >= interval.workSec -> Phase.RECOVERY
                else -> Phase.MAIN
            }
        }
        val targetZone = if (c.mode == CoachMode.ENDURANCE) 3 else c.targetPowerZone
        val targetHrZone = if (c.mode == CoachMode.ENDURANCE) 3 else c.targetHrZone
        if (phase != phaseSeen) { phaseSeen = phase; phaseSinceMs = now; repeatCount = 0 }
        val grace = c.graceMs > 0 && phase == Phase.MAIN && now - phaseSinceMs < c.graceMs

        // ---- 3. band states with hysteresis (absolute workout targets when given, else zone bounds) ----
        val tg = input.targets
        val (hLo, hHi) = if (tg != null) (tg.hrLo.toDouble() / c.maxHr) to (tg.hrHi.toDouble() / c.maxHr) else hrBounds(targetHrZone)
        val (pLo, pHi) = if (tg != null && tg.pwLo != null && tg.pwHi != null) (tg.pwLo.toDouble() / c.ftpW) to (tg.pwHi.toDouble() / c.ftpW) else powerBounds(targetZone)
        val hb = hrBand.update(now, hr?.let { it.toDouble() / c.maxHr }, hLo, hHi)
        val pb = pwBand.update(now, pw?.let { it.toDouble() / c.ftpW }, pLo, pHi)
        val bandText = if (tg != null) "${tg.hrLo}–${tg.hrHi} bpm" else "zone $targetHrZone"
        val hrZone = hr?.let { zoneOf(it.toDouble() / c.maxHr, c.hrZoneBounds) }
        val pwZone = pw?.let { PowerZones.zone(it, c.ftpW) }

        // ---- cadence mode: cadence only (effort is not coached, but HR safety still applies) ----
        if (c.mode == CoachMode.CADENCE) {
            safety(now, hb, hrZone, targetHrZone)?.let { return it }
            return cadenceCue(now, cad, phase) ?: keepIfGood(now, phase, cad != null)
        }

        // ---- 4. phase gates ----
        when (phase) {
            Phase.WARMUP -> {
                safety(now, hb, hrZone, targetHrZone)?.let { return it }
                return announce(now, phase, CueType.WARMUP, "WARM UP", "Easy spinning — effort coaching starts after the warm-up", "Warm up, easy spinning", "PHASE_WARMUP")
            }
            Phase.COOLDOWN -> {
                if (hb == Band.ABOVE && hrBand.held(now, c.effortHoldMs))
                    return if (tg != null) emit(now, CueType.EASE_OFF, "WIND DOWN", "Cool-down ceiling is now ${tg.hrHi} bpm and falling — ease the effort a little", "Wind down", "COOLDOWN_RAMP")
                    else emit(now, CueType.EASE_OFF, "EASE OFF", "Cool-down: let the heart rate come down", "Ease off", "COOLDOWN_HR_ABOVE")
                return announce(now, phase, CueType.COOLDOWN, "COOL DOWN", if (tg != null) "Last minutes: the ceiling comes down gradually. No more 'push' from here" else "Easy spinning to finish", "Cool down", "PHASE_COOLDOWN")
            }
            Phase.RECOVERY -> {
                if (pb == Band.ABOVE && pwBand.held(now, c.powerHoldMs)) return emit(now, CueType.EASE_OFF, "EASE OFF", "Recovery interval — spin easy", "Ease off, recovery", "RECOVERY_PW_ABOVE")
                return announce(now, phase, CueType.RECOVER, "RECOVER", "Easy spin — recovery interval", "Recover", "PHASE_RECOVERY")
            }
            Phase.MAIN -> { if (announcedPhase != Phase.MAIN) { announcedPhase = Phase.MAIN; keepArmed = true } }
        }

        // ---- 5. effort ladder (MAIN) ----
        val effort: CoachCue? = when {
            hr != null -> when (hb) {
                Band.ABOVE -> if (hrBand.held(now, c.effortHoldMs))
                    emit(now, CueType.EASE_OFF, "EASE OFF", "Heart rate $hr above target $bandText", "Ease off", "HR_ABOVE") else hold()
                Band.ON -> {
                    // power surging well above target while HR has not caught up yet → pre-empt the overshoot
                    val surging = pwZone != null && pwZone >= targetZone + 1 && pb == Band.ABOVE
                    if (surging) { if (surgeSince == null) surgeSince = now } else surgeSince = null
                    if (!surging) null
                    else if (now - (surgeSince ?: now) >= c.surgeHoldMs)
                        emit(now, CueType.EASE_OFF, "EASE OFF", "Power surging (zone $pwZone) — heart rate will follow", "Ease off, power is surging", "PW_SURGE")
                    else hold("PW_SURGE_HOLD")
                }
                Band.BELOW -> {
                    surgeSince = null
                    if (pb == Band.ON || pb == Band.ABOVE) hold("HR_LAG_HOLD")                   // never push: HR is catching up
                    else if (grace) hold("TRANSITION_GRACE")                                        // v0.8: just entered MAIN, HR still responding
                    else if (hrBand.held(now, c.effortHoldMs))
                        emit(now, CueType.PUSH_HARDER, "PUSH A LITTLE HARDER", "Heart rate $hr below target $bandText", "Push a little harder", "HR_BELOW")
                    else hold()
                }
                null -> null
            }
            pw != null -> when (pb) {
                Band.ABOVE -> if (pwBand.held(now, c.powerHoldMs)) emit(now, CueType.EASE_OFF, "EASE OFF", "Power above target — zone $pwZone, aim for $targetZone", "Ease off", "PW_ABOVE") else hold()
                Band.BELOW -> if (grace) hold("TRANSITION_GRACE") else if (pwBand.held(now, c.powerHoldMs)) emit(now, CueType.PUSH_HARDER, "PUSH A LITTLE HARDER", "Power below target — zone $pwZone, aim for $targetZone", "Push a little harder", "PW_BELOW") else hold()
                Band.ON, null -> null
            }
            else -> {
                if (coasting) hold("COASTING")
                else if (c.effortSource == EffortSource.POWER) info(now, CueType.NO_POWER, "PEDAL UNDER LOAD", "Power reads 0 with no load — effort coaching needs pedaling resistance", "", "NO_POWER")
                else info(now, CueType.NO_HR, "NO EFFORT SIGNAL", "Connect a heart-rate sensor, or pedal under load for power-based coaching", "", "NO_SIGNAL")
            }
        }
        if (effort != null) { if (effort.type != CueType.NONE) allGoodSince = null; return effort }

        // ---- 6. cadence hint (effort is in order and HR is not above) ----
        if (hb != Band.ABOVE) cadenceCue(now, cad, phase)?.let { if (it.type != CueType.NONE) allGoodSince = null; return it }

        // ---- 7. all good ----
        val effortKnown = hb == Band.ON || (hr == null && pb == Band.ON)
        return keepIfGood(now, phase, effortKnown)
    }

    // ---------------------------------------------------------------- helpers

    private fun hrBounds(zone: Int): Pair<Double, Double> {
        val b = config.hrZoneBounds
        val lo = if (zone <= 1) 0.0 else b[(zone - 2).coerceIn(0, b.size - 1)]
        val hi = if (zone - 1 < b.size) b[zone - 1] else 2.0
        return lo to hi
    }
    private fun powerBounds(zone: Int): Pair<Double, Double> {
        val up = doubleArrayOf(0.55, 0.75, 0.90, 1.05, 1.20, 1.50)
        val lo = if (zone <= 1) 0.0 else up[zone - 2]
        val hi = if (zone - 1 < up.size) up[zone - 1] else 9.0
        return lo to hi
    }
    private fun zoneOf(frac: Double, bounds: DoubleArray): Int { for (i in bounds.indices) if (frac <= bounds[i]) return i + 1; return bounds.size + 1 }

    /** HR two or more zones above target is never acceptable in any phase or mode. */
    private fun safety(now: Long, hb: Band?, hrZone: Int?, targetHrZone: Int): CoachCue? {
        if (hb == Band.ABOVE && hrZone != null && hrZone >= targetHrZone + 2 && hrBand.held(now, 5_000))
            return emit(now, CueType.EASE_OFF, "EASE OFF", "Heart rate zone $hrZone — well above target, back off", "Ease off", "HR_SAFETY")
        return null
    }

    private fun cadenceCue(now: Long, cad: Int?, phase: Phase): CoachCue? {
        val c = config
        if (!c.cadenceEnabled || cad == null || cad <= 0 || phase == Phase.COOLDOWN) { cadState = null; return null }
        val lo = c.cadenceLow; val hi = c.cadenceHigh
        val next = when (cadState) {
            Band.BELOW -> if (cad >= lo + c.cadenceHysteresis) Band.ON else Band.BELOW
            Band.ABOVE -> if (cad <= hi - c.cadenceHysteresis) Band.ON else Band.ABOVE
            else -> when { cad < lo - (if (cadState == Band.ON) c.cadenceHysteresis else 0) -> Band.BELOW; cad > hi + (if (cadState == Band.ON) c.cadenceHysteresis else 0) -> Band.ABOVE; else -> Band.ON }
        }
        if (next != cadState) { cadState = next; cadSince = now }
        if (now - cadSince < c.cadenceHoldMs) return if (next == Band.ON) null else hold()
        return when (next) {
            Band.BELOW -> emit(now, CueType.PEDAL_FASTER, "PEDAL FASTER", "Lift cadence toward $lo–$hi rpm", "Pedal faster", "CAD_LOW")
            Band.ABOVE -> emit(now, CueType.PEDAL_SLOWER, "PEDAL SLOWER", "Ease cadence toward $lo–$hi rpm", "Pedal slower", "CAD_HIGH")
            Band.ON -> null
        }
    }

    private fun keepIfGood(now: Long, phase: Phase, effortKnown: Boolean): CoachCue {
        if (phase != Phase.MAIN || !effortKnown) { allGoodSince = null; return CoachCue.NONE }
        if (allGoodSince == null) { allGoodSince = now; keepArmed = true }
        if (now - (allGoodSince ?: now) < config.keepHoldMs) return CoachCue.NONE
        val due = keepArmed || now - lastEmitMs >= config.keepRepeatMs
        if (!due) return CoachCue.NONE
        val cue = emit(now, CueType.KEEP_IT_UP, "KEEP IT UP", "Effort on target", "Keep it up", "ALL_GOOD")
        if (cue.type != CueType.NONE) keepArmed = false
        return cue
    }

    private fun hold(reason: String = ""): CoachCue = CoachCue.NONE

    private fun announce(now: Long, phase: Phase, type: CueType, head: String, detail: String, spoken: String, reason: String): CoachCue {
        if (announcedPhase == phase) return CoachCue.NONE
        announcedPhase = phase; allGoodSince = null; keepArmed = true
        lastType = type; lastEmitMs = now
        return CoachCue(type, head, detail, spoken, reason)
    }

    private fun info(now: Long, type: CueType, head: String, detail: String, spoken: String, reason: String): CoachCue {
        if (type == lastType && now - lastEmitMs < config.infoRepeatMs) return CoachCue.NONE
        lastType = type; lastEmitMs = now
        return CoachCue(type, head, detail, spoken, reason)
    }

    private fun emit(now: Long, type: CueType, head: String, detail: String, spoken: String, reason: String): CoachCue {
        val since = now - lastEmitMs
        if (type == lastType && type == CueType.KEEP_IT_UP && config.keepRepeatMs <= 0) return CoachCue.NONE   // "keep it up" once per good spell
        if (type == lastType && since < (if (type == CueType.KEEP_IT_UP) config.keepRepeatMs else config.sameRepeatMs)) return CoachCue.NONE
        if (type != lastType && since < config.minAlertMs) return CoachCue.NONE
        // v0.8 back-off: the same correction three times without effect → go quiet; the gauges keep showing the state
        if (config.backoff && type == lastType && type != CueType.KEEP_IT_UP) {
            repeatCount++
            if (repeatCount >= 3) {
                if (repeatCount == 3) { lastEmitMs = now; quietSinceMs = now
                    return CoachCue(CueType.QUIET, "COACH QUIET", "$head said 3 times without a change — going quiet until something changes (5 min max)", "", "BACKOFF") }
                if (now - quietSinceMs < config.quietMs) return CoachCue.NONE
                repeatCount = 0
            }
        } else repeatCount = 0
        lastType = type; lastEmitMs = now
        return CoachCue(type, head, detail, spoken, reason)
    }
}
