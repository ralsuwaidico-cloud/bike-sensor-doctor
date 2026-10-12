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

class ConnectionPolicyTest {
    @Test fun userDisconnectStops() =
        assertEquals(RecoveryAction.STOP, ConnectionPolicy.decide(userDisconnect = true, everReady = false, triedAutoConnect = false))

    @Test fun firstFailureTriesAutoConnect() =
        assertEquals(RecoveryAction.TRY_AUTOCONNECT, ConnectionPolicy.decide(false, everReady = false, triedAutoConnect = false))

    @Test fun secondFailureSchedulesRetry() =
        assertEquals(RecoveryAction.SCHEDULE_RETRY, ConnectionPolicy.decide(false, everReady = false, triedAutoConnect = true))

    @Test fun dropAfterReadyReconnects() =
        assertEquals(RecoveryAction.SCHEDULE_RETRY, ConnectionPolicy.decide(false, everReady = true, triedAutoConnect = false))

    @Test fun backoffDoublesAndCaps() {
        assertEquals(2000L, ConnectionPolicy.nextBackoffMs(1000L))
        assertEquals(16000L, ConnectionPolicy.nextBackoffMs(10000L))
        assertEquals(16000L, ConnectionPolicy.nextBackoffMs(16000L))
    }
}

class ZonesTest {
    @Test fun powerZonesAtFtp200() {
        val ftp = 200
        assertEquals(0, PowerZones.zone(0, ftp))       // coasting → neutral
        assertEquals(1, PowerZones.zone(100, ftp))     // 50% → Z1
        assertEquals(2, PowerZones.zone(130, ftp))     // 65% → Z2 endurance
        assertEquals(3, PowerZones.zone(170, ftp))     // 85% → Z3
        assertEquals(4, PowerZones.zone(200, ftp))     // 100% → Z4
        assertEquals(5, PowerZones.zone(230, ftp))     // 115% → Z5
        assertEquals(7, PowerZones.zone(400, ftp))     // 200% → Z7
    }
    @Test fun zone2Detection() {
        assertTrue(PowerZones.isZone2(130, 200))
        assertFalse(PowerZones.isZone2(190, 200))
    }
    @Test fun zone2Range() {
        val (lo, hi) = PowerZones.range(2, 200)
        assertEquals(110, lo); assertEquals(150, hi)
    }
    @Test fun hrZonesAtMax190() {
        assertEquals(1, HrZones.zone(100, 190))   // 53%
        assertEquals(2, HrZones.zone(125, 190))   // 66%
        assertEquals(5, HrZones.zone(185, 190))   // 97%
        assertTrue(HrZones.isZone2(125, 190))
    }
}

class BleStandardTest {
    @Test fun heartRate8and16bit() {
        assertEquals(72, BleStandard.heartRate(byteArrayOf(0x00, 72)))               // flags=0 → 8-bit
        assertEquals(300, BleStandard.heartRate(byteArrayOf(0x01, 0x2C, 0x01)))      // flags bit0 → 16-bit 0x012C
        assertNull(BleStandard.heartRate(byteArrayOf()))
    }
    @Test fun standardPowerInstantWatts() {
        // flags 0x0000, power 250 (0x00FA)
        assertEquals(250, BleStandard.cyclingPowerWatts(byteArrayOf(0x00, 0x00, 0xFA.toByte(), 0x00)))
        assertNull(BleStandard.cyclingPowerWatts(byteArrayOf(0x00)))
    }
    @Test fun cscCrankAndCadence() {
        val a = BleStandard.cscCrank(byteArrayOf(0x02, 10, 0, 0x00, 0x04))!!   // crank only, revs=10, t=0x0400
        val b = BleStandard.cscCrank(byteArrayOf(0x02, 14, 0, 0x00, 0x08))!!   // revs=14, t=0x0800 (+1024 ticks=1s), +4 revs
        assertEquals(10, a.cumulativeRevs)
        assertEquals(240.0, BleStandard.cadenceRpm(a, b)!!, 0.01)              // 4 rev/s = 240 rpm
    }
    @Test fun cscSkipsWheelBlock() {
        // flags 0x03 (wheel+crank): 1 flag +6 wheel, then crank revs=5 t=0x0100
        val s = BleStandard.cscCrank(byteArrayOf(0x03, 0,0,0,0, 0,0, 5,0, 0x00,0x01))!!
        assertEquals(5, s.cumulativeRevs)
    }
}

class RideStatsWindowTest {
    @Test fun tenSecondAverageSpansLongerThanThree() {
        val st = RideStats(); st.start(0)
        fun p(w: Int) = XdsSample(w, w/2, w/2, 85, 10, 0)
        // 0..9s at 100,110,...; recent 3s should average the last ~3 samples, 10s the last ~10
        var w = 100
        for (t in 0..9) { st.onSample(p(w), t * 1000L); w += 20 }  // 100,120,...,280 at t=0..9s
        val now = 9000L
        val p3 = st.power3sW(now)!!    // t within 3s of 9s → 6,7,8,9s → 220,240,260,280 → 250
        val p10 = st.power10sW(now)!!  // all 10 → mean(100..280 step 20) = 190
        assertEquals(250, p3)
        assertEquals(190, p10)
    }
}
