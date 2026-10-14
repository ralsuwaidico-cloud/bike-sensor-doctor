package com.rashed.bikesensordoctor.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rashed.bikesensordoctor.core.CoachMessage
import com.rashed.bikesensordoctor.core.Provenance
import com.rashed.bikesensordoctor.core.Tone
import com.rashed.bikesensordoctor.core.ZoneBreakdown

/*
 * v0.10 coach communication widgets: summary first, details on request.
 *  Expander        a titled section that is closed by default ("Why?", "Details", "How was this calculated?")
 *  CoachMessageCard one headline · one verdict · one next step · a progress bar, with the explanations behind expanders
 *  ZoneBar         one stacked bar for time in zones (replaces a table as the first visual)
 *  ProvenanceRow   MEASURED / ESTIMATE / SIMULATED / UNVERIFIED tags, shown once
 */

fun Tone.color(): Color = when (this) { Tone.GOOD -> D7.Green; Tone.WATCH -> D7.Amber; Tone.FIX -> D7.Orange; Tone.INFO -> D7.Violet }

@Composable
fun Expander(title: String, modifier: Modifier = Modifier, open: Boolean = false, tag: String = "", content: @Composable ColumnScope.() -> Unit) {
    var isOpen by rememberSaveable(title) { mutableStateOf(open) }
    Column(modifier.fillMaxWidth().padding(top = 6.dp)) {
        Row(Modifier.fillMaxWidth().clickable { isOpen = !isOpen }.padding(vertical = 6.dp).then(if (tag.isNotEmpty()) Modifier.testTag(tag) else Modifier), verticalAlignment = Alignment.CenterVertically) {
            Text(if (isOpen) "▾" else "▸", color = D7.Cyan, fontSize = 13.sp, modifier = Modifier.width(16.dp))
            Text(title, color = D7.Cyan, fontSize = 13.sp, fontWeight = FontWeight.Bold)
        }
        AnimatedVisibility(isOpen) { Column(Modifier.fillMaxWidth().padding(start = 16.dp, bottom = 4.dp), content = content) }
    }
}

@Composable
fun ProgressBar(fraction: Float, color: Color, modifier: Modifier = Modifier, goal: Float? = null) {
    Box(modifier.fillMaxWidth().height(8.dp).background(D7.Track, RoundedCornerShape(4.dp))) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).height(8.dp).background(color, RoundedCornerShape(4.dp)))
        goal?.let { g -> Box(Modifier.padding(start = 0.dp).fillMaxWidth(g.coerceIn(0f, 1f))) { Box(Modifier.align(Alignment.CenterEnd).width(2.dp).height(8.dp).background(D7.Fg)) } }
    }
}

/** The post-ride coach message: what you achieved · what it means · what to do next. Everything else behind the expanders. */
@Composable
fun CoachMessageCard(m: CoachMessage, modifier: Modifier = Modifier, extraDetails: @Composable (ColumnScope.() -> Unit)? = null) {
    val c = m.tone.color()
    Column(modifier.fillMaxWidth().background(D7.Panel2, RoundedCornerShape(14.dp)).border(1.5.dp, c, RoundedCornerShape(14.dp)).padding(14.dp).testTag("coach_message")) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(8.dp).background(c, CircleShape)); Spacer(Modifier.width(6.dp))
            Text(m.title.uppercase(), fontFamily = PlexMono, fontSize = 10.sp, color = c, letterSpacing = 1.sp)
        }
        Text(m.headline, fontFamily = Archivo, fontWeight = FontWeight.ExtraBold, fontSize = 22.sp, lineHeight = 26.sp, color = D7.Fg, modifier = Modifier.padding(top = 6.dp).testTag("coach_headline_post"))
        m.progress?.let { p -> ProgressBar(p, c, Modifier.padding(top = 8.dp), goal = 0.8f); Text("goal 80%", fontFamily = PlexMono, fontSize = 9.sp, color = D7.Faint, modifier = Modifier.padding(top = 2.dp)) }
        Text(m.verdict, fontSize = 15.sp, lineHeight = 20.sp, color = D7.Fg, modifier = Modifier.padding(top = 8.dp))
        Text(m.next, fontSize = 14.sp, lineHeight = 19.sp, fontWeight = FontWeight.Bold, color = c, modifier = Modifier.padding(top = 6.dp).testTag("coach_next"))
        Expander("Why?", tag = "why_expander") { Text(m.why, fontSize = 13.sp, lineHeight = 18.sp, color = D7.Mut) }
        if (m.details.isNotEmpty() || extraDetails != null) Expander("Detailed analysis") { if (m.details.isNotEmpty()) Bullets(m.details); extraDetails?.invoke(this) }
        Expander("How was this calculated?") { Text(m.how, fontSize = 12.sp, lineHeight = 17.sp, color = D7.Mut) }
    }
}

/** One stacked bar: share of time in each zone, with a small legend underneath. Colours match the zone colours used everywhere. */
@Composable
fun ZoneBar(z: ZoneBreakdown, title: String, modifier: Modifier = Modifier, highlight: Int? = null) {
    val cols = listOf(D7.Faint, D7.Cyan, D7.Green, D7.Amber, D7.Red)
    val total = z.sec.sum().coerceAtLeast(1)
    Column(modifier.fillMaxWidth()) {
        CardTitle(title.uppercase())
        Row(Modifier.fillMaxWidth().height(16.dp).background(D7.Track, RoundedCornerShape(5.dp))) {
            for (i in 1..5) { val f = z.sec[i - 1].toFloat() / total; if (f > 0f) Box(Modifier.weight(f).height(16.dp).background(cols[i - 1].copy(alpha = if (highlight == null || highlight == i) 0.95f else 0.45f), RoundedCornerShape(3.dp))) }
        }
        Row(Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            for (i in 1..5) Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Z$i", fontFamily = PlexMono, fontWeight = FontWeight.Bold, fontSize = 10.sp, color = cols[i - 1])
                Text("${z.pct(i)}%", fontFamily = PlexMono, fontSize = 10.sp, color = if (highlight == i) D7.Fg else D7.Mut)
                Text(z.set.label(i), fontFamily = PlexMono, fontSize = 8.sp, color = D7.Faint, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ProvenanceRow(items: List<Pair<String, Provenance>>, modifier: Modifier = Modifier) {
    FlowRow(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        items.forEach { (what, p) ->
            val col = when (p) { Provenance.MEASURED -> D7.Green; Provenance.ESTIMATE -> D7.Cyan; Provenance.SIMULATED -> D7.Amber; Provenance.UNVERIFIED -> D7.Orange }
            Row(Modifier.background(col.copy(alpha = 0.12f), RoundedCornerShape(6.dp)).padding(horizontal = 6.dp, vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(p.label, fontFamily = PlexMono, fontWeight = FontWeight.Bold, fontSize = 8.sp, color = col); Spacer(Modifier.width(4.dp))
                Text(what, fontFamily = PlexMono, fontSize = 8.sp, color = D7.Mut, maxLines = 1)
            }
        }
    }
}

/**
 * A metric estimate as the rider should see it: current value, candidate, confidence word, evidence — a proposal,
 * never "your FTP is now X". [onApply] applies the candidate to the profile (between rides only).
 */
@Composable
fun EstimateCard(kind: com.rashed.bikesensordoctor.core.MetricKind, current: Int?, currentTested: Boolean, est: com.rashed.bikesensordoctor.core.Estimate?, modifier: Modifier = Modifier, onApply: ((Int) -> Unit)? = null) {
    val name = when (kind) { com.rashed.bikesensordoctor.core.MetricKind.FTP -> "FTP"; com.rashed.bikesensordoctor.core.MetricKind.CRITICAL_POWER -> "Critical power"; com.rashed.bikesensordoctor.core.MetricKind.THRESHOLD_HR -> "Threshold HR"; com.rashed.bikesensordoctor.core.MetricKind.PREFERRED_CADENCE -> "Preferred cadence" }
    val unit = kind.unit
    Column(modifier.fillMaxWidth().background(D7.Panel2, RoundedCornerShape(12.dp)).border(1.dp, D7.Line, RoundedCornerShape(12.dp)).padding(12.dp)) {
        if (est == null) {
            Text("$name — no evidence yet", fontSize = 14.sp, fontWeight = FontWeight.Bold, color = D7.Fg)
            Text(when (kind) { com.rashed.bikesensordoctor.core.MetricKind.FTP -> "Needs a verified power meter and a 20-minute effort."; com.rashed.bikesensordoctor.core.MetricKind.THRESHOLD_HR -> "Needs the guided threshold test."; else -> "Needs more rides." }, fontSize = 12.sp, color = D7.Mut, modifier = Modifier.padding(top = 2.dp))
            return@Column
        }
        val differs = com.rashed.bikesensordoctor.core.Performance.meaningfullyDiffers(kind, current, est.value)
        val headline = when { current == null -> "$name estimate available"; differs && est.value > current -> "$name estimate may have increased"; differs -> "$name estimate may have decreased"; else -> "$name estimate agrees with your profile" }
        Text(headline, fontSize = 14.sp, fontWeight = FontWeight.Bold, color = D7.Fg)
        KeyValue(listOfNotNull(
            current?.let { "Current" to "$it $unit${if (currentTested) " (tested)" else ""}" },
            "Candidate" to "${est.value} $unit",
            "Confidence" to est.status.name.lowercase().replaceFirstChar { it.uppercase() } + " (${Math.round(est.confidence * 100)}%)",
            "Evidence" to "${est.evidenceIds.size} × ${est.method.label}",
        ))
        Expander("How was this calculated?") {
            Text("${est.label.replaceFirstChar { it.uppercase() }}: ${est.method.label}. Confidence = 0.30 data quality (${Math.round(est.components.dataQuality * 100)}%) + 0.25 repeatability (${Math.round(est.components.repeatability * 100)}%) + 0.20 effort validity (${Math.round(est.components.effortValidity * 100)}%) + 0.15 recency (${Math.round(est.components.recency * 100)}%) + 0.10 context (${Math.round(est.components.contextCoverage * 100)}%), capped at this method's ceiling of ${Math.round(est.method.ceiling * 100)}%. A method can never become 'verified' by repetition. ${est.algorithmVersion}.", fontSize = 12.sp, lineHeight = 16.sp, color = D7.Mut)
        }
        if (onApply != null && differs && est.status >= com.rashed.bikesensordoctor.core.EstimateStatus.PROVISIONAL) Row(Modifier.padding(top = 6.dp)) {
            if (currentTested && est.status < com.rashed.bikesensordoctor.core.EstimateStatus.HIGH) Muted("Your profile holds a tested value — a weaker estimate never overwrites it.", 11)
            else PrimaryButton(if (est.status >= com.rashed.bikesensordoctor.core.EstimateStatus.HIGH) "USE THIS VALUE" else "USE AS PROVISIONAL", color = D7.Violet) { onApply(est.value) }
        }
    }
}
