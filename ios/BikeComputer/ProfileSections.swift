import SwiftUI

// MARK: - Profile pieces (rc3, owner 1 Nov): the single Profile screen's rows and the few pages behind them.
// Short labels, segmented choices, no explanation under every row. Each setting has exactly one home.

/// Short labels for the segmented controls (the long titles stay in the model for other screens).
enum ProfileText {
    static func mode(_ m: TrainingMode) -> String { switch m { case .cycling: return "Cycling"; case .strength: return "Strength"; case .hybrid: return "Hybrid" } }
    static func level(_ l: RiderProfile.Level) -> String { switch l { case .beginner: return "Beginner"; case .intermediate: return "Intermediate"; case .advanced: return "Advanced" } }
    static func recovery(_ r: RecoveryCapacity) -> String { switch r { case .low: return "Slow"; case .normal: return "Average"; case .high: return "Fast" } }
}

/// Initials, name and one line (type · level).
struct ProfileHeaderRow: View {
    let name: String
    let line: String
    let boardConnected: Bool
    var body: some View {
        HStack(spacing: DS.m) {
            ZStack {
                Circle().fill(BC.accent.opacity(0.18)).frame(width: 48, height: 48)
                Text(initials).font(.system(.title3, design: .rounded).weight(.bold)).foregroundStyle(BC.accent)
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? "Rider" : name).font(.title3.weight(.bold)).lineLimit(1)
                Text(line).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if boardConnected { Pill(text: "board connected", color: BC.live) }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
    private var initials: String { let p = name.split(separator: " "); return p.isEmpty ? "R" : p.prefix(2).map { String($0.prefix(1)).uppercased() }.joined() }
}

/// A small title above a full-width segmented control (onboarding r7 style).
struct ProfileSegmentRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            content.pickerStyle(.segmented).labelsHidden()
        }
        .padding(.vertical, 2)
    }
}

/// Seven small day icons: bicycle = ride, dumbbell = strength, both, crescent moon = rest.
struct AvailabilityIcons: View {
    let availability: WeeklyAvailability
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { i in
                let a = availability.days[i].activity
                Group {
                    switch a {
                    case .cycle: Image(systemName: "bicycle").foregroundStyle(BC.accent)
                    case .lift: Image(systemName: "dumbbell.fill").foregroundStyle(BC.accent)
                    case .both: HStack(spacing: 0) { Image(systemName: "bicycle"); Image(systemName: "dumbbell.fill") }.font(.system(size: 8)).foregroundStyle(BC.accent)
                    case .other: Image(systemName: "figure.mixed.cardio").foregroundStyle(BC.accent)
                    case .rest: Image(systemName: "moon.fill").foregroundStyle(.tertiary)
                    }
                }
                .font(.caption2)
                .frame(minWidth: 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((0..<7).map { "\(WeeklyAvailability.longDayNames[$0]) \(availability.days[$0].activity.title.lowercased())" }.joined(separator: ", "))
    }
}

// MARK: Training › Goal
struct GoalPage: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        List {
            ForEach(RiderProfile.Goal.onboardingChoices, id: \.self) { g in
                Button { store.updateProfile { $0.goal = g } } label: {
                    HStack {
                        Text(g.title).foregroundStyle(.primary)
                        Spacer()
                        if store.profile.goal == g { Image(systemName: "checkmark").foregroundStyle(BC.accent) }
                    }
                    .frame(minHeight: DS.minTap)
                }
                .accessibilityAddTraits(store.profile.goal == g ? .isSelected : [])
            }
        }
        .navigationTitle("Goal").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Training › Time
/// Sessions and hours per week (the same values onboarding sets).
/// TODO(rc3-engine): session length (minutes per session, onboarding r7, GR-03) when the profile stores it.
struct WeeklyTimePage: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        Form {
            if store.profile.trainingMode.includesCycling {
                Section("Cycling") {
                    Stepper("\(store.profile.cyclingDaysPerWeek) rides a week", value: Binding(get: { store.profile.cyclingDaysPerWeek }, set: { v in store.updateProfile { $0.cyclingDaysPerWeek = v } }), in: 1...6)
                    Stepper("\(store.profile.hoursPerWeek) h a week", value: Binding(get: { store.profile.hoursPerWeek }, set: { v in store.updateProfile { $0.hoursPerWeek = v } }), in: 1...25)
                }
            }
            if store.profile.trainingMode.includesLifting {
                Section("Strength") {
                    Stepper("\(store.profile.liftDaysPerWeek) lifts a week", value: Binding(get: { store.profile.liftDaysPerWeek }, set: { v in store.updateProfile { $0.liftDaysPerWeek = v } }), in: 1...6)
                    Stepper("\(store.profile.liftingHoursPerWeek) h a week", value: Binding(get: { store.profile.liftingHoursPerWeek }, set: { v in store.updateProfile { $0.liftingHoursPerWeek = v } }), in: 1...12)
                }
            }
        }
        .navigationTitle("Time").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Training › Preferences
/// Everything about how the coach programs that is not a core answer: recovery, hybrid plan, routines, exercises,
/// other sports and the coach's adjustments in force.
struct TrainingPreferencesPage: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        Form {
            Section {
                ProfileSegmentRow(title: "Recovery") {
                    Picker("Recovery", selection: Binding(get: { store.profile.recoveryCapacity ?? .normal }, set: { v in store.updateProfile { $0.recoveryCapacity = v }; store.rebuildFromHybridAnswers(newDays: false) })) {
                        ForEach(RecoveryCapacity.allCases, id: \.self) { Text(ProfileText.recovery($0)).tag($0) }
                    }
                }
                .accessibilityIdentifier("recoveryCapacity")
                NavigationLink { AdjustmentsView() } label: { LabeledContent("Coach adjustments", value: store.activeAdaptations.isEmpty ? (store.settings.autoAdapt ? "None" : "Off") : "\(store.activeAdaptations.count)") }
                if store.profile.trainingMode == .hybrid {
                    NavigationLink { HybridPlanEditor() } label: { Text("Hybrid plan") }.accessibilityIdentifier("hybridPlanLink")
                }
            }
            if store.profile.trainingMode.includesLifting {
                Section("Strength") {
                    NavigationLink { StrengthPrefsPage() } label: { LabeledContent("Programming", value: store.plannerContext().goal.title) }.accessibilityIdentifier("strengthProgramming")
                    NavigationLink { TemplatesView() } label: { LabeledContent("Routines", value: "\(store.templates.count)") }
                    NavigationLink { WeekdayRoutinesPage() } label: { LabeledContent("Routine per weekday", value: "\(store.weekdayRoutines.count)") }
                    NavigationLink { MyExercisesView() } label: { LabeledContent("My exercises", value: "\(store.customExercises.count)") }
                }
            }
            Section {
                NavigationLink { SportsPicker() } label: { LabeledContent("Other sports", value: "\(store.profile.sports.count)") }
            }
        }
        .navigationTitle("Preferences").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Settings › Ride & coach
struct RideCoachSettingsPage: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        Form {
            Section("Ride") {
                Toggle("Keep the screen on", isOn: $store.settings.keepScreenOn)
                Toggle("Phone records every ride", isOn: $store.settings.phoneOnlyMode)
                NavigationLink("Ride tiles") { TilePicker() }
            }
            Section("Coach") {
                Toggle("Coach during rides", isOn: $store.settings.coachEnabled)
                ProfileSegmentRow(title: "How much it talks") {
                    Picker("How much it talks", selection: $store.settings.coachTalk) { ForEach(AppSettings.CoachTalk.allCases, id: \.self) { Text($0.title).tag($0) } }
                }
                .disabled(!store.settings.coachEnabled)
            }
        }
        .navigationTitle("Ride & coach").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: Settings › Health & safety
/// rc3 (owner 1 Nov): there is no health questionnaire for new riders. What stays: an explicit pause ("I'm unwell"),
/// the stop-and-seek-advice notice, and — for riders who answered the old health check — their saved restriction, which
/// stays in force until they review it here. Pain reports, load limits and missing-sensor handling are engine rules and
/// are unchanged.
struct HealthSafetyPage: View {
    @EnvironmentObject private var store: Store

    static func summary(_ p: RiderProfile) -> String {
        switch p.readiness.screen {
        case .paused: return "Paused"
        case .stop, .needsClearance: return "Limited"
        default: return ""
        }
    }

    private var paused: Bool { store.profile.healthScreen?.currentIllness == true }
    /// Answers saved by an earlier version (not only the pause below).
    private var hasSavedAnswers: Bool {
        guard let s = store.profile.healthScreen else { return false }
        return !s.conditionKeys.isEmpty || s.clearedAt != nil || s.supervisedOnly
    }

    var body: some View {
        Form {
            Section {
                Toggle("Pause training", isOn: Binding(get: { paused }, set: { setPause($0) }))
                    .accessibilityIdentifier("healthPause")
            } footer: { Text("Unwell or injured? Nothing is planned while paused.") }
            if hasSavedAnswers {
                Section {
                    LabeledContent("Saved answers", value: statusText)
                    NavigationLink { HealthCheckView() } label: { Text("Review") }.accessibilityIdentifier("healthReview")
                } footer: { Text("Your earlier health answers still apply until you review them.") }
            }
            Section {
                Text("Stop and get medical advice if you feel chest pain, dizziness or unusual breathlessness.").font(.footnote)
            }
        }
        .navigationTitle("Health & safety").navigationBarTitleDisplayMode(.inline)
    }

    private var statusText: String {
        switch store.profile.readiness.screen {
        case .stop: return "See a doctor first"
        case .needsClearance: return "Easy to moderate only"
        case .cleared: return "Cleared"
        case .paused: return "Paused"
        case .clear, .notAnswered: return "No limits"
        }
    }

    /// Uses the existing illness pause of the health record (HealthScreen.currentIllness → status .paused: no sessions).
    /// TODO(rc3-engine): a dedicated pause flag; a pause set here creates a record whose other answers read "no".
    private func setPause(_ on: Bool) {
        var s = store.profile.healthScreen ?? HealthScreen()
        s.currentIllness = on
        if s.answeredAt == nil { s.answeredAt = Date() }
        store.updateProfile { $0.healthScreen = s }
        store.rebuildFromHybridAnswers(newDays: false)
        store.refreshRideSafety()
    }
}
