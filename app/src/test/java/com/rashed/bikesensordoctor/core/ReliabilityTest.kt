package com.rashed.bikesensordoctor.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** P0 acceptance tests [SIM]: P0-3 snapshot/restore, P0-5 zero vs missing, P0-6 link gaps, P0-8 load verification. */
class ReliabilityTest {
    private fun s(p: Int, cad: Int = 90) = XdsSample(p, p / 2, p / 2, cad, 10, 0)

    // ---- P0-5: signal state ----
    @Test fun signalStateDistinguishesZeroFromMissing() {
        val st = RideStats()
        assertEquals(RideStats.SignalState.NONE, st.signalState(0))
        st.onSample(s(150), 1000)
        assertEquals(RideStats.SignalState.FRESH, st.signalState(2000))
        st.onSample(s(0, cad = 0), 3000)                                   // valid zero: cranks still, 0 W
        assertEquals(RideStats.SignalState.COASTING, st.signalState(4000))
        st.onSample(s(0, cad = 60), 5000)                                  // turning but unloaded still counts as fresh signal
        assertEquals(RideStats.SignalState.FRESH, st.signalState(6000))
        assertEquals(RideStats.SignalState.STALE, st.signalState(5000 + RideStats.STALE_MS + 1))
        assertNull(st.livePowerW(5000 + RideStats.STALE_MS + 1))         // stale is never held as a value
    }

    // ---- P0-3: snapshot / restore ----
    @Test fun snapshotRestoreIsLossless() {
        val a = RideStats(); a.start(0)
        for (t in 1..120) a.onSample(s(if (t % 2 == 0) 150 else 250, cad = 80 + t % 10), t * 1000L)
        val snap = a.snapshot(121_000)
        val b = RideStats()
        assertTrue(b.restore(snap))
        assertEquals(RideStats.State.PAUSED, b.state)                      // always comes back paused
        assertEquals(a.elapsedMs(121_000), b.elapsedMs(999_000))           // elapsed frozen at snapshot time
        assertEquals(a.avgPowerW, b.avgPowerW); assertEquals(a.maxPowerW, b.maxPowerW)
        assertEquals(a.avgCadenceRpm, b.avgCadenceRpm); assertEquals(a.maxCadenceRpm, b.maxCadenceRpm)
        assertEquals(a.sampleCount, b.sampleCount); assertEquals(a.normalizedPowerW, b.normalizedPowerW)
        assertEquals(a.startedAtMs, b.startedAtMs)
        // resuming continues counting
        b.resume(1_000_000); b.onSample(s(300), 1_001_000)
        assertEquals(300, b.maxPowerW); assertEquals(a.sampleCount + 1, b.sampleCount)
    }
    @Test fun restoreRejectsGarbage() {
        val b = RideStats()
        assertFalse(b.restore("hello")); assertFalse(b.restore("v=1\nstate=IDLE")); assertFalse(b.restore("v=2\nstate=PAUSED"))
        assertEquals(RideStats.State.IDLE, b.state)
    }

    // ---- P0-6: link monitor ----
    @Test fun linkQualityAndGaps() {
        val m = LinkMonitor()
        for (t in 0 until 60) m.onPacket(t * 1000L, 90, 150)
        assertEquals(100, m.qualityPct(59_000))
        assertEquals(0, m.gaps.size)
        // 20 s hole after a pedaling-under-load period, reported by the link as a clean disconnect
        m.onDisconnect(60_500, "GATT_SUCCESS")
        for (t in 80 until 90) m.onPacket(t * 1000L, 0, 0)
        assertEquals(1, m.gaps.size)
        val g = m.gaps[0]
        assertEquals(59_000, g.startMs); assertEquals(80_000, g.endMs); assertEquals(21_000, g.durationMs)
        assertEquals("GATT_SUCCESS", g.reason)
        assertTrue(g.rotatingBefore); assertTrue(g.poweredBefore)
        assertEquals(70, m.packets)
        assertEquals(79, m.qualityPct(89_000))                              // 70 packets / 89 s = 78.7
        // second gap after a pause (cranks still, 0 W), no disconnect reported → "silence"
        for (t in 110 until 112) m.onPacket(t * 1000L, 90, 120)
        assertEquals(2, m.gaps.size)
        assertFalse(m.gaps[1].rotatingBefore); assertFalse(m.gaps[1].poweredBefore); assertEquals("silence", m.gaps[1].reason)
        // an open gap is closed at finish
        m.finish(130_000)
        assertEquals(3, m.gaps.size); assertEquals(130_000, m.gaps[2].endMs)
        val r = m.report(130_000)
        assertEquals(3, r.gapCount); assertEquals(21_000 + 21_000 + 19_000, r.lostMs)   // 59→80, 89→110, 111→130
        assertTrue(r.verdict().contains("3 gap"))
    }

    // ---- P0-8: load verification ----
    @Test fun loadVerifierPassesOnlyWithRealLoad() {
        val v = LoadVerifier(0)
        for (t in 1..30) v.onSample(s(0, cad = 80), t * 1000L)             // spinning, 0 W
        assertEquals(LoadVerifier.Status.SPINNING_NO_LOAD, v.result(31_000).status)
        for (t in 31..39) v.onSample(s(120, cad = 80), t * 1000L)          // 9 loaded packets: not enough
        assertFalse(v.result(40_000).passed)
        v.onSample(s(130, cad = 80), 40_000)                               // 10th
        val r = v.result(41_000)
        assertTrue(r.passed); assertEquals(10, r.loadedPackets); assertEquals(130, r.maxPowerW)
    }
    @Test fun loadVerifierNeverPassesOnZeroWattsOrStillCranks() {
        val v = LoadVerifier(0)
        for (t in 1..60) v.onSample(s(0, cad = 95), t * 1000L)
        assertEquals(LoadVerifier.Status.TIMEOUT, v.result(61_000).status)
        val w = LoadVerifier(0)
        for (t in 1..60) w.onSample(s(200, cad = 0), t * 1000L)            // power without cadence is not pedaling
        assertFalse(w.result(61_000).passed)
    }
    @Test fun loadVerifierIgnoresImplausibleAndLatePackets() {
        val v = LoadVerifier(0)
        for (t in 1..20) v.onSample(XdsSample(5000, 0, 0, 90, 10, 0), t * 1000L)   // implausible power
        for (t in 70..90) v.onSample(s(150), t * 1000L)                           // after the 60 s window
        assertFalse(v.result(91_000).passed); assertEquals(0, v.result(91_000).loadedPackets)
    }

    // ---- Session phases ----
    @Test fun sessionPhases() {
        val p = SessionPlan(warmupSec = 300)
        assertEquals(Phase.WARMUP, Session.phaseAt(p, 0, null))
        assertEquals(Phase.WARMUP, Session.phaseAt(p, 299_999, null))
        assertEquals(Phase.MAIN, Session.phaseAt(p, 300_000, null))
        assertEquals(Phase.COOLDOWN, Session.phaseAt(p, 3_000_000, 2_900_000))
        assertEquals(Phase.MAIN, Session.phaseAt(SessionPlan(warmupSec = 0), 0, null))
        assertEquals(120, Session.warmupRemainingSec(p, 180_000))
    }
}
