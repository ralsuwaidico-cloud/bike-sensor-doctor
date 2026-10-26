import SwiftUI
import AuthenticationServices

/// Profile tab (0.5.0): a category menu instead of one long page. Each category is its own page and saves straight
/// into the Store (so nothing typed is lost); shared athlete fields keep syncing to the BikeComputer, where the phone
/// is authoritative after pairing.
struct ProfileTabView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var sync: ProfileSync
    @EnvironmentObject private var account: AccountService
    @State private var showAccount = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        ZStack { Circle().fill(BC.accent.opacity(0.18)).frame(width: 56, height: 56); Text(initials).font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(BC.accent) }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(store.profile.name.isEmpty ? "Rider" : store.profile.name).font(.title3.weight(.bold)).lineLimit(1)
                            Text("FTP \(store.profile.ftpW) W · \(store.profile.ftpLabel) · \(store.profile.hoursPerWeek) h cycling" + (store.profile.trainingMode.includesLifting ? " · \(store.profile.liftingHoursPerWeek) h lifting" : "")).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                            HStack(spacing: 6) {
                                if account.state.isSignedIn { Pill(text: "account", color: BC.live) } else if store.guest { Pill(text: "guest", color: BC.stale) } else { Pill(text: "Apple ID · this phone", color: BC.live) }
                                if device.state == .ready { Pill(text: "board connected", color: BC.live) }
                            }
                        }
                        Spacer()
                    }.padding(.vertical, 4)
                }
                Section("Profile") {
                    link("Rider information", "person.text.rectangle", "name, birth year, weight, height, units") { RiderInfoPage() }
                    link("Training profile", "target", "\(store.profile.trainingMode.title.lowercased()) mode · goals, level, availability") { TrainingProfilePage() }
                    link("Heart rate", "heart", hrSummary) { HeartRatePage() }
                    link("Power & cycling", "bolt", "FTP \(store.profile.ftpW) W · zones · meter · bike") { PowerCyclingPage() }
                }
                Section("Devices") {
                    link("Connections & devices", "dot.radiowaves.left.and.right", deviceSummary) { ConnectionsView() }
                    link("App & device settings", "gearshape", "display, notifications, privacy, sync, firmware") { AppSettingsPage() }
                }
                AccountSection(present: $showAccount)
                Section {
                    LabeledContent("Version", value: "Cyclift \(AppInfo.label)")
                    NavigationLink("Privacy policy") { LegalView(kind: .privacy) }
                    NavigationLink("Terms of use") { LegalView(kind: .terms) }
                    Link(destination: SupportInfo.supportPage) { HStack { Text("Support"); Spacer(); Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary) } }
                    LabeledContent("Protocol", value: device.info.map { "v\($0.verMajor).\($0.verMinor) · board \($0.fw)" } ?? "BikeComputer Link v1.2")
                    Text("Works offline. Network is used only for your account and cloud sync when you sign in, and for Sign in with Apple. No analytics, no advertising.").font(.footnote).foregroundStyle(.secondary)
                    if let e = store.lastSaveError { Text("Save problem: \(e)").font(.footnote).foregroundStyle(BC.warn) }
                } header: { Text("About") }
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $showAccount) { AccountSheet() }
        }
    }
    private func link<D: View>(_ title: String, _ icon: String, _ subtitle: String, @ViewBuilder _ d: @escaping () -> D) -> some View {
        NavigationLink { d() } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(BC.accent).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) { Text(title).font(.body.weight(.semibold)); Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
            }.padding(.vertical, 2)
        }
    }
    private var initials: String { let p = store.profile.name.split(separator: " "); return p.isEmpty ? "R" : p.prefix(2).map { String($0.prefix(1)).uppercased() }.joined() }
    private var hrSummary: String { "max \(store.profile.estimatedMaxHR) bpm (\(store.profile.maxHRLabel))" + (store.profile.restHR.map { " · rest \($0)" } ?? "") }
    private var deviceSummary: String {
        var parts: [String] = []
        parts.append(device.state == .ready ? "BikeComputer connected" : device.remembered ? "BikeComputer remembered" : "no BikeComputer")
        parts.append(sync.state.label)
        return parts.joined(separator: " · ")
    }
}

// MARK: - Rider information
struct RiderInfoPage: View {
    @EnvironmentObject private var store: Store
    @State private var birth = ""
    @State private var height = ""
    private let genders = ["Prefer not to say", "Female", "Male", "Other"]
    var body: some View {
        Form {
            Section("Name") { TextField("Your name", text: $store.profile.name).textContentType(.givenName) }
            Section {
                NumberRow(title: "Birth year", placeholder: "not set", text: $birth, range: 1900...Calendar.current.component(.year, from: Date())) { v in store.updateProfile { $0.birthYear = v } }
                    .onAppear { birth = store.profile.birthYear.map(String.init) ?? "" }
                Picker("Gender", selection: Binding(get: { store.profile.gender ?? genders[0] }, set: { g in store.updateProfile { $0.gender = g == genders[0] ? nil : g } })) { ForEach(genders, id: \.self) { Text($0).tag($0) } }
            } footer: { Text("Birth year sets the estimated max heart rate until you enter a measured one. Gender is optional and only stored on this phone.") }
            Section("Body") {
                HStack { Text("Weight"); Spacer(); Text(weightText).foregroundStyle(.secondary).monospacedDigit() }
                Slider(value: $store.profile.weightKg, in: 40...150, step: 0.5).onChange(of: store.profile.weightKg) { _, _ in store.profile.refreshAssumption() }
                NumberRow(title: "Height (cm)", placeholder: "not set", text: $height, range: 120...230) { v in store.updateProfile { $0.heightCm = v } }
                    .onAppear { height = store.profile.heightCm.map(String.init) ?? "" }
            }
            Section("Units") {
                Picker("Distance and speed", selection: $store.settings.units) { ForEach(AppSettings.Units.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                Text("Weight stays in kilograms; the board receives the same unit setting.").font(.footnote).foregroundStyle(.secondary)
            }
            Section { Text("Profile version \(store.profile.version). Name, weight, birth year and units are shared with the BikeComputer; the phone is the authority once paired.").font(.caption2).foregroundStyle(.secondary) }
        }
        .navigationTitle("Rider information").navigationBarTitleDisplayMode(.inline)
    }
    private var weightText: String { store.settings.units == .imperial ? String(format: "%.1f kg (%.0f lb)", store.profile.weightKg, store.profile.weightKg * 2.20462) : String(format: "%.1f kg", store.profile.weightKg) }
}

/// A numeric field that only writes a valid value (or nil when cleared) — never a half-typed number.
struct NumberRow: View {
    let title: String; let placeholder: String
    @Binding var text: String
    let range: ClosedRange<Int>
    let commit: (Int?) -> Void
    var body: some View {
        HStack {
            Text(title); Spacer()
            TextField(placeholder, text: $text).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 110)
                .onChange(of: text) { _, v in
                    if v.isEmpty { commit(nil); return }
                    if let n = Int(v), range.contains(n) { commit(n) }
                }
        }
    }
}

// MARK: - Training profile
struct TrainingProfilePage: View {
    @EnvironmentObject private var store: Store
    @State private var showAvailability = false
    var body: some View {
        Form {
            Section {
                Picker("Training mode", selection: Binding(get: { store.profile.trainingMode }, set: { m in store.updateProfile { p in p.trainingMode = m; if m == .cycling { p.liftDaysPerWeek = 0; p.liftingHoursPerWeek = 0 } else if p.liftDaysPerWeek == 0 { p.liftDaysPerWeek = 2; p.liftingHoursPerWeek = 2 } } })) { ForEach(TrainingMode.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                Text(store.profile.trainingMode.hint).font(.footnote).foregroundStyle(.secondary)
                if store.profile.trainingMode == .hybrid {
                    Picker("Main priority", selection: Binding(get: { store.profile.priority }, set: { v in store.updateProfile { $0.priority = v } })) { ForEach(TrainingPriority.allCases, id: \.self) { Text($0.title).tag($0) } }
                }
            } header: { Text("Training mode") } footer: { Text("Hybrid Athlete: one coach for cycling and lifting, with separate hour budgets. Changing the mode rebuilds the coming weeks around your days (hand-edited sessions are kept).") }
            Section("Goal") {
                ForEach(RiderProfile.Goal.onboardingChoices, id: \.self) { g in
                    Button { store.updateProfile { $0.goal = g } } label: { HStack { VStack(alignment: .leading) { Text(g.title).foregroundStyle(.primary); Text(g.hint).font(.caption).foregroundStyle(.secondary) }; Spacer(); if store.profile.goal == g { Image(systemName: "checkmark").foregroundStyle(BC.accent) } } }
                }
            }
            Section("Experience level") {
                Picker("Level", selection: $store.profile.level) { ForEach(RiderProfile.Level.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                    .onChange(of: store.profile.level) { _, _ in store.profile.refreshAssumption() }
                Text(store.profile.level.hint).font(.footnote).foregroundStyle(.secondary)
            }
            Section("Sports and activities") { NavigationLink("Sports (\(store.profile.sports.count) selected)") { SportsPicker() } }
            if store.profile.trainingMode.includesLifting {
                Section("Strength") {
                    NavigationLink { TemplatesView() } label: { HStack { Text("Routines (templates)"); Spacer(); Text("\(store.templates.count)").foregroundStyle(.secondary) } }
                    NavigationLink { WeekdayRoutinesPage() } label: { HStack { Text("Routine per weekday"); Spacer(); Text("\(store.weekdayRoutines.count) set").foregroundStyle(.secondary) } }
                    NavigationLink { EquipmentPage() } label: { HStack { Text("Equipment I own"); Spacer(); Text(store.equipment.isSet ? "\(store.equipment.owned.count) items" : "not set").foregroundStyle(.secondary) } }
                    NavigationLink { MyExercisesView() } label: { HStack { Text("My exercises"); Spacer(); Text("\(store.customExercises.count) custom · \(ExerciseCatalogue.builtIn.count) built in").font(.caption).foregroundStyle(.secondary) } }
                }
            }
            Section {
                if store.profile.trainingMode.includesCycling {
                    Stepper("Cycling: \(store.profile.cyclingDaysPerWeek) rides a week", value: Binding(get: { store.profile.cyclingDaysPerWeek }, set: { v in store.updateProfile { $0.cyclingDaysPerWeek = v } }), in: 1...6)
                    Stepper("Cycling budget: \(store.profile.hoursPerWeek) h", value: $store.profile.hoursPerWeek, in: 1...25)
                }
                if store.profile.trainingMode.includesLifting {
                    Stepper("Strength: \(store.profile.liftDaysPerWeek) lifts a week", value: Binding(get: { store.profile.liftDaysPerWeek }, set: { v in store.updateProfile { $0.liftDaysPerWeek = v } }), in: 1...6)
                    Stepper("Lifting budget: \(store.profile.liftingHoursPerWeek) h", value: Binding(get: { store.profile.liftingHoursPerWeek }, set: { v in store.updateProfile { $0.liftingHoursPerWeek = v } }), in: 1...12)
                }
                Button { showAvailability = true } label: { HStack { Text("Training days and durations"); Spacer(); Text(availabilityText).font(.caption).foregroundStyle(.secondary) } }
                let a = store.effectiveAvailability
                HStack(spacing: 4) { ForEach(0..<7, id: \.self) { i in VStack(spacing: 2) { Text(WeeklyAvailability.dayNames[i]).font(.system(size: 9, weight: .heavy)).foregroundStyle(.secondary); Image(systemName: a.days[i].activity.icon).font(.system(size: 12)).foregroundStyle(a.days[i].activity == .rest ? .secondary : BC.accent) }.frame(maxWidth: .infinity) } }
            } header: { Text("Weekly availability") } footer: { Text("The plan is built around the days you choose. Cycling hours and lifting hours are separate budgets; the coach schedules up to each and suggests changes instead of exceeding them.") }
            Section("Training history") {
                let rides = store.rides
                LabeledContent("Rides recorded", value: "\(rides.count)")
                LabeledContent("Total riding", value: Fmt.duration(seconds: rides.reduce(0) { $0 + $1.durationS }))
                LabeledContent("Sessions completed", value: "\(store.plan.filter { $0.done }.count)")
                LabeledContent("Strength sessions logged", value: "\(store.strength.count)")
                LabeledContent("Total lifting", value: Fmt.duration(minutes: store.strength.reduce(0) { $0 + $1.minutes }))
                if let first = rides.last { LabeledContent("First ride", value: first.start.dayAndDate) }
            }
        }
        .navigationTitle("Training profile").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAvailability) { AvailabilityEditor() }
        .onChange(of: store.profile.trainingMode) { _, _ in if store.availability == nil { store.regenerate(weekOf: Date(), replaceEdited: false); store.regenerate(weekOf: Calendar.current.date(byAdding: .day, value: 7, to: Date())!, replaceEdited: false) } }
    }
    private var availabilityText: String { let a = store.effectiveAvailability; return "\(a.cycleDays) ride · \(a.liftDays) lift days" + (a.fixedAssignments > 0 ? " · \(a.fixedAssignments) fixed" : "") + (store.availability == nil ? " (suggested)" : "") }
}

// MARK: - Heart rate
struct HeartRatePage: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var device: DeviceLink
    @State private var rest = ""
    @State private var maxHR = ""
    @State private var lthr = ""
    var body: some View {
        Form {
            Section {
                NumberRow(title: "Resting HR", placeholder: "not set", text: $rest, range: 25...120) { v in store.updateProfile { $0.restHR = v } }.onAppear { rest = store.profile.restHR.map(String.init) ?? "" }
                NumberRow(title: "Max HR", placeholder: "\(store.profile.estimatedMaxHR) estimated", text: $maxHR, range: 100...230) { v in store.updateProfile { $0.maxHR = v } }.onAppear { maxHR = store.profile.maxHR.map(String.init) ?? "" }
                NumberRow(title: "Threshold HR (LTHR)", placeholder: "not set", text: $lthr, range: 80...220) { v in store.updateProfile { $0.lthr = v } }.onAppear { lthr = store.profile.lthr.map(String.init) ?? "" }
            } header: { Text("Values") } footer: { Text(store.profile.maxHR == nil ? "Max heart rate is estimated from age (208 − 0.7 × age) until you enter a measured value." : "Max heart rate entered by you.") }
            Section {
                Picker("Zone method", selection: $store.profile.hrZoneMethod) { ForEach(RiderProfile.HRZoneMethod.allCases, id: \.self) { Text($0.title).tag($0) } }
                if store.profile.hrZoneMethod == .lthr, store.profile.lthr == nil { Text("Enter your LTHR above; until then zones use max heart rate.").font(.footnote).foregroundStyle(BC.stale) }
                ForEach(Array(store.profile.hrZones.enumerated()), id: \.offset) { i, z in
                    HStack { Text("Z\(i + 1)").font(.caption.weight(.heavy)).padding(.horizontal, 7).padding(.vertical, 3).background(BC.zone(i + 1), in: Capsule()).foregroundStyle(.white); Text(HrZones.names[i].dropFirst(3)).font(.footnote); Spacer(); Text("\(z.lo)–\(z.hi.map(String.init) ?? "∞") bpm").font(.footnote).monospacedDigit() }
                }
            } header: { Text("Heart-rate zones") }
            Section {
                Picker("Preferred source", selection: $store.settings.hrPref) { ForEach(AppSettings.HRPref.allCases, id: \.self) { Text($0.title).tag($0) } }
                LabeledContent("Apple Watch", value: watch.hrIsFresh ? "heart rate live" : watch.appInstalled ? "app installed · start the workout" : "no watch app")
                LabeledContent("Strap via BikeComputer", value: device.state == .ready && device.live?.hrSource == .bleStrap ? "live" : "pairs on the board")
                LabeledContent("WHOOP", value: "not connected · cloud only, never live HR")
            } header: { Text("Sources") } footer: { Text("Live heart rate comes from the Apple Watch (via this phone) or a strap paired on the board (direct). The coach uses whichever is live; nothing is shown without a live source.") }
        }
        .navigationTitle("Heart rate").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Power & cycling
struct PowerCyclingPage: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @State private var ftpText = ""
    @State private var wheel = ""
    var body: some View {
        Form {
            Section {
                HStack { Text("FTP"); Spacer(); Text("\(store.profile.ftpW) W").bold().monospacedDigit(); Pill(text: store.profile.ftpLabel, color: store.profile.ftpHow == .assumed ? BC.stale : BC.live) }
                HStack {
                    TextField("Tested FTP in watts", text: $ftpText).keyboardType(.numberPad)
                    Button("Set") { if let v = Int(ftpText), v >= 50, v <= 600 { store.updateProfile { $0.ftpW = v; $0.ftpHow = .tested }; ftpText = "" } }.disabled(Int(ftpText) == nil)
                }
                if store.profile.ftpHow != .assumed { Button("Back to the assumption from weight and level") { store.updateProfile { $0.ftpHow = .assumed; $0.refreshAssumption() } }.font(.footnote) }
                if let s = store.ftpSuggestion { Text("Suggested from your \(s.rideDate.dayAndDate) ride: \(s.watts) W (best 20 min \(s.best20) W). Accept it on Home or Progress.").font(.footnote).foregroundStyle(BC.accent) }
            } header: { Text("FTP") } footer: { Text(ftpMethod) }
            Section("Power zones") {
                ZoneBar()
                ForEach(Array(store.profile.powerZones.enumerated()), id: \.offset) { i, z in
                    HStack { ZonePill(z: i + 1); Text(PowerZones.names[i].dropFirst(3)).font(.footnote); Spacer(); Text("\(z.lo)–\(z.hi.map(String.init) ?? "∞") W").font(.footnote).monospacedDigit() }
                }
            }
            Section {
                LabeledContent("Power meter", value: meterText)
                Pill(text: "power unverified until validated", color: BC.stale)
                Text("Calibration is not available: the app never writes to the meter's control point (safety rule). Pair and forget the meter on the board's Connections › Power meter.").font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Power meter") }
            Section {
                Stepper("Low: \(store.profile.cadenceLow) rpm", value: Binding(get: { store.profile.cadenceLow }, set: { v in store.updateProfile { $0.cadenceLow = min(v, $0.cadenceHigh - 5) } }), in: 50...110, step: 5)
                Stepper("High: \(store.profile.cadenceHigh) rpm", value: Binding(get: { store.profile.cadenceHigh }, set: { v in store.updateProfile { $0.cadenceHigh = max(v, $0.cadenceLow + 5) } }), in: 60...130, step: 5)
            } header: { Text("Cadence preference") } footer: { Text("The ride coach asks you to pedal faster or slower outside this range.") }
            Section {
                TextField("Bike name (optional)", text: Binding(get: { store.profile.bikeName ?? "" }, set: { v in store.updateProfile { $0.bikeName = v.isEmpty ? nil : v } }))
                NumberRow(title: "Wheel circumference (mm)", placeholder: "2096", text: $wheel, range: 1000...2600) { v in store.updateProfile { $0.wheelMm = v ?? 2096 } }.onAppear { wheel = "\(store.profile.wheelMm)" }
                Text("Used by a speed sensor on the board (firmware 0.6.0, Connections › Speed). 700×25c ≈ 2105 mm, 700×28c ≈ 2136 mm. \(device.info?.hasSettings == true ? "Sent to the board with the device settings." : "Stored on this phone until the board supports it.")").font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Bike") }
        }
        .navigationTitle("Power & cycling").navigationBarTitleDisplayMode(.inline)
    }
    private var ftpMethod: String {
        switch store.profile.ftpHow {
        case .assumed: return "Estimation method: weight × level (\(String(format: "%.2f", store.profile.level.wkg)) W/kg) — a starting assumption, replaced by a real 20-minute effort (0.95 × best 20 min) that you accept, or by a value you enter."
        case .fromRides: return "Estimated from a ride: 0.95 × your best 20-minute power. A tested or entered value always wins."
        case .entered: return "Entered by you."
        case .tested: return "From a test you entered. Never replaced automatically."
        }
    }
    private var meterText: String {
        guard device.state == .ready, let l = device.live else { return device.remembered ? "via the BikeComputer (not connected)" : "pairs on the board" }
        switch l.meterLink { case 4: return "connected (direct on the board)"; case 1: return "not paired"; case 2: return "searching"; case 3: return "connecting"; case 5: return "reconnecting"; default: return "off" }
    }
}

// MARK: - App & device settings
struct AppSettingsPage: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var sync: ProfileSync
    var body: some View {
        Form {
            Section("Display and theme") {
                Picker("Appearance", selection: $store.settings.appearance) { ForEach(AppSettings.Appearance.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
                Toggle("Keep the screen on during a ride", isOn: $store.settings.keepScreenOn)
                NavigationLink("Ride tiles (classic layout)") { TilePicker() }
            }
            Section("Coach") {
                Toggle("Coach instructions during rides", isOn: $store.settings.coachEnabled)
                Picker("How much it talks", selection: $store.settings.coachTalk) { ForEach(AppSettings.CoachTalk.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            }
            Section {
                Toggle("Show \"recording in the background\" notice", isOn: $store.settings.backgroundNotice)
                Text("A local notification while a phone-only ride records with the screen locked. No push notifications are used.").font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Notifications") }
            Section {
                Text("Without an account everything stays on this phone. With an account, your data is stored in your own account and synced between your devices. No analytics, no advertising. Apple Health is written only when you turn it on in Connections.").font(.footnote).foregroundStyle(.secondary)
                NavigationLink("Privacy policy") { LegalView(kind: .privacy) }
                Text("Delete your account or all data: Profile › Account.").font(.footnote).foregroundStyle(.secondary)
            } header: { Text("Privacy") }
            Section("Recording") {
                Toggle("Phone-only mode", isOn: $store.settings.phoneOnlyMode)
                Text("On: this phone records every ride even with a BikeComputer connected (its values are shown, not merged). Off: a connected BikeComputer is the recorder.").font(.footnote).foregroundStyle(.secondary)
                Toggle("Connect to the BikeComputer automatically", isOn: Binding(get: { store.settings.autoConnectBoard }, set: { store.settings.autoConnectBoard = $0; device.autoConnect = $0 }))
            }
            Section("Data synchronization") {
                NavigationLink { SyncStatusView() } label: { HStack { Text("Sync status"); Spacer(); Text(sync.state.label).font(.footnote).foregroundStyle(.secondary).lineLimit(1) } }
                CloudSyncRow()
                Text("Cloud sync needs an account (Profile › Account). The BikeComputer sync works over Bluetooth with firmware 0.6.0 or newer.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Firmware") {
                LabeledContent("Board firmware", value: device.info?.fw ?? (device.remembered ? "connect to read" : "no board"))
                LabeledContent("Needed for sync / Wi-Fi / settings", value: "0.6.0")
                Text("Firmware is installed from the PC installer kit (INSTALL-v0.x.x.bat); the app cannot update the board over the air in this build.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Device settings") {
                NavigationLink { DeviceSettingsView() } label: { Label("BikeComputer settings and Wi-Fi", systemImage: "slider.horizontal.3") }
                if let i = device.info, !(i.hasSettings && i.hasProfileSync && i.hasWiFi) { Text("Board firmware \(i.fw): device settings, Wi-Fi setup and profile sync from the phone need firmware 0.6.0.").font(.footnote).foregroundStyle(BC.stale) }
            }
        }
        .navigationTitle("App & device settings").navigationBarTitleDisplayMode(.inline)
    }
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
/// The rider's own exercises (built-in ones are listed read-only in the search sheet).
struct MyExercisesView: View {
    @EnvironmentObject private var store: Store
    @State private var create = false
    var body: some View {
        List {
            Section { Text("\(ExerciseCatalogue.builtIn.count) built-in exercises are searchable by name, equipment, movement and muscle when you log a session. Add anything missing here; your exercises appear first.").font(.footnote).foregroundStyle(.secondary) }
            Section("Your exercises") {
                if store.customExercises.isEmpty { Text("None yet.").foregroundStyle(.secondary) }
                ForEach(store.customExercises) { e in VStack(alignment: .leading, spacing: 2) { Text(e.name); Text("\(e.pattern.title) · \(e.equipmentText)").font(.caption).foregroundStyle(.secondary) } }
                    .onDelete { idx in for i in idx { store.removeCustomExercise(store.customExercises[i]) } }
                Button { create = true } label: { Label("New exercise", systemImage: "plus") }
            }
        }
        .navigationTitle("My exercises").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $create) { CreateExerciseSheet(initialName: "") { store.addCustomExercise($0) } }
    }
}
