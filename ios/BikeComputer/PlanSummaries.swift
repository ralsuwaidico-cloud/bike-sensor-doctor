import Foundation

// Checkpoint C2 (Plan / Orbit — owner-approved six-part layout, 6 Nov 23:00; implementation under the master order
// 8 Nov). Read-only view models for the Plan screen, built from what the app already records: the week overview the
// Home ring uses (one ledger), planned vs recorded minutes, the coach's stored rationale notes and pending proposals.
// Nothing is calculated anew and nothing is estimated. Foundation only — tested on the Linux harness.

/// One chip on the weekly timeline: a planned or recorded session of one day.
struct PlanChip: Equatable, Identifiable {
    enum Sport: Equatable { case ride, strength, recovery, other }
    enum Mark: Equatable { case planned, done, inProgress, skipped, missed, adjusted
        var symbol: String { switch self { case .planned: return ""; case .done: return "✓"; case .inProgress: return "◐"; case .skipped: return "×"; case .missed: return "!"; case .adjusted: return "✱" } }
        var word: String { switch self { case .planned: return "planned"; case .done: return "done"; case .inProgress: return "in progress"; case .skipped: return "skipped"; case .missed: return "missed"; case .adjusted: return "coach-adjusted" } }
    }
    var id: String
    var workoutId: UUID?
    var title: String
    var minutes: Int
    var sport: Sport
    var mark: Mark
    var accessibilityLabel: String { "\(title), \(minutes > 0 ? Fmt.duration(minutes: minutes) : "no duration"), \(mark.word)" }
}

/// One row of the timeline (Monday first).
struct PlanTimelineDay: Equatable, Identifiable {
    var date: Date
    var weekday: Int                   // Calendar weekday (1 = Sunday … 7 = Saturday) — kept for the existing planDay-<n> identifiers
    var shortName: String              // "Mon"
    var isToday: Bool
    var beforePlan: Bool               // W12: shown as "Before this plan started"
    var rest: Bool
    var chips: [PlanChip]
    var id: Date { date }
    var accessibilityLabel: String {
        if beforePlan { return "\(shortName), before this plan started" }
        if chips.isEmpty { return rest ? "\(shortName), rest day" : "\(shortName), free day" }
        return shortName + ", " + chips.map(\.accessibilityLabel).joined(separator: "; ")
    }
}

/// Band D: the next planned, unfinished session.
struct PlanNextSession: Equatable {
    enum Button: Equatable { case start, resume, open }
    var workoutId: UUID
    var title: String
    var subtitle: String                // "Today · 40 min" / "Wed · 60 min"
    var button: Button
    var why: String?                    // existing-data feature B: the coach's stored rationale, first note
}

/// The whole Plan screen for one week — six bands from existing data.
struct PlanWeekSummary: Equatable {
    var overview: HomeWeekOverview      // band B: the same ring as Home / Weekly overview
    var plannedMinutes: Int             // existing-data feature A (planned vs recorded minutes, from the ledger's week totals)
    var recordedMinutes: Int
    var timeline: [PlanTimelineDay]     // band C
    var next: PlanNextSession?          // band D
    var pendingProposals: Int           // band above B (requirement 14) — opens the existing review sheet
    var minutesLine: String {
        if plannedMinutes == 0 && recordedMinutes == 0 { return "No training time planned or recorded this week" }
        return "\(Fmt.duration(minutes: recordedMinutes)) recorded of \(Fmt.duration(minutes: plannedMinutes)) planned"
    }
    var ringText: String { overview.planned == 0 ? "No sessions planned" : "\(overview.done) of \(overview.planned) sessions done" }
}

enum PlanSummaries {
    static func sport(_ k: WorkoutKind) -> PlanChip.Sport {
        switch k { case .strength: return .strength; case .rest, .recoveryDay: return .recovery; case .mobility, .other: return .other; default: return k.isRide ? .ride : .other }
    }
    static func mark(_ s: HomeStatus, adjusted: Bool) -> PlanChip.Mark {
        switch s { case .done, .marked, .imported: return .done; case .inProgress: return .inProgress; case .skipped: return .skipped; case .missed: return .missed; case .planned: return adjusted ? .adjusted : .planned }
    }
    /// Existing-data feature B: the reason the coach recorded when it built the session (goal + first note), or nil.
    static func why(_ w: Workout) -> String? {
        guard let r = w.rationale else { return nil }
        let note = r.notes.first { !$0.isEmpty }
        if r.deload { return "Deload week" + (note.map { " · " + $0 } ?? "") }
        if let note { return note }
        return r.goal.isEmpty ? nil : r.goal
    }
    static func timeline(_ ov: HomeWeekOverview, now: Date, calendar cal: Calendar = .current) -> [PlanTimelineDay] {
        let today = cal.startOfDay(for: now)
        let f = DateFormatter(); f.calendar = cal; f.dateFormat = "EEE"
        return ov.days.map { d in
            let chips: [PlanChip] = d.items.map { it in
                let w = it.session?.workout
                let adjusted = (it.session?.adjustment).map { !$0.isEmpty } ?? false || (w?.coachOriginal != nil)
                let m: PlanChip.Mark = it.session.map { mark($0.status, adjusted: adjusted) } ?? .done
                return PlanChip(id: it.id, workoutId: w?.id, title: it.title, minutes: w?.minutes ?? 0, sport: w.map { sport($0.kind) } ?? (it.isRide ? .ride : .strength), mark: m)
            }
            return PlanTimelineDay(date: d.date, weekday: cal.component(.weekday, from: d.date), shortName: f.string(from: d.date), isToday: cal.startOfDay(for: d.date) == today, beforePlan: d.kind == .beforePlan, rest: d.kind == .rest, chips: chips)
        }
    }
    /// The next planned, unfinished session of the week on or after today; Start / Resume only when the Training Hub
    /// would allow it (today, training allowed, nothing being recorded) — otherwise Open.
    static func next(_ ov: HomeWeekOverview, now: Date, trainingAllowed: Bool, recorderActive: Bool, calendar cal: Calendar = .current) -> PlanNextSession? {
        let today = cal.startOfDay(for: now)
        let f = DateFormatter(); f.calendar = cal; f.dateFormat = "EEE"
        for d in ov.days where cal.startOfDay(for: d.date) >= today {
            for it in d.items {
                guard let s = it.session, s.status == .planned || s.status == .inProgress else { continue }
                let isToday = cal.startOfDay(for: d.date) == today
                let button: PlanNextSession.Button = isToday && trainingAllowed && !recorderActive ? (s.status == .inProgress ? .resume : .start) : .open
                let when = isToday ? "Today" : f.string(from: d.date)
                return PlanNextSession(workoutId: s.workout.id, title: it.title, subtitle: when + (s.workout.minutes > 0 ? " · " + Fmt.duration(minutes: s.workout.minutes) : ""), button: button, why: why(s.workout))
            }
        }
        return nil
    }
    static func build(overview ov: HomeWeekOverview, riding: TrainingLedger.SportWeek, lifting: TrainingLedger.SportWeek, now: Date, trainingAllowed: Bool, recorderActive: Bool, pendingProposals: Int, calendar cal: Calendar = .current) -> PlanWeekSummary {
        PlanWeekSummary(overview: ov, plannedMinutes: riding.plannedMinutes + lifting.plannedMinutes, recordedMinutes: riding.minutes + lifting.minutes,
                        timeline: timeline(ov, now: now, calendar: cal), next: next(ov, now: now, trainingAllowed: trainingAllowed, recorderActive: recorderActive, calendar: cal), pendingProposals: pendingProposals)
    }
}

extension Store {
    /// The Plan screen's week summary for the week containing `date` — the same ledger, overview and totals Home uses.
    func planWeekSummary(weekOf date: Date, now: Date = Date(), recorderActive: Bool = false, calendar cal: Calendar = .current) -> PlanWeekSummary {
        let ov = homeWeekOverview(weekOf: date, now: now, recorderActive: recorderActive, calendar: cal)
        return PlanSummaries.build(overview: ov, riding: ledger.riding(weekOf: ov.monday), lifting: ledger.lifting(weekOf: ov.monday), now: now,
                                   trainingAllowed: profile.readiness.trainingAllowed, recorderActive: recorderActive, pendingProposals: pendingProposals.count, calendar: cal)
    }
}
