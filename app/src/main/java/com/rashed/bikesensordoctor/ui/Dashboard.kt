package com.rashed.bikesensordoctor.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rashed.bikesensordoctor.core.CoachMode
import com.rashed.bikesensordoctor.core.CueType
import com.rashed.bikesensordoctor.core.Phase
import com.rashed.bikesensordoctor.core.TargetStatus
import com.rashed.bikesensordoctor.core.Targets
import com.rashed.bikesensordoctor.core.Health
import com.rashed.bikesensordoctor.core.PowerZones
import com.rashed.bikesensordoctor.core.RideStats
import com.rashed.bikesensordoctor.core.RideSummary
import com.rashed.bikesensordoctor.ride.Dashboard
import com.rashed.bikesensordoctor.ride.Prefs
import com.rashed.bikesensordoctor.ride.RideEngine
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

// Premium dark sports palette
private val Ink = Color(0xFF05090B)
private val Panel = Color(0xFF0D161B)
private val Cyan = Color(0xFF34E7E4)
private val Amber = Color(0xFFFFB64D)
private val Green = Color(0xFF53E08B)
private val Red = Color(0xFFFF5A5A)
private val Violet = Color(0xFF9B8CFF)
private val Dim = Color(0xFF6B828C)

// zone colours Z1..Z7
private val zoneColors = listOf(Color(0xFF7E8C93), Cyan, Green, Color(0xFF9CDB3C), Amber, Color(0xFFFF8A3D), Red)
private fun zoneColor(z: Int) = if (z in 1..7) zoneColors[z - 1] else Dim

enum class Screen { SIGN_IN, SWITCH, WELCOME, ONBOARD, PROFILE, HOME, CLUB, BOARD, MEMBER, POST_RIDE, DASHBOARD, COACH, HISTORY, REPORT, SETTINGS, ADD_HR, DIAGNOSE, VERIFY_POWER, SIMULATION }

/** Where the app opens: sign-in without a rider, onboarding until the profile is done (or skipped), else Home. A live ride goes straight to the dashboard. */
private fun startScreen(vm: DoctorViewModel): Screen {
    val r = vm.engine.rider ?: return Screen.SIGN_IN
    if (vm.engine.dash.value.rideState != RideStats.State.IDLE) return Screen.DASHBOARD
    if (r.completed) return Screen.HOME
    return if (r.answers.isEmpty) Screen.WELCOME else Screen.ONBOARD
}

@Composable
fun BikeComputerApp(vm: DoctorViewModel, onKeepScreenOnChanged: () -> Unit, onBatteryOptimization: () -> Unit, notice: String? = null, onNotice: () -> Unit = {}) {
    var screen by remember { mutableStateOf(startScreen(vm)) }
    var reportRide by remember { mutableStateOf<Long?>(null) }
    var page by remember { mutableStateOf(vm.engine.rider?.page?.coerceIn(0, 4) ?: 0) }
    var member by remember { mutableStateOf("") }
    var profileFirstTime by remember { mutableStateOf(true) }
    val d by vm.engine.dash.collectAsStateWithLifecycle()
    val root = if (vm.engine.rider == null) Screen.SIGN_IN else if (vm.engine.rider?.completed == true) Screen.HOME else Screen.WELCOME
    // a finished ride with a profile → post-ride questions (once)
    val result = d.lastResult
    androidx.compose.runtime.LaunchedEffect(result) { if (result != null && screen != Screen.POST_RIDE) screen = Screen.POST_RIDE }
    // Back goes to the parent screen; on the root it leaves the app as usual
    val parent: Screen? = when (screen) {
        Screen.SIGN_IN, Screen.HOME, Screen.WELCOME -> null
        Screen.SWITCH -> root
        Screen.ONBOARD -> if (page > 0) Screen.ONBOARD else Screen.WELCOME
        Screen.PROFILE -> if (profileFirstTime) Screen.ONBOARD else Screen.HOME
        Screen.CLUB, Screen.BOARD, Screen.POST_RIDE, Screen.DASHBOARD -> root
        Screen.MEMBER -> Screen.CLUB
        Screen.COACH, Screen.HISTORY -> if (d.rideState != RideStats.State.IDLE) Screen.DASHBOARD else root
        Screen.REPORT -> Screen.HISTORY
        Screen.SETTINGS -> if (d.rideState != RideStats.State.IDLE) Screen.DASHBOARD else root
        Screen.ADD_HR, Screen.DIAGNOSE, Screen.VERIFY_POWER, Screen.SIMULATION -> Screen.SETTINGS
    }
    androidx.activity.compose.BackHandler(enabled = parent != null) {
        if (screen == Screen.ONBOARD && page > 0) page-- else if (screen == Screen.POST_RIDE) { vm.engine.clearResult(); screen = root } else parent?.let { screen = it }
    }
    val goTab: (String) -> Unit = { t -> screen = when (t) { "CLUB" -> Screen.CLUB; "BOARD" -> Screen.BOARD; "ME" -> { profileFirstTime = false; Screen.PROFILE }; else -> Screen.HOME } }
    val toRoot = { screen = startScreen(vm) }
    when (screen) {
        Screen.SIGN_IN -> SignInScreen(vm, switching = false, onDone = { page = vm.engine.rider?.page?.coerceIn(0, 4) ?: 0; toRoot() }, onCancel = null)
        Screen.SWITCH -> SignInScreen(vm, switching = true, onDone = { page = vm.engine.rider?.page?.coerceIn(0, 4) ?: 0; toRoot() }, onCancel = { screen = root })
        Screen.WELCOME -> WelcomeScreen(vm, onStart = { page = vm.engine.rider?.page?.coerceIn(0, 4) ?: 0; screen = Screen.ONBOARD },
            onSkip = { vm.engine.rider?.let { r -> com.rashed.bikesensordoctor.core.RiderProfile.skipAll(r.answers); r.completed = true; vm.engine.saveRider() }; screen = Screen.HOME }, onSwitch = { screen = Screen.SWITCH })
        Screen.ONBOARD -> OnboardingScreen(vm, page, onPage = { page = it }, onFinished = { profileFirstTime = vm.engine.rider?.completed != true; screen = Screen.PROFILE })
        Screen.PROFILE -> ProfileSummaryScreen(vm, firstTime = profileFirstTime, onEdit = { page = it; screen = Screen.ONBOARD },
            onConfirm = { vm.engine.rider?.let { r -> r.completed = true; r.page = 5; vm.engine.saveRider() }; screen = Screen.HOME },
            onBack = { if (profileFirstTime) { page = 4; screen = Screen.ONBOARD } else screen = Screen.HOME },
            onSignOut = { if (vm.engine.signOut()) screen = Screen.SIGN_IN })
        Screen.HOME -> HomeScreen(vm, onStartRide = { screen = Screen.DASHBOARD }, onSwitch = { screen = Screen.SWITCH }, onProfile = { profileFirstTime = true; page = 0; screen = Screen.ONBOARD },
            onTab = goTab, onHistory = { screen = Screen.HISTORY }, onSettings = { screen = Screen.SETTINGS })
        Screen.CLUB -> ClubScreen(vm, onTab = goTab, onMember = { member = it; screen = Screen.MEMBER })
        Screen.BOARD -> BoardScreen(vm, onTab = goTab)
        Screen.MEMBER -> MemberScreen(vm, member) { screen = Screen.CLUB }
        Screen.POST_RIDE -> { val res = result; if (res != null) PostRideScreen(vm, res, onDone = { vm.engine.clearResult(); screen = Screen.HOME }) else screen = root }
        Screen.DASHBOARD -> DashboardScreen(vm, onCoach = { screen = Screen.COACH }, onHistory = { screen = Screen.HISTORY }, onSettings = { screen = Screen.SETTINGS }, onHome = { screen = root }, notice = notice, onNotice = onNotice)
        Screen.COACH -> CoachScreen(vm) { screen = Screen.DASHBOARD }
        Screen.HISTORY -> HistoryScreen(vm, onBack = { screen = parent ?: root }, onOpen = { reportRide = it; screen = Screen.REPORT })
        Screen.REPORT -> ReportScreen(vm, reportRide) { screen = Screen.HISTORY }
        Screen.SETTINGS -> SettingsScreen(vm, onBack = { screen = parent ?: root }, onDiagnose = { screen = Screen.DIAGNOSE }, onAddHr = { screen = Screen.ADD_HR }, onVerifyPower = { screen = Screen.VERIFY_POWER }, onKeepScreenOnChanged, onBatteryOptimization, onSimulation = { screen = Screen.SIMULATION })
        Screen.VERIFY_POWER -> VerifyPowerScreen(vm) { screen = Screen.SETTINGS }
        Screen.ADD_HR -> AddHrScreen(vm) { screen = Screen.SETTINGS }
        Screen.DIAGNOSE -> DiagnoseScreen(vm) { screen = Screen.SETTINGS }
        Screen.SIMULATION -> SimulationScreen(vm, onBack = { screen = Screen.SETTINGS }, onRide = { screen = Screen.DASHBOARD })
    }
}

// ------------------------------------------------------------------ Dashboard (Design 7 — AI Scientific Coach)

/** Everything the screen needs to indicate, derived once per frame from the engine snapshot via core/Targets. */
private class D7State(d: Dashboard, cue: com.rashed.bikesensordoctor.core.CoachCue, prefs: Prefs) {
    val mode = runCatching { CoachMode.valueOf(d.coachMode) }.getOrDefault(CoachMode.FREE)
    val targetZone = Targets.targetZone(mode)
    val ftp = prefs.ftpW; val maxHr = prefs.maxHr
    val powerMax = Targets.powerGaugeMaxW(ftp)
    val tg = d.targets
    val hrMaxGauge = maxOf(d.hrGaugeMax, 120)
    val powerStatus = if (tg != null && tg.pwLo != null && tg.pwHi != null) bandStatus(d.powerW?.takeIf { it > 0 }, tg.pwLo, tg.pwHi) else Targets.power(d.powerW, ftp, targetZone)
    val cadLow = tg?.cadLo ?: prefs.cadenceLow; val cadHigh = tg?.cadHi ?: prefs.cadenceHigh
    val cadStatus = Targets.cadence(d.cadenceRpm, cadLow, cadHigh)
    val hrLive = if (d.hrConnected || d.simulated) d.hrBpm else null
    val hrStatus = if (tg != null) bandStatus(hrLive, tg.hrLo, tg.hrHi) else if (d.hrConnected || d.simulated) Targets.hr(d.hrBpm, maxHr, targetZone) else TargetStatus.UNKNOWN
    val powerPct = Targets.powerZonePercent(d.powerW, ftp)
    val hrPct = Targets.hrZonePercent(d.hrBpm, hrMaxGauge)
    // v0.8 TGT bands as gauge fractions (move with the phase ramps); null when no workout is active
    val powerBand: Pair<Float, Float>? = tg?.let { t -> if (t.pwLo != null && t.pwHi != null) (t.pwLo.toFloat() / powerMax) to (t.pwHi.toFloat() / powerMax) else null }
    val hrBand: Pair<Float, Float>? = tg?.let { t -> (t.hrLo.toFloat() / hrMaxGauge) to (t.hrHi.toFloat() / hrMaxGauge) }
    val powerCoached = tg == null || (tg.pwLo != null)
    val zoneTag = runCatching { com.rashed.bikesensordoctor.core.ZoneConfidence.valueOf(d.zoneConfidence) }.getOrDefault(com.rashed.bikesensordoctor.core.ZoneConfidence.GENERIC)

    // coaching presentation
    val signal = d.signal
    val coachActive = mode != CoachMode.FREE && cue.type != CueType.NONE && cue.type != CueType.NO_HR && cue.type != CueType.NO_POWER
    val coachColor: Color = when (cue.type) {
        CueType.QUIET -> D7.Faint
        CueType.KEEP_IT_UP -> D7.Green
        CueType.PEDAL_FASTER, CueType.PUSH_HARDER, CueType.WORK -> D7.Cyan
        CueType.EASE_OFF, CueType.PEDAL_SLOWER -> D7.Amber
        CueType.RECOVER, CueType.WARMUP, CueType.COOLDOWN -> D7.Violet
        else -> D7.Faint
    }
    val shape = Targets.coachShape(cue.type)
    val direction: Int? = if (coachActive) Targets.coachDirection(cue.type) else null
    val headline = when {
        mode == CoachMode.FREE -> "COACH OFF"
        cue.type == CueType.NONE -> "COACH READY"
        else -> cue.headline
    }
    val detail = when {
        mode == CoachMode.FREE -> "Tap to pick a mode: Zone 2, cadence, endurance or intervals"
        cue.type == CueType.NONE -> if (d.rideState == RideStats.State.RUNNING) "Watching your ${if (mode == CoachMode.CADENCE) "cadence" else "effort"} against the target" else "Press START — coaching runs during the ride"
        else -> cue.detail
    }
    val phaseLabel = when {
        d.plannedSec != null && d.elapsedMs >= d.plannedSec * 1000L -> "DONE · PRESS FINISH"
        d.phase == Phase.WARMUP -> "WARM-UP ${RideEngine.fmtDuration(d.warmupRemainingSec * 1000L)}"
        d.phase == Phase.MAIN -> if (d.plannedSec != null) "MAIN · ${RideEngine.fmtDuration(((d.plannedSec * 1000L) - d.elapsedMs).coerceAtLeast(0))} left" else "MAIN"
        d.phase == Phase.RECOVERY -> "RECOVERY"
        else -> if (d.plannedSec != null) "COOL-DOWN · ${RideEngine.fmtDuration(((d.plannedSec * 1000L) - d.elapsedMs).coerceAtLeast(0))}" else "COOL-DOWN"
    }
}

private fun bandStatus(v: Int?, lo: Int, hi: Int): TargetStatus = when { v == null -> TargetStatus.UNKNOWN; v < lo -> TargetStatus.BELOW; v > hi -> TargetStatus.ABOVE; else -> TargetStatus.ON }

private fun statusText(s: TargetStatus, kind: String, signal: RideStats.SignalState = RideStats.SignalState.FRESH) = when (s) {
    TargetStatus.BELOW -> if (kind == "cad") "BELOW RANGE" else "BELOW TGT"
    TargetStatus.ABOVE -> if (kind == "cad") "ABOVE RANGE" else "ABOVE TGT"
    TargetStatus.ON -> "ON TARGET"
    TargetStatus.UNKNOWN -> when (kind) {
        "hr" -> "NO STRAP"
        // P0-5: a valid zero is named as such; missing data is never dressed up as a value
        else -> when (signal) { RideStats.SignalState.STALE -> "NO SIGNAL"; RideStats.SignalState.NONE -> "NO SENSOR"; else -> if (kind == "cad") "NOT TURNING" else "COASTING" }
    }
}

@Composable
fun DashboardScreen(vm: DoctorViewModel, onCoach: () -> Unit, onHistory: () -> Unit, onSettings: () -> Unit, onHome: () -> Unit = {}, notice: String? = null, onNotice: () -> Unit = {}) {
    val d by vm.engine.dash.collectAsStateWithLifecycle()
    val cue by vm.engine.cue.collectAsStateWithLifecycle()
    val prefs = vm.engine.prefs
    val st = D7State(d, cue, prefs)
    var confirmFinish by remember { mutableStateOf(false) }

    BoxWithConstraints(Modifier.fillMaxSize().background(D7.Bg)) {
        val landscape = maxWidth > maxHeight
        if (!landscape) {
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 14.dp, vertical = 8.dp)) {
                if (notice != null && !d.simulated) Text(notice, fontFamily = PlexMono, fontSize = 11.sp, color = D7.Amber, modifier = Modifier.fillMaxWidth().background(D7.Amber.copy(alpha = 0.12f), RoundedCornerShape(8.dp)).clickable { onNotice() }.padding(8.dp).testTag("bt_notice"))
                Header(d, st) { vm.engine.sensor.recoverNow() }
                Spacer(Modifier.height(6.dp))
                Gauges(d, st)
                Spacer(Modifier.height(14.dp))
                CoachBox(st.headline, st.detail, st.coachColor, st.shape, st.direction, st.coachActive, onCoach)
                Spacer(Modifier.height(12.dp))
                LowerSection(d, st, prefs)
                Spacer(Modifier.height(14.dp))
                Controls(d, onCoach, onHistory, onSettings, onStart = { vm.engine.startRide() }, onPause = { vm.engine.pauseRide() }, onFinish = { confirmFinish = true }, onCooldown = { vm.engine.requestCooldown() }, onHome = onHome)
            }
        } else {
            Row(Modifier.fillMaxSize().padding(horizontal = 14.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                    Header(d, st) { vm.engine.sensor.recoverNow() }
                    Spacer(Modifier.height(6.dp))
                    Gauges(d, st)
                }
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
                    CoachBox(st.headline, st.detail, st.coachColor, st.shape, st.direction, st.coachActive, onCoach)
                    Spacer(Modifier.height(12.dp))
                    LowerSection(d, st, prefs)
                    Spacer(Modifier.height(14.dp))
                    Controls(d, onCoach, onHistory, onSettings, onStart = { vm.engine.startRide() }, onPause = { vm.engine.pauseRide() }, onFinish = { confirmFinish = true }, onCooldown = { vm.engine.requestCooldown() }, onHome = onHome)
                }
            }
        }
    }

    if (confirmFinish) AlertDialog(
        onDismissRequest = { confirmFinish = false },
        containerColor = D7.Panel2,
        title = { Text("Finish ride?") },
        text = { Text("${RideEngine.fmtDuration(d.elapsedMs)} · avg ${d.avgPowerW} W · max ${d.maxPowerW} W — saved to History.") },
        confirmButton = { Button(onClick = { confirmFinish = false; vm.engine.finishRide() }, modifier = Modifier.testTag("confirm_finish")) { Text("FINISH & SAVE") } },
        dismissButton = { TextButton(onClick = { confirmFinish = false }) { Text("Keep riding") } },
    )
}

/** 1 · Header: LIVE dot + link state (tap to reconnect), ride time, title, divider, coach-colour bar. */
@Composable
private fun Header(d: Dashboard, st: D7State, onReconnect: () -> Unit) {
    val live = d.health == Health.CONNECTED_LIVE || d.health == Health.CONNECTED_IDLE || d.simulated
    val (dot, text) = when {
        d.simulated -> D7.Amber to "SIMULATED"
        d.health == Health.CONNECTED_LIVE -> D7.Green to "LIVE"
        d.health == Health.CONNECTED_IDLE -> D7.Cyan to "READY"
        d.health == Health.RECONNECTING || d.health == Health.SEARCHING || d.health == Health.LINK_SILENT -> D7.Amber to "CONNECTING"
        else -> D7.Red to "OFFLINE"
    }
    Column {
        Row(Modifier.fillMaxWidth().clickable { if (!live) onReconnect() }, verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).background(dot, CircleShape))
            Spacer(Modifier.width(6.dp))
            Text(buildString {
                append(text)
                if (d.riderName.isNotEmpty()) append(" · ${d.riderName.uppercase()}")
                d.batteryPct?.let { append(" · BAT $it%") }
                if (!live && d.healthText.isNotEmpty()) append(" · tap to retry")
            }, fontFamily = PlexMono, fontSize = 10.sp, color = D7.Mut, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            Text("T ${RideEngine.fmtDuration(d.elapsedMs)}", fontFamily = PlexMono, fontSize = 12.sp, color = if (d.rideState == RideStats.State.RUNNING) D7.Fg else D7.Mut)
        }
        Spacer(Modifier.height(6.dp))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("SCIENTIFIC COACH", fontFamily = PlexMono, fontSize = 13.sp, color = D7.Cyan, letterSpacing = 2.sp, maxLines = 1, softWrap = false, modifier = Modifier.weight(1f))
            if (d.rideState != RideStats.State.IDLE) Text(st.phaseLabel, fontFamily = PlexMono, fontWeight = FontWeight.Bold, fontSize = 10.sp, maxLines = 1,
                color = if (d.phase == Phase.MAIN) D7.Green else D7.Violet)
        }
        Spacer(Modifier.height(4.dp))
        // trust tags on their own line so they never squeeze the title: power verification · zone confidence
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text(if (d.workoutName.isNotEmpty() && d.rideState != RideStats.State.IDLE) d.workoutName.uppercase() else "", fontFamily = PlexMono, fontSize = 9.sp, color = D7.Mut, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            if (!d.powerVerified) Tag("POWER UNVERIFIED", D7.Amber)
            Spacer(Modifier.width(4.dp))
            ConfidenceTag(st.zoneTag)
        }
        Spacer(Modifier.height(6.dp))
        Box(Modifier.fillMaxWidth().height(1.dp).background(D7.Line))
        Spacer(Modifier.height(2.dp))
        val bar by animateColorAsState(if (st.coachActive) st.coachColor else D7.Line, tween(400), label = "bar")
        Box(Modifier.fillMaxWidth().height(3.dp).background(bar, RoundedCornerShape(2.dp)))
    }
}

/** 2 + 3 · Large central power gauge, then RPM and HR side by side. */
@Composable
private fun Gauges(d: Dashboard, st: D7State) {
    Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
        TargetGauge(
            Modifier.fillMaxWidth(0.62f), value = d.powerW, max = st.powerMax,
            color = if (d.powerZone in 1..7) D7.powerZone(d.powerZone) else D7.Grey,
            targetFraction = Targets.powerTargetFraction(st.targetZone, st.ftp), zoneTicks = Targets.powerZoneTicks(st.ftp),
            sub = if (!st.powerCoached) "NOT COACHED" else if (d.powerZone in 1..7) "Z${d.powerZone} · ${st.powerPct ?: 0}%" else null,
            unit = "WATTS", big = true, status = if (st.powerCoached) st.powerStatus else TargetStatus.UNKNOWN,
            statusText = if (st.powerCoached) statusText(st.powerStatus, "pow", st.signal) else (if (d.powerVerified) "FTP UNKNOWN" else "UNVERIFIED"), showTgtLabel = true, band = st.powerBand,
        )
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
            TargetGauge(
                Modifier.weight(1f), value = d.cadenceRpm, max = Targets.CADENCE_GAUGE_MAX,
                color = if (d.backwards) D7.Red else D7.Violet,
                targetFraction = null, zoneTicks = FloatArray(0),
                band = st.cadLow.toFloat() / Targets.CADENCE_GAUGE_MAX to st.cadHigh.toFloat() / Targets.CADENCE_GAUGE_MAX,
                sub = if (d.backwards) "BACKWARDS" else "${st.cadLow}–${st.cadHigh}", unit = "RPM", big = false,
                status = st.cadStatus, statusText = statusText(st.cadStatus, "cad", st.signal), showTgtLabel = false,
            )
            TargetGauge(
                Modifier.weight(1f), value = st.hrLive, max = st.hrMaxGauge,
                color = if (st.hrLive != null && d.hrZone in 1..5) D7.hrZone(d.hrZone) else D7.Faint,
                targetFraction = Targets.hrTargetFraction(st.targetZone), zoneTicks = Targets.hrZoneTicks,
                sub = if (st.tg != null) "${st.tg.hrLo}–${st.tg.hrHi}" else if (st.hrLive != null && d.hrZone in 1..5) "Z${d.hrZone} · ${st.hrPct ?: 0}%" else null, unit = "BPM", big = false,
                status = st.hrStatus, statusText = statusText(st.hrStatus, "hr"), showTgtLabel = false, band = st.hrBand,
            )
        }
    }
}

/** 5–8 · Power zones, HR zones, power trend, ride statistics (Design 5, preserved). */
@Composable
private fun LowerSection(d: Dashboard, st: D7State, prefs: Prefs) {
    Column(Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().height(1.dp).background(D7.Line))
        Spacer(Modifier.height(10.dp))
        SectionLabel("POWER ZONES (target ▲ = Z${st.targetZone})")
        ZoneBand(listOf("Z1", "Z2", "Z3", "Z4", "Z5", "Z6", "Z7"), D7.powerZoneColors,
            currentFraction = d.powerW?.let { Targets.gaugeFraction(it, st.powerMax) }, targetFraction = Targets.powerTargetFraction(st.targetZone, st.ftp))
        Spacer(Modifier.height(10.dp))
        SectionLabel("HEART-RATE ZONES · ${st.zoneTag.name}" + (d.inZonePct?.let { " · IN BAND $it%" } ?: ""))
        ZoneBand(listOf("Z1", "Z2", "Z3", "Z4", "Z5"), D7.hrZoneColors,
            currentFraction = if (d.hrConnected) d.hrBpm?.let { Targets.gaugeFraction(it, st.maxHr) } else null, targetFraction = Targets.hrTargetFraction(st.targetZone))
        Spacer(Modifier.height(10.dp))
        SectionLabel("POWER TREND · last 5 min")
        Spacer(Modifier.height(4.dp))
        TrendChart(d.recentPower, st.ftp)
        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth()) {
            Stat(fmtKm(d.distanceKm, d.gpsFix), "DISTANCE", Modifier.weight(1.2f))
            Stat(d.power3sW?.let { "$it W" } ?: "—", "3S AVG", Modifier.weight(1f))
            Stat(fmtVi(d.variabilityIndex), "VARIABILITY", Modifier.weight(1f))
        }
        d.lastSavedRide?.takeIf { d.rideState == RideStats.State.IDLE || d.restoredRide }?.let {
            Text(it, fontFamily = PlexMono, fontSize = 11.sp, color = if (d.restoredRide) D7.Amber else D7.Green, modifier = Modifier.padding(top = 8.dp))
        }
        d.engineError?.let { err ->
            Text("Internal error (app kept running) — please send logs from Settings:\n$err", fontFamily = PlexMono, fontSize = 10.sp, color = D7.Red, modifier = Modifier.padding(top = 8.dp))
        }
        if (d.rideState != RideStats.State.IDLE) d.linkQualityPct?.let { q ->
            Text("LINK ${q}%" + (if (d.linkGaps > 0) " · ${d.linkGaps} gap(s), ${d.linkLostSec} s lost" else " · no gaps"), fontFamily = PlexMono, fontSize = 10.sp,
                color = if (q >= 95 && d.linkGaps == 0) D7.Faint else D7.Amber, modifier = Modifier.padding(top = 6.dp))
        }
    }
}

@Composable
private fun Controls(d: Dashboard, onCoach: () -> Unit, onHistory: () -> Unit, onSettings: () -> Unit, onStart: () -> Unit, onPause: () -> Unit, onFinish: () -> Unit, onCooldown: () -> Unit = {}, onHome: () -> Unit = {}) {
    if (d.rideState == RideStats.State.RUNNING && d.phase != Phase.COOLDOWN && d.coachMode != "FREE") {
        TextButton(onClick = onCooldown, Modifier.fillMaxWidth()) { Text("Start cool-down (no more 'push' cues)", color = D7.Violet, fontFamily = PlexMono, fontSize = 12.sp) }
    }
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        Box(Modifier.weight(1f)) {
            when (d.rideState) {
                RideStats.State.IDLE, RideStats.State.FINISHED -> BigButton("START", D7.Green, onStart, "btn_start")
                RideStats.State.RUNNING -> BigButton("PAUSE", D7.Amber, onPause, "btn_pause")
                RideStats.State.PAUSED -> BigButton("RESUME", D7.Green, onStart, "btn_resume")
            }
        }
        if (d.rideState == RideStats.State.RUNNING || d.rideState == RideStats.State.PAUSED)
            Box(Modifier.weight(1f)) { BigButton("FINISH", D7.Red, onFinish, "btn_finish") }
        Box(Modifier.width(104.dp)) { BigButton("COACH", D7.Violet, onCoach, "btn_coach", 16) }
    }
    Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        TextButton(onClick = onHome, modifier = Modifier.testTag("dash_home")) { Text("‹ Home", color = D7.Cyan) }
        TextButton(onClick = onHistory) { Text("History", color = D7.Cyan) }
        Spacer(Modifier.weight(1f))
        TextButton(onClick = onSettings) { Text("⚙ Settings", color = D7.Cyan) }
    }
}

@Composable
private fun BigButton(text: String, color: Color, onClick: () -> Unit, tag: String = "", size: Int = 19) {
    Button(onClick = onClick, Modifier.fillMaxWidth().height(60.dp).testTag(tag), shape = RoundedCornerShape(16.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 6.dp),
        colors = ButtonDefaults.buttonColors(containerColor = color, contentColor = D7.Ink)) {
        Text(text, fontFamily = Archivo, fontWeight = FontWeight.ExtraBold, fontSize = size.sp, maxLines = 1, softWrap = false)
    }
}

// ------------------------------------------------------------------ Coach

@Composable
fun CoachScreen(vm: DoctorViewModel, onBack: () -> Unit) {
    val d by vm.engine.dash.collectAsStateWithLifecycle()
    val cue by vm.engine.cue.collectAsStateWithLifecycle()
    val prefs = vm.engine.prefs
    var mode by remember { mutableStateOf(prefs.coachMode) }
    var voice by remember { mutableStateOf(prefs.coachVoice) }
    val modes = listOf("FREE" to "Free ride", "CADENCE" to "Cadence", "ZONE2" to "Zone 2", "ENDURANCE" to "Endurance", "INTERVAL" to "Intervals")

    val cueColor = when (cue.type) {
        CueType.EASE_OFF, CueType.RECOVER -> Amber
        CueType.PUSH_HARDER, CueType.WORK, CueType.KEEP_IT_UP -> Green
        CueType.PEDAL_FASTER, CueType.PEDAL_SLOWER -> Cyan
        CueType.NO_HR, CueType.NO_POWER -> Dim
        else -> Color.White
    }
    Column(Modifier.fillMaxSize().background(Ink).padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ Ride", color = Cyan, fontSize = 18.sp) }
            Text("Coach", fontSize = 24.sp, fontWeight = FontWeight.Black, color = Color.White)
        }
        Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(if (mode == "FREE") "FREE RIDE" else (cue.headline.ifEmpty { "READY" }),
                    fontSize = 44.sp, fontWeight = FontWeight.Black, color = cueColor, textAlign = TextAlign.Center, lineHeight = 48.sp)
                Spacer(Modifier.height(12.dp))
                Text(if (mode == "FREE") "No coaching — just ride." else cue.detail, fontSize = 18.sp, color = Color(0xFFBFD2DA), textAlign = TextAlign.Center)
                Spacer(Modifier.height(24.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                    MiniStat("${d.cadenceRpm ?: "—"}", "rpm", Violet)
                    MiniStat("${d.powerW ?: "—"}", "W", zoneColor(d.powerZone).takeIf { d.powerZone>0 } ?: Cyan)
                    MiniStat(if (d.hrConnected) "${d.hrBpm ?: "—"}" else "—", "bpm", Red)
                }
            }
        }
        Text("MODE", fontSize = 12.sp, color = Dim, fontWeight = FontWeight.Bold)
        Column(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            modes.chunked(3).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    row.forEach { (key, label) ->
                        val sel = mode == key
                        Box(Modifier.weight(1f).background(if (sel) Violet else Panel, RoundedCornerShape(12.dp))
                            .clickable { mode = key; prefs.coachMode = key; vm.engine.applyCoachConfig() }.padding(vertical = 12.dp), contentAlignment = Alignment.Center) {
                            Text(label, color = if (sel) Ink else Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp)
                        }
                    }
                    repeat(3 - row.size) { Box(Modifier.weight(1f)) {} }
                }
            }
        }
        if (mode == "ZONE2" && !d.hrConnected)
            Text("Zone 2 is most accurate with heart rate. Add a strap in Settings, or it will use power when you pedal under load.", fontSize = 12.sp, color = Amber, modifier = Modifier.padding(vertical = 4.dp))
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Spoken coaching", Modifier.weight(1f), fontSize = 16.sp, color = Color.White)
            Switch(checked = voice, onCheckedChange = { voice = it; prefs.coachVoice = it })
        }
    }
}

@Composable
private fun MiniStat(v: String, l: String, c: Color) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(v, fontSize = 32.sp, fontWeight = FontWeight.Black, color = c); Text(l, fontSize = 12.sp, color = Dim)
    }
}

// ------------------------------------------------------------------ Add HR

@Composable
fun AddHrScreen(vm: DoctorViewModel, onBack: () -> Unit) {
    val hr = vm.engine.hr
    val scanning by hr.scanning.collectAsStateWithLifecycle()
    val found by hr.scan.collectAsStateWithLifecycle()
    val st by hr.state.collectAsStateWithLifecycle()
    Column(Modifier.fillMaxSize().background(Ink).padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ Back", color = Cyan, fontSize = 18.sp) }
            Text("Add heart-rate sensor", fontSize = 22.sp, fontWeight = FontWeight.Black, color = Color.White)
        }
        Text("Works with any Bluetooth heart-rate strap, and with WHOOP (turn on \"Broadcast heart rate\" in the WHOOP app). " +
             "Apple Watch has no built-in broadcast — install a free HR-broadcaster watch app (e.g. one that exposes the standard Bluetooth Heart Rate service), start it, then scan here.",
            fontSize = 13.sp, color = Color(0xFFBFD2DA), modifier = Modifier.padding(vertical = 10.dp))
        if (st.connected) Card(Modifier.fillMaxWidth().padding(bottom = 8.dp)) {
            Column(Modifier.padding(12.dp)) {
                Text("Connected: ${st.name ?: st.address}", color = Green, fontWeight = FontWeight.Bold)
                Text("${st.bpm ?: "—"} bpm" + (st.batteryPct?.let { " · battery $it%" } ?: ""), color = Color.White, fontSize = 22.sp)
                TextButton(onClick = { vm.engine.forgetHr() }) { Text("Disconnect / forget", color = Red) }
            }
        }
        Button(onClick = { if (scanning) hr.stopScan() else hr.startScan() }, Modifier.fillMaxWidth().height(56.dp)) {
            Text(if (scanning) "Scanning… tap to stop" else "SCAN FOR HR SENSORS", fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.height(8.dp))
        LazyColumn {
            items(found, key = { it.address }) { dev ->
                Card(Modifier.fillMaxWidth().padding(vertical = 4.dp).clickable { vm.engine.connectHr(dev.address, dev.name) }) {
                    Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(dev.name ?: "(unnamed)", color = Color.White, fontWeight = FontWeight.Bold)
                            Text(dev.address, color = Dim, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
                        }
                        Text("${dev.rssi} dBm", color = Dim, fontSize = 12.sp)
                    }
                }
            }
        }
    }
}

// ------------------------------------------------------------------ History + Report

@Composable
fun HistoryScreen(vm: DoctorViewModel, onBack: () -> Unit, onOpen: (Long) -> Unit) {
    var rides by remember { mutableStateOf(vm.engine.history.list()) }
    val ctx = LocalContext.current
    var toDelete by remember { mutableStateOf<RideSummary?>(null) }
    Column(Modifier.fillMaxSize().background(Ink).padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ Back", color = Cyan, fontSize = 18.sp) }
            Text("History", fontSize = 24.sp, fontWeight = FontWeight.Black, color = Color.White)
            vm.engine.rider?.let { Text("  · ${it.name}", fontSize = 14.sp, color = Dim) }
        }
        if (rides.isEmpty()) Text("No rides yet. Press START on the dashboard.", color = Dim, modifier = Modifier.padding(top = 24.dp))
        LazyColumn {
            items(rides, key = { it.startedAtMs }) { r ->
                Card(Modifier.fillMaxWidth().padding(vertical = 5.dp).clickable { onOpen(r.startedAtMs) }) {
                    Column(Modifier.padding(12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(SimpleDateFormat("EEE d MMM · HH:mm", Locale.getDefault()).format(Date(r.startedAtMs)), fontSize = 14.sp, color = Color(0xFFBFD2DA), modifier = Modifier.weight(1f))
                            if (r.source == com.rashed.bikesensordoctor.core.RideSource.SIMULATED) SimTag() else if (r.distanceKm > 0) Text(String.format(Locale.US, "%.1f km", r.distanceKm), fontSize = 12.sp, color = Dim)
                            if (r.inZonePct >= 0) Text("  ${r.inZonePct}% in band", fontSize = 12.sp, color = Dim)
                        }
                        Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                            St(RideEngine.fmtDuration(r.durationMs), "time"); St("${r.avgPowerW}", "avg W"); St("${r.maxPowerW}", "max W"); St("${r.avgCadenceRpm}", "rpm"); St(String.format(Locale.US, "%.0f", r.energyKj), "kJ")
                        }
                        Row {
                            TextButton(onClick = { vm.shareRideCsv(ctx, r.startedAtMs) }) { Text("CSV") }
                            if (vm.engine.history.hasGpx(r.startedAtMs)) TextButton(onClick = { vm.shareRideGpx(ctx, r.startedAtMs) }) { Text("GPX") }
                            TextButton(onClick = { toDelete = r }) { Text("Delete", color = Red) }
                        }
                    }
                }
            }
        }
    }
    toDelete?.let { r ->
        AlertDialog(onDismissRequest = { toDelete = null }, containerColor = Panel, title = { Text("Delete this ride?") }, text = { Text("Cannot be undone.") },
            confirmButton = { TextButton(onClick = { vm.engine.history.delete(r.startedAtMs); rides = vm.engine.history.list(); toDelete = null }) { Text("Delete", color = Red) } },
            dismissButton = { TextButton(onClick = { toDelete = null }) { Text("Cancel") } })
    }
}

@Composable
fun ReportScreen(vm: DoctorViewModel, startedAtMs: Long?, onBack: () -> Unit) {
    val ride = remember(startedAtMs) { vm.engine.history.list().firstOrNull { it.startedAtMs == startedAtMs } }
    val report = remember(startedAtMs) { startedAtMs?.let { vm.engine.history.readReport(it) } }
    Column(Modifier.fillMaxSize().background(Ink).verticalScroll(rememberScrollState()).padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ History", color = Cyan, fontSize = 18.sp) }
            Text("Ride report", fontSize = 24.sp, fontWeight = FontWeight.Black, color = Color.White)
        }
        if (ride == null) { Text("Ride not found.", color = Dim); return@Column }
        Text(SimpleDateFormat("EEEE d MMM yyyy · HH:mm", Locale.getDefault()).format(Date(ride.startedAtMs)), color = Color(0xFFBFD2DA))
        Spacer(Modifier.height(12.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            St(RideEngine.fmtDuration(ride.durationMs), "time"); St("${ride.avgPowerW}", "avg W"); St("${ride.maxPowerW}", "max W")
        }
        Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            St("${ride.avgCadenceRpm}", "avg rpm"); St("${ride.maxCadenceRpm}", "max rpm"); St(String.format(Locale.US, "%.0f", ride.energyKj), "kJ")
        }
        report?.let { rep ->
            if (rep.avgHr > 0) { Spacer(Modifier.height(8.dp)); Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { St("${rep.avgHr}", "avg bpm"); St("${rep.maxHr}", "max bpm"); St("", "") } }
            Spacer(Modifier.height(16.dp)); Text("Time in power zones", color = Color.White, fontWeight = FontWeight.Bold)
            ZoneBars(rep.powerZoneSec.drop(1), (1..7).map { "Z$it" }, (1..7).map { zoneColor(it) })
            if (rep.hrZoneSec.drop(1).any { it > 0 }) {
                Spacer(Modifier.height(12.dp)); Text("Time in HR zones", color = Color.White, fontWeight = FontWeight.Bold)
                ZoneBars(rep.hrZoneSec.drop(1), (1..5).map { "Z$it" }, (1..5).map { zoneColor(it) })
            }
        }
        report?.linkVerdict?.let { v ->
            Spacer(Modifier.height(16.dp)); Text("Sensor link", color = Color.White, fontWeight = FontWeight.Bold)
            Text(v, color = if ((report.linkQualityPct ?: 0) >= 95 && report.linkGapCount == 0) Green else Amber, fontSize = 13.sp, lineHeight = 18.sp)
            report.gaps.take(8).forEachIndexed { i, g ->
                Text("Gap ${i + 1}: at ${RideEngine.fmtDuration(g.startMs - ride.startedAtMs)} for ${(g.endMs - g.startMs) / 1000} s — ${g.reason}; before it: ${if (g.rotatingBefore) "pedaling" else "cranks still"}, ${if (g.poweredBefore) "under load" else "0 W"}", color = Dim, fontSize = 12.sp, lineHeight = 16.sp)
            }
        }
        Spacer(Modifier.height(16.dp))
        Text(summaryText(ride, report), color = Color(0xFFBFD2DA), fontSize = 14.sp, lineHeight = 20.sp)
    }
}

private fun summaryText(r: RideSummary, rep: com.rashed.bikesensordoctor.ride.RideHistory.Report?): String {
    val b = StringBuilder()
    b.append("You rode ${RideEngine.fmtDuration(r.durationMs)} averaging ${r.avgPowerW} W")
    if (r.maxPowerW > 0) b.append(" (peak ${r.maxPowerW} W)")
    b.append(". ")
    if (r.avgPowerW == 0) b.append("No watts were recorded — ride under load (road or trainer) to capture power. ")
    rep?.let {
        val z2 = it.powerZoneSec.getOrElse(2) { 0 }; val total = it.powerZoneSec.sum().coerceAtLeast(1)
        if (z2 * 100 / total > 50) b.append("Most of your time was in Zone 2 — good endurance work. ")
        if (it.avgHr > 0) b.append("Average heart rate ${it.avgHr} bpm. ")
    }
    b.append("All figures are measured, not estimated.")
    return b.toString()
}

@Composable
private fun ZoneBars(secs: List<Int>, labels: List<String>, colors: List<Color>) {
    val total = secs.sum().coerceAtLeast(1)
    Column(Modifier.padding(top = 6.dp)) {
        secs.forEachIndexed { i, s ->
            Row(Modifier.fillMaxWidth().padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(labels[i], Modifier.width(32.dp), color = Dim, fontSize = 12.sp)
                Box(Modifier.weight(1f).height(16.dp).background(Panel, RoundedCornerShape(6.dp))) {
                    Box(Modifier.fillMaxWidth(s.toFloat() / total).height(16.dp).background(colors[i], RoundedCornerShape(6.dp)))
                }
                Text(RideEngine.fmtDuration(s * 1000L), Modifier.width(56.dp).padding(start = 6.dp), color = Color.White, fontSize = 12.sp)
            }
        }
    }
}

@Composable
private fun St(v: String, l: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(v, fontSize = 20.sp, fontWeight = FontWeight.Black, color = Color.White); Text(l, fontSize = 11.sp, color = Dim)
    }
}

// ------------------------------------------------------------------ Settings

@Composable
fun SettingsScreen(vm: DoctorViewModel, onBack: () -> Unit, onDiagnose: () -> Unit, onAddHr: () -> Unit, onVerifyPower: () -> Unit, onKeepScreenOnChanged: () -> Unit, onBatteryOptimization: () -> Unit, onSimulation: () -> Unit = {}) {
    val prefs = vm.engine.prefs
    val ctx = LocalContext.current
    val d by vm.engine.dash.collectAsStateWithLifecycle()
    var keepOn by remember { mutableStateOf(prefs.keepScreenOn) }
    var ftp by remember { mutableStateOf(prefs.ftpW) }
    var maxHr by remember { mutableStateOf(prefs.maxHr) }
    var ftpSet by remember { mutableStateOf(prefs.ftpSetByUser) }
    var maxHrSet by remember { mutableStateOf(prefs.maxHrSetByUser) }
    var cadOn by remember { mutableStateOf(prefs.cadenceCoaching) }
    var cadLow by remember { mutableStateOf(prefs.cadenceLow) }
    var cadHigh by remember { mutableStateOf(prefs.cadenceHigh) }
    var warmup by remember { mutableStateOf(prefs.warmupSec / 60) }
    val powerVerified = prefs.powerVerified
    Column(Modifier.fillMaxSize().background(Ink).verticalScroll(rememberScrollState()).padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ Back", color = Cyan, fontSize = 18.sp) }
            Text("Settings", fontSize = 24.sp, fontWeight = FontWeight.Black, color = Color.White)
        }
        vm.engine.rider?.let { r -> Text("Rider: ${r.name}" + (if (vm.engine.setup != null) " · zones and coaching come from the rider profile (ME tab)" else " · no profile yet, generic settings below apply"), fontSize = 13.sp, color = Dim) }
        Spacer(Modifier.height(10.dp))
        Button(onClick = onAddHr, Modifier.fillMaxWidth().height(56.dp), colors = ButtonDefaults.buttonColors(containerColor = Red, contentColor = Ink)) { Text("ADD HEART-RATE SENSOR (WHOOP / watch)", fontWeight = FontWeight.Bold, fontSize = 14.sp) }
        Spacer(Modifier.height(14.dp))

        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) { Text("Keep screen on", fontSize = 18.sp, color = Color.White); Text("During rides", fontSize = 13.sp, color = Dim) }
            Switch(checked = keepOn, onCheckedChange = { keepOn = it; prefs.keepScreenOn = it; onKeepScreenOnChanged() })
        }
        Spacer(Modifier.height(14.dp))
        // ---- P0: power verification status ----
        Text("Power meter", fontSize = 18.sp, color = Color.White)
        if (powerVerified) Text("✓ Verified under load: max ${prefs.powerVerifiedMaxW} W on ${SimpleDateFormat("d MMM HH:mm", Locale.getDefault()).format(Date(prefs.powerVerifiedAtMs))}", fontSize = 13.sp, color = Green)
        else Text("POWER UNVERIFIED — the sensor has only ever reported 0 W. Watts, zones and power coaching cannot be trusted until this passes.", fontSize = 13.sp, color = Amber)
        OutlinedButton(onClick = onVerifyPower, Modifier.fillMaxWidth().padding(top = 4.dp)) { Text(if (powerVerified) "Re-verify power under load" else "VERIFY POWER UNDER LOAD") }
        Spacer(Modifier.height(16.dp))

        // ---- P2 (partial): rider numbers, flagged until set ----
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("FTP: $ftp W", fontSize = 16.sp, color = Color.White)
            if (!ftpSet) UnverifiedTag()
        }
        Text(if (ftpSet) "Sets your power zones." else "This is a generic default, not your measured FTP. Power zones and power coaching are calibrated to a fictional rider until you set it.", fontSize = 13.sp, color = if (ftpSet) Dim else Amber)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 4.dp)) {
            OutlinedButton(onClick = { ftp = (ftp - 5).coerceAtLeast(50); prefs.ftpW = ftp; prefs.ftpSetByUser = true; ftpSet = true; vm.engine.applyCoachConfig() }) { Text("−5") }
            OutlinedButton(onClick = { ftp += 5; prefs.ftpW = ftp; prefs.ftpSetByUser = true; ftpSet = true; vm.engine.applyCoachConfig() }) { Text("+5") }
            if (!ftpSet) OutlinedButton(onClick = { prefs.ftpSetByUser = true; ftpSet = true }) { Text("Keep $ftp") }
        }
        Spacer(Modifier.height(14.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Max heart rate: $maxHr bpm", fontSize = 16.sp, color = Color.White)
            if (!maxHrSet) UnverifiedTag()
        }
        Text(if (maxHrSet) "Sets your heart-rate zones (Z2 = 60–70 % of this)." else "Generic default — not measured. Heart-rate zones and Zone 2 coaching are wrong until you set your real maximum.", fontSize = 13.sp, color = if (maxHrSet) Dim else Amber)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 4.dp)) {
            OutlinedButton(onClick = { maxHr = (maxHr - 1).coerceAtLeast(120); prefs.maxHr = maxHr; prefs.maxHrSetByUser = true; maxHrSet = true; vm.engine.applyCoachConfig() }) { Text("−1") }
            OutlinedButton(onClick = { maxHr += 1; prefs.maxHr = maxHr; prefs.maxHrSetByUser = true; maxHrSet = true; vm.engine.applyCoachConfig() }) { Text("+1") }
            if (!maxHrSet) OutlinedButton(onClick = { prefs.maxHrSetByUser = true; maxHrSet = true }) { Text("Keep $maxHr") }
        }
        Spacer(Modifier.height(16.dp))

        // ---- P1: coaching controls ----
        Text("Coaching", fontSize = 18.sp, color = Color.White)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) { Text("Cadence hints", fontSize = 16.sp, color = Color.White); Text("Only when effort is already on target", fontSize = 13.sp, color = Dim) }
            Switch(checked = cadOn, onCheckedChange = { cadOn = it; prefs.cadenceCoaching = it; vm.engine.applyCoachConfig() })
        }
        if (cadOn) {
            Text("Cadence range: $cadLow–$cadHigh rpm", fontSize = 15.sp, color = Color.White, modifier = Modifier.padding(top = 4.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(top = 4.dp)) {
                OutlinedButton(onClick = { cadLow = (cadLow - 5).coerceAtLeast(50); prefs.cadenceLow = cadLow; vm.engine.applyCoachConfig() }) { Text("low −5") }
                OutlinedButton(onClick = { cadLow = (cadLow + 5).coerceAtMost(cadHigh - 5); prefs.cadenceLow = cadLow; vm.engine.applyCoachConfig() }) { Text("low +5") }
                OutlinedButton(onClick = { cadHigh = (cadHigh - 5).coerceAtLeast(cadLow + 5); prefs.cadenceHigh = cadHigh; vm.engine.applyCoachConfig() }) { Text("high −5") }
                OutlinedButton(onClick = { cadHigh = (cadHigh + 5).coerceAtMost(130); prefs.cadenceHigh = cadHigh; vm.engine.applyCoachConfig() }) { Text("high +5") }
            }
        }
        Text("Warm-up: ${if (warmup == 0) "off" else "$warmup min"}", fontSize = 15.sp, color = Color.White, modifier = Modifier.padding(top = 10.dp))
        Text("No 'push harder' during the warm-up; only a safety 'ease off' if heart rate is far too high.", fontSize = 13.sp, color = Dim)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 4.dp)) {
            OutlinedButton(onClick = { warmup = (warmup - 1).coerceAtLeast(0); prefs.warmupSec = warmup * 60 }) { Text("−1 min") }
            OutlinedButton(onClick = { warmup = (warmup + 1).coerceAtMost(20); prefs.warmupSec = warmup * 60 }) { Text("+1 min") }
        }
        Spacer(Modifier.height(16.dp))
        Text("Connection test", fontSize = 18.sp, color = Color.White)
        Text("Leave the app open and connected for 30 min. Uptime resets to 0 on any drop.", fontSize = 13.sp, color = Dim)
        Text("Current uptime: ${RideEngine.fmtDuration(d.linkUptimeSec * 1000)}", fontSize = 20.sp, color = if (d.linkUptimeSec > 1800) Green else Cyan, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(10.dp))
        OutlinedButton(onClick = onBatteryOptimization, Modifier.fillMaxWidth()) { Text("Allow unrestricted battery use (keeps Bluetooth alive)") }
        Spacer(Modifier.height(16.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedButton(onClick = { vm.engine.sensor.recoverNow() }) { Text("Reconnect") }
            OutlinedButton(onClick = { vm.engine.shareLogs(ctx) }) { Text("Send logs") }
        }
        Spacer(Modifier.height(10.dp))
        TextButton(onClick = onDiagnose) { Text("Advanced: Diagnose & Repair sensor", color = Dim) }
        TextButton(onClick = onSimulation, modifier = Modifier.testTag("open_simulation")) { Text("Test tool: simulated sensors (SIMULATED rides)", color = Dim) }
        Spacer(Modifier.height(10.dp))
        Text("Bike Computer v0.8 · never writes to the sensor except notification subscriptions", fontSize = 11.sp, color = Dim)
    }
}

@Composable
private fun UnverifiedTag() {
    Box(Modifier.padding(start = 8.dp).background(Amber.copy(alpha = 0.18f), RoundedCornerShape(6.dp)).padding(horizontal = 6.dp, vertical = 2.dp)) {
        Text("UNVERIFIED DEFAULT", fontSize = 10.sp, color = Amber, fontWeight = FontWeight.Bold)
    }
}

// ------------------------------------------------------------------ Verify power under load (P0)

@Composable
fun VerifyPowerScreen(vm: DoctorViewModel, onBack: () -> Unit) {
    val d by vm.engine.dash.collectAsStateWithLifecycle()
    var verifier by remember { mutableStateOf<com.rashed.bikesensordoctor.core.LoadVerifier?>(null) }
    var result by remember { mutableStateOf<com.rashed.bikesensordoctor.core.LoadVerifier.Result?>(null) }
    // feed live samples into the verifier while it runs
    androidx.compose.runtime.DisposableEffect(verifier) {
        val v = verifier
        val listener: (com.rashed.bikesensordoctor.core.XdsSample, Long) -> Unit = { s, t -> v?.onSample(s, t) }
        if (v != null) vm.engine.sensor.addSampleListener(listener)
        onDispose { if (v != null) vm.engine.sensor.removeSampleListener(listener) }
    }
    androidx.compose.runtime.LaunchedEffect(verifier) {
        val v = verifier ?: return@LaunchedEffect
        while (true) {
            val r = v.result(System.currentTimeMillis()); result = r
            if (r.passed) { vm.engine.prefs.powerVerifiedAtMs = System.currentTimeMillis(); vm.engine.prefs.powerVerifiedMaxW = r.maxPowerW; vm.engine.log.add(com.rashed.bikesensordoctor.log.EventType.TEST, note = "Power verified under load: " + r.message()); verifier = null; break }
            if (r.status == com.rashed.bikesensordoctor.core.LoadVerifier.Status.TIMEOUT) { vm.engine.log.add(com.rashed.bikesensordoctor.log.EventType.TEST, note = "Power verification failed: " + r.message()); verifier = null; break }
            kotlinx.coroutines.delay(500)
        }
    }
    Column(Modifier.fillMaxSize().background(Ink).verticalScroll(rememberScrollState()).padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ Settings", color = Cyan, fontSize = 18.sp) }
            Text("Verify power", fontSize = 24.sp, fontWeight = FontWeight.Black, color = Color.White)
        }
        Text("Why: so far the XDS has only ever reported 0 W (free-spinning). This 60-second check proves it measures real watts. It passes only if at least 10 packets show ≥ 40 W while the cranks turn above 30 rpm.", fontSize = 14.sp, color = Color(0xFFBFD2DA), lineHeight = 20.sp)
        Spacer(Modifier.height(12.dp))
        Text("How: be on the road or on a trainer with resistance. Press START, then pedal normally for up to a minute.", fontSize = 14.sp, color = Color(0xFFBFD2DA), lineHeight = 20.sp)
        Spacer(Modifier.height(16.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            St("${d.powerW ?: "—"}", "W now"); St("${d.cadenceRpm ?: "—"}", "rpm now"); St(when (d.signal) { RideStats.SignalState.FRESH -> "live"; RideStats.SignalState.COASTING -> "0 W"; RideStats.SignalState.STALE -> "stale"; RideStats.SignalState.NONE -> "none" }, "signal")
        }
        Spacer(Modifier.height(16.dp))
        val r = result
        val running = verifier != null
        if (running || r != null) {
            val col = when (r?.status) { com.rashed.bikesensordoctor.core.LoadVerifier.Status.PASS -> Green; com.rashed.bikesensordoctor.core.LoadVerifier.Status.TIMEOUT -> Red; com.rashed.bikesensordoctor.core.LoadVerifier.Status.SPINNING_NO_LOAD -> Amber; else -> Cyan }
            Box(Modifier.fillMaxWidth().background(Panel, RoundedCornerShape(14.dp)).padding(14.dp)) {
                Column {
                    Text(r?.message() ?: "Starting…", color = col, fontSize = 16.sp, fontWeight = FontWeight.Bold, lineHeight = 22.sp)
                    r?.let { Text("${it.loadedPackets} loaded / ${it.totalPackets} packets · ${(it.elapsedMs / 1000).coerceAtMost(60)} s of 60", color = Dim, fontSize = 13.sp, modifier = Modifier.padding(top = 6.dp)) }
                }
            }
            Spacer(Modifier.height(12.dp))
        }
        Button(onClick = { result = null; verifier = com.rashed.bikesensordoctor.core.LoadVerifier(System.currentTimeMillis()) }, Modifier.fillMaxWidth().height(60.dp), enabled = !running,
            colors = ButtonDefaults.buttonColors(containerColor = Green, contentColor = Ink)) { Text(if (running) "CHECKING… PEDAL UNDER LOAD" else "START 60-SECOND CHECK", fontWeight = FontWeight.Black) }
        Spacer(Modifier.height(12.dp))
        Text("Nothing is written to the sensor. A PASS only records the date and the max watts seen; it does not change calibration.", fontSize = 12.sp, color = Dim)
    }
}
