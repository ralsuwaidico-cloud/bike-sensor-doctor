package com.rashed.bikesensordoctor.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class AutoFtpTest {
    private val now = 1_800_000_000_000L

    @Test fun starting_ftp_is_weight_times_experience_wkg() {
        assertEquals(225, StartingFtp.watts(75, "recreational"))      // intermediate 3.00 W/kg
        assertEquals(131, StartingFtp.watts(75, "new"))               // beginner 1.75
        assertEquals(169, StartingFtp.watts(75, "returning"))         // novice 2.25
        assertEquals(300, StartingFtp.watts(75, "experienced"))       // advanced 4.00
        assertEquals(375, StartingFtp.watts(75, "competitive"))       // competitive 5.00
        assertNull(StartingFtp.watts(null, "new")); assertNull(StartingFtp.watts(75, null)); assertNull(StartingFtp.watts(20, "new"))
    }

    @Test fun assumption_is_applied_only_when_no_credible_ftp_exists() {
        val a = RiderAnswers(mapOf("weightKg" to "75", "experience" to "recreational"))
        assertTrue(StartingFtp.applyIfMissing(a)); assertEquals(225, a.metric("ftp")!!.value); assertEquals("assumed", a.metric("ftp")!!.how)
        assertTrue(FtpHistory.lines(a).first().startsWith("Starting FTP 225 W"))
        // weight changes → assumption follows (still an assumption)
        a["weightKg"] = "80"; assertTrue(StartingFtp.applyIfMissing(a)); assertEquals(240, a.metric("ftp")!!.value)
        // a tested value is preserved
        val b = RiderAnswers(mapOf("weightKg" to "75", "experience" to "recreational", "ftp.value" to "260", "ftp.how" to "measured"))
        assertFalse(StartingFtp.applyIfMissing(b)); assertEquals(260, b.metric("ftp")!!.value)
        val c = RiderAnswers(mapOf("weightKg" to "75", "experience" to "recreational", "ftp.value" to "210", "ftp.how" to "estimated"))
        assertFalse(StartingFtp.applyIfMissing(c)); assertEquals("estimated", c.metric("ftp")!!.how)
    }

    private fun ride(n: Int, base: Int, effortStart: Int = -1, effortW: Int = 0, effortLen: Int = 1200): List<Int?> =
        (0 until n).map { t -> if (effortStart >= 0 && t in effortStart until effortStart + effortLen) effortW + ((t % 7) - 3) else if (t % 300 == 299) 0 else base + ((t % 11) - 5) }

    @Test fun mmp_tracks_best_windows_and_breaks_on_gaps() {
        val p = ride(3600, 150, effortStart = 1200, effortW = 230)
        val best = MmpTracker().compute(p)
        val b20 = best.first { it.durationSec == 1200 }
        assertTrue("MMP20 ${b20.meanW}", b20.meanW in 226..232); assertEquals(1200, b20.startIndex); assertTrue(b20.cv < 0.05)
        assertTrue(best.first { it.durationSec == 60 }.meanW >= b20.meanW)
        // a gap of missing seconds inside the effort makes windows crossing it invalid (no interpolation)
        val gappy = p.mapIndexed { i, v -> if (i in 1500..1700) null else v }
        val g20 = MmpTracker().compute(gappy).first { it.durationSec == 1200 }
        val missing = (g20.startIndex until g20.startIndex + 1200).count { gappy[it] == null }
        assertTrue("a window may contain at most 5 % missing seconds (had $missing)", missing <= 60)
    }

    @Test fun an_ordinary_endurance_ride_is_not_ftp_evidence_but_a_sustained_effort_is() {
        val cruise = ride(3600, 150)
        val bc = MmpTracker().compute(cruise).first { it.durationSec == 1200 }
        assertFalse("steady endurance ride gives no FTP evidence", QualifyingEffort.ftp20(bc, cruise))
        val effort = ride(3600, 150, effortStart = 600, effortW = 230)
        val be = MmpTracker().compute(effort).first { it.durationSec == 1200 }
        assertTrue(QualifyingEffort.ftp20(be, effort))
        // a ragged 'effort' (surging) does not qualify
        val ragged = (0 until 3600).map { t -> if (t in 600..1800) (if ((t / 20) % 2 == 0) 320 else 140) else 150 }
        val br = MmpTracker().compute(ragged).first { it.durationSec == 1200 }
        assertFalse(QualifyingEffort.ftp20(br, ragged))
    }

    @Test fun policy_auto_applies_over_an_assumption_and_proposes_over_a_tested_value() {
        val assumed = Metric(225, "assumed"); val tested = Metric(225, "measured"); val auto = Metric(225, "auto")
        val weak = Estimate(MetricKind.FTP, 195, Method.PASSIVE_MMP, 0.40, EstimateStatus.GENERIC, Components(1.0, 0.0, 0.6, 1.0, 0.25), listOf("e1"))
        val ok = weak.copy(confidence = 0.55, status = EstimateStatus.PROVISIONAL)
        assertEquals(FtpPolicy.Decision.NONE, FtpPolicy.decide(assumed, weak))                 // insufficient evidence → keep the assumption
        assertEquals(FtpPolicy.Decision.AUTO_APPLY, FtpPolicy.decide(assumed, ok))              // decrease applied automatically
        assertEquals(FtpPolicy.Decision.AUTO_APPLY, FtpPolicy.decide(auto, ok.copy(value = 240)))   // later increase applied automatically
        assertEquals(FtpPolicy.Decision.PROPOSE, FtpPolicy.decide(tested, ok))                  // calibrated value → propose
        assertEquals(FtpPolicy.Decision.NONE, FtpPolicy.decide(assumed, ok.copy(value = 228)))  // not a meaningful change
        assertEquals(FtpPolicy.Decision.NONE, FtpPolicy.decide(assumed, null))
        val a = RiderAnswers(mapOf("ftp.value" to "225", "ftp.how" to "assumed"))
        FtpPolicy.apply(a, ok)
        assertEquals(195, a.metric("ftp")!!.value); assertEquals("auto", a.metric("ftp")!!.how)
        assertTrue(FtpHistory.lines(a).last(), FtpHistory.lines(a).last().startsWith("Your starting FTP 225 W (assumption) → estimated FTP is now 195 W (lower)"))
    }

    @Test fun stages_and_window_averages() {
        assertEquals(LearningStage.LEARNING, LearningStage.of(0)); assertEquals(LearningStage.LEARNING, LearningStage.of(2))
        assertEquals(LearningStage.UNDERSTANDING, LearningStage.of(3)); assertEquals(LearningStage.PERSONALISED, LearningStage.of(8))
        val w = WindowAverages.of(power = listOf(200, 200, 0, 0, null, 200), cad = listOf(90, 90, 0, 0, null, 90), hr = listOf(null, null, 140, 142, null, null))
        assertEquals(120, w.powerW); assertEquals(5, w.powerSec)                // zeros counted, the missing second excluded
        assertEquals(54, w.cadElapsedRpm); assertEquals(90, w.cadPedallingRpm)  // elapsed vs pedalling-only
        assertEquals(141, w.hrBpm); assertEquals(2, w.hrSec)
        assertNull(WindowAverages.of(listOf(null, null), listOf(null), listOf(null)).powerW)   // a disconnected sensor is never zero
    }

    @Test fun meter_verification_needs_pedalling_coasts_and_clean_values_and_ignores_simulation() {
        val m = MeterVerification()
        repeat(700) { m.tick(180, 85, 100, simulated = false) }
        assertFalse("no coasts yet", m.verified); assertTrue(m.reason.startsWith("coasting checks"))
        repeat(3) { repeat(5) { m.tick(0, 0, 100, false) }; repeat(30) { m.tick(170, 80, 100, false) } }
        assertTrue(m.reason, m.verified)
        val s = MeterVerification(); repeat(2000) { s.tick(180, 85, 100, simulated = true) }; assertFalse("simulation never verifies", s.verified)
        val bad = MeterVerification(); repeat(650) { bad.tick(180, 85, 100, false) }; bad.tick(3000, 85, 100, false); repeat(3) { repeat(5) { bad.tick(0, 0, 100, false) }; repeat(30) { bad.tick(170, 80, 100, false) } }
        assertFalse("an impossible value blocks verification", bad.verified)
        val inconsistent = MeterVerification(); repeat(700) { inconsistent.tick(if (it % 10 == 0) 0 else 180, 85, 100, false) }
        assertFalse(inconsistent.verified); assertTrue(inconsistent.reason.startsWith("power missing while pedalling"))
    }
}
