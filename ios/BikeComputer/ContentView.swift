import SwiftUI

/// Build 17 (0.3.0): the five-tab app from Prototype v3. First run shows the onboarding; afterwards Home / Plan / Ride /
/// Progress / Profile. The Devices screen from build 14 lives under Profile › Devices unchanged.
struct RootView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var recorder: RideRecorder
    @State private var tab = 0
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if store.onboarded { tabs } else { OnboardingView() }
        }
        .onReceive(timer) { _ in tickRecorder() }
        .onChange(of: recorder.state) { _, s in idleTimer(s) }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            HomeView(tab: $tab).tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            PlanView().tabItem { Label("Plan", systemImage: "calendar") }.tag(1)
            RideTabView().tabItem { Label("Ride", systemImage: "bicycle") }.tag(2)
            ProgressTabView().tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }.tag(3)
            ProfileTabView().tabItem { Label("Profile", systemImage: "person.crop.circle") }.tag(4)
        }
        .tint(BC.accent)
    }

    private func tickRecorder() {
        recorder.phoneOnlyMode = store.settings.phoneOnlyMode
        recorder.tick()
    }

    private func idleTimer(_ s: RideRecorder.State) {
        let active = s == .running || s == .paused
        UIApplication.shared.isIdleTimerDisabled = store.settings.keepScreenOn && active
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
                Section("Waveshare BikeComputer") {
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
