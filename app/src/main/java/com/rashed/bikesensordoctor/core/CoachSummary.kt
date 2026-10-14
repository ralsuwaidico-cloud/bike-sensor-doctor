package com.rashed.bikesensordoctor.core

/*
 * v0.10 coach communication — pure Kotlin.
 *
 * The rider sees ONE short message first: a headline (the achievement or the gap), a verdict in plain words, and one
 * next step. Everything behind it — the scientific reasoning, the detailed findings and how the numbers were computed —
 * sits behind "Why?", "Details" and "How was this calculated?" so nothing is lost, it is just not shown all at once.
 * One recommendation at a time: a priority ladder picks the most important thing to act on.
 */

/** How much the rider wants to see: plain words, or the technical detail as well. */
enum class DetailLevel { SIMPLE, TECHNICAL;
    companion object { fun from(answers: RiderAnswers?): DetailLevel = if (answers?.get("detail") == "technical" || answers?.get("experience") == "experienced") TECHNICAL else SIMPLE }
}

enum class Tone { GOOD, WATCH, FIX, INFO }

/** Where a number comes from — shown once as a tag, never as a repeated disclaimer. */
enum class Provenance(val label: String) { MEASURED("MEASURED"), ESTIMATE("ESTIMATE"), SIMULATED("SIMULATED"), UNVERIFIED("UNVERIFIED") }

data class CoachMessage(
    val title: String,            // "Zone 2 performance"
    val headline: String,         // "4% of your ride in target"
    val verdict: String,          // "You rode harder than planned."
    val next: String,             // "Next ride: reduce your effort to stay in Zone 2."
    val tone: Tone,
    val progress: Float?,         // 0..1 for the progress indicator (share of the main block in the band), null = none
    val why: String,              // the scientific explanation, one short paragraph
    val details: List<String>,    // the other findings (what went well, what could improve)
    val how: String,              // how it was calculated
)

object CoachSummary {
    private fun pct(x: Int) = "$x%"

    /**
     * The post-ride message. @param band the coached HR band (null = free ride); @param zoneName e.g. "Zone 2"
     * @param level SIMPLE hides the numbers that need explaining; TECHNICAL adds them to the details
     */
    fun forRide(a: AnalysisResult, band: IntRange?, zoneName: String, level: DetailLevel, simulated: Boolean, powerTrusted: Boolean, rpe: Int? = null): CoachMessage {
        val tech = level == DetailLevel.TECHNICAL
        val how = buildString {
            append("Time in target counts every second of the main block (after the warm-up, before the cool-down) whose heart rate was inside ${band?.let { "${it.first}–${it.last} bpm" } ?: "the band"}. ")
            append("Drift compares the average heart rate of the second half of the main block with the first half, only when the effort (power or speed) was within 10% — otherwise it is not computed. ")
            append("Consistency is the variation of heart rate (and power) around its average over the main block. ")
            if (simulated) append("Watts and cadence in this ride are SIMULATED and were not used for any estimate. ")
            else if (!powerTrusted) append("The power meter is not yet verified under load, so its watts are shown but not used for calories or FTP. ")
        }
        val details = ArrayList<String>()
        details += a.wentWell; details += a.improve
        if (tech) {
            a.hrConsistencyCv?.let { details += "HR variation ±${Math.round(it * 100)}%" + (a.powerConsistencyCv?.let { p -> " · power ±${Math.round(p * 100)}%" } ?: "") }
            a.driftPct?.let { details += "HR drift ${if (it >= 0) "+" else ""}$it% (${a.driftNote})" }
            a.normalizedPowerW?.let { details += "Normalized power $it W · average ${a.avgPowerW} W" }
            if (a.longestInBandSec > 0) details += "Longest continuous block in band ${a.longestInBandSec / 60} min"
        }

        // ---- the ladder: one message, the most important first ----
        if (a.hrSamples == 0) return CoachMessage("Heart rate", "No heart rate this ride", "Without a strap the coach cannot judge your effort.",
            "Next ride: wear the heart-rate strap so the coach can guide you.", Tone.INFO, null,
            "Heart rate is the coach's authority on effort; power only confirms it. With neither, the ride is recorded but not assessed.", details, how)
        if (band == null || a.inBandPct == null) {
            val z = a.personalZones
            val top = z?.let { zz -> (1..5).maxByOrNull { zz.sec[it - 1] } }
            return CoachMessage("Free ride", if (top != null) "Most of your ride was in Zone $top" else "Ride recorded",
                if (a.avgHr != null) "Average heart rate ${a.avgHr} bpm." else "No target was set for this ride.",
                "Next ride: start a workout from Home so the coach has a target to hold you to.", Tone.INFO, null,
                "A free ride has no band, so there is no 'on target' to measure. The zone split below still shows where the effort went.", details, how)
        }
        val inb = a.inBandPct
        val aboveMore = a.improve.any { it.contains("above") } || (a.avgHr != null && a.avgHr > band.last)
        if (inb < 80) {
            val harder = aboveMore
            return CoachMessage("$zoneName performance", "${pct(inb)} of your ride in target",
                if (harder) "You rode harder than planned." else "You rode easier than planned.",
                if (harder) "Next ride: reduce your effort to stay in $zoneName — ease off as soon as the coach says so." else "Next ride: add a little effort to reach $zoneName and hold it.",
                Tone.FIX, inb / 100f,
                if (harder) "Endurance adaptations (fat metabolism, capillaries, mitochondria) come from long time at a low, steady heart rate. Above the band the session turns into tempo work: more fatigue, less of the intended adaptation, and the next hard day suffers."
                else "Below the band the stimulus is too small to drive the endurance adaptations the workout is designed for. A little more pressure on the pedals — not a sprint — moves you into the zone.",
                details, how)
        }
        a.driftPct?.let { d -> if (d > 5) return CoachMessage("Heart-rate drift", "Heart rate drifted up $d%", "Same effort, higher heart rate in the second half.",
            "Next ride: drink earlier, start cooler, or shorten the ride by 10 minutes.", Tone.WATCH, inb / 100f,
            "Cardiac drift: as body temperature rises and plasma volume drops, the heart beats faster for the same work. Up to about 5% is normal; more points to heat, dehydration or a ride that is long for current fitness.", details, how) }
        a.hrConsistencyCv?.let { cv -> if (cv >= 0.10) return CoachMessage("Pacing", "Your pace was uneven", "Heart rate swung ±${Math.round(cv * 100)}% through the main block.",
            "Next ride: pick one gear on the flats and keep the pressure even.", Tone.WATCH, inb / 100f,
            "Surges cost more than steady watts: each one pushes heart rate up and it takes minutes to settle. Steadier pacing gives more time in the zone for the same average.", details, how) }
        a.avgCadRpm?.let { c -> if (c < 75 && a.cadSamples > 600) return CoachMessage("Cadence", "Average cadence $c rpm", "You pushed a heavy gear most of the ride.",
            "Next ride: one gear easier, a quicker spin — same effort, less load on the legs.", Tone.WATCH, inb / 100f,
            "A low cadence shifts the work to muscular force; a quicker spin shares it with the heart and lungs, which recover faster. The coach learns your natural cadence from steady, on-target riding.", details, how) }
        if (rpe != null && rpe >= 8) return CoachMessage("Recovery", "That felt hard ($rpe/10)", "You held the zone, but the effort cost you.",
            "Next ride: an easy day — shorter, same zone.", Tone.WATCH, inb / 100f,
            "A high perceived effort at endurance intensity usually means fatigue, heat or poor sleep. One easier session restores the balance; pushing on compounds it.", details, how)
        return CoachMessage("$zoneName performance", "${pct(inb)} of your ride in target", "Objective achieved — a well-executed endurance ride.",
            if (rpe != null && rpe <= 4) "Next ride: same again, 5 minutes longer." else "Next ride: repeat this — consistency is what builds endurance.",
            Tone.GOOD, inb / 100f,
            "Holding the band for most of the main block is exactly the stimulus an endurance ride is for. Repeating it, then slowly extending the duration, is how the aerobic engine grows.", details, how)
    }

    /** Provenance tags for a ride, shown once at the top of the results page. */
    fun provenance(simulated: Boolean, powerTrusted: Boolean, hasHr: Boolean, hasGps: Boolean, hasPower: Boolean): List<Pair<String, Provenance>> {
        val out = ArrayList<Pair<String, Provenance>>()
        if (hasHr) out += "heart rate" to (if (simulated) Provenance.SIMULATED else Provenance.MEASURED)
        if (hasPower) out += "power · cadence" to (if (simulated) Provenance.SIMULATED else if (powerTrusted) Provenance.MEASURED else Provenance.UNVERIFIED)
        if (hasGps) out += "route · speed" to (if (simulated) Provenance.SIMULATED else Provenance.MEASURED)
        out += "calories" to Provenance.ESTIMATE
        return out
    }
}
