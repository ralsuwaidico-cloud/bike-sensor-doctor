package com.rashed.bikesensordoctor.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rashed.bikesensordoctor.core.BoardMetric
import com.rashed.bikesensordoctor.core.Leaderboard
import com.rashed.bikesensordoctor.core.RideSource
import com.rashed.bikesensordoctor.core.RiderAnswers
import com.rashed.bikesensordoctor.core.RiderProfile
import com.rashed.bikesensordoctor.ride.DemoClub
import com.rashed.bikesensordoctor.ride.Rider
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/*
 * Club and leaderboard — DEMO. Everything is on this phone: the club, the invite code, the four sample riders and
 * their SAMPLE rides. No server, no real accounts. Your own device-recorded rides are listed as real; simulated
 * rides are flagged. A production board would count device-recorded, verified rides only.
 */

@Composable
private fun DemoBanner(text: String) {
    Row(Modifier.fillMaxWidth().background(D7.Amber.copy(alpha = 0.10f), RoundedCornerShape(10.dp)).border(1.dp, D7.Amber.copy(alpha = 0.5f), RoundedCornerShape(10.dp)).padding(8.dp), verticalAlignment = Alignment.Top) {
        DemoTag(); Spacer(Modifier.width(8.dp)); Text(text, fontSize = 11.sp, lineHeight = 15.sp, color = D7.Amber, modifier = Modifier.weight(1f))
    }
}

@Composable
fun ClubScreen(vm: DoctorViewModel, onTab: (String) -> Unit, onMember: (String) -> Unit) {
    val ctx = LocalContext.current
    val me = vm.engine.rider ?: return
    var tick by remember { mutableIntStateOf(0) }
    val riders = remember(tick) { vm.engine.riders.list() }
    val members = remember(tick) { DemoClub.members(ctx).mapNotNull { id -> riders.firstOrNull { it.id == id } } }
    val rides = remember(tick) { DemoClub.allRides(vm.engine.riders, riders) }
    val inClub = members.any { it.id == me.id }
    var code by remember { mutableStateOf("") }
    var codeErr by remember { mutableStateOf(false) }
    val week = DemoClub.weekStartMs(); val month = DemoClub.monthStartMs()

    Column(Modifier.fillMaxSize().background(D7.Bg)) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 14.dp, vertical = 8.dp)) {
            D7TopBar("CLUB", null, null)
            Headline(DemoClub.NAME)
            Muted("Private group · invite code ${DemoClub.CODE} · ${members.size} riders", 12)
            Spacer(Modifier.height(8.dp))
            DemoBanner("Local demo club with fictional riders. There is no online account, server or real invite system yet; joining stores membership on this phone only.")
            Spacer(Modifier.height(8.dp))
            if (!inClub) D7Card(accent = D7.Green) {
                CardTitle("YOU ARE NOT IN THIS CLUB YET")
                Text("Enter the invite code to join and compare rides.", fontSize = 13.sp, color = D7.Fg)
                Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(value = code, onValueChange = { code = it.uppercase().take(12); codeErr = false }, singleLine = true, label = { Text(if (codeErr) "Not found" else "Invite code", fontSize = 11.sp) }, modifier = Modifier.weight(1f).testTag("invite_code"),
                        textStyle = TextStyle(fontFamily = PlexMono, fontSize = 15.sp, color = D7.Fg),
                        colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = D7.Cyan, unfocusedBorderColor = if (codeErr) D7.Red else D7.Line, focusedLabelColor = D7.Cyan, unfocusedLabelColor = D7.Mut, cursorColor = D7.Cyan))
                    Spacer(Modifier.width(8.dp))
                    PrimaryButton("JOIN", Modifier.testTag("join_btn")) { if (code.trim() == DemoClub.CODE) { DemoClub.join(ctx, me.id); tick++ } else codeErr = true }
                }
            }
            Spacer(Modifier.height(6.dp))
            CardTitle("CHALLENGES")
            val mine = { m: BoardMetric -> m.score(Leaderboard.ridesIn(rides, me.id, if (m.weekly) week else month, true)) }
            listOf(Triple(BoardMetric.WEEK_KM, "Ride 120 km this week", 120.0), Triple(BoardMetric.TIME, "20 hours in the saddle this month", 20.0), Triple(BoardMetric.Z2, "Three Zone 2 rides (≥80% in your band) this month", 3.0)).forEach { (m, title, target) ->
                val v = if (inClub) mine(m) else 0.0
                val done = members.count { r -> m.score(Leaderboard.ridesIn(rides, r.id, if (m.weekly) week else month, true)) >= target }
                D7Card(Modifier.padding(vertical = 3.dp)) {
                    Row { Text(title, fontSize = 13.sp, fontWeight = FontWeight.Bold, color = D7.Fg, modifier = Modifier.weight(1f)); Text("${m.format(v)} / ${m.format(target)}", fontFamily = PlexMono, fontSize = 12.sp, color = D7.Fg) }
                    Box(Modifier.fillMaxWidth().height(6.dp).padding(top = 2.dp).background(D7.Track, RoundedCornerShape(3.dp))) { Box(Modifier.fillMaxWidth((v / target).toFloat().coerceIn(0f, 1f)).height(6.dp).background(D7.Green, RoundedCornerShape(3.dp))) }
                    Text("${if (m.weekly) "Resets Monday" else "Resets on the 1st"} · $done of ${members.size} done${if (v >= target) " · ★ you completed it" else ""}", fontSize = 11.sp, color = D7.Mut, modifier = Modifier.padding(top = 3.dp))
                }
            }
            Spacer(Modifier.height(6.dp))
            CardTitle("MEMBERS")
            members.forEach { r ->
                val ach = Leaderboard.achievements(rides.filter { it.riderId == r.id }, week, month)
                Row(Modifier.fillMaxWidth().padding(vertical = 3.dp).background(D7.Panel2, RoundedCornerShape(12.dp)).border(1.dp, if (r.id == me.id) D7.Cyan else D7.Line, RoundedCornerShape(12.dp))
                    .clickable { onMember(r.id) }.padding(horizontal = 10.dp, vertical = 8.dp).testTag("member_${r.id}"), verticalAlignment = Alignment.CenterVertically) {
                    Avatar(r.initials); Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Row(verticalAlignment = Alignment.CenterVertically) { Text(r.name + (if (r.id == me.id) " (you)" else ""), fontWeight = FontWeight.Bold, fontSize = 14.sp, color = D7.Fg); if (r.isSample) { Spacer(Modifier.width(6.dp)); SampleTag() } }
                        val wk = Leaderboard.ridesIn(rides, r.id, week, true).size
                        Text("${RiderAnswers.GOAL_SHORT[RiderProfile.primaryGoal(r.answers)] ?: "—"} · $wk ride${if (wk == 1) "" else "s"} this week" + (if (ach.isNotEmpty()) "\n" + ach.joinToString(" · ") { "★ " + it.title } else ""), fontSize = 11.sp, lineHeight = 14.sp, color = D7.Mut)
                    }
                }
            }
            Spacer(Modifier.height(8.dp))
            D7Card {
                CardTitle("FRIENDS & GROUPS")
                Text("Adding friends by code and creating private groups need the cloud service (planned, not built). Your code would be ${me.id.uppercase().take(6)}-${me.name.take(3).uppercase()}.", fontSize = 12.sp, lineHeight = 16.sp, color = D7.Mut)
                if (inClub && !me.isSample) androidx.compose.material3.TextButton(onClick = { DemoClub.leave(ctx, me.id); tick++ }) { Text("Leave club", color = D7.Red, fontSize = 12.sp) }
            }
            Spacer(Modifier.height(8.dp))
            Muted("Privacy: members see name, distance, time, elevation, ride count and achievements. Heart rate, zones, FTP, power and coaching stay private.", 11)
            Spacer(Modifier.height(12.dp))
        }
        Column(Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) { TabBar("CLUB", onTab) }
    }
}

@Composable
fun BoardScreen(vm: DoctorViewModel, onTab: (String) -> Unit) {
    val ctx = LocalContext.current
    val me = vm.engine.rider ?: return
    var metric by remember { mutableStateOf(BoardMetric.WEEK_KM) }
    val riders = remember { vm.engine.riders.list() }
    val members = remember { DemoClub.members(ctx).mapNotNull { id -> riders.firstOrNull { it.id == id } }.map { DemoClub.boardRider(it) } }
    val rides = remember { DemoClub.allRides(vm.engine.riders, riders) }
    val week = DemoClub.weekStartMs(); val month = DemoClub.monthStartMs()
    val rows = Leaderboard.rows(metric, members, rides, week, month, includeDemo = true)
    val myIdx = rows.indexOfFirst { it.rider.id == me.id }
    val unit = if (metric == BoardMetric.Z2) "rides" else metric.unit
    val resetAt = SimpleDateFormat("EEE d MMM", Locale.getDefault()).format(Date(if (metric.weekly) DemoClub.weekEndMs() else DemoClub.monthEndMs()))
    val hasSim = rides.any { it.riderId == me.id && it.source == RideSource.SIMULATED }

    Column(Modifier.fillMaxSize().background(D7.Bg)) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 14.dp, vertical = 8.dp)) {
            D7TopBar("LEADERBOARD · ${DemoClub.NAME.uppercase()}", null, null)
            Headline(metric.label, 20)
            Spacer(Modifier.height(6.dp))
            Chips(BoardMetric.values().map { it.name to it.short }, setOf(metric.name), columns = 3, small = true) { k -> metric = BoardMetric.valueOf(k) }
            Spacer(Modifier.height(6.dp))
            Muted("Resets $resetAt · ranked by ${if (metric == BoardMetric.Z2) "rides with ≥80% of time inside each rider's own Zone 2 band" else metric.unit}. Never by watts or speed: terrain, bike, weight and wind make those unfair.", 11)
            Spacer(Modifier.height(6.dp))
            DemoBanner("Demo board: sample riders' rides are fictional${if (hasSim) "; your SIMULATED rides are flagged and would never count on a real board" else ""}. A production board counts device-recorded, verified rides only.")
            Spacer(Modifier.height(8.dp))
            rows.forEach { row ->
                val meRow = row.rider.id == me.id
                Row(Modifier.fillMaxWidth().padding(vertical = 3.dp).background(if (meRow) D7.Cyan.copy(alpha = 0.10f) else D7.Panel2, RoundedCornerShape(12.dp)).border(1.dp, if (meRow) D7.Cyan else D7.Line, RoundedCornerShape(12.dp))
                    .padding(horizontal = 10.dp, vertical = 8.dp).testTag("board_row_${row.rider.id}"), verticalAlignment = Alignment.CenterVertically) {
                    Text("${row.rank}", fontFamily = Archivo, fontWeight = FontWeight.ExtraBold, fontSize = 20.sp, color = if (row.rank == 1) D7.Amber else D7.Mut, modifier = Modifier.width(26.dp))
                    Avatar(row.rider.name.take(1).uppercase(), 30); Spacer(Modifier.width(8.dp))
                    Column(Modifier.weight(1f)) {
                        Text(row.rider.name + (if (meRow) " (you)" else ""), fontWeight = FontWeight.Bold, fontSize = 14.sp, color = D7.Fg, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Row { if (row.rider.isSample) SampleTag() else if (row.hasSimulated) SimTag() else if (row.rideCount > 0) Tag("REAL", D7.Green) }
                    }
                    Text(metric.format(row.score), fontFamily = Rajdhani, fontWeight = FontWeight.SemiBold, fontSize = 22.sp, color = D7.Fg)
                    Text(" $unit", fontFamily = PlexMono, fontSize = 9.sp, color = D7.Mut)
                }
            }
            Spacer(Modifier.height(8.dp))
            D7Card {
                CardTitle("YOUR POSITION")
                Text(if (myIdx < 0) "You are not in this club yet — join it from the Club tab." else {
                    val r = rows[myIdx]; "#${r.rank} of ${rows.size} with ${metric.format(r.score)} $unit" + (if (myIdx > 0) " · ${metric.format(rows[myIdx - 1].score - r.score)} $unit behind ${rows[myIdx - 1].rider.name}" else " · leading") + ". Rides counted this period: ${r.rideCount}."
                }, fontSize = 13.sp, lineHeight = 17.sp, color = D7.Fg)
            }
            if (myIdx >= 0) { val ach = Leaderboard.achievements(rides.filter { it.riderId == me.id }, week, month); if (ach.isNotEmpty()) D7Card(Modifier.padding(top = 8.dp)) { CardTitle("YOUR ACHIEVEMENTS"); Text(ach.joinToString(" · ") { "★ " + it.title }, fontSize = 13.sp, color = D7.Fg) } }
            Spacer(Modifier.height(12.dp))
        }
        Column(Modifier.padding(horizontal = 10.dp, vertical = 8.dp)) { TabBar("BOARD", onTab) }
    }
}

@Composable
fun MemberScreen(vm: DoctorViewModel, riderId: String, onBack: () -> Unit) {
    val r: Rider? = remember(riderId) { vm.engine.riders.load(riderId) }
    val me = vm.engine.rider
    Column(Modifier.fillMaxSize().background(D7.Bg).verticalScroll(rememberScrollState()).padding(14.dp)) {
        D7TopBar("RIDER", "Club", onBack)
        if (r == null) { Text("Rider not found.", color = D7.Mut); return@Column }
        val a = r.answers; val c = RiderProfile.deriveSetup(a)
        val cal = java.util.Calendar.getInstance(); val w = RiderProfile.recommend(a, c, r.feedback, (cal.get(java.util.Calendar.DAY_OF_WEEK) + 5) % 7)
        val riders = vm.engine.riders.list(); val rides = DemoClub.allRides(vm.engine.riders, riders).filter { it.riderId == r.id }
        val month = DemoClub.monthStartMs(); val mo = rides.filter { it.startedAtMs >= month }
        val isMe = me?.id == r.id
        Row(verticalAlignment = Alignment.CenterVertically) { Avatar(r.initials, 40); Spacer(Modifier.width(10.dp)); Column { Headline(r.name + (if (isMe) " (you)" else ""), 22); if (r.isSample) SampleTag() } }
        Spacer(Modifier.height(10.dp))
        KeyValue(listOf(
            "Goal" to (RiderAnswers.GOAL_SHORT[RiderProfile.primaryGoal(a)] ?: "—"), "Experience" to (a["experience"] ?: "—"),
            "This month" to "${String.format(Locale.US, "%.0f", mo.sumOf { it.km })} km · ${String.format(Locale.US, "%.1f", mo.sumOf { it.sec } / 3600.0)} h · ${mo.sumOf { it.elevM }.toInt()} m · ${mo.size} rides",
            "Achievements" to Leaderboard.achievements(rides, DemoClub.weekStartMs(), month).joinToString(" · ") { "★ " + it.title }.ifEmpty { "none yet" },
        ))
        D7Card(Modifier.padding(top = 10.dp)) {
            if (isMe) { CardTitle("PRIVATE TO YOU"); Row(verticalAlignment = Alignment.CenterVertically) { ConfidenceTag(c.zoneConfidence); Spacer(Modifier.width(6.dp)); Text("Zone 2 ${c.hrTargetLo}–${c.hrTargetHi} bpm · ${if (c.powerCoaching) "FTP ${c.ftp} W" else "power off"}", fontSize = 13.sp, color = D7.Fg) }; Text("Next: ${w.name}, ${w.minutes} min", fontSize = 12.sp, color = D7.Mut) }
            else { CardTitle("COACHING IS PERSONAL"); Text("${r.name}'s heart-rate zones, FTP and power are private. Their coach currently recommends ${w.name}, ${w.minutes} min — a different plan from yours because goal and calibration differ.", fontSize = 13.sp, lineHeight = 17.sp, color = D7.Fg) }
        }
        Spacer(Modifier.height(16.dp))
    }
}
