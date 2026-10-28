import Foundation

/// The week's riding and lifting totals as Plan, Progress and Home show them (RC2 owner report: Plan showed PLANNED
/// minutes under "Riding" while Progress showed DONE minutes, both unlabelled). One source: TrainingLedger (the query
/// layer in WorkoutState.swift), one week boundary (Monday 00:00 – next Monday, local calendar), and two clearly named
/// figures — "Done this week" (rides recorded or imported from Apple Health, sessions logged, marked done or imported,
/// with the minutes actually recorded or typed) and "Planned this week" (planned sessions not skipped, planned minutes).
struct WeekTotals: Equatable {
    let monday: Date
    let riding: TrainingLedger.SportWeek
    let lifting: TrainingLedger.SportWeek

    init(_ ledger: TrainingLedger, weekOf date: Date, calendar cal: Calendar = .current) {
        monday = TrainingLedger.monday(of: date, calendar: cal)
        riding = ledger.riding(weekOf: monday)
        lifting = ledger.lifting(weekOf: monday)
    }

    // MARK: words (the same on every screen)
    static let doneTitle = "Done this week"
    static let plannedTitle = "Planned this week"

    /// "1 h 03 min · 1 ride of 3 planned" (extra, unplanned sessions count too: "3 sessions of 2 planned")
    static func done(_ w: TrainingLedger.SportWeek, singular: String, plural: String) -> String {
        "\(Fmt.duration(minutes: w.minutes)) · \(w.completed) \(w.completed == 1 ? singular : plural) of \(w.planned) planned"
    }
    /// "4 h · 3 rides"
    static func planned(_ w: TrainingLedger.SportWeek, singular: String, plural: String) -> String {
        "\(Fmt.duration(minutes: w.plannedMinutes)) · \(w.planned) \(w.planned == 1 ? singular : plural)"
    }
    /// Progress footer: "Done this week: 1 h 03 min · 1 ride of 3 planned (1 imported). Planned this week: 4 h · 3 rides."
    static func sentence(_ w: TrainingLedger.SportWeek, singular: String, plural: String) -> String {
        var parts: [String] = []
        if w.logged > 0 { parts.append("\(w.logged) logged") }
        if w.manual > 0 { parts.append("\(w.manual) marked or quick") }
        if w.imported > 0 { parts.append("\(w.imported) imported") }
        if w.unknownDuration > 0 { parts.append("\(w.unknownDuration) without duration") }
        return "\(doneTitle): \(done(w, singular: singular, plural: plural))" + (parts.isEmpty ? "" : " (" + parts.joined(separator: ", ") + ")")
            + ". \(plannedTitle): \(planned(w, singular: singular, plural: plural))."
    }
}

/// How a planned session reads on Plan (RC2-UX M1, owner §4: "clearly distinguish scheduled, completed, skipped, missed
/// and modified"). Display only: built from the ledger's WorkoutStatus (never changes it) plus the date and the edit flag.
enum SessionState: Equatable {
    case scheduled, modified, inProgress, skipped, missed
    /// logged / done / imported
    case completed(String)

    static func of(_ w: Workout, status: WorkoutStatus, now: Date = Date(), calendar cal: Calendar = .current) -> SessionState {
        switch status {
        case .completedLogged: return .completed("logged")
        case .completedManual: return .completed("done")
        case .importedHealth: return .completed("imported")
        case .skipped: return .skipped
        case .started, .inProgress: return .inProgress
        case .planned:
            if w.kind == .rest || w.kind == .recoveryDay { return .scheduled }          /* a rest day is never "missed" */
            if cal.startOfDay(for: w.date) < cal.startOfDay(for: now) { return .missed }
            return w.edited ? .modified : .scheduled
        }
    }
    /// Pill text; nil = no pill (a rest day).
    var pill: String {
        switch self {
        case .scheduled: return "planned"
        case .modified: return "modified"
        case .inProgress: return "in progress"
        case .skipped: return "skipped"
        case .missed: return "missed"
        case .completed(let t): return t
        }
    }
    var isCompleted: Bool { if case .completed = self { return true }; return false }
}

/// Concrete, working fixes for a week whose PLANNED minutes are over a budget (the Plan warning "Your edits put this week
/// over a budget — tap Fix plan" used to open a sheet with sentences and no action: a dead end). Same budget rule as
/// PlanEngine.suggestions / liftSuggestions (planned, not skipped sessions of the week against the weekly hours); only
/// sessions that are not done, not skipped, not in the past and not rest can be changed.
struct BudgetFix: Equatable, Identifiable {
    enum Action: Equatable { case shorten(UUID, to: Int), skip(UUID), raiseBudget(hours: Int) }
    var id: String
    var text: String
    var action: Action

    struct Report: Equatable {
        var riding: Bool
        var plannedMinutes: Int
        var limitMinutes: Int
        var explanation: String
        var fixes: [BudgetFix]
        var overMinutes: Int { max(0, plannedMinutes - limitMinutes) }
    }

    /// nil when the sport is within its budget (or has none).
    static func report(week: [Workout], riding: Bool, budgetHours: Int, isCompleted: (Workout) -> Bool, now: Date = Date(), calendar cal: Calendar = .current) -> Report? {
        guard budgetHours > 0 else { return nil }
        let mine = week.filter { (riding ? $0.kind.isRide : $0.kind == .strength) && !$0.skipped }
        let planned = mine.reduce(0) { $0 + $1.minutes }, limit = budgetHours * 60
        guard planned > limit else { return nil }
        let over = planned - limit
        let sport = riding ? "riding" : "lifting", budget = riding ? "weekly cycling budget" : "weekly lifting budget"
        let today = cal.startOfDay(for: now)
        let changeable = mine.filter { !isCompleted($0) && cal.startOfDay(for: $0.date) >= today }.sorted { $0.minutes > $1.minutes || ($0.minutes == $1.minutes && $0.date < $1.date) }
        let fixedPart = mine.filter { !changeable.contains($0) }.reduce(0) { $0 + $1.minutes }
        let minimum = riding ? 30 : 20
        var fixes: [BudgetFix] = []
        if let l = changeable.first, l.minutes - over >= minimum {
            fixes.append(BudgetFix(id: "shorten-\(l.id)", text: "Shorten \(l.date.shortDay) \(l.displayTitle.lowercased()) from \(Fmt.duration(minutes: l.minutes)) to \(Fmt.duration(minutes: l.minutes - over))", action: .shorten(l.id, to: l.minutes - over)))
        }
        if let s = changeable.filter({ $0.minutes >= over }).min(by: { $0.minutes < $1.minutes || ($0.minutes == $1.minutes && $0.date > $1.date) }) {
            fixes.append(BudgetFix(id: "skip-\(s.id)", text: "Skip \(s.date.shortDay) \(s.displayTitle.lowercased()) (\(Fmt.duration(minutes: s.minutes)))", action: .skip(s.id)))
        }
        let hours = (planned + 59) / 60
        fixes.append(BudgetFix(id: "raise-\(sport)", text: "Raise the \(budget) to \(hours) h", action: .raiseBudget(hours: hours)))
        var text = "Planned \(sport) this week is \(Fmt.duration(minutes: planned)) in \(mine.count) \(mine.count == 1 ? "session" : "sessions"); your \(budget) is \(budgetHours) h, so the week is \(Fmt.duration(minutes: over)) over. The budget counts every planned session of the week, done ones included."
        if fixes.count == 1 {
            text += fixedPart >= limit
                ? " The sessions already done or in the past use \(Fmt.duration(minutes: fixedPart)) on their own, so nothing left this week can bring it under; raise the budget or leave it — next week starts within budget."
                : " No single remaining session can absorb \(Fmt.duration(minutes: over)); skip or shorten sessions from the day itself, or raise the budget."
        }
        return Report(riding: riding, plannedMinutes: planned, limitMinutes: limit, explanation: text, fixes: fixes)
    }
}
