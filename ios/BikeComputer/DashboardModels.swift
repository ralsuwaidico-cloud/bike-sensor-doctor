import Foundation

// Training Mix and Recovery dashboards (owner's shared design direction, 23 Nov 2026, 19:55) — the pages the second and
// third Home circles open. Built on the approved Consistency Dashboard's structure: compact summary · Weeks / Days ·
// interactive graph with a floating label · inspection card · ONE summary from the records · breakdown rows · details.
// Foundation only; nothing here writes anything, and no figure is produced that the records do not hold.

// MARK: - Training Mix
//
// A DISTRIBUTION measure, not a score: how the recorded training time divides between the athlete's sports, beside what
// was planned. The Home ring's own numbers (`TrainingLedger.riding` / `.lifting`):
//   • Recorded minutes  Cycling = the durations of recorded and imported rides, plus the minutes the athlete typed for a
//                       planned ride marked done. Strength = the minutes of strength sessions (logged, quick-logged,
//                       imported), plus typed minutes of a planned session marked done. A session without a duration
//                       adds none — it is never estimated.
//   • Planned minutes   the planned, not skipped, rides and strength sessions of the period.
//   • Overlap           every recording counts in full for its own sport; two recordings at the same time are both
//                       counted (the app has no rule for overlapping recordings).
//   • Other sports      Cyclift records rides and strength sessions only. A roster sport it cannot record has no minutes
//                       and says "Not recorded yet" — it is never shown as 0 % and never folded into another sport.
// No adherence bands are used here, and nothing says what a "good" balance is.

struct MixSession: Equatable, Identifiable {
    var base: ConsistencySession
    /// Minutes recorded (or typed) for it; nil when nothing with a duration exists.
    var recorded: Int?
    /// Minutes planned for it; nil for a recording outside the plan.
    var planned: Int?
    var id: String { base.id }
    /// "58 min recorded · 60 min planned" / "Missed · 45 min planned" / "35 min · not in the plan"
    var detail: String {
        switch base.state {
        case .recorded: return (recorded.map { Fmt.duration(minutes: $0) } ?? "No duration") + " · not in the plan"
        case .completed:
            let r = recorded.map { "\(Fmt.duration(minutes: $0)) recorded" } ?? "Done · no duration"
            return planned.map { "\(r) · \(Fmt.duration(minutes: $0)) planned" } ?? r
        default:
            return planned.map { "\(base.state.rawValue) · \(Fmt.duration(minutes: $0)) planned" } ?? base.state.rawValue
        }
    }
}

struct MixPoint: Equatable, Identifiable {
    enum Kind: Equatable { case recorded, empty, upcoming }
    var id: Int
    var start: Date
    var short: String           // "16 Nov" / "Thu"
    var title: String           // "Week of 16–22 Nov" / "Thursday 19 Nov"
    var kind: Kind
    var inProgress: Bool
    var cycling = 0, strength = 0
    var plannedCycling = 0, plannedStrength = 0
    var sessions: [MixSession] = []
    var total: Int { cycling + strength }
    var planned: Int { plannedCycling + plannedStrength }
    static func percent(_ part: Int, of whole: Int) -> Int { whole > 0 ? Int((Double(part) / Double(whole) * 100).rounded()) : 0 }
    /// "Cycling 71% · Strength 29%" — only sports with recorded time.
    var distribution: String {
        var parts: [String] = []
        if cycling > 0 { parts.append("Cycling \(MixPoint.percent(cycling, of: total))%") }
        if strength > 0 { parts.append("Strength \(MixPoint.percent(strength, of: total))%") }
        return parts.joined(separator: " · ")
    }
    /// The floating label: the period and its recorded time, then the distribution where there is one.
    var tooltip: [String] {
        switch kind {
        case .recorded: return ["\(Fmt.duration(minutes: total)) · \(short)", distribution]
        case .empty: return [(inProgress ? "Nothing recorded yet · " : "No recorded training · ") + short]
        case .upcoming: return ["Upcoming · \(short)"]
        }
    }
    var headline: String {
        switch kind {
        case .recorded: return "\(title) — \(Fmt.duration(minutes: total)) recorded"
        case .empty: return "\(title) — no recorded training"
        case .upcoming: return "\(title) — upcoming"
        }
    }
    /// What the planned-time line of this period stands at, in words.
    var plannedText: String { planned > 0 ? "\(Fmt.duration(minutes: planned)) planned" : "nothing planned" }
    var spoken: String {
        switch kind {
        case .recorded: return "\(title), \(Fmt.duration(minutes: total)) recorded, \(distribution), \(plannedText)"
        case .empty: return "\(title), no recorded training, \(plannedText)"
        case .upcoming: return "\(title), upcoming, \(plannedText)"
        }
    }
}

struct MixSportRow: Equatable, Identifiable {
    var id: String
    var name: String
    var icon: String
    /// False for a roster activity Cyclift cannot record yet.
    var tracked: Bool
    var minutes = 0, planned = 0
    /// Share of the period's recorded time; nil when nothing is recorded in the period or the sport is not recorded.
    var share: Int?
    var sessions: [MixSession] = []
    var value: String { tracked ? Fmt.duration(minutes: minutes) : "Not recorded yet" }
    var detail: String {
        guard tracked else { return "In your roster · recording coming soon" }
        var parts: [String] = []
        if let s = share { parts.append("\(s)% of recorded time") }
        parts.append(planned > 0 ? "\(Fmt.duration(minutes: planned)) planned" : "Nothing planned")
        return parts.joined(separator: " · ")
    }
    var spoken: String { tracked ? "\(name), \(Fmt.duration(minutes: minutes)) recorded, \(detail)" : "\(name), not recorded yet" }
}

struct TrainingMixDashboard: Equatable {
    var weeks: [MixPoint]
    var selectedWeek: Int
    var days: [MixPoint]
    var sports: [MixSportRow]
    var weekInsight: String
    var week: MixPoint { weeks[selectedWeek] }
    var isCurrentWeek: Bool { selectedWeek == weeks.count - 1 }
    var periodTitle: String { isCurrentWeek ? "This week · \(ConsistencyModel.range(week.start))" : week.title }
    /// True when the athlete has any recorded training in the eight weeks shown.
    var hasRecords: Bool { weeks.contains { $0.total > 0 } }
    /// The top of the graph's scale in minutes: the largest recorded or planned total shown, rounded up to a whole hour.
    static func scale(_ ps: [MixPoint]) -> Int {
        let m = ps.map { max($0.total, $0.planned) }.max() ?? 0
        return max(60, ((m + 59) / 60) * 60)
    }
}

enum TrainingMixModel {
    static func minutes(_ i: ConsistencyModel.Input, from: Date, to: Date) -> (cycling: Int, strength: Int, plannedCycling: Int, plannedStrength: Int) {
        let planned = i.plan.filter { !$0.skipped && $0.date >= from && $0.date < to }
        var rideSecs = i.ledger.rides.filter { $0.start >= from && $0.start < to }.reduce(0) { $0 + $1.durationS }
        var lift = i.ledger.logs.filter { $0.date >= from && $0.date < to }.reduce(0) { $0 + max(0, $1.minutes) }
        for p in planned where p.completion == .marked {
            guard let mm = p.manualMinutes, mm > 0 else { continue }
            if p.kind.isRide, i.ledger.ride(for: p) == nil { rideSecs += mm * 60 }
            if p.kind == .strength, i.ledger.log(for: p) == nil { lift += mm }
        }
        return (rideSecs / 60, lift, planned.filter { $0.kind.isRide }.reduce(0) { $0 + $1.minutes }, planned.filter { $0.kind == .strength }.reduce(0) { $0 + $1.minutes })
    }

    static func sessions(_ i: ConsistencyModel.Input, from: Date, to: Date) -> [MixSession] {
        ConsistencyModel.sessions(i, from: from, to: to).filter { $0.sport == "cycling" || $0.sport == "strength" }.map { s in
            let w = s.workoutID.flatMap { id in i.plan.first { $0.id == id } }
            var rec: Int? = nil
            switch s.record {
            case .ride(let id): rec = i.ledger.rides.first { $0.id == id }.map { $0.durationS / 60 }
            case .strength(let id): rec = i.ledger.logs.first { $0.id == id }.map { $0.minutes }.flatMap { $0 > 0 ? $0 : nil }
            case .none: if let w, w.completion == .marked, let mm = w.manualMinutes, mm > 0 { rec = mm }
            }
            return MixSession(base: s, recorded: rec, planned: w.map(\.minutes))
        }
    }

    private static func fmt(_ pattern: String, _ d: Date, _ cal: Calendar) -> String { let f = DateFormatter(); f.calendar = cal; f.dateFormat = pattern; return f.string(from: d) }

    static func build(_ i: ConsistencyModel.Input, selectedWeek asked: Int? = nil) -> TrainingMixDashboard {
        let cal = i.calendar, today = cal.startOfDay(for: i.now)
        let thisMonday = TrainingLedger.monday(of: i.now, calendar: cal)
        let n = ConsistencyDashboard.weekCount
        func point(_ id: Int, _ from: Date, _ to: Date, short: String, title: String, week: Bool) -> MixPoint {
            let m = minutes(i, from: from, to: to)
            let current = week ? from == thisMonday : from == today
            let kind: MixPoint.Kind = m.cycling + m.strength > 0 ? .recorded : (!week && from > today) ? .upcoming : .empty
            return MixPoint(id: id, start: from, short: short, title: title, kind: kind, inProgress: current, cycling: m.cycling, strength: m.strength,
                            plannedCycling: m.plannedCycling, plannedStrength: m.plannedStrength, sessions: sessions(i, from: from, to: to))
        }
        var weeks: [MixPoint] = []
        for k in 0..<n {
            let m = cal.date(byAdding: .day, value: -7 * (n - 1 - k), to: thisMonday)!
            weeks.append(point(k, m, cal.date(byAdding: .day, value: 7, to: m)!, short: fmt("d MMM", m, cal), title: "Week of \(ConsistencyModel.range(m, calendar: cal))", week: true))
        }
        let sel = min(max(asked ?? n - 1, 0), n - 1)
        let week = weeks[sel]
        var days: [MixPoint] = []
        for k in 0..<7 {
            let d = cal.date(byAdding: .day, value: k, to: week.start)!
            days.append(point(k, d, cal.date(byAdding: .day, value: 1, to: d)!, short: fmt("EEE", d, cal), title: fmt("EEEE d MMM", d, cal), week: false))
        }
        let rows = sports(roster: i.roster, week: week)
        return TrainingMixDashboard(weeks: weeks, selectedWeek: sel, days: days, sports: rows,
                                    weekInsight: weekInsight(week: week, previous: sel > 0 ? weeks[sel - 1] : nil, current: sel == n - 1, rows: rows))
    }

    /// One row per sport of the roster, on the catalogue's own mapping (every cycling activity is recorded as a ride,
    /// every gym activity as a strength session); an activity Cyclift cannot record keeps its own row and says so.
    static func sports(roster: [String], week: MixPoint) -> [MixSportRow] {
        var rows: [MixSportRow] = []
        func tracked(_ id: String, _ name: String, _ icon: String, _ minutes: Int, _ planned: Int) {
            guard !rows.contains(where: { $0.id == id }) else { return }
            rows.append(MixSportRow(id: id, name: name, icon: icon, tracked: true, minutes: minutes, planned: planned,
                                    share: week.total > 0 ? MixPoint.percent(minutes, of: week.total) : nil, sessions: week.sessions.filter { $0.base.sport == id }))
        }
        for id in AthleticRoster.unique(roster) {
            guard let a = AthleticRoster.activity(id) else { continue }
            switch a.planning {
            case .cycling?: tracked("cycling", "Cycling", "bicycle", week.cycling, week.plannedCycling)
            case .strength?: tracked("strength", "Strength", "dumbbell", week.strength, week.plannedStrength)
            case nil: rows.append(MixSportRow(id: a.id, name: a.title, icon: a.symbol, tracked: false))
            }
        }
        if week.cycling > 0 || week.plannedCycling > 0 { tracked("cycling", "Cycling", "bicycle", week.cycling, week.plannedCycling) }
        if week.strength > 0 || week.plannedStrength > 0 { tracked("strength", "Strength", "dumbbell", week.strength, week.plannedStrength) }
        return rows
    }

    // MARK: the one summary — fixed sentences from the recorded minutes. No balance is judged and no cause is guessed.

    static func untracked(_ rows: [MixSportRow]) -> String? {
        let names = rows.filter { !$0.tracked }.map(\.name)
        guard !names.isEmpty else { return nil }
        let list = names.count == 1 ? names[0] : names.dropLast().joined(separator: ", ") + " and " + names.last!
        return "\(list) \(names.count == 1 ? "is" : "are") in your roster, but Cyclift does not record \(names.count == 1 ? "it" : "them") yet, so \(names.count == 1 ? "it is" : "they are") not part of this mix."
    }

    /// Short on purpose (owner, 24 Nov 2026): what the distribution amounts to and how it stands against the plan, in
    /// words — the figures themselves are on the graph, the label and the card beside it.
    static func weekInsight(week w: MixPoint, previous: MixPoint?, current: Bool, rows: [MixSportRow]) -> String {
        let when = current ? "so far this week" : "in this week"
        guard w.total > 0 else {
            if current { return w.planned > 0 ? "Nothing is recorded yet this week; your planned sessions are still to come." : "Nothing is recorded yet this week." }
            return w.planned > 0 ? "Nothing was recorded in this week, although sessions were planned." : "Nothing was recorded or planned in this week."
        }
        var s: [String] = []
        if w.cycling > 0 && w.strength > 0 {
            s.append(w.cycling == w.strength ? "Cycling and strength took equal recorded time \(when)."
                     : "\(w.cycling > w.strength ? "Cycling" : "Strength") made up most of your recorded training \(when).")
        } else {
            s.append("All of your recorded training \(when) was \(w.cycling > 0 ? "cycling" : "strength").")
        }
        if current { if w.planned > 0 { s.append("The week is still in progress.") } }
        else if w.planned > 0 {
            // "about" when within five minutes of the plan: small differences in a recording are not a shortfall
            let diff = w.total - w.planned
            s.append(abs(diff) <= 5 ? "That is about what was planned." : diff < 0 ? "That is less than was planned." : "That is more than was planned.")
        } else { s.append("None of it was planned.") }
        return s.joined(separator: " ")
    }

    static func dayInsight(day p: MixPoint, calendar cal: Calendar = .current) -> String {
        let name = fmt("EEEE", p.start, cal)
        var s: [String] = []
        switch p.kind {
        case .recorded:
            s.append(p.cycling > 0 && p.strength > 0 ? "On \(name) you recorded both cycling and strength." : "On \(name) you recorded \(p.cycling > 0 ? "cycling" : "strength") only.")
        case .empty:
            s.append(p.inProgress ? "Nothing is recorded yet today." : "Nothing is recorded on \(name).")
        case .upcoming:
            s.append(p.planned > 0 ? "\(name)'s planned training is still to come." : "Nothing is planned or recorded for \(name).")
        }
        let open = p.sessions.filter { $0.base.state == .missed }.map(\.base.title)
        if !open.isEmpty { s.append("Planned and not recorded: \(open.joined(separator: ", ")).") }
        return s.joined(separator: " ")
    }
}

// MARK: - Floating label of a line chart
//
// The approved Consistency rule first (above the point; otherwise below; otherwise beside). Where that rule would give up
// and send the label to the top of the chart — a closely packed, zigzag line can leave no free place — the label stays AT
// its point instead (owner, 24 Nov 2026): above or below it, leaning left or right, in the place that covers the fewest
// neighbouring points. It never covers its own point and never leaves the chart.
enum DashTooltipRule {
    static func place(px: Double, py: Double, w: Double, h: Double, width: Double, height: Double, others: [(Double, Double)]) -> (box: ConsistencyTooltip.Box, side: String) {
        let first = ConsistencyTooltip.place(px: px, py: py, w: w, h: h, width: width, height: height, others: others)
        if first.side != .top { return (first.box, first.side.rawValue) }
        let gap = ConsistencyTooltip.gap
        func clampX(_ x: Double) -> Double { min(max(x, w / 2 + 2), max(w / 2 + 2, width - w / 2 - 2)) }
        var best: (box: ConsistencyTooltip.Box, side: String, covered: Int)? = nil
        for (y, side) in [(py - gap - h / 2, "above"), (py + gap + h / 2, "below")] {
            for x in [clampX(px), clampX(px - 14 + w / 2), clampX(px + 14 - w / 2)] {
                let b = ConsistencyTooltip.Box(x: x, y: y, w: w, h: h)
                guard b.minY >= 0, b.maxY <= height, !b.covers(px, py, margin: 6) else { continue }
                let n = others.filter { b.covers($0.0, $0.1, margin: 5) }.count
                if best == nil || n < best!.covered { best = (b, side, n) }
            }
        }
        if let b = best { return (b.box, b.side) }
        return (first.box, first.side.rawValue)
    }
}

// MARK: - Recovery
//
// The readings the app already keeps (`RecoveryLog`: one reading per kind per day, read from Apple Health, each with the
// source Apple Health names and the time of the sample). Three are recovery indicators here, as on Home: sleep, resting
// heart rate, heart-rate variability. THERE IS NO RECOVERY SCORE: nothing is combined, weighted or turned into a
// percentage, and no reading is said to prove readiness. A week's figure is the plain average of the readings recorded
// in that week, shown with how many there were. A day or a week without a reading has none — never a zero.

struct RecoveryReading: Equatable, Identifiable {
    var kind: HealthSample.Kind
    var value: Double?
    /// Days with a reading (1 for a day point).
    var count: Int
    var source: String?
    var date: Date?
    var id: String { kind.rawValue }
    var text: String { value.map { RecoveryAnalysis.valueText(kind, $0) } ?? "No reading" }
}

struct RecoveryPoint: Equatable, Identifiable {
    enum Kind: Equatable { case value, noReading, upcoming }
    var id: Int
    var start: Date
    var short: String
    var title: String
    var isWeek: Bool
    var kind: Kind
    /// The chosen metric for this period.
    var reading: RecoveryReading
    /// All three indicators for this period, for the inspection card.
    var all: [RecoveryReading]
    static func unit(_ k: HealthSample.Kind, _ n: Int) -> String { k == .sleep ? (n == 1 ? "night" : "nights") : (n == 1 ? "day" : "days") }
    static func time(_ d: Date?) -> String { guard let d else { return "" }; let f = DateFormatter(); f.dateFormat = "HH:mm"; return f.string(from: d) }
    /// One line, the size of the Consistency Dashboard's label, so that it is placed by the same rule and stays beside its
    /// point (owner, 24 Nov 2026): "7 h 20 min · Thu"; a week: "Avg 7 h 10 min · 16 Nov". The source, the time and the
    /// number of readings are in the inspection card directly below the graph.
    var tooltip: [String] {
        switch kind {
        case .value:
            return [isWeek ? "Avg \(reading.text) · \(short)" : "\(reading.text) · \(short)"]
        case .noReading: return ["No reading · \(short)"]
        case .upcoming: return ["Upcoming · \(short)"]
        }
    }
    var headline: String {
        switch kind {
        case .value: return isWeek ? "\(title) — average \(reading.text)" : "\(title) — \(reading.text)"
        case .noReading: return "\(title) — no \(RecoveryDashboard.name(reading.kind).lowercased()) reading"
        case .upcoming: return "\(title) — upcoming"
        }
    }
    var spoken: String {
        switch kind {
        case .value: return "\(title), \(RecoveryDashboard.name(reading.kind)) \(isWeek ? "average " : "")\(reading.text)"
        case .noReading: return "\(title), no reading"
        case .upcoming: return "\(title), upcoming"
        }
    }
}

struct RecoveryRow: Equatable, Identifiable {
    var kind: HealthSample.Kind
    var name: String
    var icon: String
    var latest: String?
    /// When the latest reading was taken; nil when there is none.
    var latestDate: Date?
    /// "Inside your usual range · 7.1–8.2 h from 24 nights" / "No usual range yet · 3 of the 7 readings needed" / "No reading".
    /// The words "your usual range" appear ONLY when the existing personal baseline exists: at least 7 of the athlete's
    /// own readings in the 28 days before the latest one.
    var trend: String
    /// "Apple Watch · Sat 7 Nov, 07:12 · fresh" / "No reading"
    var source: String
    /// The last 14 days, oldest first: true where a reading exists.
    var availability: [Bool]
    /// Most recent first.
    var recent: [RecoveryEntry]
    var enabled: Bool
    var id: String { kind.rawValue }
    var status: String { latest ?? (enabled ? "No reading yet" : "Not connected") }
    /// "Mon 23 Nov" — the day of the latest reading, for the header.
    var latestDay: String { guard let d = latestDate else { return "" }; let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f.string(from: d) }
    var spoken: String { latest.map { "\(name), latest \($0), \(trend), \(source)" } ?? "\(name), \(status)" }
}

struct RecoveryDashboard: Equatable {
    static let kinds: [HealthSample.Kind] = [.sleep, .restingHR, .hrv]
    static func name(_ k: HealthSample.Kind) -> String { switch k { case .sleep: return "Sleep"; case .restingHR: return "Resting HR"; case .hrv: return "HRV"; case .weight: return "Weight" } }
    static func icon(_ k: HealthSample.Kind) -> String { switch k { case .sleep: return "bed.double.fill"; case .restingHR: return "heart.fill"; case .hrv: return "waveform.path.ecg"; case .weight: return "scalemass" } }
    var metric: HealthSample.Kind
    var weeks: [RecoveryPoint]
    var selectedWeek: Int
    var days: [RecoveryPoint]
    var rows: [RecoveryRow]
    var weekInsight: String
    var week: RecoveryPoint { weeks[selectedWeek] }
    var isCurrentWeek: Bool { selectedWeek == weeks.count - 1 }
    var periodTitle: String { isCurrentWeek ? "This week · \(ConsistencyModel.range(week.start))" : week.title }
    /// True when any of the three indicators has any reading at all.
    var hasAny: Bool { rows.contains { $0.latest != nil } }
    /// True when the chosen metric has a reading anywhere in the eight weeks.
    var metricHasData: Bool { weeks.contains { $0.kind == .value } }

    /// The graph's own scale for one metric — never shared between metrics. nil when there is nothing to draw.
    static func scale(_ ps: [RecoveryPoint]) -> (low: Double, high: Double)? {
        let vs = ps.compactMap { $0.kind == .value ? $0.reading.value : nil }
        guard let lo = vs.min(), let hi = vs.max(), let k = ps.first?.reading.kind else { return nil }
        let step: Double = k == .sleep ? 0.5 : 5
        var a = (lo / step).rounded(.down) * step, b = (hi / step).rounded(.up) * step
        if b - a < step * 2 { a -= step; b += step }
        a = max(0, a)
        // an even number of steps, so the middle label of the scale is a round value too
        if Int(((b - a) / step).rounded()) % 2 != 0 { b += step }
        return (a, b)
    }
    static func axis(_ k: HealthSample.Kind, _ v: Double) -> String {
        switch k {
        case .sleep: return v == v.rounded() ? "\(Int(v)) h" : String(format: "%.1f h", v)
        default: return "\(Int(v.rounded()))"
        }
    }
}

enum RecoveryDashModel {
    private static func fmt(_ pattern: String, _ d: Date, _ cal: Calendar) -> String { let f = DateFormatter(); f.calendar = cal; f.dateFormat = pattern; return f.string(from: d) }

    static func reading(_ k: HealthSample.Kind, _ log: RecoveryLog, from: Date, to: Date) -> RecoveryReading {
        let xs = log.entries(k).filter { $0.date >= from && $0.date < to }.sorted { $0.date < $1.date }
        guard !xs.isEmpty else { return RecoveryReading(kind: k, value: nil, count: 0, source: nil, date: nil) }
        let sources = Array(Set(xs.map { $0.source ?? "Apple Health" })).sorted()
        return RecoveryReading(kind: k, value: xs.reduce(0) { $0 + $1.value } / Double(xs.count), count: xs.count,
                               source: sources.count == 1 ? sources[0] : "\(sources.count) sources", date: xs.last?.date)
    }

    static func build(log: RecoveryLog, enabled: [HealthSample.Kind], metric: HealthSample.Kind, selectedWeek asked: Int? = nil, now: Date, calendar cal: Calendar = .current) -> RecoveryDashboard {
        let today = cal.startOfDay(for: now), thisMonday = TrainingLedger.monday(of: now, calendar: cal)
        let n = ConsistencyDashboard.weekCount
        func point(_ id: Int, _ from: Date, _ to: Date, short: String, title: String, week: Bool) -> RecoveryPoint {
            let all = RecoveryDashboard.kinds.map { reading($0, log, from: from, to: to) }
            let r = all.first { $0.kind == metric } ?? RecoveryReading(kind: metric, value: nil, count: 0, source: nil, date: nil)
            let kind: RecoveryPoint.Kind = r.value != nil ? .value : (!week && from > today) ? .upcoming : .noReading
            return RecoveryPoint(id: id, start: from, short: short, title: title, isWeek: week, kind: kind, reading: r, all: all)
        }
        var weeks: [RecoveryPoint] = []
        for k in 0..<n {
            let m = cal.date(byAdding: .day, value: -7 * (n - 1 - k), to: thisMonday)!
            weeks.append(point(k, m, cal.date(byAdding: .day, value: 7, to: m)!, short: fmt("d MMM", m, cal), title: "Week of \(ConsistencyModel.range(m, calendar: cal))", week: true))
        }
        let sel = min(max(asked ?? n - 1, 0), n - 1)
        var days: [RecoveryPoint] = []
        for k in 0..<7 {
            let d = cal.date(byAdding: .day, value: k, to: weeks[sel].start)!
            days.append(point(k, d, cal.date(byAdding: .day, value: 1, to: d)!, short: fmt("EEE", d, cal), title: fmt("EEEE d MMM", d, cal), week: false))
        }
        let rows: [RecoveryRow] = RecoveryDashboard.kinds.map { k in
            let m = RecoveryAnalysis.metric(k, log: log, now: now, calendar: cal)
            let trend: String
            if let l = m.latest {
                if let b = m.baseline, m.standing != .noBaseline {
                    let basis = "\(RecoveryAnalysis.rangeText(k, b)) from \(b.records) \(RecoveryPoint.unit(k, b.records))"
                    switch m.standing {
                    case .lower: trend = "Below your usual range · \(basis)"
                    case .higher: trend = "Above your usual range · \(basis)"
                    default: trend = "Inside your usual range · \(basis)"
                    }
                } else {
                    // no baseline: say so, with how many of the athlete's own readings exist — never a made-up range
                    let from = cal.date(byAdding: .day, value: -RecoveryAnalysis.baselineDays, to: cal.startOfDay(for: l.date)) ?? l.date
                    let have = log.entries(k).filter { $0.date >= from && $0.id != l.id }.count
                    trend = "No usual range yet · \(have) of the \(RecoveryAnalysis.minBaselineRecords) earlier readings needed"
                }
            } else { trend = "No reading" }
            return RecoveryRow(kind: k, name: RecoveryDashboard.name(k), icon: RecoveryDashboard.icon(k), latest: m.latest.map { RecoveryAnalysis.valueText(k, $0.value) },
                               latestDate: m.latest?.date, trend: trend, source: m.sourceLine, availability: m.series.map { $0 != nil },
                               recent: Array(log.entries(k).sorted { $0.date > $1.date }.prefix(7)), enabled: enabled.contains(k))
        }
        return RecoveryDashboard(metric: metric, weeks: weeks, selectedWeek: sel, days: days, rows: rows,
                                 weekInsight: weekInsight(week: weeks[sel], previous: sel > 0 ? weeks[sel - 1] : nil, current: sel == n - 1, anyMetricData: weeks.contains { $0.kind == .value }))
    }

    // MARK: the one summary — what the readings say, in fixed sentences. No readiness, no diagnosis, no score.

    static func noun(_ k: HealthSample.Kind) -> String { switch k { case .sleep: return "sleep"; case .restingHR: return "resting heart rate"; case .hrv: return "HRV"; case .weight: return "weight" } }

    static func weekInsight(week w: RecoveryPoint, previous: RecoveryPoint?, current: Bool, anyMetricData: Bool) -> String {
        let k = w.reading.kind, noun = noun(k)
        guard anyMetricData else { return "There are no \(noun) readings yet, so there is nothing to describe." }
        guard let v = w.reading.value else { return current ? "There is no \(noun) reading yet this week." : "There is no \(noun) reading in this week." }
        var s: [String] = []
        let when = current ? "so far this week" : "in this week"
        if w.reading.count == 1 { s.append("One \(noun) reading \(when): \(RecoveryAnalysis.valueText(k, v)).") }
        else { s.append("Your recorded \(noun) averaged \(RecoveryAnalysis.valueText(k, v)) \(when), from \(w.reading.count) \(RecoveryPoint.unit(k, w.reading.count)).") }
        if let p = previous, let pv = p.reading.value, p.reading.count >= 3, w.reading.count >= 3 {
            let a = RecoveryAnalysis.valueText(k, v), b = RecoveryAnalysis.valueText(k, pv)
            s.append(a == b ? "That is the same as the week before." : v > pv ? "That is higher than the week before (\(b))." : "That is lower than the week before (\(b)).")
        } else {
            s.append("There is not enough \(noun) data to compare with the week before.")
        }
        return s.joined(separator: " ")
    }

    static func dayInsight(day p: RecoveryPoint, calendar cal: Calendar = .current) -> String {
        let name = fmt("EEEE", p.start, cal), k = p.reading.kind
        switch p.kind {
        case .value: return "On \(name) your recorded \(noun(k)) was \(p.reading.text) (\(p.reading.source ?? "Apple Health"))."
        case .noReading: return "There is no \(noun(k)) reading for \(name)."
        case .upcoming: return "\(name) has not happened yet, so there is no reading."
        }
    }
}

extension Store {
    private func dashboardInput(now: Date, calendar cal: Calendar) -> ConsistencyModel.Input {
        .init(plan: plan, ledger: ledger, roster: AthleticRoster.roster(of: profile), planStart: planEffectiveStart,
              title: { [weak self] w in HomeText.title(w, routine: self?.routine(for: w)) }, now: now, calendar: cal)
    }
    /// The Training Mix dashboard for this athlete's own records. Reads only.
    func trainingMixDashboard(selectedWeek: Int? = nil, now: Date = Date(), calendar cal: Calendar = .current) -> TrainingMixDashboard {
        TrainingMixModel.build(dashboardInput(now: now, calendar: cal), selectedWeek: selectedWeek)
    }
    /// The Recovery dashboard for this athlete's own readings. Reads only.
    func recoveryDashboard(metric: HealthSample.Kind, selectedWeek: Int? = nil, now: Date = Date(), calendar cal: Calendar = .current) -> RecoveryDashboard {
        RecoveryDashModel.build(log: recoveryLog, enabled: enabledHealthReads, metric: metric, selectedWeek: selectedWeek, now: now, calendar: cal)
    }
}
