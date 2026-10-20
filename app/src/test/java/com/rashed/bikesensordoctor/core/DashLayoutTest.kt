package com.rashed.bikesensordoctor.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class DashLayoutTest {
    @Test fun layout_choice_defaults_and_keys() {
        assertEquals(DashLayout.CLASSIC, DashLayout.of(null))                                   // riders from before the setting keep what they had
        assertEquals(DashLayout.CLASSIC, DashLayout.of(RiderAnswers()))
        assertEquals(DashLayout.POWER_FOCUS, DashLayout.of(RiderAnswers(mapOf("dashLayout" to "power"))))
        assertEquals(DashLayout.COMPACT, DashLayout.of(RiderAnswers(mapOf("dashLayout" to "compact"))))
        assertEquals(DashLayout.CLASSIC, DashLayout.of(RiderAnswers(mapOf("dashLayout" to "garbage"))))
        assertEquals(DashLayout.POWER_FOCUS, DashLayout.DEFAULT_NEW)
    }

    private fun check(w: Float, maxH: Float, labelH: Float, chipH: Float, chipW: Float): PowerFocusGeometry {
        val g = PowerFocus.compute(w, maxH, labelH, chipH, chipW)
        assertTrue("rings clear: $g", PowerFocus.ringsClear(g))
        assertTrue("power dominant: $g", g.power >= g.small * 1.35)
        assertTrue("fits width: $g", g.xRight + g.colSmall <= w + 0.5f && g.xLeft >= 0 && g.xPower >= 0 && g.xPower + g.colPower <= w + 0.5f)
        assertTrue("fits height: $g (max $maxH)", g.blockHeight <= maxH + 1 || g.power <= w * 0.44f * 0.56f)
        assertTrue("power fully visible from the top: $g", g.powerCenter.second - g.power / 2f >= labelH - 0.5f)
        return g
    }

    @Test fun nokia_normal_font_gives_a_large_power_ring() {
        val g = check(340f, 240f, 13f, 20f, 96f)      // Nokia 5.3: 360 dp − 2 × 10 dp padding
        assertTrue("power ≥ 140 dp on the Nokia (got ${g.power})", g.power >= 140)
        assertTrue("small gauges still ≥ 96 dp (got ${g.small})", g.small >= 96)
        println("Nokia 1.0×: $g")
    }

    @Test fun nokia_large_font_shrinks_but_never_overlaps() {
        val g = check(340f, 190f, 17f, 25f, 110f)
        assertTrue("block fits the large-font budget (${g.blockHeight})", g.blockHeight <= 191)
        println("Nokia 1.3×: $g")
    }

    @Test fun narrow_and_wide_screens_never_overlap() {
        for (w in listOf(300f, 320f, 360f, 392f, 420f, 480f)) for (h in listOf(160f, 200f, 260f, 320f)) check(w, h, 13f, 20f, 96f)
    }
}
