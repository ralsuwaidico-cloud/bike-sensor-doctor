package com.rashed.bikesensordoctor.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rashed.bikesensordoctor.core.AnalysisResult
import com.rashed.bikesensordoctor.core.HrZoneSet
import com.rashed.bikesensordoctor.core.RideAnalysis
import com.rashed.bikesensordoctor.core.RideFeedback
import com.rashed.bikesensordoctor.core.RideSource
import com.rashed.bikesensordoctor.core.CoachSummary
import com.rashed.bikesensordoctor.core.DetailLevel
import com.rashed.bikesensordoctor.core.RiderProfile
import com.rashed.bikesensordoctor.core.SeriesPoint
import com.rashed.bikesensordoctor.core.Workout
import com.rashed.bikesensordoctor.core.ZoneBreakdown
import com.rashed.bikesensordoctor.ride.RideEngine
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.cos

/*
 * v0.9 Ride Results — one vertically scrolling page (Apple-Fitness clarity, Design 7 identity):
 *   1 summary + route · 2 heart rate & zones · 3 power & cadence · 4 speed & elevation · 5 coach review · 6 next workout
 * Measured values are measured; estimates say ESTIMATE; simulated rides say SIMULATED; nothing is invented.
 */
@Composable
fun RideResultsScreen(vm: DoctorViewModel, rideId: Long, fresh: Boolean, onDone: () -> Unit, onBack: () -> Unit) {
    val h = vm.engine.history
    val summary = remember(rideId) { h.list().firstOrNull { it.startedAtMs == rideId } }
    val series = remember(rideId) { h.readSeries(rideId) }
    val meta = remember(rideId) { h.readMeta(rideId) }
    val rider = vm.engine.rider
    val setup = vm.engine.setup
    var tick by remember { mutableIntStateOf(0) }
    val savedFb = remember(tick) { rider?.feedback?.firstOrNull { it.dateMs == rideId } }
    var showApple by remember { mutableStateOf(meta["appleRef"] == true) }

    val source = runCatching { RideSource.valueOf(meta["source"] as? String ?: summary?.source?.name ?: "DEVICE") }.getOrDefault(summary?.source ?: RideSource.DEVICE)
    val simulated = source == RideSource.SIMULATED
    val powerTrusted = (meta["powerTrusted"] as? Boolean ?: false) && !simulated
    val ftpUsed = (meta["ftpUsed"] as? Int) ?: setup?.ftp ?: vm.engine.prefs.ftpW
    val edges = (meta["edges"] as? String)?.split(',')?.mapNotNull { it.toIntOrNull() }?.takeIf { it.size == 4 }?.toIntArray()
    val personal: HrZoneSet? = when {
        edges != null -> HrZoneSet("Your coaching zones", intArrayOf(edges[0] - 1, edges[1] - 1, edges[2] - 1, edges[3] - 1), meta["zoneConf"] as? String ?: "")
        setup != null -> HrZoneSet.fromSetup(setup)
        else -> HrZoneSet.generic((meta["maxHrEst"] as? Int) ?: vm.engine.prefs.maxHr)
    }
    val band = (meta["bandLo"] as? Int)?.let { lo -> (meta["bandHi"] as? Int)?.let { hi -> lo..hi } }
    val a: AnalysisResult = remember(rideId, tick, showApple) {
        RideAnalysis.analyze(series, personal, if (showApple) HrZoneSet.APPLE_12_OCT else null, ftpUsed, powerTrusted, band,
            (meta["weightKg"] as? Int) ?: rider?.answers?.int("weightKg"), (meta["age"] as? Int) ?: rider?.answers?.int("age"), meta["hrRecovery60"] as? Int, savedFb?.rpe)
    }
    val fmt = SimpleDateFormat("EEE d MMM yyyy · HH:mm", Locale.getDefault())

    Column(Modifier.fillMaxSize().background(D7.Bg).verticalScroll(rememberScrollState()).padding(horizontal = 14.dp, vertical = 8.dp).testTag("results_root")) {
        D7TopBar(if (fresh) "RIDE COMPLETE" else "RIDE RESULTS", if (fresh) null else "History", if (fresh) null else onBack)
        if (summary == null) { Text("Ride not found.", color = D7.Mut); return@Column }

        // ---------------- 1 · what you did (three numbers) + where each number comes from ----------------
        Row(verticalAlignment = Alignment.CenterVertically) {
            Headline((meta["workout"] as? String)?.ifEmpty { null } ?: "Free ride", 20)
            Spacer(Modifier.width(8.dp)); if (simulated) SimTag() else Tag("REAL", D7.Green)
        }
        Muted("${fmt.format(Date(rideId))}${(meta["riderName"] as? String)?.ifEmpty { null }?.let { " · $it" } ?: ""}", 12)
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth()) {
            Big(RideEngine.fmtDuration(summary.durationMs), "DURATION", Modifier.weight(1.2f))
            Big(String.format(Locale.US, "%.2f", a.distanceKm), "KM", Modifier.weight(1f))
            Big(a.avgHr?.toString() ?: "—", "AVG BPM", Modifier.weight(1f))
        }
        ProvenanceRow(CoachSummary.provenance(simulated, powerTrusted, a.hrSamples > 0, a.hasRoute, a.powerSamples > 0), Modifier.padding(top = 8.dp))

        // ---------------- 2 · the coach's one message: achievement · meaning · next step (details behind expanders) ----------------
        Spacer(Modifier.height(12.dp))
        val level = DetailLevel.from(rider?.answers)
        val zoneName = band?.let { b -> personal?.zone((b.first + b.last) / 2)?.let { "Zone $it" } } ?: "Zone 2"
        val msg = remember(a, level) { CoachSummary.forRide(a, band, zoneName, level, simulated, powerTrusted, savedFb?.rpe) }
        CoachMessageCard(msg) {
            if (band != null) KeyValue(listOfNotNull(
                "Target" to "${band.first}–${band.last} bpm",
                "In band" to "${a.inBandPct ?: 0}% of the main block · longest ${a.longestInBandSec / 60} min",
                "Consistency" to (a.hrConsistencyCv?.let { "heart rate ±${Math.round(it * 100)}%" + (a.powerConsistencyCv?.let { p -> " · power ±${Math.round(p * 100)}%" } ?: "") } ?: "needs 1 min of main-phase data"),
                "HR drift" to (a.driftPct?.let { "${if (it >= 0) "+" else ""}$it% (${a.driftNote})" } ?: a.driftNote),
                "Coach cues" to "${(meta["cues"] as? Int) ?: 0}",
            ))
        }

        // ---------------- 3 · one visual: where the effort went ----------------
        a.personalZones?.let { z ->
            Spacer(Modifier.height(12.dp))
            ZoneBar(z, "Time in your zones", highlight = band?.let { b -> personal?.zone((b.first + b.last) / 2) })
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 2.dp)) {
                TextButton(onClick = { showApple = !showApple }, contentPadding = androidx.compose.foundation.layout.PaddingValues(0.dp)) { Text(if (showApple) "▾ Hide Apple Fitness reference zones" else "▸ Compare with Apple Fitness reference zones", color = D7.Cyan, fontSize = 12.sp) }
            }
            if (showApple) a.referenceZones?.let { ZoneTable(it, "Apple Fitness reference (your watch's bands)", "Reference only — Apple's app-calculated bands from your 12 Oct workout; never used for coaching.") }
        }

        // ---------------- 4 · everything else, on request ----------------
        Spacer(Modifier.height(8.dp))
        Expander("Ride details", tag = "exp_details") {
            StatGrid(listOfNotNull(
                "Moving time" to RideEngine.fmtDuration(a.movingSec * 1000L),
                "Avg speed" to (a.avgSpeedKmh?.let { String.format(Locale.US, "%.1f km/h", it) } ?: "—"),
                "Max speed" to (((meta["maxSpeed"] as? Double)?.takeIf { it > 0 } ?: a.maxSpeedKmh)?.let { String.format(Locale.US, "%.1f km/h", it) } ?: "—"),
                "Elevation gain" to String.format(Locale.US, "%.0f m (%.0f ft)", a.elevationGainM, a.elevationGainM * 3.281),
                "Max HR" to (a.maxHr?.let { "$it bpm" } ?: "—"),
                if (a.powerSamples > 0) "Avg · max power" to "${a.avgPowerW} · ${a.maxPowerW} W" else "Power" to "no power data",
                "Avg cadence" to (a.avgCadRpm?.let { "$it rpm" } ?: "—"),
                "Calories" to (a.kcal?.let { "$it kcal" } ?: "—"),
                "Effort (you)" to (savedFb?.rpe?.let { "$it / 10" } ?: if (fresh) "below" else "not rated"),
                "HR recovery" to (a.hrRecovery60?.let { "${(meta["hrAtFinish"] as? Int ?: a.avgHr!!) - it} bpm in 1 min" } ?: "—"),
            ))
            Muted("Calories: ${a.kcalMethod}.", 10)
            Spacer(Modifier.height(8.dp))
            if (a.hasRoute) { CardTitle("ROUTE (GPS TRACK)"); RouteCanvas(series) } else Muted(if (simulated) "No route: simulated ride has no GPS track." else "No GPS track recorded (no fix, or location permission off).", 11)
        }
        Expander("Heart rate", tag = "exp_hr") {
            if (a.hrSamples == 0) Muted("No heart-rate data for this ride (no strap connected).", 12) else {
                LineChart(series.map { it.hr }, D7.Red, bands = personal?.let { z -> zoneBands(z) } ?: emptyList(), yMin = 60, yMax = maxOf(a.maxHr ?: 180, personal?.upper?.get(3)?.plus(10) ?: 180), unit = "bpm", refLo = band?.first, refHi = band?.last)
                Row(Modifier.fillMaxWidth().padding(top = 4.dp)) { Big("${a.avgHr}", "AVG", Modifier.weight(1f)); Big("${a.maxHr}", "MAX", Modifier.weight(1f)); Big(a.hrRecovery60?.let { "${(meta["hrAtFinish"] as? Int ?: a.avgHr!!) - it}" } ?: "—", "RECOVERY 1 MIN ↓", Modifier.weight(1.4f)) }
                a.personalZones?.let { ZoneTable(it, "Time in your zones", personal!!.source) }
                if (a.hrRecovery60 == null) Muted("Heart-rate recovery appears when the strap keeps reporting for a minute after FINISH.", 10)
            }
        }
        Expander("Power & cadence", tag = "exp_power") {
            if (a.powerSamples == 0) Muted("No power meter data in this ride.", 12) else {
                LineChart(series.map { it.powerW }, D7.Cyan, bands = emptyList(), yMin = 0, yMax = maxOf(a.maxPowerW ?: 300, (ftpUsed * 1.2).toInt()), unit = "W", refLo = (meta["pwLo"] as? Int), refHi = (meta["pwHi"] as? Int), ftpLine = ftpUsed)
                Row(Modifier.fillMaxWidth().padding(top = 4.dp)) { Big("${a.avgPowerW}", "AVG W", Modifier.weight(1f)); Big(a.normalizedPowerW?.toString() ?: "—", "NORMALIZED", Modifier.weight(1f)); Big("$ftpUsed", "FTP USED", Modifier.weight(1f)) }
                PowerZoneBars(a.powerZoneSec, ftpUsed)
                if (a.cadSamples > 0) { Spacer(Modifier.height(6.dp)); CardTitle("CADENCE"); LineChart(series.map { it.cadRpm }, D7.Violet, bands = emptyList(), yMin = 40, yMax = 130, unit = "rpm", refLo = setup?.cadLow, refHi = setup?.cadHigh); Muted("Average ${a.avgCadRpm} rpm", 12) }
            }
        }
        Expander("Speed & elevation", tag = "exp_speed") {
            if (series.none { it.speedKmh != null }) Muted("No speed data (GPS off).", 12) else {
                LineChart(series.map { it.speedKmh?.let { v -> Math.round(v).toInt() } }, D7.Green, bands = emptyList(), yMin = 0, yMax = maxOf(40, (a.maxSpeedKmh ?: 0.0).toInt() + 5), unit = "km/h")
                Muted("Average ${a.avgSpeedKmh?.let { String.format(Locale.US, "%.1f", it) } ?: "—"} km/h over moving time · max ${a.maxSpeedKmh?.let { String.format(Locale.US, "%.1f", it) } ?: "—"} km/h", 12)
                if (series.any { it.altM != null }) { Spacer(Modifier.height(6.dp)); CardTitle("ELEVATION"); LineChart(series.map { it.altM?.let { v -> Math.round(v).toInt() } }, D7.Amber, bands = emptyList(), yMin = null, yMax = null, unit = "m"); Muted("Gain ${String.format(Locale.US, "%.0f", a.elevationGainM)} m — climbs of 3 m or more between accepted fixes; GPS altitude is coarse.", 10) }
            }
        }
        // calibration with evidence rules (never from a single ride, never from simulated or unverified power)
        if (!simulated && rider != null) Expander("Fitness estimates & evidence", tag = "exp_calibration") {
            val ftpEst = remember(tick) { vm.engine.estimate(com.rashed.bikesensordoctor.core.MetricKind.FTP) }
            val thrEst = remember(tick) { vm.engine.estimate(com.rashed.bikesensordoctor.core.MetricKind.THRESHOLD_HR) }
            val pf = rider.answers.metric("ftp"); val pl = rider.answers.metric("lthr")
            EstimateCard(com.rashed.bikesensordoctor.core.MetricKind.FTP, pf?.value, pf?.measured == true, ftpEst, Modifier.padding(top = 6.dp)) { v -> rider.answers.setMetric("ftp", v, if (ftpEst!!.status >= com.rashed.bikesensordoctor.core.EstimateStatus.HIGH) "measured" else "estimated"); vm.engine.saveRider(); tick++ }
            EstimateCard(com.rashed.bikesensordoctor.core.MetricKind.THRESHOLD_HR, pl?.value, pl?.measured == true, thrEst, Modifier.padding(top = 6.dp)) { v -> rider.answers.setMetric("lthr", v, if (thrEst!!.status >= com.rashed.bikesensordoctor.core.EstimateStatus.HIGH) "measured" else "estimated"); vm.engine.saveRider(); tick++ }
            a.suggestions.filter { it.key == "maxHr" }.forEach { sg ->
                D7Card(Modifier.padding(top = 6.dp), accent = D7.Violet) {
                    CardTitle("PROVISIONAL ESTIMATE — YOUR CALL")
                    Text(sg.title, fontSize = 15.sp, fontWeight = FontWeight.Bold, color = D7.Fg); Expander("Why?") { Muted(sg.why, 12) }
                    Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        val already = rider.answers.metric(sg.key)?.value == sg.value
                        val measured = rider.answers.metric(sg.key)?.measured == true
                        if (measured) Muted("Your profile has a tested value — estimates never overwrite it.", 11)
                        else if (already) Tag("APPLIED", D7.Green)
                        else PrimaryButton("USE AS PROVISIONAL", color = D7.Violet) { rider.answers.setMetric(sg.key, sg.value, "estimated"); vm.engine.saveRider(); tick++ }
                    }
                }
            }
            Muted("Estimates change only between rides, keep their history, and never overwrite a tested value with a weaker one.", 10)
        }

        // ---------------- 5 · next workout ----------------
        Section("NEXT WORKOUT")
        NextWorkoutSection(vm, rideId, fresh, savedFb, a, onDone = onDone, onSaved = { tick++ })
        Spacer(Modifier.height(20.dp))
    }
}

// ------------------------------------------------------------------ pieces

@Composable private fun Section(title: String) { Spacer(Modifier.height(14.dp)); Box(Modifier.fillMaxWidth().height(1.dp).background(D7.Line)); Spacer(Modifier.height(8.dp)); Eyebrow(title); Spacer(Modifier.height(6.dp)) }

@Composable private fun Big(v: String, l: String, m: Modifier) { Column(m) { Text(v, fontFamily = Rajdhani, fontWeight = FontWeight.SemiBold, fontSize = 26.sp, lineHeight = 26.sp, color = if (v == "—") D7.Faint else D7.Fg, maxLines = 1); Text(l, fontFamily = PlexMono, fontSize = 9.sp, color = D7.Mut, maxLines = 1) } }

@Composable private fun StatGrid(rows: List<Pair<String, String>>) {
    Column(Modifier.fillMaxWidth().background(D7.Panel2, RoundedCornerShape(12.dp)).border(1.dp, D7.Line, RoundedCornerShape(12.dp)).padding(horizontal = 10.dp, vertical = 6.dp)) {
        rows.chunked(2).forEach { pair ->
            Row(Modifier.fillMaxWidth().padding(vertical = 3.dp)) {
                pair.forEach { (k, v) -> Column(Modifier.weight(1f)) { Text(k.uppercase(), fontFamily = PlexMono, fontSize = 9.sp, color = D7.Mut, maxLines = 1); Text(v, fontSize = 13.sp, color = D7.Fg, maxLines = 1) } }
                if (pair.size == 1) Spacer(Modifier.weight(1f))
            }
        }
    }
}

private fun zoneBands(z: HrZoneSet): List<Triple<Int, Int, Color>> {
    val cols = listOf(D7.Faint, D7.Cyan, D7.Green, D7.Amber, D7.Red)
    val lo = intArrayOf(0, z.upper[0] + 1, z.upper[1] + 1, z.upper[2] + 1, z.upper[3] + 1); val hi = intArrayOf(z.upper[0], z.upper[1], z.upper[2], z.upper[3], 260)
    return (0 until 5).map { Triple(lo[it], hi[it], cols[it]) }
}

/** Time-series line chart with optional zone bands behind, a target band and an FTP line. 1 Hz data is bucketed to the pixel width. */
@Composable
fun LineChart(values: List<Int?>, color: Color, bands: List<Triple<Int, Int, Color>>, yMin: Int?, yMax: Int?, unit: String, refLo: Int? = null, refHi: Int? = null, ftpLine: Int? = null, height: Int = 150) {
    val measurer = rememberTextMeasurer()
    val lab = TextStyle(fontFamily = PlexMono, fontSize = 9.sp, color = D7.Faint)
    val present = values.filterNotNull()
    val lo = (yMin ?: ((present.minOrNull() ?: 0) - 5)).toFloat(); val hi = (yMax ?: ((present.maxOrNull() ?: 10) + 5)).toFloat().coerceAtLeast(lo + 1)
    val data = remember(values) { RideAnalysis.downsample(values, 320) }
    Box(Modifier.fillMaxWidth().height(height.dp).background(D7.Panel, RoundedCornerShape(10.dp)).border(1.dp, D7.Line, RoundedCornerShape(10.dp))) {
        Canvas(Modifier.fillMaxSize().padding(start = 34.dp, end = 8.dp, top = 8.dp, bottom = 16.dp)) {
            fun y(v: Float) = size.height * (1f - ((v - lo) / (hi - lo)).coerceIn(0f, 1f))
            bands.forEach { (a, b, c) -> val top = y(b.toFloat()); val bot = y(a.toFloat()); if (bot > top) drawRect(c.copy(alpha = 0.10f), Offset(0f, top), Size(size.width, bot - top)) }
            if (refLo != null && refHi != null) { val top = y(refHi.toFloat()); val bot = y(refLo.toFloat()); drawRect(D7.Green.copy(alpha = 0.18f), Offset(0f, top), Size(size.width, bot - top)); drawLine(D7.Green, Offset(0f, top), Offset(size.width, top), 1f); drawLine(D7.Green, Offset(0f, bot), Offset(size.width, bot), 1f) }
            ftpLine?.let { f -> val fy = y(f.toFloat()); drawLine(D7.Amber.copy(alpha = 0.7f), Offset(0f, fy), Offset(size.width, fy), 1.5f, pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(6f, 6f))) }
            // axis labels (3)
            listOf(lo, (lo + hi) / 2, hi).forEach { v -> val m = measurer.measure(Math.round(v).toString(), lab); drawText(m, topLeft = Offset(-m.size.width - 6f, y(v) - m.size.height / 2f)) }
            if (data.size >= 2) {
                val dx = size.width / (data.size - 1)
                val path = Path(); var pen = false
                data.forEachIndexed { i, v -> if (v == null) { pen = false } else { val p = Offset(i * dx, y(v.toFloat())); if (!pen) { path.moveTo(p.x, p.y); pen = true } else path.lineTo(p.x, p.y) } }
                drawPath(path, color, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round, join = androidx.compose.ui.graphics.StrokeJoin.Round))
            }
            // time labels: start / mid / end minutes
            val n = values.size; listOf(0, n / 2, n - 1).forEachIndexed { k, s -> val m = measurer.measure("${s / 60}′", lab); drawText(m, topLeft = Offset((k * (size.width - m.size.width) / 2f), size.height + 3f)) }
            val um = measurer.measure(unit, lab); drawText(um, topLeft = Offset(size.width - um.size.width, 0f))
        }
    }
}

@Composable
private fun ZoneTable(z: ZoneBreakdown, title: String, note: String) {
    val cols = listOf(D7.Faint, D7.Cyan, D7.Green, D7.Amber, D7.Red)
    Column(Modifier.fillMaxWidth().padding(top = 8.dp)) {
        CardTitle(title.uppercase())
        for (i in 1..5) {
            val sec = z.sec[i - 1]; val pct = z.pct(i)
            Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Z$i", fontFamily = PlexMono, fontSize = 11.sp, color = cols[i - 1], fontWeight = FontWeight.Bold, modifier = Modifier.width(26.dp))
                Text(z.set.label(i), fontFamily = PlexMono, fontSize = 10.sp, color = D7.Mut, modifier = Modifier.width(66.dp))
                Box(Modifier.weight(1f).height(14.dp).background(D7.Track, RoundedCornerShape(4.dp))) { Box(Modifier.fillMaxWidth((pct / 100f).coerceIn(0f, 1f)).height(14.dp).background(cols[i - 1].copy(alpha = 0.85f), RoundedCornerShape(4.dp))) }
                Text(RideEngine.fmtDuration(sec * 1000L), fontFamily = PlexMono, fontSize = 11.sp, color = D7.Fg, modifier = Modifier.width(52.dp).padding(start = 6.dp))
                Text("$pct%", fontFamily = PlexMono, fontSize = 10.sp, color = D7.Mut, modifier = Modifier.width(34.dp), textAlign = androidx.compose.ui.text.style.TextAlign.End)
            }
        }
        Muted(note, 10)
    }
}

@Composable
private fun PowerZoneBars(sec: IntArray, ftp: Int) {
    val total = (1..7).sumOf { sec[it] }.coerceAtLeast(1)
    Column(Modifier.padding(top = 6.dp)) {
        CardTitle("TIME IN POWER ZONES (FTP $ftp W)")
        for (z in 1..7) {
            val (lo, hi) = com.rashed.bikesensordoctor.core.PowerZones.range(z, ftp)
            Row(Modifier.fillMaxWidth().padding(vertical = 1.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Z$z", fontFamily = PlexMono, fontSize = 10.sp, color = D7.powerZone(z), modifier = Modifier.width(26.dp))
                Text(if (hi == null) "≥ $lo W" else "$lo–$hi W", fontFamily = PlexMono, fontSize = 9.sp, color = D7.Mut, modifier = Modifier.width(66.dp))
                Box(Modifier.weight(1f).height(10.dp).background(D7.Track, RoundedCornerShape(3.dp))) { Box(Modifier.fillMaxWidth((sec[z].toFloat() / total).coerceIn(0f, 1f)).height(10.dp).background(D7.powerZone(z).copy(alpha = 0.85f), RoundedCornerShape(3.dp))) }
                Text(RideEngine.fmtDuration(sec[z] * 1000L), fontFamily = PlexMono, fontSize = 10.sp, color = D7.Fg, modifier = Modifier.width(52.dp).padding(start = 6.dp))
            }
        }
    }
}

/** GPS track drawn to scale (no map tiles: the app works offline). Start = green dot, finish = red dot. */
@Composable
private fun RouteCanvas(series: List<SeriesPoint>) {
    val pts = series.filter { it.lat != null && it.lon != null }
    Box(Modifier.fillMaxWidth().height(190.dp).background(D7.Panel, RoundedCornerShape(12.dp)).border(1.dp, D7.Line, RoundedCornerShape(12.dp)).testTag("route_canvas")) {
        Canvas(Modifier.fillMaxSize().padding(12.dp)) {
            if (pts.size < 2) return@Canvas
            val lat0 = pts.map { it.lat!! }.average(); val k = cos(Math.toRadians(lat0))
            val xs = pts.map { it.lon!! * k }; val ys = pts.map { it.lat!! }
            val minX = xs.min(); val maxX = xs.max(); val minY = ys.min(); val maxY = ys.max()
            val span = maxOf(maxX - minX, maxY - minY, 1e-5)
            val sc = minOf(size.width, size.height) / span.toFloat()
            val ox = (size.width - (maxX - minX).toFloat() * sc) / 2; val oy = (size.height - (maxY - minY).toFloat() * sc) / 2
            fun p(i: Int) = Offset(ox + ((xs[i] - minX) * sc).toFloat(), oy + ((maxY - ys[i]) * sc).toFloat())
            val path = Path(); path.moveTo(p(0).x, p(0).y); for (i in 1 until pts.size) path.lineTo(p(i).x, p(i).y)
            drawPath(path, D7.Cyan.copy(alpha = 0.35f), style = Stroke(7.dp.toPx(), cap = StrokeCap.Round, join = androidx.compose.ui.graphics.StrokeJoin.Round))
            drawPath(path, D7.Cyan, style = Stroke(2.5.dp.toPx(), cap = StrokeCap.Round, join = androidx.compose.ui.graphics.StrokeJoin.Round))
            drawCircle(D7.Green, 5.dp.toPx(), p(0)); drawCircle(D7.Red, 5.dp.toPx(), p(pts.size - 1))
        }
        Text("GPS track · N ↑ · no map tiles offline", fontFamily = PlexMono, fontSize = 9.sp, color = D7.Faint, modifier = Modifier.align(Alignment.BottomEnd).padding(6.dp))
    }
}

/** Section 6: the two quick questions (fresh ride) → saved feedback → before/after recommendation. */
@Composable
private fun NextWorkoutSection(vm: DoctorViewModel, rideId: Long, fresh: Boolean, savedFb: RideFeedback?, a: AnalysisResult, onSaved: () -> Unit, onDone: () -> Unit) {
    val r = vm.engine.rider
    val before = remember { vm.engine.workout }
    var rpe by remember { mutableIntStateOf(savedFb?.rpe ?: 6) }
    var limiter by remember { mutableStateOf(savedFb?.limiter) }
    var recovered by remember { mutableStateOf(savedFb?.recovered) }
    val fu = remember { r?.let { RiderProfile.followUp(it.answers, it.feedback, it.asked) } }
    var fuChoice by remember { mutableStateOf<String?>(null) }
    var fuValue by remember { mutableStateOf<Int?>(null) }
    var after by remember { mutableStateOf<Workout?>(if (savedFb != null) vm.engine.workout else null) }

    if (r == null) { Muted("Sign in and finish the rider setup to get a recommendation.", 12); PrimaryButton("DONE", Modifier.fillMaxWidth().padding(top = 8.dp).testTag("post_home"), onClick = onDone); return }
    if (savedFb == null && r.completed) {
        D7Card {
            CardTitle("TWO QUICK QUESTIONS")
            FieldLabel("HOW HARD DID THAT FEEL, 1 (EASY) TO 10 (MAXIMAL)?")
            SliderRow(rpe, 1, 10, 1, "/ 10") { rpe = it }
            FieldLabel("WHAT LIMITED YOU?")
            Chips(listOf("legs" to "Legs", "breathing" to "Breathing", "tired" to "Tiredness", "none" to "Nothing"), setOfNotNull(limiter), small = true) { limiter = it }
            FieldLabel("RECOVERED ENOUGH TO RIDE AGAIN TOMORROW?")
            Chips(listOf("yes" to "Yes", "no" to "No", "unsure" to "Not sure"), setOfNotNull(recovered), small = true) { recovered = it }
            if (fu != null) {
                FieldLabel("ONE MORE, BECAUSE IT WOULD IMPROVE YOUR PLAN")
                Text(fu.question, fontSize = 13.sp, color = D7.Fg, fontWeight = FontWeight.Bold); fu.why?.let { Muted(it, 11) }
                Spacer(Modifier.height(4.dp))
                if (fu.kind == "metric") NumberField(fuValue, fu.unit, fu.min, fu.max, Modifier.width(120.dp)) { fuValue = it } else Chips(fu.options, setOfNotNull(fuChoice), small = true) { fuChoice = it }
            }
            Spacer(Modifier.height(10.dp))
            fun finish(withAnswers: Boolean) {
                val fb = RideFeedback(rideId, a.inBandPct ?: 0, a.driftPct ?: 0, a.avgHr ?: 0, a.durationSec, if (withAnswers) rpe else null, if (withAnswers) limiter else null, if (withAnswers) recovered else null)
                val fuVal = if (!withAnswers || fu == null) null else if (fu.kind == "metric") fuValue?.toString() else fuChoice
                vm.engine.recordFeedback(fb, if (withAnswers) fu?.key else null, fuVal)
                after = vm.engine.workout; onSaved()
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                SecondaryButton("SKIP", Modifier.weight(1f)) { finish(false) }
                PrimaryButton("SAVE", Modifier.weight(1.4f).testTag("save_post"), onClick = { finish(true) })
            }
        }
    } else {
        val n = after ?: vm.engine.workout
        if (n != null) {
            val changed = before == null || before.name != n.name || before.minutes != n.minutes
            if (fresh) Headline(if (changed) "The recommendation changed" else "The recommendation stands", 17)
            if (fresh && before != null) D7Card(Modifier.padding(top = 6.dp)) { CardTitle("BEFORE THIS RIDE"); Text("${before.name} · ${before.minutes} min", fontSize = 13.sp, color = D7.Fg) }
            D7Card(Modifier.padding(top = 6.dp), accent = D7.Green) {
                CardTitle(if (fresh) "AFTER THIS RIDE" else "CURRENT RECOMMENDATION")
                Text("${n.name} · ${n.minutes} min", fontSize = 15.sp, fontWeight = FontWeight.Bold, color = D7.Fg)
                Text("${n.hrLo}–${n.hrHi} bpm${if (n.pwLo != null) " · ${n.pwLo}–${n.pwHi} W" else ""}", fontFamily = PlexMono, fontSize = 12.sp, color = D7.Cyan, modifier = Modifier.padding(vertical = 3.dp))
                n.why.firstOrNull()?.let { Text(it, fontSize = 13.sp, lineHeight = 18.sp, color = D7.Fg) }
                if (n.why.size > 1 || savedFb != null) Expander("Why this workout?") {
                    Bullets(n.why.drop(1))
                    savedFb?.let { fb -> Muted("Used: ${if (fb.rpe != null) "effort ${fb.rpe}/10, limiter ${fb.limiter ?: "—"}, recovered ${fb.recovered ?: "—"}, " else ""}time in band ${fb.inZonePct}%, drift ${fb.driftPct}%. Rides on record: ${r.feedback.size}.", 11) }
                }
            }
        } else Muted("Finish the rider setup (ME tab) to get a personal recommendation.", 12)
        if (fresh) PrimaryButton("HOME", Modifier.fillMaxWidth().padding(top = 10.dp).testTag("post_home"), onClick = onDone)
    }
}
