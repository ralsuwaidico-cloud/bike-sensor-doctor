package com.rashed.bikesensordoctor.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
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
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rashed.bikesensordoctor.core.GraphBands
import com.rashed.bikesensordoctor.core.GraphBreaches
import com.rashed.bikesensordoctor.core.GraphDecimate
import com.rashed.bikesensordoctor.core.GraphScale
import com.rashed.bikesensordoctor.core.GraphStatus
import com.rashed.bikesensordoctor.core.LiveBuffer
import com.rashed.bikesensordoctor.core.Phase
import com.rashed.bikesensordoctor.ride.RideEngine

/*
 * v0.10 live dashboard pieces: metric cards with a target bar, the combined normalised graph, the compact coach line,
 * and the Details graphs. Colours are fixed per signal everywhere: power CYAN, heart rate GREEN, cadence VIOLET.
 * Status is never colour-only: every state carries a glyph (▲ ● ▼ ○ —) and a word.
 */
object GraphColors { val Power = D7.Cyan; val Hr = D7.Green; val Cad = D7.Violet }

/** Glyph + word for a target status (never colour alone). */
fun statusLabel(s: GraphStatus, kind: String): Pair<String, Color> = when (s) {
    GraphStatus.BELOW -> "▼ BELOW" to D7.Cyan
    GraphStatus.ON -> "● ON TARGET" to D7.Green
    GraphStatus.ABOVE -> "▲ ABOVE" to D7.Amber
    GraphStatus.ZERO -> (if (kind == "pw") "○ COASTING" else "○ STOPPED") to D7.Faint
    GraphStatus.NONE -> (if (kind == "hr") "— NO STRAP" else "— NO DATA") to D7.Faint
}

/**
 * Section B card: label, big value, unit, a small horizontal target bar (band segment + marker, same mapping as the graph)
 * and the status word. [statusOverride] replaces the word when there is a better one (e.g. "UNVERIFIED").
 */
@Composable
fun MetricCard(modifier: Modifier, label: String, value: Int?, unit: String, lo: Int?, hi: Int?, color: Color, kind: String, tag: String = "",
               statusOverride: String? = null, compact: Boolean = false, testTag: String) {
    val status = GraphScale.status(value, lo, hi)
    val (word, wc) = statusLabel(status, kind)
    val n = GraphScale.norm(value, lo, hi)
    val desc = "$label ${value?.toString() ?: "no data"} $unit, ${statusOverride ?: word}"
    Column(modifier.background(D7.Panel2, RoundedCornerShape(10.dp)).border(1.dp, D7.Line, RoundedCornerShape(10.dp)).padding(start = 8.dp, end = 6.dp, top = 4.dp, bottom = 4.dp).testTag(testTag).semantics { contentDescription = desc }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(width = 3.dp, height = 10.dp).background(color, RoundedCornerShape(1.dp))); Spacer(Modifier.width(4.dp))
            Text(label, fontFamily = PlexMono, fontWeight = FontWeight.Bold, fontSize = 8.sp, color = color, letterSpacing = 1.sp, maxLines = 1, softWrap = false, modifier = Modifier.weight(1f))
            if (tag.isNotEmpty()) Text(tag, fontFamily = PlexMono, fontSize = 7.sp, color = D7.Faint, maxLines = 1)
        }
        Row(verticalAlignment = Alignment.Bottom) {
            Text(value?.toString() ?: "—", fontFamily = Rajdhani, fontWeight = FontWeight.SemiBold, fontSize = if (compact) 24.sp else 28.sp, lineHeight = if (compact) 24.sp else 28.sp,
                color = if (value == null) D7.Faint else D7.Fg, maxLines = 1, softWrap = false, modifier = Modifier.weight(1f))
            Text(unit, fontFamily = PlexMono, fontSize = 8.sp, color = D7.Mut, maxLines = 1, modifier = Modifier.padding(bottom = 4.dp))
        }
        // target bar: the band segment is lit; the marker sits where the value falls on the same (compressed) scale as the graph
        Canvas(Modifier.fillMaxWidth().height(10.dp).padding(vertical = 3.dp)) {
            val w = size.width; val h = size.height
            drawRoundRect(D7.Track, Offset(0f, 0f), Size(w, h), androidx.compose.ui.geometry.CornerRadius(h / 2))
            if (lo != null && hi != null && hi > lo) {
                val x0 = w * (1f - GraphScale.BAND_BOT); val x1 = w * (1f - GraphScale.BAND_TOP)
                drawRoundRect(color.copy(alpha = 0.55f), Offset(x0, 0f), Size(x1 - x0, h), androidx.compose.ui.geometry.CornerRadius(h / 2))
            }
            if (n != null) { val x = w * (1f - GraphScale.yFrac(n)); drawRoundRect(D7.Fg, Offset(x - 1.5f * density, -2f * density), Size(3f * density, h + 4f * density), androidx.compose.ui.geometry.CornerRadius(1f * density)) }
        }
        Text(statusOverride ?: word, fontFamily = PlexMono, fontWeight = FontWeight.Bold, fontSize = 7.5.sp, color = if (statusOverride != null) D7.Faint else wc, maxLines = 1, overflow = TextOverflow.Ellipsis)
    }
}

/** Legend row above the graph: swatch, name, the band each line is scaled against (or "no signal"). */
@Composable
fun GraphLegend(bands: GraphBands?, havePw: Boolean, haveHr: Boolean, haveCad: Boolean, modifier: Modifier = Modifier) {
    @Composable fun item(color: Color, name: String, band: String, have: Boolean, m: Modifier) {
        Row(m, verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(width = 9.dp, height = 2.5.dp).background(if (have) color else color.copy(alpha = 0.4f)))
            Spacer(Modifier.width(3.dp))
            Text(buildString { append(name); append(' '); append(if (have) band else "no signal") }, fontFamily = PlexMono, fontSize = 7.5.sp, lineHeight = 9.sp, color = if (have) D7.Mut else D7.Faint, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
    Row(modifier.fillMaxWidth()) {
        item(GraphColors.Power, "PWR 3s", if (bands?.pwLo != null) (if (bands.pwReference) "ref " else "") + "${bands.pwLo}–${bands.pwHi} W" else "no target", havePw, Modifier.weight(1.1f))
        item(GraphColors.Hr, "HR", if (bands != null) "${bands.hrLo}–${bands.hrHi} bpm" else "", haveHr, Modifier.weight(1f))
        item(GraphColors.Cad, "CAD", if (bands != null) "${bands.cadLo}–${bands.cadHi} rpm" else "", haveCad, Modifier.weight(0.95f))
    }
}

private fun DrawScope.tracePath(path: Path, buf: LiveBuffer, signal: LiveBuffer.Signal, from: Int, to: Int, cols: Int, xOf: (Int) -> Float, top: Float, h: Float) {
    path.reset()
    val pts = GraphDecimate.minMax(from, to, cols) { buf.norm(signal, it) }
    var pen = false
    var k = 0
    while (k + 1 < pts.size) {
        val i = pts[k].toInt(); val v = pts[k + 1]
        if (v.isNaN()) pen = false else { val x = xOf(i); val y = top + h * GraphScale.yFrac(v); if (pen) path.lineTo(x, y) else path.moveTo(x, y); pen = true }
        k += 2
    }
}

/**
 * Section C: the combined graph. Draws straight from the engine's ring buffer (no copies, no per-frame allocation
 * beyond the reused Paths), once per new sample ([version]). Power is the 3-s mean, HR and cadence 1 Hz.
 * Gaps are never bridged; ≥ 20 s outside the band is shaded for HR and power; phase changes are dashed verticals.
 */
@Composable
fun CombinedGraph(buf: LiveBuffer, version: Long, windowSec: Int, modifier: Modifier, testTag: String = "live_graph") {
    val pPw = remember { Path() }; val pHr = remember { Path() }; val pCad = remember { Path() }; val pFill = remember { Path() }
    val ld = LocalDensity.current
    val labelPx = with(ld) { 8.sp.toPx() }
    val paint = remember { android.graphics.Paint().apply { isAntiAlias = true; textSize = labelPx; typeface = android.graphics.Typeface.MONOSPACE } }
    Canvas(modifier.background(D7.Panel, RoundedCornerShape(6.dp)).border(1.dp, D7.Line, RoundedCornerShape(6.dp)).testTag(testTag)) {
        @Suppress("UNUSED_VARIABLE") val v = version   // read so the Canvas redraws on every new sample
        val padL = 4f * density; val padR = 4f * density; val padT = 10f * density; val padB = 12f * density
        val w = size.width - padL - padR; val h = size.height - padT - padB; val top = padT
        val n = buf.size; val from = buf.windowStart(windowSec); val cnt = n - from
        val xOf: (Int) -> Float = { i -> padL + w * ((windowSec - cnt + (i - from)).toFloat() / (windowSec - 1).coerceAtLeast(1)) }
        // target band + edges
        val bt = top + h * GraphScale.BAND_TOP; val bb = top + h * GraphScale.BAND_BOT
        drawRect(D7.Fg.copy(alpha = 0.07f), Offset(padL, bt), Size(w, bb - bt))
        val dash = PathEffect.dashPathEffect(floatArrayOf(4f * density, 5f * density))
        drawLine(D7.Fg.copy(alpha = 0.35f), Offset(padL, bt), Offset(padL + w, bt), 1f * density, pathEffect = dash)
        drawLine(D7.Fg.copy(alpha = 0.35f), Offset(padL, bb), Offset(padL + w, bb), 1f * density, pathEffect = dash)
        // breaches (HR + power), ≥ 20 s outside the band
        if (cnt > 1) for ((sig, col) in listOf(LiveBuffer.Signal.HR to GraphColors.Hr, LiveBuffer.Signal.POWER to GraphColors.Power)) {
            for (b in GraphBreaches.find(from, n, 20) { buf.norm(sig, it) }) {
                val edge = if (b.side > 0) bt else bb
                pFill.reset(); pFill.moveTo(xOf(b.from), edge)
                for (i in b.from until b.to) { val nv = buf.norm(sig, i); if (!nv.isNaN()) pFill.lineTo(xOf(i), top + h * GraphScale.yFrac(nv)) }
                pFill.lineTo(xOf(b.to - 1), edge); pFill.close()
                drawPath(pFill, col.copy(alpha = 0.18f))
            }
        }
        // phase changes
        if (cnt > 1) for (i in from + 1 until n) if (buf.phaseAt(i) != buf.phaseAt(i - 1)) {
            val x = xOf(i)
            drawLine(D7.Fg.copy(alpha = 0.3f), Offset(x, top), Offset(x, top + h), 1f * density, pathEffect = dash)
            val lab = when (buf.phaseAt(i)) { Phase.WARMUP -> "WARM"; Phase.MAIN -> "MAIN"; Phase.COOLDOWN -> "COOL"; Phase.RECOVERY -> "REST" }
            paint.color = D7.Mut.toArgb(); paint.textAlign = android.graphics.Paint.Align.CENTER
            drawContext.canvas.nativeCanvas.drawText(lab, x, top + labelPx, paint)
        }
        // traces
        if (cnt > 1) {
            val cols = (w / (1.2f * density)).toInt().coerceAtLeast(40)
            val stroke = Stroke(width = 2.2f * density, cap = StrokeCap.Round, join = StrokeJoin.Round)
            tracePath(pPw, buf, LiveBuffer.Signal.POWER, from, n, cols, xOf, top, h); drawPath(pPw, GraphColors.Power, style = stroke)
            tracePath(pHr, buf, LiveBuffer.Signal.HR, from, n, cols, xOf, top, h); drawPath(pHr, GraphColors.Hr, style = stroke)
            tracePath(pCad, buf, LiveBuffer.Signal.CADENCE, from, n, cols, xOf, top, h); drawPath(pCad, GraphColors.Cad, style = Stroke(width = 1.8f * density, cap = StrokeCap.Round, join = StrokeJoin.Round))
            // newest point: a dot on each live trace; a hollow dashed ring at band height when the signal is missing
            for ((sig, col) in listOf(LiveBuffer.Signal.POWER to GraphColors.Power, LiveBuffer.Signal.HR to GraphColors.Hr, LiveBuffer.Signal.CADENCE to GraphColors.Cad)) {
                val nv = buf.norm(sig, n - 1); val x = xOf(n - 1)
                if (!nv.isNaN()) { drawCircle(D7.Bg, 3.6f * density, Offset(x, top + h * GraphScale.yFrac(nv))); drawCircle(col, 2.6f * density, Offset(x, top + h * GraphScale.yFrac(nv))) }
                else drawCircle(col, 2.6f * density, Offset(x, top + h * 0.5f), style = Stroke(1f * density, pathEffect = PathEffect.dashPathEffect(floatArrayOf(2f, 2f))))
            }
        }
        // axis labels: right-hand ABOVE / TARGET / BELOW, bottom minutes
        paint.textAlign = android.graphics.Paint.Align.LEFT   // left edge: the newest points live at the right edge
        paint.color = D7.Mut.toArgb(); drawContext.canvas.nativeCanvas.drawText("▲ ABOVE", padL + 3f * density, bt - 3f * density, paint)
        paint.color = D7.Fg.copy(alpha = 0.7f).toArgb(); drawContext.canvas.nativeCanvas.drawText("TARGET", padL + 3f * density, top + h * 0.5f + labelPx / 2.6f, paint)
        paint.color = D7.Mut.toArgb(); drawContext.canvas.nativeCanvas.drawText("▼ BELOW", padL + 3f * density, bb + labelPx, paint)
        val mins = windowSec / 60
        paint.color = D7.Faint.toArgb()
        for (m in 0..mins) {
            val i = (n - 1) - (mins - m) * 60
            val x = padL + w * ((windowSec - cnt + (i - from)).toFloat() / (windowSec - 1).coerceAtLeast(1))
            if (x < padL - 1f) continue
            drawLine(D7.Faint, Offset(x, top + h), Offset(x, top + h + 3f * density), 1f * density)
            paint.textAlign = if (m == mins) android.graphics.Paint.Align.RIGHT else android.graphics.Paint.Align.CENTER
            drawContext.canvas.nativeCanvas.drawText(if (m == mins) "now" else "-${mins - m}m", x, size.height - 2f * density, paint)
        }
    }
}

/**
 * Section D: the compact coach line — action icon, one short instruction, one short reason, and the analysis indicator.
 * Fixed, small height; the headline steps down in size for long text and may wrap to two lines, never clips.
 */
@Composable
fun CompactCoach(modifier: Modifier, short: String, why: String, color: Color, active: Boolean, icon: String, direction: Int?,
                 analysisAgeSec: Int, analysisText: String, sources: String, onClick: () -> Unit) {
    val bg = if (active) color else D7.Panel2
    val ink = if (active) D7.Ink else D7.Fg
    val sub = if (active) D7.Ink.copy(alpha = 0.85f) else D7.Mut
    val bigFont = LocalDensity.current.fontScale > 1.15f
    val size = (when { short.length >= 30 -> 15; short.length >= 24 -> 16; else -> 18 } - (if (bigFont) 2 else 0)).sp
    Row(modifier.background(bg, RoundedCornerShape(12.dp)).then(if (active) Modifier else Modifier.border(1.dp, D7.Line, RoundedCornerShape(12.dp)))
        .clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 6.dp).testTag("coach_box"), verticalAlignment = Alignment.CenterVertically) {
        // icon: shape (▲ ✓ ▼ ○) in a dark disc with the action glyph underneath
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(28.dp).background(D7.Ink, CircleShape), contentAlignment = Alignment.Center) {
                Text(when (direction) { 1 -> "▲"; -1 -> "▼"; 0 -> "✓"; else -> "○" }, color = if (active) color else D7.Faint, fontSize = 14.sp, fontWeight = FontWeight.Bold)
            }
            if (icon.isNotEmpty()) Text(icon, fontFamily = PlexMono, fontWeight = FontWeight.Bold, fontSize = 9.sp, color = ink, maxLines = 1, modifier = Modifier.testTag("coach_icon"))
        }
        Spacer(Modifier.width(8.dp))
        Column(Modifier.weight(1f)) {
            Text(short, fontFamily = Archivo, fontWeight = FontWeight.ExtraBold, fontSize = size, lineHeight = (size.value + 1).sp, color = ink, maxLines = 2, overflow = TextOverflow.Ellipsis, modifier = Modifier.testTag("coach_headline"))
            if (why.isNotEmpty()) Text(why, fontSize = if (bigFont) 10.sp else 11.sp, lineHeight = 12.sp, color = sub, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 1.dp))
            Row(Modifier.padding(top = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(5.dp).background(if (analysisAgeSec in 0..65) (if (active) ink else D7.Green) else (if (active) ink.copy(alpha = 0.4f) else D7.Faint), CircleShape))
                Spacer(Modifier.width(4.dp))
                Text(buildString { append(if (analysisAgeSec >= 0) "${analysisAgeSec}s ago" else "first analysis after 1 min"); if (analysisText.isNotEmpty()) append(" · ").append(analysisText); if (sources.isNotEmpty()) append(" · ").append(sources) },
                    fontFamily = PlexMono, fontSize = 8.sp, color = sub, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.testTag("coach_assessment"))
            }
        }
    }
}

/**
 * Details: three separate traces in their own units with the band as it was at each second, 1 / 5 / 10-minute windows,
 * and tap-or-drag for the exact readings at that second.
 */
@Composable
fun DetailGraphs(buf: LiveBuffer, version: Long, windowAverages: ((Int) -> com.rashed.bikesensordoctor.core.WindowAverages)? = null, rideAverages: (() -> com.rashed.bikesensordoctor.core.WindowAverages)? = null) {
    var win by remember { mutableIntStateOf(300) }
    var sel by remember { mutableStateOf<Int?>(null) }
    var wholeRide by remember { mutableStateOf(false) }
    val ld = LocalDensity.current
    Column(Modifier.fillMaxWidth().testTag("detail_graphs")) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("SENSOR HISTORY", fontFamily = PlexMono, fontSize = 10.sp, color = D7.Mut, letterSpacing = 1.sp, modifier = Modifier.weight(1f))
            for (s in listOf(60, 300, 600)) {
                val on = win == s
                Text("${s / 60}m", fontFamily = PlexMono, fontWeight = FontWeight.Bold, fontSize = 10.sp, color = if (on) D7.Ink else D7.Mut,
                    modifier = Modifier.padding(start = 4.dp).background(if (on) D7.Cyan else D7.Panel2, RoundedCornerShape(6.dp)).border(1.dp, if (on) D7.Cyan else D7.Line, RoundedCornerShape(6.dp))
                        .clickable { win = s; sel = null }.padding(horizontal = 8.dp, vertical = 3.dp).testTag("detail_win_$s"))
            }
        }
        // v0.11 averages: last 5 minutes or the whole ride (time-weighted; valid 0 W counted, missing excluded; cadence elapsed vs pedalling)
        if (windowAverages != null && rideAverages != null) Row(Modifier.fillMaxWidth().padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            val a = remember(version, wholeRide, win) { if (wholeRide) rideAverages() else windowAverages(win) }
            AveragesRow(a, if (wholeRide) "AVG RIDE" else "AVG ${win / 60} MIN", Modifier.weight(1f))
            Text(if (wholeRide) "ride" else "window", fontFamily = PlexMono, fontWeight = FontWeight.Bold, fontSize = 9.sp, color = D7.Ink,
                modifier = Modifier.padding(start = 6.dp).background(D7.Cyan, RoundedCornerShape(6.dp)).clickable { wholeRide = !wholeRide }.padding(horizontal = 6.dp, vertical = 2.dp).testTag("detail_avg_toggle"))
        }
        Spacer(Modifier.height(6.dp))
        val n = buf.size; val from = buf.windowStart(win); val cnt = n - from
        val labelPx = with(ld) { 8.sp.toPx() }
        val paint = remember { android.graphics.Paint().apply { isAntiAlias = true; typeface = android.graphics.Typeface.MONOSPACE } }
        paint.textSize = labelPx
        val panels = listOf(
            Triple("POWER", GraphColors.Power, "W") to { i: Int -> buf.powerAt(i) },
            Triple("HEART RATE", GraphColors.Hr, "bpm") to { i: Int -> buf.hrAt(i) },
            Triple("CADENCE", GraphColors.Cad, "rpm") to { i: Int -> buf.cadAt(i) },
        )
        val path = remember { Path() }; val band = remember { Path() }
        for ((meta, valueAt) in panels) {
            val (name, col, unit) = meta
            Canvas(Modifier.fillMaxWidth().height(118.dp).padding(bottom = 6.dp).background(D7.Panel, RoundedCornerShape(6.dp)).border(1.dp, D7.Line, RoundedCornerShape(6.dp))
                .pointerInput(win) {
                    detectTapGestures { p -> sel = (from + ((p.x - 6f * density) / (size.width - 12f * density) * (win - 1) - (win - cnt))).toInt().coerceIn(from, (n - 1).coerceAtLeast(from)) }
                }.pointerInput(win) {
                    detectHorizontalDragGestures { change, _ -> sel = (from + ((change.position.x - 6f * density) / (size.width - 12f * density) * (win - 1) - (win - cnt))).toInt().coerceIn(from, (n - 1).coerceAtLeast(from)) }
                }) {
                @Suppress("UNUSED_VARIABLE") val v = version
                val padL = 6f * density; val padR = 6f * density; val padT = 14f * density; val padB = 6f * density
                val w = size.width - padL - padR; val h = size.height - padT - padB
                paint.textAlign = android.graphics.Paint.Align.LEFT; paint.color = col.toArgb()
                drawContext.canvas.nativeCanvas.drawText(name, padL, labelPx + 2f * density, paint)
                if (cnt < 2) return@Canvas
                // scale: data + band, in real units; power and cadence never below 0
                var mn = Float.MAX_VALUE; var mx = -Float.MAX_VALUE
                for (i in from until n) {
                    valueAt(i)?.let { mn = minOf(mn, it.toFloat()); mx = maxOf(mx, it.toFloat()) }
                    val b = buf.bandsAt(i)
                    val (lo, hi) = when (name) { "POWER" -> b.pwLo to b.pwHi; "HEART RATE" -> b.hrLo to b.hrHi; else -> b.cadLo to b.cadHi }
                    if (lo != null && hi != null) { mn = minOf(mn, lo.toFloat()); mx = maxOf(mx, hi.toFloat()) }
                }
                if (mn == Float.MAX_VALUE) { mn = 0f; mx = 10f }
                if (mx - mn < 10f) mx = mn + 10f
                val pad = (mx - mn) * 0.08f; mn -= pad; mx += pad; if (name != "HEART RATE") mn = maxOf(0f, mn)
                val xOf: (Int) -> Float = { i -> padL + w * ((win - cnt + (i - from)).toFloat() / (win - 1).coerceAtLeast(1)) }
                val yOf: (Float) -> Float = { value -> padT + h * (1f - (value - mn) / (mx - mn)) }
                // band as it was at each second (a ramp shows as a sloping band)
                band.reset(); var started = false
                for (i in from until n) { val b = buf.bandsAt(i); val hi = when (name) { "POWER" -> b.pwHi; "HEART RATE" -> b.hrHi; else -> b.cadHi } ?: continue; if (!started) { band.moveTo(xOf(i), yOf(hi.toFloat())); started = true } else band.lineTo(xOf(i), yOf(hi.toFloat())) }
                if (started) { for (i in n - 1 downTo from) { val b = buf.bandsAt(i); val lo = when (name) { "POWER" -> b.pwLo; "HEART RATE" -> b.hrLo; else -> b.cadLo } ?: continue; band.lineTo(xOf(i), yOf(lo.toFloat())) }; band.close(); drawPath(band, D7.Fg.copy(alpha = 0.10f)) }
                // phase changes
                val dash = PathEffect.dashPathEffect(floatArrayOf(4f * density, 5f * density))
                for (i in from + 1 until n) if (buf.phaseAt(i) != buf.phaseAt(i - 1)) drawLine(D7.Fg.copy(alpha = 0.3f), Offset(xOf(i), padT), Offset(xOf(i), padT + h), 1f * density, pathEffect = dash)
                // gaps: a faint strip + label
                var gs = -1
                for (i in from..n) { val miss = i < n && valueAt(i) == null; if (miss && gs < 0) gs = i; if (!miss && gs >= 0) { drawRect(col.copy(alpha = 0.08f), Offset(xOf(gs), padT), Size(maxOf(1f, xOf(i - 1) - xOf(gs)), h)); if (i - gs >= 8) { paint.textAlign = android.graphics.Paint.Align.CENTER; paint.color = col.copy(alpha = 0.8f).toArgb(); drawContext.canvas.nativeCanvas.drawText(if (name == "HEART RATE") "no strap" else "no signal", (xOf(gs) + xOf(i - 1)) / 2, padT + h / 2, paint) }; gs = -1 } }
                // trace (raw 1 Hz, min/max decimated to the pixel columns)
                path.reset(); var pen = false
                val pts = GraphDecimate.minMax(from, n, (w / (1f * density)).toInt().coerceAtLeast(40)) { i -> valueAt(i)?.toFloat() ?: Float.NaN }
                var k = 0
                while (k + 1 < pts.size) { val i = pts[k].toInt(); val value = pts[k + 1]; if (value.isNaN()) pen = false else { if (pen) path.lineTo(xOf(i), yOf(value)) else path.moveTo(xOf(i), yOf(value)); pen = true }; k += 2 }
                drawPath(path, col, style = Stroke(1.8f * density, cap = StrokeCap.Round, join = StrokeJoin.Round))
                // axis extremes
                paint.textAlign = android.graphics.Paint.Align.RIGHT; paint.color = D7.Faint.toArgb()
                drawContext.canvas.nativeCanvas.drawText("${(mx - pad).toInt()} $unit", padL + w, labelPx + 2f * density, paint)
                drawContext.canvas.nativeCanvas.drawText("${(mn + (if (name != "HEART RATE" && mn == 0f) 0f else pad)).toInt()} $unit", padL + w, size.height - 3f * density, paint)
                sel?.let { s -> if (s in from until n) drawLine(D7.Fg.copy(alpha = 0.7f), Offset(xOf(s), padT), Offset(xOf(s), padT + h), 1f * density) }
            }
        }
        // readout
        val s = sel?.takeIf { it in from until n }
        Column(Modifier.fillMaxWidth().background(D7.Panel2, RoundedCornerShape(10.dp)).border(1.dp, D7.Line, RoundedCornerShape(10.dp)).padding(10.dp).testTag("detail_readout")) {
            if (s == null) {
                Text("Tap or drag on a graph for the exact readings at that second.", fontFamily = PlexMono, fontSize = 10.sp, color = D7.Mut)
                Text("Showing the last ${win / 60} min of the ${buf.size} s kept in memory (10-minute ring buffer). Missing values are gaps, never filled; 0 W while coasting is a real zero.", fontSize = 10.sp, color = D7.Faint, modifier = Modifier.padding(top = 4.dp))
            } else {
                val p = buf[s]
                Text("at ${RideEngine.fmtDuration(p.sec * 1000L)} · ${p.phase.name.replace("WARMUP", "WARM-UP").replace("COOLDOWN", "COOL-DOWN")}", fontFamily = PlexMono, fontWeight = FontWeight.Bold, fontSize = 11.sp, color = D7.Fg)
                @Composable fun line(col: Color, lab: String, v: String, band: String) { Row(Modifier.padding(top = 3.dp)) { Text("$lab $v", fontFamily = PlexMono, fontSize = 11.sp, color = col, modifier = Modifier.width(120.dp)); Text(band, fontFamily = PlexMono, fontSize = 10.sp, color = D7.Mut) } }
                line(GraphColors.Power, "PWR", p.powerW?.let { "$it W" } ?: "—", if (p.bands.pwLo != null) "target ${p.bands.pwLo}–${p.bands.pwHi} W" else "no power target")
                line(GraphColors.Hr, "HR", p.hr?.let { "$it bpm" } ?: "—", "target ${p.bands.hrLo}–${p.bands.hrHi} bpm")
                line(GraphColors.Cad, "CAD", p.cadRpm?.let { "$it rpm" } ?: "—", "range ${p.bands.cadLo}–${p.bands.cadHi} rpm")
            }
        }
    }
}

/**
 * v0.10 hybrid: a compact Design-7 circular gauge for Section B. The LIVE dot (end of the progress arc) and the TARGET band
 * (thin arc just outside the ring) share ONE scale — 0..[max] over the 270° dial — so their positions genuinely represent the
 * reading and the range. Status is a word with a glyph under the ring; the value sits in the centre. A reference band
 * (unverified meter) is drawn dashed and dim. Nothing animates (no per-frame cost on the Nokia).
 */
@Composable
fun CompactGauge(modifier: Modifier, label: String, value: Int?, unit: String, max: Int, lo: Int?, hi: Int?, color: Color, kind: String,
                 tag: String = "", reference: Boolean = false, statusOverride: String? = null, compact: Boolean = false, testTag: String, ring: Dp = 84.dp) {
    val status = GraphScale.status(value, lo, hi)
    val (word, wc) = statusLabel(status, kind)
    val statusWord = statusOverride ?: word
    val statusColor = if (statusOverride != null) D7.Faint else wc
    // v0.11.1: the ring diameter is given by the screen (LiveScreen computes the largest three-across size); the value scales with the ring
    // so it stays readable outdoors and never spills out of the dial, whatever the system font size
    val ld = LocalDensity.current
    val valuePx = with(ld) { (ring * 0.37f).toPx() }
    val unitPx = with(ld) { 8.sp.toPx() }
    val paint = remember { android.graphics.Paint().apply { isAntiAlias = true; textAlign = android.graphics.Paint.Align.CENTER } }
    // the value is drawn, not a Text node: expose it to accessibility (and the UI tests) as a description
    val desc = "$label ${value?.toString() ?: "no data"} $unit, $statusWord"
    Column(modifier.testTag(testTag).semantics { contentDescription = desc }, horizontalAlignment = Alignment.CenterHorizontally) {
        Text(label, fontFamily = PlexMono, fontWeight = FontWeight.Bold, fontSize = 9.sp, color = color, letterSpacing = 1.sp, maxLines = 1, softWrap = false)
        Canvas(Modifier.padding(top = 1.dp).size(ring)) {
            val sw = (ring.toPx() / 9.5f).coerceAtLeast(8f * density)
            val over = sw / 2 + 1f * density
            val r = size.minDimension / 2 - over
            val c = Offset(size.width / 2, size.height / 2)
            val tl = Offset(c.x - r, c.y - r); val sz = Size(2 * r, 2 * r)
            val start = 135f; val sweep = 270f
            drawArc(D7.Track, start, sweep, false, tl, sz, style = Stroke(sw))
            val frac = if (value == null || max <= 0) null else (value.toFloat() / max).coerceIn(0f, 1f)
            if (frac != null && frac > 0f) drawArc(color.copy(alpha = 0.55f), start, sweep * frac, false, tl, sz, style = Stroke(sw, cap = StrokeCap.Round))
            // TARGET band on the same scale, just outside the ring, with end ticks
            if (lo != null && hi != null && hi > lo) {
                val rb = r - sw / 2 - 4f * density   // TARGET band just INSIDE the ring (same scale as the LIVE dot) so neighbouring gauges never touch
                val a0 = start + sweep * (lo.toFloat() / max).coerceIn(0f, 1f); val a1 = start + sweep * (hi.toFloat() / max).coerceIn(0f, 1f)
                val bc = if (reference) D7.Faint else D7.Fg
                drawArc(bc, a0, (a1 - a0).coerceAtLeast(1f), false, Offset(c.x - rb, c.y - rb), Size(2 * rb, 2 * rb),
                    style = Stroke(3f * density, pathEffect = if (reference) PathEffect.dashPathEffect(floatArrayOf(3f * density, 3f * density)) else null))
                for (a in listOf(a0, a1)) { val rad = Math.toRadians((a - 90).toDouble()); val cs = Math.cos(rad).toFloat(); val sn = Math.sin(rad).toFloat()
                    drawLine(bc, Offset(c.x + (rb - 3f * density) * cs, c.y + (rb - 3f * density) * sn), Offset(c.x + (rb + 3f * density) * cs, c.y + (rb + 3f * density) * sn), 1.5f * density) }
            }
            // LIVE dot at the reading
            if (frac != null) { val a = Math.toRadians((start + sweep * frac - 90).toDouble()); val p = Offset(c.x + r * Math.cos(a).toFloat(), c.y + r * Math.sin(a).toFloat())
                drawCircle(D7.Bg, 6.5f * density, p); drawCircle(color, 5f * density, p); drawCircle(D7.Fg, 2f * density, p) }
            // centre: value + unit (+ tag)
            paint.typeface = android.graphics.Typeface.create(android.graphics.Typeface.DEFAULT, android.graphics.Typeface.BOLD)
            paint.textSize = valuePx; paint.color = (if (value == null) D7.Faint else D7.Fg).toArgb()
            drawContext.canvas.nativeCanvas.drawText(value?.toString() ?: "—", c.x, c.y + valuePx * 0.28f, paint)
            // the unit sits in the dial's bottom opening (the SIMULATED state is already on the status line, not repeated here)
            paint.typeface = android.graphics.Typeface.MONOSPACE; paint.textSize = unitPx * 0.9f; paint.color = D7.Mut.toArgb()
            drawContext.canvas.nativeCanvas.drawText(unit, c.x, c.y + r + sw / 2 - unitPx * 0.2f, paint)
        }
        Box(Modifier.padding(top = 1.dp).background(statusColor.copy(alpha = 0.16f), RoundedCornerShape(7.dp)).border(1.dp, statusColor, RoundedCornerShape(7.dp)).padding(horizontal = 5.dp, vertical = 1.dp)) {
            Text(statusWord, fontFamily = PlexMono, fontWeight = FontWeight.Bold, fontSize = 8.sp, color = statusColor, maxLines = 1, softWrap = false)
        }
    }
}


/** v0.11: time-weighted averages over the graph window — power incl. valid 0 W (missing excluded), cadence elapsed / pedalling, HR when the strap reported. */
@Composable
fun AveragesRow(a: com.rashed.bikesensordoctor.core.WindowAverages, label: String, modifier: Modifier = Modifier) {
    @Composable fun cell(col: Color, name: String, v: Int?, unit: String, sub: String, m: Modifier) {
        Row(m, verticalAlignment = Alignment.Bottom) {
            Text(name, fontFamily = PlexMono, fontWeight = FontWeight.Bold, fontSize = 8.sp, lineHeight = 10.sp, color = col); Spacer(Modifier.width(3.dp))
            Text(v?.toString() ?: "—", fontFamily = Rajdhani, fontWeight = FontWeight.SemiBold, fontSize = 13.sp, lineHeight = 13.sp, color = if (v == null) D7.Faint else D7.Fg); Spacer(Modifier.width(2.dp))
            Text(if (sub.isEmpty()) unit else "$unit · $sub", fontFamily = PlexMono, fontSize = 7.sp, lineHeight = 9.sp, color = D7.Mut, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
    Row(modifier.fillMaxWidth().testTag("live_averages"), verticalAlignment = Alignment.Bottom) {
        Text(label, fontFamily = PlexMono, fontSize = 7.sp, lineHeight = 9.sp, color = D7.Faint, modifier = Modifier.padding(end = 4.dp))
        cell(GraphColors.Power, "PWR", a.powerW, "W", if (a.powerW != null && a.powerSec < a.windowSec) "gaps" else "", Modifier.weight(1.1f))
        cell(GraphColors.Hr, "HR", a.hrBpm, "bpm", "", Modifier.weight(0.9f))
        cell(GraphColors.Cad, "CAD", a.cadElapsedRpm, "rpm", if (a.cadPedallingRpm != null && a.cadPedallingRpm != a.cadElapsedRpm) "${a.cadPedallingRpm} pedal" else "", Modifier.weight(1.2f))
    }
}
