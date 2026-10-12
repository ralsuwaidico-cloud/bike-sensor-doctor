package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — no Android imports. P0 sensor-quality and connection-gap recorder.
 *
 * Feed every accepted packet and every link event. It records:
 *  - packets received and the ride's expected 1 Hz rate → quality % (packets ÷ seconds observed)
 *  - every gap longer than [GAP_MS] between packets, with start/end, the reason (if the link reported a
 *    disconnect) and whether the cranks were turning / power > 0 in the [ACTIVITY_WINDOW_MS] before the gap
 *    — this is the evidence that decides WHY the XDS drops (sleep on pause vs. sleep under zero load).
 * Nothing here guesses: a gap that is still open at the end of the ride is closed at the end time.
 */
class LinkMonitor {
    companion object {
        const val GAP_MS = 3_000L            // a hole longer than this between packets is a gap
        const val ACTIVITY_WINDOW_MS = 15_000L
    }

    data class Gap(
        val startMs: Long, val endMs: Long, val reason: String,
        val rotatingBefore: Boolean, val poweredBefore: Boolean, val lastCadenceRpm: Int, val lastPowerW: Int,
    ) { val durationMs get() = endMs - startMs }

    private var firstMs: Long? = null
    private var lastPacketMs: Long? = null
    var packets = 0; private set
    private val recent = ArrayDeque<Triple<Long, Int, Int>>()   // (t, cadence, power) for the activity window
    private var pendingReason: String? = null
    private val _gaps = mutableListOf<Gap>()
    val gaps: List<Gap> get() = _gaps
    private var openGapStart: Long? = null
    private var openGapActivity: Triple<Boolean, Boolean, Pair<Int, Int>>? = null

    fun reset() { firstMs = null; lastPacketMs = null; packets = 0; recent.clear(); pendingReason = null; _gaps.clear(); openGapStart = null; openGapActivity = null }

    fun onPacket(nowMs: Long, cadenceRpm: Int, powerW: Int) {
        if (firstMs == null) firstMs = nowMs
        val last = lastPacketMs
        if (last != null && nowMs - last > GAP_MS) closeGap(last, nowMs)
        packets++
        lastPacketMs = nowMs
        recent.addLast(Triple(nowMs, cadenceRpm, powerW))
        while (recent.isNotEmpty() && nowMs - recent.first().first > ACTIVITY_WINDOW_MS) recent.removeFirst()
    }

    /** The link layer reports a disconnect (e.g. "GATT_SUCCESS", "133"). Tags the gap that follows. */
    fun onDisconnect(nowMs: Long, reason: String) { pendingReason = reason }

    private fun activityBefore(): Triple<Boolean, Boolean, Pair<Int, Int>> {
        val rot = recent.any { it.second > 0 }; val pw = recent.any { it.third > 0 }
        val lastC = recent.lastOrNull()?.second ?: 0; val lastP = recent.lastOrNull()?.third ?: 0
        return Triple(rot, pw, lastC to lastP)
    }

    private fun closeGap(startMs: Long, endMs: Long) {
        val (rot, pw, lastVals) = activityBefore()
        _gaps += Gap(startMs, endMs, pendingReason ?: "silence", rot, pw, lastVals.first, lastVals.second)
        pendingReason = null
    }

    /** Call at ride end so a gap still open is counted. */
    fun finish(nowMs: Long) {
        val last = lastPacketMs ?: return
        if (nowMs - last > GAP_MS) { closeGap(last, nowMs); lastPacketMs = nowMs }
    }

    fun observedMs(nowMs: Long): Long = firstMs?.let { (nowMs - it).coerceAtLeast(0) } ?: 0
    fun lostMs(): Long = _gaps.sumOf { it.durationMs }

    /** Packets ÷ expected packets at 1 Hz over the observed span, capped at 100. null before any packet. */
    fun qualityPct(nowMs: Long): Int? {
        val f = firstMs ?: return null
        val span = ((nowMs - f) / 1000.0).coerceAtLeast(1.0)
        return (packets / span * 100.0 + 0.5).toInt().coerceIn(0, 100)
    }

    fun report(nowMs: Long): LinkReport = LinkReport(packets, qualityPct(nowMs) ?: 0, _gaps.size, lostMs(), _gaps.toList())
}

data class LinkReport(val packets: Int, val qualityPct: Int, val gapCount: Int, val lostMs: Long, val gaps: List<LinkMonitor.Gap>) {
    /** One-line plain-English verdict for the ride report. */
    fun verdict(): String = when {
        packets == 0 -> "No sensor data received."
        gapCount == 0 && qualityPct >= 95 -> "Link solid: $qualityPct % of packets, no gaps."
        else -> "Link $qualityPct %: $gapCount gap(s), ${lostMs / 1000} s lost" +
            (gaps.firstOrNull()?.let { g -> " — first gap after ${if (g.rotatingBefore) "pedaling" else "a pause"}${if (g.poweredBefore) " under load" else " at 0 W"} (${g.reason})" } ?: "")
    }
}
