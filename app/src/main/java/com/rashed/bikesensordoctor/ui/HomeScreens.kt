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
                    CardTitle("WHY"); Bullets(w.why)
                    Spacer(Modifier.height(4.dp)); CardTitle("HOW THE COACH WILL GUIDE IT"); Bullets(w.how)
                    Spacer(Modifier.height(4.dp)); CardTitle("WHAT IT WILL MEASURE"); Bullets(w.measure)
                }
                Spacer(Modifier.height(8.dp))
                Text("Change workout:", fontSize = 12.sp, color = D7.Mut)
                Chips(base!!.alts + (if (overridden) listOf("reset" to "Back to recommended") else emptyList()), emptySet(), columns = 2, small = true) { k ->
                    if (k == "reset") vm.engine.chooseWorkout(null) else RiderProfile.alternative(k, base, a, c)?.let { vm.engine.chooseWorkout(it) }
                    tick++
                }
                Spacer(Modifier.height(10.dp))
                Row(verticalAlignment = Alignment.CenterVertically) { Text("Zones: ", fontSize = 12.sp, color = D7.Mut); ConfidenceTag(c.zoneConfidence); Spacer(Modifier.width(6.dp)); Text(c.zoneConfidenceText.substringAfter("— "), fontSize = 11.sp, color = D7.Mut, maxLines = 2, modifier = Modifier.weight(1f)) }
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

// ------------------------------------------------------------------ Post-ride questions

@Composable
fun PostRideScreen(vm: DoctorViewModel, result: RideResult, onDone: () -> Unit) {
    val r = vm.engine.rider ?: return
    val a = r.answers
    val c = vm.engine.setup
    val before = remember { vm.engine.workout }
    val fu = remember { RiderProfile.followUp(a, r.feedback, r.asked) }
    var rpe by remember { mutableIntStateOf(6) }
    var limiter by remember { mutableStateOf<String?>(null) }
    var recovered by remember { mutableStateOf<String?>(null) }
    var fuChoice by remember { mutableStateOf<String?>(null) }
    var fuValue by remember { mutableStateOf<Int?>(null) }
    var after by remember { mutableStateOf<Workout?>(null) }
    var savedFb by remember { mutableStateOf<RideFeedback?>(null) }

    Column(Modifier.fillMaxSize().background(D7.Bg).verticalScroll(rememberScrollState()).padding(14.dp)) {
        if (after == null) {
            D7TopBar("POST-RIDE", null, null)
            Eyebrow("RIDE COMPLETE${if (result.source == RideSource.SIMULATED) " · SIMULATED" else ""}")
            Headline("${RideEngine.fmtDuration(result.durationSec * 1000L)} · ${String.format(java.util.Locale.US, "%.1f", result.km)} km · avg ${if (result.avgHr > 0) "${result.avgHr} bpm" else "— bpm"}", 20)
            Spacer(Modifier.height(8.dp))
            KeyValue(listOf(
                "Time in band" to (if (c != null) "${result.inZonePct}%" else "no band (generic)"),
                "HR drift" to (if (result.avgHr > 0) "${if (result.driftPct >= 0) "+" else ""}${result.driftPct}% (2nd half vs 1st)" else "no heart rate"),
                "Coach cues" to "${result.cues}",
                "Source" to (if (result.source == RideSource.SIMULATED) "SIMULATED sensors — not a real ride, never on a real board" else "device sensors"),
            ))
            Spacer(Modifier.height(12.dp))
            Headline("Two quick questions", 17)
            FieldLabel("HOW HARD DID THAT FEEL, 1 (EASY) TO 10 (MAXIMAL)?")
            SliderRow(rpe, 1, 10, 1, "/ 10") { rpe = it }
            FieldLabel("WHAT LIMITED YOU?")
            Chips(listOf("legs" to "Legs", "breathing" to "Breathing", "tired" to "Tiredness", "none" to "Nothing"), setOfNotNull(limiter), small = true) { limiter = it }
            FieldLabel("RECOVERED ENOUGH TO RIDE AGAIN TOMORROW?")
            Chips(listOf("yes" to "Yes", "no" to "No", "unsure" to "Not sure"), setOfNotNull(recovered), small = true) { recovered = it }
            if (fu != null) D7Card(Modifier.padding(top = 10.dp), accent = D7.Violet) {
                CardTitle("ONE MORE, BECAUSE IT WOULD IMPROVE YOUR PLAN")
                Text(fu.question, fontSize = 14.sp, color = D7.Fg, fontWeight = FontWeight.Bold)
                fu.why?.let { Muted(it, 12) }
                Spacer(Modifier.height(6.dp))
                if (fu.kind == "metric") NumberField(fuValue, fu.unit, fu.min, fu.max, Modifier.width(120.dp)) { fuValue = it }
                else Chips(fu.options, setOfNotNull(fuChoice), small = true) { fuChoice = it }
            }
            Spacer(Modifier.height(14.dp))
            fun finish(withAnswers: Boolean) {
                val fb = RideFeedback(result.startedAtMs, result.inZonePct, result.driftPct, result.avgHr, result.durationSec,
                    if (withAnswers) rpe else null, if (withAnswers) limiter else null, if (withAnswers) recovered else null)
                val fuVal = if (!withAnswers || fu == null) null else if (fu.kind == "metric") fuValue?.toString() else fuChoice
                vm.engine.recordFeedback(fb, if (withAnswers) fu?.key else null, fuVal)
                savedFb = fb; after = vm.engine.workout
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SecondaryButton("SKIP", Modifier.weight(1f)) { finish(false) }
                PrimaryButton("SAVE", Modifier.weight(1.4f).testTag("save_post"), onClick = { finish(true) })
            }
        } else {
            val b = before; val n = after!!
            val changed = b == null || b.name != n.name || b.minutes != n.minutes
            D7TopBar("NEXT WORKOUT", null, null)
            Headline(if (changed) "The recommendation changed" else "The recommendation stands", 20)
            Spacer(Modifier.height(8.dp))
            if (b != null) D7Card { CardTitle("BEFORE THIS RIDE"); Text("${b.name} · ${b.minutes} min", fontSize = 13.sp, color = D7.Fg) }
            D7Card(Modifier.padding(top = 8.dp), accent = D7.Green) {
                CardTitle("AFTER THIS RIDE"); Text("${n.name} · ${n.minutes} min", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = D7.Fg); Spacer(Modifier.height(4.dp)); Bullets(n.why)
            }
            savedFb?.let { fb -> Muted("Used: ${if (fb.rpe != null) "your effort ${fb.rpe}/10, limiter ${fb.limiter ?: "—"}, recovered ${fb.recovered ?: "—"}, " else ""}time in band ${fb.inZonePct}%, drift ${fb.driftPct}%. Rides on record: ${r.feedback.size}.", 12) }
            Spacer(Modifier.height(14.dp))
            PrimaryButton("HOME", Modifier.fillMaxWidth().testTag("post_home"), onClick = onDone)
        }
        Spacer(Modifier.height(16.dp))
    }
}
