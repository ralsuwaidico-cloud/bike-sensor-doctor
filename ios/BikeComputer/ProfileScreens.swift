import SwiftUI

// MARK: - Profile (V1): review and change settings — not a second questionnaire
//
// A compact header card, then grouped rows that open focused editors. The editors are the SAME views onboarding uses
// (ProfileEditors.swift) over the same authoritative profile; a change that affects planning ends in the before/after
// plan preview (current unfinished + future sessions only; completed workouts are never touched).

struct ProfileTabView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var hub: SensorHub
    @EnvironmentObject private var health: HealthAccess
    @State private var planPreview: PreviewRef? = nil
    @State private var equipmentAtOpen: EquipmentProfile? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CyTheme.sp4) {
                    Text("Profile").font(CyType.largeTitle).foregroundStyle(CyTheme.ink).accessibilityAddTraits(.isHeader)
                    NavigationLink { PersonalPage() } label: { headerCard }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(store.profile.name.isEmpty ? "Rider" : store.profile.name), \(headerLine). Account and personal details")
                        .accessibilityIdentifier("profileHeader")

                    CyCaption(text: "Training & goals")
                    CyRowGroup {
                        nav("Type & experience", value: typeLine, icon: "figure.mixed.cardio", id: "profileType") { TypeExperiencePage() }
                        CyDivider()
                        nav("Goals", value: ProfileText.goals(store.profile), icon: "target", sport: .goal, id: "profileGoal") { GoalsPage() }
                    }

                    CyCaption(text: "Week & preferences")
                    CyRowGroup {
                        nav("Your week", value: weekLine, icon: "calendar", id: "profileWeek") { WeekPage() }
                        if store.profile.trainingMode.includesLifting {
                            CyDivider()
                            nav("Equipment", value: equipmentText, icon: "dumbbell.fill", sport: .strength, id: "profileEquipment") {
                                EquipmentPage()
                                    .onAppear { if equipmentAtOpen == nil { equipmentAtOpen = store.equipment } }
                                    .onDisappear { proposeEquipment() }
                            }
                        }
                        if store.profile.trainingMode.includesCycling {
                            CyDivider()
                            nav("FTP", value: "\(store.profile.ftpDisplay) · \(store.profile.ftpSource.title)", icon: "bolt.fill", sport: .cycling, id: "profileFTP") { PowerCyclingPage() }
                            CyDivider()
                            nav("Heart rate", value: store.profile.maxHRForZones.map { "max \($0)\(store.profile.maxHRIsEstimate ? " (est.)" : "")" } ?? "zones not set", icon: "heart.fill", id: "profileHeartRate") { HeartRatePage() }
                        }
                        CyDivider()
                        nav("Preferences", value: nil, icon: "slider.horizontal.3", id: "profilePreferences") { TrainingPreferencesPage() }
                    }

                    CyCaption(text: "Devices & data")
                    CyRowGroup {
                        nav("Devices & sensors", value: devicesLine, icon: "applewatch", id: "profileDevices") { DevicesScreen() }
                        CyDivider()
                        nav("Apple Health", value: healthLine, icon: "heart.text.square.fill", sport: .recovery, id: "profileHealth") { HealthConnectionDetail() }
                    }

                    CyCaption(text: "App")
                    CyRowGroup {
                        nav("Health & safety", value: HealthSafetyPage.summary(store.profile).isEmpty ? "Pause training" : HealthSafetyPage.summary(store.profile), icon: "cross.case.fill", id: "settingsHealthSafety") { HealthSafetyPage() }
                        CyDivider()
                        nav("Settings", value: "Units · alerts · appearance · data", icon: "gearshape.fill", id: "profileSettings") { SettingsPage() }
                    }
                    Text("Cyclift \(AppInfo.label)").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3).frame(maxWidth: .infinity).padding(.top, 4)
                }
                .padding(.horizontal, CyTheme.margin).padding(.top, 8).padding(.bottom, 24)
                .frame(maxWidth: CyTheme.maxContentWidth)
                .frame(maxWidth: .infinity)
            }
            .background(CyTheme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $planPreview) { r in PlanChangeSheet(proposalId: r.id) }
        }
    }

    private func nav<D: View>(_ title: String, value: String?, icon: String, sport: CySport? = nil, id: String, @ViewBuilder destination: @escaping () -> D) -> some View {
        NavigationLink { destination() } label: {
            HStack(spacing: 12) {
                CyIconBox(systemName: icon, sport: sport)
                Text(title).font(CyType.body).foregroundStyle(CyTheme.ink).lineLimit(2)
                Spacer(minLength: 8)
                if let v = value { Text(v).font(CyType.secondary).foregroundStyle(CyTheme.ink2).multilineTextAlignment(.trailing).lineLimit(2) }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(CyTheme.ink3).accessibilityHidden(true)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(value.map { "\(title), \($0)" } ?? title)
        .accessibilityIdentifier(id)
    }

    private var headerCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(CyTheme.identity(store.profile.trainingMode == .strength ? .strength : .cycling).bg).frame(width: 48, height: 48)
                Text(initials).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(CyTheme.identity(store.profile.trainingMode == .strength ? .strength : .cycling).tint)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(store.profile.name.isEmpty ? "Rider" : store.profile.name).font(CyType.title).foregroundStyle(CyTheme.ink).lineLimit(1)
                Text(headerLine).font(CyType.secondary).foregroundStyle(CyTheme.ink2).lineLimit(2)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(CyTheme.ink3).accessibilityHidden(true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .cyCard()
    }
    private var initials: String { let p = store.profile.name.split(separator: " "); return p.isEmpty ? "R" : p.prefix(2).map { String($0.prefix(1)).uppercased() }.joined() }
    private var headerLine: String {
        let p = store.profile
        var parts = [ProfileText.mode(p.trainingMode)]
        if p.trainingMode.includesCycling { parts.append("ride \(ProfileText.level(p.level).lowercased())") }
        if p.trainingMode.includesLifting { parts.append("lift \(ProfileText.strengthLevel(store.strengthPrefs.experience ?? .beginner).lowercased())") }
        return parts.joined(separator: " · ")
    }
    private var typeLine: String {
        let p = store.profile
        return p.trainingMode == .hybrid ? "Hybrid · \(p.priority.title.lowercased())" : ProfileText.mode(p.trainingMode)
    }
    private var weekLine: String {
        let p = store.profile
        let days = store.effectiveAvailability.days.filter { $0.cycles || $0.lifts }.count
        var parts = ["\(days) day\(days == 1 ? "" : "s")"]
        if p.trainingMode.includesCycling { parts.append("ride \(p.cyclingSessionMinutes.map { "\($0)" } ?? "–")") }
        if p.trainingMode.includesLifting { parts.append("lift \(p.strengthSessionMinutes.map { "\($0) min" } ?? "–")") }
        return parts.joined(separator: " · ")
    }
    private var equipmentText: String {
        let e = store.equipment
        var s = e.isProvisional ? "Not sure yet" : e.owned.isEmpty ? "Bodyweight only" : EquipmentPreset.of(e) == .gym ? "Gym" : "\(e.owned.count) items"
        if store.strengthPrefs.prefersSupersets == true { s += " · supersets" }
        return s
    }
    private var devicesLine: String {
        let n = hub.deviceStates.values.filter { $0.state.isConnectedOrBetter }.count
        return n == 0 ? "none connected" : "\(n) connected"
    }
    private var healthLine: String { health.workoutWriteAuthorized ? (store.settings.healthReads.anyEnabled ? "On · reads on" : "On") : "Off" }

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
        planPreview = store.changeTraining(cause: .equipment) { $0.equipment = new }
    }
}

// MARK: - Focused editors (each is the onboarding editor over a local draft, saved through the plan preview)

/// Account & personal: name, date of birth (age + source + date), weight (source + date, Apple Health precedence).
struct PersonalPage: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var a = OnboardingAnswers()
    @State private var loaded = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CyTheme.sp4) {
                AthleteTypeEditor(a: $a, parts: [.name, .personal], healthWeight: nil, units: store.settings.units, dobLine: sourceLine(.dateOfBirth), weightLine: sourceLine(.weight))
                if store.profile.provenance(.weight).source == .appleHealth {
                    Text("Weight comes from Apple Health. Typing a value here overrides it until a newer Health sample arrives.").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3)
                }
                if store.profile.provenance(.dateOfBirth).needsConfirmation || store.profile.provenance(.weight).needsConfirmation {
                    CyBanner(kind: .warn, text: "A value came from an earlier version and could not be verified. Please confirm or re-enter it.", systemImage: "questionmark.circle")
                }
                CyPrimaryButton(title: "Save", isEnabled: changed, action: save).accessibilityIdentifier("personalSave")
            }
            .padding(.horizontal, CyTheme.margin).padding(.vertical, 12).frame(maxWidth: CyTheme.maxContentWidth).frame(maxWidth: .infinity)
        }
        .background(CyTheme.canvas.ignoresSafeArea())
        .navigationTitle("Personal").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            a.name = store.profile.name
            a.dateOfBirth = store.profile.dateOfBirth
            a.weightKg = store.profile.provenance(.weight).source == .unknown ? nil : store.profile.weightKg
        }
    }
    private var changed: Bool {
        (a.name ?? "") != store.profile.name || a.dateOfBirth != store.profile.dateOfBirth || a.weightKg != (store.profile.provenance(.weight).source == .unknown ? nil : store.profile.weightKg)
    }
    private func sourceLine(_ f: ProfileField) -> String? {
        let p = store.profile.provenance(f)
        let when = p.recordedAt.map { " · \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
        switch p.source {
        case .unknown: return f == .dateOfBirth ? "Not set · needed for heart-rate zones" : "Not set · needed for loads and W/kg"
        case .appleHealth: return "Apple Health\(when)"
        case .legacyUnverified: return "From an earlier version — please confirm\(when)"
        default: return "Entered by you\(when)"
        }
    }
    /// Name never touches the plan; a cleared date or weight is saved as Unknown (never a default).
    private func save() {
        store.updateProfile { p in
            if let n = a.name?.trimmingCharacters(in: .whitespaces) { p.name = n }
            if a.dateOfBirth != p.dateOfBirth { p.setDateOfBirth(a.dateOfBirth) }
            let cur = p.provenance(.weight).source == .unknown ? nil : p.weightKg
            if a.weightKg != cur { p.setWeight(a.weightKg) }
        }
        dismiss()
    }
}

/// Training type & experience (the Stage A cards and chips).
struct TypeExperiencePage: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var a = OnboardingAnswers()
    @State private var loaded = false
    @State private var preview: PreviewRef? = nil
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CyTheme.sp4) {
                AthleteTypeEditor(a: $a, parts: [.type, .experience], units: store.settings.units)
                Text("Changing the type keeps your days, goals and history; the plan is rebuilt after a preview.").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3)
                CyPrimaryButton(title: "Save", isEnabled: changed, action: save).accessibilityIdentifier("typeSave")
            }
            .padding(.horizontal, CyTheme.margin).padding(.vertical, 12).frame(maxWidth: CyTheme.maxContentWidth).frame(maxWidth: .infinity)
        }
        .background(CyTheme.canvas.ignoresSafeArea())
        .navigationTitle("Type & experience").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            a.mode = store.profile.trainingMode
            a.cyclingLevel = store.profile.level
            a.strengthLevel = store.strengthPrefs.experience
            a.priority = store.profile.trainingMode == .hybrid ? store.profile.priority : nil
        }
        .sheet(item: $preview) { r in PlanChangeSheet(proposalId: r.id) { dismiss() } }
    }
    private var changed: Bool {
        a.mode != store.profile.trainingMode || a.cyclingLevel != store.profile.level || a.strengthLevel != store.strengthPrefs.experience
            || (a.mode == .hybrid && (a.priority ?? .balanced) != store.profile.priority)
    }
    private func save() {
        var d = a
        if d.mode?.includesLifting == true, d.strengthLevel == nil { d.strengthLevel = .beginner }
        if d.mode == .hybrid, d.priority == nil { d.priority = .balanced }
        if let r = store.changeTraining(cause: .profile, { x in d.apply(to: &x) }) { preview = r } else { dismiss() }
    }
}

/// Goals & priorities (the Stage B cards).
struct GoalsPage: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var a = OnboardingAnswers()
    @State private var loaded = false
    @State private var preview: PreviewRef? = nil
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CyTheme.sp4) {
                GoalCardsEditor(a: $a, mode: store.profile.trainingMode)
                CyPrimaryButton(title: "Save", isEnabled: changed && !(a.goals ?? []).isEmpty, action: save).accessibilityIdentifier("goalsSave")
            }
            .padding(.horizontal, CyTheme.margin).padding(.vertical, 12).frame(maxWidth: CyTheme.maxContentWidth).frame(maxWidth: .infinity)
        }
        .background(CyTheme.canvas.ignoresSafeArea())
        .navigationTitle("Goals").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let choices = GoalInfo.choices(for: store.profile.trainingMode).flatMap(\.goals)
            a.goals = store.profile.effectiveGoals.filter { choices.contains($0) }
            a.primaryGoal = store.profile.primaryGoal.flatMap { (a.goals ?? []).contains($0) ? $0 : nil } ?? a.goals?.first
            a.priority = store.profile.priority
        }
        .sheet(item: $preview) { r in PlanChangeSheet(proposalId: r.id) { dismiss() } }
    }
    private var changed: Bool { a.goals != store.profile.effectiveGoals || a.primaryGoal != store.profile.effectivePrimaryGoal }
    private func save() {
        var d = OnboardingAnswers(); d.goals = a.goals; d.primaryGoal = a.primaryGoal
        if let r = store.changeTraining(cause: .goal, { x in d.apply(to: &x) }) { preview = r } else { dismiss() }
    }
}

/// Your week: days, session lengths, two-a-day, equipment preset, supersets (the Stage C builder).
struct WeekPage: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var a = OnboardingAnswers()
    @State private var loaded = false
    @State private var preview: PreviewRef? = nil
    var asSheet = false
    var body: some View {
        let content = ScrollView {
            VStack(alignment: .leading, spacing: CyTheme.sp4) {
                if loaded {
                    WeekBuilder(a: $a, mode: store.profile.trainingMode, preview: nil, proposalLabel: "Saved week",
                                baseline: OnboardingWeek.kinds(of: store.availability ?? store.effectiveAvailability, mode: store.profile.trainingMode, twoADay: true))
                }
                Text("Saving shows a before/after preview; only this week's unfinished sessions and future weeks change.").font(CyType.captionSmall).foregroundStyle(CyTheme.ink3)
                CyPrimaryButton(title: "Save", isEnabled: changed && !blocking, action: save).accessibilityIdentifier("weekSave")
            }
            .padding(.horizontal, CyTheme.margin).padding(.vertical, 12).frame(maxWidth: CyTheme.maxContentWidth).frame(maxWidth: .infinity)
        }
        .background(CyTheme.canvas.ignoresSafeArea())
        .navigationTitle("Your week").navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .sheet(item: $preview) { r in PlanChangeSheet(proposalId: r.id) { dismiss() } }
        if asSheet {
            NavigationStack { content.toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } }
        } else {
            content
        }
    }
    private func load() {
        guard !loaded else { return }
        let p = store.profile
        let mode = p.trainingMode
        a.mode = mode
        a.cyclingLevel = p.level
        a.strengthLevel = store.strengthPrefs.experience
        a.priority = p.priority
        let saved = OnboardingWeek.kinds(of: store.availability ?? store.effectiveAvailability, mode: mode, twoADay: true)
        a.week = saved
        a.rideMinutes = p.cyclingSessionMinutes
        a.liftMinutes = p.strengthSessionMinutes
        a.equipment = store.equipment.isSet ? EquipmentPreset.of(store.equipment) : .notSure
        a.supersets = store.strengthPrefs.prefersSupersets
        loaded = true
    }
    private var blocking: Bool { OnboardingWeek.feasibility(a.week ?? [], mode: store.profile.trainingMode, ride: a.rideMinutes ?? 60, lift: a.liftMinutes ?? 30, strengthLevel: a.strengthLevel).blocking }
    private var changed: Bool {
        let p = store.profile
        return a.week != OnboardingWeek.kinds(of: store.availability ?? store.effectiveAvailability, mode: p.trainingMode, twoADay: true)
            || a.rideMinutes != p.cyclingSessionMinutes || a.liftMinutes != p.strengthSessionMinutes
            || (a.equipment ?? .notSure) != (store.equipment.isSet ? EquipmentPreset.of(store.equipment) : .notSure)
            || (a.supersets ?? false) != (store.strengthPrefs.prefersSupersets ?? false)
    }
    private func save() {
        var d = OnboardingAnswers()
        d.week = a.week; d.rideMinutes = a.rideMinutes; d.liftMinutes = a.liftMinutes; d.equipment = a.equipment; d.supersets = a.supersets
        if let r = store.changeTraining(cause: .days, { x in d.apply(to: &x) }) { preview = r } else { dismiss() }
    }
}

// MARK: - Devices & sensors: real connection states, one clear action each

struct DevicesScreen: View {
    @EnvironmentObject private var hub: SensorHub
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CyTheme.sp4) {
                legend
                DeviceCardList()
                CyCaption(text: "In use now")
                VStack(spacing: 0) { InUseNowRows(hub: hub) }.padding(.horizontal, 6).cyCard()
                NavigationLink { PipelineDiagnosticsView() } label: {
                    HStack { Image(systemName: "stethoscope").foregroundStyle(CyTheme.ink2); Text("Diagnostics").font(CyType.body).foregroundStyle(CyTheme.ink); Spacer(); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(CyTheme.ink3) }
                        .padding(14).frame(minHeight: 56).cyCard()
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("connectionsDiagnostics")
            }
            .padding(.horizontal, CyTheme.margin).padding(.vertical, 12).frame(maxWidth: CyTheme.maxContentWidth).frame(maxWidth: .infinity)
        }
        .background(CyTheme.canvas.ignoresSafeArea())
        .navigationTitle("Devices & sensors").navigationBarTitleDisplayMode(.inline)
    }
    private var legend: some View {
        HStack(spacing: 10) {
            ForEach([CyDeviceState.paired, .connected, .receiving], id: \.self) { s in
                HStack(spacing: 4) {
                    Circle().fill(s == .paired ? CyTheme.cycling.tint : CyTheme.recovery.tint).frame(width: 7, height: 7)
                    Text(s.label).font(CyType.captionSmall).foregroundStyle(CyTheme.ink3)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Legend: paired means remembered; connected means reachable; receiving means measurements are arriving now")
    }
}

// MARK: - Settings: one home per app setting, plus data export / delete and About

struct SettingsPage: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var cloud: SyncEngine
    @State private var exportURL: URL?
    @State private var confirmDelete = false
    var body: some View {
        List {
            Section("Display") {
                Picker("Units", selection: $store.settings.units) { ForEach(AppSettings.Units.allCases, id: \.self) { Text($0 == .metric ? "Metric" : "Imperial").tag($0) } }
                Picker("Appearance", selection: $store.settings.appearance) { ForEach(AppSettings.Appearance.allCases, id: \.self) { Text($0.title).tag($0) } }
            }
            Section("Alerts") {
                Toggle("Ride notifications", isOn: $store.settings.backgroundNotice).accessibilityIdentifier("settingsNotifications")
                NavigationLink { RideCoachSettingsPage() } label: { Text("Ride & coach") }.accessibilityIdentifier("settingsRide")
            }
            YourDataSection(exportURL: $exportURL, confirmDelete: $confirmDelete, snapshot: { store.snapshot })
            Section("About") {
                LabeledContent("Version", value: "Cyclift \(AppInfo.label)")
                LabeledContent("Account", value: "Not needed")
                NavigationLink("Privacy policy") { LegalView(kind: .privacy) }
                NavigationLink("Terms of use") { LegalView(kind: .terms) }
                if let mail = SupportInfo.mailURL { Link(destination: mail) { HStack { Text("Contact support"); Spacer(); Image(systemName: "envelope").foregroundStyle(.secondary) } } }
                Link(destination: SupportInfo.supportPage) { HStack { Text("Support page"); Spacer(); Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary) } }
                if let e = store.lastSaveError { Text("Save problem: \(e)").font(.footnote).foregroundStyle(BC.warn) }
            }
        }
        .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $exportURL) { url in ShareSheet(items: [url]) }
        .alert("Delete everything on this phone?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { cloud.reset(); device.forget(); store.resetAll(); store.guest = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Profile, plan, ride history, strength logs, templates and the remembered BikeComputer are removed from this phone permanently. The BikeComputer keeps its own data; use Forget phone on the device too.")
        }
    }
}
