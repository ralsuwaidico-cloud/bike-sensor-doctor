package com.rashed.bikesensordoctor.ble

import java.util.UUID

/** Verified cycling metrics decoded from standard (SIG) characteristics. */
data class CyclingMetrics(
    val instantaneousPowerW: Int? = null,
    val pedalPowerBalancePct: Int? = null,
    val accumulatedTorqueNm: Double? = null,
    val cumulativeCrankRevs: Int? = null,
    val lastCrankEventTime1024: Int? = null,
    val cumulativeWheelRevs: Long? = null,
    val lastWheelEventTime1024: Int? = null,
    val derivedCadenceRpm: Double? = null,
    val source: String = "",
)

/**
 * Candidate metrics decoded from a community-documented *proprietary* layout.
 * These are NOT verified against manufacturer documentation and are shown as "candidate".
 */
data class CandidateMetrics(
    val totalPowerW: Int,
    val leftPowerW: Int,
    val rightPowerW: Int,
    val cadenceRpm: Int,
    val crankAngleDeg: Int,
    val errorCode: Int,
    val source: String,
)

object Parsers {
    fun hex(bytes: ByteArray?): String =
        bytes?.joinToString(" ") { String.format("%02X", it) } ?: ""

    private fun u8(b: ByteArray, i: Int) = b[i].toInt() and 0xFF
    private fun u16(b: ByteArray, i: Int) = u8(b, i) or (u8(b, i + 1) shl 8)
    private fun s16(b: ByteArray, i: Int) = u16(b, i).toShort().toInt()
    private fun u32(b: ByteArray, i: Int) =
        (u16(b, i).toLong()) or (u16(b, i + 2).toLong() shl 16)

    /**
     * Cycling Power Measurement (0x2A63), Bluetooth CPS 1.1, section 3.2.
     * Flags (u16) then Instantaneous Power (s16, watts) then optional fields in flag order.
     */
    fun parseCyclingPowerMeasurement(b: ByteArray): CyclingMetrics? {
        if (b.size < 4) return null
        val flags = u16(b, 0)
        var i = 2
        val power = s16(b, i); i += 2
        var balance: Int? = null
        var torque: Double? = null
        var wheelRevs: Long? = null
        var wheelTime: Int? = null
        var crankRevs: Int? = null
        var crankTime: Int? = null
        if (flags and 0x0001 != 0 && i < b.size) { balance = u8(b, i) / 2; i += 1 }          // 0.5 % units
        if (flags and 0x0004 != 0 && i + 1 < b.size) { torque = u16(b, i) / 32.0; i += 2 }   // 1/32 Nm
        if (flags and 0x0010 != 0 && i + 5 < b.size) {
            wheelRevs = u32(b, i); i += 4
            wheelTime = u16(b, i); i += 2  // 1/2048 s for CPS wheel; stored raw
        }
        if (flags and 0x0020 != 0 && i + 3 < b.size) {
            crankRevs = u16(b, i); i += 2
            crankTime = u16(b, i); i += 2  // 1/1024 s
        }
        return CyclingMetrics(
            instantaneousPowerW = power,
            pedalPowerBalancePct = balance,
            accumulatedTorqueNm = torque,
            cumulativeCrankRevs = crankRevs,
            lastCrankEventTime1024 = crankTime,
            cumulativeWheelRevs = wheelRevs,
            lastWheelEventTime1024 = wheelTime,
            source = "SIG Cycling Power Measurement 0x2A63",
        )
    }

    /** CSC Measurement (0x2A5B), CSCS 1.0 section 3.1. */
    fun parseCscMeasurement(b: ByteArray): CyclingMetrics? {
        if (b.isEmpty()) return null
        val flags = u8(b, 0)
        var i = 1
        var wheelRevs: Long? = null
        var wheelTime: Int? = null
        var crankRevs: Int? = null
        var crankTime: Int? = null
        if (flags and 0x01 != 0 && i + 5 < b.size) {
            wheelRevs = u32(b, i); i += 4
            wheelTime = u16(b, i); i += 2
        }
        if (flags and 0x02 != 0 && i + 3 < b.size) {
            crankRevs = u16(b, i); i += 2
            crankTime = u16(b, i); i += 2
        }
        return CyclingMetrics(
            cumulativeCrankRevs = crankRevs,
            lastCrankEventTime1024 = crankTime,
            cumulativeWheelRevs = wheelRevs,
            lastWheelEventTime1024 = wheelTime,
            source = "SIG CSC Measurement 0x2A5B",
        )
    }

    /** Cadence from two consecutive crank samples (revolutions, 1/1024 s event times). */
    fun cadenceFromCrank(prevRevs: Int, prevTime: Int, revs: Int, time: Int): Double? {
        val dRevs = (revs - prevRevs + 65536) % 65536
        val dTime = (time - prevTime + 65536) % 65536
        if (dRevs == 0 || dTime == 0) return null
        return dRevs * 60.0 * 1024.0 / dTime
    }

    /**
     * Community-documented XDS payload (11 bytes, little-endian) seen on characteristic 0x2A63 under
     * service 0x1828. Source: github.com/DuoDuoJuZi/xds_forwarding (xds_protocol.c). Unverified by manufacturer.
     */
    fun parseXdsCandidate(b: ByteArray): CandidateMetrics? {
        if (b.size < 11) return null
        return CandidateMetrics(
            totalPowerW = u16(b, 0),
            leftPowerW = s16(b, 2),
            rightPowerW = s16(b, 4),
            cadenceRpm = s16(b, 6).coerceAtLeast(0),
            crankAngleDeg = u16(b, 8),
            errorCode = u8(b, 10),
            source = "Community layout (xds_forwarding) — UNVERIFIED",
        )
    }

    fun parseBattery(b: ByteArray): Int? = if (b.isNotEmpty()) u8(b, 0) else null

    fun parseUtf8(b: ByteArray): String = b.toString(Charsets.UTF_8).trim { it <= ' ' || it == '\u0000' }

    fun isStringCharacteristic(uuid: UUID): Boolean = uuid in setOf(
        Uuids.DEVICE_NAME, Uuids.MODEL_NUMBER, Uuids.SERIAL_NUMBER, Uuids.FIRMWARE_REV,
        Uuids.HARDWARE_REV, Uuids.SOFTWARE_REV, Uuids.MANUFACTURER_NAME,
    )
}
