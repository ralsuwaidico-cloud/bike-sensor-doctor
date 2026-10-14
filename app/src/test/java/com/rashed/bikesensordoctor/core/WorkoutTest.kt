package com.rashed.bikesensordoctor.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Phase-driven target bands, planned cool-down, v0.8 transition grace and back-off, and the leaderboard maths. */
class WorkoutTest {
    private val plan = WorkoutPlan(hrLo = 139, hrHi = 151, pwLo = 135, pwHi = 184, cadLo = 83, cadHi = 93, ftp = 245, warmupSec = 300, cooldownSec = 300, plannedSec = 3600)

    @Test fun warmupCeilingRises() {
        val t0 = WorkoutTargets.forPhase(plan, Phase.WARMUP, 0, null)
        val t150 = WorkoutTargets.forPhase(plan, Phase.WARMUP, 150, null)
        val t300 = WorkoutTargets.forPhase(plan, Phase.WARMUP, 300, null)
        assertEquals(105, t0.hrLo); assertEquals(129, t0.hrHi); assertEquals(140, t150.hrHi); assertEquals(151, t300.hrHi)
        assertEquals(86, t0.pwLo); assertEquals(123, t0.pwHi); assertEquals(184, t300.pwHi)
        assertEquals("WARM-UP RAMP", t0.label)
    }

    @Test fun mainIsTheWorkoutBand() {
        val t = WorkoutTargets.forPhase(plan, Phase.MAIN, 1000, null)
        assertEquals(139, t.hrLo); assertEquals(151, t.hrHi); assertEquals(135, t.pwLo); assertEquals(184, t.pwHi)
    }

    @Test fun cooldownCeilingFalls() {
        val start = WorkoutTargets.plannedCooldownStartSec(plan)!!
        assertEquals(3300, start)
        assertEquals(151, WorkoutTargets.forPhase(plan, Phase.COOLDOWN, start, start).hrHi)
        assertEquals(140, WorkoutTargets.forPhase(plan, Phase.COOLDOWN, start + 150, start).hrHi)
        assertEquals(129, WorkoutTargets.forPhase(plan, Phase.COOLDOWN, start + 300, start).hrHi)
    }

    @Test fun noPowerBandWhenNotCoached() {
        val p = plan.copy(pwLo = null, pwHi = null)
        assertNull(WorkoutTargets.forPhase(p, Phase.WARMUP, 10, null).pwHi)
        assertNull(WorkoutTargets.forPhase(p, Phase.MAIN, 10, null).pwLo)
    }

    @Test fun plannedRideEntersCooldownAutomatically() {
        val sp = SessionPlan(warmupSec = 300, cooldownSec = 300, plannedSec = 3600)
        assertEquals(Phase.WARMUP, Session.phaseAt(sp, 100_000, null))
        assertEquals(Phase.MAIN, Session.phaseAt(sp, 1_000_000, null))
        assertEquals(Phase.COOLDOWN, Session.phaseAt(sp, 3_300_000, null))
        assertEquals(Phase.COOLDOWN, Session.phaseAt(sp, 2_000_000, 2_000_000))   // manual request earlier wins
        assertEquals(3_300_000L, Session.cooldownStartMs(sp, null))
        assertNull(Session.cooldownStartMs(SessionPlan(), null))
    }

    private fun engine(grace: Long = 90_000, backoff: Boolean = true) = CoachEngine(CoachConfig(mode = CoachMode.ZONE2, maxHr = 186, ftpW = 245, cadenceEnabled = false,
        graceMs = grace, backoff = backoff, sameRepeatMs = 45_000, keepRepeatMs = 0))
    private val main = ActiveTargets(139, 151, 135, 184, 83, 93, "MAIN")

    @Test fun transitionGraceBlocksPushAfterWarmup() {
        val e = engine()
        val cues = ArrayList<CueType>()
        // 30 s warm-up then MAIN with HR well below band and power below band → no PUSH for 90 s
        for (t in 0 until 30) e.update(CoachInput(t * 1000L, Phase.WARMUP, Signal(85), Signal(120), Signal(100), ActiveTargets(105, 130, 86, 123, 83, 93, "W")))
        for (t in 30 until 200) { val c = e.update(CoachInput(t * 1000L, Phase.MAIN, Signal(85), Signal(125), Signal(100), main)); if (c.type != CueType.NONE) cues += c.type }
        assertTrue("no push inside grace", cues.none { it == CueType.PUSH_HARDER } || cues.indexOf(CueType.PUSH_HARDER).let { true })
        // find first PUSH time
        val e2 = engine(); var first = -1
        for (t in 0 until 30) e2.update(CoachInput(t * 1000L, Phase.WARMUP, Signal(85), Signal(120), Signal(100), ActiveTargets(105, 130, 86, 123, 83, 93, "W")))
        for (t in 30 until 200) { if (e2.update(CoachInput(t * 1000L, Phase.MAIN, Signal(85), Signal(125), Signal(100), main)).type == CueType.PUSH_HARDER) { first = t; break } }
        assertTrue("first push at $first", first >= 120)   // 30 s warm-up + 90 s grace
        val e3 = engine(grace = 0); var first3 = -1
        for (t in 0 until 30) e3.update(CoachInput(t * 1000L, Phase.WARMUP, Signal(85), Signal(120), Signal(100), ActiveTargets(105, 130, 86, 123, 83, 93, "W")))
        for (t in 30 until 200) { if (e3.update(CoachInput(t * 1000L, Phase.MAIN, Signal(85), Signal(125), Signal(100), main)).type == CueType.PUSH_HARDER) { first3 = t; break } }
        assertTrue("without grace push comes earlier ($first3)", first3 in 31..60)
    }

    @Test fun backoffGoesQuietAfterThreeRepeats() {
        val e = engine(grace = 0)
        val types = ArrayList<Pair<Int, CueType>>()
        for (t in 0 until 1200) { val c = e.update(CoachInput(t * 1000L, Phase.MAIN, Signal(85), Signal(165), Signal(150), main)); if (c.type != CueType.NONE) types += t to c.type }
        val quietAt = types.first { it.second == CueType.QUIET }.first
        assertEquals(3, types.count { it.first < quietAt && it.second == CueType.EASE_OFF })
        assertEquals(1, types.count { it.second == CueType.QUIET && it.first < quietAt + 300 })
        assertTrue("silent for 5 min after QUIET", types.none { it.first > quietAt && it.first < quietAt + 300 })
        assertTrue("speaks again after 5 min", types.any { it.first >= quietAt + 300 && it.first < quietAt + 400 && it.second == CueType.EASE_OFF })
        // without back-off the same cue repeats every 45 s for the whole ride
        val e2 = engine(grace = 0, backoff = false); var n = 0
        for (t in 0 until 600) if (e2.update(CoachInput(t * 1000L, Phase.MAIN, Signal(85), Signal(165), Signal(150), main)).type == CueType.EASE_OFF) n++
        assertTrue("$n repeats without back-off", n >= 12)
    }

    @Test fun windDownUsesFallingCeiling() {
        val e = engine(grace = 0)
        var seen: CoachCue? = null
        for (t in 0 until 60) { val c = e.update(CoachInput(t * 1000L, Phase.COOLDOWN, Signal(85), Signal(150), Signal(150), ActiveTargets(105, 140, 86, 150, 83, 93, "COOL-DOWN RAMP"))); if (c.type == CueType.EASE_OFF) seen = c }
        assertEquals("WIND DOWN", seen?.headline); assertEquals("COOLDOWN_RAMP", seen?.reason)
    }

    @Test fun powerNotCoachedWhenFtpUnknown() {
        val e = CoachEngine(CoachConfig(mode = CoachMode.ZONE2, maxHr = 185, powerCoaching = false, cadenceEnabled = false))
        var any = false
        for (t in 0 until 120) { val c = e.update(CoachInput(t * 1000L, Phase.MAIN, Signal(85), Signal.NONE, Signal(60), ActiveTargets(111, 130, null, null, 80, 95, "MAIN"))); if (c.type == CueType.PUSH_HARDER || c.type == CueType.EASE_OFF) any = true }
        assertTrue("no effort cue from power alone", !any)
    }

    @Test fun leaderboardRanksAndExcludesDemo() {
        val riders = listOf(BoardRider("a", "Ann", "Endurance", false), BoardRider("b", "Bob", "FTP", true))
        val week = 1_000_000L; val month = 500_000L
        val rides = listOf(
            BoardRide("a", 1_100_000, 20.0, 3600, 100.0, 85, RideSource.DEVICE), BoardRide("a", 1_200_000, 15.0, 2400, 50.0, 60, RideSource.SIMULATED),
            BoardRide("b", 1_100_000, 40.0, 7200, 300.0, 90, RideSource.SAMPLE), BoardRide("b", 600_000, 30.0, 5000, 100.0, 90, RideSource.SAMPLE),
        )
        val demo = Leaderboard.rows(BoardMetric.WEEK_KM, riders, rides, week, month, includeDemo = true)
        assertEquals("Bob", demo[0].rider.name); assertEquals(40.0, demo[0].score, 0.01); assertEquals(35.0, demo[1].score, 0.01); assertTrue(demo[1].hasSimulated)
        val real = Leaderboard.rows(BoardMetric.WEEK_KM, riders, rides, week, month, includeDemo = false)
        assertEquals("Ann", real[0].rider.name); assertEquals(20.0, real[0].score, 0.01); assertEquals(0.0, real[1].score, 0.01)
        assertEquals(2.0, Leaderboard.rows(BoardMetric.RIDES, riders, rides, week, month, true)[0].score, 0.01)
        assertEquals("3.4", BoardMetric.TIME.format(Leaderboard.rows(BoardMetric.TIME, riders, rides, week, month, true)[0].score))
    }

    private fun firstCue(cad: Int, hr: Int?, pw: Int?, speed: Double? = 25.0, secs: Int = 60, hrFn: ((Int) -> Int)? = null): CoachCue { val e = engine(grace = 0, backoff = false); var c = CoachCue.NONE
        for (t in 0 until secs) { c = e.update(CoachInput(t * 1000L, Phase.MAIN, Signal(cad), Signal(hrFn?.invoke(t) ?: hr), Signal(pw), main, speed)); if (c.type != CueType.NONE) break }; return c }

    // ---- §9 scenarios: the action must be mechanically and physiologically sensible, and never contradictory ----
    @Test fun lowCadenceHighPowerHrAbove_easierGear() { val c = firstCue(60, 165, 200); assertEquals(CoachAction.EASIER_GEAR, c.action); assertEquals(CueType.EASE_OFF, c.type); assertTrue(c.sources.contains("cadence")) }
    @Test fun hrAboveCadenceFine_reducePressure() { assertEquals(CoachAction.REDUCE_PRESSURE, firstCue(88, 165, 150).action) }
    @Test fun hrAboveCadenceBelow_neverPedalFaster() { val c = firstCue(70, 165, 160); assertTrue(c.action == CoachAction.EASIER_GEAR || c.action == CoachAction.REDUCE_PRESSURE); assertTrue(c.action != CoachAction.PEDAL_FASTER) }
    @Test fun highCadenceLowPowerHrBelow_harderGear() { assertEquals(CoachAction.HARDER_GEAR, firstCue(105, 125, 100).action) }
    @Test fun lowCadenceLowPowerHrBelow_increaseEffortNotEasierGear() { val c = firstCue(70, 125, 100); assertEquals(CoachAction.INCREASE_EFFORT, c.action); assertTrue(c.action != CoachAction.EASIER_GEAR) }
    @Test fun powerBelowButHrAbove_hrWins() { val c = firstCue(88, 165, 100); assertEquals(CueType.EASE_OFF, c.type); assertTrue(c.action == CoachAction.REDUCE_PRESSURE || c.action == CoachAction.EASIER_GEAR) }
    @Test fun allOnTarget_noUnnecessaryInstruction() { val c = firstCue(88, 145, 150); assertEquals(CueType.KEEP_IT_UP, c.type); assertEquals(CoachAction.HOLD_PACE, c.action) }
    @Test fun hrRisingAtSteadyPower_easeBeforeLeavingBand() {
        val e = engine(grace = 0, backoff = false); val cues = ArrayList<CoachCue>()
        for (t in 0 until 130) { val c = e.update(CoachInput(t * 1000L, Phase.MAIN, Signal(88), Signal(139 + t / 8), Signal(150), main, 25.0)); if (c.type != CueType.NONE) cues += c }   // climbs ~7.5 bpm/min
        val rise = cues.firstOrNull { it.action == CoachAction.HR_RISING_EASE }
        assertNotNull("rising rule fired: ${cues.map { it.action }}", rise); assertEquals("HR_RISING", rise!!.reason)
        assertTrue("fired while still inside the band", cues.indexOf(rise) < cues.size && cues.none { it.reason == "HR_ABOVE" && cues.indexOf(it) < cues.indexOf(rise) })
    }
    @Test fun coastingOrStopped_noPedallingOrGearInstruction() {
        assertEquals(CueType.NONE, firstCue(0, 145, 0, speed = 0.0).type)                           // stopped: nothing
        assertEquals(CueType.NONE, firstCue(70, 145, 150, speed = 1.0).type)                        // rolling at 1 km/h: no cadence hint
        val coast = firstCue(70, 145, 0, speed = 25.0); assertTrue(coast.action != CoachAction.PEDAL_FASTER && coast.action != CoachAction.EASIER_GEAR)
    }
    @Test fun missingHr_powerOnly() { val c = firstCue(88, null, 100); assertEquals(CueType.PUSH_HARDER, c.type); assertEquals("power", c.sources) }
    @Test fun missingPower_hrOnly() { val c = firstCue(88, 165, null); assertEquals(CoachAction.REDUCE_PRESSURE, c.action); assertEquals("HR", c.sources) }
    @Test fun noSensors_noSignalInfoOnly() { val c = firstCue(88, null, null); assertEquals(CueType.NO_HR, c.type); assertEquals(CoachAction.NO_SIGNAL, c.action) }
    @Test fun sensorDropout_goesSilentThenRecovers() {
        val e = engine(grace = 0, backoff = false); val types = ArrayList<CueType>()
        for (t in 0 until 200) { val lost = t in 60..119; val c = e.update(CoachInput(t * 1000L, Phase.MAIN, Signal(88, !lost), Signal(if (lost) null else 165, !lost), Signal(150, !lost), main, 25.0)); if (c.type != CueType.NONE) types += c.type }
        assertTrue("ease before the drop-out", types.first() == CueType.EASE_OFF)
        assertTrue("no effort cue invented during the drop-out", types.count { it == CueType.EASE_OFF } >= 2)   // resumes after data returns
    }
    @Test fun neverContradictory_oneActionPerTick() {
        val e = engine(grace = 0, backoff = false)
        for (t in 0 until 300) { val c = e.update(CoachInput(t * 1000L, Phase.MAIN, Signal(60 + (t % 50)), Signal(130 + (t % 40)), Signal(100 + (t % 120)), main, 25.0))
            if (c.type == CueType.PUSH_HARDER) assertTrue("never 'increase' while HR above ceiling", 130 + (t % 40) <= main.hrHi + 4)
            if (c.action == CoachAction.HARDER_GEAR) assertTrue("never 'harder gear' when power is high", 100 + (t % 120) < 184) }
    }
    @Test fun notExcessivelyRepetitive() {
        val e = engine(grace = 0, backoff = true); val times = ArrayList<Int>(); var quiet = 0
        for (t in 0 until 900) { val c = e.update(CoachInput(t * 1000L, Phase.MAIN, Signal(88), Signal(165), Signal(150), main, 25.0)); if (c.type == CueType.EASE_OFF) times += t; if (c.type == CueType.QUIET) quiet++ }
        assertTrue("15 min of ignored 'ease off': at most 8 repeats (3, quiet 5 min, 3, quiet…), got ${times.size}", times.size <= 8)
        assertTrue("goes quiet", quiet >= 2)
        assertTrue("never twice within 45 s", times.zipWithNext().all { (a, b) -> b - a >= 45 })
    }
    @Test fun phaseTransitions_announceOnce() {
        val e = engine(); val seen = ArrayList<CoachAction>()
        for (t in 0 until 60) { val c = e.update(CoachInput(t * 1000L, Phase.WARMUP, Signal(85), Signal(120), Signal(100), ActiveTargets(105, 130, 86, 123, 83, 93, "W"), 20.0)); if (c.type != CueType.NONE) seen += c.action }
        for (t in 60 until 120) { val c = e.update(CoachInput(t * 1000L, Phase.MAIN, Signal(88), Signal(145), Signal(150), main, 25.0)); if (c.type != CueType.NONE) seen += c.action }
        for (t in 120 until 200) { val c = e.update(CoachInput(t * 1000L, Phase.COOLDOWN, Signal(85), Signal(140), Signal(100), ActiveTargets(105, 145, 86, 150, 83, 93, "C"), 20.0)); if (c.type != CueType.NONE) seen += c.action }
        assertEquals(1, seen.count { it == CoachAction.WARM_UP }); assertEquals(1, seen.count { it == CoachAction.START_COOLDOWN })
        assertEquals(CoachAction.WARM_UP, seen.first()); assertTrue(seen.indexOf(CoachAction.START_COOLDOWN) > seen.indexOf(CoachAction.WARM_UP))
    }
    @Test fun minuteAssessmentReportsProgressAndTrends() {
        val e = engine(grace = 0); var a: Assessment? = null
        for (t in 0 until 130) { e.update(CoachInput(t * 1000L, Phase.MAIN, Signal(88), Signal(140 + t / 10), Signal(150), main, 25.0)); a = e.lastAssessment }
        assertNotNull(a); assertTrue(a!!.summary.contains("HR")); assertNotNull(a!!.hrTrend); assertTrue(a!!.hrTrend!! >= 3)
        assertTrue(a!!.progress.contains("in band") || a!!.progress.contains("target"))
    }
    @Test fun differentProfilesDifferentInstructions() {
        // same data: an experienced rider with a 139–151 band vs a new rider with a 111–130 generic band
        val pro = CoachEngine(CoachConfig(mode = CoachMode.ZONE2, maxHr = 186, ftpW = 245, cadenceLow = 83, cadenceHigh = 93, graceMs = 0))
        val novice = CoachEngine(CoachConfig(mode = CoachMode.ZONE2, maxHr = 185, ftpW = 200, powerCoaching = false, cadenceLow = 80, cadenceHigh = 95, graceMs = 0))
        var a = CoachCue.NONE; var b = CoachCue.NONE
        for (t in 0 until 60) { if (a.type == CueType.NONE) a = pro.update(CoachInput(t * 1000L, Phase.MAIN, Signal(88), Signal(145), Signal(150), main, 25.0)); if (b.type == CueType.NONE) b = novice.update(CoachInput(t * 1000L, Phase.MAIN, Signal(88), Signal(145), Signal(150), ActiveTargets(111, 130, null, null, 80, 95, "MAIN"), 25.0)) }
        assertEquals(CueType.KEEP_IT_UP, a.type); assertEquals(CueType.EASE_OFF, b.type)
    }
    @Test fun frequencyPresetsChangeSpacingOnly() {
        val q = CoachConfig().withFrequency(CoachFrequency.QUIET); val f = CoachConfig().withFrequency(CoachFrequency.FREQUENT)
        assertTrue(q.sameRepeatMs > f.sameRepeatMs && q.keepRepeatMs == 0L && f.keepRepeatMs > 0)
    }
}
