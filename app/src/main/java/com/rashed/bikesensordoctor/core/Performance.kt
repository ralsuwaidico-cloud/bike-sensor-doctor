package com.rashed.bikesensordoctor.core

import kotlin.math.abs
import kotlin.math.sqrt

/*
 * PORTABLE CORE — performance-core (threshold-engine 2.1).
 *
 * Every physiological metric is an ESTIMATE with a value, a METHOD, the EVIDENCE behind it, a CONFIDENCE (0..1) that can
 * never exceed its method's ceiling, a STATUS band, and a version. FTP, critical power and threshold heart rate are
 * separate metrics: CP is never relabelled FTP, a threshold HR never comes from an ordinary ride, and nothing simulated,
 * unverified or of poor quality is ever admitted as evidence. Estimates change only between rides.
 *
 * The weights and ceilings below are product policy (versioned here), not physiology.
 */
enum class MetricKind(val unit: String) { FTP("W"), CRITICAL_POWER("W"), THRESHOLD_HR("bpm"), PREFERRED_CADENCE("rpm") }

enum class Method(val metric: MetricKind, val ceiling: Double, val label: String, val needsVerifiedPower: Boolean = false) {
    LAB_THRESHOLD_POWER(MetricKind.FTP, 0.95, "laboratory threshold"),
    STRUCTURED_FTP_TEST(MetricKind.FTP, 0.85, "structured FTP field test", true),
    FTP20_95_PERCENT(MetricKind.FTP, 0.80, "95% of a maximal 20-minute effort", true),
    PASSIVE_MMP(MetricKind.FTP, 0.65, "best 20-minute power from ordinary rides", true),
    ENDURANCE_AVERAGE(MetricKind.FTP, 0.25, "average power of an endurance ride", true),
    SYNTHETIC_WATTS(MetricKind.FTP, 0.0, "speed-derived or simulated watts"),
    USER_TESTED_FTP(MetricKind.FTP, 0.85, "entered by the rider as a tested value"),
    USER_ESTIMATED_FTP(MetricKind.FTP, 0.40, "entered by the rider as an estimate"),
    CP_MULTI_EFFORT(MetricKind.CRITICAL_POWER, 0.90, "critical-power model from ≥ 3 maximal efforts", true),
    CP_3MIN_ALL_OUT(MetricKind.CRITICAL_POWER, 0.70, "3-minute all-out test", true),
    LAB_HR_THRESHOLD(MetricKind.THRESHOLD_HR, 0.95, "laboratory lactate threshold HR"),
    FIELD_30MIN_HR(MetricKind.THRESHOLD_HR, 0.70, "guided 30-minute field assessment"),
    FIELD_20MIN_HR(MetricKind.THRESHOLD_HR, 0.65, "guided 20-minute test (HR of the block)"),
    REPEATED_HARD_SEGMENTS(MetricKind.THRESHOLD_HR, 0.50, "repeated hard steady segments"),
    HR_DEFLECTION(MetricKind.THRESHOLD_HR, 0.40, "heart-rate deflection point"),
    AGE_PERCENT(MetricKind.THRESHOLD_HR, 0.20, "percentage of an age-estimated max HR"),
    USER_TESTED_HR(MetricKind.THRESHOLD_HR, 0.85, "entered by the rider as a tested value"),
    USER_ESTIMATED_HR(MetricKind.THRESHOLD_HR, 0.40, "entered by the rider as an estimate"),
    LEARNED_CADENCE(MetricKind.PREFERRED_CADENCE, 0.80, "median cadence of steady on-target riding"),
    ;
    /** Only a laboratory source may ever be called VERIFIED. */
    val allowsVerified: Boolean get() = this == LAB_THRESHOLD_POWER || this == LAB_HR_THRESHOLD
}

enum class EstimateStatus { UNKNOWN, GENERIC, PROVISIONAL, HIGH, VERIFIED }

/** One piece of evidence: where a candidate value came from and how good the data was. */
data class Evidence(
    val id: String, val metric: MetricKind, val value: Int, val method: Method, val atMs: Long,
    val dataQuality: Double = 1.0,       // 0..1 completeness/freshness/plausibility of the samples
    val effortValidity: Double = 1.0,    // 0..1 how maximal/steady the effort was for the method
    val simulated: Boolean = false, val verifiedDevice: Boolean = true, val sourceRideId: Long? = null,
)

data class Components(val dataQuality: Double, val repeatability: Double, val effortValidity: Double, val recency: Double, val contextCoverage: Double)

data class Estimate(
    val metric: MetricKind, val value: Int, val method: Method, val confidence: Double, val status: EstimateStatus,
    val components: Components, val evidenceIds: List<String>, val algorithmVersion: String = Performance.VERSION,
) {
    val unit: String get() = metric.unit
    /** A short, honest label for the rider: "high-confidence field estimate", never "measured" unless it was. */
    val label: String get() = when (status) {
        EstimateStatus.VERIFIED -> "laboratory-verified"
        EstimateStatus.HIGH -> "high-confidence field estimate"
        EstimateStatus.PROVISIONAL -> "provisional estimate"
        EstimateStatus.GENERIC -> "generic starting point"
        EstimateStatus.UNKNOWN -> "unknown"
    }
}

object Performance {
    const val VERSION = "threshold-engine-2.1"
    const val MIN_DATA_QUALITY = 0.80
    private const val NINETY_DAYS_MS = 90L * 24 * 3600 * 1000

    /** Evidence that may enter an estimator: never simulated, never unverified power for power-based methods, never poor data. */
    fun admissible(e: Evidence): Boolean =
        !e.simulated && e.method.ceiling > 0.0 && (!e.method.needsVerifiedPower || e.verifiedDevice) && e.dataQuality >= MIN_DATA_QUALITY && e.method.metric == e.metric

    /**
     * The current estimate for a metric from its admissible evidence: the strongest method present wins; its most recent
     * values (last 3) give the value (median) and the repeatability; confidence is weighted and capped by the method ceiling.
     */
    fun estimate(metric: MetricKind, evidence: List<Evidence>, nowMs: Long): Estimate? {
        val ok = evidence.filter { it.metric == metric && admissible(it) }
        if (ok.isEmpty()) return null
        val best = ok.maxByOrNull { it.method.ceiling }!!.method
        val recent = ok.filter { it.method == best }.sortedBy { it.atMs }.takeLast(3)
        val values = recent.map { it.value }.sorted()
        val value = if (values.size == 2) recent.last().value else values[values.size / 2]   // median; with two, the newer
        val tol = if (metric == MetricKind.THRESHOLD_HR) 3.0 else value * 0.05
        val spread = if (values.size < 2) null else (values.last() - values.first()).toDouble()
        val repeatability = when { spread == null -> 0.0; spread <= tol -> 1.0; spread <= 2 * tol -> 0.6; else -> 0.2 }   // one result has no repeatability yet
        val recency = recent.maxOf { 1.0 - ((nowMs - it.atMs).coerceAtLeast(0).toDouble() / NINETY_DAYS_MS).coerceIn(0.0, 1.0) }
        val coverage = (ok.map { it.sourceRideId ?: it.id.hashCode().toLong() }.distinct().size / 4.0).coerceAtMost(1.0)
        val c = Components(recent.map { it.dataQuality }.average(), repeatability, recent.map { it.effortValidity }.average(), recency, coverage)
        val raw = 0.30 * c.dataQuality + 0.25 * c.repeatability + 0.20 * c.effortValidity + 0.15 * c.recency + 0.10 * c.contextCoverage
        val conf = minOf(best.ceiling, raw)
        return Estimate(metric, value, best, conf, status(conf, best), c, recent.map { it.id })
    }

    fun status(confidence: Double, method: Method): EstimateStatus = when {
        confidence < 0.25 -> EstimateStatus.UNKNOWN
        confidence < 0.45 -> EstimateStatus.GENERIC
        confidence < 0.70 -> EstimateStatus.PROVISIONAL
        confidence < 0.90 || !method.allowsVerified -> EstimateStatus.HIGH
        else -> EstimateStatus.VERIFIED
    }

    /** A proposal for the rider: the candidate differs meaningfully from what the profile holds (≥ 3% / ≥ 3 bpm). */
    fun meaningfullyDiffers(metric: MetricKind, current: Int?, candidate: Int): Boolean =
        current == null || (if (metric == MetricKind.THRESHOLD_HR) abs(candidate - current) >= 3 else abs(candidate - current) >= maxOf(3, (current * 0.03).toInt()))

    // ------------------------------------------------------------------ estimators

    /** FTP20: 0.95 × mean power of a deliberately executed 20-minute block. @return null unless the protocol conditions hold. */
    fun ftp20(meanPower20W: Double, verifiedDevice: Boolean, simulated: Boolean, validFraction: Double, pausedSec: Int, atMs: Long, rideId: Long?, id: String = "ftp20-$rideId"): Evidence? {
        if (simulated || !verifiedDevice || validFraction < 0.9 || pausedSec > 0 || meanPower20W < 60) return null
        return Evidence(id, MetricKind.FTP, Math.round(meanPower20W * 0.95).toInt(), Method.FTP20_95_PERCENT, atMs, dataQuality = validFraction, effortValidity = 1.0, simulated = false, verifiedDevice = true, sourceRideId = rideId)
    }

    /** Passive: the best 20-minute power of an ordinary ride (a weak method — capped at 0.65, never 'verified'). */
    fun passiveBest20(best20W: Int, verifiedDevice: Boolean, simulated: Boolean, atMs: Long, rideId: Long?, maximality: Double = 0.6): Evidence? {
        if (simulated || !verifiedDevice || best20W < 60) return null
        return Evidence("mmp20-$rideId", MetricKind.FTP, Math.round(best20W * 0.95).toInt(), Method.PASSIVE_MMP, atMs, dataQuality = 1.0, effortValidity = maximality, verifiedDevice = true, sourceRideId = rideId)
    }

    data class CpFit(val cpW: Int, val wPrimeJ: Int, val efforts: Int, val rmsErrorW: Double)

    /**
     * Critical power from maximal efforts: P(t) = CP + W′/t fitted by least squares on 1/t. Needs ≥ 3 efforts whose
     * durations span at least 2 to 10 minutes (shortest ≤ 180 s, longest ≥ 600 s). Returns CP — never an FTP.
     */
    fun criticalPower(efforts: List<Pair<Int, Double>>): CpFit? {
        val e = efforts.filter { it.first >= 90 && it.second > 0 }
        if (e.size < 3 || e.minOf { it.first } > 180 || e.maxOf { it.first } < 600) return null
        val xs = e.map { 1.0 / it.first }; val ys = e.map { it.second }
        val mx = xs.average(); val my = ys.average()
        val sxx = xs.sumOf { (it - mx) * (it - mx) }; if (sxx <= 0) return null
        val slope = xs.indices.sumOf { (xs[it] - mx) * (ys[it] - my) } / sxx      // W′ (J)
        val cp = my - slope * mx
        if (cp <= 0 || slope < 0) return null
        val rms = sqrt(xs.indices.sumOf { val p = cp + slope * xs[it]; (p - ys[it]) * (p - ys[it]) } / e.size)
        return CpFit(Math.round(cp).toInt(), Math.round(slope).toInt(), e.size, rms)
    }

    fun cpEvidence(fit: CpFit, verifiedDevice: Boolean, simulated: Boolean, atMs: Long, rideId: Long?): Evidence? {
        if (simulated || !verifiedDevice) return null
        val quality = (1.0 - (fit.rmsErrorW / fit.cpW).coerceIn(0.0, 1.0))
        return Evidence("cp-$rideId", MetricKind.CRITICAL_POWER, fit.cpW, Method.CP_MULTI_EFFORT, atMs, dataQuality = quality, effortValidity = 1.0, verifiedDevice = true, sourceRideId = rideId)
    }

    /**
     * Threshold-HR field candidate from a guided steady test: the 5%-trimmed mean of the plateau (after the first
     * [skipSec] seconds), accepted only when the effort was steady (power CV ≤ 10% when power is present, HR of the two
     * plateau halves within 5 bpm) and ≥ 90% of the plateau has heart rate. Labelled a FIELD candidate, never 'measured'.
     */
    fun thresholdHrCandidate(hr: List<Int?>, power: List<Int?>?, skipSec: Int, method: Method, atMs: Long, rideId: Long?): Evidence? {
        if (hr.size <= skipSec + 300) return null
        val plateau = hr.subList(skipSec, hr.size)
        val valid = plateau.filterNotNull().filter { it > 0 }
        if (valid.size < plateau.size * 0.9) return null
        val half = valid.size / 2
        if (abs(valid.subList(0, half).average() - valid.subList(half, valid.size).average()) > 5.0) return null
        power?.let { p -> val pv = p.subList(skipSec, minOf(p.size, hr.size)).filterNotNull().filter { it > 0 }; if (pv.size >= 60) { val m = pv.average(); val cv = sqrt(pv.sumOf { (it - m) * (it - m) } / pv.size) / m; if (cv > 0.10) return null } }
        val sorted = valid.sorted(); val trim = (sorted.size * 0.05).toInt()
        val trimmed = sorted.subList(trim, sorted.size - trim)
        return Evidence("thr-$rideId", MetricKind.THRESHOLD_HR, Math.round(trimmed.average()).toInt(), method, atMs, dataQuality = valid.size.toDouble() / plateau.size, effortValidity = 1.0, sourceRideId = rideId)
    }

    /** Preferred cadence: weighted median of segment means from steady, on-target, non-coasting riding. */
    fun preferredCadence(segmentMeans: List<Int>, atMs: Long): Evidence? {
        if (segmentMeans.size < 3) return null
        val s = segmentMeans.sorted()
        return Evidence("cad-${atMs}", MetricKind.PREFERRED_CADENCE, s[s.size / 2], Method.LEARNED_CADENCE, atMs, dataQuality = 1.0, effortValidity = (segmentMeans.size / 10.0).coerceAtMost(1.0))
    }
}
