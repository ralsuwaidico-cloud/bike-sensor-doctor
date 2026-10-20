package com.rashed.bikesensordoctor.core

import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * PORTABLE CORE — dashboard layout choice and the Power-Focus gauge geometry (v0.12).
 *
 * The layout is presentation only: every layout reads the same live data, coach and recording. The choice is stored per
 * rider (profile key "dashLayout"); riders created before the choice existed keep CLASSIC, new riders start on POWER_FOCUS.
 * The geometry is pure arithmetic in dp so the same numbers can drive the Android screen and the ESP32 display.
 */
enum class DashLayout(val key: String, val title: String, val blurb: String) {
    POWER_FOCUS("power", "Power Focus", "Large power gauge on top, cadence and heart rate tucked below on either side."),
    CLASSIC("classic", "Classic Three Gauges", "Three equal gauges in one row."),
    COMPACT("compact", "Compact Metrics", "Numerical cards with a target bar; most room for the graph.");

    companion object {
        const val KEY = "dashLayout"
        val DEFAULT_NEW = POWER_FOCUS
        val DEFAULT_EXISTING = CLASSIC
        fun fromKey(k: String?): DashLayout? = values().firstOrNull { it.key == k }
        /** The layout for a profile: an explicit choice, else CLASSIC (what existing riders had). */
        fun of(a: RiderAnswers?): DashLayout = fromKey(a?.get(KEY)) ?: DEFAULT_EXISTING
    }
}

/**
 * Power-Focus geometry, all in dp. POWER is the large ring, top centre; CADENCE (left) and HEART RATE (right) are smaller,
 * their centres pushed down just far enough that no ring, label or status chip overlaps another — computed from the
 * circle/rectangle distances, never from guessed negative offsets. Each gauge is a column: label (labelH) above the ring,
 * status chip (chipH, chipW wide) below it.
 */
data class PowerFocusGeometry(
    val power: Int, val small: Int,          // ring diameters
    val colPower: Int, val colSmall: Int,    // column widths (≥ chip width)
    val xPower: Int, val xLeft: Int, val xRight: Int,   // column left edges inside the content width
    val yPower: Int, val yLower: Int,        // column top edges
    val blockHeight: Int,
    val powerCenter: Pair<Float, Float>, val leftCenter: Pair<Float, Float>, val rightCenter: Pair<Float, Float>,
)

object PowerFocus {
    const val GAP = 6f   // minimum clearance between any two shapes, dp

    private fun distRectCircle(cx: Float, cy: Float, l: Float, t: Float, r: Float, b: Float): Float {
        val nx = cx.coerceIn(l, r); val ny = cy.coerceIn(t, b)
        return sqrt((cx - nx) * (cx - nx) + (cy - ny) * (cy - ny))
    }

    /**
     * @param contentW usable width (dp) · @param maxBlockH the most height the gauge block may take (dp) · the font-scaled
     * label/chip sizes (labelW = the widest label text, "HEART RATE", which is narrower than the column). Shrinks both rings together (power 0.44 → small 0.30 of the width at scale 1) until the block fits.
     */
    fun compute(contentW: Float, maxBlockH: Float, labelH: Float, chipH: Float, chipW: Float, labelW: Float = 64f): PowerFocusGeometry {
        var best: PowerFocusGeometry? = null
        var scale = 1.10f   // a taller screen lets both rings grow a little beyond the nominal 0.44 / 0.30 of the width
        while (scale >= 0.55f) {
            val p = (contentW * 0.44f * scale).roundToInt().toFloat()
            val s = (contentW * 0.30f * scale).roundToInt().toFloat()
            val colS = max(s, chipW); val colP = max(p, chipW)
            val pcx = contentW / 2f; val pcy = labelH + p / 2f
            val lcx = colS / 2f; val rcx = contentW - colS / 2f
            val dx = pcx - lcx
            val need = (p + s) / 2f + GAP
            var dy = if (dx >= need) 0f else sqrt(need * need - dx * dx)
            // the lower label (a rectangle above the small ring) must clear the power ring; the power chip must clear the small rings
            var lcy: Float
            while (true) {
                lcy = max(pcy + dy, labelH + s / 2f)
                val labelTop = lcy - s / 2f - labelH; val labelBot = lcy - s / 2f
                val labelClear = distRectCircle(pcx, pcy, lcx - labelW / 2f, labelTop, lcx + labelW / 2f, labelBot) >= p / 2f + GAP / 2f
                val chipL = pcx - chipW / 2f; val chipR = pcx + chipW / 2f; val chipT = pcy + p / 2f; val chipB = chipT + chipH
                val chipClear = distRectCircle(lcx, lcy, chipL, chipT, chipR, chipB) >= s / 2f + GAP / 2f
                if (labelClear && chipClear) break
                dy += 1f
                if (dy > p) break
            }
            val blockH = max(pcy + p / 2f + chipH, lcy + s / 2f + chipH)
            val g = PowerFocusGeometry(p.toInt(), s.toInt(), colP.toInt(), colS.toInt(),
                (pcx - colP / 2f).roundToInt(), 0, (contentW - colS).roundToInt(),
                0, (lcy - s / 2f - labelH).roundToInt(), blockH.roundToInt() + 1,
                pcx to pcy, lcx to lcy, rcx to lcy)
            if (best == null) best = g
            if (blockH <= maxBlockH) return g
            scale -= 0.02f
        }
        return best!!
    }

    /** True when no two rings overlap (centre distance ≥ sum of radii + GAP) — the invariant the unit test checks. */
    fun ringsClear(g: PowerFocusGeometry): Boolean {
        fun d(a: Pair<Float, Float>, b: Pair<Float, Float>) = sqrt((a.first - b.first) * (a.first - b.first) + (a.second - b.second) * (a.second - b.second))
        val rp = g.power / 2f; val rs = g.small / 2f
        return d(g.powerCenter, g.leftCenter) >= rp + rs + GAP - 0.5f && d(g.powerCenter, g.rightCenter) >= rp + rs + GAP - 0.5f && d(g.leftCenter, g.rightCenter) >= 2 * rs + GAP
    }
}
