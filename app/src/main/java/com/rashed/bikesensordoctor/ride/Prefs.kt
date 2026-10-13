package com.rashed.bikesensordoctor.ride

import android.content.Context

/**
 * Small settings store (SharedPreferences), one per rider account. The original single-rider store ("bike_computer")
 * belongs to the first/migrated rider ([RiderStore.LEGACY_ID]) so an update never loses existing settings.
 * The XDS power meter is on the bike, not the rider, so its pairing lives in the shared store for every rider.
 */
class Prefs(context: Context, val riderId: String = RiderStore.LEGACY_ID) {
    private val sp = context.getSharedPreferences(if (riderId == RiderStore.LEGACY_ID) "bike_computer" else "bike_computer_$riderId", Context.MODE_PRIVATE)
    private val shared = context.getSharedPreferences("bike_computer", Context.MODE_PRIVATE)

    var lastSensorAddress: String?
        get() = shared.getString("sensor_addr", DEFAULT_ADDRESS)
        set(v) = shared.edit().putString("sensor_addr", v).apply()

    var lastSensorName: String?
        get() = shared.getString("sensor_name", DEFAULT_NAME)
        set(v) = shared.edit().putString("sensor_name", v).apply()

    var keepScreenOn: Boolean
        get() = sp.getBoolean("keep_screen_on", true)
        set(v) = sp.edit().putBoolean("keep_screen_on", v).apply()

    /** Which metric is shown in each of the four small fields, by key. */
    var fields: List<String>
        get() = (sp.getString("fields", null) ?: DEFAULT_FIELDS.joinToString(",")).split(",")
        set(v) = sp.edit().putString("fields", v.joinToString(",")).apply()

    var ftpW: Int
        get() = sp.getInt("ftp", 200)
        set(v) = sp.edit().putInt("ftp", v).apply()

    var maxHr: Int
        get() = sp.getInt("maxhr", 185)
        set(v) = sp.edit().putInt("maxhr", v).apply()

    var hrAddress: String?
        get() = sp.getString("hr_addr", null)
        set(v) = sp.edit().putString("hr_addr", v).apply()
    var hrName: String?
        get() = sp.getString("hr_name", null)
        set(v) = sp.edit().putString("hr_name", v).apply()

    var coachMode: String
        get() = sp.getString("coach_mode", "FREE") ?: "FREE"
        set(v) = sp.edit().putString("coach_mode", v).apply()
    var coachVoice: Boolean
        get() = sp.getBoolean("coach_voice", true)
        set(v) = sp.edit().putBoolean("coach_voice", v).apply()
    // ---- P1/P2 coaching settings ----
    var cadenceCoaching: Boolean
        get() = sp.getBoolean("cad_coach", true)
        set(v) = sp.edit().putBoolean("cad_coach", v).apply()
    var warmupSec: Int
        get() = sp.getInt("warmup_sec", 300)
        set(v) = sp.edit().putInt("warmup_sec", v).apply()
    /** True once the rider has set the value; until then the UI flags the number as an UNVERIFIED DEFAULT. */
    var ftpSetByUser: Boolean
        get() = sp.getBoolean("ftp_set", false)
        set(v) = sp.edit().putBoolean("ftp_set", v).apply()
    var maxHrSetByUser: Boolean
        get() = sp.getBoolean("maxhr_set", false)
        set(v) = sp.edit().putBoolean("maxhr_set", v).apply()
    // ---- P0: power verified under real load (LoadVerifier PASS) ----
    var powerVerifiedAtMs: Long
        get() = sp.getLong("pw_verified_at", 0L)
        set(v) = sp.edit().putLong("pw_verified_at", v).apply()
    var powerVerifiedMaxW: Int
        get() = sp.getInt("pw_verified_max", 0)
        set(v) = sp.edit().putInt("pw_verified_max", v).apply()
    val powerVerified: Boolean get() = powerVerifiedAtMs > 0

    var cadenceLow: Int
        get() = sp.getInt("cad_low", 85)
        set(v) = sp.edit().putInt("cad_low", v).apply()
    var cadenceHigh: Int
        get() = sp.getInt("cad_high", 95)
        set(v) = sp.edit().putInt("cad_high", v).apply()

    companion object {
        const val DEFAULT_ADDRESS = "C0:A1:25:07:97:69"
        const val DEFAULT_NAME = "XDS-A001-9769"
        val DEFAULT_FIELDS = listOf("power3s", "avgPower", "maxPower", "time")
        val FIELD_OPTIONS = linkedMapOf(
            "power3s" to "3 s power",
            "power10s" to "10 s power",
            "avgPower" to "Average power",
            "maxPower" to "Max power",
            "powerZone" to "Power zone",
            "speed" to "Speed (GPS)",
            "distance" to "Distance (GPS)",
            "time" to "Ride time",
            "avgCadence" to "Average cadence",
            "maxCadence" to "Max cadence",
            "energy" to "Energy (kJ)",
            "battery" to "Sensor battery",
            "balance" to "L / R balance",
            "clock" to "Clock",
        )
    }
}
