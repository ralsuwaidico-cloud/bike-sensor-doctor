package com.rashed.bikesensordoctor.ride

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Looper
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

data class TrackPoint(val timeMs: Long, val lat: Double, val lon: Double, val altM: Double?, val speedKmh: Double)

data class GpsState(
    val available: Boolean = false,
    val hasFix: Boolean = false,
    val speedKmh: Double? = null,
    val distanceKm: Double = 0.0,
)

/**
 * Speed/distance/track from Android's GPS via LocationManager (no extra dependency). Distance accumulates
 * only while [recording] and only from fixes with acceptable accuracy, so a stationary jitter doesn't inflate it.
 * Caller must hold ACCESS_FINE_LOCATION; start() is a no-op without it.
 */
class GpsTracker(private val context: Context) {
    private val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
    private val _state = MutableStateFlow(GpsState())
    val state: StateFlow<GpsState> = _state

    private val points = ArrayList<TrackPoint>()
    @Volatile private var recordingActive = false
    private var last: Location? = null
    private var distanceM = 0.0
    private var listening = false

    private val listener = object : LocationListener {
        override fun onLocationChanged(loc: Location) { onFix(loc) }
        @Deprecated("Deprecated in Java") override fun onStatusChanged(p: String?, s: Int, e: android.os.Bundle?) {}
        override fun onProviderEnabled(p: String) {}
        override fun onProviderDisabled(p: String) {}
    }

    @SuppressLint("MissingPermission")
    fun start() {
        val m = lm ?: return
        if (listening) return
        val provider = when {
            m.isProviderEnabled(LocationManager.GPS_PROVIDER) -> LocationManager.GPS_PROVIDER
            m.isProviderEnabled(LocationManager.FUSED_PROVIDER) -> LocationManager.FUSED_PROVIDER
            else -> return
        }
        try {
            m.requestLocationUpdates(provider, 1000L, 0f, listener, Looper.getMainLooper())
            listening = true
            _state.value = _state.value.copy(available = true)
        } catch (_: SecurityException) {
        } catch (_: Exception) {}
    }

    fun stop() {
        try { lm?.removeUpdates(listener) } catch (_: Exception) {}
        listening = false
    }

    /** Begin/stop accumulating distance and recording the track for the current ride. */
    fun setRecording(on: Boolean) {
        recordingActive = on
        if (on) { points.clear(); distanceM = 0.0; last = null; _state.value = _state.value.copy(distanceKm = 0.0) }
    }

    private fun onFix(loc: Location) {
        val speedKmh = if (loc.hasSpeed()) loc.speed * 3.6 else 0.0
        _state.value = _state.value.copy(available = true, hasFix = true, speedKmh = speedKmh)
        if (!recordingActive) { last = loc; return }
        val prev = last
        if (prev != null && loc.hasAccuracy() && loc.accuracy <= 25f) {
            val d = prev.distanceTo(loc)
            // ignore sub-metre jitter and absurd jumps
            if (d in 0.5f..80f) distanceM += d
        }
        last = loc
        points.add(TrackPoint(System.currentTimeMillis(), loc.latitude, loc.longitude,
            if (loc.hasAltitude()) loc.altitude else null, speedKmh))
        _state.value = _state.value.copy(distanceKm = distanceM / 1000.0)
    }

    fun snapshotTrack(): List<TrackPoint> = ArrayList(points)
    fun distanceKm(): Double = distanceM / 1000.0
}
