package com.rashed.bikesensordoctor.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rashed.bikesensordoctor.ble.ConnectionState
import com.rashed.bikesensordoctor.diag.AutoState
import com.rashed.bikesensordoctor.diag.Outcome

private val Green = Color(0xFF66BB6A)
private val Amber = Color(0xFFFFB74D)
private val Red = Color(0xFFEF5350)
private val Blue = Color(0xFF4DD0E1)

@Composable
fun HomeScreen(vm: DoctorViewModel) {
    val a by vm.auto.state.collectAsStateWithLifecycle()
    var showLive by remember { mutableStateOf(false) }
    var showTech by remember { mutableStateOf(false) }

    a.approval?.let { req ->
        AlertDialog(
            onDismissRequest = { },
            title = { Text(req.title, fontSize = 20.sp) },
            text = { Column(Modifier.verticalScroll(rememberScrollState())) {
                Text(req.explanation, fontSize = 16.sp)
                Spacer(Modifier.height(12.dp))
                Text(req.risks, fontSize = 15.sp, color = Amber)
            } },
            confirmButton = { Button(onClick = { vm.auto.answerApproval(true) }) { Text(req.yesLabel, fontSize = 16.sp) } },
            dismissButton = { TextButton(onClick = { vm.auto.answerApproval(false) }) { Text(req.noLabel, fontSize = 16.sp) } },
        )
    }

    if (showLive) { LiveScreen(vm) { showLive = false }; return }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp)) {
        Text("Bike Sensor Doctor", fontSize = 28.sp, fontWeight = FontWeight.Bold)
        Text("For the XDS / Branta power meter", fontSize = 15.sp, color = Color(0xFF9FB8C2))
        Spacer(Modifier.height(20.dp))

        when {
            a.running -> RunningPanel(a) { vm.auto.cancel() }
            a.outcome != null -> ResultPanel(a, onAgain = { vm.startAuto() }, onLive = { showLive = true }, onTech = { showTech = !showTech }, showTech = showTech, vm = vm)
            else -> {
                Button(
                    onClick = { vm.startAuto() },
                    modifier = Modifier.fillMaxWidth().height(120.dp),
                    shape = RoundedCornerShape(20.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Blue, contentColor = Color(0xFF042026)),
                ) { Text("DIAGNOSE & FIX\nMY POWER METER", fontSize = 24.sp, fontWeight = FontWeight.Bold, textAlign = TextAlign.Center, lineHeight = 30.sp) }
                Spacer(Modifier.height(16.dp))
                Text("About 3 minutes, plus an optional 60-second ride to verify power. Have the bike next to you with the pedals free to turn. The app tells you exactly when to keep still, pedal and ride.", fontSize = 16.sp)
                Spacer(Modifier.height(24.dp))
                OutlinedButton(onClick = { showLive = true }, Modifier.fillMaxWidth().height(56.dp)) { Text("Show live watts & cadence on this phone", fontSize = 16.sp) }
                Spacer(Modifier.height(12.dp))
                Text("What this app will never do: change calibration, reset the sensor, update firmware, or send unknown commands. Anything that changes a setting asks you first.", fontSize = 13.sp, color = Color(0xFF9FB8C2))
            }
        }
    }
}

@Composable
private fun RunningPanel(a: AutoState, onCancel: () -> Unit) {
    LinearProgressIndicator(progress = { a.progress }, modifier = Modifier.fillMaxWidth().height(10.dp))
    Spacer(Modifier.height(16.dp))
    if (a.instruction.isNotEmpty()) {
        Box(Modifier.fillMaxWidth().background(if (a.instruction.startsWith("YOU ARE")) Red else if (a.instruction.startsWith("PEDAL") || a.instruction.startsWith("RIDE")) Green else Amber, RoundedCornerShape(16.dp)).padding(20.dp), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(a.instruction, fontSize = 24.sp, fontWeight = FontWeight.Bold, color = Color(0xFF042026), textAlign = TextAlign.Center)
                if (a.countdown > 0) Text("${a.countdown}", fontSize = 56.sp, fontWeight = FontWeight.Bold, color = Color(0xFF042026))
                if (a.liveCadence != null || a.livePower != null) {
                    Text("${a.liveCadence ?: 0} rpm${if (a.liveBackwards) " (backwards)" else ""}   ·   ${a.livePower ?: 0} W", fontSize = 22.sp, fontWeight = FontWeight.SemiBold, color = Color(0xFF042026))
                    Text("live from the sensor", fontSize = 12.sp, color = Color(0xFF042026))
                }
            }
        }
        Spacer(Modifier.height(16.dp))
    }
    Text(a.headline, fontSize = 20.sp, fontWeight = FontWeight.SemiBold)
    Spacer(Modifier.height(12.dp))
    for (s in a.steps) {
        Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.Top) {
            val (icon, col) = when (s.state) { "ok" -> "✓" to Green; "warn" -> "!" to Amber; "fail" -> "✗" to Red; "running" -> "…" to Blue; else -> "○" to Color(0xFF5A7079) }
            Text(icon, fontSize = 18.sp, color = col, modifier = Modifier.width(28.dp))
            Column {
                Text(s.title, fontSize = 16.sp, color = if (s.state == "pending") Color(0xFF9FB8C2) else MaterialTheme.colorScheme.onBackground)
                if (s.detail.isNotEmpty()) Text(s.detail, fontSize = 13.sp, color = Color(0xFF9FB8C2))
            }
        }
    }
    Spacer(Modifier.height(16.dp))
    OutlinedButton(onClick = onCancel, Modifier.fillMaxWidth().height(52.dp)) { Text("Cancel", fontSize = 16.sp) }
}

@Composable
private fun ResultPanel(a: AutoState, onAgain: () -> Unit, onLive: () -> Unit, onTech: () -> Unit, showTech: Boolean, vm: DoctorViewModel) {
    val ctx = LocalContext.current
    val (label, col, sub) = when (a.outcome) {
        Outcome.WORKING -> Triple("WORKING", Green, "Sensor is functioning")
        Outcome.FIXED -> Triple("FIXED", Green, "A problem was corrected and the fix was verified")
        Outcome.COMPATIBILITY_ISSUE -> Triple("COMPATIBILITY ISSUE", Amber, "Sensor works, but Garmin cannot read its protocol")
        Outcome.NEEDS_ATTENTION -> Triple("NEEDS ATTENTION", Red, "A hardware or software issue remains")
        else -> Triple("INCONCLUSIVE", Color(0xFF9FB8C2), "More evidence is needed")
    }
    Box(Modifier.fillMaxWidth().background(col, RoundedCornerShape(16.dp)).padding(20.dp)) {
        Column {
            Text(label, fontSize = 28.sp, fontWeight = FontWeight.Bold, color = Color(0xFF042026))
            Text(sub, fontSize = 16.sp, color = Color(0xFF042026))
        }
    }
    Spacer(Modifier.height(16.dp))
    Text(a.summary, fontSize = 16.sp, lineHeight = 23.sp)
    Spacer(Modifier.height(20.dp))
    Button(onClick = onAgain, Modifier.fillMaxWidth().height(64.dp), shape = RoundedCornerShape(16.dp)) { Text("RUN AGAIN", fontSize = 20.sp, fontWeight = FontWeight.Bold) }
    Spacer(Modifier.height(10.dp))
    OutlinedButton(onClick = onLive, Modifier.fillMaxWidth().height(52.dp)) { Text("Show live watts & cadence", fontSize = 16.sp) }
    Spacer(Modifier.height(10.dp))
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        TextButton(onClick = onTech) { Text(if (showTech) "Hide technical details" else "Technical details") }
        TextButton(onClick = { vm.shareLatestReport(ctx) }) { Text("Send report to Claude") }
    }
    Text("The technical report was saved automatically on this phone. You only need it if we are troubleshooting together.", fontSize = 12.sp, color = Color(0xFF9FB8C2))
    if (showTech) Card(Modifier.fillMaxWidth().padding(top = 8.dp)) {
        Text(a.technicalReport, Modifier.padding(10.dp), fontFamily = FontFamily.Monospace, fontSize = 10.sp)
    }
}

/** Shows whatever live numbers the phone can decode. Standard-service values are labelled verified; XDS private-format values are labelled estimated. */
@Composable
private fun LiveScreen(vm: DoctorViewModel, onBack: () -> Unit) {
    val s by vm.gatt.snapshot.collectAsStateWithLifecycle()
    val counts by vm.log.notifyCounts.collectAsStateWithLifecycle()
    val scanning by vm.scanner.scanning.collectAsStateWithLifecycle()
    val devices by vm.scanner.devices.collectAsStateWithLifecycle()
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Text("Live watts & cadence", fontSize = 26.sp, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(12.dp))
        val stateText = when (s.state) {
            ConnectionState.READY -> "Connected to ${s.name.ifEmpty { s.address }}"
            ConnectionState.DISCONNECTED -> if (scanning) "Searching for the power meter…" else "Not connected"
            else -> "Connecting…"
        }
        Text(stateText, fontSize = 16.sp, color = Color(0xFF9FB8C2))
        if (s.state == ConnectionState.DISCONNECTED && !scanning) {
            Spacer(Modifier.height(12.dp))
            Button(onClick = {
                vm.scanner.clear(); vm.scanner.start()
            }, Modifier.fillMaxWidth().height(56.dp)) { Text("CONNECT", fontSize = 18.sp) }
        }
        // auto-connect once the known meter (or any XDS-like device) appears during a scan
        LaunchedEffect(devices, scanning, s.state) {
            if (scanning && s.state == ConnectionState.DISCONNECTED) {
                val target = devices[com.rashed.bikesensordoctor.diag.AutoDiagnostic.TARGET_MAC] ?: devices.values.firstOrNull { it.looksLikeXds }
                if (target != null) { vm.scanner.stop(); vm.gatt.connect(target.address, target.name, reconnect = true) }
            }
        }
        Spacer(Modifier.height(24.dp))
        val m = s.metrics; val c = s.candidate
        when {
            m != null -> {
                Big("${m.instantaneousPowerW ?: "—"}", "WATTS (verified, standard Bluetooth)")
                Big(m.derivedCadenceRpm?.let { "%.0f".format(it) } ?: "—", "RPM (verified)")
            }
            c != null -> {
                Big("${c.totalPowerW}", "WATTS (XDS format — reads 0 unless the pedals are under load)")
                Big("${c.cadenceRpm}", if (c.backwards) "RPM — PEDALING BACKWARDS" else "RPM")
                Text("Decoded from the sensor's own data format, checked against two open-source XDS decoders and this phone's recorded packets.", fontSize = 13.sp, color = Color(0xFF9FB8C2))
            }
            s.state == ConnectionState.READY -> {
                Big("—", "WATTS"); Big("—", "RPM")
                Text(if (counts.isEmpty()) "Connected, but the sensor has sent no data yet. Pedal for 10 seconds." else "The sensor is sending ${counts.values.sum()} messages that this app cannot decode into watts.", fontSize = 15.sp, color = Amber)
            }
        }
        Spacer(Modifier.height(24.dp))
        Text("Battery: ${s.batteryPct?.let { "$it %" } ?: "—"}   Signal: ${s.rssi?.let { "$it dBm" } ?: "—"}   Messages: ${counts.values.sum()}", fontSize = 14.sp, color = Color(0xFF9FB8C2))
        Spacer(Modifier.height(24.dp))
        OutlinedButton(onClick = { vm.scanner.stop(); vm.gatt.disconnect(); onBack() }, Modifier.fillMaxWidth().height(52.dp)) { Text("Back", fontSize = 16.sp) }
    }
}

@Composable
private fun Big(value: String, label: String) {
    Text(value, fontSize = 64.sp, fontWeight = FontWeight.Bold)
    Text(label, fontSize = 14.sp, color = Color(0xFF9FB8C2))
    Spacer(Modifier.height(12.dp))
}
