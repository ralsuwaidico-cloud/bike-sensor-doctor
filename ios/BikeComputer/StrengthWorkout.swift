import SwiftUI

// MARK: - Scheduled strength session (0.8.0): built around the assigned routine
/// Shows the routine's name and duration, exercises in order with planned sets × reps and the previous performance,
/// a prominent Start workout, one insight with Why?, and the secondary actions under More.
struct StrengthWorkoutScreen: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let workoutId: UUID
    @State private var chooseRoutine = false
    @State private var editEntries = false
    @State private var showMove = false
    @State private var showEdit = false
    @State private var confirmRemove = false
    @State private var showSession = false
    @State private var budgetNote: String? = nil
    @State private var quickLog = false
    @State private var showDetails = false
    @State private var detailsFor: DetailTarget = .new
    @State private var whyFor: ExerciseEntry? = nil
    @State private var swapFor: ExerciseEntry? = nil
    enum DetailTarget { case new, edit(StrengthSession) }

    private var workout: Workout? { store.plan.first { $0.id == workoutId } }

    var body: some View {
        NavigationStack {
            Group {
                if let w = workout { content(w) } else { ContentUnavailableView("Session removed", systemImage: "calendar.badge.minus") }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Strength").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if let w = workout, !store.status(w).isCompleted { ToolbarItem(placement: .topBarLeading) { moreMenu(w) } }
            }
            .sheet(isPresented: $chooseRoutine) { if let w = workout { ChooseRoutineSheet(workout: w) { note in budgetNote = note } } }
            .sheet(isPresented: $editEntries) { if let w = workout { PlannedSetsEditor(workout: w) } }
            .sheet(isPresented: $showMove) { if let w = workout { MoveWorkoutSheet(workout: w) } }
            .sheet(isPresented: $showEdit) { if let w = workout { EditWorkoutSheet(workout: w) } }
            .sheet(isPresented: $quickLog) { if let w = workout { QuickStrengthLogSheet(date: w.date, presetFocus: w.strengthFocus, workoutId: w.id) } }
            .sheet(isPresented: $showDetails) {
                if let w = workout {
                    switch detailsFor {
                    case .new: DetailedStrengthLogSheet(date: w.date, presetFocus: w.strengthFocus ?? .custom, workoutId: w.id)
                    case .edit(let s): DetailedStrengthLogSheet(date: s.date, presetFocus: s.focus, editing: s)
                    }
                }
            }
            .sheet(item: $whyFor) { e in if let w = workout { ExerciseWhySheet(workout: w, entry: e) } }
            .sheet(item: $swapFor) { e in if let w = workout { SwapExerciseSheet(workout: w, entry: e) } }
            .fullScreenCover(isPresented: $showSession) { StrengthSessionView() }
            .alert("Remove this session?", isPresented: $confirmRemove) { Button("Remove", role: .destructive) { if let w = workout { store.remove(w) }; dismiss() }; Button("Cancel", role: .cancel) {} } message: { Text("The routine template itself is kept.") }
            .onAppear { if store.activeSession != nil, store.activeSession?.workoutId == workoutId { showSession = true } }
        }
        .undoSnackbar()
    }

    @ViewBuilder private func content(_ w: Workout) -> some View {
        let routine = store.routine(for: w)
        let removed = store.isRoutineRemoved(w)
        let entries = removed ? [] : store.plannedEntries(for: w)
        let st = store.status(w)
        let closed = st.isCompleted || st == .skipped
        let future = store.isFuture(w)
        ScrollView {
            VStack(alignment: .leading, spacing: DS.m) {
                header(w, routine)
                if let note = budgetNote { Text(note).font(.footnote).foregroundStyle(BC.warn).fixedSize(horizontal: false, vertical: true) }
                // state first when it is not simply "open today": completed, skipped, or planned for a later day
                if closed || future { statusCard(w) }
                if removed { removedRoutine(w) } else if routine == nil && entries.isEmpty { noRoutine(w) } else {
                    if routine == nil, w.generatedEntries, !closed { coachBuiltLine(w) }
                    exercises(w, entries, editable: !closed && store.activeSession?.workoutId != w.id)
                }
                if w.coachAdjusted, !closed { Text("Adjusted by the coach — Home › Coach adjustments shows why, with Undo.").font(.footnote).foregroundStyle(BC.accent).fixedSize(horizontal: false, vertical: true) }
                if !closed, !future, !removed, routine != nil || !entries.isEmpty { startButton(w, entries) }
                if !closed && !future { statusCard(w) }
                // planner-built sessions already apply progression from the logs (Why? per exercise): no second suggestion on top
                if !closed && !w.plannerBuilt { InsightCard(workout: w, entries: entries) }
                if w.fixed { Text("Fixed day — the coach never moves or changes it.").font(.footnote).foregroundStyle(.secondary) }
            }.padding()
        }
    }

    private func statusCard(_ w: Workout) -> some View {
        WorkoutStatusCard(workout: w) { log in detailsFor = log.map { DetailTarget.edit($0) } ?? .new; showDetails = true }
    }

    /// One short line; the planner's reasons are behind (i) and the per-exercise Why?.
    private func coachBuiltLine(_ w: Workout) -> some View {
        HStack(alignment: .center, spacing: DS.xs) {
            Text("Built by the coach for you.").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            InfoButton(title: "How this session was built", text: (w.rationale?.notes ?? ["Built from your exercises and equipment."]).joined(separator: "\n\n") + "\n\nAdjust the sets, swap an exercise, or choose one of your routines under More.")
        }
    }

    private func header(_ w: Workout, _ r: WorkoutTemplate?) -> some View {
        VStack(alignment: .leading, spacing: DS.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    Text(r?.name ?? w.displayTitle).font(DS.screenTitle).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DS.s)
                    Text(Fmt.duration(minutes: w.minutes)).font(.title3.weight(.bold)).monospacedDigit()
                }
                VStack(alignment: .leading, spacing: DS.xs) {
                    Text(r?.name ?? w.displayTitle).font(DS.screenTitle).fixedSize(horizontal: false, vertical: true)
                    Text(Fmt.duration(minutes: w.minutes)).font(.title3.weight(.bold)).monospacedDigit()
                }
            }
            FlowRow {
                Text(w.date.dayAndDate).font(.footnote).foregroundStyle(.secondary)
                if let r { Pill(text: r.focus.title); Text("\(r.entries.count) exercises · \(r.setCount) sets").font(.footnote).foregroundStyle(.secondary) }
                if w.edited { Pill(text: "edited", color: BC.accent) }
                if w.routineManual { Pill(text: "your choice", color: BC.zone(5)) }
            }
            if let r, !w.done, r.estimatedMinutes != w.minutes {
                Text("Routine ≈ \(Fmt.duration(minutes: r.estimatedMinutes)); \(Fmt.duration(minutes: w.minutes)) counts toward your lifting budget.").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The assigned routine was deleted (here or on another device): say so, offer another one.
    private func removedRoutine(_ w: Workout) -> some View {
        Card {
            Eyebrow(t: "Routine removed")
            Text("The routine assigned to this session no longer exists. Choose another routine, or log the session without exercises.").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !w.done && !store.isFuture(w) {
                Button { chooseRoutine = true } label: { Label("Choose another routine", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.zone(5)).controlSize(.large).accessibilityIdentifier("chooseAnotherRoutine")
                Button { quickLog = true } label: { Text("Quick log without exercises").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
            }
        }
    }

    private func noRoutine(_ w: Workout) -> some View {
        Card {
            Eyebrow(t: "No routine assigned")
            Text(store.templates.isEmpty ? "Create a routine with your exercises and equipment, then assign it here. Until then this is a \(w.strengthFocus?.title.lowercased() ?? "strength") session of \(Fmt.duration(minutes: w.minutes)) without exercise detail." : "Choose one of your saved routines for this session, or set a default for every \(WeeklyAvailability.longDayNames[Store.weekdayIndex(w.date)]).").font(.footnote).foregroundStyle(.secondary)
            if !w.done {
                Button { chooseRoutine = true } label: { Label(store.templates.isEmpty ? "Create a routine" : "Choose routine", systemImage: "doc.on.doc").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.zone(5)).controlSize(.large)
                Button { quickLog = true } label: { Text("Quick log without exercises").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
            }
        }
    }

    private func exercises(_ w: Workout, _ entries: [ExerciseEntry], editable: Bool) -> some View {
        Card {
            HStack { Eyebrow(t: "Exercises in order"); Spacer(); if editable { Button("Adjust sets") { editEntries = true }.font(.footnote.bold()).buttonStyle(.tapTarget).accessibilityIdentifier("adjustSets") } }
            ForEach(entries) { e in
                VStack(alignment: .leading, spacing: DS.xs) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: DS.s) {
                            supersetBadge(e)
                            Text(e.name).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: DS.s)
                            Text(plannedText(e)).font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: DS.s) { supersetBadge(e); Text(e.name).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true) }
                            Text(plannedText(e)).font(.subheadline.weight(.semibold)).monospacedDigit()
                        }
                    }
                    Text(e.pattern.title + (e.restSeconds.map { " · rest \(RestPrescription.text($0))" } ?? "") + " · " + (previous(e).map { "last: \($0)" } ?? "no logged sets yet")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if !e.notes.isEmpty { Text(e.notes).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    HStack(spacing: DS.s) {
                        Button { whyFor = e } label: { Label("Why?", systemImage: "questionmark.circle").font(.footnote.weight(.semibold)).frame(minHeight: DS.minTap) }
                            .buttonStyle(.borderless).accessibilityLabel("Why \(e.name)?").accessibilityIdentifier("why-\(e.exerciseId)")
                        if editable {
                            Button { swapFor = e } label: { Label("Swap", systemImage: "arrow.triangle.2.circlepath").font(.footnote.weight(.semibold)).frame(minHeight: DS.minTap) }
                                .buttonStyle(.borderless).accessibilityLabel("Swap \(e.name)").accessibilityIdentifier("swap-\(e.exerciseId)")
                        }
                        Spacer(minLength: 0)
                    }
                }.padding(.vertical, DS.xs)
                if e.id != entries.last?.id { Divider() }
            }
        }
    }
    @ViewBuilder private func supersetBadge(_ e: ExerciseEntry) -> some View {
        if let g = e.superset { Text(g).font(.caption.weight(.heavy)).padding(4).background(BC.accent.opacity(0.18), in: Circle()).accessibilityLabel("superset \(g)") }
    }
    private func plannedText(_ e: ExerciseEntry) -> String {
        guard !e.sets.isEmpty else { return "—" }
        let reps = e.sets.map { $0.reps }
        let w = e.sets.compactMap { $0.bodyweight ? nil : $0.weightKg }.max()
        let r = Set(reps).count == 1 ? "\(e.sets.count) × \(reps[0])" : "\(e.sets.count) × \(reps.min()!)–\(reps.max()!)"
        return r + (w.map { " · \(WeightFmt.text($0, store.settings.units))" } ?? (e.sets.first?.bodyweight == true ? " · BW" : ""))
    }
    /// Last completed performance of this exercise (any session), compact.
    private func previous(_ e: ExerciseEntry) -> String? {
        for s in store.strength.sorted(by: { $0.date > $1.date }) {
            if let x = s.exercises?.first(where: { $0.exerciseId == e.exerciseId }), !x.doneSets.isEmpty {
                let f = DateFormatter(); f.dateFormat = "d MMM"
                return "\(x.summary(units: store.settings.units)) (\(f.string(from: s.date)))"
            }
        }
        return nil
    }

    private func startButton(_ w: Workout, _ entries: [ExerciseEntry]) -> some View {
        VStack(spacing: 6) {
            Button {
                if store.activeSession == nil { _ = store.startStrengthSession(for: w, template: store.routine(for: w), entries: entries) }
                showSession = true
            } label: { Label(store.activeSession?.workoutId == w.id ? "Resume workout" : "Start workout", systemImage: "play.fill").frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent).tint(BC.live).controlSize(.large).accessibilityIdentifier("startWorkout")
            .disabled(store.activeSession != nil && store.activeSession?.workoutId != w.id)
            if store.activeSession != nil, store.activeSession?.workoutId != w.id { Text("Another strength session is in progress; finish or discard it first.").font(.footnote).foregroundStyle(BC.warn).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func moreMenu(_ w: Workout) -> some View {
        Menu {
            Button { chooseRoutine = true } label: { Label(store.isRoutineRemoved(w) ? "Choose another routine" : store.routine(for: w) == nil ? "Choose routine" : "Replace routine", systemImage: "doc.on.doc") }
            if let r = store.routine(for: w) {
                let wd = Store.weekdayIndex(w.date)
                if store.weekdayRoutines[wd] != r.id { Button { budgetNote = store.setWeekdayRoutine(r, weekday: wd) } label: { Label("Set as every \(WeeklyAvailability.longDayNames[wd])", systemImage: "calendar.badge.plus") } }
                else { Button { _ = store.setWeekdayRoutine(nil, weekday: wd) } label: { Label("Stop using as \(WeeklyAvailability.longDayNames[wd]) default", systemImage: "calendar.badge.minus") } }
                Button(role: .destructive) { budgetNote = store.assign(template: nil, to: w) } label: { Label("Remove routine from this session", systemImage: "xmark.circle") }
            }
            Divider()
            Button { showEdit = true } label: { Label("Edit type / duration", systemImage: "pencil") }
            Button { showMove = true } label: { Label("Move to another day", systemImage: "arrow.left.arrow.right") }
            Button { var x = w; x.skipped.toggle(); store.edit(x) } label: { Label(w.skipped ? "Unskip" : "Skip", systemImage: "forward") }
            if !store.isFuture(w) { Button { quickLog = true } label: { Label("Quick log instead", systemImage: "bolt") } }
            Button(role: .destructive) { confirmRemove = true } label: { Label("Remove session", systemImage: "trash") }
        } label: { Label("More", systemImage: "ellipsis.circle") }.accessibilityIdentifier("moreMenu")
    }
}

// MARK: - Insight card: ONE suggestion/finding, Why?, Accept / Ignore / Undo
struct InsightCard: View {
    @EnvironmentObject private var store: Store
    let workout: Workout?
    let entries: [ExerciseEntry]
    @State private var showWhy = false
    @State private var askTemplate = false
    @State private var pendingInsight: WorkoutInsight? = nil

    var body: some View {
        let ins = store.insight(for: workout, entries: entries)
        let ignored = store.ignoredInsights.contains(ins.id)
        // Undo follows the change that was applied, even when the insight shown afterwards is a different one
        let applied = store.lastAcceptedInsight(for: workout?.id)
        Card {
            HStack { Eyebrow(t: "Next workout insight"); Spacer(); Pill(text: ins.label.rawValue, color: ins.label == .suggestion ? BC.accent : BC.stale) }
            if let a = applied {
                HStack(alignment: .firstTextBaseline) { Text("Applied to this session: \(a.text)").font(.footnote).fixedSize(horizontal: false, vertical: true); Spacer(); Button("Undo") { _ = store.undoLastProposal() }.buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("insightUndo") }
            }
            Text(ignored ? "Ignored: \(ins.text)" : ins.text).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true).foregroundStyle(ignored ? .secondary : .primary)
            Text("Evidence: \(ins.evidence)").font(.caption2).foregroundStyle(.secondary)
            DisclosureGroup(isExpanded: $showWhy) { Text(ins.why).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 2) } label: { Text("Why?").font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent) }
            if ins.kind != .insufficient {
                HStack(spacing: 8) {
                    if ins.change != nil, let w = workout, !w.done, !ignored, applied == nil { Button("Accept") { pendingInsight = ins; askTemplate = true }.buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.large).accessibilityIdentifier("insightAccept") }
                    if ignored { Button("Undo ignore") { store.unignoreInsight(ins.id) }.buttonStyle(.bordered).controlSize(.large) }
                    else if applied == nil { Button("Ignore") { store.ignoreInsight(ins) }.buttonStyle(.bordered).controlSize(.large).accessibilityIdentifier("insightIgnore") }
                    Spacer()
                }
            }
        }
        .confirmationDialog("Apply to this session only, or also update the template?", isPresented: $askTemplate, titleVisibility: .visible) {
            Button("This session only") { if let p = pendingInsight, let w = workout { _ = store.acceptInsight(p, for: w, alsoTemplate: false) } }
            Button("Also update my template") { if let p = pendingInsight, let w = workout { _ = store.acceptInsight(p, for: w, alsoTemplate: true) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Choose routine: assign a template to the session, optionally as the weekday default; create new
struct ChooseRoutineSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    var onAssigned: (String?) -> Void = { _ in }
    @State private var createNew = false
    @State private var asDefault = false
    var body: some View {
        let wd = Store.weekdayIndex(workout.date)
        NavigationStack {
            List {
                Section {
                    Toggle("Also use it every \(WeeklyAvailability.longDayNames[wd])", isOn: $asDefault).tint(BC.accent)
                } footer: { Text("A weekday default is reused when future weeks are generated, until you change it. Different days can have different routines.") }
                Section(store.templates.isEmpty ? "No routines yet" : "Your routines") {
                    ForEach(store.templates) { t in
                        Button {
                            var note = store.assign(template: t, to: workout)
                            if asDefault { note = store.setWeekdayRoutine(t, weekday: wd) ?? note }
                            onAssigned(note); dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) { Text(t.name).font(.body.weight(.semibold)).foregroundStyle(.primary); Pill(text: t.focus.title); if store.weekdayRoutines[wd] == t.id { Pill(text: "\(WeeklyAvailability.dayNames[wd]) default", color: BC.zone(5)) } }
                                    Text(t.exerciseNames).font(.caption).foregroundStyle(.secondary).clampLines(2)
                                    Text("\(t.entries.count) exercises · \(t.setCount) sets · ≈ \(Fmt.duration(minutes: t.estimatedMinutes))" + budgetHint(t)).font(.caption2).foregroundStyle(budgetHint(t).isEmpty ? .secondary : BC.warn)
                                }
                                Spacer(); if workout.templateId == t.id { Image(systemName: "checkmark").foregroundStyle(BC.accent) }
                            }.frame(minHeight: 44)
                        }
                    }
                    Button { createNew = true } label: { Label("Create a new routine", systemImage: "plus") }
                }
                if workout.templateId != nil { Section { Button(role: .destructive) { onAssigned(store.assign(template: nil, to: workout)); dismiss() } label: { Label("No routine for this session", systemImage: "xmark.circle") } } footer: { Text("Removes the assignment only; the template is kept.") } }
            }
            .navigationTitle("Choose routine").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $createNew) { TemplateEditor(template: nil) { t in var note = store.assign(template: t, to: workout); if asDefault { note = store.setWeekdayRoutine(t, weekday: wd) ?? note }; onAssigned(note); dismiss() } }
        }
    }
    private func budgetHint(_ t: WorkoutTemplate) -> String {
        let b = store.profile.liftingHoursPerWeek * 60
        guard b > 0 else { return "" }
        let others = PlanEngine.liftMinutes(store.workouts(weekOf: workout.date).filter { $0.id != workout.id })
        return others + t.estimatedMinutes > b ? " · over the \(Fmt.duration(minutes: b)) lifting budget" : ""
    }
}

// MARK: - Template editor: create or edit a routine directly (no completed session is created)
struct TemplateEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let template: WorkoutTemplate?
    var onSaved: (WorkoutTemplate) -> Void = { _ in }
    @State private var name = ""
    @State private var focus: StrengthFocus = .fullBody
    @State private var entries: [ExerciseEntry] = []
    @State private var minutes: Int? = nil
    @State private var showSearch = false
    @State private var expanded: UUID? = nil
    @State private var loaded = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Routine name (e.g. Short Full Body)", text: $name).accessibilityIdentifier("templateName")
                    Picker("Type", selection: $focus) { ForEach(StrengthFocus.allCases, id: \.self) { Text($0.title).tag($0) } }
                    HStack { Text("Planned duration"); Spacer(); Text(Fmt.duration(minutes: minutes ?? estimate)).monospacedDigit().foregroundStyle(.secondary) }
                    Slider(value: Binding(get: { Double(minutes ?? estimate) }, set: { minutes = Int($0) }), in: 10...180, step: 5).tint(BC.accent)
                    if minutes != nil { Button("Use the estimate (\(Fmt.duration(minutes: estimate)))") { minutes = nil }.font(.footnote) }
                } footer: { Text("The estimate is about 2.5 minutes per set plus a warm-up. The duration counts toward your lifting budget when the routine is on the calendar.") }
                Section {
                    if entries.isEmpty { Text("Add your exercises in the order you do them. Sets, reps and weights here are the plan; actual values are recorded in the workout.").font(.footnote).foregroundStyle(.secondary) }
                    ForEach($entries) { $e in ExerciseEntryRow(entry: $e, expanded: Binding(get: { expanded == e.id }, set: { expanded = $0 ? e.id : nil }), onDelete: { entries.removeAll { $0.id == e.id } }, units: store.settings.units) }
                    .onMove { entries.move(fromOffsets: $0, toOffset: $1) }
                    Button { showSearch = true } label: { Label("Add exercise", systemImage: "plus.circle.fill") }.accessibilityIdentifier("addExercise")
                    if entries.count >= 2 { supersets }
                } header: { HStack { Text("Exercises"); Spacer(); Text("\(entries.count) · \(entries.reduce(0) { $0 + $1.sets.count }) sets").font(.caption) } }
                if !store.equipment.isSet { Section { Text("Tip: list the equipment you own in Profile › Training profile › Equipment and the coach only suggests exercises you can do.").font(.footnote).foregroundStyle(.secondary) } }
            }
            .navigationTitle(template == nil ? "New routine" : "Edit routine").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || entries.isEmpty).accessibilityIdentifier("saveTemplate") }
                ToolbarItem(placement: .topBarLeading) { if !entries.isEmpty { EditButton() } }
            }
            .sheet(isPresented: $showSearch) { ExerciseSearchSheet { ex in
                var e = ExerciseEntry(exercise: ex, sets: (0..<3).map { _ in SetEntry(reps: 10, weightKg: nil, bodyweight: ex.equipment == ["bodyweight"], unilateral: ex.unilateral) })
                if let last = lastValues(for: ex) { e.sets = last }
                entries.append(e); expanded = e.id
            } }
            .onAppear { if !loaded { loaded = true; if let t = template { name = t.name; focus = t.focus; entries = t.entries; minutes = t.minutesEstimate } } }
        }
    }
    /// The saved template: the edit time moves only when the content changed (a rename keeps last session's weights).
    static func apply(name: String, focus: StrengthFocus, entries: [ExerciseEntry], minutes: Int?, to old: WorkoutTemplate?, now: Date = Date()) -> WorkoutTemplate {
        var t = old ?? WorkoutTemplate(name: "", entries: [], updatedAt: now)
        let changed = old == nil || old!.entries != entries || old!.focus != focus || old!.minutesEstimate != minutes
        t.name = name.trimmingCharacters(in: .whitespaces); t.focus = focus; t.entries = entries; t.minutesEstimate = minutes
        if changed { t.updatedAt = now }
        return t
    }
    private var estimate: Int { min(180, max(15, 5 + Int((Double(entries.reduce(0) { $0 + $1.sets.count }) * 2.5).rounded()))) }
    private var supersets: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Supersets").font(.caption.weight(.heavy)).foregroundStyle(.secondary)
            ForEach($entries) { $e in
                HStack { Text(e.name).font(.footnote).clampLines(1); Spacer()
                    Picker("", selection: Binding(get: { e.superset ?? "" }, set: { e.superset = $0.isEmpty ? nil : $0 })) { Text("—").tag(""); ForEach(["A", "B", "C", "D"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).frame(maxWidth: 190) }
            }
        }
    }
    private func lastValues(for ex: Exercise) -> [SetEntry]? {
        for s in store.strength.sorted(by: { $0.date > $1.date }) { if let e = s.exercises?.first(where: { $0.exerciseId == ex.id }), !e.sets.isEmpty { return e.sets.map { var t = $0; t.id = UUID(); t.done = true; return t } } }
        return nil
    }
    private func save() {
        let t = TemplateEditor.apply(name: name, focus: focus, entries: entries, minutes: minutes, to: template)
        store.saveTemplate(t)
        // future, open sessions using this routine follow its duration (completed and past sessions, and hand-edited
        // durations, are never changed). Their exercises follow automatically: plannedEntries reads the template.
        let today = Calendar.current.startOfDay(for: Date())
        for i in store.plan.indices where store.plan[i].templateId == t.id && !store.plan[i].done && !store.plan[i].edited && store.plan[i].date >= today { store.plan[i].minutes = t.estimatedMinutes }
        onSaved(t); dismiss()
    }
}

// MARK: - Adjust this session's planned sets (not the template)
struct PlannedSetsEditor: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    @State private var entries: [ExerciseEntry] = []
    @State private var expanded: UUID? = nil
    @State private var loaded = false
    var body: some View {
        NavigationStack {
            Form {
                Section { ForEach($entries) { $e in ExerciseEntryRow(entry: $e, expanded: Binding(get: { expanded == e.id }, set: { expanded = $0 ? e.id : nil }), onDelete: { entries.removeAll { $0.id == e.id } }, units: store.settings.units) }.onMove { entries.move(fromOffsets: $0, toOffset: $1) } } footer: { Text("Changes apply to this session only. The routine template stays as you saved it.") }
                Section { Button("Reset to the routine") { if let r = store.routine(for: workout) { entries = r.prefilled(from: store.lastSession(template: r)) } } }
            }
            .navigationTitle("This session's sets").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                // a hand change: flagged so the coach never overrides it (and a rebuild asks first)
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if let i = store.plan.firstIndex(where: { $0.id == workout.id }) { store.plan[i].plannedEntries = entries; store.plan[i].generatedEntries = false; store.plan[i].edited = true }; dismiss() } }
            }
            .onAppear { if !loaded { loaded = true; entries = store.plannedEntries(for: workout) } }
        }
    }
}

struct MoveWorkoutSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let workout: Workout
    var body: some View {
        NavigationStack {
            List {
                Section { ForEach(store.workouts(weekOf: workout.date).filter { $0.id != workout.id }) { o in
                    Button { store.swapDays(workout, o); dismiss() } label: { HStack { Text(o.date.dayAndDate).bold().foregroundStyle(.primary); Spacer(); Text("now \(o.displayTitle(routine: store.routine(for: o)))").font(.caption).foregroundStyle(.secondary) }.frame(minHeight: 44) }
                } } footer: { Text(workout.fixed ? "This is a fixed day; moving it is your decision, the coach never does it." : "The two days swap.") }
            }
            .navigationTitle("Move to").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

struct EditWorkoutSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var workout: Workout
    var body: some View {
        NavigationStack {
            Form {
                Section("Body region") { StrengthTypeGrid(focus: Binding(get: { workout.strengthFocus ?? .fullBody }, set: { workout.strengthFocus = $0 }), choices: StrengthFocus.allCases.filter { $0 != .custom }) }
                Section("Duration") { Text(Fmt.duration(minutes: workout.minutes)).font(BC.numFont).monospacedDigit(); Slider(value: Binding(get: { Double(workout.minutes) }, set: { workout.minutes = Int($0) }), in: 15...180, step: 5).tint(BC.accent) }
            }
            .navigationTitle("Edit session").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { store.edit(workout); dismiss() } }
            }
        }
    }
}

// MARK: - Workout session mode: record each set, see previous performance, pause / resume / finish; resumable
struct StrengthSessionView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var showFinish = false
    @State private var confirmDiscard = false
    @State private var rpe: Int? = nil
    @State private var notes = ""
    @State private var expanded: UUID? = nil
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var now = Date()
    /// Adaptive coach: the finished session waiting for its check-in (the finish sheet turns into the check-in).
    @State private var checkInFor: UUID? = nil

    var body: some View {
        NavigationStack {
            Group {
                if let s = store.activeSession { content(s) } else { ContentUnavailableView("No workout in progress", systemImage: "dumbbell") }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(store.activeSession?.customName.isEmpty == false ? store.activeSession!.customName : "Workout").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Finish") { showFinish = true }.bold().accessibilityIdentifier("finishWorkout") }
            }
            .onReceive(timer) { now = $0 }
            .sheet(isPresented: $showFinish) {
                if let id = checkInFor { CheckInFlow(target: .strength(id), initialEffort: rpe) { showFinish = false; dismiss() } }
                else { finishSheet }
            }
            .alert("Discard this workout?", isPresented: $confirmDiscard) { Button("Discard", role: .destructive) { store.discardActiveSession(); dismiss() }; Button("Cancel", role: .cancel) {} } message: { Text("Nothing is saved. The planned session stays open.") }
        }
    }

    @ViewBuilder private func content(_ s: StrengthSession) -> some View {
        let done = s.exercises?.reduce(0) { $0 + $1.doneSets.count } ?? 0, total = s.exercises?.reduce(0) { $0 + $1.sets.count } ?? 0
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Card {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) { Eyebrow(t: s.pausedAt != nil ? "Paused" : "Working time"); Text(clock(s.elapsedSeconds(now: now))).font(DS.number).monospacedDigit() }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) { Eyebrow(t: "Sets"); Text("\(done) / \(total)").font(.title2.weight(.bold)).monospacedDigit() }
                    }
                    HStack(spacing: 8) {
                        if s.pausedAt == nil { Button { store.pauseActiveSession() } label: { Label("Pause", systemImage: "pause.fill").frame(maxWidth: .infinity) }.buttonStyle(.bordered) }
                        else { Button { store.resumeActiveSession() } label: { Label("Resume", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.zone(5)) }
                        Button(role: .destructive) { confirmDiscard = true } label: { Text("Discard").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                    }
                    Text("Saved as you go — close Cyclift and come back later if you need to.").font(.caption2).foregroundStyle(.secondary)
                }
                ForEach(Array((s.exercises ?? []).enumerated()), id: \.element.id) { idx, e in exerciseCard(e, index: idx) }
                Button { showFinish = true } label: { Label("Finish workout", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.live).controlSize(.large)
            }.padding()
        }
    }

    private func exerciseCard(_ e: ExerciseEntry, index: Int) -> some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                if let g = e.superset { Text(g).font(.caption.weight(.heavy)).padding(4).background(BC.accent.opacity(0.18), in: Circle()) }
                Text(e.name).font(.body.weight(.bold)).fixedSize(horizontal: false, vertical: true); Spacer()
                Text("\(e.doneSets.count)/\(e.sets.count)").font(.caption.weight(.heavy)).monospacedDigit().foregroundStyle(e.doneSets.count == e.sets.count && !e.sets.isEmpty ? BC.live : .secondary)
            }
            if let prev = previousText(e) { Text("Previous: \(prev)").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } else { Text("No previous log for this exercise").font(.caption).foregroundStyle(.secondary) }
            ForEach(Array(e.sets.enumerated()), id: \.element.id) { si, st in
                LiveSetRow(number: si + 1, set: st, units: store.settings.units, onChange: { newSet in store.updateActiveSession { $0.exercises?[index].sets[si] = newSet } })
                if si < e.sets.count - 1 { Divider() }
            }
            HStack {
                Button { store.updateActiveSession { var n = $0.exercises?[index].sets.last ?? SetEntry(); n.id = UUID(); n.done = false; $0.exercises?[index].sets.append(n) } } label: { Label("Add set", systemImage: "plus") }.buttonStyle(.bordered).controlSize(.large)
                Spacer()
                if !e.notes.isEmpty { Text(e.notes).font(.caption2).foregroundStyle(.secondary).clampLines(1) }
            }
        }
    }
    private func previousText(_ e: ExerciseEntry) -> String? {
        for s in store.strength.sorted(by: { $0.date > $1.date }) { if let x = s.exercises?.first(where: { $0.exerciseId == e.exerciseId }), !x.doneSets.isEmpty { return x.doneSets.map { $0.text(units: store.settings.units) }.joined(separator: " · ") } }
        return nil
    }
    private func clock(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

    private var finishSheet: some View {
        let nothing = store.activeSession.map(Store.finishWouldSaveNothing) ?? false
        let planned = store.activeSession?.workoutId
        return NavigationStack {
            Form {
                if nothing {
                    Section {
                        Text("No set is ticked as done, so there is nothing to save as a workout log. Go back and tick the sets you did.").font(.footnote).foregroundStyle(BC.warn).fixedSize(horizontal: false, vertical: true)
                        if let wid = planned {
                            Button { store.discardActiveSession(); store.markDone(wid); showFinish = false; dismiss() } label: { Text("Mark done without details") }.accessibilityIdentifier("finishMarkDone")
                        }
                        Button(role: .destructive) { store.discardActiveSession(); showFinish = false; dismiss() } label: { Text("Discard — nothing is saved") }
                    } footer: { Text("Mark done records the session as done with no sets, weights or duration.") }
                } else {
                    Section("How did it feel?") {
                        Picker("Effort", selection: Binding(get: { rpe ?? 0 }, set: { rpe = $0 == 0 ? nil : $0 })) { Text("—").tag(0); ForEach(1...10, id: \.self) { Text("RPE \($0)").tag($0) } }
                        TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(2...4)
                    }
                    Section { Text("Only the sets you ticked are saved, with the measured working time.").font(.footnote).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("Finish workout").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { showFinish = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { if let s = store.finishActiveSession(rpe: rpe, notes: notes), store.strength.contains(where: { $0.id == s.id }) { checkInFor = s.id } else if store.activeSession == nil { showFinish = false; dismiss() } }
                        .bold().disabled(nothing).accessibilityIdentifier("saveWorkout")
                }
            }
        }.presentationDetents([.medium, .large])
    }
}

/// One set during a workout: tick when done, adjust actual reps / weight.
struct LiveSetRow: View {
    let number: Int
    let set: SetEntry
    var units: AppSettings.Units = .metric
    var onChange: (SetEntry) -> Void
    @State private var weightText = ""
    var body: some View {
        HStack(spacing: 8) {
            Button { var s = set; s.done.toggle(); onChange(s) } label: { Image(systemName: set.done ? "checkmark.circle.fill" : "circle").font(.system(size: 26)).foregroundStyle(set.done ? BC.live : .secondary).frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel(set.done ? "Set \(number) done" : "Mark set \(number) done")
            Text("Set \(number)").font(.footnote.weight(.semibold)).frame(width: 44, alignment: .leading)
            Stepper("", value: Binding(get: { set.reps }, set: { var s = set; s.reps = $0; onChange(s) }), in: 1...100).labelsHidden()
            Text("\(set.reps)\(set.unilateral ? "/side" : "")").font(.footnote).monospacedDigit().frame(minWidth: 44, alignment: .leading)
            if set.bodyweight { Text("BW").font(.footnote).foregroundStyle(.secondary) }
            else {
                TextField(WeightFmt.unit(units), text: $weightText).keyboardType(.decimalPad).frame(width: 56).textFieldStyle(.roundedBorder)
                    .onChange(of: weightText) { _, v in
                        // only a real edit changes the stored kilograms (no drift from showing 20 kg as 44.1 lb)
                        guard v != (set.weightKg.map { WeightFmt.number($0, units) } ?? "") else { return }
                        var s = set; s.weightKg = WeightFmt.parse(v, units); onChange(s)
                    }
                Text(WeightFmt.unit(units)).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .onAppear { weightText = set.weightKg.map { WeightFmt.number($0, units) } ?? "" }
        .opacity(set.done ? 1 : 0.9)
    }
}

// MARK: - Equipment and exclusions
struct EquipmentPage: View {
    @EnvironmentObject private var store: Store
    @State private var query = ""
    @State private var customItem = ""
    private func addCustom() {
        let t = customItem.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !t.isEmpty else { return }
        store.equipment.owned.insert(EquipmentProfile.normalised(t)); customItem = ""
        store.refreshGeneratedSessions()
    }
    var body: some View {
        Form {
            Section {
                ForEach(EquipmentProfile.allOptions, id: \.self) { e in
                    Toggle(e.capitalized, isOn: Binding(get: { store.equipment.owned.contains(e) }, set: { on in if on { store.equipment.owned.insert(e) } else { store.equipment.owned.remove(e) } })).tint(BC.accent)
                }
                // custom equipment (anything not in the list, e.g. "sandbag", "rings"): matched by name in your own exercises
                ForEach(store.equipment.owned.filter { !ExerciseCatalogue.equipmentOptions.contains(EquipmentProfile.normalised($0)) }.sorted(), id: \.self) { e in
                    HStack { Text(e.capitalized); Spacer(); Button("Remove") { store.equipment.owned.remove(e) }.font(.footnote.bold()).frame(minHeight: DS.minTap) }
                }
                HStack {
                    TextField("Other equipment (e.g. sandbag)", text: $customItem).submitLabel(.done).onSubmit(addCustom)
                    Button("Add", action: addCustom).disabled(customItem.trimmingCharacters(in: .whitespaces).isEmpty).frame(minHeight: DS.minTap)
                }
            } header: { Text("Equipment I own") } footer: { Text(store.equipment.isSet ? "The coach only suggests exercises that use this equipment or bodyweight. Your saved routines are never changed because of it. Items you add yourself can be chosen when you create an exercise." : "Nothing selected yet: every exercise is treated as possible. Select what you own and suggestions are filtered.") }
            Section {
                let excluded = store.allExercises.filter { store.equipment.excluded.contains($0.id) }
                if excluded.isEmpty { Text("None").foregroundStyle(.secondary) }
                ForEach(excluded) { e in HStack { Text(e.name); Spacer(); Button("Allow") { store.equipment.excluded.remove(e.id) }.font(.caption.bold()) } }
                let results = query.isEmpty ? [] : ExerciseCatalogue.search(query, in: store.allExercises).filter { !store.equipment.excluded.contains($0.id) }.prefix(8)
                TextField("Search an exercise to exclude", text: $query)
                ForEach(Array(results)) { e in Button { store.equipment.excluded.insert(e.id); query = "" } label: { HStack { Text(e.name).foregroundStyle(.primary); Spacer(); Image(systemName: "minus.circle").foregroundStyle(BC.warn) } } }
            } header: { Text("Exercises I cannot do") } footer: { Text("Excluded exercises are never suggested. If one is in a saved routine, the routine keeps it — change the routine yourself.") }
        }
        .navigationTitle("Equipment").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Weekday defaults overview (Profile / Plan)
struct WeekdayRoutinesPage: View {
    @EnvironmentObject private var store: Store
    @State private var pick: Int? = nil
    @State private var note: String? = nil
    var body: some View {
        List {
            Section {
                ForEach(0..<7, id: \.self) { wd in
                    HStack {
                        Text(WeeklyAvailability.longDayNames[wd]).frame(width: 96, alignment: .leading)
                        Spacer()
                        Menu {
                            ForEach(store.templates) { t in Button(t.name) { note = store.setWeekdayRoutine(t, weekday: wd) } }
                            if store.weekdayRoutines[wd] != nil { Divider(); Button("No default", role: .destructive) { _ = store.setWeekdayRoutine(nil, weekday: wd); note = nil } }
                        } label: { Text(store.template(store.weekdayRoutines[wd])?.name ?? "—").foregroundStyle(store.weekdayRoutines[wd] == nil ? .secondary : .primary).lineLimit(1) }
                        .disabled(store.templates.isEmpty)
                    }.frame(minHeight: 44)
                }
            } footer: { Text(store.templates.isEmpty ? "Create a routine first (Templates)." : "Defaults fill the strength sessions of that weekday in this and future weeks, unless you chose a routine for a session by hand. Completed sessions are never changed.") }
            if let note { Section { Text(note).font(.footnote).foregroundStyle(BC.warn) } }
        }
        .navigationTitle("Routine per weekday").navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Train now: choice / unplanned session sheets
struct TrainNowSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let action: Store.TodayAction
    var openRide: () -> Void
    var openStrength: (Workout) -> Void
    @State private var quickLog = false
    @State private var createRoutine = false
    var body: some View {
        NavigationStack {
            List {
                switch action {
                case .choose(let items):
                    Section("Today's sessions") {
                        ForEach(items) { w in
                            Button { dismiss(); if w.kind.isRide { openRide() } else { openStrength(w) } } label: {
                                HStack { Image(systemName: w.kind.isRide ? "bicycle" : "dumbbell").foregroundStyle(BC.accent); VStack(alignment: .leading) { Text(w.displayTitle(routine: store.routine(for: w))).foregroundStyle(.primary); Text(Fmt.duration(minutes: w.minutes)).font(.caption).foregroundStyle(.secondary) }; Spacer(); if w.done { Pill(text: "done", color: BC.live) } }.frame(minHeight: 44)
                            }.disabled(w.done)
                        }
                    }
                case .rest, .doneToday:
                    Section {
                        if case .doneToday(let next) = action { Text(next.map { "Today is done. Next: \($0.date.shortDay) \($0.displayTitle(routine: store.routine(for: $0)).lowercased()) (\(Fmt.duration(minutes: $0.minutes)))." } ?? "Today is done — nothing more is planned this week.").font(.footnote).foregroundStyle(.secondary) }
                        else { Text("Nothing is planned today. An optional session is fine if you feel fresh; it counts like any other.").font(.footnote).foregroundStyle(.secondary) }
                    }
                    Section("Optional session") {
                        Button { dismiss(); openRide() } label: { Label("Ride (opens the Ride screen; recording starts with Start ride)", systemImage: "bicycle") }
                        Button { quickLog = true } label: { Label("Log a strength session", systemImage: "bolt") }
                        ForEach(store.templates.prefix(4)) { t in Button { startUnplanned(t) } label: { Label("Start \(t.name)", systemImage: "dumbbell") } }
                        if store.templates.isEmpty { Button { createRoutine = true } label: { Label("Create a routine", systemImage: "plus") } }
                    }
                default: EmptyView()
                }
            }
            .navigationTitle("Train now").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $quickLog) { QuickStrengthLogSheet() }
            .sheet(isPresented: $createRoutine) { TemplateEditor(template: nil) }
        }.presentationDetents([.medium, .large])
    }
    private func startUnplanned(_ t: WorkoutTemplate) {
        var w = Workout(date: Date(), kind: .strength, minutes: t.estimatedMinutes, strengthFocus: t.focus == .custom ? nil : t.focus)
        w.templateId = t.id; w.routineManual = true
        store.add(w)
        dismiss(); openStrength(w)
    }
}
