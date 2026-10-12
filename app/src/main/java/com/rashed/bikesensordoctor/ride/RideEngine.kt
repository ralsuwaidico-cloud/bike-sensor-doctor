package com.rashed.bikesensordoctor.ride

import android.app.Application
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.os.Build
import com.rashed.bikesensordoctor.ble.BleScanner
import com.rashed.bikesensordoctor.ble.GattManager
import com.rashed.bikesensordoctor.core.Health
import com.rashed.bikesensordoctor.core.Phase
import com.rashed.bikesensordoctor.core.Session
import com.rashed.bikesensordoctor.core.SessionPlan
import com.rashed.bikesensordoctor.core.LinkMonitor
import com.rashed.bikesensordoctor.core.CoachInput
import com.rashed.bikesensordoctor.core.Signal
import com.rashed.bikesensordoctor.core.RideStats
import com.rashed.bikesensordoctor.core.XdsSample
import com.rashed.bikesensordoctor.log.EventLog
import com.rashed.bikesensordoctor.log.EventType
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Everything the dashboard shows, refreshed every 500 ms. Nulls mean "no fresh measurement" and render as "—". */
data class Dashboard(
    val health: Health = Health.SEARCHING,
    val healthText: String = "",
    val rideState: RideStats.State = RideStats.State.IDLE,
    val powerW: Int? = null,
    val power3sW: Int? = null,
    val power10sW: Int? = null,
    val cadenceRpm: Int? = null,
    val backwards: Boolean = false,
    val crankAngle: Int? = null,
    val avgPowerW: Int = 0,
    val maxPowerW: Int = 0,
    val avgCadenceRpm: Int = 0,
    val maxCadenceRpm: Int = 0,
    val energyKj: Double = 0.0,
    val elapsedMs: Long = 0,
    val batteryPct: Int? = null,
    val rssi: Int? = null,
    val sensorName: String = "",
    val leftW: Int? = null,
    val rightW: Int? = null,
    val powerZone: Int = 0,
    val speedKmh: Double? = null,
    val distanceKm: Double = 0.0,
    val gpsFix: Boolean = false,
    val hrBpm: Int? = null,
    val hrZone: Int = 0,
    val hrConnected: Boolean = false,
    val hrBatteryPct: Int? = null,
    val linkUptimeSec: Long = 0,
    val recentPower: List<Int> = emptyList(),   // last 5 min of 1 Hz power for the trend chart
    val lastSavedRide: String? = null,
    val normalizedPowerW: Int? = null,          // Coggan NP, null until 30 s of riding
    val variabilityIndex: Double? = null,       // NP / avg power, null until NP exists
    val coachMode: String = "FREE",
    // ---- P0/P1 additions ----
    val signal: RideStats.SignalState = RideStats.SignalState.NONE,   // FRESH / COASTING / STALE / NONE
    val phase: Phase = Phase.MAIN,
    val warmupRemainingSec: Int = 0,
    val linkQualityPct: Int? = null,
    val linkGaps: Int = 0,
    val linkLostSec: Long = 0,
    val powerVerified: Boolean = false,
    val coachReason: String = "",
    val restoredRide: Boolean = false,                                // true after a ride was recovered from a checkpoint
)

/**
 * App-wide singleton (via BikeApp) that owns the Bluetooth link, the portable RideStats, and persistence.
 * The foreground RideService only keeps the process alive and shows the notification; logic lives here.
 */
class RideEngine(private val app: Application) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val adapter = (app.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
    val log = EventLog()
    val prefs = Prefs(app)
    val scanner = BleScanner(adapter, log)
    val gatt = GattManager(app, adapter, log)
    val sensor = SensorManager(app, adapter, log, scanner, gatt, prefs, scope)
    val history = RideHistory(app)
    val stats = RideStats()
    val gps = GpsTracker(app)
    val hr = com.rashed.bikesensordoctor.ble.HrSensor(app, adapter, log)
    val coach = com.rashed.bikesensordoctor.core.CoachEngine()

    private val _dash = MutableStateFlow(Dashboard())
    val dash: StateFlow<Dashboard> = _dash
    private val _cue = MutableStateFlow(com.rashed.bikesensordoctor.core.CoachCue.NONE)
    val cue: StateFlow<com.rashed.bikesensordoctor.core.CoachCue> = _cue
    /** Called on each NEW spoken cue so the UI can speak it via TTS. */
    var onSpeak: ((String) -> Unit)? = null

    private val csv = StringBuilder()
    // Per-second power/cadence keyed by timestamp, so GPX trackpoints can be annotated at finish.
    private val sampleByMs = LinkedHashMap<Long, Pair<Int, Int>>()  // t -> (power, cadenceMagnitude)
    private var lastHealth: Health? = null
    private var lastSampleLogged: XdsSample? = null
    private var linkUpSinceMs: Long? = null   // for the connection-uptime / 30-min test
    private var lastKeepaliveMs = 0L

    // HR zone-time accumulators (seconds in each zone) for the post-ride report
    private val hrZoneSec = IntArray(6)
    private val powerZoneSec = IntArray(8)
    private var hrSum = 0L; private var hrCount = 0; private var hrMax = 0

    // ---- P0: link quality + gaps, ride checkpoint ----
    val link = LinkMonitor()
    private var lastDisconnects = 0
    private var lastCheckpointMs = 0L
    private val checkpointFile get() = File(app.filesDir, "ride-checkpoint.txt")
    private val checkpointCsv get() = File(app.filesDir, "ride-checkpoint.csv")
    private val checkpointLink get() = File(app.filesDir, "ride-checkpoint-link.txt")
    private var csvFlushed = 0            // chars of csv already appended to checkpointCsv
    private var restoredRide = false

    // ---- P1: session phases ----
    private var cooldownRequestedAtMs: Long? = null   // riding-time at which COOL DOWN was pressed
    private val plan get() = SessionPlan(warmupSec = prefs.warmupSec)

    fun bluetoothOn() = adapter?.isEnabled == true

    init {
        restoreCheckpoint()
        sensor.addSampleListener { s, t ->
            stats.onSample(s, t)
            if (s.plausible && stats.state != RideStats.State.IDLE) link.onPacket(t, s.cadenceRpm, s.powerW)
            if (stats.state == RideStats.State.RUNNING) {
                csv.append(t).append(',').append(s.powerW).append(',').append(s.leftW).append(',').append(s.rightW).append(',').append(s.cadenceSignedRpm).append(',').append(s.crankAngleDeg).append('\n')
                if (s.plausible) { sampleByMs[t] = s.powerW to s.cadenceRpm; if (sampleByMs.size > 20000) sampleByMs.remove(sampleByMs.keys.first()) }
            }
            lastSampleLogged = s
        }
        scope.launch {
            while (isActive) { refresh(); delay(500) }
        }
    }

    /** Begin keeping the sensor connected (dashboard open) and listening for GPS. Reconnect a remembered HR strap. */
    fun connect() {
        sensor.start(); gps.start()
        val hrAddr = prefs.hrAddress
        if (hrAddr != null && !hr.state.value.connected && !hr.state.value.connecting) hr.connect(hrAddr, prefs.hrName)
        applyCoachConfig()
    }

    fun applyCoachConfig() {
        coach.config = com.rashed.bikesensordoctor.core.CoachConfig(
            mode = runCatching { com.rashed.bikesensordoctor.core.CoachMode.valueOf(prefs.coachMode) }.getOrDefault(com.rashed.bikesensordoctor.core.CoachMode.FREE),
            cadenceEnabled = prefs.cadenceCoaching, cadenceLow = prefs.cadenceLow, cadenceHigh = prefs.cadenceHigh,
            ftpW = prefs.ftpW, maxHr = prefs.maxHr,
        )
    }

    /** P1: the rider asks for the cool-down phase (effort cues stop asking for more). */
    fun requestCooldown() { cooldownRequestedAtMs = stats.elapsedMs(System.currentTimeMillis()); log.add(EventType.TEST, note = "Cool-down requested") }

    // ---------------------------------------------------------------- P0 checkpoint (ride survives app restart)
    private fun writeCheckpoint(now: Long) {
        try {
            checkpointFile.writeText(stats.snapshot(now))
            if (csv.length > csvFlushed) { checkpointCsv.appendText(csv.substring(csvFlushed)); csvFlushed = csv.length }
            checkpointLink.writeText(link.gaps.joinToString("\n") { "${it.startMs},${it.endMs},${it.reason},${it.rotatingBefore},${it.poweredBefore}" })
        } catch (_: Exception) {}
    }
    private fun clearCheckpoint() { checkpointFile.delete(); checkpointCsv.delete(); checkpointLink.delete(); csvFlushed = 0 }
    private fun restoreCheckpoint() {
        try {
            if (!checkpointFile.exists()) return
            val age = System.currentTimeMillis() - checkpointFile.lastModified()
            if (age > 6 * 3600_000L) { clearCheckpoint(); return }           // older than 6 h: not the same ride
            if (!stats.restore(checkpointFile.readText())) { clearCheckpoint(); return }
            if (checkpointCsv.exists()) { csv.setLength(0); csv.append(checkpointCsv.readText()); csvFlushed = csv.length }
            restoredRide = true
            log.add(EventType.TEST, note = "Ride restored from checkpoint (paused): ${fmtDuration(stats.elapsedMs(System.currentTimeMillis()))}, ${stats.sampleCount} samples")
            _dash.value = _dash.value.copy(lastSavedRide = "Ride restored after restart — press RESUME to continue or FINISH to save", restoredRide = true)
            RideService.start(app)
        } catch (_: Exception) { clearCheckpoint() }
    }

    fun connectHr(address: String, name: String?) { prefs.hrAddress = address; prefs.hrName = name; hr.connect(address, name) }
    fun forgetHr() { prefs.hrAddress = null; prefs.hrName = null; hr.disconnect() }

    fun startRide() {
        val now = System.currentTimeMillis()
        if (stats.state == RideStats.State.IDLE || stats.state == RideStats.State.FINISHED) {
            csv.setLength(0); csv.append("timestamp_ms,power_w,left_w,right_w,cadence_signed_rpm,crank_angle_deg\n")
            sampleByMs.clear(); recentPower.clear(); hrZoneSec.fill(0); powerZoneSec.fill(0); coach.reset()
            hrSum = 0; hrCount = 0; hrMax = 0
            link.reset(); cooldownRequestedAtMs = null; clearCheckpoint(); restoredRide = false
        }
        stats.start(now)
        applyCoachConfig()
        gps.start(); gps.setRecording(true)
        log.add(EventType.TEST, note = "Ride started/resumed")
        RideService.start(app)
    }

    fun pauseRide() { stats.pause(System.currentTimeMillis()); gps.setRecording(false); log.add(EventType.TEST, note = "Ride paused"); RideService.update(app) }

    fun finishRide(): String? {
        val now = System.currentTimeMillis()
        if (stats.state == RideStats.State.IDLE) return null
        val startedAt = stats.startedAtMs ?: now
        stats.finish(now)
        link.finish(now)
        gps.setRecording(false)
        val summary = stats.summary(now)
        val saved = if (summary.samples > 0 || summary.durationMs > 10_000) {
            history.save(summary, csv.toString())
            history.saveReport(if (summary.startedAtMs > 0) summary.startedAtMs else startedAt,
                powerZoneSec, hrZoneSec, if (hrCount > 0) (hrSum / hrCount).toInt() else 0, hrMax, link.report(now))
            // GPX if we recorded any track; annotate each point with the nearest power/cadence sample.
            val track = gps.snapshotTrack()
            val rideId = if (summary.startedAtMs > 0) summary.startedAtMs else startedAt
            val gpx = history.saveGpx(rideId, track) { tMs ->
                val near = sampleByMs.entries.minByOrNull { kotlin.math.abs(it.key - tMs) }
                val within = near?.takeIf { kotlin.math.abs(it.key - tMs) <= 3000 }?.value
                Triple(within?.first, within?.second, null)
            }
            "Ride saved: ${fmtDuration(summary.durationMs)}, avg ${summary.avgPowerW} W" + (if (gpx != null) " + GPX" else "")
        } else "Ride discarded (too short)"
        log.add(EventType.TEST, note = "Ride finished: $saved")
        saveLogSnapshot("ride-end")
        stats.reset()
        clearCheckpoint(); restoredRide = false
        RideService.stop(app)
        _dash.value = _dash.value.copy(lastSavedRide = saved, restoredRide = false)
        return saved
    }

    private val recentPower = ArrayDeque<Int>()

    private fun refresh() {
        val now = System.currentTimeMillis()
        val snap = gatt.snapshot.value
        val h = sensor.health.value
        if (h != lastHealth) {
            lastHealth = h
            if (h == Health.LINK_SILENT || h == Health.DECODE_ERROR || h == Health.SENSOR_FAULT || h == Health.RECONNECTING) saveLogSnapshot(h.name.lowercase())
        }
        // connection uptime for the 30-min test: reset whenever we're not live
        val live = h == Health.CONNECTED_LIVE || h == Health.CONNECTED_IDLE
        if (live) { if (linkUpSinceMs == null) linkUpSinceMs = now } else linkUpSinceMs = null
        val uptimeSec = linkUpSinceMs?.let { (now - it) / 1000 } ?: 0L

        // keepalive: a light battery read every 20 s keeps the GATT link active against idle timeouts
        if (live && now - lastKeepaliveMs > 20_000) { lastKeepaliveMs = now; gatt.readRssi() }

        // P0: tag the next gap with the GATT reason of a disconnect we just observed
        if (snap.disconnects != lastDisconnects) { lastDisconnects = snap.disconnects; link.onDisconnect(now, snap.lastDisconnectReason ?: "disconnect") }

        val last = sensor.lastSample.value?.first
        val fresh = stats.livePowerW(now) != null
        val g = gps.state.value
        val bpm = hr.liveBpm(now)
        val hrState = hr.state.value
        val hrZ = com.rashed.bikesensordoctor.core.HrZones.zone(bpm, prefs.maxHr)

        // P1 coaching (≈1 Hz): phase-aware, freshness-aware multi-signal engine. Only while the ride is RUNNING.
        val elapsed = stats.elapsedMs(now)
        val phase = Session.phaseAt(plan, elapsed, cooldownRequestedAtMs)
        if (stats.state == RideStats.State.RUNNING) {
            val sig = stats.signalState(now)
            val xdsFresh = sig == RideStats.SignalState.FRESH || sig == RideStats.SignalState.COASTING
            val c = coach.update(CoachInput(
                nowMs = now, phase = phase,
                cadence = Signal(stats.liveCadenceRpm(now), xdsFresh),
                hr = Signal(bpm, bpm != null),
                power = Signal(stats.livePowerW(now), xdsFresh),
            ))
            if (c.type != com.rashed.bikesensordoctor.core.CueType.NONE) {
                _cue.value = c
                log.add(EventType.TEST, note = "Coach: ${c.type} (${c.reason})")
                if (prefs.coachVoice && c.spoken.isNotEmpty()) onSpeak?.invoke(c.spoken)
            }
        }
        // P0: checkpoint every 10 s while a ride exists
        if (stats.state == RideStats.State.RUNNING || stats.state == RideStats.State.PAUSED) {
            if (now - lastCheckpointMs >= 10_000) { lastCheckpointMs = now; writeCheckpoint(now) }
        }

        // sparkline + zone-time while running
        if (stats.state == RideStats.State.RUNNING) {
            recentPower.addLast(stats.livePowerW(now) ?: 0); while (recentPower.size > 300) recentPower.removeFirst()
            if (hrZ in 1..5) hrZoneSec[hrZ]++
            if (bpm != null && bpm > 0) { hrSum += bpm; hrCount++; if (bpm > hrMax) hrMax = bpm }
            val pz = com.rashed.bikesensordoctor.core.PowerZones.zone(stats.livePowerW(now), prefs.ftpW)
            if (pz in 1..7) powerZoneSec[pz]++
        }

        _dash.value = _dash.value.copy(
            health = h, healthText = com.rashed.bikesensordoctor.core.HealthClassifier.message(h),
            rideState = stats.state,
            powerW = stats.livePowerW(now), power3sW = stats.power3sW(now), power10sW = stats.power10sW(now),
            cadenceRpm = stats.liveCadenceRpm(now),
            backwards = stats.liveBackwards(now), crankAngle = stats.liveCrankAngle(now),
            avgPowerW = stats.avgPowerW, maxPowerW = stats.maxPowerW, avgCadenceRpm = stats.avgCadenceRpm, maxCadenceRpm = stats.maxCadenceRpm,
            energyKj = stats.energyKj(now), elapsedMs = stats.elapsedMs(now),
            batteryPct = snap.batteryPct, rssi = snap.rssi, sensorName = snap.name.ifEmpty { prefs.lastSensorName ?: "" },
            leftW = if (fresh) last?.leftW else null, rightW = if (fresh) last?.rightW else null,
            powerZone = com.rashed.bikesensordoctor.core.PowerZones.zone(stats.livePowerW(now), prefs.ftpW),
            speedKmh = g.speedKmh, distanceKm = g.distanceKm, gpsFix = g.hasFix,
            hrBpm = bpm, hrZone = hrZ, hrConnected = hrState.connected, hrBatteryPct = hrState.batteryPct,
            linkUptimeSec = uptimeSec, recentPower = recentPower.toList(),
            normalizedPowerW = stats.normalizedPowerW, variabilityIndex = stats.variabilityIndex,
            coachMode = prefs.coachMode,
            signal = stats.signalState(now), phase = phase, warmupRemainingSec = Session.warmupRemainingSec(plan, elapsed),
            linkQualityPct = link.qualityPct(now), linkGaps = link.gaps.size, linkLostSec = link.lostMs() / 1000,
            powerVerified = prefs.powerVerified, coachReason = _cue.value.reason, restoredRide = restoredRide,
        )
    }

    /** Writes the event log to app storage; the user can share it from Settings. Keeps the last 30 files. */
    fun saveLogSnapshot(reason: String): File? = try {
        val dir = File(app.filesDir, "logs").apply { mkdirs() }
        val f = File(dir, "log-${SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date())}-$reason.json")
        f.writeText(log.toJson())
        dir.listFiles()?.sortedByDescending { it.lastModified() }?.drop(30)?.forEach { it.delete() }
        f
    } catch (e: Exception) { null }

    fun shareLogs(context: Context) {
        val dir = File(app.filesDir, "logs")
        val files = dir.listFiles()?.sortedByDescending { it.lastModified() }?.take(3) ?: emptyList()
        val fresh = saveLogSnapshot("manual")
        val all = (listOfNotNull(fresh) + files).distinct()
        val uris = ArrayList(all.map { androidx.core.content.FileProvider.getUriForFile(context, context.packageName + ".fileprovider", it) })
        val i = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = "application/json"; putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            putExtra(Intent.EXTRA_SUBJECT, "Bike Computer logs"); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(i, "Send logs").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    companion object {
        fun fmtDuration(ms: Long): String {
            val s = ms / 1000; val h = s / 3600; val m = (s % 3600) / 60; val sec = s % 60
            return if (h > 0) String.format(Locale.US, "%d:%02d:%02d", h, m, sec) else String.format(Locale.US, "%02d:%02d", m, sec)
        }
    }
}
