package com.rashed.bikesensordoctor.ble

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import com.rashed.bikesensordoctor.core.BleStandard
import com.rashed.bikesensordoctor.log.EventLog
import com.rashed.bikesensordoctor.log.EventType
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import java.util.UUID

data class HrDevice(val address: String, val name: String?, val rssi: Int)

data class HrState(
    val address: String? = null,
    val name: String? = null,
    val connected: Boolean = false,
    val connecting: Boolean = false,
    val bpm: Int? = null,
    val lastBeatMs: Long? = null,
    val batteryPct: Int? = null,
)

/**
 * A second, independent BLE client dedicated to a STANDARD Heart Rate Service (0x180D / measurement 0x2A37).
 * This is what WHOOP's "Broadcast heart rate" and Apple-Watch HR-broadcasting apps expose, so it works with
 * any such strap/watch. Kept separate from GattManager so the XDS link and the HR link reconnect independently.
 * Uses the same safe pattern: full close + settle before reconnect, stale-callback rejection, autoConnect fallback.
 */
class HrSensor(private val context: Context, private val adapter: BluetoothAdapter?, private val log: EventLog) {
    companion object {
        val HR_SERVICE: UUID = UUID.fromString("0000180d-0000-1000-8000-00805f9b34fb")
        val HR_MEAS: UUID = UUID.fromString("00002a37-0000-1000-8000-00805f9b34fb")
        val BATTERY: UUID = UUID.fromString("00002a19-0000-1000-8000-00805f9b34fb")
        val CCCD: UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    }

    private val main = Handler(Looper.getMainLooper())
    private val _state = MutableStateFlow(HrState())
    val state: StateFlow<HrState> = _state

    private val _scan = MutableStateFlow<List<HrDevice>>(emptyList())
    val scan: StateFlow<List<HrDevice>> = _scan
    private val _scanning = MutableStateFlow(false)
    val scanning: StateFlow<Boolean> = _scanning

    private var gatt: BluetoothGatt? = null
    private var want = false
    private var connAddress: String? = null
    private var connName: String? = null
    private var autoConnectTried = false

    // --- scanning for HR-advertising devices ---
    private val scanCb = object : ScanCallback() {
        override fun onScanResult(type: Int, r: ScanResult) {
            val found = _scan.value.toMutableList()
            if (found.none { it.address == r.device.address }) {
                found.add(HrDevice(r.device.address, r.scanRecord?.deviceName ?: r.device.name, r.rssi))
                _scan.value = found.sortedByDescending { it.rssi }
            }
        }
    }

    @SuppressLint("MissingPermission")
    fun startScan() {
        val s = adapter?.bluetoothLeScanner ?: return
        _scan.value = emptyList(); _scanning.value = true
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(HR_SERVICE)).build()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        try { s.startScan(listOf(filter), settings, scanCb) } catch (e: Exception) { _scanning.value = false }
        main.postDelayed({ stopScan() }, 15_000)
    }

    @SuppressLint("MissingPermission")
    fun stopScan() {
        try { adapter?.bluetoothLeScanner?.stopScan(scanCb) } catch (_: Exception) {}
        _scanning.value = false
    }

    // --- connection ---
    @SuppressLint("MissingPermission")
    fun connect(address: String, name: String?) {
        want = true; connAddress = address; connName = name; autoConnectTried = false
        _state.value = HrState(address = address, name = name, connecting = true)
        stopScan()
        launch(false, 0)
    }

    @SuppressLint("MissingPermission")
    private fun launch(auto: Boolean, settle: Long) {
        main.postDelayed({
            val a = adapter ?: return@postDelayed
            if (!want) return@postDelayed
            closeGatt()
            val dev = try { a.getRemoteDevice(connAddress) } catch (e: Exception) { return@postDelayed }
            log.add(EventType.CONNECTION, device = connAddress ?: "", note = "HR connectGatt(auto=$auto)")
            gatt = dev.connectGatt(context, auto, callback, BluetoothDevice.TRANSPORT_LE)
        }, settle)
    }

    @SuppressLint("MissingPermission")
    fun disconnect() {
        want = false
        closeGatt()
        _state.value = HrState()
    }

    @SuppressLint("MissingPermission")
    private fun closeGatt() {
        gatt?.let { g ->
            try { g.javaClass.getMethod("refresh").invoke(g) } catch (_: Exception) {}
            try { g.disconnect() } catch (_: Exception) {}
            try { g.close() } catch (_: Exception) {}
        }
        gatt = null
    }

    private val callback = object : BluetoothGattCallback() {
        @SuppressLint("MissingPermission")
        override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
            if (g !== gatt) { try { g.close() } catch (_: Exception) {}; return }
            main.post {
                if (g !== gatt) return@post
                if (newState == BluetoothProfile.STATE_CONNECTED && status == 0) {
                    autoConnectTried = false
                    _state.value = _state.value.copy(connected = true, connecting = false)
                    g.discoverServices()
                } else {
                    _state.value = _state.value.copy(connected = false, connecting = want, bpm = null)
                    closeGatt()
                    if (want) {
                        // try autoConnect once, then keep retrying with backoff
                        if (!autoConnectTried) { autoConnectTried = true; launch(true, 700) }
                        else launch(false, 4000)
                    }
                }
            }
        }

        @SuppressLint("MissingPermission")
        override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
            if (g !== gatt) return
            main.post {
                if (g !== gatt || status != 0) return@post
                val svc = g.getService(HR_SERVICE) ?: return@post
                val meas = svc.getCharacteristic(HR_MEAS) ?: return@post
                g.setCharacteristicNotification(meas, true)
                val cccd = meas.getDescriptor(CCCD)
                if (cccd != null) {
                    if (Build.VERSION.SDK_INT >= 33) g.writeDescriptor(cccd, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)
                    else { @Suppress("DEPRECATION") run { cccd.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE; g.writeDescriptor(cccd) } }
                }
                g.getService(UUID.fromString("0000180f-0000-1000-8000-00805f9b34fb"))?.getCharacteristic(BATTERY)?.let { g.readCharacteristic(it) }
                log.add(EventType.CONNECTION, device = addr(), note = "HR subscribed")
            }
        }

        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
            if (g !== gatt) return
            main.post { if (g === gatt && c.uuid == HR_MEAS) onBeat(value) }
        }
        @Deprecated("Deprecated in Java")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            if (Build.VERSION.SDK_INT >= 33 || g !== gatt) return
            @Suppress("DEPRECATION") val v = c.value ?: return
            main.post { if (g === gatt && c.uuid == HR_MEAS) onBeat(v) }
        }

        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray, status: Int) {
            if (g !== gatt) return
            if (c.uuid == BATTERY) main.post { _state.value = _state.value.copy(batteryPct = BleStandard.battery(value)) }
        }
        @Deprecated("Deprecated in Java")
        override fun onCharacteristicRead(g: BluetoothGatt, c: BluetoothGattCharacteristic, status: Int) {
            if (Build.VERSION.SDK_INT >= 33 || g !== gatt) return
            @Suppress("DEPRECATION") val v = c.value ?: return
            if (c.uuid == BATTERY) main.post { _state.value = _state.value.copy(batteryPct = BleStandard.battery(v)) }
        }
    }

    private fun onBeat(value: ByteArray) {
        val bpm = BleStandard.heartRate(value) ?: return
        _state.value = _state.value.copy(bpm = bpm, lastBeatMs = System.currentTimeMillis())
    }

    private fun addr() = _state.value.address ?: ""

    /** Live HR, blanked if no beat for 8 s (strap removed / out of range). */
    fun liveBpm(nowMs: Long): Int? {
        val s = _state.value
        return if (s.lastBeatMs != null && nowMs - s.lastBeatMs!! <= com.rashed.bikesensordoctor.core.SensorPolicy.HR_STALE_MS) s.bpm else null
    }
}
