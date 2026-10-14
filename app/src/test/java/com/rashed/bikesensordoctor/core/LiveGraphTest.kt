package com.rashed.bikesensordoctor.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test

class LiveGraphTest {
    private val bands = GraphBands(pwLo = 105, pwHi = 139, hrLo = 139, hrHi = 151, cadLo = 80, cadHi = 95)

    @Test fun normalisation_is_per_signal_against_its_own_band() {
        assertEquals(0f, GraphScale.norm(105, 105, 139)!!, 1e-6f)
        assertEquals(1f, GraphScale.norm(139, 105, 139)!!, 1e-6f)
        assertEquals(0.5f, GraphScale.norm(145, 139, 151)!!, 1e-6f)      // HR mid-band
        assertEquals(0.5f, GraphScale.norm(122, 105, 139)!!, 1e-6f)      // power mid-band → same height
        assertNull(GraphScale.norm(null, 105, 139))                        // missing reading
        assertNull(GraphScale.norm(120, null, null))                       // no band (power unverified)
    }

    @Test fun band_edges_map_to_the_same_plot_height_for_every_signal() {
        val top = GraphScale.yFrac(1f); val bot = GraphScale.yFrac(0f)
        assertEquals(GraphScale.BAND_H, bot - top, 1e-6f)
        assertEquals(0.5f, (top + bot) / 2, 1e-6f)
        // monotonic: higher values are always higher on the plot, even deep in the compressed zone
        var last = 2f
        for (n in -40..40) { val y = GraphScale.yFrac(n / 4f); assertTrue("y must decrease as n grows", y < last); last = y }
        // 999 W vs 300 W against a 105–139 band: both above, 999 W visibly higher but still inside the plot
        val y999 = GraphScale.yFrac(GraphScale.norm(999, 105, 139)!!); val y300 = GraphScale.yFrac(GraphScale.norm(300, 105, 139)!!)
        assertTrue(y999 < y300); assertTrue(y999 >= 0.01f)
    }

    @Test fun status_uses_the_band_and_keeps_zero_as_a_real_value() {
        assertEquals(GraphStatus.ON, GraphScale.status(120, 105, 139))
        assertEquals(GraphStatus.BELOW, GraphScale.status(90, 105, 139))
        assertEquals(GraphStatus.ABOVE, GraphScale.status(160, 105, 139))
        assertEquals(GraphStatus.ZERO, GraphScale.status(0, 105, 139))        // coasting: a value, not a gap
        assertEquals(GraphStatus.NONE, GraphScale.status(null, 105, 139))     // disconnected
        assertEquals(GraphStatus.NONE, GraphScale.status(120, null, null))    // reading but no band
    }

    @Test fun buffer_is_fixed_size_and_keeps_the_newest_samples() {
        val b = LiveBuffer(5)
        for (s in 0 until 8) b.add(s, 100 + s, 140, 85, bands, Phase.MAIN)
        assertEquals(5, b.size)
        assertEquals(3, b.secAt(0)); assertEquals(7, b.secAt(4))
        assertEquals(107, b.powerAt(4))
        assertEquals(8L, b.version)
    }

    @Test fun gaps_stay_gaps_and_zero_power_is_a_value() {
        val b = LiveBuffer(10)
        b.add(0, 120, 140, 85, bands, Phase.MAIN)
        b.add(1, null, null, null, bands, Phase.MAIN)      // meter + strap dropped
        b.add(2, 0, 141, 0, bands, Phase.MAIN)             // coasting
        assertTrue(b.norm(LiveBuffer.Signal.POWER, 1).isNaN()); assertTrue(b.norm(LiveBuffer.Signal.HR, 1).isNaN())
        assertFalse(b.norm(LiveBuffer.Signal.POWER, 2).isNaN()); assertTrue(b.norm(LiveBuffer.Signal.POWER, 2) < 0f)
        assertEquals(0, b.powerAt(2)); assertNull(b.powerAt(1))
        assertEquals(GraphStatus.ZERO, GraphScale.status(b.powerAt(2), 105, 139))
    }

    @Test fun three_second_power_never_bridges_a_gap() {
        val b = LiveBuffer(10)
        b.add(0, 100, null, null, bands, Phase.MAIN); b.add(1, 200, null, null, bands, Phase.MAIN); b.add(2, 300, null, null, bands, Phase.MAIN)
        assertEquals(200, b.power3sAt(2))
        b.add(3, null, null, null, bands, Phase.MAIN); assertNull(b.power3sAt(3))
        b.add(4, 400, null, null, bands, Phase.MAIN); assertEquals(350, b.power3sAt(4))   // (300 + 400) / 2 — the gap is skipped, not filled
    }

    @Test fun the_band_in_force_at_the_time_is_what_the_sample_is_scaled_against() {
        val b = LiveBuffer(10)
        b.add(0, 120, 145, 85, GraphBands(105, 139, 120, 130, 80, 95), Phase.WARMUP)   // warm-up ceiling 130 → 145 was ABOVE then
        b.add(1, 120, 145, 85, bands, Phase.MAIN)                                      // main band 139–151 → on target now
        assertTrue(b.norm(LiveBuffer.Signal.HR, 0) > 1f)
        assertTrue(b.norm(LiveBuffer.Signal.HR, 1) in 0f..1f)
        assertEquals(Phase.WARMUP, b.phaseAt(0)); assertEquals(Phase.MAIN, b.phaseAt(1))
    }

    @Test fun decimation_keeps_peaks_and_gaps() {
        val vals = FloatArray(600) { 0.5f }; vals[321] = 3f; vals[322] = -2f          // one-second spike and dip
        for (k in 100 until 130) vals[k] = Float.NaN                                    // 30-s drop-out
        val out = GraphDecimate.minMax(0, 600, 150) { vals[it] }
        val ys = (0 until out.size / 2).map { out[2 * it + 1] }
        assertTrue(ys.any { it == 3f }); assertTrue(ys.any { it == -2f })
        assertTrue("the gap must survive as NaN", ys.any { it.isNaN() })
        assertTrue(ys.size <= 150 * 2)
        // small windows are passed through untouched
        val small = GraphDecimate.minMax(0, 60, 150) { 1f }
        assertEquals(120, small.size)
    }

    @Test fun sustained_breaches_only() {
        val n = FloatArray(100) { 0.5f }
        for (k in 10 until 40) n[k] = 1.4f       // 30 s above
        for (k in 50 until 60) n[k] = -0.3f      // 10 s below (too short)
        for (k in 70 until 95) n[k] = 1.2f; n[80] = Float.NaN   // above, broken by one missing second → two runs of 10 and 14
        val br = GraphBreaches.find(0, 100, 20) { n[it] }
        assertEquals(listOf(Breach(10, 40, 1)), br)
    }

    @Test fun fallback_bands_come_from_the_zones_when_no_workout_runs() {
        val b = GraphBands.resolve(null, ftpW = 200, powerTrusted = true, maxHr = 185, targetZone = 2, cadLo = 80, cadHi = 95)
        assertEquals(112, b.hrLo); assertEquals(129, b.hrHi)        // Z2 = 60–70 % of max HR
        assertEquals(111, b.pwLo); assertEquals(150, b.pwHi)        // Z2 = 55–75 % of FTP
        assertFalse(b.pwReference)
        val noPower = GraphBands.resolve(null, ftpW = 200, powerTrusted = false, maxHr = 185, targetZone = 2, cadLo = 80, cadHi = 95)
        assertEquals(111, noPower.pwLo); assertTrue("unverified meter: the trace is still drawn, against a labelled reference", noPower.pwReference)
        val noFtp = GraphBands.resolve(null, ftpW = 0, powerTrusted = false, maxHr = 185, targetZone = 2, cadLo = 80, cadHi = 95)
        assertEquals(100, noFtp.pwLo); assertEquals(200, noFtp.pwHi); assertTrue(noFtp.pwReference)
        val t = ActiveTargets(139, 151, 105, 139, 80, 95, "MAIN")
        assertEquals(GraphBands(105, 139, 139, 151, 80, 95), GraphBands.resolve(t, 200, true, 185, 2, 80, 95))
        val tNoPw = ActiveTargets(139, 151, null, null, 80, 95, "MAIN")
        assertTrue(GraphBands.resolve(tNoPw, 200, false, 185, 2, 80, 95).pwReference)
    }
}
