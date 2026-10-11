package com.rashed.bikesensordoctor.ui

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat

/** Runtime permissions required for BLE on this Android version. */
object Permissions {
    fun required(): Array<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) // Android 12+
            arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        else
            arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)

    fun allGranted(context: Context): Boolean =
        required().all { ContextCompat.checkSelfPermission(context, it) == PackageManager.PERMISSION_GRANTED }
}
