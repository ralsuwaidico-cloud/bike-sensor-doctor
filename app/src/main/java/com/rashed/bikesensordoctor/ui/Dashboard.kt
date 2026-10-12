package com.rashed.bikesensordoctor.ui

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rashed.bikesensordoctor.core.CueType
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

enum class Screen { DASHBOARD, COACH, HISTORY, REPORT, SETTINGS, ADD_HR, DIAGNOSE }

@Composable
fun BikeComputerApp(vm: DoctorViewModel, onKeepScreenOnChanged: () -> Unit, onBatteryOptimization: () -> Unit) {
    var screen by remember { mutableStateOf(Screen.DASHBOARD) }
    var reportRide by remember { mutableStateOf<Long?>(null) }
    when (screen) {
        Screen.DASHBOARD -> DashboardScreen(vm, onCoach = { screen = Screen.COACH }, onHistory = { screen = Screen.HISTORY }, onSettings = { screen = Screen.SETTINGS })
        Screen.COACH -> CoachScreen(vm) { screen = Screen.DASHBOARD }
        Screen.HISTORY -> HistoryScreen(vm, onBack = { screen = Screen.DASHBOARD }, onOpen = { reportRide = it; screen = Screen.REPORT })
        Screen.REPORT -> ReportScreen(vm, reportRide) { screen = Screen.HISTORY }
        Screen.SETTINGS -> SettingsScreen(vm, onBack = { screen = Screen.DASHBOARD }, onDiagnose = { screen = Screen.DIAGNOSE }, onAddHr = { screen = Screen.ADD_HR }, onKeepScreenOnChanged, onBatteryOptimization)
        Screen.ADD_HR -> AddHrScreen(vm) { screen = Screen.SETTINGS }
        Screen.DIAGNOSE -> DiagnoseScreen(vm) { screen = Screen.SETTINGS }
    }
}

// ------------------------------------------------------------------ Dashboard

@Composable
fun DashboardScreen(vm: DoctorViewModel, onCoach: () -> Unit, onHistory: () -> Unit, onSettings: () -> Unit) {
    val d by vm.engine.dash.collectAsStateWithLifecycle()
    val cue by vm.engine.cue.collectAsStateWithLifecycle()
    val prefs = vm.engine.prefs
    var confirmFinish by remember { mutableStateOf(false) }
    var editField by remember { mutableStateOf<Int?>(null) }
    var fields by remember { mutableStateOf(prefs.fields) }

    Column(Modifier.fillMaxSize().background(Ink).padding(horizontal = 12.dp, vertical = 8.dp)) {
        StatusStrip(d) { vm.engine.sensor.recoverNow() }
        Spacer(Modifier.height(6.dp))

        // live coach banner (only while a mode is active and a cue exists)
        if (cue.type != CueType.NONE && d.rideState == RideStats.State.RUNNING) {
            val bg = when (cue.type) {
                CueType.EASE_OFF, CueType.RECOVER -> Amber
                CueType.PUSH_HARDER, CueType.WORK -> Green
                CueType.PEDAL_FASTER, CueType.PEDAL_SLOWER -> Cyan
                CueType.KEEP_IT_UP -> Green
                else -> Panel
            }
            Box(Modifier.fillMaxWidth().background(bg, RoundedCornerShape(14.dp)).clickable(onClick = onCoach).padding(12.dp)) {
                Column { Text(cue.headline, fontSize = 22.sp, fontWeight = FontWeight.Black, color = Ink)
                    if (cue.detail.isNotEmpty()) Text(cue.detail, fontSize = 13.sp, color = Ink.copy(alpha = 0.8f)) }
            }
            Spacer(Modifier.height(8.dp))
        }

        // Power gauge (hero) + cadence/HR arcs
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            ArcGauge(Modifier.weight(1.5f), value = d.powerW, max = (prefs.ftpW * 1.6f).coerceAtLeast(300f),
                label = "WATTS", color = zoneColor(d.powerZone).takeIf { d.powerZone > 0 } ?: Cyan, big = true,
                sub = if (d.powerZone in 1..7) PowerZones.name(d.powerZone) else d.power3sW?.let { "3s $it" })
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ArcGauge(Modifier.fillMaxWidth(), value = d.cadenceRpm, max = 130f,
                    label = if (d.backwards) "RPM ◄" else "RPM", color = if (d.backwards) Red else Violet, big = false, sub = null)
                ArcGauge(Modifier.fillMaxWidth(), value = d.hrBpm, max = prefs.maxHr.toFloat().coerceAtLeast(120f),
                    label = "BPM", color = if (d.hrConnected) zoneColor(d.hrZone).takeIf { d.hrZone > 0 } ?: Red else Dim,
                    big = false, sub = if (d.hrConnected) (if (d.hrZone in 1..5) "HR Z${d.hrZone}" else null) else "no strap")
            }
        }
        Spacer(Modifier.height(8.dp))
        Sparkline(d.recentPower, prefs.ftpW)
        Spacer(Modifier.height(8.dp))

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (i in 0 until 2) Field(Modifier.weight(1f), fields.getOrElse(i) { "time" }, d, prefs) { editField = i }
        }
        Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (i in 2 until 4) Field(Modifier.weight(1f), fields.getOrElse(i) { "time" }, d, prefs) { editField = i }
        }

        Spacer(Modifier.weight(1f))
        d.lastSavedRide?.takeIf { d.rideState == RideStats.State.IDLE }?.let {
            Text(it, fontSize = 13.sp, color = Green, modifier = Modifier.padding(bottom = 6.dp))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Box(Modifier.weight(1f)) {
                when (d.rideState) {
                    RideStats.State.IDLE, RideStats.State.FINISHED -> BigButton("START", Green) { vm.engine.startRide() }
                    RideStats.State.RUNNING -> BigButton("PAUSE", Amber) { vm.engine.pauseRide() }
                    RideStats.State.PAUSED -> BigButton("RESUME", Green) { vm.engine.startRide() }
                }
            }
            if (d.rideState == RideStats.State.RUNNING || d.rideState == RideStats.State.PAUSED)
                Box(Modifier.weight(1f)) { BigButton("FINISH", Red) { confirmFinish = true } }
            Box(Modifier.width(96.dp)) { BigButton("COACH", Violet, onCoach) }
        }
        Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            TextButton(onClick = onHistory) { Text("History", color = Cyan) }
            Spacer(Modifier.weight(1f))
            TextButton(onClick = onSettings) { Text("⚙ Settings", color = Cyan) }
        }
    }

    if (confirmFinish) AlertDialog(
        onDismissRequest = { confirmFinish = false },
        containerColor = Panel,
        title = { Text("Finish ride?") },
        text = { Text("${RideEngine.fmtDuration(d.elapsedMs)} · avg ${d.avgPowerW} W · max ${d.maxPowerW} W — saved to History.") },
        confirmButton = { Button(onClick = { confirmFinish = false; vm.engine.finishRide() }) { Text("FINISH & SAVE") } },
        dismissButton = { TextButton(onClick = { confirmFinish = false }) { Text("Keep riding") } },
    )
    editField?.let { idx ->
        AlertDialog(onDismissRequest = { editField = null }, containerColor = Panel, title = { Text("Show in this field") },
            text = { Column(Modifier.verticalScroll(rememberScrollState())) {
                Prefs.FIELD_OPTIONS.forEach { (key, label) ->
                    Text(label, fontSize = 18.sp, modifier = Modifier.fillMaxWidth().clickable {
                        val f = fields.toMutableList(); while (f.size < 4) f.add("time"); f[idx] = key; fields = f; prefs.fields = f; editField = null
                    }.padding(vertical = 12.dp), color = if (fields.getOrNull(idx) == key) Cyan else Color.White)
                } } },
            confirmButton = { TextButton(onClick = { editField = null }) { Text("Cancel") } })
    }
}

@Composable
private fun StatusStrip(d: Dashboard, onReconnect: () -> Unit) {
    val (dot, text) = when (d.health) {
        Health.CONNECTED_LIVE -> Green to "LIVE"
        Health.CONNECTED_IDLE -> Cyan to "READY"
        Health.RECONNECTING, Health.SEARCHING, Health.LINK_SILENT -> Amber to "CONNECTING"
        else -> Red to "OFFLINE"
    }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(9.dp).background(dot, CircleShape))
        Spacer(Modifier.width(6.dp))
        Column(Modifier.weight(1f).clickable { if (d.health !in listOf(Health.CONNECTED_LIVE, Health.CONNECTED_IDLE)) onReconnect() }) {
            Text(if (d.health in listOf(Health.CONNECTED_LIVE, Health.CONNECTED_IDLE)) "$text · ${RideEngine.fmtDuration(d.linkUptimeSec * 1000)}" else d.healthText,
                fontSize = 12.sp, color = Color(0xFFBFD2DA), maxLines = 1)
        }
        Chip("PWR", d.batteryPct?.let { "$it%" } ?: "—", if ((d.batteryPct ?: 100) < 15) Red else Dim)
        Spacer(Modifier.width(6.dp))
        Chip("HR", if (d.hrConnected) (d.hrBpm?.toString() ?: "…") else "off", if (d.hrConnected) Red else Dim)
        Spacer(Modifier.width(6.dp))
        Chip("GPS", if (d.gpsFix) "fix" else "—", if (d.gpsFix) Green else Dim)
    }
}

@Composable
private fun Chip(label: String, value: String, color: Color) {
    Row(Modifier.background(Panel, RoundedCornerShape(8.dp)).padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, fontSize = 10.sp, color = Dim); Spacer(Modifier.width(4.dp)); Text(value, fontSize = 12.sp, color = color, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun ArcGauge(modifier: Modifier, value: Int?, max: Float, label: String, color: Color, big: Boolean, sub: String?) {
    val target = ((value ?: 0).toFloat() / max).coerceIn(0f, 1f)
    val anim by animateFloatAsState(targetValue = target, animationSpec = tween(400), label = "gauge")
    val animColor by animateColorAsState(color, tween(400), label = "col")
    Box(modifier.aspectRatio(if (big) 1f else 1.7f), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = size.minDimension * (if (big) 0.085f else 0.11f)
            val inset = stroke / 2 + 2.dp.toPx()
            val d = min(size.width, size.height) - 2 * inset
            val topLeft = Offset((size.width - d) / 2, (size.height - d) / 2 + if (big) 0f else size.height * 0.08f)
            val arc = Size(d, d)
            val start = 135f; val sweep = 270f
            drawArc(Color(0xFF16242B), start, sweep, false, topLeft, arc, style = Stroke(stroke, cap = StrokeCap.Round))
            if (anim > 0f) drawArc(Brush.sweepGradient(listOf(animColor.copy(alpha = 0.5f), animColor)), start, sweep * anim, false, topLeft, arc, style = Stroke(stroke, cap = StrokeCap.Round))
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(value?.toString() ?: "—", fontSize = if (big) 68.sp else 34.sp, fontWeight = FontWeight.Black,
                color = if (value == null) Dim else Color.White, lineHeight = if (big) 70.sp else 36.sp)
            Text(label, fontSize = if (big) 14.sp else 11.sp, color = if (label.contains("◄")) Red else Dim, fontWeight = FontWeight.Bold)
            sub?.let { Text(it, fontSize = if (big) 13.sp else 10.sp, color = animColor) }
        }
    }
}

@Composable
private fun Sparkline(data: List<Int>, ftp: Int) {
    Box(Modifier.fillMaxWidth().height(54.dp).background(Panel, RoundedCornerShape(12.dp)).padding(8.dp)) {
        if (data.size < 2) { Text("power — last 60 s", fontSize = 11.sp, color = Dim); return@Box }
        val maxV = (data.max().coerceAtLeast(ftp)).toFloat()
        Canvas(Modifier.fillMaxSize()) {
            val n = data.size; val dx = size.width / (n - 1).coerceAtLeast(1)
            // FTP reference line
            val ftpY = size.height * (1f - (ftp / maxV).coerceIn(0f, 1f))
            drawLine(Color(0xFF2A3A42), Offset(0f, ftpY), Offset(size.width, ftpY), strokeWidth = 1.5f)
            var prev: Offset? = null
            data.forEachIndexed { i, v ->
                val p = Offset(i * dx, size.height * (1f - (v / maxV).coerceIn(0f, 1f)))
                prev?.let { drawLine(Cyan, it, p, strokeWidth = 3f, cap = StrokeCap.Round) }
                prev = p
            }
        }
    }
}

private fun powerColorUnused() {}

@Composable
private fun Field(modifier: Modifier, key: String, d: Dashboard, prefs: Prefs, onClick: () -> Unit) {
    val (label, value) = fieldValue(key, d, prefs)
    Column(modifier.background(Panel, RoundedCornerShape(14.dp)).clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 10.dp)) {
        Text(label.uppercase(), fontSize = 11.sp, color = Dim, fontWeight = FontWeight.SemiBold)
        Text(value, fontSize = 30.sp, fontWeight = FontWeight.Black, color = if (value == "—") Dim else Color.White)
    }
}

private fun fieldValue(key: String, d: Dashboard, prefs: Prefs): Pair<String, String> = when (key) {
    "power3s" -> "3 s power" to (d.power3sW?.let { "$it W" } ?: "—")
    "power10s" -> "10 s power" to (d.power10sW?.let { "$it W" } ?: "—")
    "avgPower" -> "Avg power" to "${d.avgPowerW} W"
    "maxPower" -> "Max power" to "${d.maxPowerW} W"
    "powerZone" -> "Power zone" to (if (d.powerZone in 1..7) "Z${d.powerZone}" else "—")
    "speed" -> "Speed" to (d.speedKmh?.let { String.format(Locale.US, "%.1f", it) } ?: if (d.gpsFix) "0.0" else "—")
    "distance" -> "Distance" to (if (d.gpsFix || d.distanceKm > 0) String.format(Locale.US, "%.2f km", d.distanceKm) else "—")
    "time" -> "Ride time" to RideEngine.fmtDuration(d.elapsedMs)
    "avgCadence" -> "Avg cadence" to "${d.avgCadenceRpm}"
    "maxCadence" -> "Max cadence" to "${d.maxCadenceRpm}"
    "energy" -> "Energy" to String.format(Locale.US, "%.0f kJ", d.energyKj)
    "battery" -> "Sensor battery" to (d.batteryPct?.let { "$it %" } ?: "—")
    "balance" -> "L / R" to (if (d.leftW != null && d.rightW != null && d.leftW + d.rightW > 0) "${d.leftW * 100 / (d.leftW + d.rightW)}/${d.rightW * 100 / (d.leftW + d.rightW)}" else "—")
    "clock" -> "Clock" to SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
    else -> key to "—"
}

@Composable
private fun BigButton(text: String, color: Color, onClick: () -> Unit) {
    Button(onClick = onClick, Modifier.fillMaxWidth().height(64.dp), shape = RoundedCornerShape(16.dp),
        colors = ButtonDefaults.buttonColors(containerColor = color, contentColor = Ink)) {
        Text(text, fontSize = 20.sp, fontWeight = FontWeight.Black)
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
            TextButton(onClick = onBack) { Text("‹ Ride", color = Cyan, fontSize = 18.sp) }
            Text("History", fontSize = 24.sp, fontWeight = FontWeight.Black, color = Color.White)
        }
        if (rides.isEmpty()) Text("No rides yet. Press START on the dashboard.", color = Dim, modifier = Modifier.padding(top = 24.dp))
        LazyColumn {
            items(rides, key = { it.startedAtMs }) { r ->
                Card(Modifier.fillMaxWidth().padding(vertical = 5.dp).clickable { onOpen(r.startedAtMs) }) {
                    Column(Modifier.padding(12.dp)) {
                        Text(SimpleDateFormat("EEE d MMM · HH:mm", Locale.getDefault()).format(Date(r.startedAtMs)), fontSize = 14.sp, color = Color(0xFFBFD2DA))
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
fun SettingsScreen(vm: DoctorViewModel, onBack: () -> Unit, onDiagnose: () -> Unit, onAddHr: () -> Unit, onKeepScreenOnChanged: () -> Unit, onBatteryOptimization: () -> Unit) {
    val prefs = vm.engine.prefs
    val ctx = LocalContext.current
    val d by vm.engine.dash.collectAsStateWithLifecycle()
    var keepOn by remember { mutableStateOf(prefs.keepScreenOn) }
    var ftp by remember { mutableStateOf(prefs.ftpW) }
    var maxHr by remember { mutableStateOf(prefs.maxHr) }
    Column(Modifier.fillMaxSize().background(Ink).verticalScroll(rememberScrollState()).padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ Ride", color = Cyan, fontSize = 18.sp) }
            Text("Settings", fontSize = 24.sp, fontWeight = FontWeight.Black, color = Color.White)
        }
        Spacer(Modifier.height(10.dp))
        Button(onClick = onAddHr, Modifier.fillMaxWidth().height(56.dp), colors = ButtonDefaults.buttonColors(containerColor = Red, contentColor = Ink)) { Text("ADD HEART-RATE SENSOR (WHOOP / watch)", fontWeight = FontWeight.Bold, fontSize = 14.sp) }
        Spacer(Modifier.height(14.dp))

        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) { Text("Keep screen on", fontSize = 18.sp, color = Color.White); Text("During rides", fontSize = 13.sp, color = Dim) }
            Switch(checked = keepOn, onCheckedChange = { keepOn = it; prefs.keepScreenOn = it; onKeepScreenOnChanged() })
        }
        Spacer(Modifier.height(14.dp))
        Text("FTP (functional threshold power): $ftp W", fontSize = 16.sp, color = Color.White)
        Text("Sets your power zones.", fontSize = 13.sp, color = Dim)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 4.dp)) {
            OutlinedButton(onClick = { ftp = (ftp - 5).coerceAtLeast(50); prefs.ftpW = ftp }) { Text("−5") }
            OutlinedButton(onClick = { ftp += 5; prefs.ftpW = ftp }) { Text("+5") }
        }
        Spacer(Modifier.height(14.dp))
        Text("Max heart rate: $maxHr bpm", fontSize = 16.sp, color = Color.White)
        Text("Sets your heart-rate zones.", fontSize = 13.sp, color = Dim)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 4.dp)) {
            OutlinedButton(onClick = { maxHr = (maxHr - 1).coerceAtLeast(120); prefs.maxHr = maxHr }) { Text("−1") }
            OutlinedButton(onClick = { maxHr += 1; prefs.maxHr = maxHr }) { Text("+1") }
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
        Spacer(Modifier.height(10.dp))
        Text("Bike Computer v0.5 · never writes to the sensor except notification subscriptions", fontSize = 11.sp, color = Dim)
    }
}
