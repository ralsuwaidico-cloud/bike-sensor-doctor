package com.ralsuwaidico.bikecomputer

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.ralsuwaidico.bikecomputer.link.BCLink

/**
 * BikeComputer for Android — foundation only (build 15 of the iOS app is the reference). It shows the five tabs as
 * empty states and carries the shared Link codec; BLE, GPS and recording follow in the Android phase. Nothing here
 * displays example data as a measurement.
 */
class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme(colorScheme = darkColorScheme()) { Root() } }
    }
}

private val tabs = listOf("Home", "Plan", "Ride", "Progress", "Profile")

@Composable
fun Root() {
    var tab by remember { mutableIntStateOf(0) }
    Scaffold(bottomBar = {
        NavigationBar { tabs.forEachIndexed { i, t -> NavigationBarItem(selected = tab == i, onClick = { tab = i }, icon = {}, label = { Text(t) }) } }
    }) { pad ->
        Column(Modifier.padding(pad).padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(tabs[tab], style = MaterialTheme.typography.headlineMedium)
            Text("no data yet", color = MaterialTheme.colorScheme.secondary)
            Text("Android foundation: Link protocol v${BCLink.VER_MAJOR}.${BCLink.VER_MINOR} shared with the iPhone app and the BikeComputer. " +
                 "Pairing, GPS and ride recording arrive in the Android phase; this screen never shows example values.",
                 style = MaterialTheme.typography.bodySmall)
        }
    }
}
