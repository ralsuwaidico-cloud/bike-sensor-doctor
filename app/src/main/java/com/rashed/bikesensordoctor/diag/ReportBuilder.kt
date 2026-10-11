package com.rashed.bikesensordoctor.diag

import com.rashed.bikesensordoctor.ble.ConnectionState
import com.rashed.bikesensordoctor.ble.DeviceSnapshot
import com.rashed.bikesensordoctor.ble.ScannedDevice
import com.rashed.bikesensordoctor.ble.Uuids
import com.rashed.bikesensordoctor.log.EventLog
import com.rashed.bikesensordoctor.log.EventType
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Builds a plain-text diagnostic report from what was actually observed. Every statement is derived from
 * logged events; nothing is assumed. Sections: Confirmed findings / Likely causes / Unresolved questions.
 */
object ReportBuilder {

    fun build(snapshot: DeviceSnapshot, scanned: Collection<ScannedDevice>, test: GuidedTestState, log: EventLog): String {
        val sb = StringBuilder()
        val now = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())
        val entries = log.entries.value
        val notifyTotal = entries.count { it.type == EventType.NOTIFY }
        val errors = entries.filter { it.type == EventType.ERROR }
        val confirmed = ArrayList<String>()
        val likely = ArrayList<String>()
        val open = ArrayList<String>()

        sb.appendLine("BIKE SENSOR DOCTOR — DIAGNOSTIC REPORT").appendLine("Generated: $now").appendLine()

        // ---- Scan ----
        sb.appendLine("== SCAN ==")
        if (scanned.isEmpty()) {
            sb.appendLine("No devices were seen in the scan.")
            open += "No BLE advertisements were received. Was Bluetooth on and location/nearby-devices permission granted?"
        } else {
            sb.appendLine("${scanned.size} device(s) seen. XDS-like candidates:")
            val xds = scanned.filter { it.looksLikeXds }
            if (xds.isEmpty()) {
                sb.appendLine("  (none matched name 'XDS*', MAC C0:A1:25*, or service 0x1828)")
                open += "The XDS-A001 device did not advertise during this session. Is the sensor awake (rotate the crank) and within ~2 m?"
            }
            for (d in xds) {
                sb.appendLine("  ${d.displayName} ${d.address} rssi avg ${"%.0f".format(d.rssiAvg)} dBm (${d.seenCount} adverts) services=${d.serviceUuids.joinToString { Uuids.short(it) }}")
                confirmed += "Device ${d.displayName} (${d.address}) is advertising; average RSSI ${"%.0f".format(d.rssiAvg)} dBm."
                if (!d.advertisesCyclingService) confirmed += "${d.displayName} does NOT advertise 0x1818 or 0x1816 — a Garmin Edge filtering on those services cannot find it."
                if (d.serviceUuids.contains(Uuids.MESH_PROXY)) confirmed += "${d.displayName} advertises 0x1828, matching the pattern community XDS bridges filter on."
            }
            val cycling = scanned.filter { it.advertisesCyclingService }
            if (cycling.isNotEmpty()) sb.appendLine("Devices advertising standard cycling services: " + cycling.joinToString { "${it.displayName} ${it.address}" })
        }
        sb.appendLine()

        // ---- Connection & GATT ----
        sb.appendLine("== CONNECTION ==")
        if (snapshot.address.isEmpty()) {
            sb.appendLine("No connection attempted.")
        } else {
            sb.appendLine("Target: ${snapshot.name} ${snapshot.address}")
            sb.appendLine("State: ${snapshot.state}, attempts=${snapshot.connectAttempts}, disconnects=${snapshot.disconnects}, MTU=${snapshot.mtu}, RSSI=${snapshot.rssi ?: "n/a"}")
            if (snapshot.batteryPct != null) { sb.appendLine("Battery: ${snapshot.batteryPct} %"); confirmed += "Battery service reports ${snapshot.batteryPct} % — the sensor's radio and firmware are alive." }
            if (snapshot.deviceInfo.isNotEmpty()) {
                sb.appendLine("Device Information:")
                snapshot.deviceInfo.forEach { (k, v) -> sb.appendLine("  $k: $v") }
            }
            if (snapshot.services.isNotEmpty()) {
                confirmed += "GATT connection and service discovery succeed (${snapshot.services.size} services)."
                sb.appendLine("Services:")
                for (s in snapshot.services) {
                    sb.appendLine("  ${Uuids.short(s.uuid)} ${Uuids.name(s.uuid)}")
                    for (c in s.characteristics) sb.appendLine("     ${Uuids.short(c.uuid)} [${c.propText}] ${Uuids.name(c.uuid)}${c.lastValueHex?.let { " = $it" } ?: ""}${if (c.notifying) " (subscribed)" else ""}")
                }
                if (snapshot.hasCyclingPower) confirmed += "Standard Cycling Power service 0x1818 IS present."
                else confirmed += "Standard Cycling Power service 0x1818 is ABSENT."
                if (snapshot.hasCsc) confirmed += "Standard CSC service 0x1816 IS present." else confirmed += "Standard CSC service 0x1816 is ABSENT."
                if (snapshot.hasMeshProxy) {
                    confirmed += "Service 0x1828 present" + (if (snapshot.meshProxyHas2A63) " and contains 0x2A63 (matches the layout used by community XDS bridges)." else " but does NOT contain 0x2A63 (differs from the layout community XDS bridges rely on).")
                    if (!snapshot.meshProxyHas2A63) open += "0x1828 lacks 0x2A63: this firmware (\"${snapshot.deviceInfo["Firmware Revision"] ?: "1.0"}\") may differ from the units the open-source bridges were built against."
                }
                if (snapshot.hasXdsCustom) open += "Custom services a6ed0401/a6ed0201 are present; no public documentation of them was found. Their role (OTA? config? auth?) is unknown."
            } else if (snapshot.state != ConnectionState.DISCONNECTED) {
                open += "Connected but no services discovered yet."
            }
        }
        sb.appendLine()

        // ---- Data ----
        sb.appendLine("== DATA ==")
        sb.appendLine("Total notifications received this session: $notifyTotal")
        log.notifyCounts.value.forEach { (u, n) -> sb.appendLine("  $n × ${runCatching { Uuids.short(java.util.UUID.fromString(u)) }.getOrDefault(u)}") }
        snapshot.metrics?.let { m ->
            sb.appendLine("Verified metrics (${m.source}): power=${m.instantaneousPowerW} W cadence=${m.derivedCadenceRpm?.let { "%.1f".format(it) } ?: "n/a"} crankRevs=${m.cumulativeCrankRevs}")
            confirmed += "Standard cycling measurements WERE decoded from a SIG service."
        }
        snapshot.candidate?.let { c ->
            sb.appendLine("CANDIDATE (unverified community layout): power=${c.totalPowerW} W L/R=${c.leftPowerW}/${c.rightPowerW} cadence=${c.cadenceRpm} angle=${c.crankAngleDeg} err=${c.errorCode}")
            likely += "Data on 0x2A63 under 0x1828 decoded with the community layout; verify by pedaling at a known cadence and comparing."
        }
        if (snapshot.services.isNotEmpty() && notifyTotal == 0) {
            confirmed += "Subscribing to every notify/indicate characteristic produced ZERO notifications."
            likely += "The sensor is waiting for a manufacturer-specific start/handshake from the X-LAB app (community bridges show one unit needed a write to 0x2A55 and another streamed without it)."
            likely += "The sensor may be asleep until crank rotation is detected — repeat the test while pedaling continuously."
            likely += "If battery/DIS reads work but measurement never flows, the strain-gauge/MCU side may be faulty while the BLE radio is fine."
        }
        sb.appendLine()

        // ---- Guided test ----
        sb.appendLine("== GUIDED TEST ==")
        if (test.phase == TestPhase.DONE && test.stationary != null && test.pedaling != null) {
            sb.appendLine("Stationary: ${test.stationary.total} notifications; Pedaling: ${test.pedaling.total} notifications")
            sb.appendLine("Verdict: ${test.verdict}")
            confirmed += "Guided test: ${test.verdict}"
        } else sb.appendLine("Not run.")
        sb.appendLine()

        // ---- Errors ----
        sb.appendLine("== ERRORS (${errors.size}) ==")
        errors.takeLast(15).forEach { sb.appendLine("  ${it.timeText} ${it.note}") }
        if (errors.any { it.note.contains("INSUFFICIENT") }) likely += "The device requested authentication/encryption on some attribute — pairing (bonding) in Android Bluetooth settings may be required before data flows."
        if (errors.any { it.note.contains("133") }) likely += "Error 133 seen: Android stack flakiness; toggle Bluetooth, reboot phone, or move closer."
        sb.appendLine()

        // ---- Summary ----
        sb.appendLine("== CONFIRMED FINDINGS ==")
        if (confirmed.isEmpty()) sb.appendLine("  (nothing confirmed yet)") else confirmed.forEach { sb.appendLine("  • $it") }
        sb.appendLine()
        sb.appendLine("== LIKELY CAUSES ==")
        if (likely.isEmpty()) sb.appendLine("  (none proposed — insufficient evidence)") else likely.forEach { sb.appendLine("  • $it") }
        sb.appendLine()
        sb.appendLine("== UNRESOLVED QUESTIONS ==")
        open += "Does the official X-LAB Bikes app (com.xds.ebike.intl) show live power on this phone? If yes, the sensor works and the problem is purely protocol/compatibility."
        open += "Is there a firmware option in the X-LAB app to broadcast standard Bluetooth Cycling Power / ANT+? None was documented publicly."
        open.forEach { sb.appendLine("  • $it") }
        sb.appendLine()
        sb.appendLine("Safety: this app only reads, subscribes (reversible CCCD writes) and reconnects. It never flashes, resets, calibrates or writes to unknown characteristics.")
        return sb.toString()
    }
}
