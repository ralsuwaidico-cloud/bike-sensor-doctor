package com.rashed.bikesensordoctor.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertNull
import org.junit.Test

class CoachSummaryTest {
    private val zones = HrZoneSet("Your coaching zones", intArrayOf(110, 129, 148, 167), "PROVISIONAL")
    private val band = 111..129
    private fun ride(n: Int = 3600, cad: Int = 85, hr: (Int) -> Int?): List<SeriesPoint> =
        (0 until n).map { t -> SeriesPoint(t, hr(t), 150, cad, 24.0, 10.0, t * 24.0 / 3600, phase = if (t < 300) Phase.WARMUP else if (t >= n - 300) Phase.COOLDOWN else Phase.MAIN) }
    private fun analyze(s: List<SeriesPoint>, rpe: Int? = null) = RideAnalysis.analyze(s, zones, null, 200, false, band, 85, 40, null, rpe)

    @Test fun too_hard_ride_gives_one_clear_fix_with_the_example_wording() {
        val a = analyze(ride { t -> if (t % 25 == 0) 120 else 150 })    // ~4 % in band, the rest above
        val m = CoachSummary.forRide(a, band, "Zone 2", DetailLevel.SIMPLE, simulated = false, powerTrusted = false)
        assertEquals("Zone 2 performance", m.title)
        assertEquals("${a.inBandPct}% of your ride in target", m.headline)
        assertEquals("You rode harder than planned.", m.verdict)
        assertTrue(m.next, m.next.startsWith("Next ride: reduce your effort to stay in Zone 2"))
        assertEquals(Tone.FIX, m.tone)
        assertTrue(m.why.isNotEmpty() && m.how.contains("main block"))
        // one message: the long explanations are not in the headline/verdict/next
        assertTrue(m.headline.length < 40 && m.verdict.length < 60 && m.next.length < 90)
    }

    @Test fun too_easy_ride_says_so() {
        val a = analyze(ride { 100 })
        val m = CoachSummary.forRide(a, band, "Zone 2", DetailLevel.SIMPLE, false, false)
        assertEquals("You rode easier than planned.", m.verdict); assertEquals(Tone.FIX, m.tone)
    }

    @Test fun good_ride_is_praised_and_progression_depends_on_feel() {
        val s = ride { 120 }
        val easy = CoachSummary.forRide(analyze(s, rpe = 3), band, "Zone 2", DetailLevel.SIMPLE, false, false, rpe = 3)
        assertEquals(Tone.GOOD, easy.tone); assertEquals("Next ride: same again, 5 minutes longer.", easy.next); assertEquals(1f, easy.progress!!, 0.01f)
        val hard = CoachSummary.forRide(analyze(s, rpe = 9), band, "Zone 2", DetailLevel.SIMPLE, false, false, rpe = 9)
        assertEquals(Tone.WATCH, hard.tone); assertEquals("Recovery", hard.title)
    }

    @Test fun technical_level_adds_numbers_simple_hides_them() {
        val a = analyze(ride { 120 })
        val simple = CoachSummary.forRide(a, band, "Zone 2", DetailLevel.SIMPLE, false, false)
        val tech = CoachSummary.forRide(a, band, "Zone 2", DetailLevel.TECHNICAL, false, false)
        assertTrue(tech.details.size > simple.details.size)
        assertTrue(tech.details.any { it.startsWith("HR variation") })
        assertTrue(simple.details.none { it.startsWith("HR variation") })
        assertEquals(DetailLevel.TECHNICAL, DetailLevel.from(RiderAnswers(mapOf("experience" to "experienced"))))
        assertEquals(DetailLevel.SIMPLE, DetailLevel.from(RiderAnswers(mapOf("experience" to "new"))))
    }

    @Test fun no_heart_rate_and_free_ride_are_informational() {
        val noHr = CoachSummary.forRide(analyze(ride { null }), band, "Zone 2", DetailLevel.SIMPLE, false, false)
        assertEquals(Tone.INFO, noHr.tone); assertNull(noHr.progress); assertTrue(noHr.next.contains("strap"))
        val free = CoachSummary.forRide(RideAnalysis.analyze(ride { 140 }, zones, null, 200, false, null, 85, 40), null, "Zone 2", DetailLevel.SIMPLE, false, false)
        assertEquals("Free ride", free.title); assertTrue(free.headline.contains("Zone 3"))
    }

    @Test fun provenance_tags_once() {
        val p = CoachSummary.provenance(simulated = true, powerTrusted = false, hasHr = true, hasGps = false, hasPower = true)
        assertEquals(listOf("heart rate" to Provenance.SIMULATED, "power · cadence" to Provenance.SIMULATED, "calories" to Provenance.ESTIMATE), p)
        val real = CoachSummary.provenance(false, false, true, true, true)
        assertEquals(Provenance.UNVERIFIED, real.first { it.first.startsWith("power") }.second)
    }
}
