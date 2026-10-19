package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — no Android imports. Rider profile: the onboarding answers and the transparent rules that turn
 * them into a coaching set-up ([deriveSetup]) and a workout recommendation ([recommend]).
 *
 * This is a 1:1 port of design/demo_src/app_part.js (deriveConfig / recommend / followUp) so the Android app and
 * the interactive demo give the same answers for the same profile. Verified by RiderProfileTest.
 *
 * Answers are a flat string map so they serialise trivially (key=value lines) and new questions never break old
 * profiles. Keys mirror the demo: "age", "experience", "primary", "goals" (comma list), "maxHr.value", "maxHr.how" …
 */
class RiderAnswers(initial: Map<String, String> = emptyMap()) {
    private val m = LinkedHashMap<String, String>(initial)

    operator fun get(key: String): String? = m[key]
    operator fun set(key: String, value: String?) { if (value == null || value.isEmpty()) m.remove(key) else m[key] = value }
    fun int(key: String): Int? = m[key]?.toIntOrNull()
    fun list(key: String): List<String> = m[key]?.split(',')?.filter { it.isNotEmpty() } ?: emptyList()
    fun setList(key: String, v: List<String>) { set(key, v.joinToString(",")) }
    fun has(key: String) = m.containsKey(key)
    val isEmpty get() = m.isEmpty()
    fun toMap(): Map<String, String> = LinkedHashMap(m)
    fun copy() = RiderAnswers(m)

    /** A metric with how it was obtained: measured / estimated / app, or null when unknown. */
    fun metric(key: String): Metric? {
        val v = int("$key.value") ?: return null
        val how = m["$key.how"] ?: "estimated"
        if (how == "unknown") return null
        return Metric(v, how)
    }
    fun setMetric(key: String, value: Int?, how: String?) { set("$key.value", value?.toString()); set("$key.how", how) }

    fun snapshot(): String = m.entries.joinToString("\n") { "${it.key}=${it.value.replace("\n", " ")}" }

    companion object {
        fun restore(text: String): RiderAnswers {
            val out = RiderAnswers()
            text.lines().forEach { line -> val i = line.indexOf('='); if (i > 0) out[line.substring(0, i)] = line.substring(i + 1) }
            return out
        }
        val DAYS = listOf("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun")
        val GOALS = listOf(
            "endurance" to "Improve aerobic endurance and Zone 2 fitness", "fasterHr" to "Ride faster at the same heart rate",
            "ftp" to "Increase FTP and sustained power", "climb" to "Improve climbing", "longer" to "Ride longer without getting exhausted",
            "event" to "Prepare for a race or event", "fitness" to "Improve general fitness", "weight" to "Lose weight or improve body composition",
            "other" to "Another personal goal",
        )
        val GOAL_SHORT = mapOf(
            "endurance" to "Endurance (Zone 2)", "fasterHr" to "Faster at same HR", "ftp" to "Higher FTP", "climb" to "Climbing",
            "longer" to "Ride longer", "event" to "Race / event", "fitness" to "General fitness", "weight" to "Body composition", "other" to "Other",
        )
        fun goalName(k: String) = GOALS.firstOrNull { it.first == k }?.second ?: k
    }
}

data class Metric(val value: Int, val how: String) { val measured get() = how == "measured" }

enum class ZoneConfidence { CONFIRMED, PROVISIONAL, GENERIC }

/** One transparent rule the profile triggered: what the coach does and why. */
data class Rule(val what: String, val because: String)

/** Everything the coach needs, derived from the answers. Ranges are inclusive bpm / W. */
data class CoachSetup(
    val hrTargetLo: Int, val hrTargetHi: Int, val hrCap: Int,
    /** Z2 start, Z3 start, Z4 start, Z5 start (bpm). */
    val hrZoneEdges: IntArray,
    val zoneConfidence: ZoneConfidence, val zoneConfidenceText: String,
    val maxHrEstimate: Int,
    val ftp: Int, val ftpKnown: Boolean, val ftpMeasured: Boolean, val powerCoaching: Boolean,
    /** v0.11: the FTP is the onboarding STARTING ASSUMPTION (weight × experience) or an automatic estimate — a tentative reference, not a measurement */
    val ftpAssumed: Boolean = false, val ftpHow: String = "unknown",
    val cadLow: Int, val cadHigh: Int, val cadenceEnabled: Boolean,
    val warmupSec: Int, val cooldownSec: Int,
    val voice: Boolean, val tone: String, val detail: String,
    val sameRepeatMs: Long, val keepRepeatMs: Long,
    val rules: List<Rule>,
    val frequency: CoachFrequency = CoachFrequency.NORMAL,
) {
    val powerLo get() = (ftp * 0.55 + 0.5).toInt()
    val powerHi get() = (ftp * 0.75 + 0.5).toInt()
}

data class Workout(
    val name: String, val kind: String, val minutes: Int,
    val hrLo: Int, val hrHi: Int, val pwLo: Int?, val pwHi: Int?,
    val why: List<String>, val how: List<String>, val measure: List<String>,
    val alts: List<Pair<String, String>>,
)

/** What the rider reported after a ride (plus what the app measured). */
data class RideFeedback(
    val dateMs: Long, val inZonePct: Int, val driftPct: Int, val avgHr: Int, val durationSec: Int,
    val rpe: Int? = null, val limiter: String? = null, val recovered: String? = null,
) {
    fun snapshot() = "$dateMs,$inZonePct,$driftPct,$avgHr,$durationSec,${rpe ?: ""},${limiter ?: ""},${recovered ?: ""}"
    companion object {
        fun restore(line: String): RideFeedback? {
            val p = line.split(','); if (p.size < 5) return null
            return runCatching { RideFeedback(p[0].toLong(), p[1].toInt(), p[2].toInt(), p[3].toInt(), p[4].toInt(),
                p.getOrNull(5)?.toIntOrNull(), p.getOrNull(6)?.ifEmpty { null }, p.getOrNull(7)?.ifEmpty { null }) }.getOrNull()
        }
    }
}

/** A progressive follow-up question the coach asks after rides (one at a time, never repeated). */
data class FollowUp(val key: String, val question: String, val why: String?, val kind: String, val unit: String = "", val min: Int = 0, val max: Int = 0,
                    val options: List<Pair<String, String>> = emptyList())

object RiderProfile {
    private fun r(x: Double) = Math.round(x).toInt()

    fun primaryGoal(a: RiderAnswers): String = a["primary"] ?: a.list("goals").firstOrNull() ?: "endurance"

    fun successOptions(a: RiderAnswers): List<Pair<String, String>> {
        val longest = a.int("longestMin") ?: 90
        val m = mapOf(
            "endurance" to listOf("z2_75" to "Hold Zone 2 for 75 min", "z2_90pct" to "90% of a ride in Zone 2", "drift5" to "HR drift under 5%"),
            "fasterHr" to listOf("speed1" to "+1 km/h at the same HR", "eff5" to "5% better speed per heartbeat"),
            "ftp" to listOf("ftp5" to "+5% FTP", "ftp10" to "+10% FTP"),
            "climb" to listOf("climb" to "Same climb, lower HR", "climb_w" to "More W/kg on climbs"),
            "longer" to listOf("long20" to "${r(longest * 1.2)}-min ride, fresh at the end", "long_hr" to "No final HR surge on long rides"),
            "event" to listOf("event_done" to "Complete the event comfortably", "event_time" to "Beat a target time"),
            "fitness" to listOf("fit3" to "3 rides a week, every week", "fit_rest" to "Lower resting HR"),
            "weight" to listOf("w_consist" to "Consistent weekly riding", "w_long" to "Longer easy rides"),
            "other" to listOf("own" to "My own target"),
        )
        return (m[primaryGoal(a)] ?: m["other"]!!) + ("unsure" to "Coach proposes one")
    }

    fun successText(a: RiderAnswers): String? = a["success"]?.let { s -> successOptions(a).firstOrNull { it.first == s }?.second }

    /** Page validity for the six-page onboarding (page 5 is the summary). */
    fun pageValid(page: Int, a: RiderAnswers): Boolean = when (page) {
        0 -> a["experience"] != null
        1 -> a["primary"] != null
        2 -> a["ridesNow"] != null && a["daysAvail"] != null
        3 -> a["hrMode"] != null && a["pwMode"] != null
        4 -> a["voice"] != null && a["freq"] != null
        else -> true
    }

    /** SKIP on a page fills safe defaults so the coach can still be derived. */
    fun skipDefaults(page: Int, a: RiderAnswers) {
        when (page) {
            0 -> if (a["experience"] == null) a["experience"] = "recreational"
            1 -> if (a["primary"] == null) { a["primary"] = "fitness"; a.setList("goals", listOf("fitness")) }
            2 -> { if (a["ridesNow"] == null) a["ridesNow"] = "2"; if (a["daysAvail"] == null) a["daysAvail"] = "3" }
            3 -> { if (a["hrMode"] == null) a["hrMode"] = "later"; if (a["pwMode"] == null) a["pwMode"] = "unknown" }
            4 -> { if (a["voice"] == null) a["voice"] = "voice"; if (a["freq"] == null) a["freq"] = "important" }
        }
    }

    /** Fill every page with defaults ("set up later"). */
    fun skipAll(a: RiderAnswers) { for (p in 0..4) skipDefaults(p, a) }

    fun deriveSetup(a: RiderAnswers): CoachSetup {
        val rules = ArrayList<Rule>()
        fun rule(what: String, because: String) { rules += Rule(what, because) }

        // --- heart-rate zones ---
        val lthr = a.metric("lthr"); val maxHr = a.metric("maxHr"); val rest = a.metric("restHr")
        val z2: IntArray; val edges: IntArray; val conf: ZoneConfidence; val confText: String; val maxEst: Int
        when {
            lthr != null -> {
                val t = lthr.value
                z2 = intArrayOf(r(t * 0.83), r(t * 0.90)); edges = intArrayOf(z2[0], r(t * 0.90) + 1, r(t * 0.95) + 1, t + 1)
                maxEst = maxHr?.value ?: r(t / 0.9)
                if (lthr.measured) { conf = ZoneConfidence.CONFIRMED; confText = "CONFIRMED — threshold HR from a test" }
                else { conf = ZoneConfidence.PROVISIONAL; confText = "PROVISIONAL — threshold HR " + (if (lthr.how == "app") "calculated by another app" else "estimated from workouts") }
                rule("Zone 2 = ${z2[0]}–${z2[1]} bpm (83–90% of threshold $t)", "You gave a threshold heart rate; threshold-based zones fit individuals better than % of max.")
            }
            maxHr != null && rest != null -> {
                val hrr = maxHr.value - rest.value; val rs = rest.value
                z2 = intArrayOf(r(rs + 0.60 * hrr), r(rs + 0.70 * hrr)); edges = intArrayOf(z2[0], r(rs + 0.70 * hrr) + 1, r(rs + 0.80 * hrr) + 1, r(rs + 0.90 * hrr) + 1)
                maxEst = maxHr.value; conf = ZoneConfidence.PROVISIONAL
                confText = if (maxHr.measured) "PROVISIONAL — heart-rate reserve from a measured max" else "PROVISIONAL — heart-rate reserve from an estimated max"
                rule("Zone 2 = ${z2[0]}–${z2[1]} bpm (60–70% of heart-rate reserve, rest $rs, max ${maxHr.value})", "Max and resting HR known → Karvonen zones instead of plain % of max.")
            }
            maxHr != null -> {
                val mx = maxHr.value
                z2 = intArrayOf(r(mx * 0.60), r(mx * 0.70)); edges = intArrayOf(z2[0], r(mx * 0.70) + 1, r(mx * 0.80) + 1, r(mx * 0.90) + 1)
                maxEst = mx; conf = ZoneConfidence.PROVISIONAL
                confText = "PROVISIONAL — % of " + (if (maxHr.measured) "measured" else "estimated") + " max HR"
                rule("Zone 2 = ${z2[0]}–${z2[1]} bpm (60–70% of max $mx)", "Only max HR known.")
            }
            else -> {
                val age = a.int("age")
                val est = if (age != null) r(208 - 0.7 * age) else 185
                z2 = intArrayOf(r(est * 0.60), r(est * 0.70)); edges = intArrayOf(z2[0], r(est * 0.70) + 1, r(est * 0.80) + 1, r(est * 0.90) + 1)
                maxEst = est; conf = ZoneConfidence.GENERIC
                confText = if (age != null) "GENERIC — max HR $est from the Tanaka age formula; please calibrate" else "GENERIC — max HR 185 assumed; please calibrate"
                rule("Zone 2 = ${z2[0]}–${z2[1]} bpm from ${if (age != null) "an age formula" else "a default max HR"}", "No heart-rate values known. A calibration ride (20-min test) is recommended before trusting these.")
            }
        }
        var cap = z2[1]
        if (a["struggleZ2"] == "yes") { cap = z2[1] - 3; rule("Ceiling lowered to $cap bpm (3 below the top of Zone 2)", "You said you drift harder than Zone 2; the coach speaks before you leave it.") }
        if (a["limiter"] == "breathing") { cap = minOf(cap, z2[1] - 2); rule("Stricter heart-rate ceiling", "Breathing/heart rate limits you, so heart rate is the first thing the coach protects.") }
        if (a["limits"] == "moderate" || a["limits"] == "medical") { cap = minOf(cap, z2[1] - 5); rule("Intensity kept moderate: ceiling 5 bpm under Zone 2 top, no interval sessions", "You asked for moderate intensity.") }
        if (a["apple"] == "yes") rule("Apple zones kept as a labelled reference (Z2 151–160 bpm), not used for coaching", "App-calculated bands are not your physiology.")

        // --- power ---
        val ftp = a.metric("ftp")
        val ftpW: Int; val ftpKnown: Boolean; val powerCoaching: Boolean
        if (ftp != null) {
            ftpW = ftp.value; ftpKnown = true; powerCoaching = a["guidance"] != "hr"
            rule("Power Zone 2 = ${r(ftpW * 0.55)}–${r(ftpW * 0.75)} W (55–75% of FTP $ftpW, ${if (ftp.how == StartingFtp.HOW) "STARTING ASSUMPTION" else if (ftp.how == "auto") "learned from your efforts" else ftp.how})",
                when { ftp.measured -> "FTP from a test → power targets are confirmed."
                       ftp.how == StartingFtp.HOW -> "Starting assumption from your weight and experience — a reference only. Without a strap the coach judges effort against your own steady output; the number is replaced automatically once your sustained efforts give better evidence."
                       ftp.how == "auto" -> "Learned automatically from sustained efforts; it keeps adjusting as new qualifying rides arrive."
                       else -> "FTP not from a test → power targets are provisional until a 20-minute test." })
            if (!powerCoaching) rule("Power shown but not coached", "You prefer heart-rate guidance.")
        } else {
            ftpW = 200; ftpKnown = false; powerCoaching = false
            rule("Power targets OFF — heart-rate guidance only; FTP test offered after 3 rides", "FTP unknown. The coach never invents watts targets.")
        }

        // --- cadence ---
        val nat = a.metric("cadence") ?: a.int("learned.cadence")?.let { Metric(it, "learned") }
        val cadLo = if (nat != null) maxOf(70, nat.value - 5) else 80
        val cadHi = if (nat != null) minOf(105, nat.value + 5) else 95
        val cadOn = a["cadAdvice"] != "no"
        if (nat != null) rule("Cadence range $cadLo–$cadHi rpm around your natural ${nat.value}", if (nat.how == "learned") "Learned from your rides (median cadence) → targets built around you, not a generic 80–95." else "Known cadence → targets built around you, not a generic 80–95.")
        if (!cadOn) rule("Cadence hints off during endurance rides", "Your preference.")
        else if (a["limiter"] == "legs") rule("Cadence hints prioritised (legs limit you)", "Higher cadence shifts load from muscles to the aerobic system.")

        // --- warm-up / cool-down ---
        var wu = 5; var cd = 5
        if ((a.int("age") ?: 0) >= 50) { wu += 5; rule("Warm-up 10 min instead of 5", "Age 50+: a longer warm-up protects the heart-rate response.") }
        if (a["experience"] == "new" || a["experience"] == "returning") { wu += 3; rule("Warm-up +3 min", "New or returning rider.") }
        if (a["heat"] == "yes") { wu += 3; cd += 3; rule("Warm-up and cool-down +3 min, heart-rate drift tolerance +3%, earlier-start advice", "You ride in heat; heart rate runs higher for the same effort.") }

        // --- communication ---
        val voice = a["voice"] != "screen"
        val tone = a["tone"] ?: "neutral"; val detail = a["detail"] ?: "detailed"
        val sameRepeat: Long; val keepRepeat: Long; val freq: CoachFrequency
        when (a["freq"]) {
            "quiet" -> { sameRepeat = 120_000; keepRepeat = 0; freq = CoachFrequency.QUIET; rule("Quiet coaching: corrections only, the same one at most every 2 min, no encouragement", "You asked for quiet coaching.") }
            "frequent" -> { sameRepeat = 45_000; keepRepeat = 90_000; freq = CoachFrequency.FREQUENT; rule("Frequent guidance: cues up to every 45 s, 'hold this pace' every 90 s", "You asked for frequent guidance.") }
            else -> { sameRepeat = 90_000; keepRepeat = 0; freq = CoachFrequency.NORMAL; rule("Normal coaching: corrections only, the same one at most every 90 s; 'hold this pace' shown once per good spell", "You asked for corrections only.") }
        }
        rule("After 3 unheeded repeats the coach goes quiet until something changes (5 min max)", "Replay of a real ride showed ~60 repeats otherwise.")

        return CoachSetup(
            hrTargetLo = z2[0], hrTargetHi = z2[1], hrCap = cap, hrZoneEdges = edges, zoneConfidence = conf, zoneConfidenceText = confText, maxHrEstimate = maxEst,
            ftp = ftpW, ftpKnown = ftpKnown, ftpMeasured = ftp?.measured == true, powerCoaching = powerCoaching, ftpAssumed = ftp?.how == StartingFtp.HOW, ftpHow = ftp?.how ?: "unknown",
            cadLow = cadLo, cadHigh = cadHi, cadenceEnabled = cadOn, warmupSec = wu * 60, cooldownSec = cd * 60,
            voice = voice, tone = tone, detail = detail, sameRepeatMs = sameRepeat, keepRepeatMs = keepRepeat, rules = rules, frequency = freq,
        )
    }

    /**
     * Today's recommendation. [todayIdx] 0 = Monday … 6 = Sunday.
     */
    fun recommend(a: RiderAnswers, c: CoachSetup, log: List<RideFeedback>, todayIdx: Int): Workout {
        val g = primaryGoal(a)
        val typ = a.int("typicalMin") ?: 60; val long = a.int("longestMin") ?: 90
        val why = ArrayList<String>(); val how = ArrayList<String>(); val measure = ArrayList<String>()
        val last = log.lastOrNull()
        val today = RiderAnswers.DAYS[((todayIdx % 7) + 7) % 7]; val yesterday = RiderAnswers.DAYS[(((todayIdx - 1) % 7) + 7) % 7]
        var name = "Zone 2 endurance"; var minutes = minOf(maxOf(30, typ), long); var kind = "z2"
        val limits = a["limits"] ?: "none"
        when {
            g == "ftp" && c.ftpKnown && !c.ftpAssumed && limits != "moderate" && limits != "medical" -> { name = "Sweet-spot intervals (3 × 10 min at 88–93% FTP)"; kind = "ss"; minutes = maxOf(60, typ); why += "Main goal is FTP and your FTP is known, so the session targets sustained power." }
            g == "ftp" -> why += if (c.ftpAssumed) "Main goal is FTP, but your FTP is still a starting assumption: endurance base first while the coach learns your real sustained power — no hard intervals prescribed from an assumption." else "Main goal is FTP, but FTP is unknown: endurance base first, FTP test offered after three rides."
            g == "climb" && a["experience"] == "experienced" && limits == "none" -> { name = "Zone 2 with 4 × 5 min low-cadence (60–70 rpm) strength blocks"; kind = "strength"; why += "Climbing goal and experienced rider: low-cadence strength work inside an endurance ride." }
            g == "fasterHr" -> { name = "Zone 2 endurance with cadence focus"; why += "Riding faster at the same heart rate comes from aerobic base plus efficient cadence." }
            g == "event" && a["style"] != "steady" -> { name = "Zone 2 endurance (event build, week 1)"; why += "Event goal: base first, intensity added from week 3." }
            else -> why += "Main goal is ${RiderAnswers.goalName(g).lowercase()}: Zone 2 endurance is the session that builds it."
        }
        if (a.list("other").contains("weights") && a.list("otherDays").contains(yesterday)) {
            if (kind != "z2") { name = "Zone 2 endurance (easy day after weights)"; kind = "z2" }
            minutes = minOf(minutes, typ); why += "You lifted weights yesterday ($yesterday); the coach keeps today easy."
        }
        if (a.list("rest").contains(today)) why += "$today is one of your rest days — this is for your next riding day."
        if (last != null) {
            val rpe = last.rpe ?: 6
            when {
                rpe >= 8 || last.recovered == "no" -> { name = "Recovery spin (Zone 1)"; kind = "rec"; minutes = minOf(40, typ); why += "Your last ride felt $rpe/10${if (last.recovered == "no") " and you are not recovered" else ""}: an easy spin keeps the habit without adding load." }
                rpe <= 4 && last.inZonePct >= 80 -> { minutes = minOf(r(minutes * 1.1 / 5) * 5, long); why += "Last ride felt easy ($rpe/10) with ${last.inZonePct}% in zone → duration +10%." }
                last.inZonePct < 60 -> why += "Only ${last.inZonePct}% of your last ride was inside the zone → same duration again, stricter ceiling, until the zone is held."
            }
            if (last.limiter == "legs") why += "Legs limited you last time → cadence hints prioritised today."
        }
        val wu = c.warmupSec / 60; val cd = c.cooldownSec / 60
        val hrLo = if (kind == "rec") c.hrTargetLo - 15 else c.hrTargetLo
        val hrHi = if (kind == "rec") c.hrTargetLo - 1 else c.hrCap
        val pwLo = if (c.powerCoaching) (if (kind == "ss") r(c.ftp * 0.88) else c.powerLo) else null
        val pwHi = if (c.powerCoaching) (if (kind == "ss") r(c.ftp * 0.93) else c.powerHi) else null
        how += "$wu-min warm-up with a rising ceiling, then hold $hrLo–$hrHi bpm${if (pwLo != null) " ($pwLo–$pwHi W)" else ""}; $cd-min cool-down with a falling ceiling."
        how += if (c.voice) "Spoken cues, ${if (a["freq"] == "important") "corrections only" else "frequent"}, ${c.tone} tone." else "Screen cues only."
        if (c.cadenceEnabled) how += "Cadence hints when effort is in order: ${c.cadLow}–${c.cadHigh} rpm."
        measure += "Time inside the heart-rate band (target ≥ 80%)"; measure += "Heart-rate drift between halves at similar speed"; measure += "Longest continuous block in zone"
        if (c.powerCoaching) measure += "Watts at the same heart rate vs previous rides (REAL once the XDS is verified)"
        if (a["heat"] == "yes") how += "Advice: start before 8 am or after sunset to cut heat drift."
        val alts = ArrayList<Pair<String, String>>()
        alts += "shorter" to "Shorter: ${maxOf(30, minutes - 15)} min"
        alts += "longer" to "Longer: ${minOf(long, minutes + 15)} min"
        alts += "rec" to "Recovery spin 30 min"
        alts += "test" to "Guided 20-min threshold test"
        if (limits == "none" && a["style"] != "steady") alts += "int" to "Intervals: 4 × 4 min Zone 3"
        return Workout(name, kind, minutes, hrLo, hrHi, pwLo, pwHi, why, how, measure, alts)
    }

    /** Apply a "change workout" choice. */
    fun alternative(key: String, base: Workout, a: RiderAnswers, c: CoachSetup): Workout? = when (key) {
        "shorter" -> base.copy(minutes = maxOf(30, base.minutes - 15), name = base.name + " (shorter)")
        "longer" -> base.copy(minutes = minOf(a.int("longestMin") ?: 90, base.minutes + 15), name = base.name + " (longer)")
        "rec" -> base.copy(minutes = 30, name = "Recovery spin (Zone 1)", kind = "rec", hrLo = c.hrTargetLo - 15, hrHi = c.hrTargetLo - 1, pwLo = null, pwHi = null)
        "int" -> base.copy(minutes = maxOf(45, base.minutes), name = "Intervals: 4 × 4 min Zone 3", kind = "int", hrLo = c.hrZoneEdges[1], hrHi = c.hrZoneEdges[2] - 1)
        // guided assessment: 15 min easy, 20 min as hard as you can hold EVENLY, 10 min easy. The last 20 min of the main block give LTHR (and FTP with a verified meter).
        "test" -> base.copy(minutes = 45, name = "Guided 20-min threshold test", kind = "test", hrLo = c.hrZoneEdges[1], hrHi = c.hrZoneEdges[3] + 20, pwLo = null, pwHi = null,
            why = listOf("A steady 20-minute best effort is the standard way to find your threshold heart rate and FTP. Ride it evenly; a fast start spoils the result."),
            how = listOf("15-min warm-up, then 20 minutes at the hardest pace you can hold EVENLY (the coach only warns about fading or surging), then 10-min cool-down."),
            measure = listOf("Average heart rate of the 20 minutes → provisional threshold HR", "Average power of the 20 minutes × 0.95 → FTP (only with a verified power meter)"))
        else -> null
    }

    fun followUp(a: RiderAnswers, log: List<RideFeedback>, asked: Set<String>): FollowUp? {
        val n = log.size
        if (n >= 2 && a.metric("restHr") == null && "restHr" !in asked)
            return FollowUp("restHr", "Do you know your resting heart rate?", "It upgrades your zones from % of max to heart-rate reserve.", "metric", "bpm", 30, 100)
        if (n >= 3 && a.metric("ftp") == null && "ftpTest" !in asked)
            return FollowUp("ftpTest", "Calibrate your FTP with a 20-minute test on your next ride?", null, "choice", options = listOf("yes" to "Yes, schedule it", "later" to "Not yet"))
        if (n >= 2 && a["struggleZ2"] == null && "struggleZ2" !in asked) {
            val lastTwo = log.takeLast(2)
            if (lastTwo.all { it.inZonePct < 60 })
                return FollowUp("struggleZ2", "Your last two rides were mostly above Zone 2. Do you find it hard to stay easy?", null, "choice", options = listOf("yes" to "Yes, I drift harder", "no" to "No, it was deliberate"))
        }
        return null
    }

    /** What the coach still needs to learn (shown on the profile). */
    fun needs(a: RiderAnswers, c: CoachSetup): List<String> {
        val n = ArrayList<String>()
        if (c.zoneConfidence != ZoneConfidence.CONFIRMED) n += "Your real threshold heart rate — a 20-minute steady test, offered after 3 rides."
        if (!c.ftpKnown) n += "Your FTP — ride with the meter; sustained efforts teach the coach automatically (a guided 20-minute test is optional)."
        else if (c.ftpAssumed) n += "Your real FTP — the current ${c.ftp} W is a starting assumption; a steady hard effort of 20 minutes in any ride replaces it automatically."
        else if (!c.ftpMeasured) n += "Confirm FTP with a test (current value is ${a["ftp.how"]})."
        n += "Whether you can hold the Zone 2 band on your route (first ride answers this)."
        if (a["heat"] == "yes") n += "How much heat lifts your heart rate (drift between halves)."
        if (a.metric("cadence") == null) n += "Your natural cadence (XDS sensor, first ride)."
        return n
    }
}
