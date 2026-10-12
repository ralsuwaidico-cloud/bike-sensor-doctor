package com.rashed.bikesensordoctor

import android.app.Application
import android.content.Context
import com.rashed.bikesensordoctor.ride.RideEngine
import java.io.File
import java.io.PrintWriter
import java.io.StringWriter
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/** Holds the single RideEngine shared by the activity and the foreground service. */
class BikeApp : Application() {
    val engine: RideEngine by lazy { RideEngine(this) }

    override fun onCreate() {
        super.onCreate()
        installCrashRecorder()
    }

    /**
     * Writes any uncaught exception to files/last-crash.txt before the app dies, so the next launch can show it
     * and the rider can send it — no adb or developer tools needed.
     */
    private fun installCrashRecorder() {
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { t, e ->
            try {
                val sw = StringWriter(); e.printStackTrace(PrintWriter(sw))
                val text = "Bike Computer crash ${SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())}\n" +
                    "version ${runCatching { packageManager.getPackageInfo(packageName, 0).versionName }.getOrNull()} · Android ${android.os.Build.VERSION.RELEASE} · ${android.os.Build.MODEL}\n" +
                    "thread ${t.name}\n\n$sw"
                crashFile(this).writeText(text)
            } catch (_: Throwable) {}
            previous?.uncaughtException(t, e)
        }
    }

    companion object {
        fun engine(ctx: Context): RideEngine = (ctx.applicationContext as BikeApp).engine
        fun crashFile(ctx: Context): File = File(ctx.filesDir, "last-crash.txt")
    }
}
