package com.rashed.bikesensordoctor.diag

import com.rashed.bikesensordoctor.ble.BleScanner
import com.rashed.bikesensordoctor.ble.ConnectionState
import com.rashed.bikesensordoctor.ble.GattManager
import com.rashed.bikesensordoctor.ble.ScannedDevice
import com.rashed.bikesensordoctor.ble.Uuids
import com.rashed.bikesensordoctor.log.EventLog
import com.rashed.bikesensordoctor.log.EventType
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

enum class Outcome { WORKING, FIXED, COMPATIBILITY_ISSUE, NEEDS_ATTENTION, INCONCLUSIVE }

data class StepStatus(val title: String, val state: String, val detail: String = "") // state: pending|running|ok|warn|fail

data class ApprovalRequest(
    val title: String,
    val explanation: String,
    val risks: String,
    val response: CompletableDeferred<Boolean>,
)

data class AutoState(
    val running: Boolean = false,
    val progress: Float = 0f,
    val headline: String = "",
    val instruction: String = "",           // big instruction to the user, e.g. "PEDAL NOW"
    val countdown: Int = 0,
    val steps: List<StepStatus> = emptyList(),
    val approval: ApprovalRequest? = null,
    val outcome: Outcome? = null,
    val summary: String = "",               // plain-language: what was tested / fixed / next
    val technicalReport: String = "",
    val reportPath: String = "",
)

/**
 * One-button orchestrator. Runs scan → identify → connect → inspect → read-only tests → safe fixes → retest,
 * and classifies the result. Every conclusion comes from observed events; nothing is simulated.
 */
class AutoDiagnostic(
    private val scanner: BleScanner,
    private val gatt: GattManager,
    private val log: EventLog,
    private val scope: CoroutineScope,
    private val saveReport: (String) -> String,   // writes text, returns path
) {
    companion object {
        const val TARGET_MAC = "C0:A1:25:07:97:69"
        const val TARGET_NAME = "XDS-A001-9769"
        const val SCAN_SECONDS = 40
        const val STILL_SECONDS = 15
        const val PEDAL_SECONDS = 30
        const val RETEST_SECONDS = 25
    }

    private val _state = MutableStateFlow(AutoState())
    val state: StateFlow<AutoState> = _state
    private var job: Job? = null

    private val stepTitles = listOf(
        "Bluetooth ready", "Find the power meter", "Connect and identify", "Battery and firmware",
        "Bluetooth services", "Listen while still", "Listen while pedaling", "Try safe fixes", "Final verdict",
    )

    fun start(bluetoothOn: Boolean) {
        job?.cancel()
        job = scope.launch { run(bluetoothOn) }
    }

    fun cancel() {
        job?.cancel(); job = null
        gatt.disconnect(); scanner.stop()
        _state.value = AutoState()
    }

    fun answerApproval(yes: Boolean) { _state.value.approval?.response?.complete(yes) }

    private fun step(i: Int, state: String, detail: String = "") {
        _state.update { s ->
            val steps = if (s.steps.isEmpty()) stepTitles.map { StepStatus(it, "pending") } else s.steps
            s.copy(steps = steps.mapIndexed { idx, st -> if (idx == i) st.copy(state = state, detail = detail) else st },
                progress = (i + (if (state == "running") 0.5f else 1f)) / stepTitles.size)
        }
    }

    private fun headline(h: String, instruction: String = "") { _state.update { it.copy(headline = h, instruction = instruction) } }

    private suspend fun countdown(seconds: Int, instruction: String) {
        for (s in seconds downTo 1) { _state.update { it.copy(countdown = s, instruction = instruction) }; delay(1000) }
        _state.update { it.copy(countdown = 0, instruction = "") }
    }

    private suspend fun requestApproval(title: String, explanation: String, risks: String): Boolean {
        val d = CompletableDeferred<Boolean>()
        _state.update { it.copy(approval = ApprovalRequest(title, explanation, risks, d)) }
        val answer = d.await()
        _state.update { it.copy(approval = null) }
        log.add(EventType.TEST, note = "User approval for '$title': ${if (answer) "YES" else "NO"}")
        return answer
    }

    /** Count notifications since [sinceSeq], per characteristic, with distinct payload counts. */
    private fun collect(sinceSeq: Long, seconds: Int): PhaseResult {
        val events = log.entries.value.filter { it.seq > sinceSeq && it.type == EventType.NOTIFY }
        val counts = HashMap<String, Int>(); val distinct = HashMap<String, MutableSet<String>>(); val samples = HashMap<String, MutableList<String>>()
        for (e in events) {
            counts[e.uuid] = (counts[e.uuid] ?: 0) + 1
            distinct.getOrPut(e.uuid) { HashSet() }.add(e.hex)
            val l = samples.getOrPut(e.uuid) { ArrayList() }; if (l.size < 3) l.add(e.hex)
        }
        return PhaseResult(seconds, counts, distinct.mapValues { it.value.size }, samples)
    }

    private fun lastSeq() = log.entries.value.lastOrNull()?.seq ?: 0L

    /** True when the stream looks like measurements: pedaling produced clearly more / more varied data than stillness. */
    private fun respondsToPedaling(still: PhaseResult, pedal: PhaseResult): Boolean {
        if (pedal.total == 0) return false
        if (still.total == 0) return true
        val varietyUp = pedal.distinctPayloadsByUuid.values.sum() > still.distinctPayloadsByUuid.values.sum() * 1.5
        val rateUp = pedal.total > still.total * 1.5
        return varietyUp || rateUp
    }

    private suspend fun waitForState(target: ConnectionState, timeoutMs: Long): Boolean =
        withTimeoutOrNull(timeoutMs) {
            while (gatt.snapshot.value.state != target) {
                if (gatt.snapshot.value.state == ConnectionState.DISCONNECTED && gatt.snapshot.value.lastError != null) delay(500)
                delay(250)
            }
            true
        } ?: false

    private suspend fun run(bluetoothOn: Boolean) {
        log.clear()
        log.add(EventType.INFO, note = "AUTO DIAGNOSTIC started")
        _state.value = AutoState(running = true, steps = stepTitles.map { StepStatus(it, "pending") })
        val tested = ArrayList<String>(); val fixed = ArrayList<String>(); val next = ArrayList<String>()
        var outcome = Outcome.INCONCLUSIVE

        // 0. Bluetooth
        step(0, "running"); headline("Checking Bluetooth…")
        if (!bluetoothOn) {
            step(0, "fail", "Bluetooth is off")
            finish(Outcome.INCONCLUSIVE, "Bluetooth is switched off, so nothing could be tested.", listOf(), listOf(), listOf("Turn Bluetooth on, then press the button again."), null)
            return
        }
        step(0, "ok", "Bluetooth on, permissions granted"); tested += "Phone Bluetooth and permissions"

        // 1. Scan
        step(1, "running"); headline("Looking for the power meter…", "Rotate the pedals a few times so the sensor wakes up")
        scanner.clear()
        if (!scanner.start()) {
            step(1, "fail", scanner.error.value ?: "scan failed")
            finish(Outcome.INCONCLUSIVE, "The phone could not start a Bluetooth scan (${scanner.error.value}).", tested, fixed, listOf("Switch Bluetooth off and on, wait 30 seconds, and try again."), null)
            return
        }
        var found: ScannedDevice? = null
        for (s in SCAN_SECONDS downTo 1) {
            _state.update { it.copy(countdown = s) }
            val devs = scanner.devices.value
            found = devs[TARGET_MAC] ?: devs.values.firstOrNull { it.name == TARGET_NAME }
            if (found != null && found.seenCount >= 3) break
            delay(1000)
        }
        scanner.stop()
        _state.update { it.copy(countdown = 0, instruction = "") }
        val candidates = scanner.devices.value.values.filter { it.looksLikeXds }
        val meter: ScannedDevice = found ?: run {
            val other = candidates.firstOrNull()
            if (other == null) {
                step(1, "fail", "Not found in $SCAN_SECONDS s (${scanner.devices.value.size} other devices seen)")
                tested += "Scan for $SCAN_SECONDS seconds (${scanner.devices.value.size} other Bluetooth devices were visible)"
                finish(Outcome.INCONCLUSIVE, "The power meter did not show up on Bluetooth at all. This usually means it is asleep, its battery is flat, or it is too far away — not a software problem.",
                    tested, fixed, listOf("Spin the cranks for 10 seconds, hold the phone within 1 metre of the crank spider, and press the button again.", "If it never appears, open the battery cover and reseat or replace the coin cell."), null)
                return
            }
            step(1, "warn", "Known meter not seen; similar device ${other.displayName} ${other.address}")
            other
        }
        if (found != null) step(1, "ok", "${meter.displayName} at ${"%.0f".format(meter.rssiAvg)} dBm, ${meter.seenCount} adverts")
        tested += "Found ${meter.displayName} (signal ${"%.0f".format(meter.rssiAvg)} dBm)"
        if (!meter.advertisesCyclingService) tested += "Its Bluetooth advertisement does NOT announce the standard cycling-power or cadence service that Garmin looks for"

        // 2. Connect
        step(2, "running"); headline("Connecting…")
        var connected = false
        for (attempt in 1..3) {
            gatt.connect(meter.address, meter.name, reconnect = false)
            connected = waitForState(ConnectionState.READY, 30_000)
            if (connected) break
            log.add(EventType.TEST, note = "Connect attempt $attempt failed; retrying")
            gatt.disconnect(silent = true); delay(2000)
        }
        if (!connected) {
            step(2, "fail", gatt.snapshot.value.lastError ?: "no response")
            finish(Outcome.INCONCLUSIVE, "The sensor was visible but refused or dropped the connection three times (${gatt.snapshot.value.lastError ?: "no response"}).",
                tested, fixed, listOf("Move the phone next to the crank, switch Bluetooth off/on and retry.", "Make sure no other app or bike computer is connected to the sensor at the same time — it accepts only one connection."), null)
            return
        }
        val snap0 = gatt.snapshot.value
        step(2, "ok", "Connected; ${snap0.services.size} services found"); tested += "Bluetooth connection and service discovery"

        // 3. Battery / firmware (reads were queued by discovery; give them time)
        step(3, "running"); headline("Reading battery and firmware…")
        delay(6000)
        val snap1 = gatt.snapshot.value
        val battery = snap1.batteryPct
        val fw = snap1.deviceInfo["Firmware Revision"]; val model = snap1.deviceInfo["Model Number"]
        if (battery != null) {
            step(3, if (battery < 15) "warn" else "ok", "Battery $battery %${fw?.let { ", firmware $it" } ?: ""}${model?.let { ", model $it" } ?: ""}")
            tested += "Battery ($battery %)" + (fw?.let { ", firmware $it" } ?: "")
            if (battery < 15) next += "The battery is low ($battery %). Replace the coin cell before trusting any other result."
        } else { step(3, "warn", "Battery level could not be read"); tested += "Battery level (could not be read)" }

        // 4. Services
        step(4, "running"); headline("Checking Bluetooth services…")
        val std = snap1.hasCyclingPower || snap1.hasCsc
        val detail = buildString {
            append(if (snap1.hasCyclingPower) "Standard power service: present. " else "Standard power service (0x1818): MISSING. ")
            append(if (snap1.hasCsc) "Standard cadence service: present. " else "Standard cadence service (0x1816): MISSING. ")
            if (snap1.hasMeshProxy) append("XDS private service 0x1828: present" + (if (snap1.meshProxyHas2A63) " with data channel 0x2A63." else " WITHOUT the usual data channel 0x2A63."))
        }
        step(4, if (std) "ok" else "warn", detail)
        tested += "Bluetooth services: " + detail.trim()
        val subscribed = snap1.services.flatMap { it.characteristics }.count { it.notifying }
        tested += "Subscribed to $subscribed data channels (all that the sensor offers)"

        // 5. Still
        step(5, "running"); headline("Listening while the bike is still", "KEEP THE BIKE COMPLETELY STILL")
        var seq = lastSeq()
        countdown(STILL_SECONDS, "KEEP THE BIKE COMPLETELY STILL")
        val stillResult = collect(seq, STILL_SECONDS)
        step(5, "ok", "${stillResult.total} messages while still")

        // 6. Pedal
        step(6, "running"); headline("Listening while pedaling", "PEDAL NOW — steady, about 80 rpm")
        seq = lastSeq()
        countdown(PEDAL_SECONDS, "PEDAL NOW — steady, about 80 rpm")
        var pedalResult = collect(seq, PEDAL_SECONDS)
        var snapP = gatt.snapshot.value
        var responsive = respondsToPedaling(stillResult, pedalResult)
        step(6, if (pedalResult.total > 0) "ok" else "fail", "${pedalResult.total} messages while pedaling" + (if (snapP.state != ConnectionState.READY) " (connection dropped!)" else ""))
        tested += "Listened ${STILL_SECONDS} s still (${stillResult.total} messages) and ${PEDAL_SECONDS} s pedaling (${pedalResult.total} messages)"

        // 7. Safe fixes, only if nothing useful arrived
        step(7, "running")
        if (!responsive) {
            // Fix A: documented, reversible — full disconnect/reconnect cycle, then retest while pedaling.
            headline("Trying fix 1 of 2: reconnecting from scratch…")
            gatt.disconnect(silent = true); delay(2500)
            gatt.connect(meter.address, meter.name, reconnect = false)
            if (waitForState(ConnectionState.READY, 30_000)) {
                delay(5000)
                seq = lastSeq()
                countdown(RETEST_SECONDS, "PEDAL NOW — retest after reconnect")
                val r = collect(seq, RETEST_SECONDS)
                log.add(EventType.TEST, note = "Retest after reconnect: ${r.total} notifications")
                if (respondsToPedaling(stillResult, r)) { responsive = true; pedalResult = r; fixed += "A full disconnect/reconnect cycle made the sensor start sending data (verified by a live pedaling retest)." }
                else tested += "Fix 1 (reconnect from scratch): no change"
            } else tested += "Fix 1 (reconnect from scratch): the sensor did not accept the new connection"
            snapP = gatt.snapshot.value
        }
        if (!responsive && snapP.state == ConnectionState.READY && snapP.hasMeshProxy && snapP.meshProxyHas2A55) {
            // Fix B: community-documented 'start' write. Requires explicit approval; harmlessly rejected on at least one unit.
            headline("A possible fix needs your approval")
            val ok = requestApproval(
                "Send the 'start sending data' request?",
                "Some XDS meters only start streaming after the phone sends a short 4-byte request to the sensor's control channel. " +
                "This exact request is used by an open-source Garmin bridge built for XDS meters. It is not from the manufacturer.",
                "Risk: low. On one other XDS unit the sensor simply rejected it (error 0x81) with no side effects. It does not touch calibration, settings or firmware. " +
                "But because it is not manufacturer-documented, its full meaning is unknown. You can decline and nothing is sent.",
            )
            if (ok) {
                seq = lastSeq()
                gatt.experimentalWrite(Uuids.SC_CONTROL_POINT, byteArrayOf(0x02, 0x16, 0xAA.toByte(), 0x10), "github.com/DuoDuoJuZi/xds_forwarding (community)")
                delay(2500)
                countdown(RETEST_SECONDS, "PEDAL NOW — retest after start request")
                val r = collect(seq, RETEST_SECONDS)
                val rejected = log.entries.value.any { it.seq > seq && it.type == EventType.ERROR && it.note.contains("Write") }
                log.add(EventType.TEST, note = "Retest after start request: ${r.total} notifications, rejected=$rejected")
                if (respondsToPedaling(stillResult, r)) { responsive = true; pedalResult = r; fixed += "Sending the 'start' request made the sensor stream data (verified by a live pedaling retest)." }
                else tested += "Fix 2 (community 'start' request): " + (if (rejected) "the sensor rejected it (harmless)" else "accepted but no data followed")
            } else tested += "Fix 2 (community 'start' request): skipped at your request"
        }
        step(7, if (fixed.isNotEmpty()) "ok" else "warn", if (fixed.isNotEmpty()) fixed.joinToString() else "No safe fix changed the result")

        // 8. Verdict
        step(8, "running"); headline("Working out the verdict…")
        val snapF = gatt.snapshot.value
        val verified = snapF.metrics != null       // decoded from a standard SIG service
        val candidate = snapF.candidate != null    // decoded with the community layout
        val summary: String
        when {
            responsive && verified && std -> {
                outcome = if (fixed.isNotEmpty()) Outcome.FIXED else Outcome.WORKING
                summary = "Live power/cadence was decoded from the standard Bluetooth cycling service while you pedaled. The sensor works and speaks the standard language a Garmin understands."
                next += "Pair the sensor again on the Edge 820 (Sensors → Add sensor). If it still fails, the Garmin side needs attention, not the sensor."
            }
            responsive -> {
                outcome = if (fixed.isNotEmpty()) Outcome.FIXED else Outcome.COMPATIBILITY_ISSUE
                summary = "The sensor is alive and sends data that changes when you pedal" + (if (candidate) " (power ≈ ${snapF.candidate!!.totalPowerW} W, cadence ≈ ${snapF.candidate!!.cadenceRpm} rpm using the community decoding)" else "") +
                    ". But it uses XDS's private Bluetooth format, not the standard cycling-power service, and it has no ANT+. " +
                    "A Garmin Edge 820 can only pair with standard Bluetooth power meters or ANT+ ones, so it will never see this sensor no matter what any phone app does."
                next += "Use the official 'X-LAB Bikes' app to see your power, or add a small bridge device (an nRF52840 dongle running an open-source XDS→ANT+ bridge) if you want the Garmin to show it. No Android app can add ANT+ to the Garmin or the sensor."
            }
            pedalResult.total > 0 -> {
                outcome = Outcome.INCONCLUSIVE
                summary = "The sensor sent ${pedalResult.total} messages, but they looked the same whether you pedaled or not, so they may be status messages rather than measurements."
                next += "Run the test again and pedal harder and faster (90+ rpm) during the pedaling phase."
                next += "Check whether the official 'X-LAB Bikes' app shows live power."
            }
            else -> {
                outcome = Outcome.NEEDS_ATTENTION
                summary = "The phone connected, read the battery" + (battery?.let { " ($it %)" } ?: "") + " and subscribed to every channel the sensor offers, but the sensor sent nothing while you pedaled — even after the safe fixes. " +
                    "Its radio works; its measuring side is silent. Either it needs the manufacturer's own app to activate it, or the sensor electronics are faulty."
                next += "Install the official 'X-LAB Bikes' app (Google Play) and check for live power or an activation/firmware prompt. If that app shows power, the sensor is fine and only the private protocol is the obstacle."
                next += "If the official app also shows nothing, contact XDS/Branta support — this is a hardware or firmware fault that no phone app can repair."
            }
        }
        if (outcome != Outcome.WORKING && outcome != Outcome.FIXED && !snapF.hasCyclingPower) {
            tested += "Why the Garmin cannot connect: the sensor does not offer the standard Bluetooth cycling-power service and has no ANT+ transmitter"
        }
        step(8, "ok", outcome.name)
        val report = ReportBuilder.build(snapF, scanner.devices.value.values, GuidedTestState(TestPhase.DONE, 0, stillResult, pedalResult, "auto: $outcome"), log)
        finish(outcome, summary, tested, fixed, next, report)
    }

    private fun finish(outcome: Outcome, summary: String, tested: List<String>, fixed: List<String>, next: List<String>, report: String?) {
        val fullReport = (report ?: "") + "\n\n== PLAIN-LANGUAGE SUMMARY ==\n$outcome\n$summary\n\nTested:\n" +
            tested.joinToString("\n") { "  • $it" } + "\n\nFixed:\n" + (if (fixed.isEmpty()) "  (nothing)" else fixed.joinToString("\n") { "  • $it" }) +
            "\n\nNext:\n" + next.joinToString("\n") { "  • $it" }
        val path = try { saveReport(fullReport) } catch (e: Exception) { "not saved: ${e.message}" }
        log.add(EventType.INFO, note = "AUTO DIAGNOSTIC finished: $outcome; report at $path")
        val text = buildString {
            appendLine(summary); appendLine()
            appendLine("What was tested:"); tested.forEach { appendLine("• $it") }; appendLine()
            appendLine("What was fixed:"); if (fixed.isEmpty()) appendLine("• Nothing needed fixing, or no safe fix changed the result.") else fixed.forEach { appendLine("• $it") }; appendLine()
            appendLine("What to do next:"); next.forEach { appendLine("• $it") }
        }
        _state.update { it.copy(running = false, progress = 1f, headline = "", instruction = "", countdown = 0, outcome = outcome, summary = text, technicalReport = fullReport, reportPath = path) }
    }
}
