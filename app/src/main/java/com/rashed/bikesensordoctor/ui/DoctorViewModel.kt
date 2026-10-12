package com.rashed.bikesensordoctor.ui

import android.app.Application
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.rashed.bikesensordoctor.BikeApp
import com.rashed.bikesensordoctor.diag.AutoDiagnostic
import com.rashed.bikesensordoctor.ride.RideEngine
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Thin ViewModel over the app-wide RideEngine. The Diagnose & Repair flow (AutoDiagnostic) reuses the engine's
 * scanner/gatt/log, so the sensor supervisor is paused while it runs and restarted afterwards.
 */
class DoctorViewModel(app: Application) : AndroidViewModel(app) {
    val engine: RideEngine = BikeApp.engine(app)
    val log get() = engine.log
    val scanner get() = engine.scanner
    val gatt get() = engine.gatt

    val auto = AutoDiagnostic(engine.scanner, engine.gatt, engine.log, viewModelScope, ::saveReport)

    fun bluetoothOn(): Boolean = engine.bluetoothOn()

    fun startAuto() {
        engine.sensor.stop()
        auto.start(bluetoothOn())
    }

    fun endAuto() {
        auto.cancel()
        engine.connect()
    }

    private fun saveReport(text: String): String {
        val dir = File(getApplication<Application>().filesDir, "reports").apply { mkdirs() }
        val f = File(dir, "report-" + SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US).format(Date()) + ".txt")
        f.writeText(text)
        File(dir, f.nameWithoutExtension + "-log.json").writeText(log.toJson())
        dir.listFiles()?.sortedByDescending { it.lastModified() }?.drop(40)?.forEach { it.delete() }
        return f.absolutePath
    }

    fun shareLatestReport(context: Context) {
        val dir = File(getApplication<Application>().filesDir, "reports")
        val files = dir.listFiles()?.sortedByDescending { it.lastModified() }?.take(2) ?: emptyList()
        if (files.isEmpty()) return
        val uris = ArrayList(files.map { FileProvider.getUriForFile(context, context.packageName + ".fileprovider", it) })
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply {
            type = "text/*"
            putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris)
            putExtra(Intent.EXTRA_SUBJECT, "Bike Computer diagnostic report")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(Intent.createChooser(intent, "Send report").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    fun shareRideCsv(context: Context, startedAtMs: Long) {
        val f = engine.history.csvFile(startedAtMs)
        if (!f.exists()) return
        val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", f)
        val i = Intent(Intent.ACTION_SEND).apply { type = "text/csv"; putExtra(Intent.EXTRA_STREAM, uri); addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION) }
        context.startActivity(Intent.createChooser(i, "Share ride").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
