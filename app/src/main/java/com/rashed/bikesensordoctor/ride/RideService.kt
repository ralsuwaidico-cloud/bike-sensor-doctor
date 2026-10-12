package com.rashed.bikesensordoctor.ride

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import com.rashed.bikesensordoctor.BikeApp
import com.rashed.bikesensordoctor.R
import com.rashed.bikesensordoctor.core.RideStats
import com.rashed.bikesensordoctor.ui.MainActivity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * Foreground service active while a ride is RUNNING or PAUSED so Android keeps the process (and the Bluetooth
 * link in RideEngine) alive with the screen off. Logic lives in RideEngine; this class only owns the notification.
 */
class RideService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var ticker: Job? = null
    private var wakeLock: android.os.PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel()
        // Keep the CPU awake during a ride so the Bluetooth link and recording survive the screen turning off.
        if (wakeLock == null) {
            val pm = getSystemService(android.content.Context.POWER_SERVICE) as android.os.PowerManager
            wakeLock = pm.newWakeLock(android.os.PowerManager.PARTIAL_WAKE_LOCK, "BikeComputer::ride").apply {
                setReferenceCounted(false); acquire(6 * 60 * 60 * 1000L)  // safety cap 6 h
            }
        }
        val n = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= 34) startForeground(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            else startForeground(ID, n)
        } catch (e: Exception) {
            // Android 12+: a foreground start from the background is refused. Never crash the app for it — the
            // activity will start us again when it comes to the foreground (RideEngine.onForeground()).
            try { BikeApp.engine(this).log.add(com.rashed.bikesensordoctor.log.EventType.ERROR, note = "Foreground service refused: ${e.javaClass.simpleName}") } catch (_: Exception) {}
            stopSelf(); return START_NOT_STICKY
        }
        if (ticker == null) ticker = scope.launch {
            while (isActive) {
                delay(5000)
                val mgr = getSystemService(NotificationManager::class.java)
                mgr.notify(ID, buildNotification())
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        ticker?.cancel()
        try { wakeLock?.let { if (it.isHeld) it.release() } } catch (_: Exception) {}
        wakeLock = null
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val d = BikeApp.engine(this).dash.value
        val state = when (d.rideState) { RideStats.State.PAUSED -> "Paused"; RideStats.State.RUNNING -> "Riding"; else -> "Ready" }
        val text = "$state · ${RideEngine.fmtDuration(d.elapsedMs)} · ${d.power3sW?.let { "$it W" } ?: "— W"} · ${d.cadenceRpm?.let { "$it rpm" } ?: "— rpm"}"
        val pi = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return Notification.Builder(this, CHANNEL)
            .setContentTitle("Bike Computer")
            .setContentText(text)
            .setSmallIcon(R.drawable.ic_stat_bike)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(pi)
            .build()
    }

    private fun ensureChannel() {
        val mgr = getSystemService(NotificationManager::class.java)
        if (mgr.getNotificationChannel(CHANNEL) == null) {
            mgr.createNotificationChannel(NotificationChannel(CHANNEL, "Ride recording", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Shown while a ride is being recorded so the sensor stays connected with the screen off"
            })
        }
    }

    companion object {
        const val CHANNEL = "ride"
        const val ID = 1001
        fun start(ctx: Context) { runCatching { ctx.startForegroundService(Intent(ctx, RideService::class.java)) } }
        fun update(ctx: Context) { runCatching { ctx.startForegroundService(Intent(ctx, RideService::class.java)) } }
        fun stop(ctx: Context) { runCatching { ctx.stopService(Intent(ctx, RideService::class.java)) } }
    }
}
