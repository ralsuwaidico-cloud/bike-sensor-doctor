import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable

/// The ONE short status line at the top of the Ride and Connections screens (PipelineMonitor.top). Hidden when every
/// set-up source is live or idle.
struct PipelineBanner: View {
    @ObservedObject var monitor: PipelineMonitor
    var dark = false
    var body: some View {
        if let t = monitor.top {
            HStack(spacing: 6) {
                Image(systemName: icon(t.health)).font(.system(size: 11, weight: .bold))
                Text(t.message).font(.system(size: dark ? 11 : 13, weight: .semibold)).lineLimit(2).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .foregroundStyle(color(t.health))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(color(t.health).opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("pipelineBanner")
        }
    }
    private func icon(_ h: PipelineHealth) -> String {
        switch h { case .recovering: return "arrow.triangle.2.circlepath"; case .waiting: return "hourglass"; case .stale: return "clock.badge.exclamationmark"; default: return "exclamationmark.triangle.fill" }
    }
    private func color(_ h: PipelineHealth) -> Color {
        switch h { case .failed, .noData: return BC.warn; case .stale, .waiting, .recovering: return BC.stale; default: return BC.live }
    }
}

/// Lazily built export so the report reflects the moment the rider taps Share.
struct DiagnosticFile: Transferable {
    let make: () -> Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.make() }
            .suggestedFileName("cyclift-diagnostics.json")
    }
}

/// Connections › Diagnostics: every path stage by stage, the board's SENSOR_DIAG, recent events, export.
struct PipelineDiagnosticsView: View {
    @EnvironmentObject private var monitor: PipelineMonitor
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    var body: some View {
        List {
            Section {
                if let t = monitor.top { Text(t.message).font(.subheadline.weight(.semibold)).foregroundStyle(t.health >= .noData ? BC.warn : BC.stale) }
                else { Text("Every source that is set up is live or ready.").font(.subheadline).foregroundStyle(BC.live) }
                if let r = monitor.lastRun { Text("Last check: \(r.trigger), \(r.at.formatted(date: .omitted, time: .standard)) · runs every second and recovers automatically").font(.caption2).foregroundStyle(.secondary) }
                Button("Run diagnostics now") { monitor.tick(); monitor.log("trigger", "Diagnostics run: manual — " + (monitor.top?.message ?? "all set-up sources live or idle")) }
                ShareLink(item: DiagnosticFile(make: { [m = monitor] in m.reportJSON() }), preview: SharePreview("Cyclift diagnostic report")) {
                    Label("Export diagnostic report", systemImage: "square.and.arrow.up")
                }
            } header: { Text("Now") } footer: {
                Text("The report contains versions, connection stages, Bluetooth services and counters, the last 50 events and the board's sensor reports — no names, e-mail addresses, locations or health history.")
            }
            ForEach(monitor.reports.filter { $0.health != .notSetUp }) { r in
                Section {
                    HStack { Text(r.health.title.capitalized).font(.subheadline.weight(.semibold)); Spacer(); if !r.message.isEmpty { Text(r.message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing) } }
                    ForEach(r.stages, id: \.stage) { s in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: symbol(s.result)).foregroundStyle(tint(s.result)).frame(width: 18)
                            Text(s.stage.title).font(.footnote)
                            Spacer()
                            Text(s.detail.isEmpty ? s.result.rawValue : s.detail).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
                        }
                    }
                    if let n = r.note { Text(n).font(.caption2).foregroundStyle(BC.stale) }
                } header: { Text(r.title) }
            }
            if watch.paired && watch.appInstalled {
                Section("Apple Watch app") {
                    LabeledContent("iPhone app", value: AppInfo.label)
                    LabeledContent("Watch app", value: watch.watchBuild ?? "not reported yet")
                    if watch.version == .watchOlder {
                        Text(WatchVersion.updateInstruction).font(.footnote).foregroundStyle(BC.stale)
                        Text("TestFlight updates the watch app by itself only when Automatic App Install is on (Watch app on iPhone › General). Otherwise install the update there by hand.").font(.caption2).foregroundStyle(.secondary)
                    }
                    LabeledContent("Live channel", value: watch.mirror.active ? "workout mirroring" : watch.reachable ? "Watch Connectivity" : "none")
                    LabeledContent("Readings accepted", value: "\(watch.ingest.accepted[.mirror] ?? 0) mirrored · \(watch.ingest.accepted[.connectivity] ?? 0) messages · \(watch.ingest.duplicates) duplicates · \(watch.ingest.dropped) dropped")
                    if let a = watch.watchWorkoutAuth { LabeledContent("Health permission (watch)", value: a) }
                }
            }
            if !device.sensorDiag.isEmpty {
                Section("Board sensor reports (SENSOR_DIAG)") {
                    ForEach(device.sensorDiag.keys.sorted(), id: \.self) { k in
                        if let d = device.sensorDiag[k] {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(d.sensor?.title ?? "Sensor \(k)"): \(d.stage?.words ?? "stage \(d.stageRaw)")").font(.footnote.weight(.semibold))
                                Text("packets \(d.packets.map { "\($0)" } ?? "–") · rejected \(d.rejected.map { "\($0)" } ?? "–") · last packet \(d.packetAgeS.map { String(format: "%.1f s", $0) } ?? "none") · last valid \(d.validAgeS.map { String(format: "%.1f s", $0) } ?? "none")" + (d.lastError.map { " · \($0)" } ?? "")).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else if device.state == .ready {
                Section("Board sensor reports") {
                    Text(BoardInputs.version(device.info?.fw, atLeast: [0, 7, 2]) ? "Waiting for the board's sensor report." : "Board firmware too old for detailed diagnostics (needs 0.7.2; the board has \(device.info?.fw ?? "?")). Stages are derived from the live data instead.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Recent events (last 50)") {
                if monitor.events.isEmpty { Text("Nothing yet").foregroundStyle(.secondary) }
                ForEach(monitor.events.reversed()) { e in
                    HStack(alignment: .top) {
                        Text(e.at.formatted(date: .omitted, time: .standard)).font(.caption2).monospacedDigit().foregroundStyle(.secondary).frame(width: 68, alignment: .leading)
                        Text(e.text).font(.caption)
                    }
                }
            }
        }
        .navigationTitle("Diagnostics").navigationBarTitleDisplayMode(.inline)
    }
    private func symbol(_ r: StageResult) -> String {
        switch r { case .ok: return "checkmark.circle.fill"; case .failed: return "xmark.octagon.fill"; case .pending: return "circle.dotted"; case .notApplicable: return "minus.circle"; case .unknown: return "questionmark.circle" }
    }
    private func tint(_ r: StageResult) -> Color {
        switch r { case .ok: return BC.live; case .failed: return BC.warn; case .pending: return BC.stale; default: return .secondary }
    }
}
