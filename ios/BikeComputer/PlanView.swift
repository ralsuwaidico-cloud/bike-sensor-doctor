import SwiftUI
import Charts

/// Plan tab: "What does my week look like?" — the week strip (bicycle / dumbbell / moon), the sessions, the week the plan
/// is built from, and Plan changes (versions, read-only, with Undo). RC3 (owner 1 Nov): the weekly totals live only in
/// Progress, and History moved to Progress › Sessions. Tap a day to view / edit / move / skip / replace / add.
struct PlanView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var recorder: RideRecorder
    /// Checkpoint C2: Plan reuses Home's Day page and Weekly overview; `perform` is the Training Hub's own action router.
    var perform: (HomeAction) -> Void = { _ in }
    @State private var path: [HomeRoute] = []
    @State private var proposalReview: PreviewRef? = nil
    @State private var weekOffset = 0
    @State private var selected: Workout?
    @State private var dayList: PlanDay?
    @State private var showAvailability = false
    @State private var addOn: Date?
    @State private var showStrengthLog = false
    @State private var showDetailedLog = false
    @State private var showTemplates = false

    private var weekDate: Date { Calendar.current.date(byAdding: .day, value: 7 * weekOffset, to: Date())! }
    private var week: [Workout] { store.workouts(weekOf: weekDate) }
    private var days: [PlanDay] { PlanDay.group(week, weekOf: weekDate) }

    private var summary: PlanWeekSummary { store.planWeekSummary(weekOf: weekDate, recorderActive: recorder.isActive) }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                let sum = summary
                VStack(spacing: 12) {
                    weekHeader                                                        // A · week selector
                    if sum.pendingProposals > 0 { proposalStrip(sum.pendingProposals) }   // requirement 14 · proposals only in their strip + sheet
                    fixRow
                    Button { path.append(.weekOverview(weekDate)) } label: { PlanCompactRing(overview: sum.overview, minutesLine: sum.minutesLine) }.buttonStyle(.plain)   // B · ring (same ledger as Home)
                    PlanWeekTimeline(days: sum.timeline, onDay: { d in if d.chips.isEmpty && !d.beforePlan { addOn = d.date } else { path.append(.day(d.date)) } },
                                     onChip: { c in if let id = c.workoutId, let w = store.plan.first(where: { $0.id == id }) { selected = w } })   // C · timeline
                    if let n = sum.next { nextSession(n) }                                 // D · next session
                    dayCards                                                           // E · day cards (today expanded)
                    managePlan                                                         // F · manage plan
                }.padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Plan")
            .navigationDestination(for: HomeRoute.self) { r in planDestination(r) }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Menu { Button { showStrengthLog = true } label: { Label("Quick log", systemImage: "bolt") }.accessibilityIdentifier("planMenuQuickLog"); Button { showDetailedLog = true } label: { Label("Log exercises", systemImage: "list.bullet.clipboard") }; Button { showTemplates = true } label: { Label("Routines", systemImage: "square.stack") } } label: { Image(systemName: "ellipsis.circle").frame(width: DS.minTap, height: DS.minTap) }.accessibilityLabel("More").accessibilityIdentifier("planMenu") }
            }
            .sheet(isPresented: $showStrengthLog) { QuickStrengthLogSheet() }
            .sheet(isPresented: $showDetailedLog) { DetailedStrengthLogSheet() }
            .sheet(isPresented: $showTemplates) { NavigationStack { TemplatesView().toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showTemplates = false } } } } }
            .sheet(item: $selected) { w in if w.kind == .strength { StrengthWorkoutScreen(workoutId: w.id) } else { WorkoutDetail(workout: w) } }
            .sheet(isPresented: $showAvailability) { WeekPage(asSheet: true) }   // V1: the one week editor (onboarding Stage C, Profile › Your week)
            .sheet(item: $addOn) { d in AddWorkoutSheet(date: d) }
            .sheet(item: $dayList) { day in dayListSheet(day) }
            .sheet(item: $proposalReview) { r in SessionChangeSheet(proposalId: r.id, onClose: { proposalReview = nil }) }
        }
    }

    @ViewBuilder private func planDestination(_ r: HomeRoute) -> some View {
        switch r {
        case .weekOverview(let d): HomeWeekOverviewView(weekOf: d, perform: perform, open: { path.append($0) })
        case .day(let d): HomeDayDetailView(date: d, perform: perform, open: { path.append($0) })
        case .ride(let id): if let ride = store.rides.first(where: { $0.id == id }) { RideDetailView(ride: ride) }
        case .log(let id): if let st = store.strength.first(where: { $0.id == id }) { StrengthSessionDetail(session: st) }
        case .cycling: HomeCyclingSummaryView(perform: perform, open: { path.append($0) })
        case .strength: HomeStrengthSummaryView(perform: perform, open: { path.append($0) })
        default: EmptyView()
        }
    }

    // MARK: band above B — pending proposal strip (never mixed into the week; opens the existing review sheet)
    private func proposalStrip(_ n: Int) -> some View {
        Button { if let p = store.pendingProposals.values.sorted(by: { $0.workoutId.uuidString < $1.workoutId.uuidString }).first { proposalReview = PreviewRef(id: p.id) } } label: {
            HStack(spacing: DS.s) {
                Image(systemName: "sparkles").foregroundStyle(CyTheme.cycling.tint)
                Text(n == 1 ? "1 change waiting for your review" : "\(n) changes waiting for your review").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Spacer()
                Text("Review").font(.subheadline.bold()).foregroundStyle(BC.accent)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: DS.minTap)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("planProposalStrip")
    }

    // MARK: band D — the next session, with the coach's stored reason (existing-data feature B)
    private func nextSession(_ n: PlanNextSession) -> some View {
        Button { if let w = store.plan.first(where: { $0.id == n.workoutId }) { selected = w } } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("NEXT SESSION").font(.caption2.weight(.heavy)).foregroundStyle(.secondary).tracking(0.5)
                    Spacer()
                    Text(n.button == .start ? "Start" : n.button == .resume ? "Resume" : "Open").font(.subheadline.bold()).foregroundStyle(n.button == .open ? BC.accent : .white)
                        .padding(.horizontal, 12).padding(.vertical, 6).background(n.button == .open ? Color.clear : CyTheme.cycling.tint, in: Capsule())
                }
                Text(n.title).font(.body.weight(.bold)).foregroundStyle(.primary)
                Text(n.subtitle).font(.footnote).foregroundStyle(.secondary)
                if let why = n.why { Label(why, systemImage: "text.bubble").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("planNextWhy") }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next session: \(n.title), \(n.subtitle). \(n.button == .start ? "Start" : n.button == .resume ? "Resume" : "Open")")
        .accessibilityIdentifier("planNextSession")
    }

    // MARK: band F — manage plan
    private var managePlan: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MANAGE PLAN").font(.caption2.weight(.heavy)).foregroundStyle(.secondary).tracking(0.5).padding(.leading, 4)
            weekRow
            changesRow
            Button { showTemplates = true } label: { manageRow("Routines", "square.stack") }.buttonStyle(.plain).accessibilityIdentifier("planRoutines")
            Button { showStrengthLog = true } label: { manageRow("Quick log", "bolt") }.buttonStyle(.plain).accessibilityIdentifier("planQuickLog")
        }
    }
    private func manageRow(_ title: String, _ icon: String) -> some View {
        HStack { Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(.primary); Spacer(); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
            .padding(12).frame(maxWidth: .infinity, minHeight: DS.minTap).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
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
    private func beforePlan(_ d: PlanDay) -> Bool {
        d.items.isEmpty && CyPlanStart.isBeforePlan(d.date, effectiveStart: store.planEffectiveStart, hasRecord: store.hasRecord(on: d.date))
    }
    private func icon(_ d: PlanDay) -> String {
        // the same icons as Home and onboarding: bicycle = ride, dumbbell = strength, crescent moon = rest / recovery
        guard let w = d.items.first else { return "moon.fill" }
        switch w.kind { case .rest, .recoveryDay: return "moon.fill"; case .strength: return "dumbbell.fill"; case .mobility: return "figure.yoga"; case .other: return "figure.mixed.cardio"; default: return "bicycle" }
    }
    private func color(_ d: PlanDay) -> Color {
        guard let w = d.items.first else { return .secondary }
        if w.skipped { return .secondary }
        return w.kind.zone > 0 ? BC.zone(w.kind.zone) : w.kind == .rest ? .secondary : BC.accent
    }

    // MARK: Fix plan (only when the week's planned sessions don't fit a budget — never a warning without a fix)
    @State private var showFix = false
    @ViewBuilder private var fixRow: some View {
        let fit = store.fitReport
        let reports = FixPlanSheet.reports(store, weekOf: weekDate)
        if !fit.conflicts.isEmpty || !reports.isEmpty {
            Button { showFix = true } label: {
                HStack(spacing: DS.s) {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(BC.warn)
                    Text(reports.first.map { "\($0.riding ? "Riding" : "Lifting") is \(Fmt.duration(minutes: $0.overMinutes)) over" } ?? "Your days don't fit").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    Spacer()
                    Text("Fix plan").font(.subheadline.bold()).foregroundStyle(BC.accent)
                }
                .padding(12).frame(maxWidth: .infinity, minHeight: DS.minTap)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("fixPlan")
            .sheet(isPresented: $showFix) { FixPlanSheet(weekOf: weekDate) }
        }
    }

    // MARK: day cards (workouts and recovery days as separate cards)
    private var dayCards: some View {
        VStack(spacing: 8) {
            ForEach(days, id: \.date) { day in
                if day.items.isEmpty {
                    if !beforePlan(day) {
                        Button { addOn = day.date } label: { HStack { Text(day.date.dayAndDate).font(.subheadline.weight(.semibold)); Spacer(); Text("free · add").font(.caption).foregroundStyle(.secondary) }.padding(12).frame(maxWidth: .infinity).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12)) }.buttonStyle(.plain)
                    }
                } else if Calendar.current.isDateInToday(day.date) {
                    ForEach(day.items) { w in
                        Button { selected = w } label: { WorkoutCard(workout: w, routine: store.routine(for: w), routineRemoved: store.isRoutineRemoved(w), status: store.status(w)) }.buttonStyle(.plain)
                    }
                } else {
                    ForEach(day.items) { w in
                        Button { selected = w } label: { compactCard(w) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
    /// Compact card for days other than today (C2 band E): one line, same destination as the full card.
    private func compactCard(_ w: Workout) -> some View {
        let st = store.status(w)
        return HStack(spacing: 10) {
            Image(systemName: w.kind == .strength ? "dumbbell.fill" : (w.kind == .rest || w.kind == .recoveryDay) ? "moon.fill" : "bicycle").foregroundStyle(w.kind == .strength ? CyTheme.strength.tint : CyTheme.cycling.tint).frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(w.displayTitle(routine: store.routine(for: w))).font(.subheadline.weight(.semibold)).foregroundStyle(w.skipped ? .secondary : .primary).lineLimit(1)
                Text(w.date.dayAndDate + (w.minutes > 0 ? " · " + Fmt.duration(minutes: w.minutes) : "")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(w.skipped ? "Skipped" : st.title).font(.caption.weight(.semibold)).foregroundStyle(st.isCompleted ? BC.live : .secondary)
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: DS.minTap)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    /// Plan changes: every applied change as a read-only version with Undo. Run 124: as a second toolbar button it was
    /// pushed off the bar at accessibility text on an iPhone SE, so it sits under "Your week" instead.
    private var changesRow: some View {
        NavigationLink { PlanVersionsView() } label: {
            HStack {
                Label("Plan changes", systemImage: "clock.arrow.circlepath").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: DS.minTap)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("planChanges")
    }

    /// The week the plan is built from (the same days onboarding step 3 sets). Edit → change preview before anything moves.
    private var weekRow: some View {
        Button { showAvailability = true } label: {
            HStack {
                Text("Your week").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Spacer()
                AvailabilityIcons(availability: store.effectiveAvailability)
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(12).frame(maxWidth: .infinity, minHeight: DS.minTap)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("planWeekSettings")
    }

    private func dayListSheet(_ day: PlanDay) -> some View {
        NavigationStack {
            List {
                ForEach(day.items) { w in
                    Button { dayList = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { selected = w } } label: {
                        HStack { ZonePill(z: w.kind.zone); VStack(alignment: .leading) { Text(w.displayTitle(routine: store.routine(for: w))).bold().foregroundStyle(.primary); Text("\(Fmt.duration(minutes: w.minutes)) · \(w.kind.subtitle)").font(.footnote).foregroundStyle(.secondary) }; Spacer(); SessionPill(state: SessionState.of(w, status: store.status(w)), coachAdjusted: w.coachAdjusted) }
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

/// One pill per session state, the same on every Plan surface: planned / modified / in progress / logged · done ·
/// imported / skipped / missed (RC2-UX M1, owner §4).
struct SessionPill: View {
    let state: SessionState
    var coachAdjusted = false
    var body: some View {
        switch state {
        case .scheduled: Pill(text: coachAdjusted ? "planned · coach-adjusted" : "planned", color: .secondary)
        case .modified: Pill(text: "modified", color: BC.accent)
        case .inProgress: Pill(text: "in progress", color: BC.accent)
        case .completed(let t): Pill(text: t, color: BC.live)
        case .skipped: Pill(text: "skipped", color: .secondary)
        case .missed: Pill(text: "missed", color: BC.warn)
        }
    }
}

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
                    let state = SessionState.of(workout, status: st)
                    if !(quiet && state == .scheduled) { SessionPill(state: state, coachAdjusted: workout.coachAdjusted) }
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
    /// Phase 1 rebuild fix: the before/after preview of a significant change; `editNotice` explains a refused change.
    @State private var preview: PreviewRef? = nil
    @State private var editNotice: String? = nil
    @State private var supersets = false

    /// The session as saved (screens never show an unsaved edit as if it were the plan).
    private func reloadFromStore() { if let w = store.plan.first(where: { $0.id == workout.id }) { workout = w } }
    private func submit(_ w: Workout, supersets s: Bool? = nil) {
        editNotice = nil
        switch store.requestEdit(w, prefersSupersets: s) {
        case .saved: mode = 0
        case .preview(let id): preview = PreviewRef(id: id)
        case .refused(let t): editNotice = t; reloadFromStore()
        }
    }

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
            .sheet(item: $preview, onDismiss: reloadFromStore) { r in SessionChangeSheet(proposalId: r.id, onApplied: { mode = 0 }, onClose: { preview = nil }) }
        }
        .undoSnackbar()
    }

    @ViewBuilder private var detail: some View {
        Card { Eyebrow(t: "Why this session"); Text(workout.why) }
        let steps = workout.steps(ftp: store.profile.targetFTP ?? 0, hrZones: watch.appInstalled ? store.profile.hrZones : nil)   // RC3: no watts from an unknown FTP; S2-0: nil zones without a max HR
        if !steps.isEmpty { Card { ForEach(steps, id: \.name) { s in HStack(alignment: .firstTextBaseline) { VStack(alignment: .leading) { Text(s.name).bold(); Text(s.target).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }; Spacer(); Text(s.duration).font(.headline).monospacedDigit() }.padding(.vertical, 4); if s != steps.last { Divider() } } } }
        if workout.kind.zone > 0 {
            Card { Eyebrow(t: "Target zone"); ZoneBar(current: workout.kind.zone)
                if store.profile.ftpKnown {
                    let z = store.profile.prescriptionZones[workout.kind.zone - 1]
                    if let c = store.profile.ftpCaution { Text(c).font(.footnote).foregroundStyle(BC.warn).fixedSize(horizontal: false, vertical: true) }
                    Text("Z\(workout.kind.zone) = \(z.lo)–\(z.hi.map(String.init) ?? "∞") W from FTP \(store.profile.ftpW) W (\(store.profile.ftpBadge)). Heart-rate targets apply when a strap or watch is connected\(watch.appInstalled && hrRange(workout.kind.zone) != nil ? ": Z\(workout.kind.zone) ≈ \(hrRange(workout.kind.zone)!)" : ".")").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("FTP unknown: ride by effort\(watch.appInstalled && hrRange(workout.kind.zone) != nil ? " and heart rate (Z\(workout.kind.zone) ≈ \(hrRange(workout.kind.zone)!))" : store.profile.hrZonesKnown ? ". \(RideSteps.pairHRHint)." : ". Heart-rate zones need your date of birth or max heart rate (Profile).")").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } }
        }
        ActionRow(actions: [
            ActionSpec(label: "Move", a11y: "Move to another day", identifier: "detailMove") { mode = 1 },
            ActionSpec(label: "Edit", a11y: "Edit type and duration", identifier: "detailEdit") { supersets = workout.riderChoice?.prefersSupersets ?? false; mode = 2 },
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
            Button { if recorder.startMode(locationAuthorized: true) == .board { device.sendRideSteps(store.todayRideSteps()); device.control(.start) } else { _ = recorder.start() }; dismiss() } label: { Label("Start this workout", systemImage: "play.fill").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.live).controlSize(.large)
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
        if !workout.kind.minutes0 { Card { Eyebrow(t: "Duration"); Text(Fmt.duration(minutes: workout.minutes)).font(BC.numFont).monospacedDigit(); Slider(value: Binding(get: { Double(workout.minutes) }, set: { workout.minutes = Int($0) }), in: 15...240, step: 5).tint(BC.accent).accessibilityIdentifier("editDuration") } }
        if workout.kind == .strength { Toggle("Use supersets to save time", isOn: $supersets).tint(BC.accent).accessibilityIdentifier("editSupersets") }
        if let t = editNotice { Text(t).font(.footnote).foregroundStyle(BC.stale).fixedSize(horizontal: false, vertical: true) }
        if workout.kind == .strength { Text("A new type or time rebuilds the exercises. You'll see the before and after before anything is saved.").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        Button { submit(workout, supersets: workout.kind == .strength && supersets != (store.plan.first { $0.id == workout.id }?.riderChoice?.prefersSupersets ?? false) ? supersets : nil) } label: { Text(workout.kind == .strength ? "Review change" : "Save").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent).tint(BC.accent).controlSize(.large).accessibilityIdentifier("editSave")
        Button("Cancel") { reloadFromStore(); editNotice = nil; mode = 0 }
    }
    @ViewBuilder private var replace: some View {
        Eyebrow(t: "Replace with")
        ForEach(Coach.alternatives(for: workout), id: \.kind) { alt in
            Button { var w = workout; w.kind = alt.kind; w.minutes = alt.minutes; submit(w) } label: {
                HStack { ZonePill(z: alt.kind.zone); VStack(alignment: .leading) { Text(alt.kind.title).bold().foregroundStyle(.primary); Text(alt.minutes > 0 ? Fmt.duration(minutes: alt.minutes) : "").font(.caption).foregroundStyle(.secondary) }; Spacer() }
                    .padding(12).frame(maxWidth: .infinity).background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
        }
        Button("Cancel") { mode = 0 }
    }
    /// nil when no max heart rate exists (S2-0: never predicted from an assumed age).
    private func hrRange(_ z: Int) -> String? { guard let mh = store.profile.maxHRForZones else { return nil }; let m = Double(mh); let b: [(Double, Double)] = [(0.5, 0.6), (0.6, 0.75), (0.75, 0.85), (0.85, 0.9), (0.9, 1.0), (0.9, 1.0), (0.9, 1.0)]; return "\(Int(m * b[z - 1].0))–\(Int(m * b[z - 1].1)) bpm" }
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
    private var entries: [TimelineEntry] { Timeline.build(rides: store.rides, plan: store.plan, ftp: store.profile.ftpValue ?? 0, strength: store.strength) }   // RC3: no load (TSS) from an unknown FTP

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
