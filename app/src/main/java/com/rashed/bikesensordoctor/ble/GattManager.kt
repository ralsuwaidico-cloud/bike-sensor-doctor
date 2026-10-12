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
    val lastPacketMs: Long? = null,
    val rejectedPackets: Int = 0,
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

    /** Every decoded XDS sample (portable core type), with wall-clock ms. Set by the ride layer. */
    var onXdsSample: ((com.rashed.bikesensordoctor.core.XdsSample, Long) -> Unit)? = null

    val isAutoReconnecting: Boolean get() = autoReconnect && !userInitiatedDisconnect && _snapshot.value.address.isNotEmpty()

    private val main = Handler(Looper.getMainLooper())
    private var gatt: BluetoothGatt? = null
    private var autoReconnect = false
    private var userInitiatedDisconnect = false
    private var reconnectDelayMs = 1000L
    private var lastCrank: Pair<Int, Int>? = null

    // Connection lifecycle state (hardened 2026-10-12 after the PC probe proved the sensor itself
    // connects 8/8 and survives rapid reconnects — so every failure was Android-side teardown/timing).
    private var generation = 0                 // bumped per connectGatt; callbacks from an old client are dropped
    private var connAddress = ""
    private var connName: String? = null
    private var connAutoConnect = false
    private var triedAutoConnect = false       // per attempt-cycle: direct first, autoConnect=true as fallback
    private var everReady = false              // reached READY at least once this connect() session

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
        // Cancel anything in flight and tear the old client down completely before we touch the radio again.
        main.removeCallbacks(reconnectRunnable); main.removeCallbacks(connectTimeout); main.removeCallbacks(connectRunnable)
        queue.clear(); inFlight = null; main.removeCallbacks(opTimeout)
        autoReconnect = reconnect
        userInitiatedDisconnect = false
        reconnectDelayMs = 1000L
        triedAutoConnect = false
        everReady = false
        connAddress = address; connName = name
        _snapshot.value = DeviceSnapshot(address = address, name = name ?: "", state = ConnectionState.CONNECTING, connectAttempts = 1)
        val hadGatt = gatt != null
        closeGatt()
        // Settle delay after a close is the single most important fix for Android's error-133 on reconnect:
        // connectGatt too soon after close() reuses a half-released client and the sensor still thinks it is taken.
        launchConnect(useAutoConnect = false, settleMs = if (hadGatt) 700 else 0)
    }

    private fun launchConnect(useAutoConnect: Boolean, settleMs: Long) {
        connAutoConnect = useAutoConnect
        main.removeCallbacks(connectRunnable)
        main.postDelayed(connectRunnable, settleMs)
    }

    @SuppressLint("MissingPermission")
    private val connectRunnable = Runnable {
        val a = adapter
        if (a == null || userInitiatedDisconnect || connAddress.isEmpty()) return@Runnable
        val device = try { a.getRemoteDevice(connAddress) } catch (e: Exception) { fail("Bad address $connAddress"); return@Runnable }
        generation++
        log.add(EventType.CONNECTION, device = connAddress, note = "connectGatt (autoConnect=$connAutoConnect, gen=$generation)")
        gatt = device.connectGatt(context, connAutoConnect, callback, BluetoothDevice.TRANSPORT_LE)
        // Direct attempts need a timeout; autoConnect=true has no deadline (the stack keeps trying in the background).
        if (!connAutoConnect) main.postDelayed(connectTimeout, 20_000)
    }

    private val connectTimeout = Runnable {
        if (_snapshot.value.state == ConnectionState.CONNECTING) {
            log.add(EventType.ERROR, device = addr(), note = "Connect attempt timed out (20 s, autoConnect=$connAutoConnect)")
            closeGatt()
            onConnectAttemptFailed("timeout")
        }
    }

    /** A connection attempt that never reached READY: try autoConnect once, then fall back to scheduled retry. */
    private fun onConnectAttemptFailed(reason: String) {
        when (com.rashed.bikesensordoctor.core.ConnectionPolicy.decide(userInitiatedDisconnect, everReady, triedAutoConnect)) {
            com.rashed.bikesensordoctor.core.RecoveryAction.STOP ->
                _snapshot.update { it.copy(state = ConnectionState.DISCONNECTED) }
            com.rashed.bikesensordoctor.core.RecoveryAction.TRY_AUTOCONNECT -> {
                triedAutoConnect = true
                log.add(EventType.CONNECTION, device = connAddress, note = "Retrying with autoConnect=true after $reason")
                _snapshot.update { it.copy(state = ConnectionState.CONNECTING) }
                launchConnect(useAutoConnect = true, settleMs = 700)
            }
            com.rashed.bikesensordoctor.core.RecoveryAction.SCHEDULE_RETRY -> scheduleReconnect()
        }
    }

    @SuppressLint("MissingPermission")
    fun disconnect(silent: Boolean = false) {
        userInitiatedDisconnect = true
        main.removeCallbacks(reconnectRunnable); main.removeCallbacks(connectTimeout); main.removeCallbacks(connectRunnable)
        queue.clear(); inFlight = null; main.removeCallbacks(opTimeout)
        if (!silent && gatt != null) log.add(EventType.CONNECTION, device = addr(), note = "User disconnect")
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
        gatt?.let { g ->
            // Clear Android's cached service handles so a reconnect reads them fresh (reversible, local-only).
            refreshDeviceCache(g)
            try { g.disconnect() } catch (_: Exception) {}
            try { g.close() } catch (_: Exception) {}
        }
        gatt = null
    }

    /** BluetoothGatt.refresh() is hidden API; calling it clears the local GATT cache. Best-effort, no-op on failure. */
    @SuppressLint("MissingPermission")
    private fun refreshDeviceCache(g: BluetoothGatt) {
        try { g.javaClass.getMethod("refresh").invoke(g) } catch (_: Exception) {}
    }

    private val reconnectRunnable = Runnable {
        if (connAddress.isEmpty() || userInitiatedDisconnect) return@Runnable
        triedAutoConnect = true   // reconnects go straight to the persistent mode below
        _snapshot.update { it.copy(state = ConnectionState.CONNECTING, connectAttempts = it.connectAttempts + 1) }
        log.add(EventType.CONNECTION, device = connAddress, note = "Auto-reconnect (persistent autoConnect) attempt ${_snapshot.value.connectAttempts}")
        closeGatt()
        // KEY FIX (2026-10-12 ride log): the XDS meter sleeps when pedaling pauses and closes the link cleanly
        // (status GATT_SUCCESS). A direct connectGatt(autoConnect=false) can never catch a non-advertising sleeping
        // sensor and times out forever. autoConnect=true waits in the background and latches the moment the sensor
        // re-advertises (i.e. when the rider pedals again) — exactly the right tool for mid-ride sleep/wake.
        launchConnect(useAutoConnect = true, settleMs = 400)
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
            if (g !== gatt) { try { g.close() } catch (_: Exception) {}; return }   // stale client from a previous attempt
            main.removeCallbacks(connectTimeout)
            main.post {
                if (g !== gatt) return@post
                if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
                    reconnectDelayMs = 1000L
                    triedAutoConnect = false
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
                    when {
                        userInitiatedDisconnect -> _snapshot.update { it.copy(state = ConnectionState.DISCONNECTED) }
                        // Dropped before ever reaching READY → a failed attempt: try autoConnect, then scheduled retry.
                        !everReady -> onConnectAttemptFailed("status $status")
                        // Dropped mid-session after a good connection → normal reconnect with backoff.
                        else -> scheduleReconnect()
                    }
                }
            }
        }

        override fun onMtuChanged(g: BluetoothGatt, mtu: Int, status: Int) {
            if (g !== gatt) return
            main.post {
                if (g !== gatt) return@post
                log.add(EventType.CONNECTION, device = addr(), note = "MTU=$mtu ${statusText(status)}")
                _snapshot.update { it.copy(mtu = mtu) }
                // Session log 2026-10-11 showed discovery hanging when started while the MTU exchange was in flight;
                // starting it from here (after the exchange) avoids that.
                startDiscovery(g)
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            if (g !== gatt) return
            main.post {
                if (g !== gatt) return@post
                if (status != BluetoothGatt.GATT_SUCCESS) {
                    log.add(EventType.ERROR, device = addr(), note = "Service discovery failed: ${statusText(status)}")
                    _snapshot.update { it.copy(lastError = "Service discovery failed: ${statusText(status)}") }
                    // treat as a failed attempt so the retry path runs instead of a dead connection
                    closeGatt(); if (!everReady) onConnectAttemptFailed("discovery $status") else scheduleReconnect()
                    return@post
                }
                everReady = true
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
            if (g !== gatt) return
            main.post { if (g === gatt) handleRead(c.uuid, value, status) }
        }
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
            if (g !== gatt) return
            main.post { if (g === gatt) handleNotify(c.service.uuid, c.uuid, value) }
        }

        // Pre-33 signatures (Android 12 on the Nokia 5.3 uses these)
        @Deprecated("Deprecated in Java")
        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            if (Build.VERSION.SDK_INT >= 33 || g !== gatt) return
            @Suppress("DEPRECATION") val v = c.value ?: ByteArray(0)
            main.post { if (g === gatt) handleRead(c.uuid, v, status) }
        }
        @Deprecated("Deprecated in Java")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT >= 33 || g !== gatt) return
            @Suppress("DEPRECATION") val v = c.value ?: ByteArray(0)
            main.post { if (g === gatt) handleNotify(c.service.uuid, c.uuid, v) }
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            if (g !== gatt) return
            main.post {
                log.add(if (status == 0) EventType.WRITE else EventType.ERROR, device = addr(), uuid = c.uuid.toString(),
                    note = "Write result: ${statusText(status)}")
                if (status != 0) _snapshot.update { it.copy(lastError = "Write ${Uuids.short(c.uuid)}: ${statusText(status)}") }
                completed()
            }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) {
            if (g !== gatt) return
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
            if (g !== gatt) return
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
                val now = System.currentTimeMillis()
                val core = com.rashed.bikesensordoctor.core.XdsDecoder.decode(value)
                if (core == null || !core.plausible) _snapshot.update { it.copy(rejectedPackets = it.rejectedPackets + 1, lastPacketMs = now) }
                else { _snapshot.update { it.copy(lastPacketMs = now) }; onXdsSample?.invoke(core, now) }
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
