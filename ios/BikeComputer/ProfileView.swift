import SwiftUI
import AuthenticationServices

/// Profile tab: rider details, zones, devices (live) vs integrations (cloud), account, settings, about.
struct ProfileTabView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var sync: ProfileSync
    @State private var confirmReset = false
    @State private var birthText = ""
    @State private var maxHRText = ""
    @State private var restHRText = ""
    @State private var lthrText = ""
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
                    HStack { Text("Birth year"); Spacer(); TextField("not set", text: $birthText).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                        .onAppear { birthText = store.profile.birthYear.map(String.init) ?? "" }
                        .onChange(of: birthText) { _, v in let y = Int(v); let ok = (y ?? 0) >= 1900 && (y ?? 0) <= Calendar.current.component(.year, from: Date()); if store.profile.birthYear != (ok ? y : nil) { store.profile.birthYear = ok ? y : nil } } }
                    HStack { Text("Max heart rate"); Spacer(); TextField("\(store.profile.estimatedMaxHR) (estimate)", text: $maxHRText).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 110)
                        .onAppear { maxHRText = store.profile.maxHR.map(String.init) ?? "" }
                        .onChange(of: maxHRText) { _, v in let n = Int(v); let ok = (n ?? 0) >= 100 && (n ?? 0) <= 230; if store.profile.maxHR != (ok ? n : nil) { store.profile.maxHR = ok ? n : nil } } }
                    HStack { Text("Resting heart rate"); Spacer(); TextField("not set", text: $restHRText).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                        .onAppear { restHRText = store.profile.restHR.map(String.init) ?? "" }
                        .onChange(of: restHRText) { _, v in let n = Int(v); let ok = (n ?? 0) >= 25 && (n ?? 0) <= 120; if store.profile.restHR != (ok ? n : nil) { store.profile.restHR = ok ? n : nil } } }
                    HStack { Text("Threshold heart rate (LTHR)"); Spacer(); TextField("not set", text: $lthrText).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 90)
                        .onAppear { lthrText = store.profile.lthr.map(String.init) ?? "" }
                        .onChange(of: lthrText) { _, v in let n = Int(v); let ok = (n ?? 0) >= 80 && (n ?? 0) <= 220; if store.profile.lthr != (ok ? n : nil) { store.profile.lthr = ok ? n : nil } } }
                    Text(store.profile.maxHR == nil ? "Max heart rate is an estimate from age (\(store.profile.birthYear == nil ? "age not set, 35 assumed" : "born \(store.profile.birthYear!)")) until you enter it." : "Max heart rate entered by you.").font(.footnote).foregroundStyle(.secondary)
                    NavigationLink("Sports and activities (\(store.profile.sports.count))") { SportsPicker() }
                    Text("Profile version \(store.profile.version) · changes sync to the BikeComputer automatically once confirmed (Sync status).").font(.caption2).foregroundStyle(.secondary)
                }

                Section {
                    HStack { Text("FTP"); Spacer(); Text("\(store.profile.ftpW) W").bold(); Pill(text: store.profile.ftpLabel, color: store.profile.ftpHow == .assumed ? BC.stale : BC.live) }
                    HStack {
                        TextField("Tested FTP in watts", text: $ftpText).keyboardType(.numberPad)
                        Button("Set") { if let v = Int(ftpText), v >= 50, v <= 600 { store.updateProfile { $0.ftpW = v; $0.ftpHow = .tested }; ftpText = "" } }.disabled(Int(ftpText) == nil)
                    }
                    if store.profile.ftpHow != .assumed { Button("Back to the assumption from weight and level") { store.profile.ftpHow = .assumed; store.profile.refreshAssumption() }.font(.footnote) }
                    ZoneBar()
                    ForEach(Array(store.profile.powerZones.enumerated()), id: \.offset) { i, z in
                        HStack { ZonePill(z: i + 1); Text(zoneName(i + 1)).font(.footnote); Spacer(); Text("\(z.lo)–\(z.hi.map(String.init) ?? "∞") W").font(.footnote).monospacedDigit(); Text("· \(hrRange(i + 1))").font(.caption2).foregroundStyle(.secondary) }
                    }
                } header: { Text("Zones") } footer: { Text("Power zones from FTP (Coggan). Heart-rate ranges from your max HR; they apply when a strap or watch provides heart rate.") }

                Section {
                    NavigationLink { ConnectionsView() } label: { Label("Connections", systemImage: "dot.radiowaves.left.and.right") }
                    NavigationLink { DeviceSettingsView() } label: { Label("BikeComputer settings and Wi-Fi", systemImage: "slider.horizontal.3") }
                    NavigationLink { SyncStatusView() } label: { HStack { Label("Sync status", systemImage: "arrow.triangle.2.circlepath"); Spacer(); Text(sync.state.label).font(.footnote).foregroundStyle(.secondary).lineLimit(1) } }
                } header: { Text("Devices") } footer: { Text("Connections shows every device and integration with one status; the board's own settings (brightness, timeout, wake gesture, Wi-Fi) are controlled from the phone with firmware 0.6.0.") }

                Section("Settings") {
                    Picker("Units", selection: $store.settings.units) { ForEach(AppSettings.Units.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Toggle("Phone-only mode", isOn: $store.settings.phoneOnlyMode)
                    Text("On: this phone records every ride, even with a BikeComputer connected (its values are shown, not merged). Off: a connected BikeComputer is the recorder.").font(.footnote).foregroundStyle(.secondary)
                    Picker("Heart-rate preference", selection: $store.settings.hrPref) { ForEach(AppSettings.HRPref.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Toggle("Keep the screen on during a ride", isOn: $store.settings.keepScreenOn)
                    Toggle("Connect to the BikeComputer automatically", isOn: Binding(get: { store.settings.autoConnectBoard }, set: { store.settings.autoConnectBoard = $0; device.autoConnect = $0 }))
                    Text("Off: the phone never connects on its own (Connections › BikeComputer › Reconnect now still works). The board's own link switch is under BikeComputer settings.").font(.footnote).foregroundStyle(.secondary)
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
                    Text("This build is simulator-tested (unit tests in CI). Pairing, live data, GPS to the board and watch heart rate were device-tested in builds 14–21; everything new in 0.4.0 is device-tested only after Rashed's checklist.").font(.footnote).foregroundStyle(.secondary)
                    if let i = device.info, !(i.hasSettings && i.hasProfileSync && i.hasWiFi) { Text("Board firmware \(i.fw): device settings, Wi-Fi setup and profile sync from the phone need firmware 0.6.0.").font(.footnote).foregroundStyle(BC.stale) }
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

struct SportsPicker: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        List {
            ForEach(RiderProfile.Sport.allCases, id: \.self) { sp in
                let on = store.profile.sports.contains(sp)
                Button { if on { store.profile.sports.removeAll { $0 == sp } } else { store.profile.sports.append(sp) } } label: { HStack { Text(sp.title).foregroundStyle(.primary); Spacer(); if on { Image(systemName: "checkmark").foregroundStyle(BC.accent) } } }
            }
            Section { Text("Other sports count toward your weekly load so the plan does not overload the bike days.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("Sports")
    }
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
