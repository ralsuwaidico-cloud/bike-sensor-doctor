package com.rashed.bikesensordoctor.core

/*
 * v0.10 live graph core — pure Kotlin (no Android), shared by the live screen, the Details view and the tests,
 * and portable to the ESP32 later.
 *
 *  LiveBuffer   fixed-size ring of 1 Hz samples: readings + the targets in force at that second + the phase.
 *               Missing reading = null (gap). A real 0 W while coasting is a value, never a gap.
 *  GraphScale   per-signal scaling: each signal is normalised against ITS OWN target band at the time of the sample
 *               (0 = lower edge, 1 = upper edge). The band is drawn once, in the middle of the plot, the same height
 *               for all three signals, so "inside the band" means "on target" for watts, bpm and rpm alike. Outside
 *               the band the scale stays linear for 1.5 band-heights from the centre, then compresses toward the edge.
 *  decimate     peak-preserving min/max downsampling for drawing only — the ride recording is a separate series.
 *  breaches     runs of ≥ N consecutive seconds outside the band (shaded on the graph).
 */

enum class GraphStatus { NONE, ZERO, BELOW, ON, ABOVE }

/** Target bands used for the graph and the metric cards. Power may have no band (meter unverified / FTP unknown). */
data class GraphBands(val pwLo: Int?, val pwHi: Int?, val hrLo: Int, val hrHi: Int, val cadLo: Int, val cadHi: Int) {
    companion object {
        /**
         * The bands in force now: the workout's active targets when a workout runs; otherwise the coaching zone edges.
         * @param ftpW FTP (0 = unknown); power gets a band only when the meter is trusted and FTP is known.
         */
        fun resolve(targets: ActiveTargets?, ftpW: Int, powerTrusted: Boolean, maxHr: Int, targetZone: Int, cadLo: Int, cadHi: Int): GraphBands {
            if (targets != null) return GraphBands(targets.pwLo, targets.pwHi, targets.hrLo, targets.hrHi, targets.cadLo, targets.cadHi)
            val z = targetZone.coerceIn(1, 5)
            val hrUpper = doubleArrayOf(0.60, 0.70, 0.80, 0.90, 1.0)
            val hrLo = if (z == 1) (maxHr * 0.50).toInt() else (maxHr * hrUpper[z - 2]).toInt() + 1
            val hrHi = (maxHr * hrUpper[z - 1]).toInt()
            val pwUpper = doubleArrayOf(0.55, 0.75, 0.90, 1.05, 1.20)
            val pwLo = if (powerTrusted && ftpW > 0) (if (z == 1) (ftpW * 0.30).toInt() else (ftpW * pwUpper[z - 2]).toInt() + 1) else null
            val pwHi = if (powerTrusted && ftpW > 0) (ftpW * pwUpper[z - 1]).toInt() else null
            return GraphBands(pwLo, pwHi, hrLo, hrHi, cadLo, cadHi)
        }
    }
}

object GraphScale {
    /** The target band occupies this fraction of the plot height, centred. */
    const val BAND_H = 0.28f
    /** Linear up to this many band-heights from the centre (= one band beyond either edge), then compressed. */
    const val LIN = 1.5f

    /** 0 at the lower edge of the band, 1 at the upper edge; null when the reading or the band is missing. */
    fun norm(v: Int?, lo: Int?, hi: Int?): Float? {
        if (v == null || lo == null || hi == null || hi <= lo) return null
        return (v - lo).toFloat() / (hi - lo)
    }

    /** Plot fraction from the top (0 = top, 1 = bottom) for a normalised value. */
    fun yFrac(n: Float): Float {
        val d = n - 0.5f
        val y = if (kotlin.math.abs(d) <= LIN) 0.5f - d * BAND_H else {
            val extra = kotlin.math.abs(d) - LIN
            val margin = 0.5f - LIN * BAND_H
            0.5f - kotlin.math.sign(d) * (LIN * BAND_H + margin * (extra / (extra + 1.5f)))
        }
        return y.coerceIn(0.01f, 0.99f)
    }
    val BAND_TOP: Float get() = yFrac(1f)
    val BAND_BOT: Float get() = yFrac(0f)

    fun status(v: Int?, lo: Int?, hi: Int?): GraphStatus {
        if (v == null) return GraphStatus.NONE
        if (v == 0) return GraphStatus.ZERO
        val n = norm(v, lo, hi) ?: return GraphStatus.NONE
        return when { n < 0f -> GraphStatus.BELOW; n > 1f -> GraphStatus.ABOVE; else -> GraphStatus.ON }
    }
}

/** One second of the live picture (allocated only for tests and the Details readout; drawing uses the arrays directly). */
data class LiveSample(val sec: Int, val powerW: Int?, val power3sW: Int?, val hr: Int?, val cadRpm: Int?, val bands: GraphBands, val phase: Phase)

class LiveBuffer(val capacity: Int = 600) {
    private val sec = IntArray(capacity)
    private val pw = IntArray(capacity); private val pw3 = IntArray(capacity); private val hr = IntArray(capacity); private val cad = IntArray(capacity)
    private val pwLo = IntArray(capacity); private val pwHi = IntArray(capacity); private val hrLo = IntArray(capacity); private val hrHi = IntArray(capacity)
    private val cadLo = IntArray(capacity); private val cadHi = IntArray(capacity); private val phase = ByteArray(capacity)
    var size = 0; private set
    private var head = 0           // index of the oldest sample
    private var generation = 0L
    /** Increments on every add — the UI redraws only when it changes. */
    val version: Long get() = generation

    fun clear() { size = 0; head = 0; generation++ }

    private fun slot(i: Int) = (head + i) % capacity

    /** Appends one second. Missing readings are null. The 3-s power average is computed here from the previous two seconds. */
    fun add(sec: Int, powerW: Int?, hr: Int?, cadRpm: Int?, bands: GraphBands, phase: Phase) {
        val idx: Int
        if (size < capacity) { idx = slot(size); size++ } else { idx = head; head = (head + 1) % capacity }
        this.sec[idx] = sec
        pw[idx] = powerW ?: MISSING; this.hr[idx] = hr ?: MISSING; cad[idx] = cadRpm ?: MISSING
        // 3-s power: mean of the available readings among this second and the two before it (a gap stays a gap)
        pw3[idx] = if (powerW == null) MISSING else {
            var sum = powerW; var n = 1
            for (back in 1..2) { val j = size - 1 - back; if (j >= 0) { val v = pw[slot(j)]; if (v != MISSING) { sum += v; n++ } } }
            Math.round(sum.toFloat() / n)
        }
        pwLo[idx] = bands.pwLo ?: MISSING; pwHi[idx] = bands.pwHi ?: MISSING
        hrLo[idx] = bands.hrLo; hrHi[idx] = bands.hrHi; cadLo[idx] = bands.cadLo; cadHi[idx] = bands.cadHi
        this.phase[idx] = phase.ordinal.toByte()
        generation++
    }

    operator fun get(i: Int): LiveSample {
        require(i in 0 until size)
        val s = slot(i)
        return LiveSample(sec[s], pw[s].orNull(), pw3[s].orNull(), hr[s].orNull(), cad[s].orNull(),
            GraphBands(pwLo[s].orNull(), pwHi[s].orNull(), hrLo[s], hrHi[s], cadLo[s], cadHi[s]), Phase.values()[phase[s].toInt()])
    }
    fun secAt(i: Int) = sec[slot(i)]
    fun phaseAt(i: Int): Phase = Phase.values()[phase[slot(i)].toInt()]
    fun powerAt(i: Int): Int? = pw[slot(i)].orNull()
    fun power3sAt(i: Int): Int? = pw3[slot(i)].orNull()
    fun hrAt(i: Int): Int? = hr[slot(i)].orNull()
    fun cadAt(i: Int): Int? = cad[slot(i)].orNull()
    fun bandsAt(i: Int): GraphBands { val s = slot(i); return GraphBands(pwLo[s].orNull(), pwHi[s].orNull(), hrLo[s], hrHi[s], cadLo[s], cadHi[s]) }

    /** Normalised value of a signal at index i against the band in force at that second; NaN when missing. */
    fun norm(signal: Signal, i: Int): Float {
        val s = slot(i)
        val (v, lo, hi) = when (signal) {
            Signal.POWER -> Triple(pw3[s], pwLo[s], pwHi[s])
            Signal.HR -> Triple(hr[s], hrLo[s], hrHi[s])
            Signal.CADENCE -> Triple(cad[s], cadLo[s], cadHi[s])
        }
        if (v == MISSING || lo == MISSING || hi == MISSING || hi <= lo) return Float.NaN
        return (v - lo).toFloat() / (hi - lo)
    }

    /** Index of the first sample inside the last [windowSec] seconds. */
    fun windowStart(windowSec: Int): Int = (size - windowSec).coerceAtLeast(0)

    enum class Signal { POWER, HR, CADENCE }

    companion object {
        const val MISSING = Int.MIN_VALUE
        private fun Int.orNull(): Int? = if (this == MISSING) null else this
    }
}

object GraphDecimate {
    /**
     * Peak-preserving downsampling for drawing: when there are more samples than [buckets] (≈ pixel columns), each bucket
     * keeps its minimum and maximum in time order, so a one-second spike survives. Output is a flat array of
     * (index, value) pairs; a NaN value marks a gap (nothing in that bucket). Display only — never applied to the stored ride.
     */
    fun minMax(from: Int, to: Int, buckets: Int, value: (Int) -> Float): FloatArray {
        val n = to - from
        if (n <= 0) return FloatArray(0)
        if (n <= buckets * 2) {
            val out = FloatArray(n * 2)
            for (k in 0 until n) { out[2 * k] = (from + k).toFloat(); out[2 * k + 1] = value(from + k) }
            return out
        }
        val out = ArrayList<Float>(buckets * 4)
        val per = n.toFloat() / buckets
        for (b in 0 until buckets) {
            val s = from + (b * per).toInt(); val e = minOf(to, from + ((b + 1) * per).toInt())
            var mi = -1; var ma = -1; var miV = 0f; var maV = 0f
            for (k in s until e) { val v = value(k); if (v.isNaN()) continue; if (mi < 0 || v < miV) { mi = k; miV = v }; if (ma < 0 || v > maV) { ma = k; maV = v } }
            if (mi < 0) { out += s.toFloat(); out += Float.NaN; continue }
            if (mi == ma) { out += mi.toFloat(); out += miV }
            else if (mi < ma) { out += mi.toFloat(); out += miV; out += ma.toFloat(); out += maV }
            else { out += ma.toFloat(); out += maV; out += mi.toFloat(); out += miV }
        }
        return out.toFloatArray()
    }
}

/** A sustained breach: [from, to) indices and the side (+1 above, −1 below). */
data class Breach(val from: Int, val to: Int, val side: Int)

object GraphBreaches {
    fun find(from: Int, to: Int, minSec: Int, norm: (Int) -> Float): List<Breach> {
        val out = ArrayList<Breach>()
        var start = -1; var side = 0
        fun close(end: Int) { if (start >= 0 && end - start >= minSec) out += Breach(start, end, side); start = -1; side = 0 }
        for (i in from until to) {
            val n = norm(i)
            val sd = if (n.isNaN()) 0 else if (n > 1f) 1 else if (n < 0f) -1 else 0
            if (sd != side || n.isNaN()) { close(i); if (sd != 0) { start = i; side = sd } }
        }
        close(to)
        return out
    }
}
