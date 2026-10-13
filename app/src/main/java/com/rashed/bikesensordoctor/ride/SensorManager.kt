package com.rashed.bikesensordoctor.ride

import android.bluetooth.BluetoothAdapter
import android.content.Context
import com.rashed.bikesensordoctor.ble.BleScanner
import com.rashed.bikesensordoctor.ble.ConnectionState
import com.rashed.bikesensordoctor.ble.GattManager
import com.rashed.bikesensordoctor.core.Health
import com.rashed.bikesensordoctor.core.HealthClassifier
import com.rashed.bikesensordoctor.core.XdsSample
import com.rashed.bikesensordoctor.log.EventLog
import com.rashed.bikesensordoctor.log.EventType
import com.rashed.bikesensordoctor.ui.Permissions
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Autonomous link to the power meter. Remembers the last sensor, finds it by scan, connects, and when the link
 * drops lets GattManager's backoff reconnect run; if that gives up or the sensor went to sleep, falls back to
 * scanning again. Also watches for a "silent link" (connected but no packets for 6 s) and cycles the connection —
 * a documented, reversible recovery action. Never writes to the sensor.
 */
class SensorManager(
    private val context: Context,
    private val adapter: BluetoothAdapter?,
    val log: EventLog,
    val scanner: BleScanner,
    val gatt: GattManager,
    private val prefs: Prefs,
    private val scope: CoroutineScope,
) {
    private val _health = MutableStateFlow(Health.SEARCHING)
    val health: StateFlow<Health> = _health

    private val _lastSample = MutableStateFlow<Pair<XdsSample, Long>?>(null)
    val lastSample: StateFlow<Pair<XdsSample, Long>?> = _lastSample

    private var supervisor: Job? = null
    private var wanted = false
    private var silentCycles = 0
    private var lastRecoveryMs = 0L
    private val listeners = ArrayList<(XdsSample, Long) -> Unit>()

    fun addSampleListener(l: (XdsSample, Long) -> Unit) { listeners += l }
    fun removeSampleListener(l: (XdsSample, Long) -> Unit) { listeners -= l }

    init {
        gatt.onXdsSample = { s, t -> dispatch(s, t) }
    }

    private fun dispatch(s: XdsSample, t: Long) {
        _lastSample.value = s to t
        listeners.forEach { it(s, t) }
    }

    /** SIMULATED source (RideSimulator): feeds a sample through exactly the same path as a real XDS packet. */
    fun inject(s: XdsSample, t: Long) = dispatch(s, t)

    /** Keep the sensor connected until [stop]. Safe to call repeatedly. */
    fun start() {
        if (wanted) return
        wanted = true
        log.add(EventType.INFO, note = "SensorManager: start (last sensor ${prefs.lastSensorAddress ?: "none"})")
        supervisor = scope.launch { supervise() }
    }

    fun stop() {
        wanted = false
        supervisor?.cancel(); supervisor = null
        scanner.stop(); gatt.disconnect(silent = true)
        _health.value = Health.SEARCHING
        log.add(EventType.INFO, note = "SensorManager: stop")
    }

    /** User-visible "Reconnect now": a full cycle, which is the documented safe recovery action. */
    fun recoverNow() {
        log.add(EventType.CONNECTION, note = "User requested reconnect")
        scanner.stop(); gatt.disconnect(silent = true)
    }

    private suspend fun supervise() {
        while (scope.isActive && wanted) {
            val snap = gatt.snapshot.value
            val now = System.currentTimeMillis()
            val permission = Permissions.allGranted(context)
            val btOn = adapter?.isEnabled == true
            val linkUp = snap.state == ConnectionState.READY
            val recovering = snap.state == ConnectionState.CONNECTING || snap.state == ConnectionState.DISCOVERING ||
                snap.state == ConnectionState.RECONNECT_WAIT || snap.state == ConnectionState.CONNECTED
            val age = snap.lastPacketMs?.let { now - it }
            val last = _lastSample.value?.first

            _health.value = HealthClassifier.classify(btOn, permission, linkUp, recovering, if (linkUp) age else null, last, snap.rejectedPackets)

            if (permission && btOn) {
                when {
                    linkUp && age != null && age > HealthClassifier.SILENT_MS && now - lastRecoveryMs > 15_000 -> {
                        // Connected but silent for 6 s: cycle the link (safe, reversible). After 3 cycles, back off to scanning.
                        silentCycles++; lastRecoveryMs = now
                        log.add(EventType.CONNECTION, device = snap.address, note = "Silent link (${age} ms without packets) — recovery cycle $silentCycles")
                        gatt.disconnect(silent = true)
                        delay(1500)
                        if (silentCycles <= 3) gatt.connect(snap.address, snap.name, reconnect = true) else { silentCycles = 0 }
                    }
                    linkUp -> silentCycles = 0
                    !recovering && snap.state == ConnectionState.DISCONNECTED -> acquire()
                }
            }
            delay(1000)
        }
    }

    /** Find the sensor (known address first, then any XDS-like device) and connect with auto-reconnect on. */
    private suspend fun acquire() {
        val known = prefs.lastSensorAddress
        if (known != null) {
            // Direct connect to the remembered address first; Android can connect without a scan if the device is advertising.
            log.add(EventType.CONNECTION, device = known, note = "Connecting to remembered sensor")
            gatt.connect(known, prefs.lastSensorName, reconnect = true)
            val ok = waitReady(25_000)
            if (ok) { onConnected(known, prefs.lastSensorName); return }
            gatt.disconnect(silent = true)
        }
        // Scan for up to 30 s for the known device or any XDS-like device
        scanner.clear()
        if (!scanner.start()) { delay(5000); return }
        var found: com.rashed.bikesensordoctor.ble.ScannedDevice? = null
        for (i in 0 until 30) {
            if (!wanted) break
            val devs = scanner.devices.value
            found = (known?.let { devs[it] }) ?: devs.values.filter { it.looksLikeXds }.maxByOrNull { it.rssiAvg }
            if (found != null) break
            delay(1000)
        }
        scanner.stop()
        if (found == null) { delay(5000); return }   // sensor asleep; try again shortly
        gatt.connect(found.address, found.name, reconnect = true)
        if (waitReady(30_000)) onConnected(found.address, found.name)
    }

    private fun onConnected(address: String, name: String?) {
        prefs.lastSensorAddress = address
        prefs.lastSensorName = name ?: prefs.lastSensorName
        log.add(EventType.CONNECTION, device = address, note = "Sensor connected and remembered")
    }

    private suspend fun waitReady(timeoutMs: Long): Boolean {
        val t0 = System.currentTimeMillis()
        while (System.currentTimeMillis() - t0 < timeoutMs) {
            val st = gatt.snapshot.value.state
            if (st == ConnectionState.READY) return true
            if (st == ConnectionState.DISCONNECTED && System.currentTimeMillis() - t0 > 3000 && !gatt.isAutoReconnecting) return false
            delay(250)
        }
        return false
    }
}
