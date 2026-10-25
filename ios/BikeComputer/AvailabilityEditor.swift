import SwiftUI

/// Per-day sport assignment (0.7.0): for every day Cycling / Strength / Both / Rest / Flexible, each activity with its
/// type, planned duration and Fixed/Flexible; a readable weekly preview; a consistency check that explains conflicts
/// and asks which constraint to relax instead of adding days or exceeding hours.
struct AvailabilityEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    /// Onboarding embeds the editor without its own navigation chrome and gets the draft back through `onSave`.
    var embedded = false
    var onSave: ((WeeklyAvailability) -> Void)? = nil
    @State private var draft = WeeklyAvailability(days: Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7))
    @State private var loaded = false
    @State private var showPreview = false
    @State private var resolveConflicts = false
    @State private var changes: [String] = []

    var body: some View {
        if embedded { content } else {
            NavigationStack {
                content
                    .navigationTitle("Training days").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                        ToolbarItem(placement: .confirmationAction) { Button("Preview & save") { showPreview = true } }
                    }
            }
        }
    }

    private var content: some View {
        Form {
            Section {
                Text("Say what happens each day. The coach builds every week around these days and never adds a day or exceeds your hours; fixed activities are never moved or changed by the coach.").font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(0..<7, id: \.self) { i in DayEditorSection(day: $draft.days[i], index: i, mode: store.profile.trainingMode) }
            Section {
                LabeledContent("Cycling", value: "\(draft.cycleDays) day\(draft.cycleDays == 1 ? "" : "s") · \(Fmt.duration(minutes: draft.cycleMinutes)) of \(store.profile.hoursPerWeek) h")
                if store.profile.trainingMode.includesLifting { LabeledContent("Lifting", value: "\(draft.liftDays) day\(draft.liftDays == 1 ? "" : "s") · \(Fmt.duration(minutes: draft.liftMinutes))" + (store.profile.liftingHoursPerWeek > 0 ? " of \(store.profile.liftingHoursPerWeek) h" : "")) }
                LabeledContent("All training", value: Fmt.duration(minutes: draft.totalMinutes))
                let issues = draft.consistency(profile: store.profile)
                ForEach(issues, id: \.self) { Text($0).font(.footnote).foregroundStyle(BC.warn) }
                if embedded { Button { showPreview = true } label: { Text("Preview my week").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.accent) }
                Button("Reset to the suggestion from my profile") { draft = WeeklyAvailability.suggested(for: store.profile) }
            } header: { Text("Totals") }
        }
        .onAppear { if !loaded { draft = store.effectiveAvailability; loaded = true } }
        .sheet(isPresented: $showPreview) { WeekPreviewSheet(draft: draft, onConfirm: { save() }, onRelax: { option in relax(option) }) }
    }

    /// Applies one of the conflict options the rider chose (budget raise or trimming); the editor stays open to show it.
    private func relax(_ option: PlanConflict.Resolution) {
        switch option {
        case .raiseCycling(let minutes): store.updateProfile { $0.hoursPerWeek = (minutes + 59) / 60 }
        case .raiseLifting(let minutes): store.updateProfile { $0.liftingHoursPerWeek = (minutes + 59) / 60 }
        case .trim: draft = WeeklyAvailability.fit(draft, profile: store.profile).availability
        case .dropDay(let sport):
            // drop the shortest flexible day of that sport (never a fixed one)
            let idx = draft.days.enumerated().filter { d in d.element.assignments.contains { $0.sport == sport && !$0.fixed } }.min { ($0.element.assignments.filter { $0.sport == sport }.reduce(0) { $0 + $1.minutes }) < ($1.element.assignments.filter { $0.sport == sport }.reduce(0) { $0 + $1.minutes }) }?.offset
            if let i = idx { draft.days[i].assignments.removeAll { $0.sport == sport && !$0.fixed }; draft.days[i].syncLegacy() }
        }
    }
    private func save() {
        for i in 0..<7 { draft.days[i].assignments = draft.days[i].assignments.filter { $0.minutes > 0 }; draft.days[i].syncLegacy() }
        if let onSave { onSave(draft); dismiss(); return }
        store.availability = draft
        let c1 = store.regenerate(weekOf: Date(), replaceEdited: false)
        _ = store.regenerate(weekOf: Calendar.current.date(byAdding: .day, value: 7, to: Date())!, replaceEdited: false)
        changes = c1
        dismiss()
    }
}

/// One day: the mark (Cycling / Strength / Both / Rest / Flexible) and its activities.
struct DayEditorSection: View {
    @Binding var day: DayAvailability
    let index: Int
    let mode: TrainingMode
    var body: some View {
        Section {
            HStack { Text(WeeklyAvailability.longDayNames[index]).font(.headline); Spacer(); Pill(text: day.mark, color: day.isRest ? .secondary : BC.accent) }
            ForEach($day.assignments) { $a in AssignmentRow(assignment: $a, onDelete: { day.assignments.removeAll { $0.id == a.id }; day.syncLegacy() }) }
            HStack(spacing: 8) {
                if mode.includesCycling, !day.assignments.contains(where: { $0.sport == .cycling }) { Button { day.assignments.append(DayAssignment(sport: .cycling, cyclingType: nil, minutes: 60)); day.syncLegacy() } label: { Label("Ride", systemImage: "bicycle") }.buttonStyle(.bordered).controlSize(.small) }
                if mode.includesLifting, !day.assignments.contains(where: { $0.sport == .strength }) { Button { day.assignments.append(DayAssignment(sport: .strength, strengthType: nil, minutes: 40)); day.syncLegacy() } label: { Label("Lift", systemImage: "dumbbell") }.buttonStyle(.bordered).controlSize(.small) }
                if day.assignments.count < 4, !day.assignments.isEmpty { Button { day.assignments.append(DayAssignment(sport: day.assignments.last?.sport == .cycling ? .strength : .cycling, cyclingType: .recovery, strengthType: .custom, minutes: 30)); day.syncLegacy() } label: { Label("Another", systemImage: "plus") }.buttonStyle(.bordered).controlSize(.small) }
                Spacer()
                if day.isRest { Toggle("Flexible", isOn: $day.flexible).toggleStyle(.button).controlSize(.small).tint(BC.accent) }
            }
            if day.isRest { Text(day.flexible ? "Flexible day: the coach may place a session here when another day is missed." : "Rest day: nothing is ever planned here.").font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct AssignmentRow: View {
    @Binding var assignment: DayAssignment
    var onDelete: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: assignment.sport == .cycling ? "bicycle" : "dumbbell").foregroundStyle(BC.accent)
                if assignment.sport == .cycling {
                    Picker("Type", selection: Binding(get: { assignment.cyclingType }, set: { assignment.cyclingType = $0 })) { Text("Coach decides").tag(CyclingType?.none); ForEach(CyclingType.allCases, id: \.self) { Text($0.title).tag(CyclingType?.some($0)) } }.labelsHidden()
                } else {
                    Picker("Type", selection: Binding(get: { assignment.strengthType }, set: { assignment.strengthType = $0 })) { Text("Coach decides").tag(StrengthFocus?.none); ForEach(StrengthFocus.allCases, id: \.self) { Text($0.title).tag(StrengthFocus?.some($0)) } }.labelsHidden()
                }
                Spacer()
                Button(role: .destructive) { onDelete() } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).foregroundStyle(.secondary).frame(minWidth: 32, minHeight: 32)
            }
            HStack {
                Text(Fmt.duration(minutes: assignment.minutes)).monospacedDigit().font(.subheadline.weight(.semibold)).frame(minWidth: 72, alignment: .leading)
                Slider(value: Binding(get: { Double(assignment.minutes) }, set: { assignment.minutes = Int($0) }), in: 15...240, step: 5).tint(assignment.sport == .cycling ? BC.accent : BC.zone(5))
                Picker("", selection: $assignment.fixed) { Text("Flexible").tag(false); Text("Fixed").tag(true) }.pickerStyle(.segmented).frame(maxWidth: 150)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(assignment.title), \(Fmt.duration(minutes: assignment.minutes)), \(assignment.fixed ? "fixed" : "flexible")")
    }
}

extension PlanConflict {
    enum Resolution: Equatable { case raiseCycling(Int), raiseLifting(Int), trim, dropDay(DayAssignment.Sport) }
}

/// Readable preview of the week before saving, with the budget check. Conflicts must be resolved (or trimming
/// accepted) before Save; nothing is ever added or exceeded silently.
struct WeekPreviewSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let draft: WeeklyAvailability
    var onConfirm: () -> Void
    var onRelax: (PlanConflict.Resolution) -> Void
    var body: some View {
        let fit = WeeklyAvailability.fit(draft, profile: store.profile)
        let conflicts = draft.conflicts(profile: store.profile)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your week").font(.system(size: 26, weight: .bold, design: .rounded))
                    ForEach(0..<7, id: \.self) { i in PreviewDayRow(index: i, day: draft.days[i]) }
                    Card {
                        LabeledContent("Cycling", value: "\(draft.cycleDays) days · \(Fmt.duration(minutes: draft.cycleMinutes)) of \(store.profile.hoursPerWeek) h")
                        if store.profile.trainingMode.includesLifting { LabeledContent("Lifting", value: "\(draft.liftDays) days · \(Fmt.duration(minutes: draft.liftMinutes))" + (store.profile.liftingHoursPerWeek > 0 ? " of \(store.profile.liftingHoursPerWeek) h" : "")) }
                        LabeledContent("Fixed activities", value: "\(draft.fixedAssignments)")
                    }
                    if conflicts.isEmpty {
                        Text("Frequency, durations and both budgets agree.").font(.footnote).foregroundStyle(BC.live)
                        Button { onConfirm(); dismiss() } label: { Text("Save these days").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.live).controlSize(.large)
                    } else {
                        ForEach(conflicts) { c in conflictCard(c, trimmed: fit.trimmed) }
                        Text("The plan is generated only inside both budgets. If you keep the days as they are, the coach shortens the flexible activities exactly as listed above and tells you so in Plan.").font(.caption2).foregroundStyle(.secondary)
                        Button { onConfirm(); dismiss() } label: { Text("Save anyway (coach trims flexible days)").frame(maxWidth: .infinity) }.buttonStyle(.bordered).controlSize(.large)
                    }
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } } }
        }
    }
    private func conflictCard(_ c: PlanConflict, trimmed: [String]) -> some View {
        Card(accent: true) {
            HStack { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(BC.warn); Text(c.text).font(.footnote.weight(.semibold)).fixedSize(horizontal: false, vertical: true) }
            Text("Which should give? Nothing is saved until the week fits.").font(.caption).foregroundStyle(.secondary)
            Button { onRelax(c.sport == .cycling ? .raiseCycling(c.plannedMinutes) : .raiseLifting(c.plannedMinutes)); dismiss() } label: { Text("Raise the \(c.sport.rawValue) budget to \(Fmt.duration(minutes: ((c.plannedMinutes + 59) / 60) * 60))").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.bordered)
            Button { onRelax(.trim); dismiss() } label: { trimLabel(trimmed) }.buttonStyle(.bordered)
            if (c.sport == .cycling ? draft.cycleDays : draft.liftDays) > 1 {
                Button { onRelax(.dropDay(c.sport == .cycling ? .cycling : .strength)); dismiss() } label: { Text("Drop the shortest flexible \(c.sport.rawValue) day").frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.bordered)
            }
        }
    }
    private func trimLabel(_ trimmed: [String]) -> some View {
        VStack(alignment: .leading) {
            Text("Shorten the flexible days to fit").frame(maxWidth: .infinity, alignment: .leading)
            if !trimmed.isEmpty { Text(trimmed.joined(separator: " · ")).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}

struct PreviewDayRow: View {
    let index: Int
    let day: DayAvailability
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(WeeklyAvailability.dayNames[index]).font(.caption.weight(.heavy)).foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                if day.isRest { Text(day.flexible ? "Flexible" : "Rest").foregroundStyle(.secondary) }
                ForEach(day.assignments) { a in assignmentLine(a) }
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
    private func assignmentLine(_ a: DayAssignment) -> some View {
        HStack(spacing: 6) {
            Image(systemName: a.sport == .cycling ? "bicycle" : "dumbbell").font(.caption).foregroundStyle(BC.accent)
            Text(a.sport == .cycling ? (a.cyclingType?.title ?? "Ride · coach decides") : (a.strengthType?.title ?? "Strength · coach decides")).font(.subheadline).lineLimit(1).minimumScaleFactor(0.8)
            Spacer()
            Text(Fmt.duration(minutes: a.minutes)).font(.subheadline.weight(.semibold)).monospacedDigit()
            if a.fixed { Pill(text: "fixed", color: BC.stale) }
        }
    }
}

/// "Fix plan": the budget conflicts and trims for the week in force, with the same options (from the Plan summary).
struct FixPlanSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false
    var body: some View {
        let fit = store.fitReport
        NavigationStack {
            List {
                if fit.conflicts.isEmpty && fit.trimmed.isEmpty { Text("Your days fit both budgets. Nothing to fix.").foregroundStyle(.secondary) }
                ForEach(fit.conflicts) { c in
                    Section(c.sport == .cycling ? "Cycling budget" : "Lifting budget") {
                        Text(c.text).font(.footnote)
                        if !fit.trimmed.isEmpty { Text("Currently the coach shortens: " + fit.trimmed.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary) }
                        Button("Raise the budget to \(Fmt.duration(minutes: ((c.plannedMinutes + 59) / 60) * 60))") { if c.sport == .cycling { store.updateProfile { $0.hoursPerWeek = (c.plannedMinutes + 59) / 60 } } else { store.updateProfile { $0.liftingHoursPerWeek = (c.plannedMinutes + 59) / 60 } }; rebuild() }
                        Button("Edit my training days") { showEditor = true }
                        Button("Keep the trimmed version") { dismiss() }
                    }
                }
                let week = store.workouts(weekOf: Date())
                let s = PlanEngine.suggestions(for: week, hoursPerWeek: store.profile.hoursPerWeek) + PlanEngine.liftSuggestions(for: week, liftingHours: store.profile.liftingHoursPerWeek)
                if !s.isEmpty { Section("This week after your edits") { ForEach(s, id: \.self) { Text($0).font(.footnote) } } }
            }
            .navigationTitle("Fix plan").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showEditor) { AvailabilityEditor() }
        }
    }
    private func rebuild() { _ = store.regenerate(weekOf: Date(), replaceEdited: false); _ = store.regenerate(weekOf: Calendar.current.date(byAdding: .day, value: 7, to: Date())!, replaceEdited: false); dismiss() }
}
