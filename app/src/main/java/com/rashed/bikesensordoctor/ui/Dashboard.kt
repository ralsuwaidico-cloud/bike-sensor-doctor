package com.rashed.bikesensordoctor.ui

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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rashed.bikesensordoctor.core.Health
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

private val Cyan = Color(0xFF4DD0E1)
private val Amber = Color(0xFFFFB74D)
private val Green = Color(0xFF66BB6A)
private val Red = Color(0xFFEF5350)
private val Dim = Color(0xFF7C9099)
private val Track = Color(0xFF1B2A31)

enum class Screen { DASHBOARD, HISTORY, SETTINGS, DIAGNOSE }

@Composable
fun BikeComputerApp(vm: DoctorViewModel, onKeepScreenOnChanged: () -> Unit, onBatteryOptimization: () -> Unit) {
    var screen by remember { mutableStateOf(Screen.DASHBOARD) }
    when (screen) {
        Screen.DASHBOARD -> DashboardScreen(vm, onHistory = { screen = Screen.HISTORY }, onSettings = { screen = Screen.SETTINGS })
        Screen.HISTORY -> HistoryScreen(vm) { screen = Screen.DASHBOARD }
        Screen.SETTINGS -> SettingsScreen(vm, onBack = { screen = Screen.DASHBOARD }, onDiagnose = { screen = Screen.DIAGNOSE }, onKeepScreenOnChanged, onBatteryOptimization)
        Screen.DIAGNOSE -> DiagnoseScreen(vm) { screen = Screen.SETTINGS }
    }
}

// ------------------------------------------------------------------ Dashboard

@Composable
fun DashboardScreen(vm: DoctorViewModel, onHistory: () -> Unit, onSettings: () -> Unit) {
    val d by vm.engine.dash.collectAsStateWithLifecycle()
    val prefs = vm.engine.prefs
    var confirmFinish by remember { mutableStateOf(false) }
    var editField by remember { mutableStateOf<Int?>(null) }
    var fields by remember { mutableStateOf(prefs.fields) }

    Column(Modifier.fillMaxSize().padding(horizontal = 14.dp, vertical = 10.dp)) {
        StatusBar(d, onHistory, onSettings, onReconnect = { vm.engine.sensor.recoverNow() })
        Spacer(Modifier.height(6.dp))

        // Main gauges: power (large) and cadence
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            Gauge(
                modifier = Modifier.weight(1.35f),
                value = d.powerW, max = (prefs.ftpW * 1.5f).coerceAtLeast(300f), label = "WATTS",
                color = powerColor(d.powerW, prefs.ftpW), big = true,
                sub = d.power3sW?.let { "3 s  $it" },
            )
            Gauge(
                modifier = Modifier.weight(1f),
                value = d.cadenceRpm, max = 130f, label = if (d.backwards) "RPM ◄ BACKWARDS" else "RPM",
                color = if (d.backwards) Red else Cyan, big = false,
                sub = d.crankAngle?.let { "∠ $it°" },
            )
        }
        Spacer(Modifier.height(10.dp))

        // Four configurable fields
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (i in 0 until 2) Field(Modifier.weight(1f), fields.getOrElse(i) { "time" }, d, prefs) { editField = i }
        }
        Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            for (i in 2 until 4) Field(Modifier.weight(1f), fields.getOrElse(i) { "time" }, d, prefs) { editField = i }
        }

        Spacer(Modifier.weight(1f))

        d.lastSavedRide?.takeIf { d.rideState == RideStats.State.IDLE }?.let {
            Text(it, fontSize = 14.sp, color = Green, modifier = Modifier.padding(bottom = 6.dp))
        }

        // Ride controls
        when (d.rideState) {
            RideStats.State.IDLE, RideStats.State.FINISHED -> BigButton("START RIDE", Green) { vm.engine.startRide() }
            RideStats.State.RUNNING -> Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.weight(1f)) { BigButton("PAUSE", Amber) { vm.engine.pauseRide() } }
                Box(Modifier.weight(1f)) { BigButton("FINISH", Red) { confirmFinish = true } }
            }
            RideStats.State.PAUSED -> Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Box(Modifier.weight(1f)) { BigButton("RESUME", Green) { vm.engine.startRide() } }
                Box(Modifier.weight(1f)) { BigButton("FINISH", Red) { confirmFinish = true } }
            }
        }
    }

    if (confirmFinish) AlertDialog(
        onDismissRequest = { confirmFinish = false },
        title = { Text("Finish this ride?") },
        text = { Text("${RideEngine.fmtDuration(d.elapsedMs)} · avg ${d.avgPowerW} W · max ${d.maxPowerW} W. It will be saved to History.") },
        confirmButton = { Button(onClick = { confirmFinish = false; vm.engine.finishRide() }) { Text("FINISH & SAVE") } },
        dismissButton = { TextButton(onClick = { confirmFinish = false }) { Text("Keep riding") } },
    )

    editField?.let { idx ->
        AlertDialog(
            onDismissRequest = { editField = null },
            title = { Text("Show in this field") },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    Prefs.FIELD_OPTIONS.forEach { (key, label) ->
                        Text(label, fontSize = 18.sp, modifier = Modifier.fillMaxWidth().clickable {
                            val f = fields.toMutableList(); while (f.size < 4) f.add("time"); f[idx] = key
                            fields = f; prefs.fields = f; editField = null
                        }.padding(vertical = 12.dp), color = if (fields.getOrNull(idx) == key) Cyan else Color.Unspecified)
                    }
                }
            },
            confirmButton = { TextButton(onClick = { editField = null }) { Text("Cancel") } },
        )
    }
}

private fun powerColor(p: Int?, ftp: Int): Color = when {
    p == null -> Dim
    p < ftp * 0.55 -> Color(0xFF90A4AE)
    p < ftp * 0.75 -> Cyan
    p < ftp * 0.90 -> Green
    p < ftp * 1.05 -> Amber
    else -> Red
}

@Composable
private fun StatusBar(d: Dashboard, onHistory: () -> Unit, onSettings: () -> Unit, onReconnect: () -> Unit) {
    val (dot, text) = when (d.health) {
        Health.CONNECTED_LIVE -> Green to d.healthText
        Health.CONNECTED_IDLE -> Cyan to d.healthText
        Health.RECONNECTING, Health.SEARCHING, Health.LINK_SILENT -> Amber to d.healthText
        else -> Red to d.healthText
    }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(10.dp).background(dot, CircleShape))
        Spacer(Modifier.size(8.dp))
        Column(Modifier.weight(1f).clickable { if (d.health != Health.CONNECTED_LIVE && d.health != Health.CONNECTED_IDLE) onReconnect() }) {
            Text(text, fontSize = 13.sp, color = Color(0xFFB8C8D0), maxLines = 2)
            val bits = buildList {
                if (d.sensorName.isNotEmpty()) add(d.sensorName)
                d.batteryPct?.let { add("🔋 $it %") }
                d.rssi?.let { add("$it dBm") }
            }
            if (bits.isNotEmpty()) Text(bits.joinToString("  ·  "), fontSize = 11.sp, color = Dim)
        }
        TextButton(onClick = onHistory) { Text("History", color = Cyan) }
        TextButton(onClick = onSettings) { Text("⚙", fontSize = 20.sp, color = Cyan) }
    }
}

@Composable
private fun Gauge(modifier: Modifier, value: Int?, max: Float, label: String, color: Color, big: Boolean, sub: String?) {
    Box(modifier.aspectRatio(1f), contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val stroke = size.minDimension * if (big) 0.075f else 0.08f
            val inset = stroke / 2 + 2.dp.toPx()
            val arcSize = Size(size.width - 2 * inset, size.height - 2 * inset)
            val topLeft = Offset(inset, inset)
            val start = 135f; val sweepMax = 270f
            drawArc(Track, start, sweepMax, false, topLeft, arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
            val frac = ((value ?: 0).toFloat() / max).coerceIn(0f, 1f)
            if (value != null && frac > 0f) drawArc(color, start, sweepMax * frac, false, topLeft, arcSize, style = Stroke(stroke, cap = StrokeCap.Round))
            // tick marks every 25 %
            val r = min(arcSize.width, arcSize.height) / 2
            val c = Offset(size.width / 2, size.height / 2)
            for (k in 0..4) {
                val a = Math.toRadians((start + sweepMax * k / 4).toDouble())
                val p1 = Offset(c.x + (r - stroke * 0.9f) * cos(a).toFloat(), c.y + (r - stroke * 0.9f) * sin(a).toFloat())
                val p2 = Offset(c.x + (r - stroke * 1.4f) * cos(a).toFloat(), c.y + (r - stroke * 1.4f) * sin(a).toFloat())
                drawLine(Dim, p1, p2, strokeWidth = 2.dp.toPx())
            }
        }
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(value?.toString() ?: "—", fontSize = if (big) 64.sp else 44.sp, fontWeight = FontWeight.Bold, color = if (value == null) Dim else Color.White, lineHeight = if (big) 64.sp else 44.sp)
            Text(label, fontSize = if (big) 14.sp else 12.sp, color = if (label.contains("BACKWARDS")) Red else Dim, fontWeight = FontWeight.SemiBold)
            sub?.let { Text(it, fontSize = 13.sp, color = Color(0xFFB8C8D0)) }
        }
    }
}

@Composable
private fun Field(modifier: Modifier, key: String, d: Dashboard, prefs: Prefs, onClick: () -> Unit) {
    val (label, value) = fieldValue(key, d, prefs)
    Column(modifier.background(Color(0xFF0E1A1F), RoundedCornerShape(14.dp)).clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 10.dp)) {
        Text(label.uppercase(), fontSize = 11.sp, color = Dim, fontWeight = FontWeight.SemiBold)
        Text(value, fontSize = 30.sp, fontWeight = FontWeight.Bold, color = if (value == "—") Dim else Color.White)
    }
}

private fun fieldValue(key: String, d: Dashboard, prefs: Prefs): Pair<String, String> = when (key) {
    "power3s" -> "3 s power" to (d.power3sW?.let { "$it W" } ?: "—")
    "avgPower" -> "Avg power" to "${d.avgPowerW} W"
    "maxPower" -> "Max power" to "${d.maxPowerW} W"
    "time" -> "Ride time" to RideEngine.fmtDuration(d.elapsedMs)
    "avgCadence" -> "Avg cadence" to "${d.avgCadenceRpm}"
    "maxCadence" -> "Max cadence" to "${d.maxCadenceRpm}"
    "energy" -> "Energy" to String.format(Locale.US, "%.0f kJ", d.energyKj)
    "battery" -> "Sensor battery" to (d.batteryPct?.let { "$it %" } ?: "—")
    "balance" -> "L / R" to (if (d.leftW != null && d.rightW != null && d.leftW + d.rightW > 0) "${d.leftW * 100 / (d.leftW + d.rightW)} / ${d.rightW * 100 / (d.leftW + d.rightW)}" else "—")
    "clock" -> "Clock" to SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
    else -> key to "—"
}

@Composable
private fun BigButton(text: String, color: Color, onClick: () -> Unit) {
    Button(onClick = onClick, Modifier.fillMaxWidth().height(72.dp), shape = RoundedCornerShape(18.dp),
        colors = ButtonDefaults.buttonColors(containerColor = color, contentColor = Color(0xFF041014))) {
        Text(text, fontSize = 24.sp, fontWeight = FontWeight.Bold)
    }
}

// ------------------------------------------------------------------ History

@Composable
fun HistoryScreen(vm: DoctorViewModel, onBack: () -> Unit) {
    var rides by remember { mutableStateOf(vm.engine.history.list()) }
    val ctx = LocalContext.current
    var toDelete by remember { mutableStateOf<RideSummary?>(null) }
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ Back", fontSize = 18.sp, color = Cyan) }
            Text("Ride history", fontSize = 24.sp, fontWeight = FontWeight.Bold)
        }
        if (rides.isEmpty()) Text("No rides yet. Press START RIDE on the dashboard.", color = Dim, modifier = Modifier.padding(top = 24.dp))
        LazyColumn {
            items(rides, key = { it.startedAtMs }) { r ->
                Card(Modifier.fillMaxWidth().padding(vertical = 5.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Text(SimpleDateFormat("EEE d MMM yyyy · HH:mm", Locale.getDefault()).format(Date(r.startedAtMs)), fontSize = 15.sp, color = Color(0xFFB8C8D0))
                        Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                            Stat(RideEngine.fmtDuration(r.durationMs), "time"); Stat("${r.avgPowerW} W", "avg"); Stat("${r.maxPowerW} W", "max"); Stat("${r.avgCadenceRpm}", "rpm"); Stat(String.format(Locale.US, "%.0f", r.energyKj), "kJ")
                        }
                        if (r.backwardsSamples > r.samples / 2 && r.samples > 0) Text("Cadence was reported as backwards for most of this ride", fontSize = 12.sp, color = Amber)
                        Row {
                            TextButton(onClick = { vm.shareRideCsv(ctx, r.startedAtMs) }) { Text("Share CSV") }
                            TextButton(onClick = { toDelete = r }) { Text("Delete", color = Red) }
                        }
                    }
                }
            }
        }
    }
    toDelete?.let { r ->
        AlertDialog(onDismissRequest = { toDelete = null }, title = { Text("Delete this ride?") }, text = { Text("This cannot be undone.") },
            confirmButton = { TextButton(onClick = { vm.engine.history.delete(r.startedAtMs); rides = vm.engine.history.list(); toDelete = null }) { Text("Delete", color = Red) } },
            dismissButton = { TextButton(onClick = { toDelete = null }) { Text("Cancel") } })
    }
}

@Composable
private fun Stat(v: String, l: String) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(v, fontSize = 18.sp, fontWeight = FontWeight.Bold); Text(l, fontSize = 11.sp, color = Dim)
    }
}

// ------------------------------------------------------------------ Settings

@Composable
fun SettingsScreen(vm: DoctorViewModel, onBack: () -> Unit, onDiagnose: () -> Unit, onKeepScreenOnChanged: () -> Unit, onBatteryOptimization: () -> Unit) {
    val prefs = vm.engine.prefs
    val ctx = LocalContext.current
    var keepOn by remember { mutableStateOf(prefs.keepScreenOn) }
    var ftp by remember { mutableStateOf(prefs.ftpW) }
    val d by vm.engine.dash.collectAsStateWithLifecycle()
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) { Text("‹ Back", fontSize = 18.sp, color = Cyan) }
            Text("Settings", fontSize = 24.sp, fontWeight = FontWeight.Bold)
        }
        Spacer(Modifier.height(12.dp))
        Button(onClick = onDiagnose, Modifier.fillMaxWidth().height(64.dp), shape = RoundedCornerShape(16.dp)) { Text("DIAGNOSE & REPAIR SENSOR", fontSize = 18.sp, fontWeight = FontWeight.Bold) }
        Text("Runs the guided check (still → pedal → optional ride) and tries safe fixes. Only use when something seems wrong.", fontSize = 13.sp, color = Dim, modifier = Modifier.padding(top = 6.dp, bottom = 18.dp))

        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.SpaceBetween) {
            Column(Modifier.weight(1f)) { Text("Keep screen on", fontSize = 18.sp); Text("While the app is open", fontSize = 13.sp, color = Dim) }
            Switch(checked = keepOn, onCheckedChange = { keepOn = it; prefs.keepScreenOn = it; onKeepScreenOnChanged() })
        }
        Spacer(Modifier.height(16.dp))
        Text("Power zones reference (FTP): $ftp W", fontSize = 18.sp)
        Text("Colours the power gauge. Tap − / + to adjust.", fontSize = 13.sp, color = Dim)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 6.dp)) {
            OutlinedButton(onClick = { ftp = (ftp - 10).coerceAtLeast(50); prefs.ftpW = ftp }) { Text("− 10") }
            OutlinedButton(onClick = { ftp += 10; prefs.ftpW = ftp }) { Text("+ 10") }
        }
        Spacer(Modifier.height(20.dp))
        Text("Keep connected with the screen off", fontSize = 18.sp)
        Text("Android may pause Bluetooth for battery saving. Allowing 'unrestricted' battery use for Bike Computer keeps rides recording reliably.", fontSize = 13.sp, color = Dim)
        OutlinedButton(onClick = onBatteryOptimization, Modifier.padding(top = 6.dp)) { Text("Allow unrestricted battery use") }
        Spacer(Modifier.height(20.dp))
        Text("Sensor", fontSize = 18.sp)
        Text("${prefs.lastSensorName ?: "—"}  ${prefs.lastSensorAddress ?: ""}\n${d.healthText}", fontSize = 13.sp, color = Dim)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 6.dp)) {
            OutlinedButton(onClick = { vm.engine.sensor.recoverNow() }) { Text("Reconnect now") }
            OutlinedButton(onClick = { prefs.lastSensorAddress = null; prefs.lastSensorName = null; vm.engine.sensor.recoverNow() }) { Text("Forget & rescan") }
        }
        Spacer(Modifier.height(20.dp))
        Text("Troubleshooting", fontSize = 18.sp)
        Text("Technical logs are saved automatically whenever a connection problem occurs. Send them if we are troubleshooting together.", fontSize = 13.sp, color = Dim)
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 6.dp)) {
            OutlinedButton(onClick = { vm.engine.shareLogs(ctx) }) { Text("Send logs to Claude") }
            OutlinedButton(onClick = { vm.shareLatestReport(ctx) }) { Text("Send last report") }
        }
        Spacer(Modifier.height(24.dp))
        Text("Bike Computer v0.3 · Bluetooth-only XDS/Branta meter · never writes to the sensor except notification subscriptions", fontSize = 11.sp, color = Dim)
    }
}
