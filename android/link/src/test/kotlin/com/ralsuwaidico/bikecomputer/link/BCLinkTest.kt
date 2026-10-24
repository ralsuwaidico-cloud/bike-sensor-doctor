package com.ralsuwaidico.bikecomputer.link

import org.junit.Assert.*
import org.junit.Test

/** Same conformance vectors as ios/BikeComputerTests/BCLinkTests.swift and firmware test/host (t_link). */
class BCLinkTest {
    private fun b(vararg v: Int) = ByteArray(v.size) { v[it].toByte() }

    @Test fun liveDecodeFromFirmwareBytes() {
        val bytes = b(0x10, 0, 7, 0, 0x40, 0xE2, 0x01, 0x00,
            0x01, 2, 0xE7, 0x00, 0x02, 2, 0x90, 0x01, 0x03, 1, 88, 0x04, 2, 0xF4, 0x01,
            0x08, 1, 1, 0x09, 2, 12, 0, 0x0A, 4, 0x10, 0x0E, 0, 0, 0x0B, 4, 0xA8, 0x61, 0, 0,
            0x0C, 1, 3, 0x0D, 1, 77, 0x0E, 1, 4, 0x0F, 2, 2, 0)
        val l = BCLink.decodeLive(bytes)!!
        assertEquals(231, l.powerW); assertEquals(400, l.powerAgeMs); assertEquals(88, l.cadenceRpm); assertNull(l.hrBpm)
        assertEquals(BCLink.RideState.RUNNING, l.rideState); assertEquals(12, l.rideId); assertEquals(3600L, l.elapsedS); assertEquals(25000L, l.distanceM)
        assertEquals(77, l.batteryPct); assertEquals(2, l.meterGaps); assertFalse(l.demo); assertEquals(7, l.seq); assertEquals(123456L, l.boardTimeMs)
        assertNull(BCLink.decodeLive(bytes.copyOf(bytes.size - 1)))
        assertNull(BCLink.decodeLive(bytes.copyOf(5)))
        assertTrue(BCLink.decodeLive(bytes + b(0x10, 1, 1))!!.demo)
        val m = b(0x10, 0, 1, 0, 0, 0, 0, 0, 0x7E, 3, 1, 2, 3, 0x01, 1, 9, 0x08, 1, 2)
        val u = BCLink.decodeLive(m)!!
        assertNull(u.powerW); assertEquals(BCLink.RideState.PAUSED, u.rideState)
        assertNull(BCLink.decodeLive(b(0x21) + m.copyOfRange(1, m.size)))
    }

    @Test fun gpsEncodingMatchesFirmwareLayout() {
        val d = BCLink.encodeGPS(BCLink.GPSFix(244667000, 544000000, 120, 50, 80, 833, 9000, 1761300000000L), 2, 0)!!
        val x = d.map { it.toInt() and 0xFF }
        assertEquals(0x21, x[0]); assertEquals(2, x[2])
        assertEquals(listOf(0x01, 4, 120, 82, 149, 14), x.subList(8, 14))
        assertEquals(listOf(0x02, 4, 0, 200, 108, 32), x.subList(14, 20))
        assertTrue(d.size <= BCLink.MAX_MESSAGE)
        assertEquals(listOf(0x09, 1, 3), x.takeLast(3))
    }

    @Test fun timeAndHREncoding() {
        val t = BCLink.encodeTime(1761300000000L, 50, 240, 1, 0)!!.map { it.toInt() and 0xFF }
        assertEquals(0x20, t[0])
        assertEquals(listOf(0x01, 8, 0, 45, 169, 21, 154, 1, 0, 0), t.subList(8, 18))
        assertEquals(listOf(0x02, 2, 50, 0), t.subList(18, 22))
        assertEquals(listOf(0x03, 2, 0xF0, 0x00), t.subList(22, 26))
        val h = BCLink.encodeHR(152, BCLink.Source.APPLE_WATCH, 1761300000000L, 2, 3, 0)!!.map { it.toInt() and 0xFF }
        assertEquals(0x22, h[0]); assertEquals(listOf(0x01, 1, 152, 0x02, 1, 4), h.subList(8, 14))
    }

    @Test fun controlRoundTrip() {
        val req = BCLink.encodeControl(9, BCLink.Command.STOP_REQUEST, 12, 5, 0)!!.map { it.toInt() and 0xFF }
        assertEquals(listOf(0x01, 2, 9, 0, 0x02, 1, 4, 0x03, 2, 12, 0), req.drop(8))
        val r = BCLink.decodeControlResponse(b(0x31, 0, 6, 0, 0, 0, 0, 0, 0x01, 2, 9, 0, 0x02, 1, 2, 0x03, 1, 1, 0x04, 2, 12, 0))!!
        assertEquals(9, r.reqId); assertEquals(BCLink.Status.NEEDS_CONFIRM, r.status); assertEquals(BCLink.RideState.RUNNING, r.rideState); assertEquals(12, r.rideId)
    }

    @Test fun info() {
        val w = BCLink.Writer(BCLink.Type.INFO, 0, 0)
        w.u8(0x01, 1); w.u8(0x02, 0); w.str(0x03, "0.4.0"); w.str(0x04, "BikeComputer"); w.u32(0x05, 0x3F); w.u16(0x06, 180)
        val i = BCLink.decodeInfo(w.result!!)!!
        assertEquals("0.4.0", i.fw); assertEquals("BikeComputer", i.name); assertEquals(0x3FL, i.caps); assertEquals(180, i.maxMsg)
        assertNull(BCLink.decodeInfo(b(0x01, 0, 0, 0, 0, 0, 0, 0)))
    }

    @Test fun signedHelper() {
        assertEquals(-1L, BCLink.sint(b(0xFF, 0xFF)))
        assertEquals(-32768L, BCLink.sint(b(0x00, 0x80, 0xFF, 0xFF)))
        assertEquals(3600L, BCLink.uint(b(0x10, 0x0E, 0, 0)))
    }
}
