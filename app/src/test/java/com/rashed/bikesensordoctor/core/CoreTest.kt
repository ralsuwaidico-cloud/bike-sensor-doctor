package com.rashed.bikesensordoctor.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Pure-JVM regression tests for the portable core, driven by real captured packets. */
class XdsDecoderTest {

    @Test
    fun idlePackets_decodeToZeroWithFrozenAngle() {
        val idle = Fixtures.parsed().take(32).map { XdsDecoder.decode(it.second)!! }
        assertTrue(idle.all { it.powerW == 0 && it.cadenceSignedRpm == 0 && !it.rotating })
        assertTrue("angle must be frozen while idle", idle.map { it.crankAngleDeg }.toSet().size == 1)
        assertEquals(346, idle.first().crankAngleDeg)
    }

    @Test
    fun rotatingPackets_negativeCadence_isReportedAsBackwardsWithCorrectMagnitude() {
        val spin = Fixtures.parsed().drop(32).map { XdsDecoder.decode(it.second)!! }
        assertEquals(16, spin.size)
        assertTrue(spin.all { it.rotating && it.backwards })
        // Rider was asked for ~80 rpm; the unit reported -24 ramping to -88, then ~-80..-88
        val settled = spin.drop(4).map { it.cadenceRpm }
        assertTrue("settled cadence should be 70..95 rpm, was $settled", settled.all { it in 70..95 })
        assertTrue("angle must advance while rotating", spin.map { it.crankAngleDeg }.toSet().size > 10)
        assertTrue(spin.all { it.powerW == 0 })  // unloaded cranks
        assertTrue(spin.all { it.plausible })
    }

    @Test
    fun forwardCadence_fromCommunitySamples_isPositiveAndSumsLeftRight() {
        for (hex in Fixtures.COMMUNITY_SAMPLES) {
            val s = XdsDecoder.decode(XdsDecoder.fromHex(hex))!!
            assertFalse(s.backwards); assertTrue(s.rotating)
            assertEquals(s.powerW, s.leftW + s.rightW)
        }
        val s = XdsDecoder.decode(XdsDecoder.fromHex("C8 00 64 00 64 00 5A 00 2D 01 00"))!!
        assertEquals(200, s.powerW); assertEquals(90, s.cadenceRpm); assertFalse(s.backwards); assertEquals(301, s.crankAngleDeg)
    }

    @Test
    fun malformedPackets_areRejectedNotGuessed() {
        assertNull(XdsDecoder.decode(ByteArray(0)))
        assertNull(XdsDecoder.decode(ByteArray(10)))
        // 11 bytes but absurd values → decodes, flagged implausible, RideStats must ignore it
        val junk = XdsDecoder.decode(XdsDecoder.fromHex("FF FF 00 00 00 00 10 27 FF FF 00"))!!
        assertFalse(junk.plausible)
    }
}

class RideStatsTest {

    private fun replay(stats: RideStats, startRunningAt: Long?, t0: Long = 1_000_000L): Long {
        var now = t0
        if (startRunningAt == null) stats.start(t0)
        for ((rel, bytes) in Fixtures.parsed()) {
            now = t0 + rel
            if (startRunningAt != null && rel >= startRunningAt && stats.state == RideStats.State.IDLE) stats.start(now)
            XdsDecoder.decode(bytes)?.let { stats.onSample(it, now) }
        }
        return now
    }

    @Test
    fun realSession_cadenceCountedBackwardsPowerZero() {
        val st = RideStats()
        val end = replay(st, null)
        assertEquals(48, st.sampleCount)
        assertEquals(0, st.rejectedCount)
        assertEquals(0, st.avgPowerW); assertEquals(0, st.maxPowerW)
        assertEquals(16, st.backwardsSamples)
        assertTrue(st.avgCadenceRpm in 60..90)
        assertEquals(88, st.maxCadenceRpm)
        assertEquals(82, st.liveCadenceRpm(end))   // last packet: AE FF = -82 → live shows 82
        assertTrue(st.liveBackwards(end))
        assertTrue(st.elapsedMs(end) in 47_000L..48_000L)
    }

    @Test
    fun threeSecondPower_isMeanOfRecentSamples_andGoesStale() {
        val st = RideStats(); st.start(0)
        fun s(p: Int) = XdsSample(p, p / 2, p / 2, 85, 10, 0)
        st.onSample(s(100), 0); st.onSample(s(200), 1000); st.onSample(s(300), 2000); st.onSample(s(400), 3000)
        assertEquals(250, st.power3sW(3000))         // 100,200,300,400 all within 3 s window
        assertEquals(300, st.power3sW(4000))         // 200,300,400 (100 aged out)
        assertEquals(400, st.livePowerW(4000))
        assertNull("4 s after last sample → stale → null, never a held value", st.livePowerW(7001))
        assertNull(st.power3sW(7001))
        assertEquals(250, st.avgPowerW); assertEquals(400, st.maxPowerW)
    }

    @Test
    fun pauseStopsTimeAndStatistics() {
        val st = RideStats(); st.start(0)
        st.onSample(XdsSample(200, 100, 100, 90, 0, 0), 1000)
        st.pause(2000)
        st.onSample(XdsSample(900, 450, 450, 120, 0, 0), 3000)   // must be ignored
        assertEquals(2000, st.elapsedMs(10_000))
        assertEquals(RideStats.State.PAUSED, st.state)
        st.resume(10_000)
        st.onSample(XdsSample(300, 150, 150, 80, 0, 0), 11_000)
        assertEquals(3000, st.elapsedMs(11_000))
        assertEquals(2, st.sampleCount); assertEquals(250, st.avgPowerW); assertEquals(300, st.maxPowerW)
        assertEquals(85, st.avgCadenceRpm); assertEquals(90, st.maxCadenceRpm)
        st.finish(12_000)
        assertEquals(RideStats.State.FINISHED, st.state)
        val sum = st.summary(12_000)
        assertEquals(4000, sum.durationMs); assertEquals(250, sum.avgPowerW)
    }

    @Test
    fun implausibleSamplesDoNotInflateMax() {
        val st = RideStats(); st.start(0)
        st.onSample(XdsSample(150, 75, 75, 80, 0, 0), 1000)
        st.onSample(XdsSample(65535, 0, 0, 10000, 65535, 0), 2000)
        assertEquals(1, st.rejectedCount); assertEquals(150, st.maxPowerW); assertEquals(1, st.sampleCount)
    }

    @Test
    fun coastingSamplesCountForPowerAverageButNotCadenceAverage() {
        val st = RideStats(); st.start(0)
        st.onSample(XdsSample(200, 100, 100, 90, 0, 0), 1000)
        st.onSample(XdsSample(0, 0, 0, 0, 0, 0), 2000)
        assertEquals(100, st.avgPowerW); assertEquals(90, st.avgCadenceRpm)
    }
}

class HealthClassifierTest {
    private val live = XdsSample(150, 75, 75, 85, 90, 0)

    @Test fun permissionBeatsEverything() = assertEquals(Health.NO_PERMISSION, HealthClassifier.classify(true, false, true, false, 100, live, 0))
    @Test fun bluetoothOff() = assertEquals(Health.BLUETOOTH_OFF, HealthClassifier.classify(false, true, false, false, null, null, 0))
    @Test fun searching() = assertEquals(Health.SEARCHING, HealthClassifier.classify(true, true, false, false, null, null, 0))
    @Test fun reconnecting() = assertEquals(Health.RECONNECTING, HealthClassifier.classify(true, true, false, true, 20_000, live, 0))
    @Test fun linkSilent_isBluetoothNotSensor() = assertEquals(Health.LINK_SILENT, HealthClassifier.classify(true, true, true, false, 9_000, live, 0))
    @Test fun decodeError_isSoftware() = assertEquals(Health.DECODE_ERROR, HealthClassifier.classify(true, true, true, false, 500, null, 5))
    @Test fun sensorFault_fromErrorByte() = assertEquals(Health.SENSOR_FAULT, HealthClassifier.classify(true, true, true, false, 500, live.copy(errorCode = 3), 0))
    @Test fun liveAndIdle() {
        assertEquals(Health.CONNECTED_LIVE, HealthClassifier.classify(true, true, true, false, 500, live, 0))
        assertEquals(Health.CONNECTED_IDLE, HealthClassifier.classify(true, true, true, false, 500, live.copy(cadenceSignedRpm = 0), 0))
    }
}
