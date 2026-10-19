package com.rashed.bikesensordoctor.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** v0.11: coaching from the first ride — no strap, FTP only an assumption; and with no effort sensors at all. */
class CoachNoStrapTest {
    private fun engine() = CoachEngine(CoachConfig(mode = CoachMode.ZONE2, maxHr = 185, ftpW = 225, ftpAssumed = true, cadenceEnabled = true, cadenceLow = 80, cadenceHigh = 95, graceMs = 0, keepRepeatMs = 90_000))
    private val main = ActiveTargets(111, 129, 124, 169, 80, 95, "MAIN")
    private fun run(e: CoachEngine, from: Int, to: Int, pw: (Int) -> Int?, cad: Int? = 85, speed: Double = 24.0, out: MutableList<Pair<Int, CoachCue>>) {
        for (t in from until to) { val c = e.update(CoachInput(t * 1000L, Phase.MAIN, Signal(cad), Signal.NONE, Signal(pw(t)), main, speed)); if (c.type != CueType.NONE) out += t to c }
    }

    @Test fun relative_mode_praises_steady_riding_and_names_a_power_drop_without_claiming_zones() {
        val e = engine(); val out = ArrayList<Pair<Int, CoachCue>>()
        run(e, 0, 900, { 160 + (it % 5) }, out = out)                       // 15 min steady
        val good = out.firstOrNull { it.second.action == CoachAction.HOLD_PACE }
        assertTrue("steady riding is acknowledged: ${out.map { it.second.action }}", good != null)
        assertEquals("Good pace — hold this effort", good!!.second.short)
        assertTrue(out.any { it.second.action == CoachAction.STEADY_MILESTONE && it.second.headline.contains("10 MINUTES") })
        run(e, 900, 1100, { 120 }, out = out)                                // output falls 25 % for 3 min
        val drop = out.firstOrNull { it.second.action == CoachAction.POWER_DROPPING }
        assertTrue("the drop is named: ${out.map { it.second.action }}", drop != null && drop.first in 960..1100)
        assertTrue(drop!!.second.short.startsWith("Power dropping"))
        // no zone language anywhere
        assertTrue(out.none { it.second.headline.contains("ZONE", true) || it.second.detail.contains("zone 2", true) })
        // never an increase-effort instruction from an assumed FTP
        assertTrue(out.none { it.second.action == CoachAction.INCREASE_EFFORT || it.second.action == CoachAction.HARDER_GEAR })
    }

    @Test fun surges_are_named_relative_to_own_output() {
        val e = engine(); val out = ArrayList<Pair<Int, CoachCue>>()
        run(e, 0, 400, { 160 }, out = out); run(e, 400, 420, { if (it in 402..408) 300 else 160 }, out = out)
        assertTrue(out.any { it.second.type == CueType.SURGE })
    }

    @Test fun no_sensors_says_so_once_then_coaches_pace_and_time() {
        val e = engine(); val out = ArrayList<Pair<Int, CoachCue>>()
        run(e, 0, 1300, { null }, cad = 85, speed = 25.0, out = out)
        assertEquals(1, out.count { it.second.type == CueType.NO_HR })
        assertTrue(out.any { it.second.action == CoachAction.STEADY_MILESTONE })
        val e2 = engine(); val out2 = ArrayList<Pair<Int, CoachCue>>()
        for (t in 0 until 400) { val c = e2.update(CoachInput(t * 1000L, Phase.MAIN, Signal(85), Signal.NONE, Signal.NONE, main, if ((t / 20) % 2 == 0) 14.0 else 30.0)); if (c.type != CueType.NONE) out2 += t to c }
        assertTrue(out2.any { it.second.action == CoachAction.STEADY_PACE })
        assertTrue("no intensity claims", out2.none { it.second.detail.contains("zone", true) })
    }

    @Test fun cadence_still_coached_without_effort_sensors() {
        val e = engine(); val out = ArrayList<Pair<Int, CoachCue>>()
        run(e, 0, 120, { null }, cad = 62, speed = 24.0, out = out)
        assertTrue(out.any { it.second.action == CoachAction.PEDAL_FASTER })
    }
}
