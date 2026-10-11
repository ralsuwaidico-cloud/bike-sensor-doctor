package com.rashed.bikesensordoctor

import com.rashed.bikesensordoctor.ble.Parsers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/** Pure-JVM tests for the byte parsers (no Android dependencies). Run: ./gradlew testDebugUnitTest */
class ParsersTest {

    @Test
    fun cyclingPowerMeasurement_powerOnly() {
        // flags=0x0000, power=250 W (0x00FA little-endian)
        val m = Parsers.parseCyclingPowerMeasurement(byteArrayOf(0x00, 0x00, 0xFA.toByte(), 0x00))!!
        assertEquals(250, m.instantaneousPowerW)
        assertNull(m.cumulativeCrankRevs)
    }

    @Test
    fun cyclingPowerMeasurement_withBalanceAndCrank() {
        // flags: balance present (bit0) + crank data present (bit5) = 0x0021
        val b = byteArrayOf(0x21, 0x00, 0x2C, 0x01, 100, 0x10, 0x00, 0x00, 0x04)
        // power 0x012C=300, balance 100/2=50%, crankRevs 0x0010=16, time 0x0400=1024
        val m = Parsers.parseCyclingPowerMeasurement(b)!!
        assertEquals(300, m.instantaneousPowerW)
        assertEquals(50, m.pedalPowerBalancePct)
        assertEquals(16, m.cumulativeCrankRevs)
        assertEquals(1024, m.lastCrankEventTime1024)
    }

    @Test
    fun csc_crankOnly() {
        val m = Parsers.parseCscMeasurement(byteArrayOf(0x02, 0x05, 0x00, 0x00, 0x08))!!
        assertEquals(5, m.cumulativeCrankRevs)
        assertEquals(0x0800, m.lastCrankEventTime1024)
    }

    @Test
    fun cadence_80rpm() {
        // 4 revs in 3 s (3072 ticks at 1024 Hz) = 80 rpm
        val c = Parsers.cadenceFromCrank(10, 1000, 14, 4072)!!
        assertEquals(80.0, c, 0.01)
    }

    @Test
    fun cadence_wrapsAround16bit() {
        val c = Parsers.cadenceFromCrank(65535, 65000, 1, 500)!!   // 2 revs in 1036 ticks
        assertEquals(2 * 60.0 * 1024 / 1036, c, 0.01)
    }

    @Test
    fun xdsCandidate_communityLayout() {
        val b = byteArrayOf(0xC8.toByte(), 0x00, 0x64, 0x00, 0x64, 0x00, 0x5A, 0x00, 0x2D, 0x01, 0x00)
        val c = Parsers.parseXdsCandidate(b)!!
        assertEquals(200, c.totalPowerW); assertEquals(100, c.leftPowerW); assertEquals(90, c.cadenceRpm); assertEquals(301, c.crankAngleDeg)
    }

    @Test
    fun shortPayloadsAreRejected() {
        assertNull(Parsers.parseCyclingPowerMeasurement(byteArrayOf(0x00)))
        assertNull(Parsers.parseXdsCandidate(byteArrayOf(1, 2, 3)))
        assertNotNull(Parsers.parseCscMeasurement(byteArrayOf(0x00)))
    }

    @Test
    fun hexFormatting() {
        assertEquals("01 AB FF", Parsers.hex(byteArrayOf(0x01, 0xAB.toByte(), 0xFF.toByte())))
    }
}
