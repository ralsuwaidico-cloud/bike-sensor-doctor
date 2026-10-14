package com.rashed.bikesensordoctor.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test

class PerformanceTest {
    private val now = 1_800_000_000_000L
    private val day = 24 * 3600 * 1000L

    @Test fun ftp20_is_95_percent_of_the_block_and_needs_the_protocol() {
        val e = Performance.ftp20(200.0, verifiedDevice = true, simulated = false, validFraction = 1.0, pausedSec = 0, atMs = now, rideId = 1)
        assertEquals(190, e!!.value); assertEquals(Method.FTP20_95_PERCENT, e.method)
        assertNull("simulated never", Performance.ftp20(200.0, true, true, 1.0, 0, now, 1))
        assertNull("unverified never", Performance.ftp20(200.0, false, false, 1.0, 0, now, 1))
        assertNull("10 % missing → invalid", Performance.ftp20(200.0, true, false, 0.88, 0, now, 1))
        assertNull("paused → invalid", Performance.ftp20(200.0, true, false, 1.0, 5, now, 1))
    }

    @Test fun simulated_and_unverified_evidence_is_inadmissible() {
        val sim = Evidence("a", MetricKind.FTP, 200, Method.FTP20_95_PERCENT, now, simulated = true)
        val unv = Evidence("b", MetricKind.FTP, 200, Method.FTP20_95_PERCENT, now, verifiedDevice = false)
        val syn = Evidence("c", MetricKind.FTP, 200, Method.SYNTHETIC_WATTS, now)
        val poor = Evidence("d", MetricKind.FTP, 200, Method.FTP20_95_PERCENT, now, dataQuality = 0.5)
        listOf(sim, unv, syn, poor).forEach { assertFalse(it.id, Performance.admissible(it)) }
        assertNull(Performance.estimate(MetricKind.FTP, listOf(sim, unv, syn, poor), now))
    }

    @Test fun one_field_test_is_provisional_never_verified() {
        val e = Performance.estimate(MetricKind.FTP, listOf(Evidence("t1", MetricKind.FTP, 210, Method.FTP20_95_PERCENT, now)), now)!!
        assertEquals(210, e.value); assertEquals(EstimateStatus.PROVISIONAL, e.status)
        assertTrue(e.confidence < 0.70)
    }

    @Test fun two_agreeing_tests_raise_confidence_to_high_but_a_field_method_is_capped() {
        val ev = listOf(Evidence("t1", MetricKind.FTP, 210, Method.FTP20_95_PERCENT, now - 10 * day, sourceRideId = 1), Evidence("t2", MetricKind.FTP, 214, Method.FTP20_95_PERCENT, now, sourceRideId = 2))
        val e = Performance.estimate(MetricKind.FTP, ev, now)!!
        assertEquals(EstimateStatus.HIGH, e.status); assertTrue(e.confidence <= 0.80)
        assertEquals("high-confidence field estimate", e.label)
    }

    @Test fun a_weak_method_repeated_100_times_cannot_exceed_its_ceiling() {
        val ev = (0 until 100).map { Evidence("m$it", MetricKind.FTP, 200, Method.PASSIVE_MMP, now - it * day, sourceRideId = it.toLong()) }
        val e = Performance.estimate(MetricKind.FTP, ev, now)!!
        assertTrue("confidence ${e.confidence}", e.confidence <= 0.65); assertEquals(EstimateStatus.PROVISIONAL, e.status)
        val age = (0 until 100).map { Evidence("a$it", MetricKind.THRESHOLD_HR, 160, Method.AGE_PERCENT, now, sourceRideId = it.toLong()) }
        assertEquals(EstimateStatus.UNKNOWN, Performance.estimate(MetricKind.THRESHOLD_HR, age, now)!!.status)
    }

    @Test fun the_strongest_method_present_wins_and_lab_may_be_verified() {
        val ev = listOf(Evidence("p", MetricKind.FTP, 190, Method.PASSIVE_MMP, now, sourceRideId = 1), Evidence("l", MetricKind.FTP, 205, Method.LAB_THRESHOLD_POWER, now, sourceRideId = 2), Evidence("l2", MetricKind.FTP, 206, Method.LAB_THRESHOLD_POWER, now - day, sourceRideId = 3))
        val e = Performance.estimate(MetricKind.FTP, ev, now)!!
        assertEquals(Method.LAB_THRESHOLD_POWER, e.method); assertEquals(205, e.value)
        // same confidence from a field test could never be VERIFIED
        assertEquals(EstimateStatus.HIGH, Performance.status(0.95, Method.STRUCTURED_FTP_TEST))
        assertEquals(EstimateStatus.VERIFIED, Performance.status(0.95, Method.LAB_THRESHOLD_POWER))
    }

    @Test fun critical_power_recovers_synthetic_cp_and_wprime_and_stays_separate_from_ftp() {
        val cp = 250.0; val w = 18_000.0
        val efforts = listOf(180, 420, 720, 1200).map { t -> t to cp + w / t }
        val fit = Performance.criticalPower(efforts)!!
        assertEquals(250, fit.cpW); assertTrue("W' ${fit.wPrimeJ}", Math.abs(fit.wPrimeJ - 18_000) <= 50)
        val ev = Performance.cpEvidence(fit, verifiedDevice = true, simulated = false, atMs = now, rideId = 9)!!
        assertEquals(MetricKind.CRITICAL_POWER, ev.metric)
        assertNull("CP evidence never counts toward FTP", Performance.estimate(MetricKind.FTP, listOf(ev), now))
        assertNull("insufficient duration spread", Performance.criticalPower(listOf(180 to 300.0, 240 to 290.0, 300 to 285.0)))
        assertNull("too few efforts", Performance.criticalPower(listOf(180 to 300.0, 1200 to 260.0)))
    }

    @Test fun threshold_hr_candidate_needs_a_steady_plateau() {
        val hr = (0 until 1800).map { t -> if (t < 600) 120 + t / 10 else 162 + (t % 7) - 3 }
        val e = Performance.thresholdHrCandidate(hr, null, 600, Method.FIELD_30MIN_HR, now, 3)!!
        assertEquals(MetricKind.THRESHOLD_HR, e.metric); assertTrue("value ${e.value}", e.value in 160..164)
        assertEquals(EstimateStatus.PROVISIONAL, Performance.estimate(MetricKind.THRESHOLD_HR, listOf(e), now)!!.status)
        // drifting plateau → no candidate; unsteady power → no candidate; too much missing HR → no candidate
        assertNull(Performance.thresholdHrCandidate((0 until 1800).map { 140 + it / 30 }, null, 600, Method.FIELD_30MIN_HR, now, 3))
        assertNull(Performance.thresholdHrCandidate(hr, (0 until 1800).map { if ((it / 60) % 2 == 0) 150 else 260 }, 600, Method.FIELD_30MIN_HR, now, 3))
        assertNull(Performance.thresholdHrCandidate(hr.mapIndexed { i, v -> if (i % 5 == 0) null else v }, null, 600, Method.FIELD_30MIN_HR, now, 3))
    }

    @Test fun estimates_change_meaningfully_or_not_at_all() {
        assertTrue(Performance.meaningfullyDiffers(MetricKind.FTP, 205, 214))
        assertFalse(Performance.meaningfullyDiffers(MetricKind.FTP, 205, 208))
        assertTrue(Performance.meaningfullyDiffers(MetricKind.THRESHOLD_HR, 160, 163)); assertFalse(Performance.meaningfullyDiffers(MetricKind.THRESHOLD_HR, 160, 162))
        val old = Performance.estimate(MetricKind.FTP, listOf(Evidence("t1", MetricKind.FTP, 205, Method.FTP20_95_PERCENT, now - day)), now)!!
        assertNotNull(old.evidenceIds.first())
    }
}
