package com.rashed.bikesensordoctor.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Mirrors design/demo_src/app_part.js deriveConfig / recommend so app and demo agree. */
class RiderProfileTest {
    private fun omar() = RiderAnswers(mapOf("age" to "38", "experience" to "experienced", "primary" to "endurance", "goals" to "endurance",
        "ridesNow" to "4", "daysAvail" to "5", "typicalMin" to "90", "longestMin" to "150", "hrMode" to "know",
        "maxHr.value" to "186", "maxHr.how" to "measured", "restHr.value" to "52", "restHr.how" to "measured", "lthr.value" to "168", "lthr.how" to "measured",
        "pwMode" to "know", "ftp.value" to "245", "ftp.how" to "measured", "cadence.value" to "88", "cadence.how" to "measured",
        "voice" to "voice", "freq" to "important", "cadAdvice" to "yes", "heat" to "yes", "tone" to "technical"))

    @Test fun thresholdZonesAreConfirmed() {
        val c = RiderProfile.deriveSetup(omar())
        assertEquals(139, c.hrTargetLo); assertEquals(151, c.hrTargetHi); assertEquals(151, c.hrCap)
        assertEquals(ZoneConfidence.CONFIRMED, c.zoneConfidence)
        assertTrue(c.powerCoaching); assertEquals(245, c.ftp); assertEquals(135, c.powerLo); assertEquals(184, c.powerHi)
        assertEquals(83, c.cadLow); assertEquals(93, c.cadHigh)
        assertEquals(8 * 60, c.warmupSec); assertEquals(8 * 60, c.cooldownSec)   // heat +3
        assertEquals(90_000L, c.sameRepeatMs); assertEquals(0L, c.keepRepeatMs)
    }

    @Test fun genericWhenNothingKnown() {
        val a = RiderAnswers(mapOf("experience" to "new", "primary" to "fitness", "hrMode" to "later", "pwMode" to "unknown", "voice" to "voice", "freq" to "frequent"))
        val c = RiderProfile.deriveSetup(a)
        assertEquals(ZoneConfidence.GENERIC, c.zoneConfidence); assertEquals(185, c.maxHrEstimate)
        assertEquals(111, c.hrTargetLo); assertEquals(130, c.hrTargetHi)   // 185*0.6=111, 185*0.7=129.5→130
        assertFalse(c.powerCoaching); assertFalse(c.ftpKnown)
        assertEquals(8 * 60, c.warmupSec)   // new rider +3
    }

    @Test fun tanakaWhenOnlyAgeKnown() {
        val a = RiderAnswers(mapOf("age" to "27", "experience" to "new", "primary" to "fitness", "hrMode" to "estimate", "pwMode" to "unknown", "voice" to "voice", "freq" to "frequent"))
        val c = RiderProfile.deriveSetup(a)
        assertEquals(189, c.maxHrEstimate); assertEquals(113, c.hrTargetLo); assertEquals(132, c.hrTargetHi)
    }

    @Test fun karvonenWhenMaxAndRest() {
        val a = RiderAnswers(mapOf("maxHr.value" to "180", "maxHr.how" to "measured", "restHr.value" to "60", "restHr.how" to "measured"))
        val c = RiderProfile.deriveSetup(a)
        assertEquals(132, c.hrTargetLo); assertEquals(144, c.hrTargetHi); assertEquals(ZoneConfidence.PROVISIONAL, c.zoneConfidence)
    }

    @Test fun struggleLowersCeiling() {
        val a = omar(); a["struggleZ2"] = "yes"
        assertEquals(148, RiderProfile.deriveSetup(a).hrCap)
    }

    @Test fun recommendationFollowsGoalAndFeedback() {
        val a = omar(); val c = RiderProfile.deriveSetup(a)
        val w = RiderProfile.recommend(a, c, emptyList(), 1)
        assertEquals("Zone 2 endurance", w.name); assertEquals(90, w.minutes); assertEquals(139, w.hrLo); assertEquals(151, w.hrHi); assertEquals(135, w.pwLo)
        val hard = RiderProfile.recommend(a, c, listOf(RideFeedback(0, 70, 5, 150, 3600, rpe = 9)), 1)
        assertEquals("rec", hard.kind); assertEquals(40, hard.minutes); assertEquals(124, hard.hrLo); assertEquals(138, hard.hrHi)
        val easy = RiderProfile.recommend(a, c, listOf(RideFeedback(0, 85, 3, 140, 3600, rpe = 3)), 1)
        assertEquals(100, easy.minutes)   // 90 * 1.1 = 99 → nearest 5 = 100, capped at longest 150
    }

    @Test fun ftpGoalWithKnownFtpGivesSweetSpot() {
        val a = RiderAnswers(mapOf("primary" to "ftp", "ftp.value" to "210", "ftp.how" to "measured", "typicalMin" to "75", "longestMin" to "120", "experience" to "experienced"))
        val w = RiderProfile.recommend(a, RiderProfile.deriveSetup(a), emptyList(), 1)
        assertEquals("ss", w.kind); assertEquals(185, w.pwLo); assertEquals(195, w.pwHi); assertEquals(75, w.minutes)
    }

    @Test fun weightsYesterdayKeepsEasy() {
        val a = RiderAnswers(mapOf("primary" to "ftp", "ftp.value" to "210", "ftp.how" to "measured", "other" to "weights", "otherDays" to "Mon", "typicalMin" to "75"))
        val w = RiderProfile.recommend(a, RiderProfile.deriveSetup(a), emptyList(), 1)   // Tuesday
        assertEquals("z2", w.kind); assertTrue(w.why.any { it.contains("weights yesterday") })
    }

    @Test fun followUpsAreProgressive() {
        val a = RiderAnswers(); val log = listOf(RideFeedback(0, 40, 5, 150, 3000), RideFeedback(1, 45, 5, 150, 3000))
        assertEquals("restHr", RiderProfile.followUp(a, log, emptySet())?.key)
        assertEquals("struggleZ2", RiderProfile.followUp(a, log, setOf("restHr"))?.key)
        assertNull(RiderProfile.followUp(a, log, setOf("restHr", "struggleZ2")))
        assertEquals("ftpTest", RiderProfile.followUp(a, log + RideFeedback(2, 90, 2, 140, 3000), setOf("restHr", "struggleZ2"))?.key)
    }

    @Test fun answersRoundTrip() {
        val a = omar(); a.setList("goals", listOf("endurance", "climb"))
        val b = RiderAnswers.restore(a.snapshot())
        assertEquals(a.toMap(), b.toMap()); assertEquals(listOf("endurance", "climb"), b.list("goals"))
        assertNotNull(b.metric("lthr")); assertEquals(168, b.metric("lthr")!!.value)
    }

    @Test fun skipDefaultsMakeEveryPageValid() {
        val a = RiderAnswers(); RiderProfile.skipAll(a)
        for (p in 0..5) assertTrue("page $p", RiderProfile.pageValid(p, a))
        assertEquals(ZoneConfidence.GENERIC, RiderProfile.deriveSetup(a).zoneConfidence)
    }

    @Test fun feedbackRoundTrip() {
        val f = RideFeedback(1234L, 82, 4, 148, 3600, 6, "legs", "yes")
        assertEquals(f, RideFeedback.restore(f.snapshot()))
        val g = RideFeedback(1L, 10, 0, 0, 600)
        assertEquals(g, RideFeedback.restore(g.snapshot()))
    }
}
