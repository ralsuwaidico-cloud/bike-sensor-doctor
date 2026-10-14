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

enum class CueType { NONE, KEEP_IT_UP, PEDAL_FASTER, PEDAL_SLOWER, EASE_OFF, PUSH_HARDER, RECOVER, WORK, NO_HR, NO_POWER, WARMUP, COOLDOWN, QUIET,
    /** v0.10 pattern rules read from the 1 Hz history: a sudden power spike, an unsteady effort, recovery after easing off */
    SURGE, STEADY }

/**
 * v3: the practical action the rider should take. One per tick, chosen by one priority ladder
 * (safety/validity → effort vs targets → cadence → gear → encouragement), so instructions never contradict.
 */
enum class CoachAction(val icon: String) {
    NONE("○"), WARM_UP("☼"), START_COOLDOWN("❄"), WIND_DOWN("❄"),
    EASIER_GEAR("⚙−"), HARDER_GEAR("⚙+"), REDUCE_PRESSURE("⇩"), INCREASE_EFFORT("⇧"), HR_RISING_EASE("♥↑"),
    PEDAL_FASTER("↻+"), PEDAL_SLOWER("↻−"), KEEP_CADENCE_STEADY("≈"), HOLD_PACE("═"), STABLE_MAINTAIN("✓"),
    RECOVER("❄"), NO_SIGNAL("?"), QUIET("…"),
    SMOOTH_SURGES("∿"), STEADY_EFFORT("≈"), RECOVERED("✓"),
}

/**
 * @param reason machine-readable cause (e.g. HR_ABOVE, HR_LAG_HOLD) for logs and tests.
 * @param action practical instruction; @param sources which signals decided ("HR + cadence"); @param live the relevant live numbers.
 */
data class CoachCue(val type: CueType, val headline: String, val detail: String, val spoken: String, val reason: String = "",
                    val action: CoachAction = CoachAction.NONE, val sources: String = "", val live: String = "",
                    /** v0.10: the glanceable form for the live screen — one short instruction and one short reason ("Ease off — HR above target" / "HR 158 vs 139–151 bpm"); the full reasoning stays in [detail] */
                    val short: String = "", val why: String = "") {
    companion object { val NONE = CoachCue(CueType.NONE, "", "", "", "") }
}

/** How much the coach talks. Quiet: corrections only, well spaced. Frequent: also encouragement, closer together. */
enum class CoachFrequency { QUIET, NORMAL, FREQUENT }

/** The 60-second assessment: not a spoken cue — a status the display shows (and the subtle "analysed at …" indicator). */
data class Assessment(val atMs: Long, val summary: String, val progress: String, val inBandPctMinute: Int?, val hrTrend: Int?, val powerTrend: Int?, val cadTrend: Int?)

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
) {
    /** Spacing presets for quiet / normal / frequent coaching. */
    fun withFrequency(f: CoachFrequency): CoachConfig = when (f) {
        CoachFrequency.QUIET -> copy(minAlertMs = 15_000, sameRepeatMs = 120_000, keepRepeatMs = 0, infoRepeatMs = 60_000)
        CoachFrequency.NORMAL -> copy(minAlertMs = 10_000, sameRepeatMs = 45_000, keepRepeatMs = 90_000, infoRepeatMs = 30_000)
        CoachFrequency.FREQUENT -> copy(minAlertMs = 8_000, sameRepeatMs = 30_000, keepRepeatMs = 60_000, infoRepeatMs = 20_000)
    }
}

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
    /** km/h, for the coasting/stopped rule and the speed trend (optional). */
    val speedKmh: Double? = null,
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
    /** v3: per-type spacing, so two different corrections cannot ping-pong every 10 s (each still respects its own repeat time). */
    private val lastEmitByType = HashMap<CueType, Long>()
    private var allGoodSince: Long? = null
    private var keepArmed = true          // KEEP IT UP fires on entering "all good"
    private var announcedPhase: Phase? = null
    private var surgeSince: Long? = null
    private var spikeSince: Long? = null; private var easeAtMs: Long? = null; private var recoveredForMs: Long? = null
    private var lastCad: Int? = null
    private var lastHr: Int? = null; private var lastPw: Int? = null; private var lastSpeed: Double? = null
    private var lastHb: Band? = null; private var lastPb: Band? = null
    private var lastHrBand = ""; private var lastPwBand = ""

    /** 30 s-vs-previous-30 s trend of a signal (per minute), from 1 Hz samples. */
    private class Trend {
        private val win = ArrayDeque<Pair<Long, Double>>()
        private var cvWin = ArrayDeque<Double>()
        fun feed(now: Long, v: Double?) { if (v == null) { win.clear(); cvWin.clear(); return }; win.addLast(now to v); while (win.isNotEmpty() && now - win.first().first > 60_000) win.removeFirst(); cvWin.addLast(v); while (cvWin.size > 60) cvWin.removeFirst() }
        /** change per minute: mean(last 30 s) − mean(previous 30 s), or null until 40 s of data */
        fun perMinute(now: Long): Double? { if (win.size < 40) return null; val recent = win.filter { now - it.first <= 30_000 }.map { it.second }; val older = win.filter { now - it.first > 30_000 }.map { it.second }; if (recent.size < 10 || older.size < 10) return null; return (recent.average() - older.average()) * 2.0 }   // windows are 30 s apart → ×2 for per minute
        fun mean(): Double? = if (cvWin.size < 45) null else cvWin.average()
        fun cv(): Double? { if (cvWin.size < 45) return null; val m = cvWin.average(); if (m <= 0) return null; return Math.sqrt(cvWin.sumOf { (it - m) * (it - m) } / cvWin.size) / m }
        /** direction reversals of ≥ 3-unit steps in the last minute: a single deliberate step change is 1, ragged pedalling is many */
        fun reversals(): Int { if (cvWin.size < 45) return 0; var n = 0; var last = 0; val a = cvWin.toList(); for (i in 1 until a.size) { val d = a[i] - a[i - 1]; val sgn = if (d >= 3) 1 else if (d <= -3) -1 else 0; if (sgn != 0) { if (last != 0 && sgn != last) n++; last = sgn } }; return n }
        fun clear() { win.clear(); cvWin.clear() }
    }
    private val hrT = Trend(); private val pwT = Trend(); private val cadT = Trend(); private val spT = Trend()
    private var minuteAbove = 0; private var minuteBelow = 0; private var minuteIn = 0; private var minuteStartMs = Long.MIN_VALUE / 2
    /** The most recent 60-second assessment (display only). */
    var lastAssessment: Assessment? = null; private set
    private var phaseSeen: Phase? = null; private var phaseSinceMs = 0L
    private var repeatCount = 0; private var quietSinceMs = 0L

    var interval: IntervalPlan = IntervalPlan()
    private var intervalStartMs: Long? = null

    fun reset() {
        cadS.clear(); hrS.clear(); pwS.clear(); hrBand.clear(); pwBand.clear(); cadState = null
        lastType = CueType.NONE; lastEmitMs = Long.MIN_VALUE / 2; lastEmitByType.clear(); allGoodSince = null; keepArmed = true
        announcedPhase = null; surgeSince = null; spikeSince = null; easeAtMs = null; recoveredForMs = null; intervalStartMs = null
        phaseSeen = null; phaseSinceMs = 0; repeatCount = 0; quietSinceMs = 0
        hrT.clear(); pwT.clear(); cadT.clear(); spT.clear(); minuteAbove = 0; minuteBelow = 0; minuteIn = 0; minuteStartMs = Long.MIN_VALUE / 2; lastAssessment = null
        lastHr = null; lastPw = null; lastSpeed = null; lastHb = null; lastPb = null
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
        lastCad = cad
        val hrRaw = hrS.feed(now, input.hr)
        // 0 W is a valid COASTING reading but carries no effort information: it must neither drive a cue nor
        // drag the rolling mean down (otherwise the first loaded seconds after coasting read as "below target").
        val coasting = input.power.available && input.power.value == 0
        val pwRaw = pwS.feed(now, if (coasting) Signal.NONE else input.power)
        val useHr = when (c.effortSource) { EffortSource.HEART_RATE -> true; EffortSource.POWER -> false; EffortSource.AUTO -> true }
        val usePw = c.effortSource != EffortSource.HEART_RATE && c.powerCoaching
        val hr = if (useHr) hrRaw else null
        val pw = if (usePw && pwRaw != null && pwRaw > 0) pwRaw else null
        lastHr = hr; lastPw = pw; lastSpeed = input.speedKmh
        hrT.feed(now, hr?.toDouble()); pwT.feed(now, pw?.toDouble()); cadT.feed(now, cad?.takeIf { it > 0 }?.toDouble()); spT.feed(now, input.speedKmh)
        // coasting or stopped: no pedalling or gear instruction makes sense (effort rules below still see HR)
        val stopped = (input.speedKmh != null && input.speedKmh < 2.0) || (cad != null && cad == 0 && input.cadence.available)

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
        lastHb = hb; lastPb = pb
        lastHrBand = if (tg != null) "${tg.hrLo}–${tg.hrHi} bpm" else "zone $targetHrZone"
        lastPwBand = if (tg != null && tg.pwLo != null && tg.pwHi != null) "${tg.pwLo}–${tg.pwHi} W" else "zone $targetZone"
        val bandText = lastHrBand
        // ---- 60-second assessment: time above/below/in band this minute, trends, progress (display only) ----
        if (phase == Phase.MAIN) { when (hb ?: pb) { Band.ABOVE -> minuteAbove++; Band.BELOW -> minuteBelow++; Band.ON -> minuteIn++; null -> {} } }
        if (minuteStartMs == Long.MIN_VALUE / 2) minuteStartMs = now
        if (now - minuteStartMs >= 60_000) {
            val tot = minuteAbove + minuteBelow + minuteIn
            val pct = if (tot > 0) minuteIn * 100 / tot else null
            val ht = hrT.perMinute(now)?.let { Math.round(it).toInt() }; val pt = pwT.perMinute(now)?.let { Math.round(it).toInt() }; val ct = cadT.perMinute(now)?.let { Math.round(it).toInt() }
            val parts = ArrayList<String>()
            hr?.let { parts += "HR $it" + (ht?.let { d -> if (d >= 3) " ↑" else if (d <= -3) " ↓" else " →" } ?: "") }
            pw?.let { parts += "$it W" + (pt?.let { d -> if (d >= 10) " ↑" else if (d <= -10) " ↓" else " →" } ?: "") }
            cad?.takeIf { it > 0 }?.let { parts += "$it rpm" }
            val progress = when { phase != Phase.MAIN -> phase.name.lowercase(); pct == null -> "no effort signal this minute"; pct >= 80 -> "on track — $pct % of the last minute in band"; minuteAbove > minuteBelow -> "mostly above target ($pct % in band) — ease"; else -> "mostly below target ($pct % in band) — a little more" }
            lastAssessment = Assessment(now, parts.joinToString(" · "), progress, pct, ht, pt, ct)
            minuteStartMs = now; minuteAbove = 0; minuteBelow = 0; minuteIn = 0
        }
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

        // ---- v0.10 patterns from the 1 Hz history (the same samples the live graph draws) ----
        // sudden spike: RAW power above 1.5× the top of the band (and at least +50 W) — judged on the instantaneous reading, not the 5-s mean
        val pHiW = (pHi * c.ftpW).takeIf { usePw && c.ftpW > 0 && pHi < 5.0 }
        val rawPw = input.power.value?.takeIf { input.power.available && it > 0 }
        val spiking = pHiW != null && rawPw != null && rawPw > maxOf(pHiW * 1.5, pHiW + 50)
        // unsteady effort: a minute of power swinging ±20 % (5-s means) around an average that is itself inside the band
        val pcv = pwT.cv(); val pMean = pwT.mean()
        // (a single deliberate step change has no direction reversals; swinging has several)
        val unsteady = pw != null && pcv != null && pMean != null && pcv > 0.20 && pwT.reversals() >= 4 && pMean >= pLo * c.ftpW && pMean <= pHi * c.ftpW
        fun steadyCue(): CoachCue? = if (!unsteady) null else emit(now, CueType.STEADY, "HOLD A STEADIER EFFORT", "Average power is on target but it swung ±${Math.round((pcv ?: 0.0) * 100)} % over the last minute — pick one gear and keep the pressure even", "Hold a steadier effort", "PW_UNSTEADY").takeIf { it.type != CueType.NONE }

        // ---- 5. effort ladder (MAIN) ----
        val effort: CoachCue? = when {
            hr != null -> when (hb) {
                Band.ABOVE -> if (hrBand.held(now, c.effortHoldMs))
                    emit(now, CueType.EASE_OFF, "EASE OFF", "Heart rate $hr above target $bandText", "Ease off", "HR_ABOVE") else hold()
                Band.ON -> {
                    // heart rate climbing fast while power is steady: it will leave the band — ease before it does
                    val rising = hrT.perMinute(now)?.let { it >= 6.0 } == true && (pwT.perMinute(now)?.let { Math.abs(it) < 15.0 } ?: true) && hr.toDouble() / c.maxHr > hHi - 0.03
                    if (rising && hrBand.held(now, 20_000)) return emit(now, CueType.EASE_OFF, "YOUR HEART RATE IS RISING. EASE OFF", "Heart rate $hr climbing about ${Math.round(hrT.perMinute(now) ?: 0.0)} bpm/min at steady power — back off a touch before it leaves the band", "Your heart rate is rising, ease off", "HR_RISING").also { if (it.type != CueType.NONE) allGoodSince = null }
                    // unsteady pedalling with the average right and HR fine: name the pattern instead of chasing each swing
                    steadyCue()?.let { return it.also { allGoodSince = null } }
                    // power surging well above target while HR has not caught up yet → pre-empt the overshoot;
                    // a big sudden spike (> 1.5× the band top for 3 s) is named as such, a moderate surge after the usual 6 s
                    val surging = pwZone != null && pwZone >= targetZone + 1 && pb == Band.ABOVE
                    if (surging || spiking) { if (surgeSince == null) surgeSince = now } else surgeSince = null
                    if (!surging && !spiking) null
                    else if (spiking && now - (surgeSince ?: now) >= 3_000)
                        emit(now, CueType.SURGE, "SMOOTH OUT THE SURGES", "Power jumped to $rawPw W — more than 1.5× the top of the target (${Math.round(pHiW ?: 0.0)} W). Surges cost more than steady watts; keep the pressure even", "Smooth out the surges", "PW_SPIKE")
                    else if (surging && now - (surgeSince ?: now) >= c.surgeHoldMs)
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
                Band.ON -> steadyCue()
                null -> null
            }
            else -> {
                if (coasting) hold("COASTING")
                else if (c.effortSource == EffortSource.POWER) info(now, CueType.NO_POWER, "PEDAL UNDER LOAD", "Power reads 0 with no load — effort coaching needs pedaling resistance", "", "NO_POWER")
                else info(now, CueType.NO_HR, "NO EFFORT SIGNAL", "Connect a heart-rate sensor, or pedal under load for power-based coaching", "", "NO_SIGNAL")
            }
        }
        if (effort != null) { if (effort.type != CueType.NONE) allGoodSince = null; return effort }

        // ---- 6. cadence hints only when effort is in order (band ON — a pending effort correction must not be interleaved with cadence talk); never while coasting or stopped ----
        val effortOk = hb == Band.ON || (hr == null && pb == Band.ON) || (hr == null && pw == null)
        if (effortOk && !stopped && !coasting) {
            cadenceCue(now, cad, phase)?.let { if (it.type != CueType.NONE) allGoodSince = null; return it }
            // uneven pedalling (cadence varying > 12 % over the last minute) with effort fine → keep the cadence steady
            val cv = cadT.cv()
            if (c.cadenceEnabled && cad != null && cad > 0 && cv != null && cv > 0.12 && cadT.reversals() >= 8 && (hb == Band.ON || (hr == null && pb == Band.ON)))
                emit(now, CueType.PEDAL_FASTER, "KEEP YOUR CADENCE STEADY", "Cadence varied ±${Math.round(cv * 100)} % over the last minute while effort was fine — settle into one rhythm", "Keep your cadence steady", "CAD_UNEVEN").let { if (it.type != CueType.NONE) { allGoodSince = null; return it } }
        }

        // ---- 7. all good (not while stopped or coasting: there is no pace to hold) ----
        if (stopped || coasting) { allGoodSince = null; return CoachCue.NONE }
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
        if (cue.type != CueType.NONE) { keepArmed = false; if (cue.action == CoachAction.RECOVERED) recoveredForMs = easeAtMs }
        return cue
    }

    private fun hold(reason: String = ""): CoachCue = CoachCue.NONE

    private fun announce(now: Long, phase: Phase, type: CueType, head0: String, detail0: String, spoken0: String, reason: String): CoachCue {
        val w = action(type, head0, detail0, spoken0, reason)
        if (announcedPhase == phase) return CoachCue.NONE
        announcedPhase = phase; allGoodSince = null; keepArmed = true
        lastType = type; lastEmitMs = now
        val (sh, why) = shortWording(w, reason)
        return CoachCue(type, w.head, w.detail, w.spoken, reason, w.action, w.sources, liveText(), sh, why)
    }

    private fun info(now: Long, type: CueType, head: String, detail: String, spoken: String, reason: String): CoachCue {
        if (type == lastType && now - lastEmitMs < config.infoRepeatMs) return CoachCue.NONE
        lastType = type; lastEmitMs = now
        val (sh, why) = shortWording(Worded(CoachAction.NO_SIGNAL, head, detail, spoken, "sensors"), reason)
        return CoachCue(type, head, detail, spoken, reason, CoachAction.NO_SIGNAL, "sensors", liveText(), sh, why)
    }

    /**
     * Actionable wording (v0.9): the SAME decision, said as what to do with the bike. Cadence decides between a gear
     * change and a pressure/effort change, so the instruction never fights the cadence hint.
     */
    private class Worded(val action: CoachAction, val head: String, val detail: String, val spoken: String, val sources: String)

    /**
     * Gear intelligence (v3): the SAME effort decision, said as what to do with the bike. Gear is inferred from
     * cadence and power — the app never measures the selected gear.
     *  - HR/power above target + low cadence + high power → easier gear (less resistance, smoother spin) · else reduce pressure
     *  - HR/power below target + high cadence + low power → harder gear · low cadence + low power → increase effort (NOT an easier gear)
     *  - effort fine → cadence hints; all fine → hold pace / maintain rhythm
     */
    private fun action(type: CueType, head: String, detail: String, spoken: String, reason: String): Worded {
        val c = config; val cad = lastCad; val pw = lastPw; val hr = lastHr
        val cadLow = cad != null && cad > 0 && cad < c.cadenceLow; val cadHigh = cad != null && cad > c.cadenceHigh
        val pwHigh = lastPb == Band.ABOVE || (pw != null && pw > c.ftpW * 0.75); val pwLow = lastPb == Band.BELOW || (pw != null && pw < c.ftpW * 0.55)
        val src = buildString { if (reason.startsWith("HR") || reason == "COOLDOWN_RAMP" || reason == "COOLDOWN_HR_ABOVE") append("HR"); if (reason.startsWith("PW")) append("power"); if (reason.startsWith("CAD")) append("cadence") }
        return when (type) {
            CueType.EASE_OFF -> when {
                head == "WIND DOWN" -> Worded(CoachAction.WIND_DOWN, "WIND DOWN", detail, spoken, "HR")
                reason == "HR_RISING" -> Worded(CoachAction.HR_RISING_EASE, head, detail, spoken, "HR trend + power")
                cadLow && !pwLow -> Worded(CoachAction.EASIER_GEAR, "SHIFT TO AN EASIER GEAR", "$detail · cadence $cad rpm with a heavy gear: less resistance, smoother spin, and the effort comes down", "Shift to an easier gear", "$src + cadence")
                else -> Worded(CoachAction.REDUCE_PRESSURE, "REDUCE PRESSURE ON THE PEDALS", detail, "Reduce pressure on the pedals", src.ifEmpty { "HR" })
            }
            CueType.PUSH_HARDER -> when {
                cadHigh && (pwLow || pw == null) -> Worded(CoachAction.HARDER_GEAR, "SHIFT TO A HARDER GEAR", "$detail · cadence $cad rpm is high with little resistance — add gear, keep the spin", "Shift to a harder gear", "$src + cadence")
                else -> Worded(CoachAction.INCREASE_EFFORT, "INCREASE YOUR EFFORT SLIGHTLY", if (cadLow) "$detail · cadence is low too, so press a little more rather than changing gear" else detail, "Increase your effort slightly", src.ifEmpty { "HR" })
            }
            CueType.PEDAL_FASTER -> if (head.startsWith("KEEP")) Worded(CoachAction.KEEP_CADENCE_STEADY, head, detail, spoken, "cadence") else Worded(CoachAction.PEDAL_FASTER, "PEDAL A LITTLE FASTER", "Easier gear, same effort — $detail", "Pedal a little faster", "cadence")
            CueType.PEDAL_SLOWER -> Worded(CoachAction.PEDAL_SLOWER, "SLOW YOUR PEDALLING", "Harder gear, same effort — $detail", "Slow your pedalling", "cadence")
            CueType.KEEP_IT_UP -> if (easeAtMs != null && easeAtMs != recoveredForMs) Worded(CoachAction.RECOVERED, "GOOD — BACK ON TARGET", "${if (hr != null) "Heart rate" else "Power"} settled back into the band after easing off — hold this", "Good, back on target", if (hr != null) "HR" else "power")
                else if (pw != null && lastPb == Band.ON) Worded(CoachAction.HOLD_PACE, "HOLD THIS PACE", "Power and heart rate on target", "Hold this pace", "HR + power")
                else Worded(CoachAction.STABLE_MAINTAIN, "YOUR EFFORT IS STABLE. MAINTAIN THIS RHYTHM", detail, "Your effort is stable, maintain this rhythm", if (hr != null) "HR" else "power")
            CueType.COOLDOWN -> Worded(CoachAction.START_COOLDOWN, "START YOUR COOLDOWN", detail, "Start your cooldown", "phase")
            CueType.SURGE -> Worded(CoachAction.SMOOTH_SURGES, head, detail, spoken, "power")
            CueType.STEADY -> Worded(CoachAction.STEADY_EFFORT, head, detail, spoken, if (hr != null) "power + HR" else "power")

            CueType.WARMUP -> Worded(CoachAction.WARM_UP, head, detail, spoken, "phase")
            CueType.RECOVER -> Worded(CoachAction.RECOVER, head, detail, spoken, "phase")
            CueType.NO_HR, CueType.NO_POWER -> Worded(CoachAction.NO_SIGNAL, head, detail, spoken, "sensors")
            CueType.QUIET -> Worded(CoachAction.QUIET, head, detail, spoken, "")
            else -> Worded(CoachAction.NONE, head, detail, spoken, src)
        }
    }

    /** v0.10: the glanceable live-screen form of an instruction — short head + short reason, from the signals that decided. */
    private fun shortWording(w: Worded, reason: String): Pair<String, String> {
        val hr = lastHr; val cad = lastCad; val pw = lastPw
        val hrv = hr?.let { "HR $it" } ?: ""; val cadv = cad?.let { "$it rpm" } ?: ""
        val pwReason = reason.startsWith("PW") || reason.startsWith("RECOVERY_PW")
        return when (w.action) {
            CoachAction.EASIER_GEAR -> "Shift to an easier gear" to "$cadv low · ${if (pwReason) "power" else "HR"} above target"
            CoachAction.HARDER_GEAR -> "Shift to a harder gear" to "$cadv high · ${if (pwReason) "power" else "HR"} below target"
            CoachAction.REDUCE_PRESSURE -> (if (pwReason) "Ease off — power above target" else "Ease off — HR above target") to (if (pwReason) "$pw W vs $lastPwBand" else "$hrv vs $lastHrBand")
            CoachAction.INCREASE_EFFORT -> (if (pwReason) "Push a little — power below target" else "Push a little — HR below target") to (if (pwReason) "$pw W vs $lastPwBand" else "$hrv vs $lastHrBand")
            CoachAction.HR_RISING_EASE -> "HR rising — ease off" to "climbing at steady power"
            CoachAction.PEDAL_FASTER -> "Pedal a little faster" to "$cadv · below ${config.cadenceLow} rpm"
            CoachAction.PEDAL_SLOWER -> "Slow your pedalling" to "$cadv · above ${config.cadenceHigh} rpm"
            CoachAction.KEEP_CADENCE_STEADY -> "Keep your cadence steady" to "rhythm uneven over the last minute"
            CoachAction.HOLD_PACE -> "Hold this pace" to "power and HR on target"
            CoachAction.STABLE_MAINTAIN -> "Maintain this rhythm" to "effort stable · on target"
            CoachAction.START_COOLDOWN -> "Start your cooldown" to "ceiling comes down gradually"
            CoachAction.WIND_DOWN -> "Wind down" to "HR above the cool-down ceiling"
            CoachAction.WARM_UP -> "Warm up — easy spinning" to "no 'push' until the main block"
            CoachAction.RECOVER -> "Recover — easy spin" to "recovery interval"
            CoachAction.QUIET -> "Coach quiet" to "said 3× — speaks again on change"
            CoachAction.SMOOTH_SURGES -> "Smooth out the surges" to "power spikes well above target"
            CoachAction.STEADY_EFFORT -> "Hold a steadier effort" to "power swinging around the target"
            CoachAction.RECOVERED -> "Good — back on target" to (if (lastHr != null) "HR settled after easing off" else "power settled after easing off")
            CoachAction.NO_SIGNAL -> "No effort signal" to (if (reason == "NO_POWER") "pedal under load" else "no heart rate, no loaded power")
            CoachAction.NONE -> w.head.lowercase().replaceFirstChar { it.uppercase() } to w.detail.substringBefore(" — ").take(46)
        }
    }

    private fun liveText(): String = listOfNotNull(lastHr?.let { "HR $it" }, lastPw?.let { "$it W" }, lastCad?.takeIf { it > 0 }?.let { "$it rpm" }).joinToString(" · ")

    private fun emit(now: Long, type: CueType, head0: String, detail0: String, spoken0: String, reason: String): CoachCue {
        val w = action(type, head0, detail0, spoken0, reason)
        val head = w.head; val detail = w.detail; val spoken = w.spoken
        val since = now - lastEmitMs
        if (type == lastType && type == CueType.KEEP_IT_UP && config.keepRepeatMs <= 0) return CoachCue.NONE   // "keep it up" once per good spell
        if (type == lastType && since < (if (type == CueType.KEEP_IT_UP) config.keepRepeatMs else config.sameRepeatMs)) return CoachCue.NONE
        if (type != lastType && since < config.minAlertMs) return CoachCue.NONE
        if (type != CueType.KEEP_IT_UP) lastEmitByType[type]?.let { if (now - it < config.sameRepeatMs) return CoachCue.NONE }   // (KEEP IT UP keeps its own enter-good-spell rule)
        // v0.8 back-off: the same correction three times without effect → go quiet; the gauges keep showing the state
        if (config.backoff && type == lastType && type != CueType.KEEP_IT_UP) {
            repeatCount++
            if (repeatCount >= 3) {
                if (repeatCount == 3) { lastEmitMs = now; quietSinceMs = now
                    return CoachCue(CueType.QUIET, "COACH QUIET", "$head said 3 times without a change — going quiet until something changes (5 min max)", "", "BACKOFF", CoachAction.QUIET, "", liveText(), "Coach quiet", "said 3× — speaks again on change") }
                if (now - quietSinceMs < config.quietMs) return CoachCue.NONE
                repeatCount = 0
            }
        } else repeatCount = 0
        lastType = type; lastEmitMs = now; lastEmitByType[type] = now
        if (type == CueType.EASE_OFF || type == CueType.SURGE) easeAtMs = now
        val (sh, why) = shortWording(w, reason)
        return CoachCue(type, head, detail, spoken, reason, w.action, w.sources, liveText(), sh, why)
    }
}
