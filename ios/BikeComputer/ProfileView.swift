import SwiftUI

/// Profile (rc3, owner 1 Nov): ONE screen, four sections — Personal, Training, Devices & Connections, Settings — then
/// Your data and About. It replaces the old category menu, the "Training profile" page and the duplicated "Connections &
/// devices" / "App & device settings" pages: every setting has one home. Training reads and writes the same profile the
/// onboarding writes (one source of truth). Gender and height are no longer shown (no feature uses them; the stored
/// values are kept and still exported).
struct ProfileTabView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var cloud: SyncEngine
    @State private var exportURL: URL?
    @State private var confirmDelete = false
    @State private var showAvailability = false
    /// RC3: the before/after preview of a training change made here (nothing is saved until Apply).
    @State private var planPreview: PreviewRef? = nil
    @State private var equipmentAtOpen: EquipmentProfile? = nil

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ProfileHeaderRow(name: store.profile.name, line: headerLine, boardConnected: device.state == .ready)
                }
                personal
                training
                Section {
                    DevicesConnectionsRows()
                } header: { Text("Devices & Connections") }
                settings
                YourDataSection(exportURL: $exportURL, confirmDelete: $confirmDelete, snapshot: { store.snapshot })
                about
            }
            .navigationTitle("Profile")
            .sheet(item: $exportURL) { url in ShareSheet(items: [url]) }
            .sheet(isPresented: $showAvailability) { AvailabilityEditor() }
            // RC3 / ENG-J2: every training change made here goes through one before/after preview (current unfinished
            // and future sessions only; completed workouts are never changed)
            .sheet(item: $planPreview) { r in PlanChangeSheet(proposalId: r.id) }
            .alert("Delete everything on this phone?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { cloud.reset(); device.forget(); store.resetAll(); store.guest = true }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Profile, plan, ride history, strength logs, templates and the remembered BikeComputer are removed from this phone permanently. The BikeComputer keeps its own data; use Forget phone on the device too.")
            }
        }
    }

    // MARK: Personal
    private var personal: some View {
        Section("Personal") {
            HStack {
                Text("Name")
                Spacer()
                TextField("Your name", text: $store.profile.name).textContentType(.givenName).multilineTextAlignment(.trailing)
            }
            // RC3: date of birth (the same field onboarding r7 writes); the board still receives the birth year.
            // S2-0: nothing is pre-filled — an unset date shows "Not set" and a picker appears only on request (GR-20).
            if let d = store.profile.dateOfBirth {
                DatePicker("Date of birth", selection: Binding(get: { d }, set: { v in store.updateProfile { $0.setDateOfBirth(v) } }), in: ProfileTabView.birthRange, displayedComponents: .date)
                    .accessibilityIdentifier("profileBirth")
                if store.profile.provenance(.dateOfBirth).needsConfirmation { Text("From an earlier version — please check it.").font(.footnote).foregroundStyle(BC.warn) }
            } else {
                DateOfBirthEntryRow(range: ProfileTabView.birthRange)
                Text("Needed for heart-rate zones (max heart rate from age). Until then rides use effort targets.").font(.footnote).foregroundStyle(.secondary)
            }
            if let w = store.profile.weightKg {
                Stepper(value: Binding(get: { w }, set: { v in store.updateProfile { $0.setWeight(v) } }), in: 30...200, step: 0.5) {
                    HStack { Text("Weight"); Spacer(); Text(weightText).foregroundStyle(.secondary).monospacedDigit() }
                }
                .accessibilityIdentifier("profileWeight")
                Text(weightSourceText).font(.footnote).foregroundStyle(store.profile.provenance(.weight).needsConfirmation ? BC.warn : .secondary)
            } else {
                WeightEntryRow()
                Text("Needed for W/kg and lifting loads. Enter it, or turn on Apple Health weight in Settings.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Training (replaces the old Training profile page; the same fields onboarding r7 writes)
    private var training: some View {
        Section("Training") {
            ProfileSegmentRow(title: "Type") {
                Picker("Type", selection: Binding(get: { store.profile.trainingMode }, set: { m in
                    change(.profile) { x in
                        x.profile.trainingMode = m
                        if m == .cycling { x.profile.liftDaysPerWeek = 0; x.profile.liftingHoursPerWeek = 0 } else if x.profile.liftDaysPerWeek == 0 { x.profile.liftDaysPerWeek = 2; x.profile.liftingHoursPerWeek = 2 }
                    }
                })) {
                    ForEach(TrainingMode.allCases, id: \.self) { Text(ProfileText.mode($0)).tag($0) }
                }
            }
            .accessibilityIdentifier("profileType")
            if store.profile.trainingMode == .hybrid {
                ProfileSegmentRow(title: "Priority") {
                    Picker("Priority", selection: Binding(get: { store.profile.priority }, set: { v in change(.priority) { $0.profile.priority = v } })) {
                        ForEach(TrainingPriority.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                }
            }
            if store.profile.trainingMode.includesCycling {
                ProfileSegmentRow(title: "Cycling level") {
                    Picker("Cycling level", selection: Binding(get: { store.profile.level }, set: { v in change(.profile) { $0.profile.level = v } })) {
                        ForEach(RiderProfile.Level.allCases, id: \.self) { Text(ProfileText.level($0)).tag($0) }
                    }
                }
                .accessibilityIdentifier("profileCyclingLevel")
            }
            if store.profile.trainingMode.includesLifting {
                // RC3 / ENG-A1: lifting experience is its own answer (never copied from the cycling level)
                ProfileSegmentRow(title: "Strength level") {
                    Picker("Strength level", selection: Binding(get: { store.strengthPrefs.experience ?? .beginner }, set: { v in change(.strengthLevel) { $0.strengthPrefs.experience = v; $0.profile.confirmStrengthLevel = nil } })) {
                        ForEach(StrengthPrefs.Experience.allCases, id: \.self) { Text(ProfileText.strengthLevel($0)).tag($0) }
                    }
                }
                .accessibilityIdentifier("profileStrengthLevel")
            }
            NavigationLink { GoalPage() } label: { LabeledContent("Goals", value: ProfileText.goals(store.profile)) }
                .accessibilityIdentifier("profileGoal")
            Button { showAvailability = true } label: {
                HStack {
                    Text("Week").foregroundStyle(.primary)
                    Spacer()
                    AvailabilityIcons(availability: store.effectiveAvailability)
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .accessibilityIdentifier("profileWeek")
            NavigationLink { WeeklyTimePage() } label: { LabeledContent("Session length", value: timeText) }
                .accessibilityIdentifier("profileTime")
            if store.profile.trainingMode.includesLifting {
                NavigationLink {
                    // Equipment edits are proposed as one change when the page closes (preview before anything changes)
                    EquipmentPage()
                        .onAppear { if equipmentAtOpen == nil { equipmentAtOpen = store.equipment } }
                        .onDisappear { proposeEquipment() }
                } label: { LabeledContent("Equipment", value: equipmentText) }
                    .accessibilityIdentifier("profileEquipment")
            }
            if store.profile.trainingMode.includesCycling {
                NavigationLink { PowerCyclingPage() } label: { LabeledContent("FTP", value: "\(store.profile.ftpDisplay) · \(store.profile.ftpSource.title)") }
                    .accessibilityIdentifier("profileFTP")
            }
            NavigationLink { HeartRatePage() } label: { LabeledContent("Heart rate", value: store.profile.maxHRForZones.map { "max \($0)\(store.profile.maxHRIsEstimate ? " (est.)" : "")" } ?? "zones not set") }
            NavigationLink { TrainingPreferencesPage() } label: { Text("Preferences") }
                .accessibilityIdentifier("profilePreferences")
        }
    }

    private var equipmentText: String {
        let e = store.equipment
        if e.isProvisional { return "Not sure yet" }
        if e.owned.isEmpty { return "Bodyweight only" }
        return "\(e.owned.count) items"
    }
    /// The Equipment page edits the store directly; on close the edit is turned back into one proposal (old values are
    /// restored first so the preview compares before/after and Cancel keeps the old equipment).
    private func proposeEquipment() {
        guard let old = equipmentAtOpen else { return }
        equipmentAtOpen = nil
        var new = store.equipment
        guard new != old else { return }
        if new.owned.isEmpty && !old.isProvisional { new.confirmed = true }
        if !new.owned.isEmpty { new.confirmed = true }
        store.equipment = old
        change(.equipment) { $0.equipment = new }
    }

    // MARK: Settings (one home for each app setting)
    private var settings: some View {
        Section("Settings") {
            ProfileSegmentRow(title: "Units") {
                Picker("Units", selection: $store.settings.units) { ForEach(AppSettings.Units.allCases, id: \.self) { Text($0 == .metric ? "Metric" : "Imperial").tag($0) } }
            }
            ProfileSegmentRow(title: "Appearance") {
                Picker("Appearance", selection: $store.settings.appearance) { ForEach(AppSettings.Appearance.allCases, id: \.self) { Text($0.title).tag($0) } }
            }
            Toggle("Ride notifications", isOn: $store.settings.backgroundNotice)
                .accessibilityIdentifier("settingsNotifications")
            NavigationLink { RideCoachSettingsPage() } label: { Text("Ride & coach") }
                .accessibilityIdentifier("settingsRide")
            NavigationLink { HealthSafetyPage() } label: { LabeledContent("Health & safety", value: HealthSafetyPage.summary(store.profile)) }
                .accessibilityIdentifier("settingsHealthSafety")
            NavigationLink("Privacy policy") { LegalView(kind: .privacy) }
            // Accounts are off in this version (ReleaseFlags.accountsEnabled): nothing to sign in to
            LabeledContent("Account", value: "Not needed")
        }
    }

    private var about: some View {
        Section {
            LabeledContent("Version", value: "Cyclift \(AppInfo.label)")
            NavigationLink("Terms of use") { LegalView(kind: .terms) }
            if let mail = SupportInfo.mailURL {
                Link(destination: mail) { HStack { Text("Contact support"); Spacer(); Image(systemName: "envelope").foregroundStyle(.secondary) } }
            }
            Link(destination: SupportInfo.supportPage) { HStack { Text("Support page"); Spacer(); Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary) } }
            if let e = store.lastSaveError { Text("Save problem: \(e)").font(.footnote).foregroundStyle(BC.warn) }
        } header: { Text("About") }
    }

    static var birthRange: ClosedRange<Date> {
        let cal = Calendar.current
        let lo = cal.date(from: DateComponents(year: 1920, month: 1, day: 1)) ?? Date.distantPast
        let hi = cal.date(byAdding: .year, value: -13, to: Date()) ?? Date()
        return lo...hi
    }
    private func change(_ cause: PlanChangeCause, _ edit: (inout PlanInputs) -> Void) { planPreview = store.changeTraining(cause: cause, edit) }

    private var headerLine: String {
        let p = store.profile
        return ProfileText.mode(p.trainingMode) + " · " + ProfileText.level(p.level)
    }
    private var weightText: String { let w = store.profile.weightKg ?? 0; return store.settings.units == .imperial ? String(format: "%.1f kg (%.0f lb)", w, w * 2.20462) : String(format: "%.1f kg", w) }
    /// S2-0: where the weight came from and when (Entered / Apple Health / Unverified).
    private var weightSourceText: String {
        let p = store.profile.provenance(.weight)
        let when = p.recordedAt.map { " · \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
        switch p.source {
        case .appleHealth: return "Apple Health\(when)"
        case .legacyUnverified: return "From an earlier version — please confirm\(when)"
        case .unknown: return "Not set"
        default: return "Entered by you\(when)"
        }
    }
    private var timeText: String {
        let p = store.profile
        var parts: [String] = []
        if p.trainingMode.includesCycling { parts.append("Ride \(p.cyclingSessionMinutes.map { "\($0) min" } ?? "–")") }
        if p.trainingMode.includesLifting { parts.append("Lift \(p.strengthSessionMinutes.map { "\($0) min" } ?? "–")") }
        return parts.joined(separator: " · ")
    }
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
                NumberRow(title: "Resting HR", placeholder: "not set", text: $rest, range: 25...120) { v in store.updateProfile { $0.setRestHR(v) } }.onAppear { rest = store.profile.restHR.map(String.init) ?? "" }
                NumberRow(title: "Max HR", placeholder: store.profile.maxHRForZones.map { "\($0) estimated" } ?? "not set", text: $maxHR, range: 100...230) { v in store.updateProfile { $0.setMaxHR(v) } }.onAppear { maxHR = store.profile.maxHR.map(String.init) ?? "" }
                NumberRow(title: "Threshold HR (LTHR)", placeholder: "not set", text: $lthr, range: 80...220) { v in store.updateProfile { $0.lthr = v } }.onAppear { lthr = store.profile.lthr.map(String.init) ?? "" }
            } header: { Text("Values") } footer: { Text(store.profile.maxHR != nil ? "Max heart rate entered by you." : store.profile.maxHRForZones != nil ? "Max heart rate is estimated from your age (208 − 0.7 × age) until you enter a measured value." : "No max heart rate: enter one, or set your date of birth in Profile for an age-based estimate. Until then there are no heart-rate zones.") }
            Section {
                Picker("Zone method", selection: $store.profile.hrZoneMethod) { ForEach(RiderProfile.HRZoneMethod.allCases, id: \.self) { Text($0.title).tag($0) } }
                if store.profile.hrZoneMethod == .lthr, store.profile.lthr == nil { Text("Enter your LTHR above; until then zones use max heart rate.").font(.footnote).foregroundStyle(BC.stale) }
                if let zones = store.profile.hrZones {
                    ForEach(Array(zones.enumerated()), id: \.offset) { i, z in
                        HStack { Text("Z\(i + 1)").font(.caption.weight(.heavy)).padding(.horizontal, 7).padding(.vertical, 3).background(BC.zone(i + 1), in: Capsule()).foregroundStyle(.white); Text(HrZones.names[i].dropFirst(3)).font(.footnote); Spacer(); Text("\(z.lo)–\(z.hi.map(String.init) ?? "∞") bpm").font(.footnote).monospacedDigit() }
                    }
                } else {
                    Text("Unknown — no max or threshold heart rate yet.").font(.footnote).foregroundStyle(.secondary)
                }
            } header: { Text("Heart-rate zones") }
            Section {
                Picker("Preferred source", selection: $store.settings.hrPref) { ForEach(AppSettings.HRPref.allCases, id: \.self) { Text($0.title).tag($0) } }
                LabeledContent("Apple Watch", value: watch.hrIsFresh ? "heart rate live" : watch.appInstalled ? "app installed · start the workout" : "no watch app")
                LabeledContent("Strap via BikeComputer", value: device.state == .ready && device.live?.hrSource == .bleStrap ? "live" : "pairs on the board")
            } header: { Text("Sources") } footer: { Text("Live heart rate comes from the Apple Watch (via this phone), a Bluetooth heart-rate sensor paired with this phone, or a strap paired on the BikeComputer. The coach uses whichever is live; nothing is shown without a live source.") }
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
    @State private var preview: PreviewRef? = nil
    var body: some View {
        Form {
            Section {
                // RC3 / ENG-E1: an unknown FTP stays "Unknown" — never a number from weight × level
                LabeledContent("FTP", value: "\(store.profile.ftpDisplay) · \(store.profile.ftpSource.title)")
                    .accessibilityIdentifier("ftpValue")
                HStack {
                    TextField("FTP in watts", text: $ftpText).keyboardType(.numberPad)
                    // a typed value is "Entered" — only a recorded FTP test ride with verified power is "Tested"
                    Button("Set") { if let v = Int(ftpText), v >= 50, v <= 600 { preview = store.changeTraining(cause: .ftp) { $0.profile.setFTP(v, source: .entered) }; ftpText = "" } }
                        .disabled(Int(ftpText).map { $0 < 50 || $0 > 600 } ?? true).frame(minHeight: DS.minTap)
                }
                if store.profile.ftpKnown {
                    Button("I don't know my FTP") { preview = store.changeTraining(cause: .ftp) { $0.profile.setFTP(nil, source: .unknown) } }.font(.footnote)
                }
                if let s = store.ftpSuggestion { Text("Suggested from your \(s.rideDate.dayAndDate) ride: \(s.watts) W. Accept it on Home or Progress.").font(.footnote).foregroundStyle(BC.accent) }
            } header: { Text("FTP") } footer: { Text(store.profile.ftpKnown ? ftpMethod : "Rides use heart rate and effort until you enter an FTP or do an FTP test.") }
            if store.profile.ftpKnown {
                Section("Power zones") {
                    ZoneBar()
                    ForEach(Array(store.profile.powerZones.enumerated()), id: \.offset) { i, z in
                        HStack { ZonePill(z: i + 1); Text(PowerZones.names[i].dropFirst(3)).font(.footnote); Spacer(); Text("\(z.lo)–\(z.hi.map(String.init) ?? "∞") W").font(.footnote).monospacedDigit() }
                    }
                }
            }
            Section {
                LabeledContent("Power meter", value: meterText)
                Pill(text: "power unverified until validated", color: BC.stale)
                Text("Cyclift does not calibrate power meters: it only reads them and never writes to the meter's control point (safety rule). Pair and forget the meter on the board's Connections › Power meter.").font(.footnote).foregroundStyle(.secondary)
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
        .sheet(item: $preview) { r in PlanChangeSheet(proposalId: r.id) }
    }
    private var ftpMethod: String {
        let p = store.profile
        return p.ftpSourceText + (p.ftpCaution.map { " " + $0 } ?? "")
    }
    private var meterText: String {
        guard device.state == .ready, let l = device.live else { return device.remembered ? "via the BikeComputer (not connected)" : "pairs on the board" }
        switch l.meterLink { case 4: return "connected (direct on the board)"; case 1: return "not paired"; case 2: return "searching"; case 3: return "connecting"; case 5: return "reconnecting"; default: return "off" }
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

/// Profile › Your data (Cyclift 1.0 has no accounts): where the data lives, export (JSON share sheet) and the local
/// wipe (App Review 5.1.1 v: everything the app stores can be deleted in-app; there is no server copy to delete).
/// The section only flips state owned by the Profile list: a sheet or alert attached to a row inside a List is torn
/// down when the list re-renders that row.
struct YourDataSection: View {
    @Binding var exportURL: URL?
    @Binding var confirmDelete: Bool
    @State private var exportError: String?
    let snapshot: () -> StoreFile

    var body: some View {
        Section {
            Label("Your data stays on this iPhone", systemImage: "iphone")
            Button { export() } label: { Label("Export my data", systemImage: "square.and.arrow.up") }.accessibilityIdentifier("exportData")
            if let e = exportError { Text(e).font(.footnote).foregroundStyle(BC.warn) }
            Button(role: .destructive) { confirmDelete = true } label: { Label("Delete all data on this phone", systemImage: "trash") }.accessibilityIdentifier("deleteAllData")
        } header: { Text("Your data") } footer: {
            Text("Profile, plan, rides, strength sessions and templates are stored only in Cyclift on this iPhone. Export creates one JSON file with all of it.")
        }
    }

    private func export() {
        exportError = nil
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]; enc.dateEncodingStrategy = .iso8601
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cyclift-export-\(Int(Date().timeIntervalSince1970)).json")
        do { try enc.encode(snapshot()).write(to: url, options: .atomic); exportURL = url }
        catch { exportError = "Export failed: \(error.localizedDescription)" }
    }
}
