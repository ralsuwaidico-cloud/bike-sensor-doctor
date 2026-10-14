package com.rashed.bikesensordoctor.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rashed.bikesensordoctor.core.CoachShape
import com.rashed.bikesensordoctor.core.Health
import com.rashed.bikesensordoctor.core.Phase
import com.rashed.bikesensordoctor.core.RideStats
import com.rashed.bikesensordoctor.core.TargetStatus
import com.rashed.bikesensordoctor.core.Targets
import com.rashed.bikesensordoctor.ride.RideEngine
import java.util.Locale

/*
 * v0.9 LIVE screen — Design 7, one fixed Nokia 5.3 screen, NO scrolling.
 *   top    : speed · distance · ride time
 *   middle : power · heart rate · cadence gauges with LIVE dot, TGT band and status pill; one line of target ranges
 *   bottom : the coach instruction (always visible, takes whatever height is left) · controls
 * Zone bands, the power trend, link quality and ride statistics moved to the Details screen.
 */
@Composable
fun LiveScreen(vm: DoctorViewModel, onCoach: () -> Unit, onDetails: () -> Unit, onHome: () -> Unit, onSettings: () -> Unit, notice: String? = null, onNotice: () -> Unit = {}) {
    val d by vm.engine.dash.collectAsStateWithLifecycle()
    val cue by vm.engine.cue.collectAsStateWithLifecycle()
    val st = D7State(d, cue, vm.engine.prefs)
    var confirmFinish by remember { mutableStateOf(false) }

    BoxWithConstraints(Modifier.fillMaxSize().background(D7.Bg).testTag("live_root")) {
        val short = maxHeight < 620.dp   // small phones / large system font: tighter spacing, smaller top strip
        Column(Modifier.fillMaxSize().padding(horizontal = 10.dp, vertical = 4.dp)) {
            // ---- status line ----
            val live = d.health == Health.CONNECTED_LIVE || d.health == Health.CONNECTED_IDLE || d.simulated
            val (dot, text) = when {
                d.simulated -> D7.Amber to "SIMULATED"
                d.health == Health.CONNECTED_LIVE -> D7.Green to "LIVE"
                d.health == Health.CONNECTED_IDLE -> D7.Cyan to "READY"
                d.health == Health.RECONNECTING || d.health == Health.SEARCHING || d.health == Health.LINK_SILENT -> D7.Amber to "CONNECTING"
                else -> D7.Red to "OFFLINE"
            }
            Row(Modifier.fillMaxWidth().clickable { if (!live) vm.engine.sensor.recoverNow() }, verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(7.dp).background(dot, CircleShape)); Spacer(Modifier.width(5.dp))
                Text(buildString { append(text); if (d.riderName.isNotEmpty()) append(" · ${d.riderName.uppercase()}"); if (!d.powerVerified) append(" · PWR UNVERIFIED") },
                    fontFamily = PlexMono, fontSize = 9.sp, color = D7.Mut, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                if (d.rideState != RideStats.State.IDLE) Text(st.phaseLabel, fontFamily = PlexMono, fontWeight = FontWeight.Bold, fontSize = 9.sp, maxLines = 1,
                    color = if (d.phase == Phase.MAIN) D7.Green else D7.Violet)
                Spacer(Modifier.width(6.dp)); ConfidenceTag(st.zoneTag)
            }
            if (notice != null && !d.simulated) Text(notice, fontFamily = PlexMono, fontSize = 9.sp, color = D7.Amber, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.fillMaxWidth().padding(top = 2.dp).background(D7.Amber.copy(alpha = 0.12f), RoundedCornerShape(6.dp)).clickable { onNotice() }.padding(horizontal = 6.dp, vertical = 2.dp).testTag("bt_notice"))
            val bar by animateColorAsState(if (st.coachActive) st.coachColor else D7.Line, tween(400), label = "bar")
            Box(Modifier.fillMaxWidth().padding(top = 3.dp).height(2.dp).background(bar, RoundedCornerShape(1.dp)))

            // ---- top strip: speed · distance · time ----
            Row(Modifier.fillMaxWidth().padding(top = if (short) 2.dp else 6.dp), verticalAlignment = Alignment.Bottom) {
                TopStat(d.speedKmh?.let { String.format(Locale.US, "%.1f", it) } ?: "—", "KM/H", Modifier.weight(1.25f), big = !short, tag = "live_speed")
                TopStat(if (d.gpsFix || d.distanceKm > 0) String.format(Locale.US, "%.2f", d.distanceKm) else "—", "KM", Modifier.weight(1f), big = false, tag = "live_dist")
                TopStat(RideEngine.fmtDuration(d.elapsedMs), "TIME", Modifier.weight(1.15f), big = false, tag = "live_time", mono = true)
            }

            // ---- gauges ----
            Row(Modifier.fillMaxWidth().padding(top = if (short) 2.dp else 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                TargetGauge(
                    Modifier.weight(1f).testTag("gauge_power"), value = d.powerW, max = st.powerMax,
                    color = if (d.powerZone in 1..7) D7.powerZone(d.powerZone) else D7.Grey,
                    targetFraction = if (st.powerCoached) Targets.powerTargetFraction(st.targetZone, st.ftp) else null, zoneTicks = Targets.powerZoneTicks(st.ftp),
                    sub = if (!st.powerCoached) "NOT COACHED" else if (d.powerZone in 1..7) "Z${d.powerZone}" else null,
                    unit = "WATTS", big = false, status = if (st.powerCoached) st.powerStatus else TargetStatus.UNKNOWN,
                    statusText = if (st.powerCoached) statusText(st.powerStatus, "pow", st.signal) else (if (d.powerVerified) "FTP UNKNOWN" else "UNVERIFIED"), showTgtLabel = false, band = st.powerBand,
                )
                TargetGauge(
                    Modifier.weight(1f).testTag("gauge_hr"), value = st.hrLive, max = st.hrMaxGauge,
                    color = if (st.hrLive != null && d.hrZone in 1..5) D7.hrZone(d.hrZone) else D7.Faint,
                    targetFraction = if (st.tg == null) Targets.hrTargetFraction(st.targetZone) else null, zoneTicks = Targets.hrZoneTicks,
                    sub = if (st.tg != null) "${st.tg.hrLo}–${st.tg.hrHi}" else if (st.hrLive != null && d.hrZone in 1..5) "Z${d.hrZone}" else null, unit = "BPM", big = false,
                    status = st.hrStatus, statusText = statusText(st.hrStatus, "hr"), showTgtLabel = false, band = st.hrBand,
                )
                TargetGauge(
                    Modifier.weight(1f).testTag("gauge_cad"), value = d.cadenceRpm, max = Targets.CADENCE_GAUGE_MAX,
                    color = if (d.backwards) D7.Red else D7.Violet,
                    targetFraction = null, zoneTicks = FloatArray(0),
                    band = st.cadLow.toFloat() / Targets.CADENCE_GAUGE_MAX to st.cadHigh.toFloat() / Targets.CADENCE_GAUGE_MAX,
                    sub = if (d.backwards) "BACKWARDS" else "${st.cadLow}–${st.cadHigh}", unit = "RPM", big = false,
                    status = st.cadStatus, statusText = statusText(st.cadStatus, "cad", st.signal), showTgtLabel = false,
                )
            }
            // ---- one line of active targets ----
            val tg = st.tg
            Text(if (tg != null) "TGT ${tg.label} · ${tg.hrLo}–${tg.hrHi} bpm · ${if (tg.pwLo != null) "${tg.pwLo}–${tg.pwHi} W" else "power off"} · ${tg.cadLo}–${tg.cadHi} rpm"
                 else "TGT Z${st.targetZone} · ${st.cadLow}–${st.cadHigh} rpm · ${if (d.workoutName.isNotEmpty()) d.workoutName else "press START"}",
                fontFamily = PlexMono, fontSize = 9.sp, color = D7.Mut, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.fillMaxWidth().padding(top = 2.dp).testTag("live_targets"))

            // ---- coach: always visible, takes the remaining height ----
            CoachPanel(Modifier.weight(1f).fillMaxWidth().padding(top = if (short) 4.dp else 8.dp), st.headline, st.detail, st.coachColor, st.shape, st.direction, st.coachActive,
                icon = if (st.coachActive) cue.action.icon else "", sources = if (st.coachActive) cue.sources else "", live = if (st.coachActive) cue.live else "",
                assessment = d.assessment, assessmentAgeSec = if (d.assessmentAtMs > 0) ((vm.engine.now() - d.assessmentAtMs) / 1000).toInt() else -1, onClick = onCoach)

            // ---- controls ----
            Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Box(Modifier.weight(1f)) {
                    when (d.rideState) {
                        RideStats.State.IDLE, RideStats.State.FINISHED -> LiveButton("START", D7.Green, "btn_start") { vm.engine.startRide() }
                        RideStats.State.RUNNING -> LiveButton("PAUSE", D7.Amber, "btn_pause") { vm.engine.pauseRide() }
                        RideStats.State.PAUSED -> LiveButton("RESUME", D7.Green, "btn_resume") { vm.engine.startRide() }
                    }
                }
                if (d.rideState == RideStats.State.RUNNING || d.rideState == RideStats.State.PAUSED) Box(Modifier.weight(1f)) { LiveButton("FINISH", D7.Red, "btn_finish") { confirmFinish = true } }
                if (d.rideState == RideStats.State.RUNNING && d.phase != Phase.COOLDOWN && d.coachMode != "FREE") Box(Modifier.weight(0.9f)) { LiveButton("COOL", D7.Violet, "btn_cool") { vm.engine.requestCooldown() } }
                else Box(Modifier.weight(0.9f)) { LiveButton("COACH", D7.Violet, "btn_coach", 14) { onCoach() } }
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                SmallLink("‹ Home", "dash_home", onHome); SmallLink("Details", "dash_details", onDetails)
                Spacer(Modifier.weight(1f))
                d.linkQualityPct?.takeIf { d.rideState != RideStats.State.IDLE }?.let { q -> Text("LINK $q%", fontFamily = PlexMono, fontSize = 9.sp, color = if (q >= 95) D7.Faint else D7.Amber) }
                SmallLink("⚙", "dash_settings", onSettings)
            }
        }
    }

    if (confirmFinish) AlertDialog(
        onDismissRequest = { confirmFinish = false }, containerColor = D7.Panel2,
        title = { Text("Finish ride?") },
        text = { Text("${RideEngine.fmtDuration(d.elapsedMs)} · ${String.format(Locale.US, "%.1f", d.distanceKm)} km · avg ${d.avgPowerW} W — saved to History, then the results open.") },
        confirmButton = { Button(onClick = { confirmFinish = false; vm.engine.finishRide() }) { Text("FINISH & SAVE") } },
        dismissButton = { TextButton(onClick = { confirmFinish = false }) { Text("Keep riding") } },
    )
}

@Composable
private fun TopStat(value: String, label: String, modifier: Modifier, big: Boolean, tag: String, mono: Boolean = false) {
    Column(modifier.testTag(tag)) {
        Text(value, fontFamily = if (mono) PlexMono else Rajdhani, fontWeight = if (mono) FontWeight.Bold else FontWeight.SemiBold, fontSize = if (big) 34.sp else if (mono) 22.sp else 26.sp, lineHeight = if (big) 34.sp else 26.sp,
            color = if (value == "—") D7.Faint else D7.Fg, maxLines = 1, softWrap = false)
        Text(label, fontFamily = PlexMono, fontSize = 9.sp, color = D7.Mut, maxLines = 1)
    }
}

@Composable
private fun LiveButton(text: String, color: Color, tag: String, size: Int = 16, onClick: () -> Unit) {
    Button(onClick = onClick, Modifier.fillMaxWidth().height(48.dp).testTag(tag), shape = RoundedCornerShape(14.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 4.dp),
        colors = ButtonDefaults.buttonColors(containerColor = color, contentColor = D7.Ink)) {
        Text(text, fontFamily = Archivo, fontWeight = FontWeight.ExtraBold, fontSize = size.sp, maxLines = 1, softWrap = false)
    }
}

@Composable
private fun SmallLink(text: String, tag: String, onClick: () -> Unit) {
    TextButton(onClick = onClick, modifier = Modifier.heightIn(min = 28.dp).testTag(tag), contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 8.dp, vertical = 2.dp)) {
        Text(text, color = D7.Cyan, fontSize = 12.sp, maxLines = 1)
    }
}

/**
 * The coach panel: ONE big action, one short reason, the last-minute line, and the lit EASE · ON TARGET · FASTER scale.
 * Fills whatever height the fixed layout leaves; the headline shrinks by length and may wrap to two lines, never clips.
 */
@Composable
fun CoachPanel(modifier: Modifier, headline: String, detail: String, color: Color, shape: CoachShape, direction: Int?, active: Boolean,
               icon: String = "", sources: String = "", live: String = "", assessment: String = "", assessmentAgeSec: Int = -1, onClick: () -> Unit) {
    val bg = if (active) color else D7.Panel2
    val ink = if (active) D7.Ink else D7.Fg
    val sub = if (active) D7.Ink.copy(alpha = 0.82f) else D7.Mut
    // large system fonts: the panel must still hold everything, so the headline steps down and the assessment line gives way
    val bigFont = androidx.compose.ui.platform.LocalDensity.current.fontScale > 1.15f
    val base = when { headline.length >= 30 -> 19; headline.length >= 22 -> 21; headline.length >= 18 -> 24; headline.length >= 14 -> 27; else -> 30 }
    val size = (if (bigFont) base - 4 else base).sp
    Column(modifier.background(bg, RoundedCornerShape(16.dp)).then(if (active) Modifier else Modifier.border(1.dp, D7.Line, RoundedCornerShape(16.dp)))
        .clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 10.dp).testTag("coach_box"), verticalArrangement = Arrangement.Center) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            // action icon: shape badge (▲ ✓ ▼) plus the action glyph (⚙− easier gear, ⚙+ harder gear, ↻ cadence, ⇩⇧ effort, ♥↑ HR rising, ❄ cooldown)
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                CoachBadgePublic(shape, badge = ink, glyph = if (active) color else D7.Faint)
                if (icon.isNotEmpty()) Text(icon, fontFamily = PlexMono, fontWeight = FontWeight.Bold, fontSize = 12.sp, color = ink, maxLines = 1, modifier = Modifier.padding(top = 2.dp).testTag("coach_icon"))
            }
            Spacer(Modifier.width(10.dp))
            Text(headline, fontFamily = Archivo, fontWeight = FontWeight.ExtraBold, fontSize = size, lineHeight = (size.value + 2).sp, color = ink, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).testTag("coach_headline"))
        }
        if (detail.isNotEmpty()) Text(detail, fontSize = if (bigFont) 11.sp else 13.sp, lineHeight = if (bigFont) 14.sp else 16.sp, color = sub, maxLines = if (bigFont) 1 else 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp))
        // relevant live numbers + which signals decided
        if (live.isNotEmpty() || sources.isNotEmpty()) Text(listOf(live, if (sources.isNotEmpty()) "from $sources" else "").filter { it.isNotEmpty() }.joinToString("  ·  "), fontFamily = PlexMono, fontSize = 10.sp, color = sub, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 4.dp).testTag("coach_sources"))
        Spacer(Modifier.height(6.dp))
        CoachScalePublic(direction, lit = if (active) color else D7.Faint, ink = ink, active = active)
        // the 60-second assessment, with a subtle "analysed … ago" indicator
        if (assessment.isNotEmpty() && !bigFont) Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(6.dp).background(if (assessmentAgeSec in 0..65) (if (active) ink else D7.Green) else D7.Faint, CircleShape))
            Spacer(Modifier.width(5.dp))
            Text((if (assessmentAgeSec >= 0) "${assessmentAgeSec}s ago · " else "") + assessment, fontFamily = PlexMono, fontSize = 9.sp, color = sub, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.testTag("coach_assessment"))
        }
    }
}
