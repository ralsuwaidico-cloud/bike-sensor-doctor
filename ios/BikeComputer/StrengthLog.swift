import SwiftUI

// MARK: - Session type grid (P0): 3 columns, 2 on compact widths, short labels, ≥ 44 pt targets.
struct StrengthTypeGrid: View {
    @Binding var focus: StrengthFocus
    var choices: [StrengthFocus] = StrengthFocus.quickLog
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        let cols = dts.isAccessibilitySize ? 2 : 3
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: cols), spacing: 8) {
            ForEach(choices, id: \.self) { f in
                Button { focus = f } label: {
                    VStack(spacing: 4) {
                        Image(systemName: f.icon).font(.system(size: 18, weight: .semibold))
                        Text(f.short).font(.footnote.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 52).padding(.vertical, 6)
                    .background(focus == f ? BC.accent.opacity(0.18) : Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(focus == f ? BC.accent : Color.clear, lineWidth: 1.5))
                    .foregroundStyle(focus == f ? BC.accent : .primary)
                }.buttonStyle(.plain).accessibilityLabel(f.title).accessibilityAddTraits(focus == f ? .isSelected : [])
            }
        }
    }
}

/// Quick Strength Log: type, duration, effort, optional notes. Saved as a strength session with its own hours.
struct QuickStrengthLogSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var date: Date = Date()
    var presetFocus: StrengthFocus? = nil
    var workoutId: UUID? = nil
    @State private var focus: StrengthFocus = .fullBody
    @State private var customName = ""
    @State private var minutes = 40
    @State private var effort = 6
    @State private var notes = ""
    @State private var when = Date()
    @State private var loaded = false
    @State private var detailed = false
    /// Adaptive coach: the saved session waiting for its check-in (the sheet turns into the check-in).
    @State private var checkInFor: UUID? = nil

    var body: some View {
        if let id = checkInFor { CheckInFlow(target: .strength(id), initialEffort: effort) { dismiss() } }
        else { logForm }
    }
    private var logForm: some View {
        NavigationStack {
            Form {
                Section("Session type") {
                    StrengthTypeGrid(focus: $focus)
                    if focus == .custom { TextField("Name (e.g. Kettlebell circuit)", text: $customName) }
                    DatePicker("When", selection: $when, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
                Section("Duration") {
                    HStack { Text(Fmt.duration(minutes: minutes)).font(BC.numFont).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6); Spacer() }
                    Slider(value: Binding(get: { Double(minutes) }, set: { minutes = Int($0) }), in: 10...180, step: 5).tint(BC.accent)
                }
                Section {
                    Picker("Effort", selection: $effort) { Text("Easy").tag(4); Text("Moderate").tag(6); Text("Hard").tag(8) }.pickerStyle(.segmented)
                    Stepper("RPE \(effort) of 10", value: $effort, in: 1...10)
                } header: { Text("Effort") } footer: { Text("Rate of perceived exertion: how hard the whole session felt.") }
                Section("Notes (optional)") { TextField("Anything worth remembering", text: $notes, axis: .vertical).lineLimit(2...4) }
                Section {
                    Button { detailed = true } label: { Label("Log exercises, sets and weights instead", systemImage: "list.bullet.rectangle") }
                } footer: { Text("A quick log tells the coach the session type, duration and effort — nothing about movements. Log exercises when you want squat / hinge / push / pull coverage and progression checked.") }
            }
            .navigationTitle("Log strength").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(focus == .custom && customName.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear { if !loaded { loaded = true; when = min(date, Date()); if let f = presetFocus { focus = f == .legs ? .lower : f } } }
            .alert("Already logged", isPresented: Binding(get: { duplicate != nil }, set: { if !$0 { duplicate = nil } }), presenting: duplicate) { _ in
                Button("Save as an extra session") { save(asExtra: true) }
                Button("Cancel", role: .cancel) {}
            } message: { d in Text("This session is already in your history (\(d.title.lowercased()), \(Fmt.duration(minutes: d.minutes)), \(d.date.dayAndDate)). Logging it again would count it twice. Save only if this was another workout.") }
            .alert("Not saved", isPresented: $rejected) { Button("OK", role: .cancel) {} } message: { Text("A session with the same time and duration is already in your history, so it was not added twice.") }
            .sheet(isPresented: $detailed, onDismiss: { if store.strength.contains(where: { $0.workoutId != nil && $0.workoutId == workoutId }) || detailedSaved { dismiss() } }) {
                DetailedStrengthLogSheet(date: when, presetFocus: focus, workoutId: workoutId, onSaved: { detailedSaved = true })
            }
        }
    }
    @State private var detailedSaved = false
    @State private var duplicate: StrengthSession? = nil
    @State private var rejected = false
    /// A5: a second log of the same planned session is not saved silently. The rider sees what is already logged and
    /// may save this one as an extra, unplanned session instead.
    private func save(asExtra: Bool = false) {
        if !asExtra, let d = store.existingLog(forWorkout: workoutId, on: when) { duplicate = d; return }
        let s = StrengthSession(date: when, minutes: minutes, focus: focus, customName: customName.trimmingCharacters(in: .whitespaces), rpe: effort, notes: notes, workoutId: asExtra ? nil : workoutId)
        if store.addStrength(s) { checkInFor = s.id } else { rejected = true }
    }
}

// MARK: - Detailed log: exercises → sets, supersets, templates
struct DetailedStrengthLogSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var date: Date = Date()
    var presetFocus: StrengthFocus = .custom
    var workoutId: UUID? = nil
    var template: WorkoutTemplate? = nil
    var editing: StrengthSession? = nil
    var onSaved: (() -> Void)? = nil
    @State private var entries: [ExerciseEntry] = []
    @State private var name = ""
    @State private var focus: StrengthFocus = .custom
    @State private var minutes = 45
    @State private var effort: Int? = nil
    @State private var notes = ""
    @State private var when = Date()
    @State private var showSearch = false
    @State private var saveAsTemplate = false
    @State private var templateName = ""
    @State private var loaded = false
    @State private var expanded: UUID? = nil
    @State private var checkInFor: UUID? = nil

    var body: some View {
        if let id = checkInFor { CheckInFlow(target: .strength(id), initialEffort: effort) { dismiss() } }
        else { logForm }
    }
    private var logForm: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Session name (e.g. Lower A)", text: $name)
                    Picker("Type", selection: $focus) { ForEach(StrengthFocus.allCases, id: \.self) { Text($0.title).tag($0) } }
                    DatePicker("When", selection: $when, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    HStack { Text("Duration"); Spacer(); Text(Fmt.duration(minutes: minutes)).monospacedDigit().foregroundStyle(.secondary) }
                    Slider(value: Binding(get: { Double(minutes) }, set: { minutes = Int($0) }), in: 10...180, step: 5).tint(BC.accent)
                }
                Section {
                    if entries.isEmpty { Text("No exercises yet. Add from the catalogue (search by name, equipment, movement or muscle) or create your own.").font(.footnote).foregroundStyle(.secondary) }
                    ForEach($entries) { $e in ExerciseEntryRow(entry: $e, expanded: Binding(get: { expanded == e.id }, set: { expanded = $0 ? e.id : nil }), onDelete: { entries.removeAll { $0.id == e.id } }, units: store.settings.units) }
                    .onMove { entries.move(fromOffsets: $0, toOffset: $1) }
                    Button { showSearch = true } label: { Label("Add exercise", systemImage: "plus.circle.fill") }
                    if entries.count >= 2 { supersetControls }
                } header: { HStack { Text("Exercises"); Spacer(); Text("\(entries.count) · \(entries.reduce(0) { $0 + $1.doneSets.count }) sets").font(.caption) } } footer: { Text("Superset: give two or more exercises the same letter (A, B…) to mark them as performed back to back. Reps are per side for one-sided movements.") }
                Section("Effort and notes (optional)") {
                    Picker("Effort", selection: Binding(get: { effort ?? 0 }, set: { effort = $0 == 0 ? nil : $0 })) { Text("—").tag(0); ForEach(1...10, id: \.self) { Text("RPE \($0)").tag($0) } }
                    TextField("Notes", text: $notes, axis: .vertical).lineLimit(2...4)
                }
                Section {
                    Toggle("Save as a template for next time", isOn: $saveAsTemplate).tint(BC.accent)
                    if saveAsTemplate { TextField("Template name", text: $templateName) }
                } footer: { Text(template != nil ? "This session started from the template “\(template!.name)”; saving updates the template's last values." : "Templates keep the exercise list and prefill the sets from your last session.") }
            }
            .navigationTitle(editing != nil ? "Edit session" : "Log exercises").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { if editing == nil, store.existingLog(forWorkout: workoutId, on: when).map({ $0.isDetailed || workoutId == nil }) == true { askExtra = true } else { save() } }.disabled(entries.isEmpty || entries.allSatisfy { $0.doneSets.isEmpty }) }
                ToolbarItem(placement: .topBarLeading) { if !entries.isEmpty { EditButton() } }
            }
            .sheet(isPresented: $showSearch) { ExerciseSearchSheet { ex in
                var e = ExerciseEntry(exercise: ex, sets: [SetEntry(reps: 8, weightKg: nil, bodyweight: ex.equipment == ["bodyweight"], unilateral: ex.unilateral)])
                if let last = lastValues(for: ex) { e.sets = last }
                entries.append(e); expanded = e.id
            } }
            .onAppear { load() }
            .alert("Already logged", isPresented: $askExtra) {
                Button("Save as an extra session") { save(asExtra: true) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This day's session is already in your history. Logging it again would count it twice. Save only if this was another workout.") }
        }
    }
    @State private var askExtra = false
    private var supersetControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Supersets").font(.caption.weight(.heavy)).foregroundStyle(.secondary)
            ForEach($entries) { $e in
                HStack {
                    Text(e.name).font(.footnote).lineLimit(1); Spacer()
                    Picker("", selection: Binding(get: { e.superset ?? "" }, set: { e.superset = $0.isEmpty ? nil : $0 })) { Text("—").tag(""); ForEach(["A", "B", "C", "D"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented).frame(maxWidth: 190)
                }
            }
        }
    }
    /// Sets as last logged for this exercise (any session), so values carry over.
    private func lastValues(for ex: Exercise) -> [SetEntry]? {
        for s in store.strength.sorted(by: { $0.date > $1.date }) { if let e = s.exercises?.first(where: { $0.exerciseId == ex.id }), !e.sets.isEmpty { return e.sets.map { var t = $0; t.id = UUID(); t.done = true; return t } } }
        return nil
    }
    private func load() {
        guard !loaded else { return }; loaded = true
        when = min(date, Date()); focus = presetFocus == .legs ? .lower : presetFocus
        if let s = editing { entries = s.exercises ?? []; name = s.customName; focus = s.focus; minutes = s.minutes; effort = s.rpe; notes = s.notes; when = s.date }
        else if let t = template { entries = t.prefilled(from: store.lastSession(template: t)); name = t.name; focus = t.focus; templateName = t.name }
    }
    private func save(asExtra: Bool = false) {
        var s = editing ?? StrengthSession(date: when, minutes: minutes, focus: focus, workoutId: asExtra ? nil : workoutId)
        s.date = when; s.minutes = minutes; s.focus = focus; s.customName = name.trimmingCharacters(in: .whitespaces); s.rpe = effort; s.notes = notes
        s.exercises = entries; s.templateId = template?.id ?? editing?.templateId
        if saveAsTemplate {
            let tn = templateName.trimmingCharacters(in: .whitespaces).isEmpty ? (s.customName.isEmpty ? "\(focus.title) session" : s.customName) : templateName.trimmingCharacters(in: .whitespaces)
            var t = template ?? WorkoutTemplate(name: tn, focus: focus, entries: [])
            t.name = tn; t.focus = focus; t.entries = entries.map { e in var x = e; x.id = UUID(); return x }; t.updatedAt = Date(); t.lastUsed = when
            store.saveTemplate(t); s.templateId = t.id
        }
        if editing != nil { store.updateStrength(s); onSaved?(); dismiss(); return }
        // a new completed session: ask for the check-in before closing (adaptive coach)
        if store.addStrength(s) { onSaved?(); checkInFor = s.id } else { onSaved?(); dismiss() }
    }
}

struct ExerciseEntryRow: View {
    @Binding var entry: ExerciseEntry
    @Binding var expanded: Bool
    var onDelete: () -> Void
    var units: AppSettings.Units = .metric
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { expanded.toggle() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let s = entry.superset { Text(s).font(.caption.weight(.heavy)).padding(5).background(BC.accent.opacity(0.18), in: Circle()) }
                    VStack(alignment: .leading, spacing: 2) { Text(entry.name).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(2); Text("\(entry.pattern.title) · \(entry.summary(units: units))").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                    Spacer(); Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(.secondary).font(.caption)
                }.frame(minHeight: 44)
            }.buttonStyle(.plain)
            if expanded {
                ForEach($entry.sets) { $s in SetRow(set: $s, onDelete: { entry.sets.removeAll { $0.id == s.id } }, units: units) }
                HStack {
                    Button { var n = entry.sets.last ?? SetEntry(); n.id = UUID(); n.done = true; entry.sets.append(n) } label: { Label("Add set", systemImage: "plus") }.buttonStyle(.bordered).controlSize(.small)
                    Spacer()
                    Button(role: .destructive) { onDelete() } label: { Label("Remove", systemImage: "trash") }.buttonStyle(.bordered).controlSize(.small)
                }
                TextField("Notes for this exercise", text: $entry.notes).font(.footnote)
            }
        }
    }
}

struct SetRow: View {
    @Binding var set: SetEntry
    var onDelete: () -> Void
    var units: AppSettings.Units = .metric
    @State private var weightText = ""
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { repsField; weightField; flags; deleteButton }
            VStack(alignment: .leading, spacing: 6) { HStack(spacing: 8) { repsField; weightField; deleteButton }; flags }
        }
        .onAppear { weightText = set.weightKg.map { WeightFmt.number($0, units) } ?? "" }
    }
    private var repsField: some View {
        HStack(spacing: 4) {
            Stepper("", value: $set.reps, in: 1...100).labelsHidden()
            Text("\(set.reps) rep\(set.reps == 1 ? "" : "s")").font(.footnote).monospacedDigit().frame(minWidth: 52, alignment: .leading)
        }
    }
    private var weightField: some View {
        HStack(spacing: 4) {
            TextField(WeightFmt.unit(units), text: $weightText).keyboardType(.decimalPad).frame(width: 56).textFieldStyle(.roundedBorder).disabled(set.bodyweight)
                .onChange(of: weightText) { _, v in if v != (set.weightKg.map { WeightFmt.number($0, units) } ?? "") { set.weightKg = WeightFmt.parse(v, units) } }
            Text(set.bodyweight ? "BW" : WeightFmt.unit(units)).font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var flags: some View {
        HStack(spacing: 6) {
            Toggle("BW", isOn: $set.bodyweight).toggleStyle(.button).controlSize(.small).tint(BC.accent).accessibilityLabel("Bodyweight")
            Toggle("1-side", isOn: $set.unilateral).toggleStyle(.button).controlSize(.small).tint(BC.accent).accessibilityLabel("One side at a time")
            Menu { Button("—") { set.rpe = nil }; ForEach(5...10, id: \.self) { r in Button("RPE \(r)") { set.rpe = r } } } label: { Text(set.rpe.map { "@\($0)" } ?? "RPE").font(.caption).padding(.horizontal, 6).frame(minHeight: 28) }.buttonStyle(.bordered).controlSize(.small)
        }
    }
    private var deleteButton: some View { Button(role: .destructive) { onDelete() } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).foregroundStyle(.secondary).frame(minWidth: 32, minHeight: 32) }
}

// MARK: - Exercise search (name, equipment, movement, muscle) + create your own
struct ExerciseSearchSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var onPick: (Exercise) -> Void
    @State private var query = ""
    @State private var pattern: MovementPattern? = nil
    @State private var equipment: String? = nil
    @State private var showCreate = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            chip("All", pattern == nil) { pattern = nil }
                            ForEach(MovementPattern.allCases, id: \.self) { p in chip(p.title, pattern == p) { pattern = pattern == p ? nil : p } }
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            chip("Any equipment", equipment == nil) { equipment = nil }
                            ForEach(ExerciseCatalogue.equipmentOptions, id: \.self) { e in chip(e.capitalized, equipment == e) { equipment = equipment == e ? nil : e } }
                        }
                    }
                }
                let results = ExerciseCatalogue.search(query, in: store.allExercises, pattern: pattern, equipment: equipment)
                Section(results.isEmpty ? "No match" : "\(results.count) exercise\(results.count == 1 ? "" : "s")") {
                    ForEach(results) { e in
                        Button { onPick(e); dismiss() } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) { Text(e.name).foregroundStyle(.primary); if e.custom { Pill(text: "yours", color: BC.accent) } }
                                    Text("\(e.pattern.title) · \(e.equipmentText)" + (e.muscles.isEmpty ? "" : " · \(e.muscles.joined(separator: ", "))")).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer(); Image(systemName: "plus.circle").foregroundStyle(BC.accent)
                            }.frame(minHeight: 44)
                        }
                    }
                    Button { showCreate = true } label: { Label(query.isEmpty ? "Create my own exercise" : "Create “\(query)”", systemImage: "square.and.pencil") }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Name, equipment, movement or muscle")
            .navigationTitle("Add exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(isPresented: $showCreate) { CreateExerciseSheet(initialName: query) { e in store.addCustomExercise(e); onPick(e); dismiss() } }
        }
    }
    private func chip(_ t: String, _ on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(t).font(.footnote.weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 34).background(on ? BC.accent.opacity(0.2) : Color(.tertiarySystemGroupedBackground), in: Capsule()).foregroundStyle(on ? BC.accent : .primary) }.buttonStyle(.plain)
    }
}

struct CreateExerciseSheet: View {
    @Environment(\.dismiss) private var dismiss
    var initialName: String
    var onCreate: (Exercise) -> Void
    @State private var name = ""
    @State private var pattern: MovementPattern = .other
    @State private var equipment: Set<String> = []
    @State private var muscles = ""
    @State private var unilateral = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Name") { TextField("Exercise name", text: $name) }
                Section { Picker("Movement", selection: $pattern) { ForEach(MovementPattern.allCases, id: \.self) { Text($0.title).tag($0) } }; Toggle("One side at a time", isOn: $unilateral).tint(BC.accent) } footer: { Text("The movement pattern is what the coach uses for coverage (squat, hinge, single-leg, core, push, pull). Choose the closest one.") }
                Section("Equipment") { ForEach(ExerciseCatalogue.equipmentOptions, id: \.self) { e in Toggle(e.capitalized, isOn: Binding(get: { equipment.contains(e) }, set: { if $0 { equipment.insert(e) } else { equipment.remove(e) } })).tint(BC.accent) } }
                Section("Main muscles (optional, comma-separated)") { TextField("e.g. glutes, hamstrings", text: $muscles) }
            }
            .navigationTitle("New exercise").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create") {
                    let n = name.trimmingCharacters(in: .whitespaces)
                    onCreate(Exercise(id: "custom-\(UUID().uuidString)", name: n, equipment: Array(equipment).sorted(), pattern: pattern, muscles: muscles.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, unilateral: unilateral, custom: true))
                    dismiss()
                }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear { name = initialName }
        }
    }
}

// MARK: - Templates (routines): created directly, edited, assigned to weekdays — never a completed session
struct TemplatesView: View {
    @EnvironmentObject private var store: Store
    @State private var edit: WorkoutTemplate? = nil
    @State private var createNew = false
    @State private var startNow: WorkoutTemplate? = nil
    var body: some View {
        List {
            Section {
                NavigationLink { WeekdayRoutinesPage() } label: { HStack { Label("Routine per weekday", systemImage: "calendar"); Spacer(); Text("\(store.weekdayRoutines.count) set").foregroundStyle(.secondary) } }
                NavigationLink { EquipmentPage() } label: { HStack { Label("Equipment I own", systemImage: "wrench.and.screwdriver"); Spacer(); Text(store.equipment.isSet ? "\(store.equipment.owned.count)" : "not set").foregroundStyle(.secondary) } }
            }
            Section(store.templates.isEmpty ? "No routines yet" : "Your routines") {
                if store.templates.isEmpty { Text("Create a routine with your own exercises, sets and equipment. Then assign it to a day on the calendar or make it the default for a weekday. Creating a routine never logs a workout.").font(.footnote).foregroundStyle(.secondary) }
                ForEach(store.templates) { t in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack { Text(t.name).font(.body.weight(.semibold)); Spacer(); Pill(text: t.focus.title); Text("≈ \(Fmt.duration(minutes: t.estimatedMinutes))").font(.caption).foregroundStyle(.secondary) }
                        Text(t.exerciseNames).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        let days = store.weekdayRoutines.filter { $0.value == t.id }.keys.sorted().map { WeeklyAvailability.dayNames[$0] }
                        Text((t.lastUsed.map { "last used \($0.dayAndDate)" } ?? "never used") + (days.isEmpty ? "" : " · default on \(days.joined(separator: ", "))")).font(.caption2).foregroundStyle(.secondary)
                        HStack { Button("Edit") { edit = t }.buttonStyle(.bordered).controlSize(.small); Button("Start now") { startNow = t }.buttonStyle(.bordered).controlSize(.small).disabled(store.activeSession != nil); Spacer() }
                    }.padding(.vertical, 4)
                }
                .onDelete { idx in for i in idx { store.deleteTemplateEverywhere(store.templates[i]) } }
                Button { createNew = true } label: { Label("New routine", systemImage: "plus") }.accessibilityIdentifier("newRoutine")
            }
        }
        .navigationTitle("Routines").navigationBarTitleDisplayMode(.inline)
        .sheet(item: $edit) { t in TemplateEditor(template: t) }
        .sheet(isPresented: $createNew) { TemplateEditor(template: nil) }
        .sheet(item: $startNow) { t in UnplannedStartSheet(template: t) }
    }
}

/// Start a routine that is not on today's calendar: adds today's session (hand-added) and opens it.
struct UnplannedStartSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let template: WorkoutTemplate
    @State private var workoutId: UUID? = nil
    var body: some View {
        Group {
            if let id = workoutId { StrengthWorkoutScreen(workoutId: id) } else { ProgressView().onAppear {
                var w = Workout(date: Date(), kind: .strength, minutes: template.estimatedMinutes, strengthFocus: template.focus == .custom ? nil : template.focus)
                w.templateId = template.id; w.routineManual = true
                store.add(w); workoutId = w.id
            } }
        }
    }
}

// MARK: - Home card for Strength and Hybrid modes: progress, one line, compact table, Why?, proposals, review
struct HybridCoachCard: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var recorder: RideRecorder
    @Binding var tab: Int
    @Binding var showWorkout: Bool
    @Binding var showAlternatives: Bool
    @Binding var showStrengthLog: Bool
    @State private var showWhy = false
    @State private var showReview = false
    @State private var lastApplied: String? = nil

    private var a: HybridAssessment { HybridCoach.assess(profile: store.profile, plan: store.plan, rides: store.rides, strength: store.strength, availability: store.effectiveAvailability) }

    var body: some View {
        let a = self.a
        Card(accent: true) {
            HStack { Eyebrow(t: "\(store.profile.trainingMode.title) coach (rules) · \(Date().shortDay)"); Spacer(); Pill(text: a.combined, color: pillColor(a.combined)) }
            Text(a.recommendation).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { if let c = a.cycling { progress("Cycling", c, color: BC.accent) }; if let s = a.strength { progress("Strength", s, color: BC.zone(5)) } }
                VStack(spacing: 8) { if let c = a.cycling { progress("Cycling", c, color: BC.accent) }; if let s = a.strength { progress("Strength", s, color: BC.zone(5)) } }
            }
            if let t = a.next, t.kind != .rest { table(t) }
            DisclosureGroup(isExpanded: $showWhy) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(a.why.enumerated()), id: \.offset) { _, line in Text(line).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                    ForEach(a.findings.filter { $0.severity != .ok }) { f in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: f.severity == .gap ? "exclamationmark.circle.fill" : f.severity == .conflict ? "calendar.badge.exclamationmark" : "info.circle").foregroundStyle(f.severity == .gap ? BC.warn : f.severity == .conflict ? BC.stale : .secondary).font(.footnote)
                            VStack(alignment: .leading, spacing: 2) { Text(f.text).font(.footnote).fixedSize(horizontal: false, vertical: true); if let e = f.evidence { Pill(text: e, color: BC.stale) } }
                        }
                    }
                    if let c = a.coverage, c.known { coverageStrip(c) }
                    Text("Start opens the Ride screen; recording begins only when you hold Start ride there. Strength is logged, never recorded automatically.").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 4)
            } label: { Text("Why?").font(.subheadline.weight(.semibold)).foregroundStyle(BC.accent) }
            if !a.proposals.isEmpty || !store.appliedProposals.isEmpty { proposals(a) }
            ActionRow(actions: actionSpecs(a)).accessibilityIdentifier("coachActions")
        }
        if let w = nextStrength { InsightCard(workout: w, entries: store.plannedEntries(for: w)) }
        if let r = HybridCoach.weeklyReview(profile: store.profile, plan: store.plan, rides: store.rides, strength: store.strength) { reviewCard(r) }
    }

    /// The next open strength session (today or later this week) — the insight card on Home is about that one.
    private var nextStrength: Workout? {
        let today = Calendar.current.startOfDay(for: Date())
        return store.plan.filter { $0.kind == .strength && !$0.done && !$0.skipped && $0.date >= today }.min { $0.date < $1.date }
    }

    @ViewBuilder private func proposals(_ a: HybridAssessment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(t: "Coach proposals")
            ForEach(a.proposals) { p in
                VStack(alignment: .leading, spacing: 4) {
                    Text(p.text).font(.footnote.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(p.why).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack { Button("Accept") { if store.apply(p) { lastApplied = p.text } }.buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.small); Spacer() }
                }.padding(8).background(Color(.systemGroupedBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
            }
            if let last = store.appliedProposals.last {
                HStack { Text("Applied: \(last.text)").font(.caption).foregroundStyle(.secondary).lineLimit(2); Spacer(); Button("Undo") { _ = store.undoLastProposal() }.font(.caption.bold()) }
            }
        }
    }
    private func coverageStrip(_ c: CoverageReport) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Movement coverage, 4 weeks (detailed logs)").font(.caption2.weight(.heavy)).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 6)], spacing: 6) {
                ForEach(MovementPattern.coverage, id: \.self) { p in
                    HStack(spacing: 4) { Circle().fill(c.count(p) > 0 ? BC.live : BC.warn).frame(width: 7, height: 7); Text("\(p.title) \(c.count(p))").font(.caption2).lineLimit(1) }
                }
            }
        }
    }
    private func reviewCard(_ r: WeeklyReview) -> some View {
        Card {
            HStack { Eyebrow(t: "Last week · \(r.completionPct) % completed"); Spacer(); Button(showReview ? "Hide" : "Review ›") { showReview.toggle() }.font(.caption.bold()) }
            HStack(spacing: 10) {
                if store.profile.trainingMode.includesCycling { stat("Rides", "\(r.ridesDone)/\(r.ridesPlanned)", Fmt.duration(minutes: r.rideMinutesDone)) }
                if store.profile.trainingMode.includesLifting { stat("Lifts", "\(r.liftsDone)/\(r.liftsPlanned)", Fmt.duration(minutes: r.liftMinutesDone)) }
                stat("Missed", "\(r.missedWorkouts.count)", "")
            }
            if showReview {
                Text(r.suggestion).font(.footnote).fixedSize(horizontal: false, vertical: true)
                ForEach(r.missedWorkouts) { w in Text("· \(w.date.shortDay): \(w.displayTitle) (\(Fmt.duration(minutes: w.minutes)))").font(.caption).foregroundStyle(.secondary) }
                if r.offerRevise { Button { tab = 1 } label: { Label("Revise my training days", systemImage: "calendar.badge.clock").frame(maxWidth: .infinity) }.buttonStyle(.bordered).tint(BC.stale); Text("Two or more recent weeks missed half their sessions. Changing the days beats carrying the same plan again.").font(.caption2).foregroundStyle(.secondary) }
            }
        }
    }
    private func stat(_ t: String, _ v: String, _ sub: String) -> some View { VStack(alignment: .leading, spacing: 1) { Eyebrow(t: t); Text(v).font(.headline).monospacedDigit(); if !sub.isEmpty { Text(sub).font(.caption).foregroundStyle(.secondary) } }.frame(maxWidth: .infinity, alignment: .leading) }

    /// Short labels that never wrap or hyphenate (the full action is the VoiceOver label): Start · Log · Adjust · Swap.
    private func actionSpecs(_ a: HybridAssessment) -> [ActionSpec] {
        let next = a.next
        let rideNext = next?.kind.isRide == true && !recorder.isActive
        let liftNext = next?.kind == .strength
        var out: [ActionSpec] = []
        if rideNext { out.append(ActionSpec(label: "Start", a11y: "Start: opens the Ride screen", icon: "play.fill", prominent: true, tint: BC.live, identifier: "coachStart") { tab = 2 }) }
        out.append(ActionSpec(label: "Log", a11y: "Log strength", icon: liftNext ? "dumbbell" : nil, prominent: liftNext, tint: liftNext ? BC.zone(5) : nil, identifier: "coachLog") { showStrengthLog = true })
        if store.today != nil {
            out.append(ActionSpec(label: "Adjust", a11y: "Adjust today's session", identifier: "coachAdjust") { showWorkout = true })
            out.append(ActionSpec(label: "Swap", a11y: "Swap today's session for an alternative", identifier: "coachSwap") { showAlternatives = true })
        }
        return out
    }
    private func progress(_ title: String, _ p: SportProgress, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Eyebrow(t: title); Spacer(); Text(p.sessionsTarget > 0 ? "\(p.sessionsDone)/\(p.sessionsTarget)" : "\(p.sessionsDone)").font(.caption.weight(.heavy)).monospacedDigit() }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    if p.minutesTarget > 0 { Capsule().fill(color.opacity(0.35)).frame(width: g.size.width * min(1, Double(p.minutesPlanned) / Double(p.minutesTarget))) }
                    Capsule().fill(color).frame(width: g.size.width * min(1, p.minutesTarget > 0 ? p.ratio : (p.minutesDone > 0 ? 1 : 0)))
                }
            }.frame(height: 7)
            Text(p.minutesTarget > 0 ? "\(Fmt.duration(minutes: p.minutesDone)) of \(Fmt.duration(minutes: p.minutesTarget))" : "\(Fmt.duration(minutes: p.minutesDone)) · no budget set").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(8).background(Color(.systemGroupedBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityLabel("\(title): \(p.note)")
    }
    private func intensity(_ t: Workout) -> String {
        if t.kind.zone > 0 { return "Zone \(t.kind.zone) · \(zoneWatts(t.kind.zone))" }
        if t.kind == .strength { return (t.strengthFocus.map { "\($0.title) · " } ?? "") + "moderate (RPE 6–7)" }
        return t.kind.subtitle
    }
    private func pillColor(_ c: String) -> Color { c == "on track" ? BC.live : c.contains("check") ? BC.stale : BC.warn }
    private func status(_ t: Workout) -> String {
        let st = store.status(t)
        if st == .planned { return recorder.isActive && t.kind.isRide ? "in progress" : t.fixed ? "planned · fixed day" : "planned" }
        return st.title.lowercased()
    }
    private func table(_ t: Workout) -> some View {
        VStack(spacing: 0) {
            row("Workout", t.displayTitle(routine: store.routine(for: t)))
            row("Duration", t.minutes > 0 ? Fmt.duration(minutes: t.minutes) : "—")
            row("Intensity", intensity(t))
            row("Benefit", t.benefit)
            row("Status", status(t), last: true)
        }.background(Color(.systemGroupedBackground).opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
    private func row(_ k: String, _ v: String, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) { Text(k).font(.footnote).foregroundStyle(.secondary).frame(width: 84, alignment: .leading); Text(v).font(.footnote.weight(.medium)).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true) }.padding(.horizontal, 10).padding(.vertical, 6)
            if !last { Divider().padding(.leading, 10) }
        }
    }
    private func zoneWatts(_ z: Int) -> String { let p = store.profile.powerZones[max(0, min(6, z - 1))]; return "\(p.lo)–\(p.hi.map(String.init) ?? "∞") W" }
}

// MARK: - Strength session detail (timeline tap): exercises, sets, per-exercise progression, edit / delete
struct StrengthSessionDetail: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let session: StrengthSession
    @State private var edit = false
    @State private var confirmDelete = false
    private var live: StrengthSession { store.strength.first { $0.id == session.id } ?? session }
    var body: some View {
        let s = live
        let prog = StrengthAnalysis.progression(store.strength)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text(s.title).font(.system(size: 26, weight: .bold, design: .rounded)).lineLimit(2).minimumScaleFactor(0.7); Spacer(); Pill(text: s.isImported ? "imported" : "completed", color: s.isImported ? BC.zone(1) : BC.live) }
                Text("\(s.date.dayAndDate) · \(Fmt.duration(minutes: s.minutes)) · \(s.effortLabel) · \(s.source == "manual" ? (s.isDetailed ? "detailed log" : "quick log") : s.source)").font(.footnote).foregroundStyle(.secondary)
                if let ex = s.exercises, !ex.isEmpty {
                    Card {
                        Eyebrow(t: "Exercises")
                        ForEach(ex) { e in
                            VStack(alignment: .leading, spacing: 3) {
                                HStack { if let g = e.superset { Text(g).font(.caption.weight(.heavy)).padding(4).background(BC.accent.opacity(0.18), in: Circle()) }; Text(e.name).font(.body.weight(.semibold)); Spacer(); Text(e.pattern.title).font(.caption).foregroundStyle(.secondary) }
                                Text(e.doneSets.map { $0.text(units: store.settings.units) }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                if let p = prog.first(where: { $0.exerciseId == e.exerciseId }) {
                                    HStack(spacing: 6) {
                                        Text(trendText(p)).font(.caption2).foregroundStyle(p.trend == .up ? BC.live : p.trend == .down ? BC.stale : .secondary)
                                        if p.points.count >= 3 { Spark(title: "", values: p.points.compactMap { $0.tonnageKg.map { Int(WeightFmt.value($0, store.settings.units)) } }, unit: "\(WeightFmt.unit(store.settings.units))·reps", color: BC.zone(5)).frame(maxWidth: 140) }
                                    }
                                }
                                if !e.notes.isEmpty { Text(e.notes).font(.caption2).foregroundStyle(.secondary) }
                            }.padding(.vertical, 4)
                            if e.id != ex.last?.id { Divider() }
                        }
                    }
                    let pats = s.patterns
                    Card { Eyebrow(t: "Movements trained"); Text(MovementPattern.allCases.filter { pats.contains($0) }.map { $0.title }.joined(separator: ", ")).font(.footnote) }
                } else {
                    Card { Text(s.isImported ? "Imported from \(s.source): duration only. Add exercises to make it count for coverage and progression." : "Quick log: type, duration and effort. No exercises were recorded, so this session says nothing about movement coverage.").font(.footnote).foregroundStyle(.secondary) }
                }
                if !s.notes.isEmpty { Card { Eyebrow(t: "Notes"); Text(s.notes) } }
                HStack { Button { edit = true } label: { Label(s.isDetailed ? "Edit" : "Add exercises", systemImage: "pencil").frame(maxWidth: .infinity) }.buttonStyle(.bordered); Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash").frame(maxWidth: .infinity) }.buttonStyle(.bordered) }
            }.padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Strength").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $edit) { DetailedStrengthLogSheet(date: s.date, presetFocus: s.focus, editing: s) }
        .alert("Delete this session?", isPresented: $confirmDelete) { Button("Delete", role: .destructive) { store.deleteStrength(s); dismiss() }; Button("Cancel", role: .cancel) {} }
    }
    private func trendText(_ p: ExerciseProgression) -> String {
        switch p.trend { case .up: return "Progressing (load × reps rising over \(p.points.count) sessions)"; case .down: return "Load × reps fell over the last sessions"; case .flat: return "Steady over \(p.points.count) sessions"; case .insufficient: return "\(p.points.count) session\(p.points.count == 1 ? "" : "s") logged · progression needs 4 with weights" }
    }
}
