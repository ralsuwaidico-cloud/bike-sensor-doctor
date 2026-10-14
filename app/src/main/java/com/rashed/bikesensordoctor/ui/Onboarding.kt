package com.rashed.bikesensordoctor.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
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
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rashed.bikesensordoctor.core.RiderAnswers
import com.rashed.bikesensordoctor.core.RiderProfile
import com.rashed.bikesensordoctor.ride.Rider

/*
 * Rider accounts (local) and the six-page onboarding. The pages, controls and rules mirror the approved
 * interactive demo (design/coach_demo.html). Nothing here talks to a server: accounts live on this phone only.
 */

// ------------------------------------------------------------------ Sign in / create account / switch rider

@Composable
fun SignInScreen(vm: DoctorViewModel, switching: Boolean, onDone: () -> Unit, onCancel: (() -> Unit)?) {
    val riders = remember { mutableStateOf(vm.engine.riders.list()) }
    var pinFor by remember { mutableStateOf<Rider?>(null) }
    var pin by remember { mutableStateOf("") }
    var pinError by remember { mutableStateOf(false) }
    var newName by remember { mutableStateOf("") }
    var newPin by remember { mutableStateOf("") }
    val active = vm.engine.rider?.id
    fun signIn(r: Rider) { if (vm.engine.switchRider(r.id)) onDone() }

    Column(Modifier.fillMaxSize().background(D7.Bg).verticalScroll(rememberScrollState()).padding(14.dp)) {
        D7TopBar(if (switching) "SWITCH RIDER" else "SIGN IN", if (onCancel != null) "Cancel" else null, onCancel)
        Headline(if (switching) "Who is riding?" else "Choose your account")
        Spacer(Modifier.height(4.dp))
        Muted(if (switching) "The next ride is saved under the rider you pick. Their zones, coach, heart-rate strap and workout load with them."
              else "Each rider's zones, coaching and rides are kept apart on this phone. Accounts are local for now — there is no cloud sign-in yet.")
        Spacer(Modifier.height(10.dp))
        riders.value.forEach { r ->
            Row(Modifier.fillMaxWidth().padding(vertical = 3.dp).background(D7.Panel2, RoundedCornerShape(12.dp))
                .border(1.dp, if (r.id == active) D7.Cyan else D7.Line, RoundedCornerShape(12.dp))
                .clickable { if (r.pin != null) { pinFor = r; pin = ""; pinError = false } else signIn(r) }
                .padding(horizontal = 10.dp, vertical = 8.dp).testTag("rider_${r.id}"), verticalAlignment = Alignment.CenterVertically) {
                Avatar(r.initials)
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(r.name, fontWeight = FontWeight.Bold, fontSize = 15.sp, color = D7.Fg)
                        if (r.isSample) { Spacer(Modifier.width(6.dp)); SampleTag() }
                    }
                    Text((if (r.completed) RiderAnswers.GOAL_SHORT[RiderProfile.primaryGoal(r.answers)] ?: "" else "setup not finished") + (if (r.pin != null) " · PIN" else ""), fontSize = 12.sp, color = D7.Mut)
                }
                if (r.id == active) Text("ACTIVE", fontFamily = PlexMono, fontSize = 9.sp, color = D7.Cyan)
            }
            if (pinFor?.id == r.id) D7Card(Modifier.padding(vertical = 4.dp)) {
                CardTitle("PIN FOR ${r.name.uppercase()}")
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(value = pin, onValueChange = { pin = it.filter { c -> c.isDigit() }.take(6); pinError = false }, singleLine = true, modifier = Modifier.width(130.dp).testTag("pin_box"),
                        visualTransformation = PasswordVisualTransformation(), keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword),
                        textStyle = TextStyle(fontFamily = PlexMono, fontSize = 18.sp, color = D7.Fg),
                        colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = D7.Cyan, unfocusedBorderColor = D7.Line, cursorColor = D7.Cyan))
                    Spacer(Modifier.width(8.dp))
                    PrimaryButton("UNLOCK", Modifier.testTag("pin_ok")) { if (pin == r.pin) signIn(r) else { pinError = true; pin = "" } }
                }
                if (pinError) Text("Wrong PIN.", color = D7.Red, fontSize = 12.sp, modifier = Modifier.padding(top = 4.dp))
            }
        }
        Spacer(Modifier.height(10.dp))
        D7Card {
            CardTitle("CREATE ACCOUNT")
            Row(verticalAlignment = Alignment.CenterVertically) {
                OutlinedTextField(value = newName, onValueChange = { newName = it.take(18) }, singleLine = true, label = { Text("Display name", fontSize = 11.sp) }, modifier = Modifier.weight(1f).testTag("new_name"),
                    textStyle = TextStyle(fontSize = 15.sp, color = D7.Fg),
                    colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = D7.Cyan, unfocusedBorderColor = D7.Line, focusedLabelColor = D7.Cyan, unfocusedLabelColor = D7.Mut, cursorColor = D7.Cyan))
                Spacer(Modifier.width(8.dp))
                OutlinedTextField(value = newPin, onValueChange = { newPin = it.filter { c -> c.isDigit() }.take(6) }, singleLine = true, label = { Text("PIN (opt.)", fontSize = 11.sp) }, modifier = Modifier.width(110.dp).testTag("new_pin"),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.NumberPassword), textStyle = TextStyle(fontFamily = PlexMono, fontSize = 15.sp, color = D7.Fg),
                    colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = D7.Cyan, unfocusedBorderColor = D7.Line, focusedLabelColor = D7.Cyan, unfocusedLabelColor = D7.Mut, cursorColor = D7.Cyan))
            }
            Spacer(Modifier.height(8.dp))
            PrimaryButton("CREATE & SET UP", Modifier.fillMaxWidth().testTag("create_btn"), enabled = newName.isNotBlank()) {
                vm.engine.createRider(newName, newPin.ifBlank { null }); riders.value = vm.engine.riders.list(); onDone()
            }
        }
        Spacer(Modifier.height(10.dp))
        Muted("Sample riders (Omar, Layla, Sami, Noor) are fictional and marked SAMPLE everywhere. They exist so the club and leaderboard have something to show.", 12)
        Spacer(Modifier.height(20.dp))
    }
}

// ------------------------------------------------------------------ Welcome (first launch for a new rider)

@Composable
fun WelcomeScreen(vm: DoctorViewModel, onStart: () -> Unit, onSkip: () -> Unit, onSwitch: () -> Unit) {
    val r = vm.engine.rider
    Column(Modifier.fillMaxSize().background(D7.Bg).verticalScroll(rememberScrollState()).padding(18.dp)) {
        D7TopBar("WELCOME", null, null, right = { TextButton(onClick = onSwitch) { Text("Switch rider", color = D7.Mut, fontSize = 12.sp) } })
        Spacer(Modifier.height(30.dp))
        Eyebrow("NEW RIDER · ${r?.name?.uppercase() ?: ""}")
        Spacer(Modifier.height(8.dp))
        Headline("Let's build your personal cycling coach${r?.name?.let { ", $it" } ?: ""}.", 26)
        Spacer(Modifier.height(12.dp))
        Muted("Six short pages, about two minutes. Skip anything you don't know — the coach will say what it still needs to learn. Nothing leaves this phone.", 15)
        Spacer(Modifier.height(28.dp))
        PrimaryButton("START", Modifier.fillMaxWidth().testTag("start_onboarding"), onClick = onStart)
        Spacer(Modifier.height(8.dp))
        if (r != null && !r.answers.isEmpty) SecondaryButton("RESUME WHERE I STOPPED", Modifier.fillMaxWidth(), onClick = onStart)
        else SecondaryButton("SKIP — SET UP LATER", Modifier.fillMaxWidth().testTag("skip_onboarding"), onClick = onSkip)
        Spacer(Modifier.height(10.dp))
        Muted("Without a profile the coach uses generic zones (marked GENERIC) until you complete the setup from the ME tab.", 12)
    }
}

// ------------------------------------------------------------------ The six pages

private val PAGES = listOf(
    "About you" to "Four quick facts. Everything else is optional.",
    "Your goals" to "One main goal; add a second if you like.",
    "Your training routine" to "So the plan fits your week, not an ideal one.",
    "Fitness & zones" to "Skip anything you don't know — the coach will say what is provisional.",
    "Coaching preferences" to "Change these any time in the ME tab.",
    "Your personal coach" to "",
)

@Composable
fun OnboardingScreen(vm: DoctorViewModel, page: Int, onPage: (Int) -> Unit, onFinished: () -> Unit) {
    val r = vm.engine.rider ?: return
    val a = r.answers
    var tick by remember { mutableIntStateOf(0) }
    fun saved() { r.page = page; vm.engine.riders.save(r) }          // numbers/sliders: persist without rebuilding the page (keeps the keyboard focus)
    fun changed() { saved(); tick++ }                                  // chips: persist and rebuild so the selection shows
    fun pick(key: String, v: String) {
        a[key] = v
        if (key == "primary") { a.setList("goals", listOf(v) + a.list("goals").filter { it != v }); a["success"] = null }
        changed()
    }
    fun toggle(key: String, v: String) {
        var cur = a.list(key)
        if (v == "none") cur = if ("none" in cur) emptyList() else listOf("none")
        else { cur = cur.filter { it != "none" }; cur = if (v in cur) cur.filter { it != v } else cur + v }
        a.setList(key, cur); changed()
    }
    val valid = tick >= 0 && RiderProfile.pageValid(page, a)

    Column(Modifier.fillMaxSize().background(D7.Bg)) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 14.dp, vertical = 8.dp)) {
            D7TopBar("SET UP", null, null, right = { Text("${page + 1} / 6", fontFamily = PlexMono, fontSize = 11.sp, color = D7.Faint) })
            Row(horizontalArrangement = Arrangement.spacedBy(5.dp), modifier = Modifier.padding(bottom = 8.dp)) {
                repeat(6) { i -> Box(Modifier.size(width = if (i == page) 18.dp else 8.dp, height = 8.dp).background(if (i < page) D7.Green else if (i == page) D7.Cyan else D7.Line, CircleShape)) }
            }
            Headline(PAGES[page].first)
            if (PAGES[page].second.isNotEmpty()) { Spacer(Modifier.height(2.dp)); Muted(PAGES[page].second, 12) }
            Spacer(Modifier.height(4.dp))
            Keyed(tick) {
                when (page) {
                    0 -> PageYou(a, ::pick, ::saved)
                    1 -> PageGoals(a, ::pick, ::toggle)
                    2 -> PageRoutine(a, ::pick, ::toggle, ::saved)
                    3 -> PageZones(a, ::pick, ::saved, ::changed)
                    4 -> PagePrefs(a, ::pick, ::toggle, ::saved, ::changed)
                    else -> {}
                }
            }
            Spacer(Modifier.height(16.dp))
        }
        Row(Modifier.fillMaxWidth().background(D7.Panel).padding(10.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            SecondaryButton("‹ BACK", Modifier.weight(0.9f)) { if (page > 0) onPage(page - 1) }
            SecondaryButton("SKIP", Modifier.weight(0.8f).testTag("skip_page")) { RiderProfile.skipDefaults(page, a); changed(); if (page >= 4) onFinished() else onPage(page + 1) }
            PrimaryButton("CONTINUE ›", Modifier.weight(1.3f).testTag("next_page"), enabled = valid) { changed(); if (page >= 4) onFinished() else onPage(page + 1) }
        }
    }
}

@Composable
private fun Keyed(k: Int, content: @Composable () -> Unit) { androidx.compose.runtime.key(k) { content() } }

@Composable
private fun MetricRow(a: RiderAnswers, key: String, label: String, unit: String, min: Int, max: Int, onChange: () -> Unit, onTick: () -> Unit) {
    val m = a.metric(key)
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, fontSize = 12.sp, lineHeight = 14.sp, color = D7.Fg, modifier = Modifier.width(64.dp))
        NumberField(a.int("$key.value"), unit, min, max, Modifier.width(80.dp).testTag("num_$key")) { v -> a.setMetric(key, v, a["$key.how"] ?: if (v != null) "estimated" else null); onChange() }
        Spacer(Modifier.width(6.dp))
        Box(Modifier.weight(1f)) {
            Chips(listOf("measured" to "Tested", "estimated" to "Est.", "app" to "App"), setOfNotNull(a["$key.how"]), small = true) { how -> a["$key.how"] = how; onTick() }
        }
    }
    if (m == null && a["$key.how"] != null) Muted("Enter the value, or clear the tag.", 11)
}

@Composable
private fun PageYou(a: RiderAnswers, pick: (String, String) -> Unit, changed: () -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        NumberField(a.int("age"), "Age", 14, 90, Modifier.weight(1f).testTag("num_age")) { a["age"] = it?.toString(); changed() }
        NumberField(a.int("heightCm"), "Height cm", 120, 220, Modifier.weight(1f)) { a["heightCm"] = it?.toString(); changed() }
        NumberField(a.int("weightKg"), "Weight kg", 35, 160, Modifier.weight(1f)) { a["weightKg"] = it?.toString(); changed() }
    }
    FieldLabel("EXPERIENCE")
    Chips(listOf("new" to "New", "recreational" to "1–3 yrs", "experienced" to "3+ yrs", "returning" to "Returning"), setOfNotNull(a["experience"])) { pick("experience", it) }
}

@Composable
private fun PageGoals(a: RiderAnswers, pick: (String, String) -> Unit, toggle: (String, String) -> Unit) {
    FieldLabel("MAIN GOAL?")
    Chips(RiderAnswers.GOALS.map { it.first to (RiderAnswers.GOAL_SHORT[it.first] ?: it.first) }, setOfNotNull(a["primary"]), columns = 2) { pick("primary", it) }
    FieldLabel("SECONDARY", optional = true)
    Chips(RiderAnswers.GOALS.filter { it.first != a["primary"] && it.first != "other" }.map { it.first to (RiderAnswers.GOAL_SHORT[it.first] ?: it.first) }, a.list("goals").filter { it != a["primary"] }.toSet(), columns = 3, small = true) { toggle("goals", it) }
    if (a["primary"] != null) {
        FieldLabel("IN 3 MONTHS?")
        Chips(RiderProfile.successOptions(a), setOfNotNull(a["success"]), columns = 2) { pick("success", it) }
    }
}

@Composable
private fun PageRoutine(a: RiderAnswers, pick: (String, String) -> Unit, toggle: (String, String) -> Unit, changed: () -> Unit) {
    var more by remember { mutableStateOf(a.list("rest").isNotEmpty() || a.list("otherDays").isNotEmpty()) }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(Modifier.weight(1f)) { FieldLabel("RIDES / WEEK NOW"); Chips(listOf("0" to "0–1", "2" to "2", "3" to "3", "4" to "4", "5" to "5+"), setOfNotNull(a["ridesNow"]), small = true) { pick("ridesNow", it) } }
        Column(Modifier.weight(1f)) { FieldLabel("DAYS YOU COULD RIDE"); Chips(listOf("2" to "2", "3" to "3", "4" to "4", "5" to "5+"), setOfNotNull(a["daysAvail"]), small = true) { pick("daysAvail", it) } }
    }
    FieldLabel("TYPICAL RIDE")
    SliderRow(a.int("typicalMin") ?: 60, 20, 240, 5, "min") { a["typicalMin"] = it.toString(); changed() }
    FieldLabel("OTHER EXERCISE")
    Chips(listOf("weights" to "Weights", "running" to "Running", "swim" to "Swimming", "sport" to "Sport", "none" to "None"), a.list("other").toSet(), columns = 3, small = true) { toggle("other", it) }
    TextButton(onClick = { more = !more }, contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)) { Text(if (more) "▾ Fewer options" else "▸ More options", color = D7.Cyan, fontSize = 12.sp) }
    if (more) {
        FieldLabel("LONGEST COMFORTABLE RIDE")
        SliderRow(a.int("longestMin") ?: 90, 30, 360, 10, "min") { a["longestMin"] = it.toString(); changed() }
        if (a.list("other").any { it != "none" }) { FieldLabel("DAYS FOR THAT EXERCISE"); Chips(RiderAnswers.DAYS.map { it to it }, a.list("otherDays").toSet(), small = true) { toggle("otherDays", it) } }
        FieldLabel("REST DAYS"); Chips(RiderAnswers.DAYS.map { it to it }, a.list("rest").toSet(), small = true) { toggle("rest", it) }
    }
}

@Composable
private fun PageZones(a: RiderAnswers, pick: (String, String) -> Unit, saved: () -> Unit, changed: () -> Unit) {
    FieldLabel("HEART RATE")
    Chips(listOf("know" to "I know my numbers", "estimate" to "Estimate for now", "later" to "Set up later"), setOfNotNull(a["hrMode"]), small = true) { pick("hrMode", it) }
    when (a["hrMode"]) {
        "know" -> D7Card(Modifier.padding(top = 6.dp)) {
            MetricRow(a, "maxHr", "Max HR", "bpm", 120, 220, saved, changed); MetricRow(a, "restHr", "Resting HR", "bpm", 30, 100, saved, changed); MetricRow(a, "lthr", "Threshold HR", "bpm", 110, 210, saved, changed)
            Muted("Fill any you know. \"Tested\" values become confirmed zones; the rest stay provisional.", 11)
        }
        "estimate" -> Muted("Zone 2 will be estimated from ${if (a.int("age") != null) "your age" else "a default max HR"} and marked GENERIC until a calibration ride.", 12)
        "later" -> Muted("Heart-rate guidance stays generic until you add numbers in the ME tab.", 12)
    }
    FieldLabel("POWER")
    Chips(listOf("know" to "I know my FTP", "unknown" to "Don't know yet"), setOfNotNull(a["pwMode"]), small = true) { pick("pwMode", it) }
    when (a["pwMode"]) {
        "know" -> D7Card(Modifier.padding(top = 6.dp)) { MetricRow(a, "ftp", "FTP", "W", 60, 450, saved, changed) }
        "unknown" -> Muted("Power is shown, not coached. An FTP test is offered after three rides — once the meter is verified under load.", 12)
    }
}

@Composable
private fun PagePrefs(a: RiderAnswers, pick: (String, String) -> Unit, toggle: (String, String) -> Unit, saved: () -> Unit, changed: () -> Unit) {
    var more by remember { mutableStateOf(a["tone"] != null || a["detail"] != null || a.metric("cadence") != null) }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(Modifier.weight(1f)) { FieldLabel("VOICE COACHING"); Chips(listOf("voice" to "On", "screen" to "Screen only"), setOfNotNull(a["voice"]), small = true) { pick("voice", it) } }
        Column(Modifier.weight(1f)) { FieldLabel("COACH SPEAKS"); Chips(listOf("quiet" to "Quiet", "important" to "Normal", "frequent" to "Often"), setOfNotNull(a["freq"]), small = true) { pick("freq", it) } }
    }
    FieldLabel("WHERE YOU RIDE")
    Chips(listOf("flat" to "Flat road", "hills" to "Hills", "indoor" to "Indoor", "mixed" to "Mixed"), a.list("env").toSet(), columns = 2, small = true) { toggle("env", it) }
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Column(Modifier.weight(1f)) { FieldLabel("CADENCE GUIDANCE"); Chips(listOf("yes" to "On", "no" to "Off"), setOfNotNull(a["cadAdvice"]), small = true) { pick("cadAdvice", it) } }
        Column(Modifier.weight(1f)) { FieldLabel("HOT CONDITIONS?"); Chips(listOf("yes" to "Yes", "no" to "No"), setOfNotNull(a["heat"]), small = true) { pick("heat", it) } }
    }
    TextButton(onClick = { more = !more }, contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)) { Text(if (more) "▾ Fewer options" else "▸ More options", color = D7.Cyan, fontSize = 12.sp) }
    if (more) {
        FieldLabel("TONE"); Chips(listOf("encouraging" to "Encouraging", "neutral" to "Neutral", "technical" to "Technical"), setOfNotNull(a["tone"]), small = true) { pick("tone", it) }
        FieldLabel("EXPLANATIONS"); Chips(listOf("simple" to "Simple", "detailed" to "Detailed"), setOfNotNull(a["detail"]), small = true) { pick("detail", it) }
        FieldLabel("NATURAL CADENCE, IF KNOWN"); MetricRow(a, "cadence", "Cadence", "rpm", 50, 120, saved, changed)
    }
}

// ------------------------------------------------------------------ Page 6: the derived coach (profile summary; also the ME tab)

@Composable
fun ProfileSummaryScreen(vm: DoctorViewModel, firstTime: Boolean, onEdit: (Int) -> Unit, onConfirm: () -> Unit, onBack: () -> Unit, onSignOut: (() -> Unit)? = null) {
    val r = vm.engine.rider ?: return
    val a = r.answers
    val c = RiderProfile.deriveSetup(a)
    val cal = java.util.Calendar.getInstance(); val today = (cal.get(java.util.Calendar.DAY_OF_WEEK) + 5) % 7
    val w = RiderProfile.recommend(a, c, r.feedback, today)
    fun v(x: String?, alt: String = "—") = x ?: alt
    fun m(k: String): String { val x = a.metric(k) ?: return "unknown"; return "${x.value} (${if (x.measured) "tested" else x.how})" }
    Column(Modifier.fillMaxSize().background(D7.Bg).verticalScroll(rememberScrollState()).padding(14.dp)) {
        D7TopBar(if (firstTime) "SET UP · 6 / 6" else "RIDER PROFILE", if (firstTime) "Back" else "Home", onBack)
        Row(verticalAlignment = Alignment.CenterVertically) { Avatar(r.initials, 40); Spacer(Modifier.width(10.dp)); Column { Headline(if (firstTime) "Your personal coach" else r.name, 22); if (r.isSample) SampleTag() } }
        Spacer(Modifier.height(10.dp))
        // 1 · the one thing to do: today's workout (why behind an expander)
        D7Card(accent = D7.Green) {
            CardTitle(if (firstTime) "YOUR FIRST WORKOUT" else "TODAY'S WORKOUT")
            Text(w.name, fontFamily = Archivo, fontWeight = FontWeight.ExtraBold, fontSize = 18.sp, lineHeight = 22.sp, color = D7.Fg)
            Text("${w.minutes} min · ${w.hrLo}–${w.hrHi} bpm${if (w.pwLo != null) " · ${w.pwLo}–${w.pwHi} W" else ""}", fontFamily = PlexMono, fontSize = 12.sp, color = D7.Cyan, modifier = Modifier.padding(vertical = 3.dp))
            w.why.firstOrNull()?.let { Text(it, fontSize = 13.sp, lineHeight = 18.sp, color = D7.Fg) }
            if (w.why.size > 1) Expander("Why this workout?") { Bullets(w.why.drop(1)) }
        }
        // 2 · the targets the coach will hold you to — one line each, confidence as a tag
        D7Card(Modifier.padding(top = 8.dp)) {
            CardTitle("YOUR TARGETS")
            Row(verticalAlignment = Alignment.CenterVertically) { Text("Zone 2 ${c.hrTargetLo}–${c.hrTargetHi} bpm", fontSize = 15.sp, color = D7.Fg, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f)); ConfidenceTag(c.zoneConfidence) }
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 3.dp)) {
                Text(if (c.powerCoaching) "Power ${c.powerLo}–${c.powerHi} W" else "Power targets off until FTP is known", fontSize = 13.sp, color = if (c.powerCoaching) D7.Fg else D7.Mut, modifier = Modifier.weight(1f))
                if (c.powerCoaching) { if (c.ftpMeasured) Tag("CONFIRMED", D7.Green) else Tag("PROVISIONAL", D7.Amber) }
            }
            Text("Cadence ${if (c.cadenceEnabled) "${c.cadLow}–${c.cadHigh} rpm" else "not coached"} · warm-up ${c.warmupSec / 60} min · cool-down ${c.cooldownSec / 60} min", fontSize = 12.sp, color = D7.Mut, modifier = Modifier.padding(top = 3.dp))
            Expander("Why these targets?") {
                Text(c.zoneConfidenceText, fontSize = 12.sp, lineHeight = 16.sp, color = D7.Mut)
                Spacer(Modifier.height(4.dp))
                c.rules.forEach { Text(it.what, fontSize = 12.sp, color = D7.Fg, fontWeight = FontWeight.Bold); Text(it.because, fontSize = 11.sp, lineHeight = 14.sp, color = D7.Mut, modifier = Modifier.padding(bottom = 4.dp)) }
            }
        }
        // 3 · progress: what the coach has learned so far (real rides only)
        if (!firstTime) {
            val l = remember { vm.engine.learned() }
            D7Card(Modifier.padding(top = 8.dp), accent = D7.Violet) {
                CardTitle("YOUR PROGRESS · ${l.rides} REAL RIDE${if (l.rides == 1) "" else "S"}")
                if (l.rides == 0) Text("Your first real ride starts the record. Simulated rides never count.", fontSize = 13.sp, lineHeight = 18.sp, color = D7.Fg)
                else {
                    l.inBandTrend?.let { Text("Zone discipline: $it", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = D7.Fg) }
                    Row(Modifier.fillMaxWidth().padding(top = 6.dp)) {
                        l.naturalCadence?.let { Column(Modifier.weight(1f)) { Text("$it", fontFamily = Rajdhani, fontWeight = FontWeight.SemiBold, fontSize = 24.sp, color = D7.Fg); Text("RPM NATURAL", fontFamily = PlexMono, fontSize = 9.sp, color = D7.Mut) } }
                        l.longestRideMin?.let { Column(Modifier.weight(1f)) { Text("$it", fontFamily = Rajdhani, fontWeight = FontWeight.SemiBold, fontSize = 24.sp, color = D7.Fg); Text("MIN LONGEST", fontFamily = PlexMono, fontSize = 9.sp, color = D7.Mut) } }
                        l.hrAtTypicalEffort?.let { Column(Modifier.weight(1f)) { Text("$it", fontFamily = Rajdhani, fontWeight = FontWeight.SemiBold, fontSize = 24.sp, color = D7.Fg); Text("BPM USUAL", fontFamily = PlexMono, fontSize = 9.sp, color = D7.Mut) } }
                    }
                }
                if (com.rashed.bikesensordoctor.core.Calibration.zonesTooLow(r.feedback)) Text("Your zones may be too low — three easy rides sat above the band. Ride the guided threshold test.", fontSize = 13.sp, lineHeight = 18.sp, color = D7.Amber, modifier = Modifier.padding(top = 6.dp))
                Expander("Details") {
                    KeyValue(listOfNotNull(
                        l.sustainablePowerW?.let { "Sustainable power" to "$it W best 20 min (verified meter)" },
                        l.recoveryBpm?.let { "Recovery" to "HR falls $it bpm in the first minute (median)" },
                    ))
                    val pf = a.metric("ftp"); val pl = a.metric("lthr")
                    EstimateCard(com.rashed.bikesensordoctor.core.MetricKind.FTP, pf?.value, pf?.measured == true, remember { vm.engine.estimate(com.rashed.bikesensordoctor.core.MetricKind.FTP) }, Modifier.padding(top = 6.dp))
                    EstimateCard(com.rashed.bikesensordoctor.core.MetricKind.THRESHOLD_HR, pl?.value, pl?.measured == true, remember { vm.engine.estimate(com.rashed.bikesensordoctor.core.MetricKind.THRESHOLD_HR) }, Modifier.padding(top = 6.dp))
                }
            }
        }
        // 4 · the profile itself and what is still unknown — on request
        Expander("Your profile", tag = "exp_profile") {
            KeyValue(listOf(
                "Goal" to ((RiderAnswers.GOAL_SHORT[RiderProfile.primaryGoal(a)] ?: "—") + (a.list("goals").drop(1).takeIf { it.isNotEmpty() }?.let { " +${it.size}" } ?: "") + (RiderProfile.successText(a)?.let { " · $it" } ?: "")),
                "You" to "${v(a["age"])} y · ${v(a["heightCm"])} cm · ${v(a["weightKg"])} kg · ${v(a["experience"])}",
                "Routine" to "${v(a["ridesNow"])} rides/wk now · ${v(a["daysAvail"])} days possible · ${v(a["typicalMin"])} min typical" + a.list("other").filter { it != "none" }.takeIf { it.isNotEmpty() }?.let { " · " + it.joinToString(", ") }.orEmpty(),
                "Heart rate" to "max ${m("maxHr")} · rest ${m("restHr")} · threshold ${m("lthr")}",
                "Power" to "FTP ${m("ftp")}",
                "Coaching" to "${v(a["voice"])} · ${v(a["freq"])} · cadence ${v(a["cadAdvice"])}${if (a["heat"] == "yes") " · hot conditions" else ""}",
            ))
            Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                listOf(0 to "you", 1 to "goals", 2 to "routine", 3 to "zones", 4 to "prefs").forEach { (i, l) -> TextButton(onClick = { onEdit(i) }, contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 4.dp)) { Text("edit $l", color = D7.Cyan, fontSize = 11.sp) } }
            }
        }
        Expander("Still to learn") { Bullets(RiderProfile.needs(a, c).take(3)) }
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            if (firstTime) SecondaryButton("‹ BACK", Modifier.weight(1f), onClick = onBack)
            PrimaryButton(if (firstTime) "START RIDING" else "SAVE", Modifier.weight(1.4f).testTag("confirm_profile"), onClick = onConfirm)
        }
        if (!firstTime) {
            Spacer(Modifier.height(8.dp))
            Row { TextButton(onClick = { onEdit(0) }) { Text("Redo my onboarding", color = D7.Mut, fontSize = 12.sp) }; if (onSignOut != null) TextButton(onClick = onSignOut) { Text("Sign out", color = D7.Mut, fontSize = 12.sp) } }
        }
        Spacer(Modifier.height(16.dp))
    }
}
