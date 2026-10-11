package com.rashed.bikesensordoctor.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import com.rashed.bikesensordoctor.log.EventLog
import com.rashed.bikesensordoctor.log.EventType
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import java.util.UUID

data class ScannedDevice(
    val address: String,
    val name: String?,
    val rssi: Int,
    val rssiHistory: List<Int>,       // last ~20 samples, for identification
    val serviceUuids: List<UUID>,
    val manufacturerData: Map<Int, String>, // company id -> hex
    val rawAdvertisement: String,     // full hex of scan record bytes
    val connectable: Boolean?,
    val lastSeenMs: Long,
    val seenCount: Int,
) {
    val rssiAvg: Double get() = if (rssiHistory.isEmpty()) rssi.toDouble() else rssiHistory.average()
    val displayName: String get() = name ?: "(no name)"
    val looksLikeXds: Boolean
        get() = (name?.startsWith("XDS", ignoreCase = true) == true) ||
                address.uppercase().startsWith("C0:A1:25") ||
                serviceUuids.contains(Uuids.MESH_PROXY)
    val advertisesCyclingService: Boolean
        get() = serviceUuids.contains(Uuids.CYCLING_POWER) || serviceUuids.contains(Uuids.CYCLING_SPEED_CADENCE)
}

/** Wraps BluetoothLeScanner; the caller is responsible for permissions (see Permissions.kt). */
class BleScanner(private val adapter: BluetoothAdapter?, private val log: EventLog) {

    private val _devices = MutableStateFlow<Map<String, ScannedDevice>>(emptyMap())
    val devices: StateFlow<Map<String, ScannedDevice>> = _devices

    private val _scanning = MutableStateFlow(false)
    val scanning: StateFlow<Boolean> = _scanning

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error

    private val callback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) = handle(result)
        override fun onBatchScanResults(results: MutableList<ScanResult>) = results.forEach { handle(it) }
        override fun onScanFailed(errorCode: Int) {
            val msg = "Scan failed: " + when (errorCode) {
                SCAN_FAILED_ALREADY_STARTED -> "already started ($errorCode)"
                SCAN_FAILED_APPLICATION_REGISTRATION_FAILED -> "app registration failed ($errorCode) — try toggling Bluetooth off/on"
                SCAN_FAILED_FEATURE_UNSUPPORTED -> "feature unsupported ($errorCode)"
                SCAN_FAILED_INTERNAL_ERROR -> "internal error ($errorCode)"
                5 -> "out of hardware resources ($errorCode)"
                6 -> "scanning too frequently ($errorCode) — wait 30 s and retry"
                else -> "code $errorCode"
            }
            _error.value = msg
            _scanning.value = false
            log.add(EventType.ERROR, note = msg)
        }
    }

    @SuppressLint("MissingPermission")
    private fun handle(result: ScanResult) {
        val record = result.scanRecord
        val addr = result.device.address
        val name = record?.deviceName ?: result.device.name
        val uuids = record?.serviceUuids?.map { it.uuid } ?: emptyList()
        val mfg = HashMap<Int, String>()
        record?.manufacturerSpecificData?.let { sa ->
            for (i in 0 until sa.size()) mfg[sa.keyAt(i)] = Parsers.hex(sa.valueAt(i))
        }
        _devices.update { map ->
            val prev = map[addr]
            val hist = ((prev?.rssiHistory ?: emptyList()) + result.rssi).takeLast(20)
            map + (addr to ScannedDevice(
                address = addr,
                name = name ?: prev?.name,
                rssi = result.rssi,
                rssiHistory = hist,
                serviceUuids = if (uuids.isNotEmpty()) uuids else (prev?.serviceUuids ?: emptyList()),
                manufacturerData = if (mfg.isNotEmpty()) mfg else (prev?.manufacturerData ?: emptyMap()),
                rawAdvertisement = Parsers.hex(record?.bytes).ifEmpty { prev?.rawAdvertisement ?: "" },
                connectable = result.isConnectable,
                lastSeenMs = System.currentTimeMillis(),
                seenCount = (prev?.seenCount ?: 0) + 1,
            ))
        }
        if ((_devices.value[addr]?.seenCount ?: 0) == 1) {
            log.add(EventType.SCAN, device = addr, bytes = record?.bytes,
                note = "first seen name=${name ?: "-"} rssi=${result.rssi} services=${uuids.joinToString { Uuids.short(it) }}")
        }
    }

    @SuppressLint("MissingPermission")
    fun start(): Boolean {
        _error.value = null
        val a = adapter ?: run { _error.value = "This phone has no Bluetooth adapter."; return false }
        if (!a.isEnabled) { _error.value = "Bluetooth is turned off. Enable it in Settings."; return false }
        val scanner = a.bluetoothLeScanner ?: run { _error.value = "BLE scanner unavailable."; return false }
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setReportDelay(0)
            .build()
        return try {
            scanner.startScan(null, settings, callback)
            _scanning.value = true
            log.add(EventType.INFO, note = "Scan started (low latency, no filter)")
            true
        } catch (e: Exception) {
            _error.value = "Scan start failed: ${e.message}"
            log.add(EventType.ERROR, note = _error.value ?: "")
            false
        }
    }

    @SuppressLint("MissingPermission")
    fun stop() {
        try { adapter?.bluetoothLeScanner?.stopScan(callback) } catch (_: Exception) {}
        if (_scanning.value) log.add(EventType.INFO, note = "Scan stopped")
        _scanning.value = false
    }

    fun clear() { _devices.value = emptyMap() }
}
