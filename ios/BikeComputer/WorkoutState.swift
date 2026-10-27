import Foundation

// MARK: - Workout state model and the ONE query layer (quality release, ios/QUALITY_RELEASE.md)
//
// A planned session is only ever "completed" by evidence or by an explicit rider action:
//   • a strength log linked to it (detailed → completedLogged, quick / no exercises → completedManual,
//     Apple Health → importedHealth), or a recorded ride on its day (Health ride → importedHealth);
//   • the rider tapping "Mark done" (completedManual, no duration unless they type one).
// It is never completed because its date passed, because it is on the calendar, or for a later day.
// Home, Plan, Progress, History and the coach all read the same `TrainingLedger`, so their counts agree.

/// How a planned session was completed (stored on the Workout). nil = not completed.
enum WorkoutCompletion: String, Codable, Equatable {
    /// A strength log or a recorded ride backs the completion.
    case recorded
    /// The rider marked it done without detail.
    case marked
}

/// The explicit state of one planned session, derived by `TrainingLedger.status(_:)`.
enum WorkoutStatus: String, Codable, CaseIterable, Equatable {
    case planned, started, inProgress, completedLogged, completedManual, skipped, importedHealth
    var isCompleted: Bool { self == .completedLogged || self == .completedManual || self == .importedHealth }
    var title: String {
        switch self {
        case .planned: return "Planned"
        case .started: return "Started"
        case .inProgress: return "In progress"
        case .completedLogged: return "Logged"
        case .completedManual: return "Marked done"
        case .skipped: return "Skipped"
        case .importedHealth: return "Imported"
        }
    }
    /// Short pill text.
    var pill: String {
        switch self {
        case .planned: return "planned"
        case .started: return "started"
        case .inProgress: return "in progress"
        case .completedLogged: return "logged"
        case .completedManual: return "done"
        case .skipped: return "skipped"
        case .importedHealth: return "imported"
        }
    }
}

/// Read-only view over plan + logs + rides. Pure; built on demand (cheap) by the Store and by the coach.
struct TrainingLedger {
    let plan: [Workout]
    /// Logs that count: everything except records still waiting for the rider's review.
    let logs: [StrengthSession]
    let rides: [RideRecord]
    let active: StrengthSession?
    let cal: Calendar
    /// Planned strength session id → the log that completed it (explicit link first, then an unlinked log of that day).
    private(set) var logFor: [UUID: StrengthSession] = [:]
    private let rideDays: [Date: [RideRecord]]

    init(plan: [Workout], strength: [StrengthSession], rides: [RideRecord], active: StrengthSession? = nil, calendar: Calendar = .current) {
        self.plan = plan
        self.logs = strength.filter { !$0.awaitingReview && !$0.inProgress }
        self.rides = rides.filter { !$0.demo }
        self.active = active
        self.cal = calendar
        var days: [Date: [RideRecord]] = [:]
        for r in self.rides { days[calendar.startOfDay(for: r.start), default: []].append(r) }
        rideDays = days
        let strengthPlan = plan.filter { $0.kind == .strength }
        let ids = Set(strengthPlan.map { $0.id })
        var map: [UUID: StrengthSession] = [:]
        // 1. explicit links (never to a session planned for a later day than the log)
        for s in logs.sorted(by: { $0.date < $1.date }) {
            guard let wid = s.workoutId, ids.contains(wid), map[wid] == nil, let w = strengthPlan.first(where: { $0.id == wid }) else { continue }
            if calendar.startOfDay(for: w.date) > calendar.startOfDay(for: s.date) { continue }
            map[wid] = s
        }
        // 2. unlinked logs of a day stand for that day's open planned strength sessions (sequence order)
        let used = Set(map.values.map { $0.id })
        for s in logs.sorted(by: { $0.date < $1.date }) where !used.contains(s.id) && s.unplanned != true && (s.workoutId == nil || !ids.contains(s.workoutId!)) {
            if let w = strengthPlan.filter({ map[$0.id] == nil && !$0.skipped && calendar.isDate($0.date, inSameDayAs: s.date) }).min(by: { $0.sequence < $1.sequence }) { map[w.id] = s }
        }
        logFor = map
    }

    func log(for w: Workout) -> StrengthSession? { logFor[w.id] }
    func ride(for w: Workout) -> RideRecord? { w.kind.isRide ? rideDays[cal.startOfDay(for: w.date)]?.first : nil }

    /// The explicit state of a planned session.
    func status(_ w: Workout) -> WorkoutStatus {
        if w.kind == .strength {
            if let a = active, a.workoutId == w.id { return (a.exercises ?? []).contains { !$0.doneSets.isEmpty } ? .inProgress : .started }
            if let l = logFor[w.id] { return l.isImported ? .importedHealth : l.isDetailed ? .completedLogged : .completedManual }
        } else if w.kind.isRide, let r = ride(for: w) {
            return r.recorder == .health ? .importedHealth : .completedLogged
        }
        if w.completion == .marked { return .completedManual }
        if w.skipped { return .skipped }
        return .planned
    }

    // MARK: weekly counts — one definition for every screen
    struct SportWeek: Equatable {
        var monday: Date
        /// Planned sessions of the week (not skipped) and their planned minutes.
        var planned = 0, plannedMinutes = 0
        /// Completed sessions = detailed logs + manual completions (quick logs and "Mark done") + imports.
        var completed = 0
        var logged = 0, manual = 0, imported = 0
        /// Minutes actually recorded or typed by the rider; sessions without a duration add none.
        var minutes = 0
        var unknownDuration = 0
        var loggedMinutes = 0, manualMinutes = 0, importedMinutes = 0
    }

    private func week(_ monday: Date) -> (start: Date, end: Date) { (monday, cal.date(byAdding: .day, value: 7, to: monday)!) }

    func lifting(weekOf monday: Date) -> SportWeek {
        let (m, e) = week(monday)
        var w = SportWeek(monday: m)
        let planned = plan.filter { $0.kind == .strength && !$0.skipped && $0.date >= m && $0.date < e }
        w.planned = planned.count; w.plannedMinutes = planned.reduce(0) { $0 + $1.minutes }
        for s in logs where s.date >= m && s.date < e {
            w.completed += 1; w.minutes += s.minutes
            if s.minutes <= 0 { w.unknownDuration += 1 }
            if s.isImported { w.imported += 1; w.importedMinutes += s.minutes }
            else if s.isDetailed { w.logged += 1; w.loggedMinutes += s.minutes }
            else { w.manual += 1; w.manualMinutes += s.minutes }
        }
        for p in planned where logFor[p.id] == nil && p.completion == .marked {
            w.completed += 1; w.manual += 1
            if let mm = p.manualMinutes, mm > 0 { w.minutes += mm; w.manualMinutes += mm } else { w.unknownDuration += 1 }
        }
        return w
    }

    func riding(weekOf monday: Date) -> SportWeek {
        let (m, e) = week(monday)
        var w = SportWeek(monday: m)
        let planned = plan.filter { $0.kind.isRide && !$0.skipped && $0.date >= m && $0.date < e }
        w.planned = planned.count; w.plannedMinutes = planned.reduce(0) { $0 + $1.minutes }
        let rs = rides.filter { $0.start >= m && $0.start < e }
        w.completed = rs.count
        let secs = rs.reduce(0) { $0 + $1.durationS }
        w.minutes = secs / 60
        w.imported = rs.filter { $0.recorder == .health }.count; w.logged = rs.count - w.imported
        w.importedMinutes = rs.filter { $0.recorder == .health }.reduce(0) { $0 + $1.durationS } / 60
        w.loggedMinutes = w.minutes - w.importedMinutes
        for p in planned where ride(for: p) == nil && p.completion == .marked {
            w.completed += 1; w.manual += 1
            if let mm = p.manualMinutes, mm > 0 { w.minutes += mm; w.manualMinutes += mm } else { w.unknownDuration += 1 }
        }
        return w
    }

    static func monday(of d: Date, calendar cal: Calendar = .current) -> Date {
        let d0 = cal.startOfDay(for: d); let wd = (cal.component(.weekday, from: d0) + 5) % 7
        return cal.date(byAdding: .day, value: -wd, to: d0)!
    }
}

// MARK: - Soft delete with Undo
/// A deleted record kept for Undo (snackbar) and for 30 days. `planBefore` = the planned sessions the deletion changed,
/// exactly as they were, so Undo restores both sides.
struct TrashItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var deletedAt: Date
    var label: String
    var strength: [StrengthSession] = []
    var workout: Workout? = nil
    var planBefore: [Workout] = []
    static let keepDays = 30
}

struct UndoToast: Identifiable, Equatable {
    var id: UUID          // the trash item id
    var text: String
}

// MARK: - Store: state transitions (every write of done / completion goes through here)
extension Store {
    var ledger: TrainingLedger { TrainingLedger(plan: plan, strength: strength, rides: rides, active: activeSession) }
    func status(_ w: Workout) -> WorkoutStatus { ledger.status(w) }

    /// Finishing would save nothing: the session had planned exercises but no set is ticked as done.
    static func finishWouldSaveNothing(_ s: StrengthSession) -> Bool {
        let ex = s.exercises ?? []
        return !ex.isEmpty && !ex.contains { !$0.doneSets.isEmpty }
    }

    /// A session can be completed (logged, marked done, started) only on or after its own day.
    func isFuture(_ w: Workout, now: Date = Date()) -> Bool { Calendar.current.startOfDay(for: w.date) > Calendar.current.startOfDay(for: now) }

    /// "Mark done" without detail. Refused for a later day, for a skipped or already completed session. `minutes` only
    /// when the rider typed one.
    @discardableResult
    func markDone(_ id: UUID, minutes: Int? = nil, now: Date = Date()) -> Bool {
        guard let i = plan.firstIndex(where: { $0.id == id }) else { return false }
        let w = plan[i]
        guard !isFuture(w, now: now), !ledger.status(w).isCompleted, w.kind != .rest, w.kind != .recoveryDay else { return false }
        var x = w
        x.done = true; x.completion = .marked; x.completedAt = now; x.manualMinutes = minutes.flatMap { $0 > 0 ? $0 : nil }; x.skipped = false
        plan[i] = x
        return true
    }

    /// Correct a wrongly-completed session: back to planned. Logs that completed it are either deleted (soft, Undo) or
    /// kept as extra sessions on their own date (never silently re-linked).
    @discardableResult
    func revertToPlanned(_ id: UUID, deleteLinkedLogs: Bool) -> Bool {
        guard let i = plan.firstIndex(where: { $0.id == id }) else { return false }
        let before = plan[i]
        var linked = strength.filter { $0.workoutId == id }
        if let l = ledger.log(for: before), !linked.contains(where: { $0.id == l.id }) { linked.append(l) }
        if deleteLinkedLogs, !linked.isEmpty {
            trashLogs(linked, planBefore: [before], label: "Session reopened", toast: "Session reopened and its log deleted")
        } else {
            for l in linked { if let j = strength.firstIndex(where: { $0.id == l.id }) { strength[j].workoutId = nil; strength[j].unplanned = true } }
        }
        if let k = plan.firstIndex(where: { $0.id == id }) { plan[k].done = false; plan[k].completion = nil; plan[k].completedAt = nil; plan[k].manualMinutes = nil }
        return true
    }

    /// Deletes one log: it moves to the trash and the planned session it completed goes back to planned.
    func deleteStrengthLog(_ s: StrengthSession) {
        let l = ledger
        let completed = plan.filter { w in l.log(for: w)?.id == s.id || w.id == s.workoutId }
        trashLogs([s], planBefore: completed, label: s.title, toast: "\(s.title) deleted")
    }

    private func trashLogs(_ logs: [StrengthSession], planBefore: [Workout], label: String, toast: String) {
        let present = logs.filter { l in strength.contains { $0.id == l.id } }
        guard !present.isEmpty else { return }
        let item = TrashItem(deletedAt: Date(), label: label, strength: present, planBefore: planBefore)
        let ids = Set(present.map { $0.id })
        strength.removeAll { ids.contains($0.id) }
        for b in planBefore { if let i = plan.firstIndex(where: { $0.id == b.id }), plan[i].completion != .marked { plan[i].done = false; plan[i].completion = nil; plan[i].completedAt = nil } }
        trash.append(item)
        undoToast = UndoToast(id: item.id, text: toast)
    }

    /// Removes a planned session (trash + Undo). Its logs stay in history as extra sessions.
    func deleteWorkout(_ w: Workout) {
        guard let cur = plan.first(where: { $0.id == w.id }) else { return }
        let item = TrashItem(deletedAt: Date(), label: cur.displayTitle, workout: cur)
        plan.removeAll { $0.id == w.id }
        for j in strength.indices where strength[j].workoutId == w.id { strength[j].unplanned = true }
        trash.append(item)
        undoToast = UndoToast(id: item.id, text: "\(cur.displayTitle) removed")
    }

    /// Undo a deletion: the records come back with their ids, and the planned sessions they touched as they were.
    @discardableResult
    func undoDelete(_ trashId: UUID) -> Bool {
        guard let item = trash.first(where: { $0.id == trashId }) else { return false }
        var logs = strength
        for s in item.strength where !logs.contains(where: { $0.id == s.id }) { logs.append(s) }
        if let w = item.workout { for j in logs.indices where logs[j].workoutId == w.id { logs[j].unplanned = nil } }
        logs.sort { $0.date > $1.date }
        var p = plan
        if let w = item.workout, !p.contains(where: { $0.id == w.id }) { p.append(w) }
        for b in item.planBefore { if let i = p.firstIndex(where: { $0.id == b.id }) { p[i] = b } else { p.append(b) } }
        p.sort { $0.date < $1.date }
        strength = logs
        plan = p
        trash.removeAll { $0.id == trashId }
        if undoToast?.id == trashId { undoToast = nil }
        return true
    }

    /// Trash older than 30 days is removed for good (called at launch).
    func purgeTrash(now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-Double(TrashItem.keepDays) * 86_400)
        if trash.contains(where: { $0.deletedAt < cutoff }) { trash.removeAll { $0.deletedAt < cutoff } }
    }

    /// The rider confirms a record the migration flagged: it counts again (and completes its planned session).
    func confirmReviewed(_ id: UUID, minutes: Int? = nil) {
        guard let i = strength.firstIndex(where: { $0.id == id }) else { return }
        strength[i].needsReview = nil
        if let m = minutes, m > 0 { strength[i].minutes = m }
        if let wid = strength[i].workoutId, let j = plan.firstIndex(where: { $0.id == wid }), !isFuture(plan[j], now: strength[i].date) {
            plan[j].done = true; plan[j].completion = .recorded; plan[j].completedAt = strength[i].date
        }
    }

    /// Moves a session planned for a later day to today (so it can be started now). A hand edit.
    @discardableResult
    func moveToToday(_ id: UUID, now: Date = Date()) -> Bool {
        guard let i = plan.firstIndex(where: { $0.id == id }), isFuture(plan[i], now: now) else { return false }
        let cal = Calendar.current
        let t = cal.dateComponents([.hour, .minute, .second], from: plan[i].date)
        plan[i].date = cal.date(bySettingHour: t.hour ?? 7, minute: t.minute ?? 0, second: t.second ?? 0, of: now) ?? now
        plan[i].markRiderEdited()
        plan.sort { $0.date < $1.date }
        return true
    }
}

// MARK: - Schema 2 migration (idempotent; never deletes; original values kept in notes)
enum StoreMigration {
    static let ruleText = """
    Rule M1 (future completion): a planned session marked done whose day is after the migration day is set back to planned; logs linked to it stay on their own date as extra sessions.
    Rule M2 (zero-set finish): a log saved from workout mode with no exercise sets is kept but flagged for review (not counted until the rider confirms it); a recorded duration of 2 min or less is a timer artefact and becomes "not recorded".
    Rule M3 (evidence): a session marked done keeps "completed" only when a counted log (strength) or a recorded ride (cycling) exists for it; otherwise it goes back to planned, because no earlier build offered a manual "mark done".
    Rule M4 (FTP label): an FTP labelled "tested" without a recorded test ride is shown as Unverified; the value is kept.
    """

    static func v2(_ f0: StoreFile, now: Date = Date(), calendar cal: Calendar = .current) -> StoreFile {
        var f = f0
        guard f.schema < 2 else { return f }
        let today = cal.startOfDay(for: now)
        let df = DateFormatter(); df.dateFormat = "EEE d MMM yyyy"; df.locale = Locale(identifier: "en_GB")
        var log: [String] = []

        // M2 — zero-set logs from workout mode
        for i in f.strength.indices {
            let s = f.strength[i]
            guard s.source == "manual", s.startedAt != nil, !(s.exercises ?? []).contains(where: { !$0.doneSets.isEmpty }), s.needsReview == nil else { continue }
            var note = "Migration v2 (\(df.string(from: now))): saved from workout mode with no completed sets (original: \(s.minutes) min, \(s.exercises?.count ?? 0) exercises, none ticked)"
            if s.minutes <= 2 { f.strength[i].minutes = 0; note += "; the duration was a timer artefact and is now 'not recorded'" }
            note += ". Not counted until you confirm it."
            f.strength[i].needsReview = true
            f.strength[i].migrationNote = note
            log.append("\(df.string(from: s.date)): a strength record with no completed sets is waiting for your review (History).")
        }

        // M1 / M3 — completion flags
        for i in f.plan.indices where f.plan[i].done {
            let w = f.plan[i]
            let day = cal.startOfDay(for: w.date)
            if day > today {
                f.plan[i].done = false; f.plan[i].completion = nil
                f.plan[i].migrationNote = "Migration v2: was marked completed for a future date (\(df.string(from: w.date))); set back to planned (original: done = true)."
                for j in f.strength.indices where f.strength[j].workoutId == w.id {
                    f.strength[j].workoutId = nil; f.strength[j].unplanned = true
                    let add = "Was linked to the session planned for \(df.string(from: w.date)); kept on its own date."
                    f.strength[j].migrationNote = (f.strength[j].migrationNote.map { $0 + " " } ?? "") + add
                }
                log.append("\(w.displayTitle) on \(df.string(from: w.date)) was marked completed before its day — set back to planned.")
                continue
            }
            if w.completion != nil { continue }
            let counted = f.strength.filter { !$0.awaitingReview }
            var evidence = false
            if w.kind == .strength {
                evidence = counted.contains { $0.workoutId == w.id } || counted.contains { $0.workoutId == nil && $0.unplanned != true && cal.isDate($0.date, inSameDayAs: w.date) }
            } else if w.kind.isRide {
                evidence = f.rides.contains { !$0.demo && cal.isDate($0.start, inSameDayAs: w.date) }
            }
            if evidence { f.plan[i].completion = .recorded; continue }
            f.plan[i].done = false
            f.plan[i].migrationNote = "Migration v2: was marked completed but no log or recorded ride exists for \(df.string(from: w.date)) (a deleted or reassigned log); set back to planned (original: done = true)."
            if w.kind == .strength || w.kind.isRide { log.append("\(w.displayTitle) on \(df.string(from: w.date)) had no log behind its 'completed' mark — set back to planned.") }
        }

        // M4 — FTP label
        if f.profile.ftpHow == .tested, f.profile.ftpVerifiedTest != true {
            log.append("FTP \(f.profile.ftpW) W was labelled 'tested' but no test ride was recorded — now shown as Unverified (value kept).")
        }

        f.schema = 2
        if !log.isEmpty { f.migrationLog += log }
        return f
    }
}

extension Workout {
    /// Exercises filled by the personalised planner (its progression and reasons are in `rationale`).
    var plannerBuilt: Bool { generatedEntries && rationale != nil && templateId == nil }
}
