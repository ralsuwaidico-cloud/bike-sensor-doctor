package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — no Android imports. This file and RideStats.kt are the parts to re-implement on the
 * ESP32-S3 (see docs/PORTING_SPEC.md). Keep them free of platform code.
 *
 * XDS / Branta power meter, Bluetooth LE, service 0x1828, characteristic 0x2A63 (notify, ~1 Hz).
 * Packet: 11 bytes, little-endian.
 *
 *   offset  size  type  field
 *   0       2     u16   total power, watts
 *   2       2     s16   left power, watts
 *   4       2     s16   right power, watts
 *   6       2     s16   cadence, rpm — SIGNED. Negative was observed on Rashed's unit (2026-10-11) while the
 *                       cranks were turned with the bike stationary; the 66ccff231 bridge README calls negative
 *                       "reverse pedaling". Magnitude is correct either way.
 *   8       2     u16   crank angle, degrees 0..359 (advances every packet while rotating; frozen when idle)
 *   10      1     u8    error code (0 observed)
 *
 * Sources: github.com/DuoDuoJuZi/xds_forwarding (xds_protocol.c), github.com/66ccff231/ad350-nrf52840-bridge
 * (README table + sample packets where total = left + right), and 48 packets captured from XDS-A001-9769.
 */
data class XdsSample(
    val powerW: Int,
    val leftW: Int,
    val rightW: Int,
    val cadenceSignedRpm: Int,
    val crankAngleDeg: Int,
    val errorCode: Int,
) {
    val cadenceRpm: Int get() = if (cadenceSignedRpm < 0) -cadenceSignedRpm else cadenceSignedRpm
    val backwards: Boolean get() = cadenceSignedRpm < 0
    val rotating: Boolean get() = cadenceSignedRpm != 0
    /** Sanity: a real crank is 0..359° and a human 0..250 rpm; power below 3000 W. */
    val plausible: Boolean get() = crankAngleDeg in 0..359 && cadenceRpm <= 250 && powerW in 0..3000
}

object XdsDecoder {
    const val PACKET_LENGTH = 11

    private fun u8(b: ByteArray, i: Int) = b[i].toInt() and 0xFF
    private fun u16(b: ByteArray, i: Int) = u8(b, i) or (u8(b, i + 1) shl 8)
    private fun s16(b: ByteArray, i: Int) = u16(b, i).toShort().toInt()

    /** Returns null for malformed packets (wrong length). Never guesses. */
    fun decode(b: ByteArray): XdsSample? {
        if (b.size < PACKET_LENGTH) return null
        return XdsSample(
            powerW = u16(b, 0),
            leftW = s16(b, 2),
            rightW = s16(b, 4),
            cadenceSignedRpm = s16(b, 6),
            crankAngleDeg = u16(b, 8),
            errorCode = u8(b, 10),
        )
    }

    /** "00 00 .. " hex string → bytes; convenience for tests and log replay. */
    fun fromHex(hex: String): ByteArray =
        hex.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }.map { it.toInt(16).toByte() }.toByteArray()
}
