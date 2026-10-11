package com.rashed.bikesensordoctor.ui

import android.app.Application
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.rashed.bikesensordoctor.ble.BleScanner
import com.rashed.bikesensordoctor.ble.GattManager
import com.rashed.bikesensordoctor.diag.AutoDiagnostic
import com.rashed.bikesensordoctor.log.EventLog
import com.rashed.bikesensordoctor.log.EventType
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class DoctorViewModel(app: Application) : AndroidViewModel(app) {
    private val adapter = (app.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    val log = EventLog()
    val scanner = BleScanner(adapter, log)
    val gatt = GattManager(app, adapter, log)
    val auto = AutoDiagnostic(scanner, gatt, log, viewModelScope, ::saveReport)

    private var rssiJob: Job? = null

    init {
        log.add(EventType.INFO, note = "Bike Sensor Doctor started")
        rssiJob = viewModelScope.launch { while (isActive) { delay(3000); gatt.readRssi() } }
    }

    fun bluetoothOn(): Boolean = adapter?.isEnabled == true

    fun startAuto() = auto.start(bluetoothOn())

    /** Saves the technical report silently into the app's private files; returns the path. */
    private fun saveReport(text: String): String {
        val dir = File(getApplication<Application>().filesDir, "reports").apply { mkdirs() }
        val f = File(dir, "report-" + SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date()) + ".txt")
        f.writeText(text)
        // also save the raw JSON log next to it
        File(dir, f.nameWithoutExtension + "-log.json").writeText(log.toJson())
        // keep only the last 20 reports
        dir.listFiles()?.sortedByDescending { it.lastModified() }?.drop(40)?.forEach { it.delete() }
        return f.absolutePath
    }

    /** Opens the share sheet with the latest report and its JSON log (only used for troubleshooting). */
    fun shareLatestReport(context: Context) {
        val dir = File(getApplication<Application>().filesDir, "reports")
        val files = dir.listFiles()?.sortedByDescending { it.lastModified() }?.take(2) ?: emptyList()
        if (files.isEmpty()) return
        val uris = ArrayList(files.map { FileProvider.getUriForFile(context, context.packageName + ".fileprovider", it) })
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = "text/*"
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            putExtra(Intent.EXTRA_SUBJECT, "Bike Sensor Doctor report")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "Send report").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    override fun onCleared() {
        rssiJob?.cancel()
        scanner.stop()
        gatt.disconnect(silent = true)
    }
}
