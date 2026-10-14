package com.rashed.bikesensordoctor.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RideAnalysisTest {
    /** Rashed's 12 Oct 2026 ride as Apple Fitness reported it (reference fixture, NOT a fitness setting). */
    private val appleZoneSec = intArrayOf(1606, 1262, 956, 80, 0)   // 26:46, 21:02, 15:56, 01:20, 00:00
    private val keys = listOf(0 to 100, 2 to 118, 4 to 132, 6 to 140, 9 to 143, 12 to 138, 14 to 120, 15 to 128, 18 to 150, 22 to 155, 26 to 158, 30 to 160, 32 to 135, 33 to 140, 36 to 158, 40 to 160, 43 to 162, 46 to 150, 50 to 140, 52 to 145, 55 to 158, 58 to 165, 61 to 170, 63 to 173, 64 to 168, 65 to 165)
    private fun interp(tMin: Double): Double { for (i in 1 until keys.size) if (tMin <= keys[i].first) { val (a, va) = keys[i - 1]; val (b, vb) = keys[i]; return va + (vb - va) * (tMin - a) / (b - a).coerceAtLeast(1) }; return keys.last().second.toDouble() }

    private fun oct12(): List<SeriesPoint> = (0 until 3905).map { t -> SeriesPoint(t, hr = Math.round(interp(t / 60.0)).toInt(), speedKmh = if (t % 1000 in 0..20) 0.0 else 19.7, distKm = 21.46 * t / 3904.0, phase = if (t < 300) Phase.WARMUP else if (t >= 3600) Phase.COOLDOWN else Phase.MAIN) }

    @Test fun appleZonesFromTheChartTraceLandNearApplesTotals() {
        val a = RideAnalysis.analyze(oct12(), null, HrZoneSet.APPLE_12_OCT, 200, false, null, 85, 40)
        val z = a.referenceZones!!.sec
        // The trace is read off Apple's chart by hand (26 key points), so each zone can differ by a few minutes from the
        // watch's own second-by-second data. The test documents the agreement, it does not pretend to equality.
        println("12 Oct Apple zones  ours=${z.joinToString()}  apple=${appleZoneSec.joinToString()}")
        for (i in 0 until 5) assertTrue("zone ${i + 1}: ours ${z[i]} s vs Apple ${appleZoneSec[i]} s", Math.abs(z[i] - appleZoneSec[i]) <= 540)
        assertTrue("same ordering Z1 > Z2 > Z3 > Z4 > Z5", z[0] > z[1] && z[1] > z[2] && z[2] > z[3] && z[3] >= z[4] && z[4] == 0)
        assertEquals(3905, z.sum())
        assertEquals("≤ 150", HrZoneSet.APPLE_12_OCT.label(1)); assertEquals("151–160", HrZoneSet.APPLE_12_OCT.label(2)); assertEquals("≥ 179", HrZoneSet.APPLE_12_OCT.label(5))
        assertEquals(150.0, a.avgHr!!.toDouble(), 3.0)   // Apple: 150 bpm average
        assertEquals(21.46, a.distanceKm, 0.01)
        assertEquals(3905, a.durationSec)
        assertTrue(a.movingSec < a.durationSec && a.movingSec > 3800)
        assertNotNull(a.kcal); assertTrue(a.kcalMethod.startsWith("ESTIMATE from heart rate"))
        assertNull("no power → no FTP suggestion", a.suggestions.firstOrNull { it.key == "ftp" })
    }

    @Test fun personalAndReferenceZonesAreKeptApart() {
        val c = RiderProfile.deriveSetup(RiderAnswers(mapOf("lthr.value" to "168", "lthr.how" to "measured")))
        val a = RideAnalysis.analyze(oct12(), HrZoneSet.fromSetup(c), HrZoneSet.APPLE_12_OCT, 200, false, 139..151, 85, 40)
        assertEquals("Your coaching zones", a.personalZones!!.set.name); assertEquals("Apple Fitness (your watch)", a.referenceZones!!.set.name)
        assertEquals("139–151", a.personalZones!!.set.label(2))
        assertTrue(a.personalZones!!.sec.contentEquals(a.referenceZones!!.sec).not())
        assertNotNull(a.inBandPct); assertTrue(a.inBandPct!! in 1..99)
        assertEquals(false, a.objectiveMet)   // most of this ride was above 151
        assertTrue(a.improve.any { it.contains("inside the band") })
    }

    @Test fun powerMetricsOnlyWhenTrusted() {
        val s = (0 until 1800).map { t -> SeriesPoint(t, hr = 145, powerW = 150 + (t % 20), cadRpm = 85, speedKmh = 25.0, distKm = t / 144.0) }
        val trusted = RideAnalysis.analyze(s, null, null, 200, true, null, 80, 38)
        assertEquals(159.0, trusted.avgPowerW!!.toDouble(), 1.0); assertNotNull(trusted.normalizedPowerW); assertTrue(trusted.kcalMethod.contains("measured power"))
        assertEquals(1800, trusted.movingSec)
        val longer = RideAnalysis.analyze((0 until 1500).map { t -> SeriesPoint(t, powerW = 200, cadRpm = 90, speedKmh = 25.0) }, null, null, 200, true, null, 80, 38)
        assertEquals(190, longer.suggestions.first { it.key == "ftp" }.value)   // 0.95 × 200
        val untrusted = RideAnalysis.analyze(s, null, null, 200, false, null, 80, 38)
        assertTrue(untrusted.suggestions.none { it.key == "ftp" }); assertTrue(untrusted.kcalMethod.contains("heart rate"))
    }

    @Test fun driftNeedsComparableHalves() {
        val steady = (0 until 2400).map { t -> SeriesPoint(t, hr = if (t < 1200) 140 else 147, speedKmh = 25.0, phase = Phase.MAIN) }
        val a = RideAnalysis.analyze(steady, null, null, 200, false, 139..151, 80, 38)
        assertEquals(5, a.driftPct)
        val uneven = (0 until 2400).map { t -> SeriesPoint(t, hr = if (t < 1200) 140 else 147, speedKmh = if (t < 1200) 20.0 else 30.0, phase = Phase.MAIN) }
        assertNull(RideAnalysis.analyze(uneven, null, null, 200, false, 139..151, 80, 38).driftPct)
    }

    @Test fun elevationGainAndRecovery() {
        val s = (0 until 600).map { t -> SeriesPoint(t, hr = 150, altM = 10.0 + (t / 60) * 4.0, speedKmh = 20.0) }
        val a = RideAnalysis.analyze(s, null, null, 200, false, null, 80, 38, hrRecovery60 = 120)
        assertEquals(36.0, a.elevationGainM, 0.01)
        assertTrue(a.wentWell.any { it.contains("fell 30 bpm") })
    }

    @Test fun seriesCsvRoundTrip() {
        val p = SeriesPoint(42, 150, 180, 88, 25.4, 12.3, 1.234, 24.4539, 54.3773, Phase.MAIN, true)
        val q = SeriesPoint.parse(p.csv())!!
        assertEquals(p.hr, q.hr); assertEquals(p.powerW, q.powerW); assertEquals(25.4, q.speedKmh!!, 0.01); assertEquals(1.234, q.distKm, 0.001); assertEquals(54.3773, q.lon!!, 1e-5); assertEquals(true, q.inBand)
        assertNull(SeriesPoint.parse(SeriesPoint.HEADER))
        val sparse = SeriesPoint.parse(SeriesPoint(7).csv())!!; assertNull(sparse.hr); assertNull(sparse.lat)
    }
}
