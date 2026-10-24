import SwiftUI
import AuthenticationServices

/// Profile tab: rider details, zones, devices (live) vs integrations (cloud), account, settings, about.
struct ProfileTabView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var location: LocationService
    @State private var confirmReset = false
    @State private var ftpText = ""
    @State private var showAccount = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Rider") {
                    TextField("Name", text: $store.profile.name)
                    Picker("Goal", selection: $store.profile.goal) { ForEach(RiderProfile.Goal.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Picker("Level", selection: $store.profile.level) { ForEach(RiderProfile.Level.allCases, id: \.self) { Text($0.title).tag($0) } }.onChange(of: store.profile.level) { _, _ in store.profile.refreshAssumption() }
                    Stepper("Hours per week: \(store.profile.hoursPerWeek) h", value: $store.profile.hoursPerWeek, in: 2...20)
                    HStack { Text("Weight"); Spacer(); Text(String(format: "%.0f kg", store.profile.weightKg)).foregroundStyle(.secondary) }
                    Slider(value: $store.profile.weightKg, in: 40...150, step: 1).onChange(of: store.profile.weightKg) { _, _ in store.profile.refreshAssumption() }
                    Stepper("Age: \(store.profile.age)", value: $store.profile.age, in: 12...90)
                    HStack { Text("Max heart rate"); Spacer(); Text("\(store.profile.estimatedMaxHR) bpm · estimated from age").foregroundStyle(.secondary).font(.footnote) }
                }

                Section {
                    HStack { Text("FTP"); Spacer(); Text("\(store.profile.ftpW) W").bold(); Pill(text: store.profile.ftpHow.label, color: store.profile.ftpHow == .assumed ? BC.stale : BC.live) }
                    HStack {
                        TextField("Tested FTP in watts", text: $ftpText).keyboardType(.numberPad)
                        Button("Set") { if let v = Int(ftpText), v >= 50, v <= 600 { store.profile.ftpW = v; store.profile.ftpHow = .entered; ftpText = "" } }.disabled(Int(ftpText) == nil)
                    }
                    if store.profile.ftpHow != .assumed { Button("Back to the assumption from weight and level") { store.profile.ftpHow = .assumed; store.profile.refreshAssumption() }.font(.footnote) }
                    ZoneBar()
                    ForEach(Array(store.profile.powerZones.enumerated()), id: \.offset) { i, z in
                        HStack { ZonePill(z: i + 1); Text(zoneName(i + 1)).font(.footnote); Spacer(); Text("\(z.lo)–\(z.hi.map(String.init) ?? "∞") W").font(.footnote).monospacedDigit(); Text("· \(hrRange(i + 1))").font(.caption2).foregroundStyle(.secondary) }
                    }
                } header: { Text("Zones") } footer: { Text("Power zones from FTP (Coggan). Heart-rate ranges from your max HR; they apply when a strap or watch provides heart rate.") }

                Section("Devices") {
                    NavigationLink { DevicesView() } label: {
                        DeviceRow(name: "Waveshare BikeComputer", status: boardStatus, live: device.state == .ready, caps: ["LIVE power", "LIVE cadence", "recorder"])
                    }
                    DeviceRow(name: "XDS power meter", status: meterStatus, live: meterLive, caps: ["LIVE via board"])
                    DeviceRow(name: "Apple Watch", status: watchStatus, live: watch.hrIsFresh, caps: ["LIVE HR", "workout"])
                    DeviceRow(name: "Heart-rate strap or band", status: strapLive ? "live via board" : "pair on the BikeComputer (Sensors)", live: strapLive, caps: ["LIVE HR direct to board"])
                    DeviceRow(name: "Phone GPS", status: gpsStatus, live: location.sharing && location.last != nil, caps: ["speed", "distance", "map"])
                }

                Section {
                    DeviceRow(name: "WHOOP", status: "not connected", live: false, caps: ["CLOUD recovery", "HRV", "sleep"])
                    DeviceRow(name: "Garmin Connect", status: "not connected", live: false, caps: ["CLOUD rides", "sleep"])
                    DeviceRow(name: "Apple Health", status: "not connected", live: false, caps: ["CLOUD write rides", "HRV"])
                } header: { Text("Integrations (cloud, not live)") } footer: { Text("Cloud integrations arrive with the account service. They provide morning recovery data, never live heart rate; live heart rate comes only from a watch or strap above. Nothing is shown from them until connected.") }

                Section("Settings") {
                    Picker("Units", selection: $store.settings.units) { ForEach(AppSettings.Units.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Toggle("Phone-only mode", isOn: $store.settings.phoneOnlyMode)
                    Text("On: this phone records every ride, even with a BikeComputer connected (its values are shown, not merged). Off: a connected BikeComputer is the recorder.").font(.footnote).foregroundStyle(.secondary)
                    Picker("Heart-rate preference", selection: $store.settings.hrPref) { ForEach(AppSettings.HRPref.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Toggle("Keep the screen on during a ride", isOn: $store.settings.keepScreenOn)
                }

                Section("Account") {
                    if store.guest {
                        HStack { Text("Guest"); Spacer(); Text("rides stay on this phone").foregroundStyle(.secondary).font(.footnote) }
                        Button("Create account") { showAccount = true }
                    } else {
                        HStack { Text("Signed in with Apple"); Spacer(); Pill(text: "local only · sync coming", color: BC.stale) }
                        Button("Sign out (keeps data on this phone)") { store.guest = true; store.appleUserId = nil }
                    }
                    Button("Delete account and all data on this phone", role: .destructive) { confirmReset = true }
                }

                Section("About") {
                    LabeledContent("Version", value: AppInfo.label)
                    LabeledContent("Protocol", value: device.info.map { "v\($0.verMajor).\($0.verMinor) · board \($0.fw)" } ?? "BikeComputer Link v1")
                    Text("Build 15 is simulator-tested (unit tests in CI). Features marked live are device-tested only after Rashed's checklist; nothing in this build is device-verified yet.").font(.footnote).foregroundStyle(.secondary)
                    Text("Offline by design: no network calls in this build. Health data stays on this phone.").font(.footnote).foregroundStyle(.secondary)
                    if let e = store.lastSaveError { Text("Save problem: \(e)").font(.footnote).foregroundStyle(BC.warn) }
                }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showAccount) { AccountSheet() }
            .alert("Delete everything on this phone?", isPresented: $confirmReset) {
                Button("Delete", role: .destructive) { device.forget(); store.resetAll() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Profile, plan, ride history and the remembered BikeComputer are removed. The board keeps its own data; use Forget phone on the board too.") }
        }
    }

    private var boardStatus: String {
        if device.state == .ready { return "connected" }
        if device.state == .idle { return device.remembered ? "remembered · not connected" : "not paired" }
        return device.state.rawValue
    }
    private var liveNow: BCLink.Live? { device.state == .ready && device.liveIsFresh ? device.live : nil }
    private var meterLive: Bool { liveNow?.meterLink == 4 }
    private var meterStatus: String {
        guard let l = liveNow else { return "via the BikeComputer" }
        return l.meterLink == 4 ? "connected via board" : "board searching"
    }
    private var strapLive: Bool { liveNow?.hrSource == .bleStrap && liveNow?.hrBpm != nil }
    private var watchStatus: String {
        if watch.hrIsFresh { return "heart rate live" }
        if watch.appInstalled { return "app installed · start the workout on the watch" }
        return watch.paired ? "watch paired · app not installed" : "no watch"
    }
    private var gpsStatus: String {
        guard location.authorized else { return "permission needed" }
        return location.sharing ? location.status : "ready"
    }
    private func zoneName(_ z: Int) -> String { ["Recovery", "Endurance", "Tempo", "Threshold", "VO2 max", "Anaerobic", "Neuromuscular"][z - 1] }
    private func hrRange(_ z: Int) -> String { let m = Double(store.profile.estimatedMaxHR); let b: [(Double, Double)] = [(0.5, 0.6), (0.6, 0.75), (0.75, 0.85), (0.85, 0.9), (0.9, 1.0), (0.9, 1.0), (0.9, 1.0)]; return "\(Int(m * b[z - 1].0))–\(Int(m * b[z - 1].1)) bpm" }
}

struct DeviceRow: View {
    let name: String; let status: String; let live: Bool; let caps: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { StatusDot(color: live ? BC.live : .secondary); Text(name).font(.subheadline.weight(.semibold)); Spacer(); Text(status).font(.caption).foregroundStyle(live ? BC.live : .secondary).multilineTextAlignment(.trailing) }
            HStack(spacing: 4) { ForEach(caps, id: \.self) { c in Pill(text: c, color: c.hasPrefix("LIVE") ? BC.live : c.hasPrefix("CLOUD") ? BC.accent : .secondary) } }
        }.padding(.vertical, 2)
    }
}

/// Account creation. Apple sign-in works now and only identifies the rider on this phone (no server yet).
/// Google and e-mail arrive with the sync service; Apple requires Sign in with Apple when Google is offered.
struct AccountSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("Create an account").font(.system(size: 28, weight: .bold, design: .rounded))
                Text("Your rides and plan are on this phone. An account lets them follow you to a new phone or Android once the sync service is live; until then Sign in with Apple only identifies you here.").foregroundStyle(.secondary)
                SignInWithAppleButton(.signUp) { r in r.requestedScopes = [.fullName] } onCompletion: { result in
                    switch result {
                    case .success(let a): if let c = a.credential as? ASAuthorizationAppleIDCredential { store.appleUserId = c.user; store.guest = false; if let n = c.fullName?.givenName, !n.isEmpty, store.profile.name.isEmpty { store.profile.name = n }; dismiss() }
                    case .failure(let e): error = e.localizedDescription
                    }
                }.signInWithAppleButtonStyle(.black).frame(height: 50).clipShape(RoundedRectangle(cornerRadius: 14))
                Button { } label: { Text("Sign in with Google · coming with the sync service").frame(maxWidth: .infinity) }.buttonStyle(.bordered).disabled(true)
                Button { } label: { Text("Continue with e-mail · coming with the sync service").frame(maxWidth: .infinity) }.buttonStyle(.bordered).disabled(true)
                if let e = error { Text(e).font(.footnote).foregroundStyle(BC.warn) }
                Spacer()
            }.padding()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Not now") { dismiss() } } }
        }
    }
}
