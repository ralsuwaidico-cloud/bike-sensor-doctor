import SwiftUI

// MARK: - Profile pieces (rc3, owner 1 Nov): the single Profile screen's rows and the few pages behind them.
// Short labels, segmented choices, no explanation under every row. Each setting has exactly one home.

// MARK: - One way to change training inputs (RC3 / ENG-J2)
extension Store {
    /// Every Profile / Plan control that changes what is planned calls this. The change is prepared as a proposal for the
    /// current unfinished session and future open sessions. Returns the preview to show (nothing saved yet), or nil when it
    /// was saved straight away: either nothing that affects planning changed, or no planned session changes (then the
    /// settings are applied with a plan version, no extra screen). Completed workouts are never in scope.
    func changeTraining(cause: PlanChangeCause, _ change: (inout PlanInputs) -> Void) -> PreviewRef? {
        proposeOrApplyPlanChange(cause: cause, change).map { PreviewRef(id: $0) }
    }
}

/// Short labels for the segmented controls (the long titles stay in the model for other screens).
enum ProfileText {
    static func mode(_ m: TrainingMode) -> String { switch m { case .cycling: return "Cycling"; case .strength: return "Strength"; case .hybrid: return "Hybrid" } }
    static func level(_ l: RiderProfile.Level) -> String { switch l { case .beginner: return "Beginner"; case .intermediate: return "Intermediate"; case .advanced: return "Advanced" } }
    static func recovery(_ r: RecoveryCapacity) -> String { switch r { case .low: return "Slow"; case .normal: return "Average"; case .high: return "Fast" } }
    static func strengthLevel(_ e: StrengthPrefs.Experience) -> String { switch e { case .beginner: return "Beginner"; case .intermediate: return "Intermediate"; case .advanced: return "Advanced" } }
    /// "Endurance" or "Endurance +1" (primary goal first).
    static func goals(_ p: RiderProfile) -> String {
        let g = p.effectiveGoals
        let first = p.effectivePrimaryGoal.title
        return g.count > 1 ? "\(first) +\(g.count - 1)" : first
    }
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

// MARK: Training › Goals (the same goals onboarding r7 asks; one is primary)
struct GoalPage: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var goals: [GoalID] = []
    @State private var primary: GoalID? = nil
    @State private var loaded = false
    @State private var preview: PreviewRef? = nil

    private var choices: [GoalID] {
        let m = store.profile.trainingMode
        return GoalID.allCases.filter { g in
            switch g.sport {
            case .cycling: return m.includesCycling
            case .strength: return m.includesLifting
            case .general: return true
            }
        }
    }

    var body: some View {
        List {
            Section {
                ForEach(choices) { g in
                    let on = goals.contains(g)
                    HStack {
                        Button { toggle(g) } label: {
                            HStack {
                                Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? BC.accent : .secondary)
                                Text(g.title).foregroundStyle(.primary)
                                Spacer()
                            }
                            .frame(minHeight: DS.minTap)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? [.isSelected] : [])
                        if on {
                            Button { primary = g } label: {
                                Image(systemName: primary == g ? "star.fill" : "star").foregroundStyle(primary == g ? BC.accent : .secondary)
                                    .frame(minWidth: DS.minTap, minHeight: DS.minTap)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(primary == g ? "\(g.title), main goal" : "Make \(g.title) the main goal")
                        }
                    }
                }
            } footer: { Text("★ = main goal") }
        }
        .navigationTitle("Goals").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.bold().disabled(goals.isEmpty || !changed).accessibilityIdentifier("goalsSave")
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            goals = store.profile.effectiveGoals.filter { choices.contains($0) }
            primary = store.profile.primaryGoal.flatMap { goals.contains($0) ? $0 : nil } ?? goals.first
        }
        .sheet(item: $preview) { r in PlanChangeSheet(proposalId: r.id) { dismiss() } }
    }

    private var changed: Bool { goals != store.profile.effectiveGoals || primary != store.profile.effectivePrimaryGoal }
    private func toggle(_ g: GoalID) {
        if let i = goals.firstIndex(of: g) { goals.remove(at: i); if primary == g { primary = goals.first } }
        else { goals.append(g); if primary == nil { primary = g } }
    }
    private func save() {
        let x = store.setGoals(goals, primary: primary)
        if let r = store.changeTraining(cause: .goal, { $0 = x }) { preview = r } else { dismiss() }
    }
}

// MARK: Training › Session length (r7: a firm maximum per session; sessions a week come from the Week)
struct WeeklyTimePage: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var ride = 60
    @State private var lift = 45
    @State private var loaded = false
    @State private var preview: PreviewRef? = nil
    static let rideOptions = [30, 45, 60, 90, 120]
    static let liftOptions = [20, 30, 45, 60, 75]

    var body: some View {
        Form {
            if store.profile.trainingMode.includesCycling {
                Section {
                    ProfileSegmentRow(title: "Ride") {
                        Picker("Ride", selection: $ride) { ForEach(options(Self.rideOptions, ride), id: \.self) { Text("\($0)").tag($0) } }
                    }
                    .accessibilityIdentifier("sessionRideMinutes")
                }
            }
            if store.profile.trainingMode.includesLifting {
                Section {
                    ProfileSegmentRow(title: "Strength") {
                        Picker("Strength", selection: $lift) { ForEach(options(Self.liftOptions, lift), id: \.self) { Text("\($0)").tag($0) } }
                    }
                    .accessibilityIdentifier("sessionLiftMinutes")
                } footer: { Text("Minutes. Every session is built to fit.") }
            }
        }
        .navigationTitle("Session length").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.bold().disabled(!changed).accessibilityIdentifier("sessionLengthSave")
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            ride = store.profile.cyclingSessionMinutes ?? 60
            lift = store.profile.strengthSessionMinutes ?? 45
        }
        .sheet(item: $preview) { r in PlanChangeSheet(proposalId: r.id) { dismiss() } }
    }

    /// The standard choices plus the saved value when it is not one of them.
    private func options(_ base: [Int], _ v: Int) -> [Int] { base.contains(v) ? base : (base + [v]).sorted() }
    private var changed: Bool {
        let p = store.profile
        return (p.trainingMode.includesCycling && p.cyclingSessionMinutes != ride) || (p.trainingMode.includesLifting && p.strengthSessionMinutes != lift)
    }
    private func save() {
        let mode = store.profile.trainingMode
        let r = store.changeTraining(cause: .minutes) { x in
            if mode.includesCycling { x.profile.cyclingSessionMinutes = ride }
            if mode.includesLifting { x.profile.strengthSessionMinutes = lift }
            x.profile.confirmSessionLength = nil
        }
        if let r { preview = r } else { dismiss() }
    }
}

// MARK: Training › Preferences
/// Everything about how the coach programs that is not a core answer: recovery, hybrid plan, routines, exercises,
/// other sports and the coach's adjustments in force.
struct TrainingPreferencesPage: View {
    @EnvironmentObject private var store: Store
    @State private var preview: PreviewRef? = nil
    var body: some View {
        Form {
            Section {
                ProfileSegmentRow(title: "Recovery") {
                    Picker("Recovery", selection: Binding(get: { store.profile.recoveryCapacity ?? .normal }, set: { v in preview = store.changeTraining(cause: .profile) { $0.profile.recoveryCapacity = v } })) {
                        ForEach(RecoveryCapacity.allCases, id: \.self) { Text(ProfileText.recovery($0)).tag($0) }
                    }
                }
                .accessibilityIdentifier("recoveryCapacity")
                NavigationLink { AdjustmentsView() } label: { LabeledContent("Coach adjustments", value: store.activeAdaptations.isEmpty ? (store.settings.autoAdapt ? "None" : "Off") : "\(store.activeAdaptations.count)") }
                if store.profile.trainingMode.includesLifting {
                    NavigationLink { HybridPlanEditor() } label: { LabeledContent("Strength split", value: store.profile.strengthSplit?.title ?? "Coach decides") }.accessibilityIdentifier("hybridPlanLink")
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
        .sheet(item: $preview) { r in PlanChangeSheet(proposalId: r.id) }
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
/// rc3 (owner 1 Nov): there is no health questionnaire for new riders. What stays: an explicit pause (unwell / injured /
/// away), the stop-and-seek-advice notice, and — for riders who answered the old health check — their saved restriction,
/// which stays in force until they review it here. Pain reports, load limits, the return-after-a-break ramp and
/// missing-sensor handling are engine rules and are unchanged (ios/SAFETY_CHANGES_RC3.md).
struct HealthSafetyPage: View {
    @EnvironmentObject private var store: Store

    static func summary(_ p: RiderProfile) -> String {
        if p.trainingPause != nil { return "Paused" }
        switch p.readiness.screen {
        case .paused: return "Paused"
        case .stop, .needsClearance: return "Limited"
        default: return ""
        }
    }

    /// Answers saved by an earlier version.
    private var hasSavedAnswers: Bool {
        guard let s = store.profile.healthScreen else { return false }
        return s.answeredAt != nil && (!s.conditionKeys.isEmpty || s.clearedAt != nil || s.supervisedOnly || s.currentIllness)
    }

    var body: some View {
        Form {
            Section {
                NavigationLink { TrainingPauseView().navigationTitle("Pause training").navigationBarTitleDisplayMode(.inline) } label: {
                    LabeledContent("Pause training", value: store.profile.trainingPause.map { "Paused · \($0.reason.title)" } ?? "Off")
                }
                .accessibilityIdentifier("healthPause")
            } footer: { Text("Unwell, injured or away? Nothing is planned while paused.") }
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
        case .paused: return "Paused (ill)"
        case .clear, .notAnswered: return "No limits"
        }
    }
}
