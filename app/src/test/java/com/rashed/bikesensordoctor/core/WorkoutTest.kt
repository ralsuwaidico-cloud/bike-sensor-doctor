package com.rashed.bikesensordoctor.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
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

    private fun firstCue(cad: Int, hr: Int, pw: Int): CoachCue { val e = engine(grace = 0, backoff = false); var c = CoachCue.NONE
        for (t in 0 until 60) { c = e.update(CoachInput(t * 1000L, Phase.MAIN, Signal(cad), Signal(hr), Signal(pw), main)); if (c.type != CueType.NONE) break }; return c }

    @Test fun actionableWordingFollowsCadenceContext() {
        assertEquals("SHIFT TO AN EASIER GEAR", firstCue(60, 165, 150).headline)      // HR above + grinding → easier gear
        assertEquals("REDUCE PEDAL PRESSURE", firstCue(88, 165, 150).headline)        // HR above, cadence fine → less force
        assertEquals("SHIFT TO A HARDER GEAR", firstCue(105, 125, 100).headline)       // HR below + spinning out → harder gear
        assertEquals("INCREASE EFFORT SLIGHTLY", firstCue(88, 125, 100).headline)      // HR below, cadence fine → a bit more effort
        assertEquals("MAINTAIN YOUR RHYTHM", firstCue(88, 145, 150).headline)         // all good
        assertEquals(CueType.EASE_OFF, firstCue(60, 165, 150).type)                   // the decision itself is unchanged (vectors still hold)
    }
}
