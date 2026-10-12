package com.rashed.bikesensordoctor.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Design-7 indicator logic: below/on/above target, gauge positions, zone percent, coaching shape/direction, NP/VI. */
class TargetsTest {
    private val ftp = 200
    private val maxHr = 185

    @Test fun powerStatusAgainstZone2() {
        assertEquals(TargetStatus.BELOW, Targets.power(80, ftp, 2))    // 40 % FTP = Z1
        assertEquals(TargetStatus.ON, Targets.power(130, ftp, 2))      // 65 % = Z2
        assertEquals(TargetStatus.ABOVE, Targets.power(170, ftp, 2))   // 85 % = Z3
        assertEquals(TargetStatus.UNKNOWN, Targets.power(0, ftp, 2))   // coasting is not "below"
        assertEquals(TargetStatus.UNKNOWN, Targets.power(null, ftp, 2))
    }

    @Test fun hrStatusAgainstZone2() {
        assertEquals(TargetStatus.BELOW, Targets.hr(100, maxHr, 2))    // 54 %
        assertEquals(TargetStatus.ON, Targets.hr(120, maxHr, 2))       // 65 %
        assertEquals(TargetStatus.ABOVE, Targets.hr(150, maxHr, 2))    // 81 %
        assertEquals(TargetStatus.UNKNOWN, Targets.hr(null, maxHr, 2))
    }

    @Test fun cadenceStatusAgainstRange() {
        assertEquals(TargetStatus.BELOW, Targets.cadence(72, 85, 95))
        assertEquals(TargetStatus.ON, Targets.cadence(85, 85, 95))
        assertEquals(TargetStatus.ON, Targets.cadence(95, 85, 95))
        assertEquals(TargetStatus.ABOVE, Targets.cadence(96, 85, 95))
        assertEquals(TargetStatus.UNKNOWN, Targets.cadence(0, 85, 95))
    }

    @Test fun gaugeScaleAndFractions() {
        assertEquals(300, Targets.powerGaugeMaxW(ftp))                 // 1.5 × 200
        assertEquals(315, Targets.powerGaugeMaxW(210))
        assertEquals(300, Targets.powerGaugeMaxW(150))                 // floor at 300 W
        assertEquals(0.5f, Targets.gaugeFraction(150, 300), 1e-6f)
        assertEquals(1f, Targets.gaugeFraction(900, 300), 1e-6f)      // clamped
        assertEquals(0f, Targets.gaugeFraction(null, 300), 1e-6f)
    }

    @Test fun targetLineSitsMidZone() {
        // Z2 at FTP 200 = 110..150 W → mid 130 → 130/300
        assertEquals(130f / 300f, Targets.powerTargetFraction(2, ftp), 1e-4f)
        assertEquals(0.65f, Targets.hrTargetFraction(2), 1e-6f)
        assertEquals(0.75f, Targets.hrTargetFraction(3), 1e-6f)
    }

    @Test fun zoneTicksAreMonotonicWithinGauge() {
        val t = Targets.powerZoneTicks(ftp)
        assertEquals(6, t.size)
        for (i in 1 until t.size) assertTrue(t[i] >= t[i - 1])
        assertTrue(t.last() <= 1f)
        assertEquals(0.55f * 200 / 300, t[0], 1e-5f)
    }

    @Test fun zonePercentProgressesThroughZone() {
        // Z2 at FTP 200 = 110..150 W
        assertEquals(100, Targets.powerZonePercent(110, ftp))   // 110 W is the very top of Z1 (bounds are inclusive)
        assertEquals(50, Targets.powerZonePercent(130, ftp))
        assertEquals(100, Targets.powerZonePercent(150, ftp))
        assertNull(Targets.powerZonePercent(0, ftp))
        // HR Z2 = 111..129.5 at max 185
        assertEquals(50.0, Targets.hrZonePercent(120, maxHr)!!.toDouble(), 3.0)
        assertNull(Targets.hrZonePercent(null, maxHr))
    }

    @Test fun coachShapeAndDirectionFromCue() {
        assertEquals(CoachShape.UP, Targets.coachShape(CueType.PEDAL_FASTER)); assertEquals(1, Targets.coachDirection(CueType.PEDAL_FASTER))
        assertEquals(CoachShape.UP, Targets.coachShape(CueType.PUSH_HARDER))
        assertEquals(CoachShape.CHECK, Targets.coachShape(CueType.KEEP_IT_UP)); assertEquals(0, Targets.coachDirection(CueType.KEEP_IT_UP))
        assertEquals(CoachShape.DOWN, Targets.coachShape(CueType.EASE_OFF)); assertEquals(-1, Targets.coachDirection(CueType.EASE_OFF))
        assertEquals(CoachShape.DOWN, Targets.coachShape(CueType.PEDAL_SLOWER))
        assertEquals(CoachShape.NONE, Targets.coachShape(CueType.NO_HR)); assertEquals(0, Targets.coachDirection(CueType.NO_HR))
        assertEquals(CoachShape.NONE, Targets.coachShape(CueType.NONE))
    }

    @Test fun targetZonePerMode() {
        assertEquals(2, Targets.targetZone(CoachMode.ZONE2))
        assertEquals(3, Targets.targetZone(CoachMode.ENDURANCE))
        assertEquals(2, Targets.targetZone(CoachMode.CADENCE))
    }

    // ---- Normalized power / variability (RideStats) ----
    private fun s(p: Int) = XdsSample(p, p / 2, p / 2, 90, 10, 0)

    @Test fun steadyPowerHasVariabilityOne() {
        val st = RideStats(); st.start(0)
        for (t in 0..60) st.onSample(s(200), t * 1000L)
        assertEquals(200, st.normalizedPowerW)
        assertEquals(1.0, st.variabilityIndex!!, 0.01)
    }

    @Test fun npIsNullBeforeThirtySeconds() {
        val st = RideStats(); st.start(0)
        for (t in 0..20) st.onSample(s(200), t * 1000L)
        assertNull(st.normalizedPowerW)
        assertNull(st.variabilityIndex)
    }

    @Test fun surgesRaiseNpAboveAverage() {
        val st = RideStats(); st.start(0)
        // 2 min alternating 60 s at 100 W and 60 s at 300 W: avg 200, NP well above
        for (t in 0..239) st.onSample(s(if ((t / 60) % 2 == 0) 100 else 300), t * 1000L)
        assertEquals(200, st.avgPowerW)
        assertTrue("NP should exceed avg on surges", st.normalizedPowerW!! > 215)
        assertTrue(st.variabilityIndex!! > 1.05)
    }

    @Test fun pausedSamplesDoNotFeedNp() {
        val st = RideStats(); st.start(0)
        for (t in 0..40) st.onSample(s(200), t * 1000L)
        st.pause(41_000)
        for (t in 41..100) st.onSample(s(900), t * 1000L)   // ignored while paused
        assertEquals(200, st.normalizedPowerW)
    }
}
