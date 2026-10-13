package com.rashed.bikesensordoctor.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
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
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rashed.bikesensordoctor.core.ZoneConfidence

/*
 * Small Design-7 building blocks shared by the onboarding, home, club and leaderboard screens.
 * Compact by design: the Nokia 5.3 is 360 dp wide, so controls are chips and sliders, not long lists.
 */

@Composable
fun D7TopBar(title: String, back: String?, onBack: (() -> Unit)?, right: @Composable (() -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().padding(bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        if (onBack != null) TextButton(onClick = onBack, contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 4.dp)) { Text("‹ ${back ?: ""}", color = D7.Cyan, fontSize = 15.sp, maxLines = 1) }
        Text(title, fontFamily = PlexMono, fontSize = 12.sp, color = D7.Cyan, letterSpacing = 2.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f).padding(start = if (onBack == null) 4.dp else 0.dp))
        right?.invoke()
    }
}

@Composable
fun Eyebrow(text: String) = Text(text, fontFamily = PlexMono, fontSize = 10.sp, color = D7.Cyan, letterSpacing = 1.5.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)

@Composable
fun Headline(text: String, size: Int = 22) = Text(text, fontFamily = Archivo, fontWeight = FontWeight.ExtraBold, fontSize = size.sp, lineHeight = (size + 4).sp, color = D7.Fg)

@Composable
fun Muted(text: String, size: Int = 13) = Text(text, fontSize = size.sp, lineHeight = (size + 5).sp, color = D7.Mut)

@Composable
fun FieldLabel(text: String, optional: Boolean = false) {
    Row(Modifier.padding(top = 10.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(text, fontFamily = PlexMono, fontSize = 10.sp, color = D7.Mut, letterSpacing = 1.sp)
        if (optional) Text("  optional", fontFamily = PlexMono, fontSize = 9.sp, color = D7.Faint)
    }
}

/** Colour tag: REAL / SIMULATED / SAMPLE / CONFIRMED / PROVISIONAL / GENERIC / DEMO. */
@Composable
fun Tag(text: String, color: Color, modifier: Modifier = Modifier) {
    Box(modifier.background(color.copy(alpha = 0.16f), RoundedCornerShape(5.dp)).border(1.dp, color.copy(alpha = 0.6f), RoundedCornerShape(5.dp)).padding(horizontal = 5.dp, vertical = 1.dp)) {
        Text(text, fontFamily = PlexMono, fontSize = 9.sp, color = color, fontWeight = FontWeight.Bold, maxLines = 1)
    }
}

@Composable
fun ConfidenceTag(c: ZoneConfidence) = when (c) {
    ZoneConfidence.CONFIRMED -> Tag("CONFIRMED", D7.Green)
    ZoneConfidence.PROVISIONAL -> Tag("PROVISIONAL", D7.Amber)
    ZoneConfidence.GENERIC -> Tag("GENERIC", D7.Amber)
}

@Composable
fun SampleTag() = Tag("SAMPLE", D7.Amber)
@Composable
fun DemoTag() = Tag("DEMO", D7.Amber)
@Composable
fun SimTag() = Tag("SIMULATED", D7.Amber)

/** A card with a thin line border; accent = green border for the recommended item. */
@Composable
fun D7Card(modifier: Modifier = Modifier, accent: Color? = null, content: @Composable ColumnScope.() -> Unit) {
    Column(modifier.fillMaxWidth().background(D7.Panel2, RoundedCornerShape(12.dp)).border(1.dp, accent ?: D7.Line, RoundedCornerShape(12.dp)).padding(10.dp), content = content)
}

@Composable
fun CardTitle(text: String) = Text(text, fontFamily = PlexMono, fontSize = 10.sp, color = D7.Mut, letterSpacing = 1.sp, modifier = Modifier.padding(bottom = 4.dp))

/** Segmented chips. Single-select: [selected] holds one key; multi: comma list. */
@Composable
fun Chips(options: List<Pair<String, String>>, selected: Set<String>, columns: Int = 0, small: Boolean = false, onClick: (String) -> Unit) {
    val rows = if (columns > 0) options.chunked(columns) else listOf(options)
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        rows.forEach { row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                row.forEach { (k, label) ->
                    val on = k in selected
                    Box(Modifier.weight(1f).background(if (on) D7.Cyan.copy(alpha = 0.14f) else D7.Panel2, RoundedCornerShape(9.dp))
                        .border(1.dp, if (on) D7.Cyan else D7.Line, RoundedCornerShape(9.dp)).clickable { onClick(k) }
                        .padding(horizontal = 6.dp, vertical = if (small) 7.dp else 10.dp), contentAlignment = Alignment.Center) {
                        Text(label, fontSize = if (small) 11.sp else 12.5.sp, lineHeight = 14.sp, color = if (on) D7.Cyan else D7.Fg, fontWeight = if (on) FontWeight.Bold else FontWeight.Normal,
                            maxLines = 2, overflow = TextOverflow.Ellipsis, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                    }
                }
                if (columns > 0) repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/** Compact numeric field with a unit label. Empty = unknown. */
@Composable
fun NumberField(value: Int?, unit: String, min: Int, max: Int, modifier: Modifier = Modifier, onChange: (Int?) -> Unit) {
    var text by remember(value) { mutableStateOf(value?.toString() ?: "") }
    OutlinedTextField(
        value = text, onValueChange = { t -> text = t.filter { it.isDigit() }.take(3); val v = text.toIntOrNull(); onChange(if (v != null && v in min..max) v else null) },
        modifier = modifier, singleLine = true, label = { Text(unit, fontSize = 11.sp) },
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), textStyle = TextStyle(fontFamily = PlexMono, fontSize = 16.sp, color = D7.Fg),
        colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = D7.Cyan, unfocusedBorderColor = D7.Line, focusedLabelColor = D7.Cyan, unfocusedLabelColor = D7.Mut, cursorColor = D7.Cyan),
    )
}

@Composable
fun SliderRow(value: Int, min: Int, max: Int, step: Int, unit: String, onChange: (Int) -> Unit) {
    var v by remember { mutableStateOf(value) }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text("$v $unit", fontFamily = Rajdhani, fontWeight = FontWeight.SemiBold, fontSize = 22.sp, color = D7.Fg, modifier = Modifier.width(92.dp))
        Slider(value = v.toFloat(), onValueChange = { v = (Math.round(it / step) * step).coerceIn(min, max); onChange(v) }, valueRange = min.toFloat()..max.toFloat(),
            modifier = Modifier.weight(1f), colors = SliderDefaults.colors(thumbColor = D7.Cyan, activeTrackColor = D7.Cyan, inactiveTrackColor = D7.Track))
    }
}

@Composable
fun PrimaryButton(text: String, modifier: Modifier = Modifier, color: Color = D7.Green, enabled: Boolean = true, onClick: () -> Unit) {
    Button(onClick = onClick, modifier.height(48.dp), enabled = enabled, shape = RoundedCornerShape(12.dp),
        colors = ButtonDefaults.buttonColors(containerColor = color, contentColor = D7.Ink, disabledContainerColor = D7.Track, disabledContentColor = D7.Faint)) {
        Text(text, fontFamily = Archivo, fontWeight = FontWeight.ExtraBold, fontSize = 14.sp, maxLines = 1)
    }
}

@Composable
fun SecondaryButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Button(onClick = onClick, modifier.height(48.dp), shape = RoundedCornerShape(12.dp), colors = ButtonDefaults.buttonColors(containerColor = D7.Panel2, contentColor = D7.Fg),
        border = androidx.compose.foundation.BorderStroke(1.dp, D7.Line)) {
        Text(text, fontFamily = Archivo, fontWeight = FontWeight.ExtraBold, fontSize = 13.sp, maxLines = 1)
    }
}

@Composable
fun Avatar(initials: String, size: Int = 34) {
    Box(Modifier.size(size.dp).background(Color(0xFF123038), CircleShape).border(1.dp, D7.Cyan, CircleShape), contentAlignment = Alignment.Center) {
        Text(initials, fontFamily = Archivo, fontWeight = FontWeight.ExtraBold, fontSize = (size * 0.38).sp, color = D7.Cyan)
    }
}

@Composable
fun KeyValue(rows: List<Pair<String, String>>) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(5.dp)) {
        rows.forEach { (k, v) ->
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Top) {
                Text(k.uppercase(), fontFamily = PlexMono, fontSize = 10.sp, color = D7.Mut, modifier = Modifier.width(96.dp).padding(top = 2.dp))
                Text(v, fontSize = 13.sp, lineHeight = 17.sp, color = D7.Fg, modifier = Modifier.weight(1f))
            }
        }
    }
}

@Composable
fun Bullets(items: List<String>) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(3.dp)) {
        items.forEach { Row { Text("•  ", fontSize = 13.sp, color = D7.Mut); Text(it, fontSize = 13.sp, lineHeight = 17.sp, color = D7.Fg) } }
    }
}

/** Bottom tab bar: HOME · CLUB · BOARD · ME. */
@Composable
fun TabBar(current: String, onTab: (String) -> Unit) {
    Row(Modifier.fillMaxWidth().background(D7.Panel, RoundedCornerShape(14.dp)).padding(4.dp), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        listOf("HOME", "CLUB", "BOARD", "ME").forEach { t ->
            val on = t == current
            Box(Modifier.weight(1f).background(if (on) D7.Cyan.copy(alpha = 0.14f) else Color.Transparent, RoundedCornerShape(10.dp)).clickable { onTab(t) }.padding(vertical = 9.dp), contentAlignment = Alignment.Center) {
                Text(t, fontFamily = PlexMono, fontSize = 11.sp, letterSpacing = 1.sp, color = if (on) D7.Cyan else D7.Mut, fontWeight = if (on) FontWeight.Bold else FontWeight.Normal)
            }
        }
    }
}
