package com.rashed.bikesensordoctor.ui

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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
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
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.rashed.bikesensordoctor.core.CoachMode
import com.rashed.bikesensordoctor.core.CueType
import com.rashed.bikesensordoctor.core.Health
import com.rashed.bikesensordoctor.core.Phase
import com.rashed.bikesensordoctor.core.RideStats
import com.rashed.bikesensordoctor.ride.RideEngine
import java.util.Locale

/*
 * v0.11.1 LIVE screen — full-screen, NO scrolling: header → three large gauges (width-sized) → averages + graph (all remaining height) → compact coach → controls.
 * Sections:
 *   A  speed · distance · time · phase
 *   B  power · heart rate · cadence cards with a target bar and a status word
 *   C  the combined graph (power cyan · HR green · cadence violet), last 5 minutes — the main visual
 *   D  the compact coach line: icon · short instruction · short reason · analysis indicator
 *   controls: START/PAUSE/RESUME · FINISH · COOL/COACH, then Home · Details · ⚙
 */
@Composable
fun LiveScreen(vm: DoctorViewModel, onCoach: () -> Unit, onDetails: () -> Unit, onHome: () -> Unit, onSettings: () -> Unit, notice: String? = null, onNotice: () -> Unit = {}) {
    val d by vm.engine.dash.collectAsStateWithLifecycle()
    val cue by vm.engine.cue.collectAsStateWithLifecycle()
    val st = D7State(d, cue, vm.engine.prefs)
    var confirmFinish by remember { mutableStateOf(false) }
    val bigFont = LocalDensity.current.fontScale > 1.15f

    BoxWithConstraints(Modifier.fillMaxSize().background(D7.Bg).testTag("live_root")) {
        val short = maxHeight < 620.dp
        val screenW = maxWidth
        val screenH = maxHeight
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
                ConfidenceTag(st.zoneTag)
            }
            if (notice != null && !d.simulated) Text(notice, fontFamily = PlexMono, fontSize = 9.sp, color = D7.Amber, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.fillMaxWidth().padding(top = 2.dp).background(D7.Amber.copy(alpha = 0.12f), RoundedCornerShape(6.dp)).clickable { onNotice() }.padding(horizontal = 6.dp, vertical = 2.dp).testTag("bt_notice"))

            // ---- A · ride information ----
            Row(Modifier.fillMaxWidth().padding(top = if (short) 2.dp else 4.dp), verticalAlignment = Alignment.Bottom) {
                TopStat(d.speedKmh?.let { String.format(Locale.US, "%.1f", it) } ?: "—", "KM/H", Modifier.weight(1.15f), big = !short && !bigFont, tag = "live_speed")
                TopStat(if (d.gpsFix || d.distanceKm > 0) String.format(Locale.US, "%.2f", d.distanceKm) else "—", "KM", Modifier.weight(0.95f), big = false, tag = "live_dist")
                TopStat(RideEngine.fmtDuration(d.elapsedMs), "TIME", Modifier.weight(1.05f), big = false, tag = "live_time", mono = true)
                PhaseChip(d, st, Modifier.weight(1.1f))
            }

            // ---- B · live sensor readings ----
            val b = d.bands
            val hrLive = st.hrLive
            // v0.12: three presentations of the SAME data — Power Focus (default for new riders), Classic three gauges, Compact cards.
            // The choice lives in the rider profile ("dashLayout") and changes presentation only.
            val layout = com.rashed.bikesensordoctor.core.DashLayout.of(vm.engine.rider?.answers)
            val contentW = screenW - 20.dp
            val pwStatus = when { d.powerW == null -> null; !d.powerVerified -> "○ UNVERIFIED"; b?.pwReference == true -> "○ NO TARGET"; else -> null }
            val cadStatus = if (d.backwards) "▼ BACKWARDS" else null
            val simTag = if (d.simulated) "SIM" else ""
            when (layout) {
                com.rashed.bikesensordoctor.core.DashLayout.POWER_FOCUS -> {
                    // budget: everything else on the screen (status line, top stats, legend, averages, coach, controls, links, paddings)
                    // plus a readable graph minimum; the geometry shrinks the rings together until the block fits, never lets them overlap
                    val fixed = if (bigFont) 330.dp else 292.dp
                    val minGraph = if (bigFont) 90.dp else 110.dp
                    val maxBlock = (screenH - fixed - minGraph).coerceAtLeast(150.dp)
                    val g = remember(contentW, maxBlock, bigFont) {
                        com.rashed.bikesensordoctor.core.PowerFocus.compute(contentW.value, maxBlock.value, if (bigFont) 17f else 13f, if (bigFont) 25f else 20f, if (bigFont) 110f else 96f)
                    }
                    Box(Modifier.fillMaxWidth().padding(top = if (short) 2.dp else 4.dp).height(g.blockHeight.dp).testTag("gauges_power")) {
                        CompactGauge(Modifier.offset(x = g.xLeft.dp, y = g.yLower.dp).width(g.colSmall.dp), "CADENCE", d.cadenceRpm, "RPM", com.rashed.bikesensordoctor.core.Targets.CADENCE_GAUGE_MAX, b?.cadLo, b?.cadHi, GraphColors.Cad, "cad", tag = simTag,
                            statusOverride = cadStatus, compact = bigFont, testTag = "card_cad", ring = g.small.dp)
                        CompactGauge(Modifier.offset(x = g.xPower.dp, y = g.yPower.dp).width(g.colPower.dp), "POWER", d.powerW, "W", st.powerMax, b?.pwLo, b?.pwHi, GraphColors.Power, "pw", tag = simTag, reference = b?.pwReference == true,
                            statusOverride = pwStatus, compact = bigFont, testTag = "card_power", ring = g.power.dp)
                        CompactGauge(Modifier.offset(x = g.xRight.dp, y = g.yLower.dp).width(g.colSmall.dp), "HEART RATE", hrLive, "BPM", st.hrMaxGauge, b?.hrLo, b?.hrHi, GraphColors.Hr, "hr", tag = simTag, compact = bigFont, testTag = "card_hr", ring = g.small.dp)
                    }
                }
                com.rashed.bikesensordoctor.core.DashLayout.CLASSIC -> {
                    // v0.11.1: the ring diameter is the largest that fits three across the actual screen width (104 dp on the Nokia 5.3);
                    // at large system font the labels and status chips grow, so the ring gives back 12 dp to keep the graph readable
                    val ring = (((screenW - 20.dp - 8.dp) / 3 - 4.dp) - (if (bigFont) 12.dp else 0.dp)).coerceIn(80.dp, 124.dp)
                    Row(Modifier.fillMaxWidth().padding(top = if (short) 2.dp else 4.dp).testTag("gauges_classic"), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        CompactGauge(Modifier.weight(1f), "POWER", d.powerW, "W", st.powerMax, b?.pwLo, b?.pwHi, GraphColors.Power, "pw", tag = simTag, reference = b?.pwReference == true,
                            statusOverride = pwStatus, compact = short || bigFont, testTag = "card_power", ring = ring)
                        CompactGauge(Modifier.weight(1f), "HEART RATE", hrLive, "BPM", st.hrMaxGauge, b?.hrLo, b?.hrHi, GraphColors.Hr, "hr", tag = simTag, compact = short || bigFont, testTag = "card_hr", ring = ring)
                        CompactGauge(Modifier.weight(1f), "CADENCE", d.cadenceRpm, "RPM", com.rashed.bikesensordoctor.core.Targets.CADENCE_GAUGE_MAX, b?.cadLo, b?.cadHi, GraphColors.Cad, "cad", tag = simTag,
                            statusOverride = cadStatus, compact = short || bigFont, testTag = "card_cad", ring = ring)
                    }
                }
                com.rashed.bikesensordoctor.core.DashLayout.COMPACT -> {
                    // the v0.10 numerical cards with a target bar — the smallest block, so the graph gets the most height
                    Row(Modifier.fillMaxWidth().padding(top = if (short) 2.dp else 4.dp).testTag("gauges_compact"), horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                        MetricCard(Modifier.weight(1f), "POWER", d.powerW, "W", b?.pwLo, b?.pwHi, GraphColors.Power, "pw", tag = simTag, statusOverride = pwStatus, compact = short || bigFont, testTag = "card_power")
                        MetricCard(Modifier.weight(1f), "HEART RATE", hrLive, "BPM", b?.hrLo, b?.hrHi, GraphColors.Hr, "hr", tag = simTag, compact = short || bigFont, testTag = "card_hr")
                        MetricCard(Modifier.weight(1f), "CADENCE", d.cadenceRpm, "RPM", b?.cadLo, b?.cadHi, GraphColors.Cad, "cad", tag = simTag, statusOverride = cadStatus, compact = short || bigFont, testTag = "card_cad")
                    }
                }
            }

            // ---- C · combined performance graph (takes whatever height is left) ----
            GraphLegend(b, havePw = d.powerW != null, haveHr = hrLive != null, haveCad = d.cadenceRpm != null, modifier = Modifier.padding(top = 3.dp).testTag("live_targets"))
            // v0.11: averages over the same 5-minute window the graph shows (time-weighted; a disconnected sensor is never zero)
            val avg = remember(d.graphVersion) { val buf = vm.engine.liveBuffer; val from = buf.windowStart(300); com.rashed.bikesensordoctor.core.WindowAverages.of((from until buf.size).map { buf.powerAt(it) }, (from until buf.size).map { buf.cadAt(it) }, (from until buf.size).map { buf.hrAt(it) }) }
            AveragesRow(avg, "AVG 5 MIN", Modifier.padding(top = 2.dp))
            // v0.11.1: the graph takes ALL the height left after the header, gauges, coach and controls (no fixed height, no trailing
            // spacer — that spacer was the empty band seen on the Nokia). On the Nokia 5.3 this is roughly 1.5–2× the v0.11 118 dp.
            CombinedGraph(vm.engine.liveBuffer, d.graphVersion, 300, Modifier.fillMaxWidth().weight(1f).heightIn(min = 72.dp).padding(top = 2.dp))

            // ---- D · compact coach ----
            val analysisAge = if (d.assessmentAtMs > 0) ((vm.engine.now() - d.assessmentAtMs) / 1000).toInt() else -1
            val (shortText, whyText) = when {
                st.mode == CoachMode.FREE -> "Coach off" to "tap to pick a mode"
                cue.type == CueType.NONE -> (if (d.rideState == RideStats.State.RUNNING) "Coach ready — watching" else "Coach ready") to (if (d.rideState == RideStats.State.RUNNING) "speaks only when something should change" else "press START — coaching runs during the ride")
                else -> cue.short.ifEmpty { cue.headline } to cue.why.ifEmpty { cue.detail }
            }
            CompactCoach(Modifier.fillMaxWidth().padding(top = if (short) 4.dp else 6.dp), shortText, whyText, st.coachColor, st.coachActive, if (st.coachActive) cue.action.icon else "", st.direction,
                analysisAge, d.assessment.substringBefore(" · ").takeIf { st.coachActive || d.rideState == RideStats.State.RUNNING } ?: "", if (st.coachActive) cue.sources else "", onClick = onCoach)

            // ---- controls ----
            Row(Modifier.fillMaxWidth().padding(top = if (short) 4.dp else 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
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
            // v0.11.1: the links row was 51 dp tall because TextButton enforces a 48 dp touch target; 32 dp is still a comfortable tap and frees ~18 dp for the graph
            androidx.compose.runtime.CompositionLocalProvider(androidx.compose.material3.LocalMinimumInteractiveComponentSize provides 32.dp) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                SmallLink("‹ Home", "dash_home", onHome); SmallLink("Details", "dash_details", onDetails)
                Spacer(Modifier.weight(1f))
                d.linkQualityPct?.takeIf { d.rideState != RideStats.State.IDLE }?.let { q -> Text("LINK $q%", fontFamily = PlexMono, fontSize = 9.sp, color = if (q >= 95) D7.Faint else D7.Amber) }
                SmallLink("⚙", "dash_settings", onSettings)
            }
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

/** Section A phase chip: the workout phase and what is left of it; "FREE" with no workout. */
@Composable
private fun PhaseChip(d: com.rashed.bikesensordoctor.ride.Dashboard, st: D7State, modifier: Modifier) {
    val (label, sub, color) = when {
        d.rideState == RideStats.State.IDLE -> Triple(if (d.workoutName.isNotEmpty()) "PLANNED" else "FREE", if (d.workoutName.isNotEmpty()) d.workoutName else "no workout", D7.Violet)
        d.plannedSec != null && d.elapsedMs >= d.plannedSec * 1000L -> Triple("DONE", "press FINISH", D7.Green)
        d.phase == Phase.WARMUP -> Triple("WARM-UP", RideEngine.fmtDuration(d.warmupRemainingSec * 1000L) + " left", D7.Violet)
        d.phase == Phase.MAIN -> Triple("MAIN", if (d.plannedSec != null) RideEngine.fmtDuration(((d.plannedSec * 1000L) - d.elapsedMs).coerceAtLeast(0)) + " left" else "zone ${st.targetZone}", D7.Green)
        d.phase == Phase.RECOVERY -> Triple("RECOVERY", "easy spin", D7.Violet)
        else -> Triple("COOL-DOWN", if (d.plannedSec != null) RideEngine.fmtDuration(((d.plannedSec * 1000L) - d.elapsedMs).coerceAtLeast(0)) + " left" else "easy spin", D7.Violet)
    }
    Column(modifier.background(color.copy(alpha = 0.14f), RoundedCornerShape(8.dp)).border(1.dp, color, RoundedCornerShape(8.dp)).padding(horizontal = 4.dp, vertical = 3.dp).testTag("live_phase"), horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, fontFamily = PlexMono, fontWeight = FontWeight.Bold, fontSize = 9.sp, color = color, maxLines = 1, softWrap = false, textAlign = TextAlign.Center)
        Text(sub, fontFamily = PlexMono, fontSize = 8.sp, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
    }
}

@Composable
private fun TopStat(value: String, label: String, modifier: Modifier, big: Boolean, tag: String, mono: Boolean = false) {
    Column(modifier.testTag(tag)) {
        Text(value, fontFamily = if (mono) PlexMono else Rajdhani, fontWeight = if (mono) FontWeight.Bold else FontWeight.SemiBold, fontSize = if (big) 32.sp else if (mono) 19.sp else 24.sp, lineHeight = if (big) 32.sp else 24.sp,
            color = if (value == "—") D7.Faint else D7.Fg, maxLines = 1, softWrap = false)
        Text(label, fontFamily = PlexMono, fontSize = 8.sp, color = D7.Mut, maxLines = 1)
    }
}

@Composable
private fun LiveButton(text: String, color: Color, tag: String, size: Int = 16, onClick: () -> Unit) {
    Button(onClick = onClick, Modifier.fillMaxWidth().height(44.dp).testTag(tag), shape = RoundedCornerShape(12.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 4.dp),
        colors = ButtonDefaults.buttonColors(containerColor = color, contentColor = D7.Ink)) {
        Text(text, fontFamily = Archivo, fontWeight = FontWeight.ExtraBold, fontSize = size.sp, maxLines = 1, softWrap = false)
    }
}

@Composable
private fun SmallLink(text: String, tag: String, onClick: () -> Unit) {
    TextButton(onClick = onClick, modifier = Modifier.heightIn(min = 26.dp).testTag(tag), contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 8.dp, vertical = 1.dp)) {
        Text(text, color = D7.Cyan, fontSize = 12.sp, maxLines = 1)
    }
}
