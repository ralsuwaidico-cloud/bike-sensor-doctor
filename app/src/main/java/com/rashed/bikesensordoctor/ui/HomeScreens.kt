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
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rashed.bikesensordoctor.core.RideFeedback
import com.rashed.bikesensordoctor.core.RideSource
import com.rashed.bikesensordoctor.core.RiderAnswers
import com.rashed.bikesensordoctor.core.RiderProfile
import com.rashed.bikesensordoctor.core.Workout
import com.rashed.bikesensordoctor.ride.RideEngine
import com.rashed.bikesensordoctor.ride.RideResult

/*
 * Personal home (today's recommended workout), post-ride questions and the updated recommendation.
 * Social features live in ClubScreens.kt; the live ride screen stays the Design-7 dashboard.
 */

@Composable
fun HomeScreen(vm: DoctorViewModel, onStartRide: () -> Unit, onSwitch: () -> Unit, onProfile: () -> Unit, onTab: (String) -> Unit, onHistory: () -> Unit, onSettings: () -> Unit) {
    val d by vm.engine.dash.collectAsStateWithLifecycle()
    val r = vm.engine.rider ?: return
    val a = r.answers
    val c = vm.engine.setup
    var tick by remember { mutableIntStateOf(0) }
    val w = vm.engine.workout
    val base = remember(tick, r.feedback.size) { c?.let { s -> val cal = java.util.Calendar.getInstance(); RiderProfile.recommend(a, s, r.feedback, (cal.get(java.util.Calendar.DAY_OF_WEEK) + 5) % 7) } }
    val overridden = w != null && base != null && (w.name != base.name || w.minutes != base.minutes)

    Column(Modifier.fillMaxSize().background(D7.Bg)) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 14.dp, vertical = 8.dp)) {
            D7TopBar("HOME", null, null, right = { TextButton(onClick = onSettings) { Text("⚙", color = D7.Cyan, fontSize = 16.sp) } })
            D7Card {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Avatar(r.initials)
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Row(verticalAlignment = Alignment.CenterVertically) { Text("Riding as ", fontSize = 13.sp, color = D7.Mut); Text(r.name, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = D7.Fg); if (r.isSample) { Spacer(Modifier.width(6.dp)); SampleTag() } }
                        Text("Power meter: ${vm.engine.prefs.lastSensorName ?: "none"} · HR: ${vm.engine.prefs.hrName ?: "no strap"}", fontSize = 11.sp, color = D7.Mut, maxLines = 1)
                    }
                    SecondaryButton("SWITCH", Modifier.height(36.dp).testTag("switch_rider"), onClick = onSwitch)
                }
            }
            Spacer(Modifier.height(10.dp))
            if (c == null || w == null) {
                Eyebrow("NO PROFILE YET")
                Headline("Generic coaching until you finish the setup.", 20)
                Spacer(Modifier.height(6.dp))
                Muted("Zones are a generic default (max HR ${vm.engine.prefs.maxHr}, FTP ${vm.engine.prefs.ftpW}) and marked GENERIC on the ride screen. Two minutes of questions make the coach yours.")
                Spacer(Modifier.height(10.dp))
                PrimaryButton("FINISH SETUP", Modifier.fillMaxWidth().testTag("finish_setup"), color = D7.Cyan, onClick = onProfile)
                Spacer(Modifier.height(10.dp))
            } else {
                Eyebrow("MAIN GOAL")
                Headline(RiderAnswers.goalName(RiderProfile.primaryGoal(a)), 20)
                RiderProfile.successText(a)?.let { Muted("Success in 3 months: $it", 12) }
                Spacer(Modifier.height(8.dp))
                D7Card(accent = D7.Green) {
                    Row(verticalAlignment = Alignment.CenterVertically) { CardTitle("TODAY'S RECOMMENDED WORKOUT"); if (overridden) { Spacer(Modifier.width(6.dp)); Tag("YOUR CHOICE", D7.Amber) } }
                    Text(w.name, fontFamily = Archivo, fontWeight = FontWeight.ExtraBold, fontSize = 18.sp, lineHeight = 22.sp, color = D7.Fg)
                    Text("${w.minutes} min · ${w.hrLo}–${w.hrHi} bpm · ${if (w.pwLo != null) "${w.pwLo}–${w.pwHi} W" else "power off"}", fontFamily = PlexMono, fontSize = 12.sp, color = D7.Cyan, modifier = Modifier.padding(vertical = 4.dp))
                    w.why.firstOrNull()?.let { Text(it, fontSize = 13.sp, lineHeight = 18.sp, color = D7.Fg) }
                    Expander("Why this workout?", tag = "exp_why_workout") { Bullets(w.why.drop(1).ifEmpty { w.why }) }
                    Expander("How the coach will guide it") { Bullets(w.how); Spacer(Modifier.height(4.dp)); CardTitle("WHAT IT WILL MEASURE"); Bullets(w.measure) }
                }
                Spacer(Modifier.height(8.dp))
                Text("Change workout:", fontSize = 12.sp, color = D7.Mut)
                Chips(base!!.alts + (if (overridden) listOf("reset" to "Back to recommended") else emptyList()), emptySet(), columns = 2, small = true) { k ->
                    if (k == "reset") vm.engine.chooseWorkout(null) else RiderProfile.alternative(k, base, a, c)?.let { vm.engine.chooseWorkout(it) }
                    tick++
                }
                Spacer(Modifier.height(10.dp))
                Row(verticalAlignment = Alignment.CenterVertically) { Text("Zones: ", fontSize = 12.sp, color = D7.Mut); ConfidenceTag(c.zoneConfidence); Spacer(Modifier.width(6.dp)); Text(c.zoneConfidenceText.substringAfter("— ").substringBefore(". "), fontSize = 11.sp, color = D7.Mut, maxLines = 1, overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis, modifier = Modifier.weight(1f)) }
                if (!vm.engine.prefs.powerVerified && c.powerCoaching) Text("Power targets stay off until the meter is verified under load (Settings).", fontSize = 11.sp, color = D7.Amber, modifier = Modifier.padding(top = 4.dp))
                Spacer(Modifier.height(10.dp))
            }
            if (d.simulated) Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) { SimTag(); Spacer(Modifier.width(6.dp)); Text("Simulated sensors are running (Settings → Simulation).", fontSize = 11.sp, color = D7.Amber) }
            d.lastSavedRide?.let { Text(it, fontFamily = PlexMono, fontSize = 11.sp, color = D7.Green, modifier = Modifier.padding(top = 6.dp)) }
            Spacer(Modifier.height(12.dp))
        }
        // START RIDE is always visible, whatever the scroll position
        Column(Modifier.padding(horizontal = 10.dp, vertical = 6.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SecondaryButton("HISTORY", Modifier.weight(1f), onClick = onHistory)
                PrimaryButton(if (d.rideState == com.rashed.bikesensordoctor.core.RideStats.State.IDLE) "START RIDE" else "BACK TO RIDE", Modifier.weight(1.6f).testTag("start_ride"), onClick = onStartRide)
            }
            Spacer(Modifier.height(6.dp))
            TabBar("HOME", onTab)
        }
    }
}
