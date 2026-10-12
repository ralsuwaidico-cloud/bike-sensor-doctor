package com.rashed.bikesensordoctor.core

/**
 * PORTABLE CORE — no Android imports.
 * Turns raw link/decoder facts into one of a few plain-language states so the UI never shows GATT codes.
 */
enum class Health {
    SEARCHING,          // not connected, scanning for the sensor
    RECONNECTING,       // link dropped, automatic recovery in progress
    CONNECTED_IDLE,     // link up, sensor streaming, cranks not turning
    CONNECTED_LIVE,     // link up, sensor streaming, cranks turning
    LINK_SILENT,        // link up but no packets for a while → Bluetooth problem, not sensor
    DECODE_ERROR,       // packets arrive but are malformed/implausible → software/firmware problem
    SENSOR_FAULT,       // sensor reports an error code
    BLUETOOTH_OFF,
    NO_PERMISSION,
}

object HealthClassifier {
    const val SILENT_MS = 6000L   // sensor sends at 1 Hz; 6 missed packets = link problem

    fun classify(
        bluetoothOn: Boolean,
        permission: Boolean,
        linkUp: Boolean,
        recovering: Boolean,
        lastPacketAgeMs: Long?,    // null = never
        lastSample: XdsSample?,
        recentRejected: Int,       // malformed in the last minute
    ): Health = when {
        !permission -> Health.NO_PERMISSION
        !bluetoothOn -> Health.BLUETOOTH_OFF
        !linkUp && recovering -> Health.RECONNECTING
        !linkUp -> Health.SEARCHING
        lastPacketAgeMs == null || lastPacketAgeMs > SILENT_MS -> Health.LINK_SILENT
        recentRejected >= 3 && lastSample == null -> Health.DECODE_ERROR
        lastSample != null && lastSample.errorCode != 0 -> Health.SENSOR_FAULT
        lastSample != null && lastSample.rotating -> Health.CONNECTED_LIVE
        else -> Health.CONNECTED_IDLE
    }

    fun message(h: Health): String = when (h) {
        Health.SEARCHING -> "Looking for your power meter… turn the pedals to wake it"
        Health.RECONNECTING -> "Connection lost — reconnecting automatically"
        Health.CONNECTED_IDLE -> "Connected · pedals still"
        Health.CONNECTED_LIVE -> "Connected · live"
        Health.LINK_SILENT -> "Connected, but no data is arriving — Bluetooth hiccup, retrying"
        Health.DECODE_ERROR -> "Sensor data is arriving but cannot be understood — please send a report"
        Health.SENSOR_FAULT -> "The sensor is reporting an internal error"
        Health.BLUETOOTH_OFF -> "Bluetooth is off"
        Health.NO_PERMISSION -> "Bluetooth permission needed"
    }
}
