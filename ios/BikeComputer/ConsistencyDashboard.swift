import Foundation

// MARK: - Consistency Dashboard (owner's design direction, 23 Nov 2026, 11:59) — the page the Home Consistency ring opens.
//
// ONE definition, the Home ring's own (`TrainingLedger`): consistency = completed eligible planned sessions ÷ eligible
// planned sessions.
//   • Eligible   a planned ride or strength session that is not skipped — the sessions Cyclift plans and records.
//   • Completed  an eligible session the ledger reports completed: recorded, imported or marked done. Each record
//                completes at most one planned session (the ledger's rule), so nothing is counted twice.
//   • Skipped    left out of both numbers, and counted separately.
//   • Missed     an eligible session whose day has passed without completion. Today and later days are never missed.
//   • In progress  a started session is still planned and not yet completed.
//   • Moved      a moved session is counted on the day it now has; the plan keeps no record of the move, so there is no
//                separate "rescheduled" count.
//   • Unplanned recordings are listed and never counted.
//   • Planned sessions of another kind (mobility, other activity) are listed as "not counted": the Home ring does not
//     count them either. (The older Weekly overview page does — a difference reported to the owner, not changed here.)
// A period with no eligible session has NO percentage — never 0 %. Nothing here writes anything. Foundation only.

/// The three display bands (owner: initial visual bands, not a performance classification or a coaching threshold).
enum ConsistencyBand: String, Equatable {
    case high, moderate, low
    static func of(percent p: Int) -> ConsistencyBand { p >= 80 ? .high : p >= 50 ? .moderate : .low }
    var range: String { switch self { case .high: return "80–100%"; case .moderate: return "50–79%"; case .low: return "0–49%" } }
}

struct ConsistencyCount: Equatable {
    var planned = 0, done = 0, missed = 0, skipped = 0
    var open: Int { max(0, planned - done - missed) }
    /// nil when nothing eligible was planned: there is no percentage then.
    var percent: Int? { planned > 0 ? Int((Double(done) / Double(planned) * 100).rounded()) : nil }
    var fraction: Double? { planned > 0 ? min(1, Double(done) / Double(planned)) : nil }
    var ratio: String { "\(done) of \(planned)" }
}

/// One session behind a figure: a planned session with its real state, or a recording outside the plan.
struct ConsistencySession: Equatable, Identifiable {
    enum State: String, Equatable {
        case completed = "Completed", missed = "Missed", skipped = "Skipped", inProgress = "In progress"
        case today = "Planned today", upcoming = "Upcoming", recorded = "Recorded · not in the plan", notCounted = "Planned · not counted"
    }
    var id: String
    var date: Date
    var title: String
    /// "cycling", "strength", or "" for a session no sport row covers.
    var sport: String
    var state: State
    var isRide: Bool
    /// The planned session, when there is one.
    var workoutID: UUID?
    var record: HomeDayItem.Record
    /// True for a session inside the calculation (eligible, skipped ones excluded).
    var counted: Bool
}

/// One point of the graph: a week, or a day of the selected week.
struct ConsistencyPoint: Equatable, Identifiable {
    enum Kind: Equatable {
        case evaluated      // a finished period with eligible sessions: has a percentage and a band
        case inProgress     // the current week, or today with a session still open: percentage so far, no band
        case upcoming       // a later day with planned sessions: no percentage
        case rest           // a day with nothing planned
        case noPlanned      // a week with no eligible planned session
        case beforePlan     // before the plan started
    }
    var id: Int
    var start: Date
    var axis: String            // "16 Nov" / "Thu"
    var title: String           // "Week of 16–22 Nov" / "Thursday 26 Nov"
    var kind: Kind
    var count: ConsistencyCount
    var sessions: [ConsistencySession]
    var percent: Int? { kind == .evaluated || kind == .inProgress ? count.percent : nil }
    var band: ConsistencyBand? { kind == .evaluated ? count.percent.map(ConsistencyBand.of(percent:)) : nil }
    /// The words that stand beside the figure, or instead of one.
    var status: String {
        switch kind {
        case .evaluated: return band.map { $0.range } ?? ""
        case .inProgress: return "In progress"
        case .upcoming: return "Upcoming"
        case .rest: return count.skipped > 0 ? "Skipped" : sessions.isEmpty ? "Rest day" : "Nothing planned"
        case .noPlanned: return "No planned sessions"
        case .beforePlan: return "Before your plan"
        }
    }
    var headline: String { percent.map { "\(title) — \($0)%" } ?? "\(title) — \(status)" }
    var line: String {
        switch kind {
        case .evaluated: return "\(count.ratio) planned sessions completed"
        case .inProgress: return "\(count.ratio) planned sessions completed so far"
        case .upcoming: return "\(count.planned) planned session\(count.planned == 1 ? "" : "s") · not due yet"
        case .rest: return count.skipped > 0 ? "The planned session was skipped, so this day is not counted."
            : sessions.isEmpty ? "Nothing was planned. A rest day is not counted." : "Nothing was planned, so this day is not counted. What you recorded is listed, outside the plan."
        case .noPlanned: return "No sessions were planned, so there is no percentage."
        case .beforePlan: return "Before your plan started. Not counted."
        }
    }
    var spoken: String { percent.map { "\(title), \($0) percent, \(count.ratio) planned sessions completed, \(status)" } ?? "\(title), \(status)" }
    /// The floating label at a chosen point: the figure and its period — or, where there is no figure, the truthful
    /// status. A period in progress shows its figure so far and says so.
    var tooltip: String {
        switch kind {
        case .evaluated: return "\(percent ?? 0)% · \(axis)"
        case .inProgress: return "In progress · \(percent ?? 0)%"
        case .noPlanned: return "No plan · \(axis)"
        default: return "\(status) · \(axis)"
        }
    }
}

/// Where the floating label of a chosen point goes (owner, 23 Nov 2026, 14:04): immediately above the point; when that
/// would leave the chart or cover another point, below it, then beside it; always wholly inside the chart, never over the
/// chosen point. Plain numbers so the rule is tested without a screen.
enum ConsistencyTooltip {
    struct Box: Equatable {
        var x: Double, y: Double, w: Double, h: Double     // centre and size
        var minX: Double { x - w / 2 }; var maxX: Double { x + w / 2 }; var minY: Double { y - h / 2 }; var maxY: Double { y + h / 2 }
        func covers(_ px: Double, _ py: Double, margin: Double) -> Bool { px > minX - margin && px < maxX + margin && py > minY - margin && py < maxY + margin }
    }
    enum Side: String, Equatable { case above, below, right, left, top }
    static let gap = 12.0
    static func place(px: Double, py: Double, w: Double, h: Double, width: Double, height: Double, others: [(Double, Double)]) -> (box: Box, side: Side) {
        func clampX(_ x: Double) -> Double { min(max(x, w / 2 + 2), max(w / 2 + 2, width - w / 2 - 2)) }
        func inside(_ b: Box) -> Bool { b.minX >= 0 && b.maxX <= width && b.minY >= 0 && b.maxY <= height }
        func clear(_ b: Box) -> Bool { !b.covers(px, py, margin: 6) && !others.contains { b.covers($0.0, $0.1, margin: 5) } }
        let candidates: [(Box, Side)] = [
            (Box(x: clampX(px), y: py - gap - h / 2, w: w, h: h), .above),
            (Box(x: clampX(px), y: py + gap + h / 2, w: w, h: h), .below),
            (Box(x: px + gap + w / 2, y: min(max(py, h / 2), height - h / 2), w: w, h: h), .right),
            (Box(x: px - gap - w / 2, y: min(max(py, h / 2), height - h / 2), w: w, h: h), .left)]
        for c in candidates where inside(c.0) && clear(c.0) { return c }
        // nothing free beside the point: the strip kept clear along the top of the chart, above the 100 % line
        return (Box(x: clampX(px), y: h / 2 + 1, w: w, h: h), .top)
    }
}

struct ConsistencySportRow: Equatable, Identifiable {
    var id: String              // "cycling", "strength", or the roster activity id
    var name: String
    var icon: String
    /// False for a roster activity Cyclift does not plan or record yet.
    var tracked: Bool
    var count: ConsistencyCount
    var inProgress: Bool
    var sessions: [ConsistencySession]
    var percent: Int? { tracked ? count.percent : nil }
    var band: ConsistencyBand? { inProgress ? nil : percent.map(ConsistencyBand.of(percent:)) }
    var status: String {
        if !tracked { return "Not tracked yet" }
        guard let p = percent else { return "No planned sessions" }
        return "\(p)%"
    }
    var detail: String { !tracked ? "In your roster · plans coming soon" : count.planned == 0 ? "Nothing planned in this period" : "\(count.done) / \(count.planned) sessions" }
    var spoken: String { tracked ? (percent.map { "\(name), \($0) percent, \(count.ratio) planned sessions completed" } ?? "\(name), no planned sessions") : "\(name), not tracked yet" }
}

struct ConsistencyDashboard: Equatable {
    static let weekCount = 8
    var hasPlan: Bool
    /// Oldest first; the last is the current week.
    var weeks: [ConsistencyPoint]
    var selectedWeek: Int
    /// Monday to Sunday of the selected week.
    var days: [ConsistencyPoint]
    var sports: [ConsistencySportRow]
    var overallInsight: String
    var sportInsight: String
    var week: ConsistencyPoint { weeks[selectedWeek] }
    var isCurrentWeek: Bool { selectedWeek == weeks.count - 1 }
    var periodTitle: String { isCurrentWeek ? "This week · \(ConsistencyModel.range(week.start))" : week.title }
    /// Recordings of the selected week that no planned session accounts for.
    var unplanned: [ConsistencySession] { week.sessions.filter { $0.state == .recorded } }
}

enum ConsistencyModel {
    struct Input {
        var plan: [Workout]
        var ledger: TrainingLedger
        var roster: [String]
        var planStart: Date?
        var title: (Workout) -> String
        var now: Date
        var calendar: Calendar = .current
    }

    static func range(_ monday: Date, calendar cal: Calendar = .current) -> String {
        let end = cal.date(byAdding: .day, value: 6, to: monday)!
        let f = DateFormatter(); f.calendar = cal; f.dateFormat = "d MMM"
        let a = cal.component(.month, from: monday) == cal.component(.month, from: end) ? "\(cal.component(.day, from: monday))" : f.string(from: monday)
        return "\(a)–\(f.string(from: end))"
    }
    private static func fmt(_ pattern: String, _ d: Date, _ cal: Calendar) -> String { let f = DateFormatter(); f.calendar = cal; f.dateFormat = pattern; return f.string(from: d) }

    static func eligible(_ w: Workout) -> Bool { w.kind.isRide || w.kind == .strength }
    static func sport(_ w: Workout) -> String { w.kind.isRide ? "cycling" : w.kind == .strength ? "strength" : "" }

    /// Every session of [from, to): planned ones with their real state, then recordings outside the plan.
    static func sessions(_ i: Input, from: Date, to: Date) -> [ConsistencySession] {
        let cal = i.calendar, today = cal.startOfDay(for: i.now)
        var out: [ConsistencySession] = []
        var usedRides = Set<UUID>(), usedLogs = Set<UUID>()
        for w in i.plan.filter({ $0.date >= from && $0.date < to && HomeToday.isTraining($0) }).sorted(by: { ($0.date, $0.sequence) < ($1.date, $1.sequence) }) {
            let st = i.ledger.status(w), day = cal.startOfDay(for: w.date)
            var rec: HomeDayItem.Record = .none
            // a skipped session stays skipped (the ledger's weekly counts leave it out even when something was recorded
            // that day); the recording is then listed on its own, outside the plan
            if !w.skipped {
                if w.kind.isRide, let r = i.ledger.ride(for: w) { rec = .ride(r.id); usedRides.insert(r.id) }
                else if let l = i.ledger.log(for: w) { rec = .strength(l.id); usedLogs.insert(l.id) }
            }
            let state: ConsistencySession.State
            if !eligible(w) { state = .notCounted }
            else if w.skipped { state = .skipped }
            else if st.isCompleted { state = .completed }
            else if st == .started || st == .inProgress { state = .inProgress }
            else if day < today { state = .missed }
            else if day == today { state = .today }
            else { state = .upcoming }
            out.append(ConsistencySession(id: w.id.uuidString, date: w.date, title: i.title(w), sport: sport(w), state: state, isRide: w.kind.isRide, workoutID: w.id, record: rec,
                                          counted: eligible(w) && state != .skipped))
        }
        for r in i.ledger.rides.filter({ $0.start >= from && $0.start < to && !usedRides.contains($0.id) }).sorted(by: { $0.start < $1.start }) {
            out.append(ConsistencySession(id: "ride-\(r.id)", date: r.start, title: "Ride", sport: "cycling", state: .recorded, isRide: true, workoutID: nil, record: .ride(r.id), counted: false))
        }
        for l in i.ledger.logs.filter({ $0.date >= from && $0.date < to && !usedLogs.contains($0.id) }).sorted(by: { $0.date < $1.date }) {
            out.append(ConsistencySession(id: "log-\(l.id)", date: l.date, title: l.title, sport: "strength", state: .recorded, isRide: false, workoutID: nil, record: .strength(l.id), counted: false))
        }
        return out.sorted { $0.date < $1.date }
    }

    static func count(_ s: [ConsistencySession]) -> ConsistencyCount {
        var c = ConsistencyCount()
        for x in s where x.state != .recorded && x.state != .notCounted {
            if x.state == .skipped { c.skipped += 1; continue }
            c.planned += 1
            if x.state == .completed { c.done += 1 }
            if x.state == .missed { c.missed += 1 }
        }
        return c
    }

    static func build(_ i: Input, selectedWeek asked: Int? = nil) -> ConsistencyDashboard {
        let cal = i.calendar, today = cal.startOfDay(for: i.now)
        let thisMonday = TrainingLedger.monday(of: i.now, calendar: cal)
        let hasPlan = i.plan.contains { HomeToday.isTraining($0) }
        let start = i.planStart.map { cal.startOfDay(for: $0) }
        var weeks: [ConsistencyPoint] = []
        for k in 0..<ConsistencyDashboard.weekCount {
            let m = cal.date(byAdding: .day, value: -7 * (ConsistencyDashboard.weekCount - 1 - k), to: thisMonday)!
            let e = cal.date(byAdding: .day, value: 7, to: m)!
            let ss = sessions(i, from: m, to: e), c = count(ss)
            let kind: ConsistencyPoint.Kind
            if c.planned == 0 { kind = (start.map { e <= $0 } ?? false) ? .beforePlan : .noPlanned }
            else { kind = m == thisMonday ? .inProgress : .evaluated }
            weeks.append(ConsistencyPoint(id: k, start: m, axis: fmt("d MMM", m, cal), title: "Week of \(range(m, calendar: cal))", kind: kind, count: c, sessions: ss))
        }
        let sel = min(max(asked ?? weeks.count - 1, 0), weeks.count - 1)
        let week = weeks[sel]
        var days: [ConsistencyPoint] = []
        for k in 0..<7 {
            let d = cal.date(byAdding: .day, value: k, to: week.start)!
            let ss = week.sessions.filter { cal.isDate($0.date, inSameDayAs: d) }, c = count(ss)
            let kind: ConsistencyPoint.Kind
            if c.planned == 0 {
                kind = (start.map { d < $0 } ?? false) && ss.isEmpty ? .beforePlan : hasPlan ? .rest : .noPlanned
            } else if d > today { kind = .upcoming }
            else if d == today && c.done < c.planned { kind = .inProgress }
            else { kind = .evaluated }
            days.append(ConsistencyPoint(id: k, start: d, axis: fmt("EEE", d, cal), title: fmt("EEEE d MMM", d, cal), kind: kind, count: c, sessions: ss))
        }
        let rows = sports(roster: i.roster, week: week)
        let previous = sel > 0 ? weeks[sel - 1] : nil
        return ConsistencyDashboard(hasPlan: hasPlan, weeks: weeks, selectedWeek: sel, days: days, sports: rows,
                                    overallInsight: overallInsight(week: week, previous: previous, hasPlan: hasPlan, current: sel == weeks.count - 1),
                                    sportInsight: sportInsight(rows: rows, week: week, hasPlan: hasPlan))
    }

    /// One row per sport of the roster. Every cycling activity is planned and recorded as general cycling, and every
    /// gym activity as gym training (the catalogue's own mapping), so those share one row each; an activity no engine
    /// plans keeps its own row and says so. A sport with sessions in the period is shown even if the roster lacks it.
    static func sports(roster: [String], week: ConsistencyPoint) -> [ConsistencySportRow] {
        var rows: [ConsistencySportRow] = []
        func tracked(_ id: String, _ name: String, _ icon: String) {
            guard !rows.contains(where: { $0.id == id }) else { return }
            let ss = week.sessions.filter { $0.sport == id && $0.state != .recorded && $0.state != .notCounted }
            rows.append(ConsistencySportRow(id: id, name: name, icon: icon, tracked: true, count: count(ss), inProgress: week.kind == .inProgress, sessions: week.sessions.filter { $0.sport == id }))
        }
        for id in AthleticRoster.unique(roster) {
            guard let a = AthleticRoster.activity(id) else { continue }
            switch a.planning {
            case .cycling?: tracked("cycling", "Cycling", "bicycle")
            case .strength?: tracked("strength", "Strength", "dumbbell")
            case nil:
                rows.append(ConsistencySportRow(id: a.id, name: a.title, icon: a.symbol, tracked: false, count: ConsistencyCount(), inProgress: false, sessions: []))
            }
        }
        if week.sessions.contains(where: { $0.sport == "cycling" }) { tracked("cycling", "Cycling", "bicycle") }
        if week.sessions.contains(where: { $0.sport == "strength" }) { tracked("strength", "Strength", "dumbbell") }
        return rows
    }

    // MARK: the two summaries — fixed sentences built from the counts above. No model writes them and no cause is guessed.

    private static func n(_ k: Int, _ one: String, _ many: String) -> String { "\(k) \(k == 1 ? one : many)" }

    static func overallInsight(week: ConsistencyPoint, previous: ConsistencyPoint?, hasPlan: Bool, current: Bool) -> String {
        guard hasPlan else { return "You have no training plan yet. Consistency compares completed sessions with planned ones, so there is nothing to measure." }
        let c = week.count
        guard c.planned > 0, let p = c.percent else {
            return week.kind == .beforePlan ? "This week was before your plan started, so it is not counted." : "No sessions were planned in this week, so there is no consistency figure."
        }
        var s: [String] = []
        if current {
            s.append("You have completed \(c.ratio) planned sessions so far this week.")
            if c.open > 0 { s.append("\(n(c.open, "session is", "sessions are")) still to come.") }
        } else {
            s.append("You completed \(c.ratio) planned sessions in this week.")
            if let b = previous, b.kind == .evaluated, let q = b.count.percent {
                s.append(p > q ? "That is higher than the week before (\(q)%)." : p < q ? "That is lower than the week before (\(q)%)." : "That is the same as the week before (\(q)%).")
            }
        }
        if c.missed > 0 {
            let rides = week.sessions.filter { $0.state == .missed && $0.sport == "cycling" }.count
            let lifts = week.sessions.filter { $0.state == .missed && $0.sport == "strength" }.count
            var parts: [String] = []
            if rides > 0 { parts.append(n(rides, "ride", "rides")) }
            if lifts > 0 { parts.append(n(lifts, "strength session", "strength sessions")) }
            s.append("Missed: \(parts.joined(separator: " and ")).")
        }
        if c.skipped > 0 { s.append("\(n(c.skipped, "skipped session is", "skipped sessions are")) left out of the figure.") }
        return s.joined(separator: " ")
    }

    /// The summary for one chosen day — the same fixed-sentence rule as the week's.
    static func dayInsight(day p: ConsistencyPoint, hasPlan: Bool, calendar cal: Calendar = .current) -> String {
        guard hasPlan else { return "You have no training plan yet. Consistency compares completed sessions with planned ones, so there is nothing to measure." }
        let f = DateFormatter(); f.calendar = cal; f.dateFormat = "EEEE"
        let name = f.string(from: p.start), c = p.count
        let outside = p.sessions.filter { $0.state == .recorded }.count
        var s: [String] = []
        switch p.kind {
        case .evaluated:
            s.append(c.done == c.planned ? "You completed \(c.planned == 1 ? "the planned session" : "all \(c.planned) planned sessions") on \(name)." : "You completed \(c.ratio) planned sessions on \(name).")
            let missed = p.sessions.filter { $0.state == .missed }.map(\.title)
            if !missed.isEmpty { s.append("Missed: \(missed.joined(separator: ", ")).") }
        case .inProgress:
            s.append("\(c.ratio) planned sessions are done so far today.")
        case .upcoming:
            s.append("\(n(c.planned, "session is", "sessions are")) planned for \(name). Not due yet, so nothing is counted.")
        case .rest:
            s.append(c.skipped > 0 ? "The session planned for \(name) was skipped, so the day is not counted." : "Nothing was planned on \(name), so it is not counted.")
        case .noPlanned:
            s.append("No sessions were planned on \(name).")
        case .beforePlan:
            s.append("\(name) was before your plan started, so it is not counted.")
        }
        if c.skipped > 0 && p.kind != .rest { s.append("\(n(c.skipped, "skipped session is", "skipped sessions are")) left out of the figure.") }
        if outside > 0 { s.append("\(n(outside, "recording", "recordings")) outside the plan \(outside == 1 ? "is" : "are") listed and not counted.") }
        return s.joined(separator: " ")
    }

    static func sportInsight(rows: [ConsistencySportRow], week: ConsistencyPoint, hasPlan: Bool) -> String {
        var s: [String] = []
        let measured = rows.filter { $0.tracked && $0.count.planned > 0 }
        if !hasPlan {
            if rows.isEmpty { return "No sport can be assessed yet." }
        } else if measured.isEmpty {
            s.append("No ride or strength session was planned in this period, so sports cannot be compared.")
        } else if week.kind == .inProgress {
            s.append("This week is still in progress, so your sports are not compared yet.")
            for r in measured where r.count.done == r.count.planned { s.append("Every planned \(r.name.lowercased()) session so far is done.") }
        } else if measured.count == 1, let r = measured.first {
            s.append(r.count.done == r.count.planned ? "You completed every planned \(r.name.lowercased()) session." : "You completed \(r.count.ratio) planned \(r.name.lowercased()) sessions.")
        } else {
            let sorted = measured.sorted { ($0.percent ?? 0) > ($1.percent ?? 0) }
            let a = sorted[0], b = sorted[sorted.count - 1]
            if a.percent == b.percent { s.append("\(a.name) and \(b.name) were equally consistent (\(a.percent ?? 0)%).") }
            else { s.append("\(a.name) (\(a.percent ?? 0)%) was more consistent than \(b.name.lowercased()) (\(b.percent ?? 0)%).") }
        }
        let untracked = rows.filter { !$0.tracked }.map(\.name)
        if !untracked.isEmpty {
            let names = untracked.count == 1 ? untracked[0] : untracked.dropLast().joined(separator: ", ") + " and " + untracked.last!
            s.append("\(names) \(untracked.count == 1 ? "is" : "are") in your roster, but Cyclift does not plan or record \(untracked.count == 1 ? "it" : "them") yet, so there is nothing to assess.")
        }
        return s.isEmpty ? "There is nothing to compare yet." : s.joined(separator: " ")
    }
}

extension Store {
    /// The Consistency Dashboard for this athlete's own records. Reads only.
    func consistencyDashboard(selectedWeek: Int? = nil, now: Date = Date(), calendar cal: Calendar = .current) -> ConsistencyDashboard {
        ConsistencyModel.build(.init(plan: plan, ledger: ledger, roster: AthleticRoster.roster(of: profile), planStart: planEffectiveStart,
                                     title: { [weak self] w in HomeText.title(w, routine: self?.routine(for: w)) }, now: now, calendar: cal), selectedWeek: selectedWeek)
    }
}
