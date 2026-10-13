package com.rashed.bikesensordoctor.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rashed.bikesensordoctor.ride.RideSimulator

/** Test tool: SIMULATED sensors for checking screens and coaching without hardware. Rides are tagged SIMULATED. */
@Composable
fun SimulationScreen(vm: DoctorViewModel, onBack: () -> Unit, onRide: () -> Unit) {
    val d by vm.engine.dash.collectAsStateWithLifecycle()
    var speed by remember { mutableIntStateOf(10) }
    var profile by remember { mutableStateOf(RideSimulator.Profile.STEADY_Z2) }
    Column(Modifier.fillMaxSize().background(D7.Bg).verticalScroll(rememberScrollState()).padding(14.dp)) {
        D7TopBar("SIMULATION", "Settings", onBack)
        Row(verticalAlignment = Alignment.CenterVertically) { Headline("Simulated ride", 22); Spacer(Modifier.width(8.dp)); SimTag() }
        Spacer(Modifier.height(6.dp))
        Muted("Feeds scripted power, cadence and heart rate through the same path as the real sensors so every screen and the coach can be tested without the bike. Nothing here measures you: rides are saved as SIMULATED and never count on a real leaderboard.")
        FieldLabel("RIDE SCRIPT")
        Chips(RideSimulator.Profile.values().map { it.name to it.label }, setOf(profile.name), columns = 2, small = true) { profile = RideSimulator.Profile.valueOf(it) }
        FieldLabel("PLAYBACK SPEED")
        Chips(listOf("1" to "1×", "5" to "5×", "10" to "10×", "30" to "30×"), setOf(speed.toString()), small = true) { speed = it.toInt() }
        Spacer(Modifier.height(12.dp))
        if (!d.simulated) PrimaryButton("START SIMULATED SENSORS", Modifier.fillMaxWidth().testTag("sim_start"), color = D7.Amber) { vm.engine.startSimulation(speed, profile); onRide() }
        else Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SecondaryButton("STOP", Modifier.weight(1f).testTag("sim_stop")) { vm.engine.stopSimulation() }
            PrimaryButton("GO TO RIDE SCREEN", Modifier.weight(1.4f), onClick = onRide)
        }
        Spacer(Modifier.height(10.dp))
        Text("Then press START on the ride screen as usual. The planned workout length ends the ride in the cool-down; at 10× a 60-minute ride takes 6 minutes.", fontSize = 12.sp, color = D7.Mut)
    }
}
