package com.rashed.bikesensordoctor.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

/**
 * Property tests: invariants that must hold for thousands of randomly generated rider states, whatever the wording.
 *  - HR above the ceiling never produces an increase-effort / harder-gear instruction
 *  - power above the upper target never produces a harder gear for more power
 *  - stopped or coasting → no pedalling or gear instruction
 *  - a missing or stale power signal is never cited as the authority ("power" alone) for an instruction
 *  - one tick → at most one primary action (by construction: a single cue), and the same state replays identically
 */
class CoachInvariantTest {
    private val main = ActiveTargets(139, 151, 135, 184, 83, 93, "MAIN")
    private fun engine(seed: Int) = CoachEngine(CoachConfig(mode = CoachMode.ZONE2, maxHr = 186, ftpW = 245, cadenceEnabled = true, cadenceLow = 83, cadenceHigh = 93, graceMs = 0, backoff = seed % 2 == 0, keepRepeatMs = if (seed % 3 == 0) 0 else 90_000))

    private val increase = setOf(CoachAction.INCREASE_EFFORT, CoachAction.HARDER_GEAR)
    private val pedalling = setOf(CoachAction.PEDAL_FASTER, CoachAction.PEDAL_SLOWER, CoachAction.EASIER_GEAR, CoachAction.HARDER_GEAR, CoachAction.KEEP_CADENCE_STEADY)

    /** A random ride: piecewise-constant segments so holds can elapse, with drop-outs, coasting and stops mixed in. */
    private fun segments(rnd: Random, n: Int): List<CoachInput> {
        val out = ArrayList<CoachInput>(); var t = 0L
        while (out.size < n) {
            val len = 5 + rnd.nextInt(60)
            val hr: Int? = if (rnd.nextInt(10) == 0) null else 100 + rnd.nextInt(90)
            val pw: Int? = when (rnd.nextInt(12)) { 0 -> null; 1 -> 0; else -> 40 + rnd.nextInt(360) }
            val cad: Int? = when (rnd.nextInt(12)) { 0 -> null; 1 -> 0; else -> 50 + rnd.nextInt(70) }
            val speed = if (rnd.nextInt(15) == 0) 0.5 else 18.0 + rnd.nextInt(15)
            val phase = if (rnd.nextInt(20) == 0) Phase.WARMUP else Phase.MAIN
            repeat(len) { out += CoachInput(t, phase, Signal(cad), Signal(hr), Signal(pw), main, speed); t += 1000 }
        }
        return out
    }

    @Test fun invariants_hold_over_random_rides() {
        var cues = 0; var ticks = 0
        for (seed in 0 until 60) {
            val rnd = Random(seed); val e = engine(seed)
            val inputs = segments(rnd, 1500)
            for ((i, inp) in inputs.withIndex()) {
                val c = e.update(inp); ticks++
                if (c.type == CueType.NONE) continue
                cues++
                val hr = inp.hr.value; val pw = inp.power.value; val cad = inp.cadence.value
                // the engine judges 5-s means, so the invariants are stated on the last 5 s of input (a single new second may not have registered yet)
                val last5 = inputs.subList(maxOf(0, i - 4), i + 1)
                val stopped = inp.speedKmh!! < 2.0 || last5.all { it.cadence.value == 0 }
                val coasting = pw == 0
                if (last5.all { (it.hr.value ?: 0) > main.hrHi + 3 }) assertTrue("seed $seed t=${inp.nowMs}: HR $hr over the ceiling must never produce ${c.action} (${c.reason})", c.action !in increase)
                if (last5.all { (it.power.value ?: 0) > main.pwHi!! * 1.02 }) assertTrue("seed $seed: power $pw above target must never produce HARDER_GEAR", c.action != CoachAction.HARDER_GEAR)
                if (stopped || coasting) assertTrue("seed $seed t=${inp.nowMs}: stopped/coasting must not produce a pedalling or gear instruction (${c.action}, ${c.reason})", c.action !in pedalling)
                if (pw == null || pw == 0) assertTrue("seed $seed: without a loaded power reading, power alone cannot decide (${c.action} from '${c.sources}', ${c.reason})", c.sources != "power" || c.type == CueType.SENSOR_LOST)
                assertTrue("short wording always present", c.short.isNotEmpty())
            }
        }
        assertTrue("the random rides must actually produce cues ($cues of $ticks ticks)", cues > 200)
    }

    @Test fun replay_is_deterministic() {
        val rnd = Random(7); val inputs = segments(rnd, 3000)
        val a = CoachEngine(CoachConfig(mode = CoachMode.ZONE2, maxHr = 186, ftpW = 245, graceMs = 0)); val b = CoachEngine(CoachConfig(mode = CoachMode.ZONE2, maxHr = 186, ftpW = 245, graceMs = 0))
        val ra = inputs.map { a.update(it) }; val rb = inputs.map { b.update(it) }
        assertEquals(ra, rb)
    }

    @Test fun hr_ceiling_vetoes_increase_even_with_low_power_and_high_cadence() {
        val e = engine(1)
        var bad = 0
        for (t in 0 until 300) { val c = e.update(CoachInput(t * 1000L, Phase.MAIN, Signal(105), Signal(170), Signal(90), main, 25.0)); if (c.action in increase) bad++ }
        assertEquals(0, bad)
    }
}
