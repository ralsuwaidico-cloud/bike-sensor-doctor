package com.rashed.bikesensordoctor.ride

import android.app.Application
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import android.os.Build
import com.rashed.bikesensordoctor.ble.BleScanner
import com.rashed.bikesensordoctor.ble.GattManager
import com.rashed.bikesensordoctor.core.Health
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
    val lastSavedRide: String? = null,
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

    private val _dash = MutableStateFlow(Dashboard())
    val dash: StateFlow<Dashboard> = _dash

    private val csv = StringBuilder()
    private var lastHealth: Health? = null
    private var lastSampleLogged: XdsSample? = null

    fun bluetoothOn() = adapter?.isEnabled == true

    init {
        sensor.addSampleListener { s, t ->
            stats.onSample(s, t)
            if (stats.state == RideStats.State.RUNNING) csv.append(t).append(',').append(s.powerW).append(',').append(s.leftW).append(',').append(s.rightW).append(',').append(s.cadenceSignedRpm).append(',').append(s.crankAngleDeg).append('\n')
            lastSampleLogged = s
        }
        scope.launch {
            while (isActive) { refresh(); delay(500) }
        }
    }

    /** Begin keeping the sensor connected (dashboard open). */
    fun connect() = sensor.start()

    fun startRide() {
        val now = System.currentTimeMillis()
        if (stats.state == RideStats.State.IDLE || stats.state == RideStats.State.FINISHED) {
            csv.setLength(0); csv.append("timestamp_ms,power_w,left_w,right_w,cadence_signed_rpm,crank_angle_deg\n")
        }
        stats.start(now)
        log.add(EventType.TEST, note = "Ride started/resumed")
        RideService.start(app)
    }

    fun pauseRide() { stats.pause(System.currentTimeMillis()); log.add(EventType.TEST, note = "Ride paused"); RideService.update(app) }

    fun finishRide(): String? {
        val now = System.currentTimeMillis()
        if (stats.state == RideStats.State.IDLE) return null
        stats.finish(now)
        val summary = stats.summary(now)
        val saved = if (summary.samples > 0 || summary.durationMs > 10_000) {
            history.save(summary, csv.toString()); "Ride saved: ${fmtDuration(summary.durationMs)}, avg ${summary.avgPowerW} W"
        } else "Ride discarded (too short)"
        log.add(EventType.TEST, note = "Ride finished: $saved")
        saveLogSnapshot("ride-end")
        stats.reset()
        RideService.stop(app)
        _dash.value = _dash.value.copy(lastSavedRide = saved)
        return saved
    }

    private fun refresh() {
        val now = System.currentTimeMillis()
        val snap = gatt.snapshot.value
        val h = sensor.health.value
        if (h != lastHealth) {
            lastHealth = h
            // Save a technical log automatically whenever a problem state appears
            if (h == Health.LINK_SILENT || h == Health.DECODE_ERROR || h == Health.SENSOR_FAULT || h == Health.RECONNECTING) saveLogSnapshot(h.name.lowercase())
        }
        val last = sensor.lastSample.value?.first
        val fresh = stats.livePowerW(now) != null
        _dash.value = _dash.value.copy(
            health = h, healthText = com.rashed.bikesensordoctor.core.HealthClassifier.message(h),
            rideState = stats.state,
            powerW = stats.livePowerW(now), power3sW = stats.power3sW(now), cadenceRpm = stats.liveCadenceRpm(now),
            backwards = stats.liveBackwards(now), crankAngle = stats.liveCrankAngle(now),
            avgPowerW = stats.avgPowerW, maxPowerW = stats.maxPowerW, avgCadenceRpm = stats.avgCadenceRpm, maxCadenceRpm = stats.maxCadenceRpm,
            energyKj = stats.energyKj(now), elapsedMs = stats.elapsedMs(now),
            batteryPct = snap.batteryPct, rssi = snap.rssi, sensorName = snap.name.ifEmpty { prefs.lastSensorName ?: "" },
            leftW = if (fresh) last?.leftW else null, rightW = if (fresh) last?.rightW else null,
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
