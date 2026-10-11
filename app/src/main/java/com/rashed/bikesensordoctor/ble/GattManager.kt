package com.rashed.bikesensordoctor.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.rashed.bikesensordoctor.log.EventLog
import com.rashed.bikesensordoctor.log.EventType
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import java.util.ArrayDeque
import java.util.UUID

enum class ConnectionState { DISCONNECTED, CONNECTING, CONNECTED, DISCOVERING, READY, RECONNECT_WAIT }

data class CharInfo(
    val uuid: UUID,
    val properties: Int,
    val lastValueHex: String? = null,
    val lastValueText: String? = null,
    val notifying: Boolean = false,
) {
    val canRead get() = properties and BluetoothGattCharacteristic.PROPERTY_READ != 0
    val canWrite get() = properties and (BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0
    val canNotify get() = properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0
    val canIndicate get() = properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0
    val propText: String get() = buildList {
        if (canRead) add("R"); if (canWrite) add("W"); if (canNotify) add("N"); if (canIndicate) add("I")
    }.joinToString("")
}

data class ServiceInfo(val uuid: UUID, val characteristics: List<CharInfo>)

data class DeviceSnapshot(
    val address: String = "",
    val name: String = "",
    val state: ConnectionState = ConnectionState.DISCONNECTED,
    val services: List<ServiceInfo> = emptyList(),
    val batteryPct: Int? = null,
    val deviceInfo: Map<String, String> = emptyMap(),
    val rssi: Int? = null,
    val mtu: Int = 23,
    val metrics: CyclingMetrics? = null,
    val candidate: CandidateMetrics? = null,
    val lastError: String? = null,
    val connectAttempts: Int = 0,
    val disconnects: Int = 0,
    val hasCyclingPower: Boolean = false,
    val hasCsc: Boolean = false,
    val hasMeshProxy: Boolean = false,
    val hasXdsCustom: Boolean = false,
    val meshProxyHas2A63: Boolean = false,
    val meshProxyHas2A55: Boolean = false,
)

/**
 * Single-device GATT client with a serialized operation queue, timeouts and optional auto-reconnect.
 * All writes to the device are confined to [enableNotifications] (CCCD) and [experimentalWrite], which
 * the UI only calls after explicit user confirmation.
 */
class GattManager(private val context: Context, private val adapter: BluetoothAdapter?, val log: EventLog) {

    private val _snapshot = MutableStateFlow(DeviceSnapshot())
    val snapshot: StateFlow<DeviceSnapshot> = _snapshot

    private val main = Handler(Looper.getMainLooper())
    private var gatt: BluetoothGatt? = null
    private var autoReconnect = false
    private var userInitiatedDisconnect = false
    private var reconnectDelayMs = 1000L
    private var lastCrank: Pair<Int, Int>? = null

    // ---- serialized operation queue ----
    private class Op(val name: String, val run: () -> Boolean)
    private val queue = ArrayDeque<Op>()
    private var inFlight: Op? = null
    private val opTimeout = Runnable {
        inFlight?.let {
            log.add(EventType.ERROR, device = addr(), note = "Timeout (10 s) waiting for: ${it.name}")
            _snapshot.update { s -> s.copy(lastError = "Timeout: ${it.name}") }
        }
        inFlight = null
        next()
    }

    private fun enqueue(name: String, run: () -> Boolean) {
        queue.add(Op(name, run)); if (inFlight == null) next()
    }

    private fun next() {
        main.removeCallbacks(opTimeout)
        inFlight = null
        val op = queue.poll() ?: return
        inFlight = op
        val started = try { op.run() } catch (e: Exception) {
            log.add(EventType.ERROR, device = addr(), note = "${op.name} threw ${e.message}"); false
        }
        if (!started) {
            log.add(EventType.ERROR, device = addr(), note = "${op.name} could not be started (stack returned false)")
            main.post { next() }
        } else {
            main.postDelayed(opTimeout, 10_000)
        }
    }

    private fun completed() { main.post { next() } }

    private fun addr() = _snapshot.value.address

    // ---- public API ----

    @SuppressLint("MissingPermission")
    fun connect(address: String, name: String?, reconnect: Boolean) {
        val a = adapter ?: return fail("No Bluetooth adapter")
        if (!a.isEnabled) return fail("Bluetooth is off")
        disconnect(silent = true)
        autoReconnect = reconnect
        userInitiatedDisconnect = false
        reconnectDelayMs = 1000L
        _snapshot.value = DeviceSnapshot(address = address, name = name ?: "", state = ConnectionState.CONNECTING, connectAttempts = 1)
        val device = try { a.getRemoteDevice(address) } catch (e: IllegalArgumentException) { return fail("Bad address $address") }
        log.add(EventType.CONNECTION, device = address, note = "connectGatt (autoConnect=false, TRANSPORT_LE)")
        gatt = device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
        main.postDelayed(connectTimeout, 20_000)
    }

    private val connectTimeout = Runnable {
        if (_snapshot.value.state == ConnectionState.CONNECTING) {
            log.add(EventType.ERROR, device = addr(), note = "Connection timeout (20 s)")
            _snapshot.update { it.copy(lastError = "Connection timeout (20 s)") }
            closeGatt()
            scheduleReconnect()
        }
    }

    @SuppressLint("MissingPermission")
    fun disconnect(silent: Boolean = false) {
        userInitiatedDisconnect = true
        main.removeCallbacks(reconnectRunnable); main.removeCallbacks(connectTimeout)
        queue.clear(); inFlight = null; main.removeCallbacks(opTimeout)
        gatt?.let {
            if (!silent) log.add(EventType.CONNECTION, device = addr(), note = "User disconnect")
            try { it.disconnect() } catch (_: Exception) {}
        }
        closeGatt()
        if (!silent) _snapshot.update { it.copy(state = ConnectionState.DISCONNECTED) }
    }

    /** Documented, reversible recovery action #1: drop the link and reconnect from scratch. */
    fun reconnectNow() {
        val s = _snapshot.value
        if (s.address.isEmpty()) return
        log.add(EventType.CONNECTION, device = s.address, note = "Recovery: manual disconnect/reconnect cycle")
        val reconnect = autoReconnect
        disconnect()
        main.postDelayed({ connect(s.address, s.name, reconnect) }, 1500)
    }

    @SuppressLint("MissingPermission")
    fun readRssi() { gatt?.let { g -> enqueue("readRemoteRssi") { g.readRemoteRssi() } } }

    @SuppressLint("MissingPermission")
    fun readAllReadable() {
        val g = gatt ?: return
        for (svc in g.services) for (c in svc.characteristics) {
            if (c.properties and BluetoothGattCharacteristic.PROPERTY_READ != 0) {
                enqueue("read ${Uuids.short(c.uuid)}") { g.readCharacteristic(c) }
            }
        }
    }

    /** Subscribes (CCCD write) to every characteristic that supports notify or indicate. Reversible. */
    @SuppressLint("MissingPermission")
    fun enableAllNotifications() {
        val g = gatt ?: return
        for (svc in g.services) for (c in svc.characteristics) {
            val n = c.properties and BluetoothGattCharacteristic.PROPERTY_NOTIFY != 0
            val i = c.properties and BluetoothGattCharacteristic.PROPERTY_INDICATE != 0
            if (n || i) enableNotifications(c, indicate = !n && i)
        }
    }

    @SuppressLint("MissingPermission")
    private fun enableNotifications(c: BluetoothGattCharacteristic, indicate: Boolean) {
        val g = gatt ?: return
        enqueue("subscribe ${Uuids.short(c.uuid)}") {
            if (!g.setCharacteristicNotification(c, true)) return@enqueue false
            val cccd = c.getDescriptor(Uuids.CCCD) ?: run {
                log.add(EventType.ERROR, device = addr(), uuid = c.uuid.toString(), note = "No CCCD descriptor; cannot subscribe")
                return@enqueue false
            }
            val value = if (indicate) BluetoothGattDescriptor.ENABLE_INDICATION_VALUE else BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            if (Build.VERSION.SDK_INT >= 33) {
                g.writeDescriptor(cccd, value) == BluetoothGatt.GATT_SUCCESS
            } else {
                @Suppress("DEPRECATION")
                run { cccd.value = value; g.writeDescriptor(cccd) }
            }
        }
    }

    /**
     * PHASE 2 EXPERIMENT ONLY. Writes [bytes] to [charUuid]. The UI must show the source of the byte
     * sequence and obtain explicit confirmation before calling this. Never called automatically.
     */
    @SuppressLint("MissingPermission")
    fun experimentalWrite(charUuid: UUID, bytes: ByteArray, sourceNote: String) {
        val g = gatt ?: return
        val c = g.services.flatMap { it.characteristics }.firstOrNull { it.uuid == charUuid }
            ?: return log.add(EventType.ERROR, device = addr(), note = "Write target ${Uuids.short(charUuid)} not found")
        log.add(EventType.WRITE, device = addr(), uuid = charUuid.toString(), bytes = bytes, note = "USER-CONFIRMED experimental write. Source: $sourceNote")
        enqueue("write ${Uuids.short(charUuid)}") {
            val type = if (c.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0)
                BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT else BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            if (Build.VERSION.SDK_INT >= 33) {
                g.writeCharacteristic(c, bytes, type) == BluetoothGatt.GATT_SUCCESS
            } else {
                @Suppress("DEPRECATION")
                run { c.writeType = type; c.value = bytes; g.writeCharacteristic(c) }
            }
        }
    }

    // ---- internals ----

    private fun fail(msg: String) {
        log.add(EventType.ERROR, device = addr(), note = msg)
        _snapshot.update { it.copy(lastError = msg, state = ConnectionState.DISCONNECTED) }
    }

    @SuppressLint("MissingPermission")
    private fun closeGatt() {
        try { gatt?.close() } catch (_: Exception) {}
        gatt = null
    }

    @SuppressLint("MissingPermission")
    private val reconnectRunnable = Runnable {
        val s = _snapshot.value
        if (s.address.isEmpty() || userInitiatedDisconnect) return@Runnable
        log.add(EventType.CONNECTION, device = s.address, note = "Auto-reconnect attempt ${s.connectAttempts + 1}")
        _snapshot.update { it.copy(state = ConnectionState.CONNECTING, connectAttempts = it.connectAttempts + 1) }
        val device = adapter?.getRemoteDevice(s.address) ?: return@Runnable
        gatt = device.connectGatt(context, false, callback, BluetoothDevice.TRANSPORT_LE)
        main.postDelayed(connectTimeout, 20_000)
    }

    private fun scheduleReconnect() {
        if (!autoReconnect || userInitiatedDisconnect) {
            _snapshot.update { it.copy(state = ConnectionState.DISCONNECTED) }; return
        }
        _snapshot.update { it.copy(state = ConnectionState.RECONNECT_WAIT) }
        log.add(EventType.CONNECTION, device = addr(), note = "Reconnect in ${reconnectDelayMs} ms")
        main.postDelayed(reconnectRunnable, reconnectDelayMs)
        reconnectDelayMs = (reconnectDelayMs * 2).coerceAtMost(16_000)
    }

    private fun statusText(status: Int): String = when (status) {
        BluetoothGatt.GATT_SUCCESS -> "GATT_SUCCESS"
        BluetoothGatt.GATT_READ_NOT_PERMITTED -> "READ_NOT_PERMITTED (0x02)"
        BluetoothGatt.GATT_WRITE_NOT_PERMITTED -> "WRITE_NOT_PERMITTED (0x03)"
        BluetoothGatt.GATT_INSUFFICIENT_AUTHENTICATION -> "INSUFFICIENT_AUTHENTICATION (0x05) — device wants pairing/bonding"
        BluetoothGatt.GATT_REQUEST_NOT_SUPPORTED -> "REQUEST_NOT_SUPPORTED (0x06)"
        BluetoothGatt.GATT_INSUFFICIENT_ENCRYPTION -> "INSUFFICIENT_ENCRYPTION (0x0F) — device wants an encrypted link"
        BluetoothGatt.GATT_INVALID_OFFSET -> "INVALID_OFFSET (0x07)"
        BluetoothGatt.GATT_INVALID_ATTRIBUTE_LENGTH -> "INVALID_ATTRIBUTE_LENGTH (0x0D)"
        BluetoothGatt.GATT_CONNECTION_CONGESTED -> "CONNECTION_CONGESTED (0x8F)"
        BluetoothGatt.GATT_FAILURE -> "GATT_FAILURE (0x101)"
        8 -> "CONN_TIMEOUT (0x08) — link supervision timeout"
        19 -> "REMOTE_USER_TERMINATED (0x13) — the sensor closed the link"
        22 -> "LOCAL_HOST_TERMINATED (0x16)"
        62 -> "CONN_FAIL_ESTABLISH (0x3E)"
        133 -> "GATT_ERROR 133 (0x85) — generic Android stack failure; retry, toggle Bluetooth, or power-cycle sensor"
        0x81 -> "Application error 0x81 — device-defined rejection (seen by a community bridge for the '02 16 AA 10' write)"
        else -> "status $status (0x${Integer.toHexString(status)})"
    }

    private val callback = object : BluetoothGattCallback() {

        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            main.removeCallbacks(connectTimeout)
            main.post {
                if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                    reconnectDelayMs = 1000L
                    log.add(EventType.CONNECTION, device = g.device.address, note = "Connected; requesting MTU 247, then discovering services")
                    _snapshot.update { it.copy(state = ConnectionState.CONNECTED, lastError = null) }
                    discoveryStarted = false
                    if (!g.requestMtu(247)) startDiscovery(g)
                    // Fallback: if the MTU callback never arrives, discover anyway after 2 s.
                    main.postDelayed({ startDiscovery(g) }, 2000)
                } else {
                    log.add(EventType.CONNECTION, device = g.device.address, note = "Disconnected: ${statusText(status)}")
                    queue.clear(); inFlight = null; main.removeCallbacks(opTimeout)
                    _snapshot.update { it.copy(disconnects = it.disconnects + 1, lastError = if (status != 0) statusText(status) else it.lastError) }
                    closeGatt()
                    scheduleReconnect()
                }
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
            main.post {
                log.add(EventType.CONNECTION, device = addr(), note = "MTU=$mtu ${statusText(status)}")
                _snapshot.update { it.copy(mtu = mtu) }
                // Session log 2026-10-11 showed discovery hanging when started while the MTU exchange was in flight;
                // starting it from here (after the exchange) avoids that.
                startDiscovery(g)
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            main.post {
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    log.add(EventType.ERROR, device = addr(), note = "Service discovery failed: ${statusText(status)}")
                    _snapshot.update { it.copy(lastError = "Service discovery failed: ${statusText(status)}") }
                    return@post
                }
                val services = g.services.map { s ->
                    ServiceInfo(s.uuid, s.characteristics.map { c -> CharInfo(c.uuid, c.properties) })
                }
                for (s in services) {
                    log.add(EventType.SERVICE, device = addr(), uuid = s.uuid.toString(),
                        note = "Service ${Uuids.name(s.uuid)}: " + s.characteristics.joinToString { "${Uuids.short(it.uuid)}[${it.propText}]" })
                }
                val mesh = services.firstOrNull { it.uuid == Uuids.MESH_PROXY }
                _snapshot.update {
                    it.copy(
                        state = ConnectionState.READY,
                        services = services,
                        hasCyclingPower = services.any { s -> s.uuid == Uuids.CYCLING_POWER },
                        hasCsc = services.any { s -> s.uuid == Uuids.CYCLING_SPEED_CADENCE },
                        hasMeshProxy = mesh != null,
                        hasXdsCustom = services.any { s -> s.uuid == Uuids.XDS_CUSTOM_0401 || s.uuid == Uuids.XDS_CUSTOM_0201 },
                        meshProxyHas2A63 = mesh?.characteristics?.any { c -> c.uuid == Uuids.CP_MEASUREMENT } == true,
                        meshProxyHas2A55 = mesh?.characteristics?.any { c -> c.uuid == Uuids.SC_CONTROL_POINT } == true,
                    )
                }
                readAllReadable()
                enableAllNotifications()
                readRssi()
            }
        }

        // API 33+ signatures
        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            main.post { handleRead(c.uuid, value, status) }
        }
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
            main.post { handleNotify(c.service.uuid, c.uuid, value) }
        }

        // Pre-33 signatures (Android 12 on the Nokia 5.3 uses these)
        @Deprecated("Deprecated in Java")
        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            if (Build.VERSION.SDK_INT >= 33) return
            @Suppress("DEPRECATION") val v = c.value ?: ByteArray(0)
            main.post { handleRead(c.uuid, v, status) }
        }
        @Deprecated("Deprecated in Java")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT >= 33) return
            @Suppress("DEPRECATION") val v = c.value ?: ByteArray(0)
            main.post { handleNotify(c.service.uuid, c.uuid, v) }
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            main.post {
                log.add(if (status == 0) EventType.WRITE else EventType.ERROR, device = addr(), uuid = c.uuid.toString(),
                    note = "Write result: ${statusText(status)}")
                if (status != 0) _snapshot.update { it.copy(lastError = "Write ${Uuids.short(c.uuid)}: ${statusText(status)}") }
                completed()
            }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) {
            main.post {
                val cu = d.characteristic.uuid
                if (status == BluetoothGatt.GATT_SUCCESS) {
                    log.add(EventType.INFO, device = addr(), uuid = cu.toString(), note = "Subscribed (CCCD written)")
                    updateChar(cu) { it.copy(notifying = true) }
                } else {
                    log.add(EventType.ERROR, device = addr(), uuid = cu.toString(), note = "CCCD write failed: ${statusText(status)}")
                }
                completed()
            }
        }

        override fun onReadRemoteRssi(g: BluetoothGatt, rssi: Int, status: Int) {
            main.post {
                if (status == 0) _snapshot.update { it.copy(rssi = rssi) }
                completed()
            }
        }
    }

    private var discoveryStarted = false

    @SuppressLint("MissingPermission")
    private fun startDiscovery(g: BluetoothGatt) {
        if (discoveryStarted || gatt !== g) return
        discoveryStarted = true
        _snapshot.update { it.copy(state = ConnectionState.DISCOVERING) }
        if (!g.discoverServices()) log.add(EventType.ERROR, device = addr(), note = "discoverServices() returned false")
    }

    private fun updateChar(uuid: UUID, f: (CharInfo) -> CharInfo) {
        _snapshot.update { s ->
            s.copy(services = s.services.map { svc ->
                svc.copy(characteristics = svc.characteristics.map { if (it.uuid == uuid) f(it) else it })
            })
        }
    }

    private fun handleRead(uuid: UUID, value: ByteArray, status: Int) {
        if (status != BluetoothGatt.GATT_SUCCESS) {
            log.add(EventType.ERROR, device = addr(), uuid = uuid.toString(), note = "Read failed: ${statusText(status)}")
            completed(); return
        }
        val text = when {
            Parsers.isStringCharacteristic(uuid) -> Parsers.parseUtf8(value)
            uuid == Uuids.BATTERY_LEVEL -> Parsers.parseBattery(value)?.let { "$it %" }
            else -> null
        }
        log.add(EventType.READ, device = addr(), uuid = uuid.toString(), bytes = value, note = "${Uuids.name(uuid)}${text?.let { " = $it" } ?: ""}")
        updateChar(uuid) { it.copy(lastValueHex = Parsers.hex(value), lastValueText = text) }
        when (uuid) {
            Uuids.BATTERY_LEVEL -> _snapshot.update { it.copy(batteryPct = Parsers.parseBattery(value)) }
            Uuids.MODEL_NUMBER, Uuids.SERIAL_NUMBER, Uuids.FIRMWARE_REV, Uuids.HARDWARE_REV, Uuids.SOFTWARE_REV, Uuids.MANUFACTURER_NAME, Uuids.DEVICE_NAME ->
                _snapshot.update { it.copy(deviceInfo = it.deviceInfo + (Uuids.name(uuid) to (text ?: Parsers.hex(value)))) }
        }
        completed()
    }

    private fun handleNotify(serviceUuid: UUID, uuid: UUID, value: ByteArray) {
        var note = Uuids.name(uuid)
        updateChar(uuid) { it.copy(lastValueHex = Parsers.hex(value)) }
        when {
            uuid == Uuids.CP_MEASUREMENT && serviceUuid == Uuids.CYCLING_POWER -> {
                Parsers.parseCyclingPowerMeasurement(value)?.let { m -> applyMetrics(m); note += " power=${m.instantaneousPowerW}W" }
            }
            uuid == Uuids.CSC_MEASUREMENT && serviceUuid == Uuids.CYCLING_SPEED_CADENCE -> {
                Parsers.parseCscMeasurement(value)?.let { m -> applyMetrics(m); note += " crankRevs=${m.cumulativeCrankRevs}" }
            }
            uuid == Uuids.CP_MEASUREMENT && serviceUuid == Uuids.MESH_PROXY -> {
                // Not a SIG-compliant placement; try the community-documented XDS layout, labelled as candidate.
                Parsers.parseXdsCandidate(value)?.let { c ->
                    _snapshot.update { it.copy(candidate = c) }
                    note += " XDS power=${c.totalPowerW}W cadence=${c.cadenceSignedRpm} angle=${c.crankAngleDeg}"
                }
            }
            uuid == Uuids.BATTERY_LEVEL -> _snapshot.update { it.copy(batteryPct = Parsers.parseBattery(value)) }
        }
        log.add(EventType.NOTIFY, device = addr(), uuid = uuid.toString(), bytes = value, note = note)
    }

    private fun applyMetrics(m: CyclingMetrics) {
        var out = m
        val revs = m.cumulativeCrankRevs; val t = m.lastCrankEventTime1024
        if (revs != null && t != null) {
            lastCrank?.let { (pr, pt) -> Parsers.cadenceFromCrank(pr, pt, revs, t)?.let { out = out.copy(derivedCadenceRpm = it) } }
            lastCrank = revs to t
        }
        _snapshot.update { it.copy(metrics = out) }
    }
}
