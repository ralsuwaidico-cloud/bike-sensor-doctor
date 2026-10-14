package com.rashed.bikesensordoctor.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.assertFalse
import org.junit.Test

/** v0.10 pattern rules (spike, unsteady effort, recovery) and the short live-screen wording. */
class CoachPatternTest {
    private fun engine() = CoachEngine(CoachConfig(mode = CoachMode.ZONE2, maxHr = 186, ftpW = 245, cadenceEnabled = false, graceMs = 0, backoff = true, keepRepeatMs = 0))
    private val main = ActiveTargets(139, 151, 135, 184, 83, 93, "MAIN")
    private fun run(e: CoachEngine, from: Int, to: Int, hr: Int?, pw: (Int) -> Int?, cad: Int? = 88, out: MutableList<Pair<Int, CoachCue>>) {
        for (t in from until to) { val c = e.update(CoachInput(t * 1000L, Phase.MAIN, Signal(cad), Signal(hr), Signal(pw(t)), main, 25.0)); if (c.type != CueType.NONE) out += t to c }
    }

    @Test fun sudden_power_spike_is_named_once_and_not_while_hr_is_already_above() {
        val e = engine(); val out = ArrayList<Pair<Int, CoachCue>>()
        run(e, 0, 60, 145, { 160 }, out = out)                                   // settled on target
        run(e, 60, 70, 145, { if (it in 62..66) 420 else 160 }, out = out)        // 5-s spike to 420 W (> 1.5 × 184)
        val spike = out.firstOrNull { it.second.type == CueType.SURGE }
        assertTrue("spike must be reported: $out", spike != null)
        assertEquals(CoachAction.SMOOTH_SURGES, spike!!.second.action)
        assertEquals("Smooth out the surges", spike.second.short)
        // a 2-s blip is ignored
        val e2 = engine(); val out2 = ArrayList<Pair<Int, CoachCue>>()
        run(e2, 0, 60, 145, { 160 }, out = out2); run(e2, 60, 90, 145, { if (it in 62..63) 420 else 160 }, out = out2)
        assertTrue(out2.none { it.second.type == CueType.SURGE })
        // HR already above the band: the effort ladder speaks (ease off), never a second, contradicting message about surges
        val e3 = engine(); val out3 = ArrayList<Pair<Int, CoachCue>>()
        run(e3, 0, 90, 165, { if (it in 40..60) 420 else 200 }, out = out3)
        assertTrue(out3.none { it.second.type == CueType.SURGE }); assertTrue(out3.any { it.second.type == CueType.EASE_OFF })
    }

    @Test fun unsteady_effort_with_a_correct_average_is_named() {
        val e = engine(); val out = ArrayList<Pair<Int, CoachCue>>()
        // mean 160 W (on target) but swinging 90 ↔ 230 every 5 s; HR steady in band
        run(e, 0, 150, 145, { if ((it / 8) % 2 == 0) 90 else 230 }, out = out)
        assertTrue("unsteady must be reported: ${out.map { it.second.type }}", out.any { it.second.type == CueType.STEADY })
        val steady = out.first { it.second.type == CueType.STEADY }.second
        assertEquals(CoachAction.STEADY_EFFORT, steady.action); assertEquals("Hold a steadier effort", steady.short)
        // a genuinely steady effort never triggers it
        val e2 = engine(); val out2 = ArrayList<Pair<Int, CoachCue>>()
        run(e2, 0, 150, 145, { 160 + (it % 3) * 4 }, out = out2)
        assertTrue(out2.none { it.second.type == CueType.STEADY })
    }

    @Test fun first_all_good_after_an_ease_off_is_worded_as_recovery() {
        val e = engine(); val out = ArrayList<Pair<Int, CoachCue>>()
        run(e, 0, 40, 165, { 200 }, out = out)                 // above → EASE OFF
        run(e, 40, 120, 145, { 160 }, out = out)               // back in band
        val ease = out.first { it.second.type == CueType.EASE_OFF }
        val good = out.first { it.first > ease.first && it.second.type == CueType.KEEP_IT_UP }.second
        assertEquals(CoachAction.RECOVERED, good.action)
        assertEquals("Good — back on target", good.short)
        assertEquals("HR settled after easing off", good.why)
        // a later good spell without an ease-off in between is an ordinary HOLD / MAINTAIN
        val e2 = engine(); val out2 = ArrayList<Pair<Int, CoachCue>>()
        run(e2, 0, 120, 145, { 160 }, out = out2)
        val g2 = out2.first { it.second.type == CueType.KEEP_IT_UP }.second
        assertTrue(g2.action == CoachAction.HOLD_PACE || g2.action == CoachAction.STABLE_MAINTAIN)
    }

    @Test fun short_wording_is_short_and_carries_the_numbers() {
        val e = engine(); val out = ArrayList<Pair<Int, CoachCue>>()
        run(e, 0, 40, 165, { 200 }, out = out)
        val ease = out.first { it.second.type == CueType.EASE_OFF }.second
        assertEquals("Ease off — HR above target", ease.short)
        assertTrue(ease.why, ease.why.startsWith("HR 165 vs 139–151 bpm"))
        assertTrue(ease.short.length <= 34)
        // gear wording keeps its own short form
        val e2 = engine(); val out2 = ArrayList<Pair<Int, CoachCue>>()
        run(e2, 0, 40, 165, { 230 }, cad = 60, out = out2)
        val gear = out2.first { it.second.type == CueType.EASE_OFF }.second
        assertEquals(CoachAction.EASIER_GEAR, gear.action); assertEquals("Shift to an easier gear", gear.short); assertTrue(gear.why.contains("60 rpm"))
        assertFalse(gear.short.isEmpty())
    }
}
