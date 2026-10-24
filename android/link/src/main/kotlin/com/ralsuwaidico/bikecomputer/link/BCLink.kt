package com.ralsuwaidico.bikecomputer.link

/**
 * BikeComputer Link protocol v1 — Kotlin twin of ios/Shared/BCLink.swift and the firmware's bc_link.c.
 * 8-byte header (type, flags, seq LE16, tMs LE32) followed by tag/len/value fields, little-endian.
 * Unknown tags are skipped; a truncated message is rejected as a whole. No field is ever guessed.
 */
object BCLink {
    const val VER_MAJOR = 1
    const val VER_MINOR = 0
    const val MAX_MESSAGE = 180
    const val SERVICE_UUID = "B1CE0000-7E3A-4C55-9D2B-5A0E1C7C0000"
    const val INFO_UUID = "B1CE0002-7E3A-4C55-9D2B-5A0E1C7C0000"
    const val LIVE_UUID = "B1CE0003-7E3A-4C55-9D2B-5A0E1C7C0000"
    const val INPUT_UUID = "B1CE0004-7E3A-4C55-9D2B-5A0E1C7C0000"
    const val CONTROL_UUID = "B1CE0005-7E3A-4C55-9D2B-5A0E1C7C0000"

    object Type { const val INFO = 0x01; const val LIVE = 0x10; const val IN_TIME = 0x20; const val IN_GPS = 0x21; const val IN_HR = 0x22; const val IN_BATTERY = 0x24; const val CTRL_REQ = 0x30; const val CTRL_RESP = 0x31 }
    enum class Source(val code: Int, val label: String) {
        UNKNOWN(0, "?"), XDS(1, "XDS"), BLE_STRAP(2, "Strap"), PHONE_GPS(3, "Phone GPS"), WEAR_OS(5, "Wear OS"), PHONE_STRAP(6, "Phone strap"), ONBOARD_GPS(7, "GPS"), APPLE_WATCH(4, "Apple Watch"), DEMO(0x7F, "DEMO");
        companion object { fun of(c: Int) = entries.firstOrNull { it.code == c } ?: UNKNOWN }
    }
    enum class Command(val code: Int) { START(1), PAUSE(2), RESUME(3), STOP_REQUEST(4), STOP_CONFIRM(5) }
    enum class Status(val code: Int) { OK(0), BAD_STATE(1), NEEDS_CONFIRM(2), UNKNOWN(3), WRONG_RIDE(4);
        companion object { fun of(c: Int) = entries.firstOrNull { it.code == c } ?: UNKNOWN } }
    enum class RideState(val code: Int) { IDLE(0), RUNNING(1), PAUSED(2), ENDED(3);
        companion object { fun of(c: Int) = entries.firstOrNull { it.code == c } ?: IDLE } }

    data class Header(val type: Int, val flags: Int, val seq: Int, val tMs: Long)
    data class Field(val tag: Int, val value: ByteArray)

    /** Live values from the board. null = "no data right now", never a held value. */
    data class Live(
        val powerW: Int? = null, val powerAgeMs: Int? = null, val cadenceRpm: Int? = null, val cadAgeMs: Int? = null,
        val hrBpm: Int? = null, val hrSource: Source = Source.UNKNOWN, val hrAgeMs: Int? = null,
        val rideState: RideState = RideState.IDLE, val rideId: Int = 0, val elapsedS: Long = 0, val distanceM: Long = 0,
        val cueId: Int = 0, val batteryPct: Int? = null, val meterLink: Int = 0, val meterGaps: Int = 0, val demo: Boolean = false,
        val seq: Int = 0, val boardTimeMs: Long = 0,
    )
    data class ControlResponse(val reqId: Int = 0, val status: Status = Status.UNKNOWN, val rideState: RideState = RideState.IDLE, val rideId: Int = 0)
    data class Info(val verMajor: Int, val verMinor: Int, val fw: String, val name: String, val caps: Long, val maxMsg: Int)

    fun uint(v: ByteArray): Long { var x = 0L; for (i in v.indices) if (i < 8) x = x or ((v[i].toLong() and 0xFF) shl (8 * i)); return x }
    fun sint(v: ByteArray): Long { val x = uint(v); val bits = 8 * v.size; return if (bits in 1..63 && (x shr (bits - 1)) and 1L == 1L) x - (1L shl bits) else x }

    fun parse(d: ByteArray): Pair<Header, List<Field>>? {
        if (d.size < 8) return null
        val h = Header(d[0].toInt() and 0xFF, d[1].toInt() and 0xFF, uint(d.copyOfRange(2, 4)).toInt(), uint(d.copyOfRange(4, 8)))
        val out = ArrayList<Field>(); var p = 8
        while (p < d.size) {
            if (p + 2 > d.size) return null
            val tag = d[p].toInt() and 0xFF; val len = d[p + 1].toInt() and 0xFF
            if (p + 2 + len > d.size) return null
            out += Field(tag, d.copyOfRange(p + 2, p + 2 + len)); p += 2 + len
        }
        return h to out
    }

    fun decodeLive(d: ByteArray): Live? {
        val (h, f) = parse(d) ?: return null
        if (h.type != Type.LIVE) return null
        var l = Live(seq = h.seq, boardTimeMs = h.tMs)
        for (x in f) { val v = x.value
            when (x.tag to v.size) {
                0x01 to 2 -> l = l.copy(powerW = uint(v).toInt()); 0x02 to 2 -> l = l.copy(powerAgeMs = uint(v).toInt())
                0x03 to 1 -> l = l.copy(cadenceRpm = v[0].toInt() and 0xFF); 0x04 to 2 -> l = l.copy(cadAgeMs = uint(v).toInt())
                0x05 to 1 -> l = l.copy(hrBpm = v[0].toInt() and 0xFF); 0x06 to 1 -> l = l.copy(hrSource = Source.of(v[0].toInt() and 0xFF))
                0x07 to 2 -> l = l.copy(hrAgeMs = uint(v).toInt()); 0x08 to 1 -> l = l.copy(rideState = RideState.of(v[0].toInt() and 0xFF))
                0x09 to 2 -> l = l.copy(rideId = uint(v).toInt()); 0x0A to 4 -> l = l.copy(elapsedS = uint(v)); 0x0B to 4 -> l = l.copy(distanceM = uint(v))
                0x0C to 1 -> l = l.copy(cueId = v[0].toInt() and 0xFF); 0x0D to 1 -> l = l.copy(batteryPct = if ((v[0].toInt() and 0xFF) == 0xFF) null else v[0].toInt() and 0xFF)
                0x0E to 1 -> l = l.copy(meterLink = v[0].toInt() and 0xFF); 0x0F to 2 -> l = l.copy(meterGaps = uint(v).toInt()); 0x10 to 1 -> l = l.copy(demo = v[0].toInt() != 0)
            }
        }
        return l
    }

    fun decodeControlResponse(d: ByteArray): ControlResponse? {
        val (h, f) = parse(d) ?: return null
        if (h.type != Type.CTRL_RESP) return null
        var r = ControlResponse()
        for (x in f) { val v = x.value
            when (x.tag to v.size) {
                0x01 to 2 -> r = r.copy(reqId = uint(v).toInt()); 0x02 to 1 -> r = r.copy(status = Status.of(v[0].toInt() and 0xFF))
                0x03 to 1 -> r = r.copy(rideState = RideState.of(v[0].toInt() and 0xFF)); 0x04 to 2 -> r = r.copy(rideId = uint(v).toInt())
            }
        }
        return r
    }

    fun decodeInfo(d: ByteArray): Info? {
        val (h, f) = parse(d) ?: return null
        if (h.type != Type.INFO) return null
        var major: Int? = null; var minor = 0; var fw = ""; var name = ""; var caps = 0L; var maxMsg = 0
        for (x in f) { val v = x.value
            when (x.tag) { 0x01 -> if (v.size == 1) major = v[0].toInt() and 0xFF; 0x02 -> if (v.size == 1) minor = v[0].toInt() and 0xFF
                0x03 -> fw = String(v, Charsets.UTF_8); 0x04 -> name = String(v, Charsets.UTF_8); 0x05 -> if (v.size == 4) caps = uint(v); 0x06 -> if (v.size == 2) maxMsg = uint(v).toInt() }
        }
        return Info(major ?: return null, minor, fw, name, caps, maxMsg)
    }

    /** Writer with the same size limit as the Swift and C writers. */
    class Writer(type: Int, seq: Int, tMs: Long) {
        private val buf = ArrayList<Byte>(); var ok = true; private set
        init { buf += type.toByte(); buf += 0; le(seq.toLong(), 2); le(tMs, 4) }
        private fun le(v: Long, n: Int) { for (i in 0 until n) buf += ((v shr (8 * i)) and 0xFF).toByte() }
        fun field(tag: Int, value: ByteArray) { if (!ok || buf.size + 2 + value.size > MAX_MESSAGE || value.size > 255) { ok = false; return }; buf += tag.toByte(); buf += value.size.toByte(); value.forEach { buf += it } }
        fun u8(tag: Int, v: Int) = field(tag, byteArrayOf(v.toByte()))
        fun u16(tag: Int, v: Int) = field(tag, leBytes(v.toLong(), 2))
        fun s16(tag: Int, v: Int) = field(tag, leBytes(v.toLong(), 2))
        fun u32(tag: Int, v: Long) = field(tag, leBytes(v, 4))
        fun s32(tag: Int, v: Int) = field(tag, leBytes(v.toLong(), 4))
        fun u64(tag: Int, v: Long) = field(tag, leBytes(v, 8))
        fun str(tag: Int, s: String) = field(tag, s.toByteArray(Charsets.UTF_8))
        val result: ByteArray? get() = if (ok) buf.toByteArray() else null
        companion object { fun leBytes(v: Long, n: Int) = ByteArray(n) { i -> ((v shr (8 * i)) and 0xFF).toByte() } }
    }

    data class GPSFix(val latE7: Int, val lonE7: Int, val altDm: Int?, val haccDm: Int, val vaccDm: Int, val speedCms: Int?, val courseCdeg: Int?, val fixEpochMs: Long, val source: Source = Source.PHONE_GPS)

    fun encodeTime(epochMs: Long, uncertaintyMs: Int, tzMinutes: Int, seq: Int, tMs: Long): ByteArray? {
        val w = Writer(Type.IN_TIME, seq, tMs); w.u64(0x01, epochMs); w.u16(0x02, uncertaintyMs); w.s16(0x03, tzMinutes); return w.result
    }
    fun encodeGPS(g: GPSFix, seq: Int, tMs: Long): ByteArray? {
        val w = Writer(Type.IN_GPS, seq, tMs)
        w.s32(0x01, g.latE7); w.s32(0x02, g.lonE7); g.altDm?.let { w.s32(0x03, it) }
        w.u16(0x04, g.haccDm); w.u16(0x05, g.vaccDm); g.speedCms?.let { w.u16(0x06, it) }; g.courseCdeg?.let { w.u16(0x07, it) }
        w.u64(0x08, g.fixEpochMs); w.u8(0x09, g.source.code); return w.result
    }
    fun encodeHR(bpm: Int, source: Source, sampleEpochMs: Long, quality: Int, seq: Int, tMs: Long): ByteArray? {
        val w = Writer(Type.IN_HR, seq, tMs); w.u8(0x01, bpm); w.u8(0x02, source.code); w.u64(0x03, sampleEpochMs); w.u8(0x04, quality); return w.result
    }
    fun encodeControl(reqId: Int, cmd: Command, rideId: Int, seq: Int, tMs: Long): ByteArray? {
        val w = Writer(Type.CTRL_REQ, seq, tMs); w.u16(0x01, reqId); w.u8(0x02, cmd.code); w.u16(0x03, rideId); return w.result
    }
}
