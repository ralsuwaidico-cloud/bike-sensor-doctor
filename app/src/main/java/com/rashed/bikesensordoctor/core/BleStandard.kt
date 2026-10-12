package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — no Android imports. Decoders for the STANDARD Bluetooth SIG cycling/HR profiles, so the
 * app (and later the ESP32-S3) can also read any ordinary heart-rate strap, speed/cadence sensor or
 * standards-compliant power meter — not just the proprietary XDS format. All offsets per the SIG specs.
 */
object BleStandard {
    private fun u8(b: ByteArray, i: Int) = b[i].toInt() and 0xFF
    private fun u16(b: ByteArray, i: Int) = u8(b, i) or (u8(b, i + 1) shl 8)
    private fun u32(b: ByteArray, i: Int) = (u16(b, i).toLong()) or (u16(b, i + 2).toLong() shl 16)

    /** Heart Rate Measurement 0x2A37: flags bit0 = 16-bit value, else 8-bit. Returns bpm or null. */
    fun heartRate(b: ByteArray): Int? {
        if (b.isEmpty()) return null
        val flags = u8(b, 0)
        return if (flags and 0x01 != 0) { if (b.size >= 3) u16(b, 1) else null }
        else { if (b.size >= 2) u8(b, 1) else null }
    }

    /** Cycling Power Measurement 0x2A63 (standard): flags u16, then instantaneous power s16 (watts). */
    fun cyclingPowerWatts(b: ByteArray): Int? {
        if (b.size < 4) return null
        return u16(b, 2).toShort().toInt()
    }

    data class CrankSample(val cumulativeRevs: Int, val lastEventTime1024: Int)
    /** CSC Measurement 0x2A5B crank fields (flags bit1). For cadence = Δrevs / Δtime (1/1024 s). */
    fun cscCrank(b: ByteArray): CrankSample? {
        if (b.isEmpty()) return null
        val flags = u8(b, 0)
        var i = 1
        if (flags and 0x01 != 0) i += 6          // wheel data present → skip 4-byte revs + 2-byte time
        if (flags and 0x02 == 0) return null      // no crank data
        if (i + 4 > b.size) return null           // need 2-byte revs + 2-byte time
        return CrankSample(u16(b, i), u16(b, i + 2))
    }

    /** Cadence rpm from two crank samples, handling 16-bit wrap. */
    fun cadenceRpm(prev: CrankSample, cur: CrankSample): Double? {
        val dRevs = (cur.cumulativeRevs - prev.cumulativeRevs + 65536) % 65536
        val dT = (cur.lastEventTime1024 - prev.lastEventTime1024 + 65536) % 65536
        if (dRevs == 0 || dT == 0) return null
        return dRevs * 60.0 * 1024.0 / dT
    }

    /** Battery Level 0x2A19 → percent. */
    fun battery(b: ByteArray): Int? = if (b.isNotEmpty()) u8(b, 0) else null
}
