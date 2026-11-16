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
                          isToday: d.isToday, isRest: d.rest, sessions: d.beforePlan ? [] : d.chips.map(session), date: cal.startOfDay(for: d.date))
            }
            let title: String
            if off == 0 { title = "This week" }
            else if let a = sum.timeline.first?.date, let b = sum.timeline.last?.date { title = "\(range.string(from: a)) – \(range.string(from: b))" }
            else { title = off < 0 ? "Last week" : "Next week" }
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
            case .lift: return PlanRecurringRow(id: n.0, weekday: n.1, discipline: .strength, title: "Strength", duration: Fmt.duration(minutes: d.liftMinutes ?? d.minutes))
            case .both: return PlanRecurringRow(id: n.0, weekday: n.1, discipline: .endurance, title: "Ride and strength", duration: Fmt.duration(minutes: d.minutes + (d.liftMinutes ?? 0)))
            case .other: return PlanRecurringRow(id: n.0, weekday: n.1, discipline: nil, title: "Other activity", duration: d.minutes > 0 ? Fmt.duration(minutes: d.minutes) : "")
            case .rest: return PlanRecurringRow(id: n.0, weekday: n.1, discipline: nil, title: "Rest", duration: "")
            }
        }
        let trainingDays = avail.days.filter { $0.activity != .rest }.count
        let this = store.planWeekSummary(weekOf: now, now: now, recorderActive: recorderActive, calendar: cal)
        return PlanData(goalTitle: p.effectiveGoals.isEmpty ? nil : ProfileText.goals(p),
                        goalDetail: "\(ProfileText.mode(p.trainingMode)) · \(trainingDays) training day\(trainingDays == 1 ? "" : "s") a week",
                        weeks: weeks,
                        suggestion: store.homeCoach(now: now)?.title,
                        recurring: recurring,
                        availability: this.minutesLine,
                        availabilityWarning: nil,
                        programName: nil,
                        note: CycliftLab.isLab ? "Cyclift Lab · demo athlete" : nil)
    }

    private static func session(_ c: PlanChip) -> PlanSession {
        var detail = c.minutes > 0 ? Fmt.duration(minutes: c.minutes) : ""
        let status: PlanStatus
        switch c.mark {
        case .planned: status = .planned
        case .adjusted: status = .planned; detail += detail.isEmpty ? "changed" : " · changed"
        case .inProgress: status = .planned; detail += detail.isEmpty ? "in progress" : " · in progress"
        case .done: status = .done
        case .missed: status = .missed
        case .skipped: status = .skipped
        }
        return PlanSession(id: c.workoutId?.uuidString ?? c.id, discipline: c.sport == .strength ? .strength : .endurance, title: c.title, detail: detail, status: status)
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

    var body: some View {
        NavigationStack {
            PlanScreen(data: PlanV2Adapter.data(store: store, recorderActive: recorder.isActive), bottomInset: CyTheme.dockClearance - 44,
                       initialDay: Calendar.current.component(.day, from: Date()), onRequest: handle)
                .toolbar(.hidden, for: .navigationBar)
                .sheet(item: $selected) { w in if w.kind == .strength { StrengthWorkoutScreen(workoutId: w.id) } else { WorkoutDetail(workout: w) } }
                .sheet(item: $addOn) { d in AddWorkoutSheet(date: d) }
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
        case "Add a goal", "Set a goal", "Goal & Program": page = .goal; return true
        case "Routines": page = .routines; return true
        case "Availability & preferences": page = .availability; return true
        case "Coach proposal": page = .adjustments; return true
        default:
            if r.weekday != nil { page = .availability; return true }       // a Recurring Plan row: the existing week editor
            return false                                                    // e.g. Plan history
        }
    }
}
