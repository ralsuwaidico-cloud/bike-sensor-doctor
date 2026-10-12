package com.rashed.bikesensordoctor.ui

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat

class MainActivity : ComponentActivity() {
    private val vm: DoctorViewModel by viewModels()
    private val permissionGranted = mutableStateOf(false)
    private val bluetoothOn = mutableStateOf(false)

    private val permissionLauncher = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        permissionGranted.value = Permissions.allGranted(this)
        if (permissionGranted.value) afterPermissions()
    }
    private val enableBtLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        bluetoothOn.value = vm.bluetoothOn()
    }

    private var tts: android.speech.tts.TextToSpeech? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyKeepScreenOn()
        // Spoken coaching: route the engine's cues through Android TTS.
        tts = android.speech.tts.TextToSpeech(this) { status ->
            if (status == android.speech.tts.TextToSpeech.SUCCESS) tts?.language = java.util.Locale.ENGLISH
        }
        vm.engine.onSpeak = { text ->
            runCatching { tts?.speak(text, android.speech.tts.TextToSpeech.QUEUE_FLUSH, null, "coach") }
        }
        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    primary = Color(0xFF4DD0E1), secondary = Color(0xFFFFB74D),
                    background = Color(0xFF000000), surface = Color(0xFF0E1A1F), onBackground = Color(0xFFF2F7F9), onSurface = Color(0xFFF2F7F9),
                ),
            ) {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    when {
                        !permissionGranted.value -> PermissionGate { permissionLauncher.launch(Permissions.required() + extraPermissions()) }
                        !bluetoothOn.value -> BluetoothGate { enableBtLauncher.launch(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)) }
                        else -> BikeComputerApp(vm, onKeepScreenOnChanged = { applyKeepScreenOn() }, onBatteryOptimization = { requestIgnoreBatteryOptimizations() })
                    }
                }
            }
        }
    }

    // Location is optional (for GPS speed/distance); denying it must not block the app, so it is requested
    // alongside but never gates entry — Permissions.allGranted() only checks the required Bluetooth permissions.
    private fun extraPermissions(): Array<String> = buildList {
        add(Manifest.permission.ACCESS_FINE_LOCATION)
        if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
    }.toTypedArray()

    private fun afterPermissions() { vm.engine.connect() }

    fun applyKeepScreenOn() {
        if (vm.engine.prefs.keepScreenOn) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    /** Asks Android to exempt the app from battery optimisation so the Bluetooth link survives Doze during rides. */
    private fun requestIgnoreBatteryOptimizations() {
        val pm = getSystemService(PowerManager::class.java)
        if (!pm.isIgnoringBatteryOptimizations(packageName)) {
            try {
                startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
            } catch (_: Exception) {
                startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            }
        }
    }

    override fun onResume() {
        super.onResume()
        permissionGranted.value = Permissions.allGranted(this)
        bluetoothOn.value = vm.bluetoothOn()
        if (permissionGranted.value && bluetoothOn.value) vm.engine.connect()
    }

    override fun onDestroy() {
        runCatching { tts?.shutdown() }
        super.onDestroy()
    }
}

@Composable
private fun PermissionGate(onRequest: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(24.dp)) {
        Text("One permission is needed", fontSize = 26.sp, style = MaterialTheme.typography.headlineSmall)
        Text(
            "Android asks you to allow \"Nearby devices\" so this app can talk to your power meter over Bluetooth. It is never used for location.",
            Modifier.padding(vertical = 16.dp), fontSize = 18.sp,
        )
        Button(onClick = onRequest, Modifier.fillMaxWidth().height(64.dp)) { Text("ALLOW", fontSize = 22.sp) }
        Text(
            "If nothing happens, Android has blocked the request. Open Settings → Apps → Bike Computer → Permissions → Nearby devices → Allow, then come back.",
            Modifier.padding(top = 20.dp), fontSize = 15.sp,
        )
    }
}

@Composable
private fun BluetoothGate(onEnable: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(24.dp)) {
        Text("Bluetooth is off", fontSize = 26.sp, style = MaterialTheme.typography.headlineSmall)
        Text("Turn it on to continue.", Modifier.padding(vertical = 16.dp), fontSize = 18.sp)
        Button(onClick = onEnable, Modifier.fillMaxWidth().height(64.dp)) { Text("TURN ON BLUETOOTH", fontSize = 20.sp) }
    }
}
