package com.rashed.bikesensordoctor.ui

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.ExperimentalTextApi
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontLoadingStrategy
import androidx.compose.ui.text.font.FontVariation
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rashed.bikesensordoctor.R
import com.rashed.bikesensordoctor.core.CoachShape
import com.rashed.bikesensordoctor.core.TargetStatus
import java.util.Locale
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/*
 * DESIGN 7 — "AI Scientific Coach". Faithful Compose port of design/bike_designs.html (aiSci()).
 * Pure drawing + layout; every decision (zone, target status, shape, direction) comes from core/Targets.kt.
 * Coaching is triple-coded: colour, shape (▲ ✓ ▼) and a lit EASE · ON TARGET · FASTER scale.
 */

// ---- palette (identical to the design mockup) ----
object D7 {
    val Bg = Color(0xFF060A0D); val Panel = Color(0xFF080E12); val Panel2 = Color(0xFF0A1015)
    val Track = Color(0xFF16242B); val Line = Color(0xFF1D2A33); val Grid = Color(0xFF0E161B)
    val Fg = Color(0xFFEEF4F7); val Mut = Color(0xFF8396A0); val Faint = Color(0xFF5A6B74); val Ink = Color(0xFF05121A)
    val Cyan = Color(0xFF34E7E4); val Green = Color(0xFF56E08C); val Lime = Color(0xFFA6E22E); val Amber = Color(0xFFFFB64D)
    val Orange = Color(0xFFFF8A3D); val Red = Color(0xFFFF5A5A); val Violet = Color(0xFF9B8CFF); val Grey = Color(0xFF7E8C93)
    val powerZoneColors = listOf(Grey, Cyan, Green, Lime, Amber, Orange, Red)
    val hrZoneColors = listOf(Faint, Cyan, Green, Amber, Red)
    fun powerZone(z: Int) = powerZoneColors.getOrNull(z - 1) ?: Grey
    fun hrZone(z: Int) = hrZoneColors.getOrNull(z - 1) ?: Faint
    fun status(s: TargetStatus) = when (s) { TargetStatus.BELOW -> Cyan; TargetStatus.ON -> Green; TargetStatus.ABOVE -> Amber; TargetStatus.UNKNOWN -> Faint }
}

// ---- fonts bundled in res/font (SIL OFL; licences in assets/licenses) ----
// Async loading: if a font file cannot be loaded on a device, Compose falls back to the system font instead of
// throwing during layout (a blocking load failure would crash the dashboard).
val Rajdhani = FontFamily(Font(R.font.rajdhani_medium, FontWeight.Medium, loadingStrategy = FontLoadingStrategy.Async), Font(R.font.rajdhani_semibold, FontWeight.SemiBold, loadingStrategy = FontLoadingStrategy.Async))
val PlexMono = FontFamily(Font(R.font.plexmono_regular, FontWeight.Normal, loadingStrategy = FontLoadingStrategy.Async), Font(R.font.plexmono_bold, FontWeight.Bold, loadingStrategy = FontLoadingStrategy.Async))
@OptIn(ExperimentalTextApi::class)
val Archivo = FontFamily(Font(R.font.archivo_variable, FontWeight.ExtraBold, loadingStrategy = FontLoadingStrategy.Async, variationSettings = FontVariation.Settings(FontVariation.weight(800))))

private const val START = 135f
private const val SWEEP = 270f

private fun DrawScope.polar(c: Offset, r: Float, deg: Float): Offset {
    val a = Math.toRadians((deg - 90).toDouble())
    return Offset(c.x + r * cos(a).toFloat(), c.y + r * sin(a).toFloat())
}

/**
 * Design-4-style circular gauge: track + zone-coloured progress + zone boundary ticks + white target line
 * (+ "TGT" label on the big gauge) + big number + unit + zone sub-label, and a below/on/above pill underneath.
 */
@Composable
fun TargetGauge(
    modifier: Modifier,
    value: Int?, max: Int, color: Color,
    targetFraction: Float?, zoneTicks: FloatArray, rangeArc: Pair<Float, Float>? = null,
    sub: String?, unit: String, big: Boolean,
    status: TargetStatus, statusText: String, showTgtLabel: Boolean,
    /** v0.8: the active TGT band (0..1 of the gauge) drawn just outside the ring; it moves with the workout phase. */
    band: Pair<Float, Float>? = null,
) {
    val frac = if (value == null || max <= 0) 0f else (value.toFloat() / max).coerceIn(0f, 1f)
    val anim by animateFloatAsState(frac, tween(400), label = "g")
    val col by animateColorAsState(color, tween(400), label = "c")
    val measurer = rememberTextMeasurer()
    val tgtStyle = TextStyle(fontFamily = PlexMono, fontSize = 9.sp, color = D7.Mut)
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.fillMaxWidth().aspectRatio(1f), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxSize()) {
                val sw = size.minDimension * (if (big) 0.10f else 0.105f)
                val over = sw / 2 + (if (showTgtLabel) 24.dp.toPx() else 10.dp.toPx())
                val r = size.minDimension / 2 - over
                val c = Offset(size.width / 2, size.height / 2)
                val tl = Offset(c.x - r, c.y - r); val sz = Size(2 * r, 2 * r)
                drawArc(D7.Track, START, SWEEP, false, tl, sz, style = Stroke(sw))
                if (anim > 0f) drawArc(col, START, SWEEP * anim, false, tl, sz, style = Stroke(sw, cap = StrokeCap.Round))
                // cadence target range on the track (green)
                rangeArc?.let { (a, b) -> drawArc(D7.Green, START + SWEEP * a, SWEEP * (b - a), false, tl, sz, style = Stroke(sw * 0.3f)) }
                // zone boundary ticks across the ring
                zoneTicks.forEach { zf ->
                    if (zf <= 0f || zf >= 1f) return@forEach
                    val a = START + SWEEP * zf
                    drawLine(D7.Bg, polar(c, r - sw / 2, a), polar(c, r + sw / 2, a), strokeWidth = 2.dp.toPx())
                }
                // v0.8 TGT band: a thin arc outside the ring with end ticks, coloured by the live status; the LIVE value is the
                // white-rimmed dot at the end of the progress arc, so "where am I vs the band" is visible at a glance.
                band?.let { (a, b) ->
                    val lo = a.coerceIn(0f, 1f); val hi = b.coerceIn(lo, 1f)
                    val rb = r + sw / 2 + 5.dp.toPx(); val bw = 3.dp.toPx()
                    val bc = D7.status(status).let { if (status == TargetStatus.UNKNOWN) D7.Fg.copy(alpha = 0.7f) else it }
                    drawArc(bc, START + SWEEP * lo, SWEEP * (hi - lo), false, Offset(c.x - rb, c.y - rb), Size(2 * rb, 2 * rb), style = Stroke(bw, cap = StrokeCap.Butt))
                    listOf(lo, hi).forEach { f -> val ang = START + SWEEP * f; drawLine(bc, polar(c, rb - 4.dp.toPx(), ang), polar(c, rb + 4.dp.toPx(), ang), strokeWidth = 2.dp.toPx()) }
                    if (showTgtLabel) {
                        val mid = START + SWEEP * (lo + hi) / 2
                        val p = polar(c, rb + 11.dp.toPx(), mid)
                        val m = measurer.measure("TGT", tgtStyle)
                        drawText(m, topLeft = Offset(p.x - m.size.width / 2f, p.y - m.size.height / 2f))
                    }
                }
                if (value != null && anim > 0f) {
                    val p = polar(c, r, START + SWEEP * anim)
                    drawCircle(D7.Fg, sw * 0.42f, p); drawCircle(col, sw * 0.28f, p)
                }
                // white target line (zone-based targets, when no band is active)
                if (band == null) targetFraction?.let { tf ->
                    val a = START + SWEEP * tf
                    drawLine(D7.Fg, polar(c, r - sw / 2 - 4.dp.toPx(), a), polar(c, r + sw / 2 + 4.dp.toPx(), a), strokeWidth = 2.5.dp.toPx())
                    if (showTgtLabel) {
                        val p = polar(c, r + sw / 2 + 13.dp.toPx(), a)
                        val m = measurer.measure("TGT", tgtStyle)
                        drawText(m, topLeft = Offset(p.x - m.size.width / 2f, p.y - m.size.height / 2f))
                    }
                }
            }
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                // small gauges have no room for a long label inside the ring: keep it to 8 characters (the pill below says the rest)
                Text((sub ?: " ").let { if (!big && it.length > 8) " " else it }, fontFamily = PlexMono, fontSize = if (big) 13.sp else 9.sp, color = col, maxLines = 1, softWrap = false)
                Text(value?.toString() ?: "—", fontFamily = Rajdhani, fontWeight = FontWeight.Medium,
                    fontSize = if (big) 64.sp else 28.sp, lineHeight = if (big) 64.sp else 29.sp,
                    color = if (value == null) D7.Faint else D7.Fg, maxLines = 1, softWrap = false)
                Text(unit, fontFamily = PlexMono, fontSize = if (big) 13.sp else 9.sp, color = D7.Mut, letterSpacing = 1.sp, maxLines = 1)
            }
        }
        StatusPill(status, statusText, big)
    }
}

/** Colour-tinted pill with a shape glyph: ▲ below · ● on · ▼ above target. Shape and colour both carry the state. */
@Composable
fun StatusPill(status: TargetStatus, text: String, big: Boolean) {
    val c = D7.status(status)
    val glyph = when (status) { TargetStatus.BELOW -> "▲"; TargetStatus.ON -> "●"; TargetStatus.ABOVE -> "▼"; TargetStatus.UNKNOWN -> "○" }
    Box(Modifier.background(c.copy(alpha = 0.16f), RoundedCornerShape(50)).border(1.dp, c, RoundedCornerShape(50))
        .padding(horizontal = if (big) 12.dp else 9.dp, vertical = if (big) 4.dp else 3.dp)) {
        Text("$glyph $text", fontFamily = PlexMono, fontWeight = FontWeight.Bold, fontSize = if (big) 12.sp else 10.sp, color = c, maxLines = 1)
    }
}

/** The big coaching box: shape badge + cue + detail (≤ 2 lines) + lit three-step scale. */
@Composable
fun CoachBox(
    headline: String, detail: String, color: Color, shape: CoachShape, direction: Int?, active: Boolean, onClick: () -> Unit,
) {
    val bg = if (active) color else D7.Panel2
    val ink = if (active) D7.Ink else D7.Fg
    val sub = if (active) D7.Ink.copy(alpha = 0.82f) else D7.Mut
    val size = when { headline.length >= 14 -> 20.sp; headline.length >= 12 -> 23.sp; headline.length >= 10 -> 26.sp; else -> 28.sp }
    Column(Modifier.fillMaxWidth().background(bg, RoundedCornerShape(16.dp))
        .then(if (active) Modifier else Modifier.border(1.dp, D7.Line, RoundedCornerShape(16.dp)))
        .clickable(onClick = onClick).padding(horizontal = 12.dp, vertical = 12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            CoachBadge(shape, badge = ink, glyph = if (active) color else D7.Faint)
            Spacer(Modifier.width(8.dp))
            Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(headline, fontFamily = Archivo, fontWeight = FontWeight.ExtraBold, fontSize = size, lineHeight = size,
                    color = ink, maxLines = 1, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
                if (detail.isNotEmpty()) Text(detail, fontSize = 13.sp, lineHeight = 16.sp, color = sub, maxLines = 2,
                    overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center, modifier = Modifier.padding(top = 3.dp))
            }
            Spacer(Modifier.width(44.dp))   // balance the badge so the text is centred in the box
        }
        Spacer(Modifier.height(10.dp))
        CoachScale(direction, lit = if (active) color else D7.Faint, ink = ink, active = active)
    }
}

/** Distinct SHAPE per state inside a dark disc: ▲ faster/push · ✓ on target · ▼ ease · ○ nothing to say. */
@Composable
fun CoachBadgePublic(shape: CoachShape, badge: Color, glyph: Color) = CoachBadge(shape, badge, glyph)
@Composable
fun CoachScalePublic(direction: Int?, lit: Color, ink: Color, active: Boolean) = CoachScale(direction, lit, ink, active)

@Composable
private fun CoachBadge(shape: CoachShape, badge: Color, glyph: Color) {
    Canvas(Modifier.size(40.dp)) {
        val c = Offset(size.width / 2, size.height / 2); val r = size.minDimension / 2
        drawCircle(badge, r, c)
        val u = r * 0.55f
        when (shape) {
            CoachShape.UP -> drawPath(Path().apply { moveTo(c.x, c.y - u); lineTo(c.x + u, c.y + u * 0.7f); lineTo(c.x - u, c.y + u * 0.7f); close() }, glyph)
            CoachShape.DOWN -> drawPath(Path().apply { moveTo(c.x, c.y + u); lineTo(c.x + u, c.y - u * 0.7f); lineTo(c.x - u, c.y - u * 0.7f); close() }, glyph)
            CoachShape.CHECK -> drawPath(Path().apply { moveTo(c.x - u * 0.9f, c.y + u * 0.05f); lineTo(c.x - u * 0.25f, c.y + u * 0.7f); lineTo(c.x + u, c.y - u * 0.7f) },
                glyph, style = Stroke(3.5.dp.toPx(), cap = StrokeCap.Round, join = androidx.compose.ui.graphics.StrokeJoin.Round))
            CoachShape.NONE -> drawCircle(glyph, u * 0.8f, c, style = Stroke(2.dp.toPx()))
        }
    }
}

/** EASE · ON TARGET · FASTER — the active step is lit, so you see WHERE you are relative to the target. */
@Composable
private fun CoachScale(direction: Int?, lit: Color, ink: Color, active: Boolean) {
    val steps = listOf("▼ EASE" to -1, "✓ ON TARGET" to 0, "▲ FASTER" to 1)
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        steps.forEach { (label, d) ->
            val on = active && direction == d
            Box(Modifier.weight(1f).height(18.dp)
                .background(if (on) ink else ink.copy(alpha = 0.12f), RoundedCornerShape(50))
                .border(1.dp, ink.copy(alpha = if (on) 1f else 0.35f), RoundedCornerShape(50)), contentAlignment = Alignment.Center) {
                Text(label, fontFamily = PlexMono, fontWeight = FontWeight.Bold, fontSize = 8.5.sp,
                    color = if (on) lit else ink.copy(alpha = 0.75f), maxLines = 1, softWrap = false)
            }
        }
    }
}

/** Design-5 horizontal zone band: segments, labels, begin/mid/end ticks, cyan target bar, white current marker. */
@Composable
fun ZoneBand(labels: List<String>, colors: List<Color>, currentFraction: Float?, targetFraction: Float?) {
    val measurer = rememberTextMeasurer()
    val style = TextStyle(fontFamily = PlexMono, fontSize = 10.sp, color = D7.Fg)
    Canvas(Modifier.fillMaxWidth().height(30.dp)) {
        val top = 6.dp.toPx(); val h = 18.dp.toPx(); val w = size.width; val sw = w / labels.size
        drawRoundRect(D7.Panel2, Offset(0f, top), Size(w, h), androidx.compose.ui.geometry.CornerRadius(3.dp.toPx()))
        labels.forEachIndexed { i, lab ->
            drawRect(colors[i].copy(alpha = 0.25f + 0.1f * i), Offset(i * sw, top), Size(sw - 2.dp.toPx(), h))
            floatArrayOf(0f, .5f, 1f).forEach { t -> drawLine(D7.Faint, Offset(i * sw + sw * t, top + h), Offset(i * sw + sw * t, top + h + 4.dp.toPx()), 1f) }
            val m = measurer.measure(lab, style)
            drawText(m, topLeft = Offset(i * sw + sw / 2 - m.size.width / 2f, top + h / 2 - m.size.height / 2f))
        }
        targetFraction?.let { drawRect(D7.Cyan, Offset(it * w - 1.dp.toPx(), top - 3.dp.toPx()), Size(2.dp.toPx(), h + 6.dp.toPx())) }
        currentFraction?.let { f ->
            val mx = f.coerceIn(0f, 1f) * w
            drawPath(Path().apply { moveTo(mx - 5.dp.toPx(), top - 6.dp.toPx()); lineTo(mx + 5.dp.toPx(), top - 6.dp.toPx()); lineTo(mx, top + 1.dp.toPx()); close() }, D7.Fg)
        }
    }
}

/** Power trend (last 5 min) with a dashed FTP reference line and a hot dot on the latest sample. */
@Composable
fun TrendChart(data: List<Int>, ftp: Int, modifier: Modifier = Modifier) {
    val measurer = rememberTextMeasurer()
    val lab = TextStyle(fontFamily = PlexMono, fontSize = 9.sp, color = D7.Faint)
    Box(modifier.fillMaxWidth().height(130.dp).background(D7.Panel).border(1.dp, D7.Line)) {
        Canvas(Modifier.fillMaxSize().padding(8.dp)) {
            val maxV = (data.maxOrNull() ?: 0).coerceAtLeast(ftp).toFloat() * 1.05f
            val ftpY = size.height * (1f - ftp / maxV)
            drawLine(Color(0xFF13202A), Offset(0f, ftpY), Offset(size.width, ftpY), 1.5f, pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f)))
            drawText(measurer.measure("FTP", lab), topLeft = Offset(0f, ftpY - 12.dp.toPx()))
            if (data.size < 2) return@Canvas
            val dx = size.width / (data.size - 1)
            var prev: Offset? = null
            data.forEachIndexed { i, v ->
                val p = Offset(i * dx, size.height * (1f - (v / maxV).coerceIn(0f, 1f)))
                prev?.let { drawLine(D7.Cyan, it, p, 2.5.dp.toPx(), cap = StrokeCap.Round) }
                prev = p
            }
            prev?.let { drawCircle(D7.Cyan, 3.dp.toPx(), it) }
        }
        if (data.size < 2) Text("power trend appears once the ride starts", fontFamily = PlexMono, fontSize = 10.sp, color = D7.Faint,
            modifier = Modifier.align(Alignment.Center))
    }
}

@Composable
fun SectionLabel(text: String) {
    Text(text, fontFamily = PlexMono, fontSize = 11.sp, color = D7.Mut, maxLines = 1, overflow = TextOverflow.Ellipsis)
}

@Composable
fun Stat(value: String, label: String, modifier: Modifier = Modifier) {
    Column(modifier) {
        Text(value, fontFamily = Rajdhani, fontWeight = FontWeight.Medium, fontSize = 26.sp, lineHeight = 26.sp, color = if (value == "—") D7.Faint else D7.Fg, maxLines = 1)
        Text(label, fontFamily = PlexMono, fontSize = 9.sp, color = D7.Mut, maxLines = 1)
    }
}

fun fmtVi(vi: Double?): String = vi?.let { String.format(Locale.US, "%.2f", it) } ?: "—"
fun fmtKm(km: Double, hasFix: Boolean): String = if (hasFix || km > 0) String.format(Locale.US, "%.1f km", km) else "—"
