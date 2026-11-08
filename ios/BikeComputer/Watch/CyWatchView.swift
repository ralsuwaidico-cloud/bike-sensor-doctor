import SwiftUI

// Connections › Cyclift Watch (LILYGO): the companion link's real state, battery, last frame and the event log.
// Nothing here claims a connection that the radio has not made; "hardware-tested" is a tracker state, not a label here.
struct CyWatchCard: View {
    @EnvironmentObject private var cw: CyWatchCoordinator
    @EnvironmentObject private var store: Store
    var body: some View {
        NavigationLink { CyWatchPage() } label: {
            HStack(spacing: 12) {
                Image(systemName: "applewatch.radiowaves.left.and.right").font(.title3).foregroundStyle(CyTheme.ink2).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cyclift Watch").font(CyType.body).foregroundStyle(CyTheme.ink)
                    Text(subtitle).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3)
                }
                Spacer(); Image(systemName: "chevron.right").foregroundStyle(CyTheme.ink3)
            }
            .padding(14).frame(minHeight: 56).cyCard()
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("connectionsCyWatch")
    }
    private var subtitle: String {
        guard store.settings.cyWatchEnabled else { return "Off · the LILYGO watch link is not enabled" }
        switch cw.link.state {
        case .off: return "Starting…"
        case .bluetoothOff: return "Bluetooth is off"
        case .scanning: return "Searching for the watch…"
        case .connecting: return "Connecting…"
        case .connected(let n): return "Connected · \(n)" + (cw.link.status.map { " · battery \($0.batteryPct) %" } ?? "")
        case .failed(let r): return "Not connected · \(r)"
        }
    }
}

struct CyWatchPage: View {
    @EnvironmentObject private var cw: CyWatchCoordinator
    @EnvironmentObject private var store: Store
    var body: some View {
        List {
            Section {
                Toggle("Connect to Cyclift Watch", isOn: Binding(get: { store.settings.cyWatchEnabled }, set: { on in store.settings.cyWatchEnabled = on; on ? cw.link.start() : cw.link.stop() }))
                    .accessibilityIdentifier("cyWatchToggle")
                Text("The ESP32 Cyclift Watch mirrors this phone's live values, GPS, today's session and the recovery summary over Bluetooth, and sends back what you log on the wrist. This phone stays the recorder.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Status") {
                LabeledContent("Link", value: stateText)
                if let s = cw.link.status {
                    LabeledContent("Battery", value: "\(s.batteryPct) %" + (s.charging ? " · charging" : ""))
                    LabeledContent("Unsent events on the watch", value: "\(s.pendingEvents)")
                    LabeledContent("Watch free memory", value: "\(s.freeHeap / 1024) KB")
                    LabeledContent("Reported", value: SourceFormat.ago(s.at))
                }
                LabeledContent("Last frame", value: SourceFormat.ago(cw.link.lastFrameAt))
                if cw.link.droppedFrames > 0 { LabeledContent("Frames rejected (CRC / version)", value: "\(cw.link.droppedFrames)").foregroundStyle(BC.warn) }
            }
            Section("Protocol") {
                LabeledContent("Version", value: "\(CyWatchWire.protocolVersion)")
                Text("Service \(CyWatchWire.serviceUUID.prefix(8))… · absent values are sent as absent, never as zero · events carry (device, sequence) and are acknowledged cumulatively, so a reconnect never duplicates a logged set.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Events from the watch") {
                if cw.log.isEmpty { Text("None yet.").font(.footnote).foregroundStyle(.secondary) }
                ForEach(Array(cw.log.reversed().enumerated()), id: \.offset) { _, l in Text(l).font(.caption.monospacedDigit()) }
            }
        }
        .navigationTitle("Cyclift Watch").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("cyWatchPage")
    }
    private var stateText: String {
        guard store.settings.cyWatchEnabled else { return "off" }
        switch cw.link.state {
        case .off: return "starting"; case .bluetoothOff: return "Bluetooth off"; case .scanning: return "searching"; case .connecting: return "connecting"
        case .connected(let n): return "connected · \(n)"; case .failed(let r): return "failed · \(r)"
        }
    }
}
