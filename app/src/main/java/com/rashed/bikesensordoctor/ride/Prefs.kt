package com.rashed.bikesensordoctor.ride

import android.content.Context

/** Small settings store (SharedPreferences). */
class Prefs(context: Context) {
    private val sp = context.getSharedPreferences("bike_computer", Context.MODE_PRIVATE)

    var lastSensorAddress: String?
        get() = sp.getString("sensor_addr", DEFAULT_ADDRESS)
        set(v) = sp.edit().putString("sensor_addr", v).apply()

    var lastSensorName: String?
        get() = sp.getString("sensor_name", DEFAULT_NAME)
        set(v) = sp.edit().putString("sensor_name", v).apply()

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
