import SwiftUI

// MARK: - Quality release: explicit session state, per-exercise Why? and Swap, strength preferences.
// Everything here reads the one query layer (TrainingLedger via store.status / store.ledger) and writes only through
// the Store's state transitions (markDone, revertToPlanned, deleteStrengthLog, applySwap), so every screen agrees.

/// The state of a planned session with the actions that state allows. Never says "completed" without evidence or an
/// explicit "Mark done"; a session planned for a later day can only be moved to today.
struct WorkoutStatusCard: View {
    @EnvironmentObject private var store: Store
    let workout: Workout
    /// Opens the detailed log for this session (convert a manual completion into a detailed log).
    var onAddDetails: (StrengthSession?) -> Void = { _ in }
    @State private var markDone = false
    @State private var confirmReopen = false

    var body: some View {
        let st = store.status(workout)
        let log = store.ledger.log(for: workout)
        let future = store.isFuture(workout)
        Card {
            HStack(alignment: .firstTextBaseline, spacing: DS.s) {
                Text(st.title).font(.headline).foregroundStyle(st.isCompleted ? BC.live : .primary)
                Spacer(minLength: DS.s)
                WorkoutStatusPill(status: st)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("sessionStatus-\(st.rawValue)")
            Text(Self.detail(st, workout: workout, log: log, future: future)).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let n = workout.migrationNote { Text(n).font(.caption).foregroundStyle(BC.stale).fixedSize(horizontal: false, vertical: true) }
            ActionRow(actions: actions(st, log: log, future: future))
        }
        .accessibilityIdentifier(st.isCompleted ? "sessionCompleted" : "sessionOpen")
        .sheet(isPresented: $markDone) { MarkDoneSheet(workout: workout) }
        .confirmationDialog("Reopen this session?", isPresented: $confirmReopen, titleVisibility: .visible) {
            if log != nil {
                Button("Keep the log as an extra session") { store.revertToPlanned(workout.id, deleteLinkedLogs: false) }
                Button("Delete the log (Undo available)", role: .destructive) { store.revertToPlanned(workout.id, deleteLinkedLogs: true) }
            } else {
                Button("Set back to planned") { store.revertToPlanned(workout.id, deleteLinkedLogs: false) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { Text(log != nil ? "The session goes back to planned. Its log can stay in your history as an extra session, or be deleted." : "The \"done\" mark is removed; nothing else changes.") }
    }

    static func detail(_ st: WorkoutStatus, workout w: Workout, log: StrengthSession?, future: Bool) -> String {
        switch st {
        case .planned:
            return future ? "Planned for \(w.date.dayAndDate). It can be started or marked done on that day — or move it to today." : "Not done yet. Start it, log it, or mark it done without details."
        case .started: return "Started — no set ticked yet."
        case .inProgress: return "In progress — sets are being recorded."
        case .completedLogged:
            guard let l = log else { return "Logged." }
            return "Logged \(l.date.dayAndDate) · \(l.minutes > 0 ? Fmt.duration(minutes: l.minutes) : "duration not recorded") · \(l.exerciseCount) exercises, \(l.setCount) sets" + (l.rpe.map { " · RPE \($0)" } ?? "")
        case .completedManual:
            if let l = log { return "Quick log \(l.date.dayAndDate) · \(l.minutes > 0 ? Fmt.duration(minutes: l.minutes) : "duration not recorded"). No exercises, so it does not count for progression." }
            return "Marked done without details" + (w.manualMinutes.map { " · \(Fmt.duration(minutes: $0))" } ?? " · duration not recorded") + ". No exercises, so it does not count for progression."
        case .importedHealth: return "Imported from Apple Health" + (log.map { " · \(Fmt.duration(minutes: $0.minutes))" } ?? "") + "."
        case .skipped: return "Skipped. It does not count as done."
        }
    }

    private func actions(_ st: WorkoutStatus, log: StrengthSession?, future: Bool) -> [ActionSpec] {
        var a: [ActionSpec] = []
        let id = workout.id
        switch st {
        case .planned:
            if future { a.append(ActionSpec(label: "Move to today", a11y: "Move this session to today", icon: "arrow.uturn.left", identifier: "moveToToday") { store.moveToToday(id) }) }
            else if workout.kind != .rest { a.append(ActionSpec(label: "Mark done", a11y: "Mark done without details", icon: "checkmark", identifier: "markDone") { markDone = true }) }
            a.append(ActionSpec(label: "Skip", a11y: "Skip this session", identifier: "skipSession") { var x = workout; x.skipped = true; store.edit(x) })
        case .skipped:
            a.append(ActionSpec(label: "Unskip", a11y: "Unskip this session", identifier: "unskipSession") { var x = workout; x.skipped = false; store.edit(x) })
        case .completedManual:
            if workout.kind == .strength { a.append(ActionSpec(label: "Add details", a11y: "Add exercises to this session", icon: "list.bullet", identifier: "addDetails") { onAddDetails(log) }) }
            a.append(ActionSpec(label: "Reopen", a11y: "Reopen: set back to planned", icon: "arrow.uturn.backward", identifier: "reopenSession") { confirmReopen = true })
        case .completedLogged, .importedHealth:
            a.append(ActionSpec(label: "Reopen", a11y: "Reopen: set back to planned", icon: "arrow.uturn.backward", identifier: "reopenSession") { confirmReopen = true })
        case .started, .inProgress:
            break
        }
        return a
    }
}

/// "Mark done" without details: the duration is optional and only stored when the rider types it.
struct MarkDoneSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    @State private var withDuration = false
    @State private var minutes = 30
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("I know how long it took", isOn: $withDuration).tint(BC.accent)
                    if withDuration { Stepper("\(Fmt.duration(minutes: minutes))", value: $minutes, in: 5...300, step: 5) }
                } footer: { Text("Cyclift records only what you enter: no sets, reps, weights or duration are made up. Add exercises later with Add details.") }
            }
            .navigationTitle("Mark done").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Mark done") { store.markDone(workout.id, minutes: withDuration ? minutes : nil); dismiss() }.accessibilityIdentifier("confirmMarkDone") }
            }
            .onAppear { minutes = max(5, workout.minutes) }
        }.presentationDetents([.medium])
    }
}

// MARK: - Per-exercise "Why?" (from the planner's actual decision factors)
struct ExerciseWhySheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    let entry: ExerciseEntry
    var body: some View {
        let lines = StrengthPlanner.why(entry: entry, workout: workout, ctx: store.plannerContext(), routineName: store.routine(for: workout)?.name)
        NavigationStack {
            List {
                ForEach(lines) { l in
                    VStack(alignment: .leading, spacing: DS.xs) {
                        Text(l.title).font(.subheadline.weight(.semibold))
                        Text(l.text).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.padding(.vertical, DS.xs).accessibilityElement(children: .combine)
                }
            }
            .navigationTitle(entry.name).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.presentationDetents([.medium, .large])
    }
}

// MARK: - Per-exercise Swap: alternatives the rider can actually do, then the reason (persisted)
struct SwapExerciseSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    let entry: ExerciseEntry
    @State private var chosen: Exercise? = nil
    @State private var reason: SwapReason = .todayOnly
    @State private var tempMode = 0   // 0 = next 3 sessions, 1 = 2 weeks
    @State private var result: String? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let r = result { done(r) } else if let c = chosen { reasonStep(c) } else { options }
            }
            .navigationTitle(result != nil ? "Swapped" : chosen == nil ? "Swap \(entry.name)" : "Why swap?").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { if result == nil { Button(chosen == nil ? "Cancel" : "Back") { if chosen == nil { dismiss() } else { chosen = nil } } } }
                ToolbarItem(placement: .confirmationAction) { if result != nil { Button("Done") { dismiss() } } }
            }
        }
    }

    private var options: some View {
        let ctx = store.plannerContext()
        let opts = StrengthPlanner.alternatives(for: entry, in: workout, entries: store.plannedEntries(for: workout), ctx: ctx)
        return List {
            Section {
                if opts.isEmpty { Text("No alternative fits your equipment and restrictions. Add equipment in Profile › Training profile › Equipment.").font(.footnote).foregroundStyle(.secondary) }
                ForEach(opts) { o in
                    Button { chosen = o.exercise } label: {
                        VStack(alignment: .leading, spacing: DS.xs) {
                            HStack(spacing: DS.s) {
                                Text(o.exercise.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                if o.flagged { Pill(text: "check", color: BC.warn) }
                            }
                            Text(o.reasons.joined(separator: " · ")).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }.padding(.trailing, DS.l).frame(maxWidth: .infinity, minHeight: DS.minTap, alignment: .leading)
                        .overlay(alignment: .trailing) { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary).accessibilityHidden(true) }
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("swapOption-\(o.exercise.id)")
                }
            } header: { Text("Alternatives") } footer: { Text("Only exercises your equipment allows. Sets and reps stay the same; a weight is used only from your own logs of the new exercise.") }
        }
    }

    private func reasonStep(_ c: Exercise) -> some View {
        Form {
            Section { Text("\(entry.name) → \(c.name)").font(.headline) }
            Section {
                ForEach(SwapReason.allCases) { r in
                    Button { reason = r } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) { Text(r.title).foregroundStyle(.primary); Text(r.detail).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                            Spacer(minLength: DS.s)
                            if reason == r { Image(systemName: "checkmark").foregroundStyle(BC.accent) }
                        }.frame(minHeight: DS.minTap).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("swapReason-\(r.rawValue)").accessibilityAddTraits(reason == r ? .isSelected : [])
                }
                if reason == .temporarilyUnavailable {
                    Picker("For", selection: $tempMode) { Text("Next 3 sessions").tag(0); Text("2 weeks").tag(1) }.pickerStyle(.segmented)
                }
            } header: { Text("Reason") }
            Section {
                Button { apply(c) } label: { Text("Swap").frame(maxWidth: .infinity, minHeight: DS.minTap - 12) }.buttonStyle(.borderedProminent).tint(BC.accent).accessibilityIdentifier("confirmSwap")
            }
        }
    }

    private func done(_ r: String) -> some View {
        List { Section { Text(r).fixedSize(horizontal: false, vertical: true) } }
    }

    private func apply(_ c: Exercise) {
        let until: Date? = reason == .temporarilyUnavailable && tempMode == 1 ? Calendar.current.date(byAdding: .day, value: 14, to: Date()) : nil
        let sessions: Int? = reason == .temporarilyUnavailable && tempMode == 0 ? 3 : nil
        result = store.applySwap(workoutId: workout.id, entryId: entry.id, to: c, reason: reason, until: until, sessions: sessions) ?? "Nothing changed."
    }
}

// MARK: - Strength programming preferences (Profile › Training profile)
struct StrengthPrefsPage: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        let ctx = store.plannerContext()
        Form {
            Section {
                Picker("Experience", selection: Binding(get: { store.strengthPrefs.experience ?? ctx.experience }, set: { v in store.strengthPrefs.experience = v; store.refreshGeneratedSessions() })) {
                    ForEach(StrengthPrefs.Experience.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker("Strength goal", selection: Binding(get: { store.strengthPrefs.goal ?? ctx.goal }, set: { v in store.strengthPrefs.goal = v; store.refreshGeneratedSessions() })) {
                    ForEach(StrengthPrefs.Goal.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } header: { Text("Programming") } footer: { Text("Coach-built sessions use these with your cycling priority, equipment and logged sets. Your own routines and fixed days are never changed.") }
            Section("Excluded (discomfort)") {
                let avoided = store.strengthPrefs.avoid
                if avoided.isEmpty { Text("None").foregroundStyle(.secondary) }
                ForEach(avoided, id: \.exerciseId) { a in
                    HStack { Text(name(a.exerciseId)); Spacer(); Button("Allow again") { store.strengthPrefs.avoid.removeAll { $0.exerciseId == a.exerciseId }; store.refreshGeneratedSessions() }.font(.footnote.bold()).frame(minHeight: DS.minTap) }
                }
            }
            if !store.strengthPrefs.reviewFlags.isEmpty {
                Section {
                    ForEach(store.strengthPrefs.reviewFlags, id: \.self) { id in
                        HStack { Text(name(id)); Spacer(); Button("Fine for me") { store.strengthPrefs.reviewFlags.removeAll { $0 == id }; store.refreshGeneratedSessions() }.font(.footnote.bold()).frame(minHeight: DS.minTap) }
                    }
                } header: { Text("Flagged to check") } footer: { Text("These load the body like an exercise you said causes discomfort. They are used less until you clear them. If pain persists, get it checked by a doctor or physiotherapist.") }
            }
            Section("Always use instead") {
                if store.strengthPrefs.alwaysPrefer.isEmpty { Text("None").foregroundStyle(.secondary) }
                ForEach(store.strengthPrefs.alwaysPrefer.keys.sorted(), id: \.self) { k in
                    HStack { Text("\(name(k)) → \(name(store.strengthPrefs.alwaysPrefer[k] ?? ""))").fixedSize(horizontal: false, vertical: true); Spacer(); Button("Remove") { store.strengthPrefs.alwaysPrefer.removeValue(forKey: k); store.refreshGeneratedSessions() }.font(.footnote.bold()).frame(minHeight: DS.minTap) }
                }
            }
            let temp = store.strengthPrefs.temporary.filter { $0.active(now: Date()) }
            if !temp.isEmpty {
                Section("Temporarily unavailable") {
                    ForEach(temp) { t in
                        HStack { VStack(alignment: .leading) { Text(name(t.exerciseId)); Text(t.until.map { "until \($0.dayAndDate)" } ?? "\(t.sessionsLeft ?? 0) sessions left").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Available") { store.strengthPrefs.temporary.removeAll { $0.id == t.id }; store.refreshGeneratedSessions() }.font(.footnote.bold()).frame(minHeight: DS.minTap) }
                    }
                }
            }
        }
        .navigationTitle("Strength programming").navigationBarTitleDisplayMode(.inline)
    }
    private func name(_ id: String) -> String { store.allExercises.first { $0.id == id }?.name ?? id }
}
