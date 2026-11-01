import SwiftUI

/// First run — onboarding revision 7 (owner-approved design, 1 Nov 2026): an uncounted Welcome, then five screens.
///  1 About you + training · 2 Goals · 3 Your week · 4 Connections · 5 Your plan.
/// Every answer is written straight to the same data Profile › Training edits (ios/ENGINE_API_RC3.md): one source of truth.
/// No height and no health questionnaire (owner decision, rc3). Nothing unknown is invented: an FTP the athlete doesn't
/// know stays Unknown, equipment not set stays "Not sure" (provisional bodyweight plan).
struct OnboardingView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var watch: WatchLink
    @EnvironmentObject private var health: HealthAccess
    @State private var step = 0
    @State private var guestName = ""
    @State private var showDOB = false
    @State private var ftpText = ""
    @State private var healthResult: String?
    @State private var twoADay = false
    @State private var resumed = false
    static let screens = 5

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if step > 0 {
                    HStack(spacing: DS.s) {
                        ProgressView(value: Double(step), total: Double(Self.screens)).tint(BC.accent)
                        Text("\(step) of \(Self.screens)").font(.caption.weight(.semibold)).foregroundStyle(.secondary).accessibilityIdentifier("onboardingProgress")
                    }.padding(.horizontal).padding(.top, 6)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: DS.m) {
                        switch step {
                        case 0: welcome
                        case 1: aboutYou
                        case 2: goals
                        case 3: week
                        case 4: connections
                        default: yourPlan
                        }
                    }.padding(DS.l)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step > 1 { ToolbarItem(placement: .navigationBarLeading) { Button("Back") { step -= 1 }.accessibilityIdentifier("onboardingBack") } }
                if step == 4 { ToolbarItem(placement: .navigationBarTrailing) { Button("Skip") { step = 5 }.accessibilityIdentifier("onboardingSkip") } }
            }
            .onAppear(perform: resume)
            .onChange(of: step) { _, s in store.onboardingStage = s == 0 ? 0 : 100 + s }
        }
    }

    /// Resume where the athlete left off. r7 stages are stored as 101…105; build-121 stages (1…9) map to the r7 screen
    /// that now holds that question (REDESIGN_SPEC.md "Persistence and resume").
    private func resume() {
        guard !resumed else { return }
        resumed = true
        let s = store.onboardingStage
        if s >= 101 { step = min(Self.screens, s - 100) }
        else {
            switch s {
            case 1, 4: step = 1
            case 5: step = 2
            case 2, 3: step = 3
            case 6, 7, 8: step = 4
            case 9: step = 5
            default: step = 0
            }
        }
        if !store.profile.name.isEmpty { guestName = store.profile.name }
        twoADay = (store.availability?.days.contains { $0.cycles && $0.lifts }) ?? false
    }

    // MARK: Welcome (not counted)
    private var welcome: some View {
        VStack(alignment: .leading, spacing: DS.l) {
            HStack(spacing: 10) { CycliftMark(size: 44); Text("Cyclift").font(.system(.largeTitle, design: .rounded).weight(.bold)) }
            Text("Cycling and strength in one plan.").font(.title3).foregroundStyle(.secondary)
            TextField("First name", text: $guestName).textFieldStyle(.roundedBorder).textContentType(.givenName).accessibilityIdentifier("onboardingName")
            Button {
                store.guest = true
                let n = guestName.trimmingCharacters(in: .whitespaces)
                if !n.isEmpty { store.updateProfile { $0.name = n } }
                step = 1
            } label: { Text("Start").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.large).accessibilityIdentifier("onboardingContinue")
            Text("Everything stays on this iPhone.").font(.footnote).foregroundStyle(.secondary)
        }
    }

    // MARK: shared pieces
    private func header(_ t: String) -> some View {
        Text(t).font(.system(.title, design: .rounded).weight(.bold)).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
    }
    private func continueButton(_ label: String = "Continue", id: String = "onboardingNext", action: (() -> Void)? = nil) -> some View {
        Button { action?(); step += 1 } label: { Text(label).frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.large).accessibilityIdentifier(id)
    }
    private func row<V: View>(_ title: String, @ViewBuilder value: () -> V) -> some View {
        HStack(spacing: DS.s) { Text(title).foregroundStyle(.secondary); Spacer(minLength: DS.s); value() }.frame(minHeight: DS.minTap)
    }

    // MARK: 1 About you + training
    private var aboutYou: some View {
        VStack(alignment: .leading, spacing: DS.m) {
            header("About you")
            Card {
                row("Name") {
                    TextField("First name", text: Binding(get: { store.profile.name }, set: { v in store.updateProfile { $0.name = v } }))
                        .multilineTextAlignment(.trailing).textContentType(.givenName).accessibilityIdentifier("onbName")
                }
                Divider()
                Button { withAnimation { showDOB.toggle() } } label: {
                    row("Date of birth") { Text(store.profile.dateOfBirth.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "Add").foregroundStyle(store.profile.dateOfBirth == nil ? BC.accent : .primary) }
                }.buttonStyle(.plain).accessibilityIdentifier("onbDOB")
                if showDOB {
                    DatePicker("Date of birth", selection: Binding(get: { store.profile.dateOfBirth ?? Self.defaultDOB }, set: setDOB),
                               in: Self.dobRange, displayedComponents: .date)
                        .datePickerStyle(.wheel).labelsHidden()
                    Button("Done") { if store.profile.dateOfBirth == nil { setDOB(Self.defaultDOB) }; withAnimation { showDOB = false } }
                        .frame(maxWidth: .infinity, minHeight: DS.minTap).accessibilityIdentifier("onbDOBDone")
                }
                Divider()
                row("Weight") {
                    Stepper(value: Binding(get: { store.profile.weightKg }, set: { v in store.updateProfile { $0.weightKg = v; $0.refreshAssumption() } }),
                            in: 35...200, step: store.settings.units == .imperial ? 0.45359 : 0.5) {
                        Text(weightText).font(.body.monospacedDigit()).frame(maxWidth: .infinity, alignment: .trailing)
                    }.accessibilityIdentifier("onbWeight")
                }
                Picker("Units", selection: $store.settings.units) { ForEach(AppSettings.Units.allCases, id: \.self) { Text($0 == .imperial ? "lb" : "kg").tag($0) } }
                    .pickerStyle(.segmented).accessibilityIdentifier("onbUnits")
            }
            Card {
                CompactChoiceRow(title: "Training", options: TrainingMode.allCases, label: { $0 == .hybrid ? "Hybrid" : $0.title },
                                 selection: Binding(get: { store.profile.trainingMode }, set: setMode), identifier: "onbMode")
                if store.profile.trainingMode.includesCycling {
                    CompactChoiceRow(title: "Cycling level", options: RiderProfile.Level.allCases, label: Self.levelTitle,
                                     selection: Binding(get: { store.profile.level }, set: { v in store.updateProfile { $0.level = v; $0.refreshAssumption() } }), identifier: "onbCyclingLevel")
                        .padding(.leading, DS.s)
                }
                if store.profile.trainingMode.includesLifting {
                    CompactChoiceRow(title: "Strength level", options: StrengthPrefs.Experience.allCases, label: Self.strengthTitle,
                                     selection: Binding(get: { store.strengthPrefs.experience ?? .beginner }, set: { v in store.strengthPrefs.experience = v; store.updateProfile { $0.confirmStrengthLevel = nil } }), identifier: "onbStrengthLevel")
                        .padding(.leading, DS.s)
                }
                if store.profile.trainingMode == .hybrid {
                    CompactChoiceRow(title: "Priority", options: [TrainingPriority.cycling, .balanced, .strength], label: { $0.title },
                                     selection: Binding(get: { store.profile.priority }, set: { v in store.updateProfile { $0.priority = v } }), identifier: "onbPriority")
                        .padding(.leading, DS.s)
                }
            }
            continueButton(action: {
                // a strength level shown on screen is an answer (Beginner was visible as the default)
                if store.profile.trainingMode.includesLifting, store.strengthPrefs.experience == nil { store.strengthPrefs.experience = .beginner }
            })
        }
    }
    static let defaultDOB = Calendar.current.date(byAdding: .year, value: -35, to: Date()) ?? Date()
    static let dobRange: ClosedRange<Date> = (Calendar.current.date(byAdding: .year, value: -100, to: Date()) ?? Date())...(Calendar.current.date(byAdding: .year, value: -13, to: Date()) ?? Date())
    private func setDOB(_ d: Date) {
        store.updateProfile { $0.dateOfBirth = d; $0.birthYear = Calendar.current.component(.year, from: d) }
    }
    private var weightText: String {
        store.settings.units == .imperial ? String(format: "%.0f lb", store.profile.weightKg * 2.20462) : String(format: "%.1f kg", store.profile.weightKg)
    }
    static func levelTitle(_ l: RiderProfile.Level) -> String { switch l { case .beginner: return "Beginner"; case .intermediate: return "Intermediate"; case .advanced: return "Advanced" } }
    static func strengthTitle(_ e: StrengthPrefs.Experience) -> String { switch e { case .beginner: return "Beginner"; case .intermediate: return "Intermediate"; case .advanced: return "Advanced" } }
    private func setMode(_ m: TrainingMode) {
        store.updateProfile { p in
            p.trainingMode = m
            if m == .strength { p.priority = .strength } else if m == .cycling { p.priority = .cycling } else if p.priority != .balanced { p.priority = .balanced }
        }
    }

    // MARK: 2 Goals
    private struct GoalGroup: Identifiable { let id: String; let goals: [GoalID] }
    private var goalChoices: [GoalGroup] {
        var out: [GoalGroup] = []
        if store.profile.trainingMode.includesCycling { out.append(GoalGroup(id: "Cycling", goals: [.endurance, .power, .climbing, .sprint, .event])) }
        if store.profile.trainingMode.includesLifting { out.append(GoalGroup(id: "Strength", goals: [.strength, .muscle, .stamina, .maintain])) }
        out.append(GoalGroup(id: "General", goals: [.fitness]))
        return out
    }
    private var goals: some View {
        VStack(alignment: .leading, spacing: DS.m) {
            header("Goals")
            Text("Pick any. Star the main one.").font(.subheadline).foregroundStyle(.secondary)
            ForEach(goalChoices) { group in
                Card {
                    Eyebrow(t: group.id)
                    FlowRow {
                        ForEach(group.goals) { g in goalChip(g) }
                    }
                }
            }
            continueButton(action: {
                if store.profile.goals.isEmpty { applyGoals(store.profile.effectiveGoals, primary: store.profile.effectivePrimaryGoal) }
            })
        }
    }
    private func goalChip(_ g: GoalID) -> some View {
        let on = store.profile.goals.contains(g)
        let primary = on && store.profile.primaryGoal == g
        return HStack(spacing: 0) {
            Button { toggleGoal(g) } label: {
                HStack(spacing: 4) { if on { Image(systemName: "checkmark") }; Text(g.title) }
                    .padding(.horizontal, 12).frame(minHeight: DS.minTap)
            }
            .buttonStyle(.plain).accessibilityLabel(g.title).accessibilityAddTraits(on ? .isSelected : []).accessibilityIdentifier("goal-\(g.rawValue)")
            if on {
                Button { applyGoals(store.profile.goals, primary: g) } label: {
                    Image(systemName: primary ? "star.fill" : "star").frame(minWidth: DS.minTap, minHeight: DS.minTap)
                }
                .buttonStyle(.plain).accessibilityLabel(primary ? "\(g.title) is the main goal" : "Make \(g.title) the main goal").accessibilityIdentifier("goalStar-\(g.rawValue)")
            }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(on ? BC.accent : .primary)
        .background(on ? BC.accent.opacity(0.14) : Color(.tertiarySystemGroupedBackground), in: Capsule())
    }
    private func toggleGoal(_ g: GoalID) {
        var list = store.profile.goals
        if list.contains(g) { list.removeAll { $0 == g } } else { list.append(g) }
        let primary = store.profile.primaryGoal.flatMap { list.contains($0) ? $0 : nil } ?? list.first
        applyGoals(list, primary: primary)
    }
    private func applyGoals(_ list: [GoalID], primary: GoalID?) {
        let x = store.setGoals(list, primary: primary)
        store.updateProfile { $0 = x.profile }
        if store.strengthPrefs != x.strengthPrefs { store.strengthPrefs = x.strengthPrefs }
    }

    // MARK: 3 Your week
    private var mode: TrainingMode { store.profile.trainingMode }
    /// The week being edited: the saved one, else the engine's suggestion for these answers. Days are normalised to the
    /// training type (a ride day in Strength mode becomes a lift day, and so on) so switching type never loses a day.
    private var weekKinds: [DayKind] {
        let a = store.availability ?? WeeklyAvailability.suggested(for: store.profile)
        return a.days.map { d in normalise(d.cycles && d.lifts ? .both : d.cycles ? .ride : d.lifts ? .lift : .rest) }
    }
    private func normalise(_ k: DayKind) -> DayKind {
        switch (mode, k) {
        case (.cycling, .lift), (.cycling, .both): return .ride
        case (.strength, .ride), (.strength, .both): return .lift
        case (.hybrid, .both): return twoADay ? .both : .ride
        default: return k
        }
    }
    private var cycle: [DayKind] {
        switch mode {
        case .cycling: return [.ride, .rest]
        case .strength: return [.lift, .rest]
        case .hybrid: return twoADay ? [.ride, .lift, .both, .rest] : [.ride, .lift, .rest]
        }
    }
    private var rideMinutes: Int { store.profile.cyclingSessionMinutes ?? 60 }
    private var liftMinutes: Int { store.profile.strengthSessionMinutes ?? 45 }

    private var week: some View {
        let kinds = weekKinds
        let rides = kinds.filter { $0 == .ride || $0 == .both }.count
        let lifts = kinds.filter { $0 == .lift || $0 == .both }.count
        return VStack(alignment: .leading, spacing: DS.m) {
            header("Your week")
            Card {
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in
                        DayIconCell(dayName: WeeklyAvailability.dayNames[i], longDayName: WeeklyAvailability.longDayNames[i], kind: kinds[i]) { tapDay(i, kinds) }
                            .accessibilityIdentifier("onbDay\(i)")
                    }
                }
                HStack {
                    if mode.includesCycling { Label("\(rides)", systemImage: "bicycle").accessibilityLabel("\(rides) rides") }
                    if mode.includesLifting { Label("\(lifts)", systemImage: "dumbbell").accessibilityLabel("\(lifts) strength sessions") }
                    Spacer()
                    Text("Tap a day to change it").font(.caption).foregroundStyle(.secondary)
                }.font(.subheadline.weight(.semibold)).accessibilityIdentifier("onbWeekCounts")
                if let m = weekMismatch(rides: rides, lifts: lifts) {
                    Text(m).font(.footnote).foregroundStyle(BC.warn).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("onbWeekMismatch")
                }
                if mode == .hybrid {
                    Toggle("Two a day", isOn: Binding(get: { twoADay }, set: { v in twoADay = v; saveWeek(weekKinds) })).tint(BC.accent).frame(minHeight: DS.minTap)
                }
            }
            Card {
                if mode.includesCycling {
                    row("Ride length") {
                        Stepper(value: Binding(get: { rideMinutes }, set: { v in store.updateProfile { $0.cyclingSessionMinutes = v }; saveWeek(weekKinds) }), in: 20...300, step: 10) {
                            Text("\(rideMinutes) min").monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                        }.accessibilityIdentifier("onbRideMinutes")
                    }
                }
                if mode.includesLifting {
                    row("Strength length") {
                        Stepper(value: Binding(get: { liftMinutes }, set: { v in store.updateProfile { $0.strengthSessionMinutes = v; $0.confirmSessionLength = nil }; saveWeek(weekKinds) }), in: 15...120, step: 5) {
                            Text("\(liftMinutes) min").monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
                        }.accessibilityIdentifier("onbLiftMinutes")
                    }
                    CompactChoiceRow(title: "Equipment", options: EquipmentPreset.allCases, label: { $0.title },
                                     selection: Binding(get: { EquipmentPreset.of(store.equipment) }, set: { store.equipment = $0.apply(to: store.equipment) }), identifier: "onbEquipment")
                    Toggle("Supersets", isOn: Binding(get: { store.strengthPrefs.prefersSupersets ?? false }, set: { store.strengthPrefs.prefersSupersets = $0 }))
                        .tint(BC.accent).frame(minHeight: DS.minTap).accessibilityIdentifier("onbSupersets")
                }
            }
            continueButton(action: { saveWeek(weekKinds) })
        }
    }
    private func weekMismatch(rides: Int, lifts: Int) -> String? {
        if rides + lifts == 0 { return "Pick at least one training day." }
        if mode == .hybrid && rides == 0 { return "Hybrid needs at least one ride day." }
        if mode == .hybrid && lifts == 0 { return "Hybrid needs at least one strength day." }
        if rides + lifts == 7 && !kindsHaveRest { return "No rest day this week. You can still continue." }
        return nil
    }
    private var kindsHaveRest: Bool { weekKinds.contains(.rest) }
    private func tapDay(_ i: Int, _ kinds: [DayKind]) {
        var k = kinds
        let order = cycle
        let at = order.firstIndex(of: k[i]) ?? (order.count - 1)
        k[i] = order[(at + 1) % order.count]
        saveWeek(k)
    }
    /// Writes the week exactly as shown: one assignment per session at the session length, firm minutes (weekIsExplicit),
    /// the training days as preferred days, and the frequencies / weekly budgets the planner reads kept in step.
    private func saveWeek(_ kinds: [DayKind]) {
        let r = rideMinutes, l = liftMinutes
        let days: [DayAvailability] = kinds.map { k in
            switch k {
            case .ride: return DayAvailability(assignments: [DayAssignment(sport: .cycling, minutes: r)])
            case .lift: return DayAvailability(assignments: [DayAssignment(sport: .strength, minutes: l)])
            case .both: return DayAvailability(assignments: [DayAssignment(sport: .cycling, minutes: r), DayAssignment(sport: .strength, minutes: l)])
            case .rest: return DayAvailability(activity: .rest, minutes: 0)
            }
        }
        let a = WeeklyAvailability(days: days)
        if store.availability != a { store.availability = a }
        let rides = kinds.filter { $0 == .ride || $0 == .both }.count
        let lifts = kinds.filter { $0 == .lift || $0 == .both }.count
        store.updateProfile { p in
            p.weekIsExplicit = true
            p.preferredDays = kinds.indices.filter { kinds[$0] != .rest }
            if p.trainingMode.includesCycling, rides > 0 {
                p.cyclingDaysPerWeek = rides
                p.cyclingSessionMinutes = r
                p.hoursPerWeek = max(1, Int((Double(rides * r) / 60).rounded(.up)))
            }
            if p.trainingMode.includesLifting {
                p.liftDaysPerWeek = lifts
                p.strengthSessionMinutes = l
                p.liftingHoursPerWeek = lifts == 0 ? 0 : max(1, Int((Double(lifts * l) / 60).rounded(.up)))
            } else {
                p.liftDaysPerWeek = 0; p.liftingHoursPerWeek = 0
            }
        }
    }

    // MARK: 4 Connections
    private var connections: some View {
        VStack(alignment: .leading, spacing: DS.m) {
            header("Connections")
            Card {
                row("Apple Health") {
                    if !health.available { Text("Not available").foregroundStyle(.secondary) }
                    else if health.workoutWriteAuthorized { Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(BC.live) }
                    else {
                        Button("Connect") {
                            store.settings.appleHealthWanted = true
                            health.request { ok in healthResult = ok ? nil : "Not allowed. Change it in iOS Settings › Health." }
                        }.buttonStyle(.bordered).accessibilityIdentifier("onbHealth")
                    }
                }
                if let r = healthResult { Text(r).font(.caption).foregroundStyle(BC.stale) }
                Divider()
                Toggle(isOn: connectionBinding("watch")) {
                    VStack(alignment: .leading, spacing: 2) { Text("Apple Watch"); Text(watch.paired ? "Paired" : "Not paired").font(.caption).foregroundStyle(.secondary) }
                }.tint(BC.accent).accessibilityIdentifier("onbWatch")
                Divider()
                row("BikeComputer") {
                    if device.state == .ready { Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(BC.live) }
                    else {
                        Button(device.stage.isAttempt && device.stage != .waiting ? "Searching…" : "Connect") { device.connect() }
                            .buttonStyle(.bordered).accessibilityIdentifier("onbBoard")
                    }
                }
                if device.state == .scanning, !device.found.isEmpty {
                    ForEach(device.found, id: \.id) { f in Button("Connect to \(f.name)") { device.connect(to: f.id) }.frame(minHeight: DS.minTap) }
                }
                if mode.includesCycling {
                    Divider()
                    Toggle("Heart-rate strap", isOn: connectionBinding("strap")).tint(BC.accent).frame(minHeight: DS.minTap).accessibilityIdentifier("onbStrap")
                    Toggle("Power meter", isOn: connectionBinding("meter")).tint(BC.accent).frame(minHeight: DS.minTap).accessibilityIdentifier("onbMeter")
                }
            }
            if mode.includesCycling {
                Card {
                    CompactChoiceRow(title: "FTP", options: [FTPSource.unknown, .entered, .tested], label: { $0 == .unknown ? "Don't know" : $0.title },
                                     selection: Binding(get: { ftpChoice }, set: setFTPChoice), identifier: "onbFTP")
                    if store.profile.ftpKnown {
                        row("Watts") {
                            TextField("W", text: $ftpText).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(maxWidth: 90)
                                .onChange(of: ftpText) { _, v in if let n = Int(v), (50...600).contains(n) { store.updateProfile { $0.setFTP(n, source: ftpChoice == .tested ? .tested : .entered) } } }
                                .accessibilityIdentifier("onbFTPWatts")
                        }
                    } else {
                        Text("Rides use heart rate and effort until you know it.").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            continueButton()
        }
        .onAppear { if store.profile.ftpKnown { ftpText = "\(store.profile.ftpW)" } }
    }
    private var ftpChoice: FTPSource {
        switch store.profile.ftpSource { case .unknown: return .unknown; case .tested: return .tested; default: return .entered }
    }
    private func setFTPChoice(_ s: FTPSource) {
        switch s {
        case .unknown:
            store.updateProfile { $0.setFTP(nil, source: .unknown) }
            ftpText = ""
        default:
            let w = Int(ftpText).flatMap { (50...600).contains($0) ? $0 : nil } ?? (store.profile.ftpW > 0 ? store.profile.ftpW : 200)
            ftpText = "\(w)"
            store.updateProfile { $0.setFTP(w, source: s) }
        }
    }
    private func connectionBinding(_ key: String) -> Binding<Bool> {
        Binding(get: { store.settings.enabledConnections.contains(key) },
                set: { if $0 { store.settings.enabledConnections.insert(key) } else { store.settings.enabledConnections.remove(key) } })
    }

    // MARK: 5 Your plan
    private var yourPlan: some View {
        let kinds = weekKinds
        return VStack(alignment: .leading, spacing: DS.m) {
            header("Your plan")
            Card {
                HStack(spacing: 4) {
                    ForEach(0..<7, id: \.self) { i in DayIconCell(dayName: WeeklyAvailability.dayNames[i], longDayName: WeeklyAvailability.longDayNames[i], kind: kinds[i]) }
                }
                summaryRow("Training", mode == .hybrid ? "Hybrid · \(store.profile.priority.title)" : mode.title)
                summaryRow("Goal", store.profile.effectivePrimaryGoal.title)
                if mode.includesCycling { summaryRow("Rides", "\(rideMinutes) min · FTP \(store.profile.ftpDisplay)") }
                if mode.includesLifting { summaryRow("Strength", "\(liftMinutes) min · \(EquipmentPreset.of(store.equipment).title)") }
            }
            Card {
                Eyebrow(t: "Why this plan")
                ForEach(whyPoints, id: \.self) { p in
                    Label { Text(p).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "checkmark.circle").foregroundStyle(BC.accent) }
                        .font(.subheadline)
                }
            }.accessibilityIdentifier("onbWhy")
            Button(action: createPlan) { Text("Create plan").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).tint(BC.live).controlSize(.large).accessibilityIdentifier("onbCreatePlan")
        }
    }
    private func summaryRow(_ k: String, _ v: String) -> some View {
        HStack { Text(k).foregroundStyle(.secondary); Spacer(); Text(v).multilineTextAlignment(.trailing) }.font(.subheadline).frame(minHeight: 32)
    }
    /// At most three reasons, each true for this athlete's answers (engine rules ENG-D1, E1/E3, H1, C2, hybrid spacing).
    private var whyPoints: [String] {
        var out: [String] = []
        let kinds = weekKinds
        let lifts = kinds.filter { $0 == .lift || $0 == .both }.count
        let rides = kinds.filter { $0 == .ride || $0 == .both }.count
        if mode.includesLifting, lifts >= 1, lifts <= 3 { out.append("\(lifts) full-body strength session\(lifts == 1 ? "" : "s"), \(liftMinutes) min each.") }
        if mode == .hybrid, lifts > 0, rides > 0 { out.append("Hard rides are kept away from leg-heavy lifts.") }
        if mode.includesCycling, !store.profile.ftpKnown { out.append("Rides use heart rate and effort until your FTP is known.") }
        if mode.includesLifting, store.equipment.isProvisional { out.append("Bodyweight strength until you set your equipment.") }
        if mode.includesCycling, rides > 0, out.count < 3 { out.append("\(rides) ride\(rides == 1 ? "" : "s") a week, never longer than \(rideMinutes) min.") }
        if out.isEmpty { out.append("Built from the days and times you chose.") }
        return Array(out.prefix(3))
    }
    private func createPlan() {
        saveWeek(weekKinds)
        if store.profile.goals.isEmpty { applyGoals(store.profile.effectiveGoals, primary: store.profile.effectivePrimaryGoal) }
        store.onboardingStage = 0
        _ = store.regenerate(weekOf: Date(), replaceEdited: true)
        if let next = Calendar.current.date(byAdding: .day, value: 7, to: Date()) { _ = store.regenerate(weekOf: next, replaceEdited: true) }
        store.onboarded = true
    }
}

/// Onboarding r7 equipment presets mapped onto the one equipment record the planner reads (`EquipmentProfile`).
/// "Not sure" = not set → provisional bodyweight plan; a full gym is never assumed.
enum EquipmentPreset: String, CaseIterable, Hashable {
    case gym, home, bodyweight, notSure
    var title: String { switch self { case .gym: return "Gym"; case .home: return "Home"; case .bodyweight: return "Bodyweight"; case .notSure: return "Not sure" } }
    static let homeKit: Set<String> = ["dumbbell", "bench", "band", "pull-up bar", "kettlebell"]
    static var gymKit: Set<String> { Set(ExerciseCatalogue.equipmentOptions.filter { $0 != "bodyweight" }) }
    static func of(_ e: EquipmentProfile) -> EquipmentPreset {
        if !e.isSet { return .notSure }
        if e.owned.isEmpty { return .bodyweight }
        if e.owned.isSuperset(of: gymKit) { return .gym }
        return .home
    }
    /// Keeps the athlete's exclusions; replaces only what is owned.
    func apply(to e: EquipmentProfile) -> EquipmentProfile {
        switch self {
        case .gym: return EquipmentProfile(owned: Self.gymKit, excluded: e.excluded, confirmed: true)
        case .home: return EquipmentProfile(owned: Self.homeKit, excluded: e.excluded, confirmed: true)
        case .bodyweight: return EquipmentProfile(owned: [], excluded: e.excluded, confirmed: true)
        case .notSure: return EquipmentProfile(owned: [], excluded: e.excluded, confirmed: nil)
        }
    }
}
