import SwiftUI

/// Build 11: a functional test app — Ride (live values from the board + controls) and Devices (Waveshare, GPS, Watch).
/// The final five-tab product design follows the clickable prototype review.
struct RootView: View {
    var body: some View {
        TabView {
            RideView().tabItem { Label("Ride", systemImage: "bicycle") }
            DevicesView().tabItem { Label("Devices", systemImage: "antenna.radiowaves.left.and.right") }
        }
    }
}

// MARK: - Ride
struct RideView: View {
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var location: LocationService
    @State private var confirmStop = false
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var live: BCLink.Live? { device.liveIsFresh ? device.live : nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    statusBanner
                    if let l = live, l.demo {
                        Text("DEMO MODE — simulated values on the Waveshare").font(.caption.bold()).foregroundStyle(.black)
                            .padding(6).frame(maxWidth: .infinity).background(.orange, in: RoundedRectangle(cornerRadius: 8))
                    }
                    HStack(spacing: 12) {
                        Metric(title: "POWER", value: live?.powerW.map { "\($0)" }, unit: "W", source: live?.powerW != nil ? "XDS" : nil, big: true)
                        Metric(title: "CADENCE", value: live?.cadenceRpm.map { "\($0)" }, unit: "rpm", source: live?.cadenceRpm != nil ? "XDS" : nil)
                    }
                    HStack(spacing: 12) {
                        Metric(title: "HEART RATE", value: live?.hrBpm.map { "\($0)" }, unit: "bpm", source: live?.hrBpm != nil ? live?.hrSource.label : nil)
                        Metric(title: "SPEED", value: speedText, unit: "km/h", source: speedText != nil ? "Phone GPS" : nil)
                    }
                    HStack(spacing: 12) {
                        Metric(title: "TIME", value: live.map { duration($0.elapsedS) }, unit: "", source: live != nil ? "Waveshare" : nil)
                        Metric(title: "DISTANCE", value: live.map { String(format: "%.2f", Double($0.distanceM) / 1000) }, unit: "km", source: live != nil ? "Waveshare" : nil)
                    }
                    controls
                    if let r = device.lastControl {
                        Text("Board answered: \(controlText(r))").font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("Values come from the Waveshare once a second. \"--\" means the board has no current value; nothing is estimated here.")
                        .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 4)
                }
                .padding()
            }
            .navigationTitle("Ride")
            .onReceive(timer) { tick = $0 }
            .alert("End the ride on the Waveshare?", isPresented: $confirmStop) {
                Button("End ride", role: .destructive) { device.control(.stopConfirm) }
                Button("Keep riding", role: .cancel) {}
            } message: { Text("The board will show the results screen; you save or discard the ride there or here.") }
        }
    }

    private var speedText: String? {
        guard location.sharing, let l = location.last, l.speed >= 0, Date().timeIntervalSince(l.timestamp) < 5 else { return nil }
        return String(format: "%.1f", l.speed * 3.6)
    }

    private var statusBanner: some View {
        HStack {
            Circle().fill(device.state == .ready ? .green : .orange).frame(width: 10, height: 10)
            Text(device.state == .ready ? "Waveshare connected" : device.state.rawValue).font(.subheadline)
            Spacer()
            if device.state == .ready, !device.liveIsFresh { Text("no live data").font(.caption).foregroundStyle(.orange) }
        }
        .padding(10).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private var controls: some View {
        let st = live?.rideState ?? .idle
        HStack(spacing: 12) {
            switch st {
            case .idle, .ended:
                Button { device.control(.start) } label: { Label("Start ride", systemImage: "play.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).tint(.green).disabled(device.state != .ready)
            case .running:
                Button { device.control(.pause) } label: { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                Button { device.control(.stopRequest); confirmStop = true } label: { Label("End", systemImage: "stop.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(.red)
            case .paused:
                Button { device.control(.resume) } label: { Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(.green)
                Button { device.control(.stopRequest); confirmStop = true } label: { Label("End", systemImage: "stop.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(.red)
            }
        }
    }

    private func duration(_ s: Int) -> String { s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60) }

    private func controlText(_ r: BCLink.ControlResponse) -> String {
        switch r.status {
        case .ok: return "OK (ride \(r.rideState))"
        case .needsConfirm: return "waiting for confirmation"
        case .badState: return "not possible in the current state"
        case .wrongRide: return "that ride is no longer active"
        case .unknown: return "unknown command"
        }
    }
}

private struct Metric: View {
    let title: String; let value: String?; let unit: String; let source: String?; var big = false
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2.bold()).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value ?? "--").font(.system(size: big ? 44 : 32, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(value == nil ? .secondary : .primary)
                Text(unit).font(.caption).foregroundStyle(.secondary)
            }
            Text(source ?? "no data").font(.caption2).foregroundStyle(source == nil ? .orange : .green)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Devices
struct DevicesView: View {
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var location: LocationService

    var body: some View {
        NavigationStack {
            List {
                Section("Waveshare cycling computer") {
                    LabeledContent("Status", value: device.state.rawValue)
                    if let i = device.info { LabeledContent("Firmware", value: i.fw); LabeledContent("Protocol", value: "v\(i.verMajor).\(i.verMinor)") }
                    if let r = device.rssi { LabeledContent("Signal", value: "\(r) dBm") }
                    if let l = device.live, device.liveIsFresh {
                        LabeledContent("Board battery", value: l.batteryPct.map { "\($0)%" } ?? "unknown")
                        LabeledContent("Power meter", value: meterText(l.meterLink) + (l.meterGaps > 0 ? " · \(l.meterGaps) gaps" : ""))
                    }
                    if device.state == .pairing {
                        Text("Look at the round screen: it shows a 6-digit code. Type it into the iPhone dialog. This happens once; afterwards the phone is remembered.")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if device.state == .scanning {
                        if device.found.isEmpty { Text("Searching for a BikeComputer nearby… (its Settings > Phone must say WAITING FOR PHONE)").font(.footnote).foregroundStyle(.secondary) }
                        ForEach(device.found, id: \.id) { f in
                            Button { device.connect(to: f.id) } label: { HStack { Text(f.name); Spacer(); Text("\(f.rssi) dBm").foregroundStyle(.secondary) } }
                        }
                    }
                    HStack {
                        if device.state == .ready || device.state == .connecting || device.state == .pairing {
                            Button("Disconnect") { device.disconnect() }
                        } else {
                            Button(device.remembered ? "Connect" : "Find my Waveshare") { device.connect() }
                        }
                        Spacer()
                        if device.remembered { Button("Forget", role: .destructive) { device.forget() } }
                    }
                    if let e = device.lastError { Text(e).font(.footnote).foregroundStyle(.red) }
                    Text("Sent: \(device.stats.sentGPS) GPS · \(device.stats.sentHR) HR · \(device.stats.sentTime) time   Received: \(device.stats.liveMsgs) live · \(device.stats.rejected) rejected · \(device.stats.disconnects) drops")
                        .font(.caption2).foregroundStyle(.secondary)
                }

                Section("Phone GPS → Waveshare") {
                    Toggle("Share GPS with the Waveshare", isOn: $location.sharing)
                    LabeledContent("Status", value: location.status)
                    LabeledContent("Fixes sent", value: "\(location.sent)")
                    Text("The board turns speed into distance itself and shows \"PHONE GPS\" as the source.").font(.footnote).foregroundStyle(.secondary)
                }

                Section("Apple Watch → heart rate") {
                    StatusRow(title: "Watch paired", ok: watch.paired)
                    StatusRow(title: "Watch app installed", ok: watch.appInstalled)
                    StatusRow(title: "Watch app reachable now", ok: watch.reachable)
                    LabeledContent("Workout on the watch", value: watch.workoutState)
                    LabeledContent("Live heart rate", value: watch.hrIsFresh ? "\(watch.hrBpm ?? 0) bpm (Apple Watch)" : "--")
                    LabeledContent("Readings forwarded", value: "\(watch.hrReceived)")
                    if let b = watch.watchBattery { LabeledContent("Watch battery", value: "\(b)%") }
                    Button("Test connection to Watch") { watch.ping() }
                    Text(watch.lastResult).font(.footnote).foregroundStyle(.secondary)
                    Text("Start the workout in the BikeComputer app on the watch. Heart rate reaches the board labelled WATCH; a reading older than 6 s is dropped, never held.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section { Text("Companion app · test build \(AppInfo.label)").font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Devices")
        }
    }

    private func meterText(_ s: Int) -> String {
        switch s { case 4: return "connected"; case 1: return "not paired"; case 2: return "searching"; case 3: return "connecting"; case 5: return "reconnecting"; default: return "off" }
    }
}

struct StatusRow: View {
    let title: String
    let ok: Bool
    var body: some View {
        HStack {
            Text(title); Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle").foregroundStyle(ok ? .green : .secondary).accessibilityLabel(ok ? "Yes" : "No")
        }
    }
}
