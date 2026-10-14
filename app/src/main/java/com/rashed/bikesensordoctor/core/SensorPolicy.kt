package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — sensor-quality policy (versioned product defaults, not physiology).
 * A reading older than its stale limit is reported as null — shown as "—", drawn as a gap, never held or invented.
 * A measured 0 W while coasting is a value, not a gap. Simulated and unverified sources are flagged, never promoted.
 */
object SensorPolicy {
    const val VERSION = "sensor-policy-1.0"
    /** The XDS meter notifies about once per second; 4 s tolerates one missed packet without flickering to "—". */
    const val POWER_STALE_MS = 4_000L
    const val CADENCE_STALE_MS = 4_000L
    const val HR_STALE_MS = 6_000L
    const val GPS_STALE_MS = 10_000L

    enum class Quality { VALID, MISSING, STALE, OUTLIER, RECONNECTING, UNVERIFIED_DEVICE, SIMULATED }

    /** Plausibility gate for a single reading (outliers are flagged, not corrected). */
    fun plausiblePower(w: Int) = w in 0..2500
    fun plausibleHr(bpm: Int) = bpm in 30..230
    fun plausibleCadence(rpm: Int) = rpm in 0..220
}
