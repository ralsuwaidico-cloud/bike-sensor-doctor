import SwiftUI

// Plan v2.0 on the real athlete record. PlanV2Adapter turns what the existing planner and training ledger already hold
// into the plain values PlanScreen draws; PlanV2Host opens the EXISTING editors for what the athlete taps. No second
// planner, no second session list, nothing estimated or invented: a value the app does not have is left out.

enum PlanV2Adapter {
    /// Last week, this week and next week, from `Store.planWeekSummary` (the same source as the existing Plan screen).
    static func data(store: Store, recorderActive: Bool, now: Date = Date(), calendar cal: Calendar = .current) -> PlanData {
        let full = DateFormatter(); full.dateFormat = "EEEE"
        let month = DateFormatter(); month.dateFormat = "MMM"
        let range = DateFormatter(); range.dateFormat = "d MMM"
        var weeks: [PlanWeek] = []
        for off in [-1, 0, 1] {
            let anchor = cal.date(byAdding: .day, value: 7 * off, to: now) ?? now
            let sum = store.planWeekSummary(weekOf: anchor, now: now, recorderActive: recorderActive, calendar: cal)
            let days: [PlanV2Day] = sum.timeline.map { d in
                PlanV2Day(id: cal.component(.day, from: d.date), weekday: full.string(from: d.date), short: d.shortName, month: month.string(from: d.date),
                          isToday: d.isToday, isRest: d.rest, sessions: d.beforePlan ? [] : d.chips.map { session($0, store: store) }, date: cal.startOfDay(for: d.date))
            }
            // Sheet B1: the week is named by its dates ("16–22 Nov"; "30 Nov – 6 Dec" across two months), this week included.
            let title: String
            if let a = sum.timeline.first?.date, let b = sum.timeline.last?.date {
                let sameMonth = cal.component(.month, from: a) == cal.component(.month, from: b)
                title = sameMonth ? "\(cal.component(.day, from: a))–\(range.string(from: b))" : "\(range.string(from: a)) – \(range.string(from: b))"
            } else { title = off == 0 ? "This week" : (off < 0 ? "Last week" : "Next week") }
            weeks.append(PlanWeek(id: off, title: title, days: days))
        }
        let p = store.profile
        let avail = store.effectiveAvailability
        let names = [("Mon", "Monday"), ("Tue", "Tuesday"), ("Wed", "Wednesday"), ("Thu", "Thursday"), ("Fri", "Friday"), ("Sat", "Saturday"), ("Sun", "Sunday")]
        let recurring: [PlanRecurringRow] = names.enumerated().map { i, n in
            guard i < avail.days.count else { return PlanRecurringRow(id: n.0, weekday: n.1, discipline: nil, title: "Rest", duration: "") }
            let d = avail.days[i]
            switch d.activity {
            case .cycle: return PlanRecurringRow(id: n.0, weekday: n.1, discipline: .endurance, title: "Ride", duration: Fmt.duration(minutes: d.minutes))
            // Sheet B2 names the session ("Full Body A"): a strength day carries the name of the routine the athlete assigned
            // to that weekday, when there is one. A ride has no fixed weekly name in the planner, so it stays "Ride".
            case .lift: return PlanRecurringRow(id: n.0, weekday: n.1, discipline: .strength, title: routine(i, store: store) ?? "Strength", duration: Fmt.duration(minutes: d.liftMinutes ?? d.minutes))
            case .both: return PlanRecurringRow(id: n.0, weekday: n.1, discipline: .endurance, title: "Ride + " + (routine(i, store: store) ?? "strength"), duration: Fmt.duration(minutes: d.minutes + (d.liftMinutes ?? 0)))
            case .other: return PlanRecurringRow(id: n.0, weekday: n.1, discipline: nil, title: "Other activity", duration: d.minutes > 0 ? Fmt.duration(minutes: d.minutes) : "")
            case .rest: return PlanRecurringRow(id: n.0, weekday: n.1, discipline: nil, title: "Rest", duration: "")
            }
        }
        let trainingDays = avail.days.filter { $0.activity != .rest }.count
        let this = store.planWeekSummary(weekOf: now, now: now, recorderActive: recorderActive, calendar: cal)
        let coach = store.homeCoach(now: now, postponed: CoachPostpone.ids(store.dir))
        return PlanData(goalTitle: p.effectiveGoals.isEmpty ? nil : ProfileText.goals(p),
                        goalDetail: "\(ProfileText.mode(p.trainingMode)) · \(trainingDays) training day\(trainingDays == 1 ? "" : "s") a week",
                        weeks: weeks,
                        suggestion: coach?.plainTitle,
                        suggestionHeading: coach?.planHeading ?? "COACH SUGGESTS",
                        suggestionAction: coach?.planAction ?? "Review",
                        recurring: recurring,
                        availability: availabilityLine(avail, profile: p, trainingDays: trainingDays),
                        availabilityWarning: budgetWarning(avail, profile: p),
                        programName: nil,
                        note: CycliftLab.isLab ? "Cyclift Lab · demo athlete" : nil)
    }

    /// The routine the athlete assigned to a weekday (Monday = 0), when it still exists.
    private static func routine(_ weekday: Int, store: Store) -> String? {
        guard let t = store.template(store.weekdayRoutines[weekday]) else { return nil }
        let name = t.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Sheet B2's availability summary: training days and the normal week's time ("6 days · 6 h of 6 h"). The budget part
    /// is shown only when the athlete's week is held to weekly budgets; a week set day by day has no budget to compare with.
    static func availabilityLine(_ a: WeeklyAvailability, profile p: RiderProfile, trainingDays: Int) -> String {
        let days = "\(trainingDays) day\(trainingDays == 1 ? "" : "s")"
        let planned = a.cycleMinutes + a.liftMinutes
        if planned == 0 { return days }
        var budget = 0
        if p.weekIsExplicit != true {
            if p.trainingMode.includesCycling { budget += p.hoursPerWeek * 60 }
            if p.trainingMode.includesLifting { budget += p.liftingHoursPerWeek * 60 }
            // a lifting athlete without a lifting budget has no whole-week budget to state
            if p.trainingMode.includesLifting && p.liftingHoursPerWeek == 0 { budget = 0 }
        }
        return budget > 0 ? "\(days) · \(Fmt.duration(minutes: planned)) of \(Fmt.duration(minutes: budget))" : "\(days) · \(Fmt.duration(minutes: planned)) a week"
    }

    /// A week-level problem marks the availability row (specification 7.4 / 24.4): the constraint and both numbers, from
    /// the planner's own budget check. nil when the athlete's settings are within their budgets.
    static func budgetWarning(_ a: WeeklyAvailability, profile p: RiderProfile) -> String? {
        let c = a.conflicts(profile: p)
        guard !c.isEmpty else { return nil }
        return c.map { "\($0.sport == .cycling ? "Cycling" : "Lifting") \(Fmt.duration(minutes: $0.plannedMinutes)) · budget \(Fmt.duration(minutes: $0.budgetMinutes))" }.joined(separator: " · ")
    }

    /// What a planned session consists of, from its own prescription (sheets B1 / B2: "30 min · 5 exercises", "1 h 15 min
    /// · Zone 2", and a bar per part). Rides: the engine's short structure text and one bar per ride step, as wide as
    /// its minutes and as tall as its effort. Strength: the number of planned exercises and one bar per exercise, as wide
    /// as its number of sets — all the same height, because the plan holds no intensity for an exercise and none is
    /// invented. A session without a prescription (recorded only, or no routine assigned) gets neither.
    static func prescription(_ w: Workout, store: Store) -> (text: String, structure: [PlanSegment]) {
        if w.kind == .strength {
            let entries = store.plannedEntries(for: w)
            guard !entries.isEmpty else { return ("", []) }
            return ("\(entries.count) exercise\(entries.count == 1 ? "" : "s")", entries.map { PlanSegment(weight: Double(max($0.sets.count, 1)), level: 0.6) })
        }
        guard w.kind.isRide else { return ("", []) }
        let segs = w.rideSteps.filter { $0.minutes > 0 }.map { s -> PlanSegment in
            // effort 1–10 from the engine's own RPE range for the step
            PlanSegment(weight: Double(s.minutes), level: min(1, max(0.15, Double(s.rpe.lowerBound + s.rpe.upperBound) / 2 / 9)))
        }
        return (w.structureText, segs)
    }

    private static func session(_ c: PlanChip, store: Store) -> PlanSession {
        // a recorded session with no planned session behind it carries no planned length: say what it is instead of nothing
        var detail = c.minutes > 0 ? Fmt.duration(minutes: c.minutes) : (c.workoutId == nil ? "Recorded · not in the plan" : "")
        var structure: [PlanSegment] = []
        if let id = c.workoutId, let w = store.plan.first(where: { $0.id == id }) {
            let p = prescription(w, store: store)
            if !p.text.isEmpty { detail += detail.isEmpty ? p.text : " · \(p.text)" }
            structure = p.structure
        }
        let status: PlanStatus
        switch c.mark {
        case .planned: status = .planned
        case .adjusted: status = .planned; detail += detail.isEmpty ? "changed" : " · changed"
        case .inProgress: status = .planned; detail += detail.isEmpty ? "in progress" : " · in progress"
        case .done: status = .done
        case .missed: status = .missed
        case .skipped: status = .skipped
        }
        return PlanSession(id: c.workoutId?.uuidString ?? c.id, discipline: c.sport == .strength ? .strength : .endurance, title: c.title, detail: detail, status: status, structure: structure)
    }
}

/// The Plan tab when the redesign is on.
struct PlanV2Host: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var recorder: RideRecorder
    private enum Page: String, Identifiable { case goal, routines, availability, adjustments; var id: String { rawValue } }
    @State private var selected: Workout?
    @State private var addOn: Date?
    @State private var page: Page?
    @State private var showCoach = false
    @State private var showGoal = false
    @State private var goalDetent = PlanGoalFlow.listDetent

    var body: some View {
        NavigationStack {
            PlanScreen(data: PlanV2Adapter.data(store: store, recorderActive: recorder.isActive), bottomInset: CyTheme.dockClearance - 44,
                       initialDay: Calendar.current.component(.day, from: Date()), onRequest: handle)
                .toolbar(.hidden, for: .navigationBar)
                .sheet(item: $selected) { w in if w.kind == .strength { StrengthWorkoutScreen(workoutId: w.id) } else { WorkoutDetail(workout: w) } }
                .sheet(item: $addOn) { d in AddWorkoutSheet(date: d) }
                // the Coach row opens the one Coach page, where the same item stands with its own action
                .fullScreenCover(isPresented: $showCoach) { CoachTimelineScreen(backTitle: "Plan", onClose: { showCoach = false }).cyThemeRoot() }
                // Add a goal / Set a goal / the goal row: the redesigned goal sheet (B3) and its set-up and preview (B4).
                // The existing Goals page stays where production uses it (Profile); this host is the redesign only.
                .sheet(isPresented: $showGoal) {
                    PlanGoalFlow(detent: $goalDetent)
                        .presentationDetents([PlanGoalFlow.listDetent, .large], selection: $goalDetent)
                        .presentationDragIndicator(.visible)
                        .cyThemeRoot()
                }
                .sheet(item: $page) { p in
                    NavigationStack {
                        Group {
                            switch p {
                            case .goal: GoalsPage()
                            case .routines: TemplatesView()
                            case .availability: WeekPage()
                            case .adjustments: AdjustmentsView()
                            }
                        }
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { page = nil } } }
                    }
                }
        }
        .accessibilityIdentifier("planV2")
    }

    /// true = a real screen was opened for the request.
    private func handle(_ r: PlanV2Request) -> Bool {
        switch r.name {
        case "Session detail", "Session actions":
            guard let id = r.session.flatMap({ UUID(uuidString: $0.id) }), let w = store.plan.first(where: { $0.id == id }) else { return false }
            selected = w; return true
        case "Add session":
            guard let d = r.day?.date else { return false }
            addOn = d; return true
        case "Add a goal", "Set a goal", "Goal & Program": goalDetent = PlanGoalFlow.listDetent; showGoal = true; return true
        case "Routines": page = .routines; return true
        case "Availability & preferences": page = .availability; return true
        case "Coach proposal": showCoach = true; return true
        default:
            if r.weekday != nil { page = .availability; return true }       // a Recurring Plan row: the existing week editor
            return false                                                    // e.g. Plan history
        }
    }
}
