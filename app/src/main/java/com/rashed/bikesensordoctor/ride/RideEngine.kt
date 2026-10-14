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
import com.rashed.bikesensordoctor.core.ActiveTargets
import com.rashed.bikesensordoctor.core.CoachSetup
import com.rashed.bikesensordoctor.core.RideFeedback
import com.rashed.bikesensordoctor.core.RideSource
import com.rashed.bikesensordoctor.core.RiderProfile
import com.rashed.bikesensordoctor.core.Workout
import com.rashed.bikesensordoctor.core.WorkoutPlan
import com.rashed.bikesensordoctor.core.WorkoutTargets
import com.rashed.bikesensordoctor.core.ZoneConfidence
import com.rashed.bikesensordoctor.core.SeriesPoint
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
    val engineError: String? = null,                                  // last refresh() exception, shown on the dashboard instead of crashing
    // ---- v0.8: rider accounts + workout targets ----
    val riderName: String = "",
    val riderId: String = "",
    val profileCompleted: Boolean = false,
    val workoutName: String = "",
    val plannedSec: Int? = null,
    val targets: ActiveTargets? = null,                               // active bands this second (phase ramps applied); null = zone-based
    val hrGaugeMax: Int = 185,
    val zoneConfidence: String = "GENERIC",
    val inZonePct: Int? = null,                                       // % of MAIN-phase seconds inside the HR (or power) band
    val simulated: Boolean = false,                                   // SIMULATED sensor source active (never a real ride)
    val lastResult: RideResult? = null,                               // set when a ride finishes; the post-ride screen consumes it
    val minuteLine: String = "",                                      // v0.9: last-minute summary under the coach instruction
    val assessment: String = "",                                      // v3: the coach's 60-second assessment (progress toward the objective)
    val assessmentAtMs: Long = 0,
    val maxSpeedKmh: Double = 0.0,
    val elevationGainM: Double = 0.0,
)

/** What a finished ride measured, for the post-ride questions and the next recommendation. */
data class RideResult(val startedAtMs: Long, val durationSec: Int, val km: Double, val avgHr: Int, val inZonePct: Int, val driftPct: Int, val cues: Int, val source: RideSource, val saved: String)

/**
 * App-wide singleton (via BikeApp) that owns the Bluetooth link, the portable RideStats, and persistence.
 * The foreground RideService only keeps the process alive and shows the notification; logic lives here.
 */
class RideEngine(private val app: Application) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val adapter = (app.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
    val log = EventLog()
    val riders = RiderStore(app).also { it.migrateIfNeeded() }
    var rider: Rider? = riders.activeId?.let { riders.load(it) }; private set
    var prefs = Prefs(app, rider?.id ?: RiderStore.LEGACY_ID); private set
    val scanner = BleScanner(adapter, log)
    val gatt = GattManager(app, adapter, log)
    val sensor = SensorManager(app, adapter, log, scanner, gatt, prefs, scope)
    var history = RideHistory(riders.ridesDir(rider?.id ?: RiderStore.LEGACY_ID)); private set
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

    private val recentPower = ArrayDeque<Int>()
    @Volatile var lastEngineError: String? = null; private set

    // ---- v0.8: profile-driven workout ----
    var setup: CoachSetup? = null; private set
    var workout: Workout? = null; private set
    private var plan = SessionPlan()
    private var workoutPlan: WorkoutPlan? = null
    private var inZoneSec = 0; private var mainSec = 0
    private val hrFirstHalf = ArrayList<Int>(); private val hrSecondHalf = ArrayList<Int>()
    private var cueCount = 0
    private var rideSource = RideSource.DEVICE
    // ---- v0.9: 1 Hz series for the Ride Results page; written to the checkpoint every 10 s ----
    private val series = ArrayList<SeriesPoint>()
    private var seriesFlushed = 0
    private val checkpointSeries get() = File(app.filesDir, "ride-checkpoint-series.csv")
    private var simSpeedKmh: Double? = null; private var simDistKm = 0.0; private var simAlt = 10.0; private var simGain = 0.0; private var simMaxSpeed = 0.0
    internal fun simMotion(speedKmh: Double?, climbM: Double) { simSpeedKmh = speedKmh; if (stats.state == RideStats.State.RUNNING && speedKmh != null) { simDistKm += speedKmh / 3600.0; simMaxSpeed = maxOf(simMaxSpeed, speedKmh); if (climbM > 0) simGain += climbM; simAlt += climbM } }
    private var hrAtFinish: Int? = null

    // ---- clock (the simulator can run it faster than real time) ----
    @Volatile var clockOffsetMs = 0L
    @Volatile var clockSpeed = 1
    private var clockAnchorReal = System.currentTimeMillis()
    private var clockAnchorVirtual = clockAnchorReal
    /** Engine time: real time, or accelerated virtual time while a simulation runs. */
    fun now(): Long = if (clockSpeed == 1) System.currentTimeMillis() + clockOffsetMs else clockAnchorVirtual + (System.currentTimeMillis() - clockAnchorReal) * clockSpeed
    fun accelerateClock(speed: Int) { val v = now(); clockAnchorReal = System.currentTimeMillis(); clockAnchorVirtual = v; clockSpeed = speed.coerceIn(1, 60); clockOffsetMs = if (clockSpeed == 1) v - clockAnchorReal else 0 }
    var simulator: RideSimulator? = null; private set

    fun bluetoothOn() = adapter?.isEnabled == true
    fun hasBluetooth() = adapter != null

    // ---------------------------------------------------------------- v0.8 rider accounts
    private fun loadRiderState() {
        val r = rider
        prefs = Prefs(app, r?.id ?: RiderStore.LEGACY_ID)
        history = RideHistory(riders.ridesDir(r?.id ?: RiderStore.LEGACY_ID))
        setup = r?.takeIf { it.completed }?.let { RiderProfile.deriveSetup(it.answers) }
        workout = setup?.let { s -> recommendFor(r!!, s) }
        setup?.let { s ->
            prefs.ftpW = s.ftp; prefs.maxHr = s.maxHrEstimate; prefs.cadenceLow = s.cadLow; prefs.cadenceHigh = s.cadHigh; prefs.warmupSec = s.warmupSec
            prefs.cadenceCoaching = s.cadenceEnabled; prefs.coachVoice = s.voice
            prefs.ftpSetByUser = s.ftpKnown; prefs.maxHrSetByUser = s.zoneConfidence != ZoneConfidence.GENERIC
            if (prefs.coachMode == "FREE") prefs.coachMode = "ZONE2"     // a rider with a profile is coached by default; Free ride can still be picked per ride
        }
        applyCoachConfig()
        _dash.value = _dash.value.copy(riderName = r?.name ?: "", riderId = r?.id ?: "", profileCompleted = r?.completed == true, zoneConfidence = setup?.zoneConfidence?.name ?: "GENERIC",
            hrGaugeMax = setup?.maxHrEstimate ?: prefs.maxHr, workoutName = workout?.name ?: "")
        val hrAddr = prefs.hrAddress
        if (hrAddr != null && hrAddr != hr.state.value.address) { hr.disconnect(); hr.connect(hrAddr, prefs.hrName) }
        else if (hrAddr == null && hr.state.value.connected) hr.disconnect()
    }

    private fun recommendFor(r: Rider, s: CoachSetup): Workout {
        val cal = java.util.Calendar.getInstance(); val today = (cal.get(java.util.Calendar.DAY_OF_WEEK) + 5) % 7
        return RiderProfile.recommend(r.answers, s, r.feedback, today)
    }

    /** Switch the active rider. Refused while a ride is running or paused, so a ride can never change owner. */
    fun switchRider(id: String): Boolean {
        if (stats.state == RideStats.State.RUNNING || stats.state == RideStats.State.PAUSED) return false
        val r = riders.load(id) ?: return false
        riders.activeId = id; rider = r
        log.add(EventType.INFO, note = "Rider switched to ${r.name} (${r.id})")
        loadRiderState()
        return true
    }
    fun signOut(): Boolean { if (stats.state == RideStats.State.RUNNING || stats.state == RideStats.State.PAUSED) return false; riders.activeId = null; rider = null; loadRiderState(); return true }
    fun createRider(name: String, pin: String?): Rider { val r = riders.create(name, pin); switchRider(r.id); return r }
    /** Persist edits to the active rider's profile and re-derive the coach. */
    fun saveRider() { rider?.let { riders.save(it) }; loadRiderState() }

    /** v3 learning: facts the coach has gathered from this rider's device rides (never from simulated ones). */
    fun learned(): com.rashed.bikesensordoctor.core.Calibration.Learned {
        val r = rider ?: return com.rashed.bikesensordoctor.core.Calibration.learn(emptyList(), emptyList(), emptyList(), emptyList(), emptyList(), emptyList())
        val rides = history.list().filter { it.source == RideSource.DEVICE && it.durationMs > 600_000 }.sortedBy { it.startedAtMs }
        val metas = rides.map { history.readMeta(it.startedAtMs) }
        return com.rashed.bikesensordoctor.core.Calibration.learn(
            rides.map { it.avgCadenceRpm }.filter { it > 40 }, metas.mapNotNull { it["best20"] as? Int }, rides.map { it.avgHr }.filter { it > 60 },
            rides.map { (it.durationMs / 60_000).toInt() }, r.feedback.map { it.inZonePct }, metas.mapNotNull { it["hrRecovery60"] as? Int }.zip(metas.mapNotNull { it["hrAtFinish"] as? Int }).map { (a, b) -> b - a })
    }
    /** Evidence lists for FTP / threshold calibration (verified device rides only). */
    fun ftpEvidence(): List<Int> = history.list().filter { it.source == RideSource.DEVICE }.sortedBy { it.startedAtMs }.mapNotNull { history.readMeta(it.startedAtMs)["best20"] as? Int }
    fun testEvidence(): List<Int> = history.list().filter { it.source == RideSource.DEVICE }.sortedBy { it.startedAtMs }.mapNotNull { history.readMeta(it.startedAtMs)["testHr"] as? Int }
    fun chooseWorkout(w: Workout?) { workout = w ?: setup?.let { s -> rider?.let { recommendFor(it, s) } }; _dash.value = _dash.value.copy(workoutName = workout?.name ?: "") }
    fun refreshRecommendation() { workout = setup?.let { s -> rider?.let { recommendFor(it, s) } }; _dash.value = _dash.value.copy(workoutName = workout?.name ?: "") }

    /** Record the rider's post-ride answers under the active account. */
    fun recordFeedback(fb: RideFeedback, followUpKey: String?, followUpValue: String?) {
        val r = rider ?: return
        r.feedback += fb
        if (followUpKey != null) {
            r.asked += followUpKey
            if (followUpValue != null) when (followUpKey) {
                "restHr" -> followUpValue.toIntOrNull()?.let { r.answers.setMetric("restHr", it, "estimated") }
                else -> r.answers[followUpKey] = followUpValue
            }
        }
        // learning: after three real rides the median cadence becomes the rider's natural cadence unless they entered one
        runCatching { val l = learned(); if (l.rides >= 3 && l.naturalCadence != null && r.answers.metric("cadence") == null) r.answers["learned.cadence"] = l.naturalCadence.toString() }
        riders.save(r); loadRiderState()   // the post-ride screen clears lastResult itself when the rider leaves it
    }
    fun clearResult() { _dash.value = _dash.value.copy(lastResult = null) }

    // ---------------------------------------------------------------- v0.8 simulation (SIMULATED sensor source; never a real ride)
    fun startSimulation(speed: Int, profile: RideSimulator.Profile) {
        if (stats.state != RideStats.State.IDLE && stats.state != RideStats.State.FINISHED) return
        simulator?.stop()
        accelerateClock(speed)
        simulator = RideSimulator(this, profile).also { it.start() }
        rideSource = RideSource.SIMULATED
        log.add(EventType.TEST, note = "SIMULATION started at ${speed}× (${profile.name})")
        _dash.value = _dash.value.copy(simulated = true)
    }
    fun stopSimulation() {
        simulator?.stop(); simulator = null
        if (stats.state == RideStats.State.IDLE || stats.state == RideStats.State.FINISHED) rideSource = RideSource.DEVICE
        accelerateClock(1); clockOffsetMs = 0
        _dash.value = _dash.value.copy(simulated = false)
    }
    /** The simulator feeds samples through the same path as the real sensor. */
    internal fun injectSample(s: XdsSample, t: Long) = sensor.inject(s, t)
    internal var simulatedHr: Int? = null

    init {
        plan = SessionPlan(warmupSec = prefs.warmupSec)
        loadRiderState()
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
            delay(300)   // never run the first refresh synchronously inside the constructor
            while (isActive) {
                try { refresh() } catch (e: Throwable) {
                    // A bug in one refresh must never kill the app: record it, show it, keep going.
                    val msg = "${e.javaClass.simpleName}: ${e.message}\n" + e.stackTrace.take(6).joinToString("\n") { "  at $it" }
                    if (lastEngineError == null) { log.add(EventType.ERROR, note = "refresh() failed: $msg"); lastEngineError = msg }
                    runCatching { _dash.value = _dash.value.copy(engineError = msg) }
                }
                delay((500 / clockSpeed).toLong().coerceAtLeast(50))
            }
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
        val s = setup
        val prefMode = runCatching { com.rashed.bikesensordoctor.core.CoachMode.valueOf(prefs.coachMode) }.getOrDefault(com.rashed.bikesensordoctor.core.CoachMode.FREE)
        coach.config = if (s != null && workoutPlan != null) com.rashed.bikesensordoctor.core.CoachConfig(
            // profile-driven workout: absolute bands come per tick via CoachInput.targets
            mode = if (prefMode == com.rashed.bikesensordoctor.core.CoachMode.FREE) com.rashed.bikesensordoctor.core.CoachMode.FREE else com.rashed.bikesensordoctor.core.CoachMode.ZONE2,
            cadenceEnabled = s.cadenceEnabled, cadenceLow = s.cadLow, cadenceHigh = s.cadHigh,
            ftpW = s.ftp, maxHr = s.maxHrEstimate, powerCoaching = s.powerCoaching && prefs.powerVerified,
            graceMs = 90_000, backoff = true,
        ).withFrequency(s.frequency).copy(sameRepeatMs = s.sameRepeatMs, keepRepeatMs = s.keepRepeatMs) else com.rashed.bikesensordoctor.core.CoachConfig(
            mode = prefMode,
            cadenceEnabled = prefs.cadenceCoaching, cadenceLow = prefs.cadenceLow, cadenceHigh = prefs.cadenceHigh,
            ftpW = prefs.ftpW, maxHr = prefs.maxHr,
        )
    }

    /** P1: the rider asks for the cool-down phase (effort cues stop asking for more). */
    fun requestCooldown() { cooldownRequestedAtMs = stats.elapsedMs(now()); log.add(EventType.TEST, note = "Cool-down requested") }

    // ---------------------------------------------------------------- P0 checkpoint (ride survives app restart)
    private fun writeCheckpoint(now: Long) {
        try {
            checkpointFile.writeText(stats.snapshot(now))
            if (csv.length > csvFlushed) { checkpointCsv.appendText(csv.substring(csvFlushed)); csvFlushed = csv.length }
            checkpointLink.writeText(link.gaps.joinToString("\n") { "${it.startMs},${it.endMs},${it.reason},${it.rotatingBefore},${it.poweredBefore}" })
            if (series.size > seriesFlushed) { checkpointSeries.appendText(series.subList(seriesFlushed, series.size).joinToString("\n", postfix = "\n") { it.csv() }); seriesFlushed = series.size }
        } catch (_: Exception) {}
    }
    private fun clearCheckpoint() { checkpointFile.delete(); checkpointCsv.delete(); checkpointLink.delete(); checkpointSeries.delete(); csvFlushed = 0; seriesFlushed = 0 }
    private fun restoreCheckpoint() {
        try {
            if (!checkpointFile.exists()) return
            val age = System.currentTimeMillis() - checkpointFile.lastModified()
            if (age > 6 * 3600_000L) { clearCheckpoint(); return }           // older than 6 h: not the same ride
            if (!stats.restore(checkpointFile.readText())) { clearCheckpoint(); return }
            if (checkpointCsv.exists()) { csv.setLength(0); csv.append(checkpointCsv.readText()); csvFlushed = csv.length }
            if (checkpointSeries.exists()) { series.clear(); checkpointSeries.useLines { l -> l.mapNotNullTo(series) { SeriesPoint.parse(it) } }; seriesFlushed = series.size }
            restoredRide = true
            log.add(EventType.TEST, note = "Ride restored from checkpoint (paused): ${fmtDuration(stats.elapsedMs(System.currentTimeMillis()))}, ${stats.sampleCount} samples")
            _dash.value = _dash.value.copy(lastSavedRide = "Ride restored after restart — press RESUME to continue or FINISH to save", restoredRide = true)
            // the foreground service is started by onForeground() once a screen is visible (Android 12 rule)
        } catch (_: Exception) { clearCheckpoint() }
    }

    /** Called by MainActivity.onResume: a restored/active ride needs its foreground service, which Android only lets us start now. */
    fun onForeground() {
        if (stats.state == RideStats.State.RUNNING || stats.state == RideStats.State.PAUSED) RideService.start(app)
    }

    fun connectHr(address: String, name: String?) { prefs.hrAddress = address; prefs.hrName = name; hr.connect(address, name) }
    fun forgetHr() { prefs.hrAddress = null; prefs.hrName = null; hr.disconnect() }

    fun startRide() {
        val now = now()
        if (stats.state == RideStats.State.IDLE || stats.state == RideStats.State.FINISHED) {
            csv.setLength(0); csv.append("timestamp_ms,power_w,left_w,right_w,cadence_signed_rpm,crank_angle_deg\n")
            sampleByMs.clear(); recentPower.clear(); hrZoneSec.fill(0); powerZoneSec.fill(0); coach.reset()
            hrSum = 0; hrCount = 0; hrMax = 0; inZoneSec = 0; mainSec = 0; hrFirstHalf.clear(); hrSecondHalf.clear(); cueCount = 0
            series.clear(); seriesFlushed = 0; simDistKm = 0.0; simGain = 0.0; simMaxSpeed = 0.0; hrAtFinish = null; lastZoneSec = -1
            link.reset(); cooldownRequestedAtMs = null; clearCheckpoint(); restoredRide = false
            if (simulator == null) rideSource = RideSource.DEVICE
            // v0.8: the recommended workout sets the session plan and the target bands; without a profile the old settings apply
            val s = setup; val w = workout
            if (s != null && w != null) {
                workoutPlan = WorkoutPlan(w.hrLo, w.hrHi, if (s.powerCoaching && prefs.powerVerified) w.pwLo else null, if (s.powerCoaching && prefs.powerVerified) w.pwHi else null,
                    s.cadLow, s.cadHigh, s.ftp, s.warmupSec, s.cooldownSec, plannedSec = w.minutes * 60)
                plan = SessionPlan(warmupSec = s.warmupSec, cooldownSec = s.cooldownSec, plannedSec = w.minutes * 60)
                if (prefs.coachMode == "FREE") prefs.coachMode = "ZONE2"
            } else { workoutPlan = null; plan = SessionPlan(warmupSec = prefs.warmupSec) }
            _cue.value = com.rashed.bikesensordoctor.core.CoachCue.NONE
            _dash.value = _dash.value.copy(lastResult = null, plannedSec = plan.plannedSec, workoutName = w?.name ?: "")
        }
        if (stats.state == RideStats.State.IDLE || stats.state == RideStats.State.FINISHED) simulator?.restart()
        stats.start(now)
        applyCoachConfig()
        gps.start(); gps.setRecording(true)
        log.add(EventType.TEST, note = "Ride started/resumed")
        RideService.start(app)
    }

    fun pauseRide() { stats.pause(now()); gps.setRecording(false); log.add(EventType.TEST, note = "Ride paused"); RideService.update(app) }

    fun finishRide(): String? {
        val now = now()
        if (stats.state == RideStats.State.IDLE) return null
        val startedAt = stats.startedAtMs ?: now
        stats.finish(now)
        link.finish(now)
        gps.setRecording(false)
        val g = gps.state.value
        val avgHrAll = if (hrCount > 0) (hrSum / hrCount).toInt() else 0
        val inZone = if (workoutPlan != null && mainSec > 0) (inZoneSec * 100 / mainSec) else -1
        val distKm = if (simulator != null) simDistKm else g.distanceKm
        val elevM = if (simulator != null) simGain else g.elevationGainM
        val summary = stats.summary(now).copy(distanceKm = distKm, elevationGainM = elevM, avgHr = avgHrAll, inZonePct = inZone, source = rideSource, riderId = rider?.id ?: "")
        val saved = if (summary.samples > 0 || summary.durationMs > 10_000) {
            history.save(summary, csv.toString())
            history.saveReport(if (summary.startedAtMs > 0) summary.startedAtMs else startedAt,
                powerZoneSec, hrZoneSec, if (hrCount > 0) (hrSum / hrCount).toInt() else 0, hrMax, link.report(now))
            // v0.9: the 1 Hz series and the context the Ride Results page needs
            val rid = if (summary.startedAtMs > 0) summary.startedAtMs else startedAt
            runCatching { history.saveSeries(rid, series) }
            val wp = workoutPlan; val s = setup
            // calibration evidence from THIS ride: best 20-min power (verified meter only) and the guided test block (last 20 min of MAIN)
            val trusted = prefs.powerVerified && rideSource == RideSource.DEVICE
            var best20: Int? = null
            if (trusted) { var sum = 0.0; var best = 0.0; val win = ArrayDeque<Int>(); series.forEach { p -> val w = p.powerW ?: 0; win.addLast(w); sum += w; if (win.size > 1200) sum -= win.removeFirst(); if (win.size == 1200 && sum / 1200 > best) best = sum / 1200 }; if (best > 60) best20 = Math.round(best).toInt() }
            val mainPts = series.filter { it.phase == Phase.MAIN }
            val testBlock = if (workout?.kind == "test" && mainPts.size >= 1200) mainPts.takeLast(1200) else null
            val testHr = testBlock?.mapNotNull { it.hr }?.takeIf { it.size >= 1000 }?.average()?.let { Math.round(it).toInt() }
            val testPw = if (trusted) testBlock?.mapNotNull { it.powerW }?.takeIf { it.size >= 1000 }?.average()?.let { Math.round(it).toInt() } else null
            runCatching { history.updateMeta(rid, mapOf("best20" to best20, "testHr" to testHr, "testPw" to testPw, "workoutKind" to (workout?.kind ?: ""),
                "workout" to (workout?.name ?: ""), "bandLo" to wp?.hrLo, "bandHi" to wp?.hrHi, "pwLo" to wp?.pwLo, "pwHi" to wp?.pwHi,
                "ftpUsed" to (s?.ftp ?: prefs.ftpW), "powerTrusted" to (prefs.powerVerified && rideSource == RideSource.DEVICE), "source" to rideSource.name,
                "zoneConf" to (s?.zoneConfidenceText ?: "GENERIC"), "edges" to (s?.hrZoneEdges?.joinToString(",") ?: ""), "maxHrEst" to (s?.maxHrEstimate ?: prefs.maxHr),
                "weightKg" to rider?.answers?.int("weightKg"), "age" to rider?.answers?.int("age"), "appleRef" to (rider?.answers?.get("apple") == "yes"),
                "riderName" to (rider?.name ?: ""), "cues" to cueCount, "maxSpeed" to (if (simulator != null) simMaxSpeed else g.maxSpeedKmh))) }
            // HR recovery: if the strap keeps reporting, note the heart rate 60 s after the finish
            val lastHr = series.lastOrNull { it.hr != null }?.hr
            if (lastHr != null && simulator == null) { hrAtFinish = lastHr; scope.launch { delay(60_000); val r60 = hr.liveBpm(System.currentTimeMillis()); if (r60 != null) runCatching { history.updateMeta(rid, mapOf("hrRecovery60" to r60, "hrAtFinish" to lastHr)) } } }
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
        val drift = if (hrFirstHalf.size > 60 && hrSecondHalf.size > 60) Math.round((hrSecondHalf.average() / hrFirstHalf.average() - 1) * 100).toInt() else 0
        val result = RideResult(if (summary.startedAtMs > 0) summary.startedAtMs else startedAt, (summary.durationMs / 1000).toInt(), g.distanceKm, avgHrAll,
            if (inZone < 0) 0 else inZone, drift, cueCount, rideSource, saved)
        stats.reset()
        clearCheckpoint(); restoredRide = false
        workoutPlan = null
        RideService.stop(app)
        if (simulator != null) stopSimulation()
        _cue.value = com.rashed.bikesensordoctor.core.CoachCue.NONE
        _dash.value = _dash.value.copy(lastSavedRide = saved, restoredRide = false, lastResult = if (summary.durationMs > 10_000) result else null, targets = null, inZonePct = null, plannedSec = null, minuteLine = "")
        return saved
    }

    private fun refresh() {
        val now = now()
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
        val bpm = simulatedHr ?: hr.liveBpm(System.currentTimeMillis())
        val hrState = hr.state.value
        val hrZ = com.rashed.bikesensordoctor.core.HrZones.zone(bpm, prefs.maxHr)

        // P1 coaching (≈1 Hz): phase-aware, freshness-aware multi-signal engine. Only while the ride is RUNNING.
        val elapsed = stats.elapsedMs(now)
        val phase = Session.phaseAt(plan, elapsed, cooldownRequestedAtMs)
        val wp = workoutPlan
        val targets = wp?.let { WorkoutTargets.forPhase(it, phase, (elapsed / 1000).toInt(), Session.cooldownStartMs(plan, cooldownRequestedAtMs)?.let { ms -> (ms / 1000).toInt() }) }
        if (stats.state == RideStats.State.RUNNING) {
            val sig = stats.signalState(now)
            val xdsFresh = sig == RideStats.SignalState.FRESH || sig == RideStats.SignalState.COASTING
            val c = coach.update(CoachInput(
                nowMs = now, phase = phase,
                cadence = Signal(stats.liveCadenceRpm(now), xdsFresh),
                hr = Signal(bpm, bpm != null),
                power = Signal(stats.livePowerW(now), xdsFresh),
                targets = targets, speedKmh = if (simulator != null) simSpeedKmh else g.speedKmh,
            ))
            if (c.type != com.rashed.bikesensordoctor.core.CueType.NONE) {
                _cue.value = c
                cueCount++
                log.add(EventType.TEST, note = "Coach: ${c.type} (${c.reason})")
                if (prefs.coachVoice && c.spoken.isNotEmpty()) onSpeak?.invoke(c.spoken)
            }
            // v0.8/0.9: once per second of riding time — in-band accounting, HR drift halves, the 1 Hz series, the minute line
            if (elapsed / 1000 != lastZoneSec) {
                lastZoneSec = elapsed / 1000
                val pw = stats.livePowerW(now)
                var inBand: Boolean? = null
                if (targets != null && phase == Phase.MAIN) {
                    mainSec++
                    inBand = when {
                        bpm != null -> bpm in targets.hrLo..targets.hrHi
                        pw != null && pw > 0 && targets.pwLo != null && targets.pwHi != null -> pw in targets.pwLo..targets.pwHi
                        else -> false
                    }
                    if (inBand) inZoneSec++
                    if (bpm != null) { val half = ((plan.plannedSec ?: 3600) - plan.warmupSec - plan.cooldownSec) / 2; if (mainSec <= half) hrFirstHalf += bpm else hrSecondHalf += bpm }
                }
                val sim = simulator != null
                if (series.size < 8 * 3600) series += SeriesPoint(lastZoneSec.toInt(), bpm, pw, stats.liveCadenceRpm(now), if (sim) simSpeedKmh else g.speedKmh, if (sim) simAlt else g.altM,
                    if (sim) simDistKm else g.distanceKm, if (sim) null else g.lat, if (sim) null else g.lon, phase, inBand)
                if (lastZoneSec > 0 && lastZoneSec % 60 == 0L) {
                    val last = series.takeLast(60)
                    val h = last.mapNotNull { it.hr }; val p = last.mapNotNull { it.powerW }.filter { it > 0 }; val c = last.mapNotNull { it.cadRpm }.filter { it > 0 }
                    val parts = ArrayList<String>()
                    if (h.isNotEmpty()) parts += "HR ${h.average().toInt()} avg" + (targets?.let { t -> if (h.average() > t.hrHi) " (above band)" else if (h.average() < t.hrLo) " (below band)" else " (in band)" } ?: "")
                    if (c.isNotEmpty()) parts += "${c.average().toInt()} rpm"
                    if (p.isNotEmpty()) parts += "${p.average().toInt()} W"
                    val inb = last.count { it.inBand == true }
                    if (targets != null && phase == Phase.MAIN) parts += "${inb * 100 / 60}% in band"
                    _dash.value = _dash.value.copy(minuteLine = if (parts.isEmpty()) "" else "Last minute: " + parts.joinToString(" · "))
                }
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
            speedKmh = if (simulator != null) simSpeedKmh else g.speedKmh, distanceKm = if (simulator != null) simDistKm else g.distanceKm, gpsFix = g.hasFix || simulator != null,
            maxSpeedKmh = if (simulator != null) simMaxSpeed else g.maxSpeedKmh, elevationGainM = if (simulator != null) simGain else g.elevationGainM,
            hrBpm = bpm, hrZone = hrZ, hrConnected = hrState.connected, hrBatteryPct = hrState.batteryPct,
            linkUptimeSec = uptimeSec, recentPower = recentPower.toList(),
            normalizedPowerW = stats.normalizedPowerW, variabilityIndex = stats.variabilityIndex,
            coachMode = prefs.coachMode,
            signal = stats.signalState(now), phase = phase, warmupRemainingSec = Session.warmupRemainingSec(plan, elapsed),
            linkQualityPct = link.qualityPct(now), linkGaps = link.gaps.size, linkLostSec = link.lostMs() / 1000,
            powerVerified = prefs.powerVerified, coachReason = _cue.value.reason, restoredRide = restoredRide,
            targets = if (stats.state == RideStats.State.IDLE) null else targets, inZonePct = if (mainSec > 0) inZoneSec * 100 / mainSec else null,
            assessment = coach.lastAssessment?.let { "${it.progress} · ${it.summary}" } ?: "", assessmentAtMs = coach.lastAssessment?.atMs ?: 0,
            plannedSec = if (stats.state == RideStats.State.IDLE) null else plan.plannedSec,
        )
    }
    private var lastZoneSec = -1L

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
