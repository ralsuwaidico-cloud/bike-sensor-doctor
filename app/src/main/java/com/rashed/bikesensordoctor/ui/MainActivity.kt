package com.rashed.bikesensordoctor.ui

import android.bluetooth.BluetoothAdapter
import android.content.Intent
import android.os.Bundle
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

class MainActivity : ComponentActivity() {
    private val vm: DoctorViewModel by viewModels()
    private val permissionGranted = mutableStateOf(false)
    private val bluetoothOn = mutableStateOf(false)

    private val permissionLauncher = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        permissionGranted.value = result.values.all { it }
    }
    private val enableBtLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        bluetoothOn.value = vm.bluetoothOn()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        setContent {
            MaterialTheme(
                colorScheme = darkColorScheme(
                    primary = Color(0xFF4DD0E1), secondary = Color(0xFFFFB74D),
                    background = Color(0xFF07161B), surface = Color(0xFF0E2229), onBackground = Color(0xFFE8F4F8), onSurface = Color(0xFFE8F4F8),
                ),
            ) {
                Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.background) {
                    when {
                        !permissionGranted.value -> PermissionGate { permissionLauncher.launch(Permissions.required()) }
                        !bluetoothOn.value -> BluetoothGate { enableBtLauncher.launch(Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)) }
                        else -> HomeScreen(vm)
                    }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        permissionGranted.value = Permissions.allGranted(this)
        bluetoothOn.value = vm.bluetoothOn()
    }
}

@Composable
private fun PermissionGate(onRequest: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(24.dp)) {
        Text("One permission is needed", fontSize = 26.sp, style = MaterialTheme.typography.headlineSmall)
        Text(
            "Android asks you to allow \"Nearby devices\" so this app can talk to your power meter over Bluetooth. " +
            "It is never used for location.",
            Modifier.padding(vertical = 16.dp), fontSize = 18.sp,
        )
        Button(onClick = onRequest, Modifier.fillMaxWidth().height(64.dp)) { Text("ALLOW", fontSize = 22.sp) }
        Text(
            "If nothing happens, Android has blocked the request. Open Settings → Apps → Bike Sensor Doctor → Permissions → Nearby devices → Allow, then come back.",
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
