import SwiftUI
import Charts

/// Plan tab (0.5.0): a clean weekly calendar built around the rider's own availability, a weekly summary with the
/// time budget, and the historical timeline below. Tap a day to view / edit / move / skip / replace / add.
struct PlanView: View {
    @EnvironmentObject private var store: Store
    @State private var weekOffset = 0
    @State private var selected: Workout?
    @State private var dayList: PlanDay?
    @State private var showAvailability = false
    @State private var confirmRegenerate = false
    @State private var addOn: Date?
    @State private var showStrengthLog = false
    @State private var lastChanges: [String] = []
    @State private var showDetailedLog = false
    @State private var showTemplates = false

    private var weekDate: Date { Calendar.current.date(byAdding: .day, value: 7 * weekOffset, to: Date())! }
    private var week: [Workout] { store.workouts(weekOf: weekDate) }
    private var days: [PlanDay] { PlanDay.group(week, weekOf: weekDate) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    weekHeader
                    calendar
                    summary
                    dayCards
                    availabilityCard
                    TimelineSection()
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Menu { Button { showStrengthLog = true } label: { Label("Quick log", systemImage: "bolt") }; Button { showDetailedLog = true } label: { Label("Log exercises", systemImage: "list.bullet.rectangle") }; Button { showTemplates = true } label: { Label("Routines", systemImage: "doc.on.doc") } } label: { Label("Log strength", systemImage: "dumbbell") } }
                ToolbarItem(placement: .topBarTrailing) { Button { showAvailability = true } label: { Label("Days", systemImage: "calendar.badge.clock") } }
            }
            .sheet(isPresented: $showStrengthLog) { QuickStrengthLogSheet() }
            .sheet(isPresented: $showDetailedLog) { DetailedStrengthLogSheet() }
            .sheet(isPresented: $showTemplates) { NavigationStack { TemplatesView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showTemplates = false } } } } }
            .sheet(item: $selected) { w in if w.kind == .strength { StrengthWorkoutScreen(workoutId: w.id) } else { WorkoutDetail(workout: w) } }
            .sheet(isPresented: $showAvailability) { AvailabilityEditor() }
            .sheet(item: $addOn) { d in AddWorkoutSheet(date: d) }
            .sheet(item: $dayList) { day in dayListSheet(day) }
            .alert("Replace your edited sessions?", isPresented: $confirmRegenerate) {
                Button("Replace", role: .destructive) { lastChanges = store.regenerate(weekOf: weekDate, replaceEdited: true); _ = store.runAdaptation() }
                Button("Keep my edits") { lastChanges = store.regenerate(weekOf: weekDate, replaceEdited: false); _ = store.runAdaptation() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("\(store.editedCount(weekOf: weekDate)) session(s) this week were changed by hand. Completed sessions and past days are never touched.") }
        }
    }

    // MARK: header + calendar
    private var weekHeader: some View {
        HStack {
            Button { weekOffset -= 1 } label: { Image(systemName: "chevron.left").frame(width: DS.minTap, height: DS.minTap).contentShape(Rectangle()) }.accessibilityLabel("Previous week")
            Spacer()
            VStack(spacing: 2) {
                Text(weekOffset == 0 ? "This week" : weekOffset == 1 ? "Next week" : weekOffset == -1 ? "Last week" : weekTitle).font(.headline)
                Text(weekRange).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { weekOffset += 1 } label: { Image(systemName: "chevron.right").frame(width: DS.minTap, height: DS.minTap).contentShape(Rectangle()) }.disabled(weekOffset >= 1).accessibilityLabel("Next week")
        }
    }
    private var weekTitle: String { let f = DateFormatter(); f.dateFormat = "d MMM"; return "Week of \(f.string(from: days.first?.date ?? weekDate))" }
    private var weekRange: String {
        let f = DateFormatter(); f.dateFormat = "d MMM"
        guard let a = days.first?.date, let b = days.last?.date else { return "" }
        return "\(f.string(from: a)) – \(f.string(from: b))"
    }

    /// Seven days, always all visible: equal widths, text that shrinks instead of widening the row, type capped at
    /// xxLarge for this strip only (the day list below carries the large text). No horizontal scrolling anywhere.
    private var calendar: some View {
        HStack(alignment: .top, spacing: 3) {
            ForEach(days, id: \.date) { day in
                Button { if day.items.count > 1 { dayList = day } else if let w = day.items.first { selected = w } else { addOn = day.date } } label: {
                    VStack(spacing: 4) {
                        Text(day.date.shortDay).font(.caption2.weight(.heavy)).foregroundStyle(Calendar.current.isDateInToday(day.date) ? BC.accent : .secondary).lineLimit(1).minimumScaleFactor(0.6)
                        Image(systemName: icon(day)).font(.system(size: 15, weight: .semibold)).foregroundStyle(color(day)).frame(height: 18)
                        Text(day.items.first.map { Fmt.compact(minutes: $0.minutes) } ?? "—").font(.caption.weight(.bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                        HStack(spacing: 2) { ForEach(day.items.prefix(3)) { w in RoundedRectangle(cornerRadius: 2).fill(w.kind.zone > 0 ? BC.zone(w.kind.zone) : Color.secondary.opacity(0.35)).frame(height: 4) } }
                        if day.items.count > 1 { Text("+\(day.items.count - 1)").font(.caption2.weight(.heavy)).padding(.horizontal, 4).background(BC.accent.opacity(0.18), in: Capsule()) }
                    }
                    .padding(.vertical, 7).padding(.horizontal, 1).frame(minWidth: 0, maxWidth: .infinity, minHeight: 72)
                    .background(day.items.contains { store.status($0).isCompleted } ? BC.live.opacity(0.14) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Calendar.current.isDateInToday(day.date) ? BC.accent : Color.clear, lineWidth: 1.5))
                }.buttonStyle(.plain)
                .frame(minWidth: 0, maxWidth: .infinity)
                .accessibilityIdentifier("planDay-\(Calendar.current.component(.weekday, from: day.date))")
                .accessibilityLabel("\(day.date.dayAndDate): \(day.items.isEmpty ? "free" : day.items.map { "\($0.kind.title) \(Fmt.duration(minutes: $0.minutes)), \(store.status($0).title.lowercased())" }.joined(separator: ", "))")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planDayStrip")
    }
    private func icon(_ d: PlanDay) -> String {
        guard let w = d.items.first else { return "plus" }
        switch w.kind { case .rest: return "moon.zzz"; case .recoveryDay: return "leaf"; case .strength: return "dumbbell"; case .mobility: return "figure.yoga"; case .other: return "figure.run"; case .ftpTest: return "stopwatch"; default: return "bicycle" }
    }
    private func color(_ d: PlanDay) -> Color {
        guard let w = d.items.first else { return .secondary }
        if w.skipped { return .secondary }
        return w.kind.zone > 0 ? BC.zone(w.kind.zone) : w.kind == .rest ? .secondary : BC.accent
    }

    // MARK: summary (compact: counts, two budgets, ONE prioritised action; details behind Fix plan)
    @State private var showFix = false
    private var summary: some View {
        // RC2: every figure from the one query layer (WeekTotals → TrainingLedger), the same numbers as Progress and Home,
        // and named "Done this week" / "Planned this week" (it used to show planned minutes under a bare "Riding")
        let ledger = store.ledger
        let totals = WeekTotals(ledger, weekOf: weekDate)
        let rw = totals.riding, lw = totals.lifting
        let planned = rw.plannedMinutes, lifting = lw.plannedMinutes
        let done = rw.minutes
        let liftDone = lw.minutes
        let limit = store.profile.hoursPerWeek * 60, liftLimit = store.profile.liftingHoursPerWeek * 60
        let fit = store.fitReport
        let overEdits = !PlanEngine.suggestions(for: week, hoursPerWeek: store.profile.hoursPerWeek).isEmpty || !PlanEngine.liftSuggestions(for: week, liftingHours: store.profile.liftingHoursPerWeek).isEmpty
        let lifts = store.profile.trainingMode.includesLifting || lifting > 0
        let action: String = {
            if !fit.conflicts.isEmpty { return "Your days exceed a budget; the coach trimmed flexible activities — tap Fix plan." }
            if overEdits { return "Your edits put this week over a budget — tap Fix plan." }
            if let next = week.first(where: { !ledger.status($0).isCompleted && !$0.skipped && $0.kind != .rest && Calendar.current.startOfDay(for: $0.date) >= Calendar.current.startOfDay(for: Date()) }) { return "Next: \(next.date.shortDay) \(next.displayTitle.lowercased()), \(Fmt.duration(minutes: next.minutes))." }
            return "Everything planned for this week is done."
        }()
        return Card {
            HStack { Eyebrow(t: "Weekly summary"); Spacer(); if !fit.conflicts.isEmpty || overEdits || !fit.trimmed.isEmpty { Button { showFix = true } label: { Label("Fix plan", systemImage: "wrench.and.screwdriver").font(.caption.bold()) } } }
            HStack(alignment: .top, spacing: 12) {
                totalsColumn("Riding", rw, singular: "ride", plural: "rides", warn: planned > limit, id: "Riding")
                if lifts { totalsColumn("Lifting", lw, singular: "lift", plural: "lifts", warn: liftLimit > 0 && lifting > liftLimit, id: "Lifting") }
            }
            budgetBar("Cycling budget", planned: planned, done: done, limit: limit, color: BC.accent)
            if lifts { budgetBar("Lifting budget", planned: lifting, done: liftDone, limit: liftLimit, color: BC.zone(5)) }
            Text(action).font(.footnote).foregroundStyle(fit.conflicts.isEmpty && !overEdits ? .primary : BC.warn).fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $showFix) { FixPlanSheet() }
    }
    private func budgetBar(_ title: String, planned: Int, done: Int, limit: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Text(title).font(.caption2.weight(.heavy)).foregroundStyle(.secondary); Spacer(); Text(limit == 0 ? "no budget set" : planned > limit ? "\(Fmt.duration(minutes: planned - limit)) over \(Fmt.duration(minutes: limit))" : "\(Fmt.duration(minutes: limit - planned)) spare of \(Fmt.duration(minutes: limit))").font(.caption2.weight(.heavy)).foregroundStyle(planned > limit && limit > 0 ? BC.warn : .secondary) }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.18))
                    Capsule().fill(planned > limit && limit > 0 ? BC.warn : color).frame(width: g.size.width * min(1, limit > 0 ? Double(planned) / Double(limit) : (planned > 0 ? 1 : 0)))
                    Capsule().fill(BC.live).frame(width: g.size.width * min(1, limit > 0 ? Double(done) / Double(limit) : 0))
                }
            }.frame(height: 8)
        }
    }
    /// One sport: "Done this week" and "Planned this week", each with its minutes and session count.
    private func totalsColumn(_ title: String, _ w: TrainingLedger.SportWeek, singular: String, plural: String, warn: Bool, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Eyebrow(t: title)
            Text(WeekTotals.doneTitle).font(.caption2).foregroundStyle(.secondary)
            Text(WeekTotals.done(w, singular: singular, plural: plural)).font(.subheadline.weight(.semibold)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("planDone\(id)")
            Text(WeekTotals.plannedTitle).font(.caption2).foregroundStyle(.secondary)
            Text(WeekTotals.planned(w, singular: singular, plural: plural)).font(.subheadline).monospacedDigit().foregroundStyle(warn ? BC.warn : .primary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("planPlanned\(id)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    // MARK: day cards (workouts and recovery days as separate cards)
    private var dayCards: some View {
        VStack(spacing: 8) {
            ForEach(days, id: \.date) { day in
                if day.items.isEmpty {
                    Button { addOn = day.date } label: { HStack { Text(day.date.dayAndDate).font(.subheadline.weight(.semibold)); Spacer(); Text("free · add").font(.caption).foregroundStyle(.secondary) }.padding(12).frame(maxWidth: .infinity).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
                } else {
                    ForEach(day.items) { w in
                        Button { selected = w } label: { WorkoutCard(workout: w, routine: store.routine(for: w), routineRemoved: store.isRoutineRemoved(w), status: store.status(w)) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var availabilityCard: some View {
        Card {
            HStack { Eyebrow(t: "Your training days"); Spacer(); Button("Edit ›") { showAvailability = true }.font(.caption.bold()) }
            let a = store.effectiveAvailability
            HStack(spacing: 4) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 3) {
                        Text(WeeklyAvailability.dayNames[i]).font(.caption2.weight(.heavy)).foregroundStyle(.secondary).lineLimit(1)
                        Image(systemName: a.days[i].activity.icon).font(.system(size: 12)).foregroundStyle(a.days[i].isRest ? (a.days[i].flexible ? BC.stale : .secondary) : BC.accent)
                        Text(a.days[i].isRest ? (a.days[i].flexible ? "flex" : "—") : a.days[i].activity == .both ? "\(Fmt.compact(minutes: a.days[i].cycleMinutes))+\(Fmt.compact(minutes: a.days[i].liftingMinutes))" : Fmt.compact(minutes: a.days[i].totalMinutes)).font(.system(size: 10, weight: .bold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    }.frame(maxWidth: .infinity)
                }
            }
            Text(store.availability == nil ? "Suggested from your profile (\(store.profile.trainingMode.title.lowercased())). Set what happens each day and the plan is built around it." : "\(a.cycleDays) cycling days · \(Fmt.duration(minutes: a.cycleMinutes)) riding" + (a.liftDays > 0 ? " · \(a.liftDays) lift days · \(Fmt.duration(minutes: a.liftMinutes)) lifting" : "") + (a.fixedAssignments > 0 ? " · \(a.fixedAssignments) fixed" : "")).font(.footnote).foregroundStyle(.secondary)
            if !lastChanges.isEmpty { Text("Changed: " + lastChanges.joined(separator: "; ")).font(.caption).foregroundStyle(BC.accent).fixedSize(horizontal: false, vertical: true) }
            Button {
                if store.editedCount(weekOf: weekDate) > 0 { confirmRegenerate = true } else { lastChanges = store.regenerate(weekOf: weekDate, replaceEdited: false); _ = store.runAdaptation() }
            } label: { Text("Rebuild this week from my days").frame(maxWidth: .infinity) }.buttonStyle(.bordered).disabled(weekOffset < 0)
        }
    }

    private func dayListSheet(_ day: PlanDay) -> some View {
        NavigationStack {
            List {
                ForEach(day.items) { w in
                    Button { dayList = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { selected = w } } label: {
                        HStack { ZonePill(z: w.kind.zone); VStack(alignment: .leading) { Text(w.displayTitle(routine: store.routine(for: w))).bold().foregroundStyle(.primary); Text("\(Fmt.duration(minutes: w.minutes)) · \(w.kind.subtitle)").font(.footnote).foregroundStyle(.secondary) }; Spacer(); WorkoutStatusPill(status: store.status(w)) }
                    }
                }
                Button("Add another activity") { let d = day.date; dayList = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { addOn = d } }
            }
            .navigationTitle(day.date.dayAndDate).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dayList = nil } } }
        }.presentationDetents([.medium])
    }
}

extension Date: Identifiable { public var id: TimeInterval { timeIntervalSince1970 } }

/// One session as a card: rides and off-bike sessions look different, recovery/rest days are quiet.
struct WorkoutCard: View {
    let workout: Workout
    var routine: WorkoutTemplate? = nil
    /// The assigned routine was deleted: the card says so instead of falling back to a generic session.
    var routineRemoved = false
    /// From the one query layer; nil = derived from the stored flags (previews / tests).
    var status: WorkoutStatus? = nil
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        let quiet = workout.kind == .rest || workout.kind == .recoveryDay
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3).fill(workout.skipped ? Color.secondary.opacity(0.4) : workout.kind.zone > 0 ? BC.zone(workout.kind.zone) : quiet ? Color.secondary.opacity(0.3) : BC.accent).frame(width: 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(workout.date.dayAndDate).font(.caption.weight(.heavy)).foregroundStyle(Calendar.current.isDateInToday(workout.date) ? BC.accent : .secondary)
                    Spacer()
                    let st = status ?? (workout.done ? .completedManual : workout.skipped ? .skipped : .planned)
                    if st != .planned { WorkoutStatusPill(status: st) } else if workout.edited { Pill(text: "edited", color: BC.accent) } else if workout.coachAdjusted { Pill(text: "coach-adjusted", color: BC.accent) } else if workout.fixed { Pill(text: "fixed", color: BC.stale) }
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) { titleBlock; Spacer(); durationBlock }
                    VStack(alignment: .leading, spacing: 4) { titleBlock; durationBlock }
                }
                if let r = routine { Text("\(r.entries.count) exercises · \(r.setCount) sets · " + r.exerciseNames).font(.caption).foregroundStyle(.secondary).clampLines(2) }
                else if workout.kind == .strength, routineRemoved, !workout.done { Text("routine removed — tap to choose another").font(.caption).foregroundStyle(BC.warn).fixedSize(horizontal: false, vertical: true) }
                else if workout.kind == .strength, !workout.done, let e = workout.plannedEntries, !e.isEmpty { Text("\(e.count) exercises · " + e.map { $0.name }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary).clampLines(2) }
                else if workout.kind == .strength { Text(workout.done ? "logged without a routine" : "no routine assigned · tap to choose one").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                else if !quiet { Text(workout.structureText + " · " + workout.benefit).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(quiet ? Color(.secondarySystemGroupedBackground).opacity(0.6) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
    private var titleBlock: some View { HStack(spacing: 6) { Text(workout.displayTitle(routine: routine)).font(.body.weight(.bold)).fixedSize(horizontal: false, vertical: true); ZonePill(z: workout.kind.zone) } }
    private var durationBlock: some View { Text(workout.minutes > 0 ? Fmt.duration(minutes: workout.minutes) : "—").font(.headline).monospacedDigit().lineLimit(1) }
}

/// Add a session on a given day (type + duration); counted as hand-edited.
struct AddWorkoutSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let date: Date
    @State private var kind: WorkoutKind = .endurance
    @State private var minutes = 60
    @State private var focus: StrengthFocus = .fullBody
    var body: some View {
        NavigationStack {
            Form {
                Section("Type") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 6) {
                        ForEach(WorkoutKind.allCases.filter { $0 != .rest }, id: \.self) { k in Button(k.title) { kind = k; if k.minutes0 { minutes = 0 } else if minutes == 0 { minutes = k.defaultMinutes } }.buttonStyle(.bordered).tint(kind == k ? BC.accent : .secondary).controlSize(.large) }
                    }
                }
                if kind == .strength { Section("Body region") { Picker("Region", selection: $focus) { ForEach(StrengthFocus.allCases.filter { $0 != .custom }, id: \.self) { Text($0.title).tag($0) } } } }
                if !kind.minutes0 { Section("Duration") { HStack { Text(Fmt.duration(minutes: minutes)).font(BC.numFont).monospacedDigit(); Spacer() }; Slider(value: Binding(get: { Double(minutes) }, set: { minutes = Int($0) }), in: 15...240, step: 5).tint(BC.accent) } }
            }
            .navigationTitle(date.dayAndDate).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Add") { store.add(Workout(date: Calendar.current.startOfDay(for: date).addingTimeInterval(7 * 3600), kind: kind, minutes: minutes, strengthFocus: kind == .strength ? focus : nil)); dismiss() } }
            }
        }
    }
}

struct WorkoutDetail: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var device: DeviceLink
    @EnvironmentObject private var recorder: RideRecorder
    @EnvironmentObject private var watch: WatchLink
    @Environment(\.dismiss) private var dismiss
    @State var workout: Workout
    @State private var mode = 0   // 0 detail, 1 move, 2 edit, 3 replace
    @State private var confirmDelete = false
    @State private var showLog = false
    @State private var showDetailed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) { Text(workout.displayTitle).font(DS.screenTitle).fixedSize(horizontal: false, vertical: true); Spacer(); ZonePill(z: workout.kind.zone) }
                    Text("\(workout.date.dayAndDate) · \(workout.minutes > 0 ? "\(Fmt.duration(minutes: workout.minutes)) · " : "")\(workout.kind.subtitle)").foregroundStyle(.secondary)
                    if workout.edited { Pill(text: "edited by you — kept when the week is rebuilt", color: BC.accent) }
                    if workout.fixed { Pill(text: "fixed day — the coach never moves or changes it", color: BC.stale) }
                    if mode == 0, workout.kind != .rest { WorkoutStatusCard(workout: store.plan.first { $0.id == workout.id } ?? workout) { _ in showDetailed = true } }
                    if mode == 0 { detail } else if mode == 1 { move } else if mode == 2 { edit } else { replace }
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("Remove this session?", isPresented: $confirmDelete) { Button("Remove", role: .destructive) { store.remove(workout); dismiss() }; Button("Cancel", role: .cancel) {} }
            .sheet(isPresented: $showLog, onDismiss: { if let w = store.plan.first(where: { $0.id == workout.id }) { workout = w } }) { QuickStrengthLogSheet(date: workout.date, presetFocus: workout.strengthFocus, workoutId: workout.id) }
            .sheet(isPresented: $showDetailed, onDismiss: { if let w = store.plan.first(where: { $0.id == workout.id }) { workout = w } }) { DetailedStrengthLogSheet(date: workout.date, presetFocus: workout.strengthFocus ?? .custom, workoutId: workout.id) }
        }
        .undoSnackbar()
    }

    @ViewBuilder private var detail: some View {
        Card { Eyebrow(t: "Why this session"); Text(workout.why) }
        let steps = workout.steps(ftp: store.profile.prescriptionFTP)
        if !steps.isEmpty { Card { ForEach(steps, id: \.name) { s in HStack(alignment: .firstTextBaseline) { VStack(alignment: .leading) { Text(s.name).bold(); Text(s.target).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }; Spacer(); Text(s.duration).font(.headline).monospacedDigit() }.padding(.vertical, 4); if s != steps.last { Divider() } } } }
        if workout.kind.zone > 0 {
            Card { Eyebrow(t: "Target zone"); ZoneBar(current: workout.kind.zone)
                let z = store.profile.prescriptionZones[workout.kind.zone - 1]
                if let c = store.profile.ftpCaution { Text(c).font(.footnote).foregroundStyle(BC.warn).fixedSize(horizontal: false, vertical: true) }
                Text("Z\(workout.kind.zone) = \(z.lo)–\(z.hi.map(String.init) ?? "∞") W from FTP \(store.profile.ftpW) W (\(store.profile.ftpConfidence.short)). Heart-rate targets apply when a strap or watch is connected\(watch.appInstalled ? ": Z\(workout.kind.zone) ≈ \(hrRange(workout.kind.zone))" : ".")").font(.footnote).foregroundStyle(.secondary) }
        }
        ActionRow(actions: [
            ActionSpec(label: "Move", a11y: "Move to another day", identifier: "detailMove") { mode = 1 },
            ActionSpec(label: "Edit", a11y: "Edit type and duration", identifier: "detailEdit") { mode = 2 },
            ActionSpec(label: "Swap", a11y: "Swap for another session type", identifier: "detailSwap") { mode = 3 },
            ActionSpec(label: "Remove", a11y: "Remove this session (Undo available)", tint: BC.warn, identifier: "detailRemove") { confirmDelete = true }
        ])
        // quality release: never for a later day (the old "today + 24 h" window let tomorrow's session be completed)
        if workout.kind == .strength, !store.isFuture(workout), !store.status(workout).isCompleted {
            HStack(spacing: 8) {
                Button { showLog = true } label: { Label("Quick log", systemImage: "bolt").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.zone(5))
                Button { showDetailed = true } label: { Label("Log exercises", systemImage: "list.bullet.rectangle").frame(maxWidth: .infinity) }.buttonStyle(.bordered).tint(BC.zone(5))
            }.controlSize(.large)
            Text("Logging exercises lets the coach check coverage and progression.").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if workout.kind.isRide, Calendar.current.isDateInToday(workout.date), !recorder.isActive, recorder.startMode(locationAuthorized: true) != .blockedByBoardRide {
            Button { if recorder.startMode(locationAuthorized: true) == .board { device.control(.start) } else { _ = recorder.start() }; dismiss() } label: { Label("Start this workout", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.live).controlSize(.large)
            Text("The Ride screen coaches against this session's zone; targets reach the BikeComputer when it is connected.").font(.footnote).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var move: some View {
        Eyebrow(t: "Move to (the two days swap)")
        ForEach(store.workouts(weekOf: workout.date).filter { $0.id != workout.id }) { o in
            Button { store.swapDays(workout, o); dismiss() } label: { HStack { Text(o.date.dayAndDate).bold(); Spacer(); Text("now \(o.kind.title)").font(.caption).foregroundStyle(.secondary) }.padding(12).frame(maxWidth: .infinity).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
        }
        Button("Cancel") { mode = 0 }
    }
    @ViewBuilder private var edit: some View {
        Card { Eyebrow(t: "Type"); LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 6) { ForEach(WorkoutKind.allCases, id: \.self) { k in Button(k.title) { workout.kind = k; if k.minutes0 { workout.minutes = 0 } else if workout.minutes == 0 { workout.minutes = k.defaultMinutes } }.buttonStyle(.bordered).tint(workout.kind == k ? BC.accent : .secondary).controlSize(.large) } } }
        if workout.kind == .strength { Card { Eyebrow(t: "Body region"); LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 6) { ForEach(StrengthFocus.allCases.filter { $0 != .custom }, id: \.self) { f in Button(f.short) { workout.strengthFocus = f }.buttonStyle(.bordered).tint(workout.strengthFocus == f ? BC.accent : .secondary).controlSize(.large) } } } }
        if !workout.kind.minutes0 { Card { Eyebrow(t: "Duration"); Text(Fmt.duration(minutes: workout.minutes)).font(BC.numFont).monospacedDigit(); Slider(value: Binding(get: { Double(workout.minutes) }, set: { workout.minutes = Int($0) }), in: 15...240, step: 5).tint(BC.accent) } }
        Button { store.edit(workout); mode = 0 } label: { Text("Save").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.large)
        Button("Cancel") { mode = 0 }
    }
    @ViewBuilder private var replace: some View {
        Eyebrow(t: "Replace with")
        ForEach(Coach.alternatives(for: workout), id: \.kind) { alt in
            Button { var w = workout; w.kind = alt.kind; w.minutes = alt.minutes; workout = w; store.edit(w); mode = 0 } label: {
                HStack { ZonePill(z: alt.kind.zone); VStack(alignment: .leading) { Text(alt.kind.title).bold().foregroundStyle(.primary); Text(alt.minutes > 0 ? Fmt.duration(minutes: alt.minutes) : "").font(.caption).foregroundStyle(.secondary) }; Spacer() }
                    .padding(12).frame(maxWidth: .infinity).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
        }
        Button("Cancel") { mode = 0 }
    }
    private func hrRange(_ z: Int) -> String { let m = Double(store.profile.estimatedMaxHR); let b: [(Double, Double)] = [(0.5, 0.6), (0.6, 0.75), (0.75, 0.85), (0.85, 0.9), (0.9, 1.0), (0.9, 1.0), (0.9, 1.0)]; return "\(Int(m * b[z - 1].0))–\(Int(m * b[z - 1].1)) bpm" }
}
extension WorkoutKind { var minutes0: Bool { self == .rest || self == .recoveryDay } }

/// Activities grouped per calendar day for the week strip (pure, unit-tested).
struct PlanDay: Identifiable, Equatable {
    var id: Date { date }
    let date: Date
    let items: [Workout]
    static func group(_ week: [Workout], weekOf d: Date, calendar cal: Calendar = .current) -> [PlanDay] {
        let d0 = cal.startOfDay(for: d)
        let wd = (cal.component(.weekday, from: d0) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: d0)!
        return (0..<7).map { i in
            let day = cal.date(byAdding: .day, value: i, to: monday)!
            let items = week.filter { cal.isDate($0.date, inSameDayAs: day) }.sorted { a, b in a.sequence != b.sequence ? a.sequence < b.sequence : (a.kind.isRide != b.kind.isRide ? a.kind.isRide : a.minutes > b.minutes) }
            return PlanDay(date: day, items: items)
        }
    }
}

// MARK: - Historical timeline
struct TimelineSection: View {
    @EnvironmentObject private var store: Store
    @State private var showAll = false
    private var entries: [TimelineEntry] { Timeline.build(rides: store.rides, plan: store.plan, ftp: store.profile.ftpW, strength: store.strength) }

    var body: some View {
        let all = entries
        let shown = showAll ? all : Array(all.prefix(12))
        VStack(alignment: .leading, spacing: 8) {
            HStack { Eyebrow(t: "History"); Spacer(); Text("\(all.filter { $0.status == .completed || $0.status == .imported }.count) done · \(all.filter { $0.status == .missed }.count) missed").font(.caption).foregroundStyle(.secondary) }
            if all.isEmpty {
                Card { Text("No rides, logged strength sessions or completed sessions yet. Rides from this phone or the BikeComputer, quick strength logs and Apple Health imports (Connections › Apple Health) appear here.").font(.footnote).foregroundStyle(.secondary) }
            } else {
                trends(all)
                ForEach(shown) { e in
                    if let rid = e.rideId, let r = store.rides.first(where: { $0.id == rid }) {
                        NavigationLink { RideDetailView(ride: r) } label: { TimelineRow(entry: e, units: store.settings.units) }.buttonStyle(.plain)
                    } else if let sid = e.strengthId, let st = store.strength.first(where: { $0.id == sid }) {
                        NavigationLink { StrengthSessionDetail(session: st) } label: { TimelineRow(entry: e, units: store.settings.units) }.buttonStyle(.plain)
                    } else { TimelineRow(entry: e, units: store.settings.units) }
                }
                if all.count > 12 { Button(showAll ? "Show less" : "Show all \(all.count)") { showAll.toggle() }.font(.footnote.bold()).buttonStyle(.tapTarget) }
            }
        }
    }
    @ViewBuilder private func trends(_ all: [TimelineEntry]) -> some View {
        let pw = Timeline.trend(all) { $0.avgPower }, hr = Timeline.trend(all) { $0.avgHR }, tss = Timeline.trend(all) { $0.tss }, mins = Timeline.trend(all) { $0.status == .completed ? $0.minutes : nil }
        if pw != nil || hr != nil || tss != nil || mins != nil {
            HStack(spacing: 8) {
                if let v = mins { Spark(title: "Duration", values: v, unit: "min", color: BC.accent) }
                if let v = pw { Spark(title: "Avg power", values: v, unit: "W", color: BC.zone(3)) }
                if let v = hr { Spark(title: "Avg HR", values: v, unit: "bpm", color: BC.warn) }
                if let v = tss { Spark(title: "Load", values: v, unit: "TSS", color: BC.zone(5)) }
            }
        }
    }
}

struct Spark: View {
    let title: String; let values: [Int]; let unit: String; let color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption2.weight(.heavy)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Chart(Array(values.enumerated()), id: \.offset) { i, v in LineMark(x: .value("i", i), y: .value("v", v)).foregroundStyle(color).interpolationMethod(.catmullRom) }
                .chartXAxis(.hidden).chartYAxis(.hidden).frame(height: 28)
            Text("\(values.last ?? 0) \(unit)").font(.caption.weight(.bold)).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(8).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct TimelineRow: View {
    let entry: TimelineEntry; let units: AppSettings.Units
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 2) {
                Image(systemName: entry.rideId != nil ? "bicycle" : (entry.strengthId != nil || entry.title.hasPrefix("Strength")) ? "dumbbell" : "figure.run").font(.system(size: 14, weight: .semibold)).foregroundStyle(statusColor)
                Circle().fill(statusColor).frame(width: 6, height: 6)
            }.frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                FlowRow(spacing: DS.s) {
                    Text(entry.date.dayAndDate).font(.caption.weight(.heavy)).foregroundStyle(.secondary)
                    Text(entry.title).font(.subheadline.weight(.bold))
                    Pill(text: entry.status.rawValue, color: statusColor)
                }
                FlowRow(spacing: 10) {
                    metric(entry.minutes > 0 ? Fmt.duration(minutes: entry.minutes) : "no duration", "")
                    if let d = entry.distanceM { metric(Fmt.km(d, imperial: units == .imperial), "") }
                    if let p = entry.avgPower { metric("\(p)", "W" + (entry.normalizedPower.map { " · NP \($0)" } ?? "")) }
                    if let h = entry.avgHR { metric("\(h)", "bpm" + (entry.maxHR.map { " · max \($0)" } ?? "")) }
                    if let c = entry.cadence { metric("\(c)", "rpm") }
                    if let t = entry.tss { metric("\(t)", "TSS") }
                }.font(.caption)
                if entry.zoneSeconds.reduce(0, +) > 0 { ZoneStrip(seconds: entry.zoneSeconds) }
                if let d = entry.detail { Text(d).font(.caption2).foregroundStyle(.secondary) }
                if let r = entry.recorder { Text(entry.isStrength ? r : "recorded by \(r)").font(.caption2).foregroundStyle(.secondary) }
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .opacity(entry.status == .completed || entry.status == .imported ? 1 : 0.75)
    }
    private func metric(_ v: String, _ u: String) -> some View { HStack(spacing: 2) { Text(v).bold().monospacedDigit(); if !u.isEmpty { Text(u).foregroundStyle(.secondary) } } }
    private var statusColor: Color { switch entry.status { case .completed: return BC.live; case .planned: return BC.accent; case .skipped: return .secondary; case .missed: return BC.stale; case .imported: return BC.zone(1); case .review: return BC.warn } }
}

/// Time-in-zone as proportional segments (no numbers to read while scanning).
struct ZoneStrip: View {
    let seconds: [Int]
    var body: some View {
        let total = max(1, seconds.reduce(0, +))
        GeometryReader { g in
            HStack(spacing: 1) {
                ForEach(Array(seconds.enumerated()), id: \.offset) { i, s in
                    if s > 0 { RoundedRectangle(cornerRadius: 1).fill(BC.zone(i + 1)).frame(width: max(2, g.size.width * Double(s) / Double(total))) }
                }
            }
        }.frame(height: 5).accessibilityLabel("time in zones")
    }
}
