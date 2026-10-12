package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — no Android imports. Everything the Design-7 "AI Scientific Coach" screen needs to decide
 * WHAT to indicate (the UI only decides how to draw it). Reusable verbatim on the ESP32-S3.
 *
 *  - [TargetStatus]: is a live value below / on / above its target? Drives the pill under each gauge.
 *  - [Targets.gaugeFraction] / [Targets.targetFraction]: where the needle and the white target line sit on a 0..1 gauge.
 *  - [Targets.zoneFraction]: how far through the current zone we are ("Z2 · 82%").
 *  - [Targets.coachDirection] / [Targets.coachShape]: the shape and the lit step of the coaching scale, from the cue type.
 *
 * Rules: nothing is invented — a missing value is UNKNOWN, never guessed. Zone maths comes from [PowerZones]/[HrZones].
 */
enum class TargetStatus { BELOW, ON, ABOVE, UNKNOWN }

/** The three coaching shapes: ▲ go faster / push, ✓ on target, ▼ ease off, ○ nothing to say. */
enum class CoachShape { UP, CHECK, DOWN, NONE }

object Targets {
    /** Power gauge full-scale: the start of Z7 (1.5 × FTP), never less than 300 W so a low FTP still gives a readable dial. */
    fun powerGaugeMaxW(ftpW: Int): Int = maxOf(300, (ftpW * 1.5 + 0.5).toInt())

    const val CADENCE_GAUGE_MAX = 130

    /** 0..1 position of a value on a gauge of [max]; null value → 0. */
    fun gaugeFraction(value: Int?, max: Int): Float {
        if (value == null || max <= 0) return 0f
        return (value.toFloat() / max).coerceIn(0f, 1f)
    }

    /** Power vs a target zone. Coasting (0 W) is UNKNOWN: a power meter reads 0 unloaded and that is not "below target". */
    fun power(powerW: Int?, ftpW: Int, targetZone: Int): TargetStatus {
        val z = PowerZones.zone(powerW, ftpW)
        if (z == 0) return TargetStatus.UNKNOWN
        return compare(z, targetZone)
    }

    fun hr(bpm: Int?, maxHr: Int, targetZone: Int): TargetStatus {
        val z = HrZones.zone(bpm, maxHr)
        if (z == 0) return TargetStatus.UNKNOWN
        return compare(z, targetZone)
    }

    /** Cadence vs a range; not rotating (0 rpm) is UNKNOWN. */
    fun cadence(rpm: Int?, low: Int, high: Int): TargetStatus {
        if (rpm == null || rpm <= 0) return TargetStatus.UNKNOWN
        return when { rpm < low -> TargetStatus.BELOW; rpm > high -> TargetStatus.ABOVE; else -> TargetStatus.ON }
    }

    private fun compare(zone: Int, target: Int) = when { zone < target -> TargetStatus.BELOW; zone > target -> TargetStatus.ABOVE; else -> TargetStatus.ON }

    /** Where the white target line sits on the power gauge: the middle of the target zone, as 0..1 of the gauge. */
    fun powerTargetFraction(targetZone: Int, ftpW: Int): Float {
        val (lo, hi) = PowerZones.range(targetZone, ftpW)
        val mid = if (hi == null) lo.toFloat() else (lo + hi) / 2f
        return (mid / powerGaugeMaxW(ftpW)).coerceIn(0f, 1f)
    }

    /** Middle of the target HR zone as 0..1 of max HR (Z5 is open-ended → its lower edge). */
    fun hrTargetFraction(targetZone: Int): Float {
        val bounds = floatArrayOf(0f, 0.60f, 0.70f, 0.80f, 0.90f, 1.0f)
        if (targetZone !in 1..5) return 0f
        return if (targetZone == 5) 0.90f else (bounds[targetZone - 1] + bounds[targetZone]) / 2f
    }

    /** Zone boundaries as 0..1 of the power gauge, for the tick marks on the ring. */
    fun powerZoneTicks(ftpW: Int): FloatArray {
        val max = powerGaugeMaxW(ftpW).toFloat()
        return floatArrayOf(0.55f, 0.75f, 0.90f, 1.05f, 1.20f, 1.50f).map { (it * ftpW / max).coerceIn(0f, 1f) }.toFloatArray()
    }

    /** HR zone boundaries as 0..1 of max HR. */
    val hrZoneTicks = floatArrayOf(0.60f, 0.70f, 0.80f, 0.90f)

    /** Percent of the way through the current power zone (0..100), or null when not in a zone. */
    fun powerZonePercent(powerW: Int?, ftpW: Int): Int? {
        val z = PowerZones.zone(powerW, ftpW); if (z == 0 || powerW == null) return null
        val (lo, hi) = PowerZones.range(z, ftpW)
        val top = hi ?: (lo + ftpW * 0.5).toInt()   // Z7: treat the next 50 % of FTP as its span
        return pct(powerW.toDouble(), lo.toDouble(), top.toDouble())
    }

    fun hrZonePercent(bpm: Int?, maxHr: Int): Int? {
        val z = HrZones.zone(bpm, maxHr); if (z == 0 || bpm == null) return null
        val b = doubleArrayOf(0.0, 0.60, 0.70, 0.80, 0.90, 1.0)
        return pct(bpm.toDouble(), b[z - 1] * maxHr, b[z] * maxHr)
    }

    private fun pct(v: Double, lo: Double, hi: Double): Int {
        if (hi <= lo) return 0
        return ((v - lo) / (hi - lo) * 100).coerceIn(0.0, 100.0).let { it + 0.5 }.toInt()
    }

    /** -1 ease / 0 on target / +1 faster-push, from the coaching cue. Informational cues have no direction. */
    fun coachDirection(type: CueType): Int = when (type) {
        CueType.PEDAL_FASTER, CueType.PUSH_HARDER, CueType.WORK -> +1
        CueType.PEDAL_SLOWER, CueType.EASE_OFF, CueType.RECOVER -> -1
        else -> 0
    }

    fun coachShape(type: CueType): CoachShape = when (type) {
        CueType.PEDAL_FASTER, CueType.PUSH_HARDER, CueType.WORK -> CoachShape.UP
        CueType.PEDAL_SLOWER, CueType.EASE_OFF, CueType.RECOVER -> CoachShape.DOWN
        CueType.KEEP_IT_UP -> CoachShape.CHECK
        else -> CoachShape.NONE
    }

    /** The target effort zone a coaching mode aims for (Endurance = tempo Z3, everything else Z2). */
    fun targetZone(mode: CoachMode): Int = if (mode == CoachMode.ENDURANCE) 3 else 2
}
