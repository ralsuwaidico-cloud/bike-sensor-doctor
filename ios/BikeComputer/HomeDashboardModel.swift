import Foundation

// MARK: - Checkpoint C (owner 5 Nov): the Premium Home Dashboard's numbers, computed once from the store.
// Every value here is read from existing records (plan, ledger, rides, strength logs, profile values with their
// provenance). Nothing is estimated or invented: a tile without data says so through its `SourceTag`, and the hub
// state is the same `HomeToday` the previous Today card used. Foundation only, so the Linux harness tests it.

struct HomeDashboard: Equatable {
    struct Header: Equatable {
        var dateLine: String        // "Wednesday 4 Nov"
        var greeting: String        // "Good morning, Rashed"
        var context: String         // "Hybrid · week 1 · lift today"
    }
    struct Ring: Equatable {
        var done: Int
        var planned: Int
        var remaining: Int
        var missed: Int
        var skipped: Int
        /// "4 remaining · Tue 3 – Sun 8 Nov"
        var sub: String
        /// W12: shown when the plan started after Monday.
        var countedNote: String?
        var fraction: Double { CyDesign.ringFraction(done: done, planned: planned) }
    }
    struct Tile: Equatable {
        var value: String?          // "1 h 02" / "0 of 2"; nil = unknown
        var unit: String?
        var sub: String
        var tag: SourceTag
        /// Last 8 weeks (oldest first) — minutes ridden or sessions lifted; weeks before the first activity are nil (no bar).
        var series: [Double?]
    }
    struct Recovery: Equatable {
        struct Reading: Equatable { var title: String; var value: String; var unit: String; var date: Date }
        var readings: [Reading]
        var hasData: Bool { !readings.isEmpty }
        /// Empty state: what is missing and the one next step.
        var emptyTitle: String { "No readings yet" }
        var emptySub: String { "Connect Apple Health for sleep, resting HR and HRV" }
    }
    struct Goal: Equatable {
        var id: GoalID
        var title: String
        var isMain: Bool
        var measured: String        // "1 ride recorded of 4 needed" / "Progress appears after your first logged ride."
        var detail: String          // what the goal tracks (GoalInfo.effect)
        var next: String?           // "Complete this week's three rides."
    }
    struct Reminder: Equatable {
        var title: String           // "Strength · Full body · 30 min"
        var sub: String             // "Open the Training Hub to start"
    }
    /// The hub's one-word state (the dock reads `CyCentreState` for the look; this is the hub page's heading).
    enum HubState: String, Equatable { case pending, active, completed, missed, rest, multiple, hold, first }

    var header: Header
    var ring: Ring?
    var cycling: Tile?
    var strength: Tile?
    var days: [CyDay]
    var weekTitle: String           // "Week · 2 – 8 Nov"
    var recovery: Recovery
    var goal: Goal?
    var reminder: Reminder?
    var hub: HubState
}

enum HomeDashboardModel {
    static func greeting(hour: Int, name: String) -> String {
        let g = hour < 5 ? "Good night" : hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        let n = name.trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? g : "\(g), \(n)"
    }
    static func dateLine(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMM"; return f.string(from: d)
    }
    /// "2 – 8 Nov" / "28 Sep – 4 Oct": the Monday–Sunday range.
    static func weekRange(monday: Date, calendar cal: Calendar) -> String {
        let sunday = cal.date(byAdding: .day, value: 6, to: monday)!
        let dm = DateFormatter(); dm.dateFormat = "d MMM"
        let d = DateFormatter(); d.dateFormat = "d"
        return cal.isDate(monday, equalTo: sunday, toGranularity: .month) ? "\(d.string(from: monday)) – \(dm.string(from: sunday))" : "\(dm.string(from: monday)) – \(dm.string(from: sunday))"
    }
    /// "Tue 3 – Sun 8 Nov": the counted window from the plan's effective start (or Monday) to Sunday.
    static func windowText(start: Date, monday: Date, calendar cal: Calendar) -> String {
        let sunday = cal.date(byAdding: .day, value: 6, to: monday)!
        let from = max(start, monday)
        let a = DateFormatter(); a.dateFormat = "EEE d"
        let b = DateFormatter(); b.dateFormat = "EEE d MMM"
        return "\(a.string(from: from)) – \(b.string(from: sunday))"
    }
    static func weekNumber(effectiveStart: Date?, now: Date, calendar cal: Calendar) -> Int? {
        guard let s = effectiveStart else { return nil }
        let a = TrainingLedger.monday(of: s, calendar: cal), b = TrainingLedger.monday(of: now, calendar: cal)
        guard b >= a else { return nil }
        return (cal.dateComponents([.day], from: a, to: b).day ?? 0) / 7 + 1
    }
    static func todayWord(_ layout: HomeToday.Layout) -> String? {
        switch layout {
        case .single(let s): return s.isRide ? "ride today" : s.workout.kind == .strength ? "lift today" : "session today"
        case .multi: return "two sessions today"
        case .rest: return "rest day"
        case .hold: return "training paused"
        case .freeSession: return "session in progress"
        case .first: return nil
        }
    }
    static func hubState(_ h: HomeToday) -> HomeDashboard.HubState {
        switch h.layout {
        case .first: return .first
        case .hold: return .hold
        case .freeSession: return .active
        case .rest: return h.missed != nil ? .missed : .rest
        case .single(let s):
            switch s.status {
            case .inProgress: return .active
            case .done, .marked, .imported: return .completed
            case .missed: return .missed
            case .skipped: return h.missed != nil ? .missed : .rest
            case .planned: return .pending
            }
        case .multi(let ss):
            if ss.contains(where: { $0.status == .inProgress }) { return .active }
            let open = ss.filter { $0.status == .planned }
            if open.count > 1 { return .multiple }
            if open.count == 1 { return .pending }
            return ss.allSatisfy({ [.done, .marked, .imported].contains($0.status) }) ? .completed : (h.missed != nil ? .missed : .rest)
        }
    }

    /// The seven days of the current week for the calendar strip. Status: done when every active session is completed;
    /// missed when a planned session's day has passed without completion or skip (today is never missed); planned
    /// otherwise; beforePlan for days before the effective start with nothing recorded (W12); none for rest days.
    static func days(plan: [Workout], status: (Workout) -> WorkoutStatus, effectiveStart: Date?, hasRecord: (Date) -> Bool, now: Date, calendar cal: Calendar) -> [CyDay] {
        let today = cal.startOfDay(for: now)
        let monday = TrainingLedger.monday(of: now, calendar: cal)
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: monday)!
            let all = plan.filter { cal.isDate($0.date, inSameDayAs: d) && HomeToday.isTraining($0) }.sorted { $0.sequence < $1.sequence }
            let active = all.filter { !$0.skipped }
            let ride = active.contains { $0.kind.isRide }, lift = active.contains { $0.kind == .strength }
            let sport: CyDaySport = ride && lift ? .both : ride ? .cycling : lift ? .strength : active.isEmpty ? .rest : .cycling
            var st: CyDayStatus
            if active.isEmpty {
                st = all.isEmpty && CyPlanStart.isBeforePlan(d, effectiveStart: effectiveStart, hasRecord: hasRecord(d), calendar: cal) ? .beforePlan : .none
            } else if active.allSatisfy({ status($0).isCompleted }) {
                st = .done
            } else if d < today, active.contains(where: { status($0) == .planned }) {
                st = .missed
            } else {
                st = .planned
            }
            let long = DateFormatter(); long.dateFormat = "EEEE"
            return CyDay(id: i, shortName: WeeklyAvailability.dayNames[i], longName: long.string(from: d), sport: sport, status: st, isToday: cal.isDate(d, inSameDayAs: now))
        }
    }

    /// Minutes or sessions per week for the mini chart; weeks before the first activity give nil (drawn as no bar).
    static func series(_ buckets: [WeekBucket], firstActivity: Date?, minutes: Bool, calendar cal: Calendar) -> [Double?] {
        let since = firstActivity.map { TrainingLedger.monday(of: $0, calendar: cal) }
        return buckets.map { b in
            guard let s = since, b.start >= s else { return nil }
            return minutes ? Double(b.minutes) : Double(b.sessions)
        }
    }
}

extension Store {
    func homeDashboard(now: Date = Date(), recorderActive: Bool = false, calendar cal: Calendar = .current) -> HomeDashboard {
        let h = homeToday(now: now, recorderActive: recorderActive)
        let w = homeWeek(now: now)
        let monday = TrainingLedger.monday(of: now, calendar: cal)
        let start = planEffectiveStart
        let mode = profile.trainingMode

        // header
        var ctx: [String] = [mode == .hybrid ? "Hybrid" : mode.title]
        if let n = HomeDashboardModel.weekNumber(effectiveStart: start, now: now, calendar: cal) { ctx.append("week \(n)") }
        if let t = HomeDashboardModel.todayWord(h.layout) { ctx.append(t) }
        let header = HomeDashboard.Header(dateLine: HomeDashboardModel.dateLine(now), greeting: HomeDashboardModel.greeting(hour: cal.component(.hour, from: now), name: profile.name), context: ctx.joined(separator: " · "))

        // ring (nil before any plan)
        var ring: HomeDashboard.Ring? = nil
        if case .first = h.layout {} else {
            let t = w.total
            let today = cal.startOfDay(for: now)
            let weekPlan = plan.filter { $0.date >= monday && $0.date < cal.date(byAdding: .day, value: 7, to: monday)! && HomeToday.isTraining($0) && !$0.skipped }
            let missed = weekPlan.filter { cal.startOfDay(for: $0.date) < today && ledger.status($0) == .planned }.count
            let remaining = max(0, t.planned - t.plannedDone - missed)
            let sub = "\(remaining) remaining · \(HomeDashboardModel.windowText(start: start ?? monday, monday: monday, calendar: cal))"
            let note = (start.map { cal.startOfDay(for: $0) > monday && cal.startOfDay(for: $0) <= cal.date(byAdding: .day, value: 6, to: monday)! } ?? false) ? "Counted from the day you approved the plan." : nil
            ring = HomeDashboard.Ring(done: t.plannedDone, planned: t.planned, remaining: remaining, missed: missed, skipped: t.skipped, sub: sub, countedNote: note)
        }

        // sport tiles: this week's recorded time / sessions against the plan, with an 8-week mini series
        let firstRide = rides.filter { !$0.demo }.map(\.start).min()
        let firstLift = strength.map(\.date).min()
        var cycling: HomeDashboard.Tile? = nil, strengthTile: HomeDashboard.Tile? = nil
        if mode != .strength {
            let r = ledger.riding(weekOf: monday)
            let km = Double(rides.filter { !$0.demo && $0.start >= monday && $0.start < cal.date(byAdding: .day, value: 7, to: monday)! }.reduce(0) { $0 + $1.distanceM }) / 1000
            let value: String? = r.completed > 0 ? (r.minutes > 0 ? Fmt.duration(minutes: r.minutes) : "\(r.completed) \(r.completed == 1 ? "ride" : "rides")") : (r.planned > 0 ? "0 of \(r.planned)" : nil)
            var sub: String
            if r.completed > 0 {
                sub = (r.planned > 0 ? "of \(Fmt.duration(minutes: r.plannedMinutes)) planned" : "nothing planned this week") + " · \(r.completed) \(r.completed == 1 ? "ride" : "rides")"
                if km > 0 { sub += String(format: " · %.1f km", km) }
            } else {
                sub = r.planned > 0 ? "rides · \(Fmt.duration(minutes: r.plannedMinutes)) planned" : "nothing planned this week"
            }
            let tag: SourceTag = r.completed == 0 ? .needsData : r.logged > 0 ? .measured : .logged   // recorded rides are measured; quick logs, marks and imports are logged values
            cycling = HomeDashboard.Tile(value: value, unit: nil, sub: sub, tag: tag, series: HomeDashboardModel.series(TrendChartMath.buckets(ledger, riding: true, weeks: 8, now: now, calendar: cal), firstActivity: firstRide, minutes: true, calendar: cal))
        }
        if mode != .cycling {
            let l = ledger.lifting(weekOf: monday)
            let value: String? = l.planned > 0 ? "\(l.plannedDone) of \(l.planned)" : (l.completed > 0 ? "\(l.completed)" : nil)
            var sub = l.planned > 0 ? "sessions" : "nothing planned this week"
            if l.completed == 0, let next = plan.filter({ $0.kind == .strength && !$0.skipped && $0.date >= cal.startOfDay(for: now) && $0.date < cal.date(byAdding: .day, value: 7, to: monday)! }).min(by: { $0.date < $1.date }) {
                sub += cal.isDate(next.date, inSameDayAs: now) ? " · first lift today" : " · next \(HomeText.weekday(next.date))"
            } else if l.minutes > 0 { sub += " · \(Fmt.duration(minutes: l.minutes))" }
            let tag: SourceTag = l.completed == 0 ? .needsData : .logged
            strengthTile = HomeDashboard.Tile(value: value, unit: nil, sub: sub, tag: tag, series: HomeDashboardModel.series(TrendChartMath.buckets(ledger, riding: false, weeks: 8, now: now, calendar: cal), firstActivity: firstLift, minutes: false, calendar: cal))
        }

        // calendar
        let days = HomeDashboardModel.days(plan: plan, status: { [ledger] in ledger.status($0) }, effectiveStart: start, hasRecord: { [weak self] in self?.hasRecord(on: $0, calendar: cal) ?? false }, now: now, calendar: cal)

        // recovery: the latest value of each enabled Health read, with its date (profile provenance); never a score
        var readings: [HomeDashboard.Recovery.Reading] = []
        func read(_ f: ProfileField) -> (ValueSource, Date)? {
            let p = profile.provenance(f)
            guard p.source == .appleHealth || p.source == .entered, let d = p.recordedAt else { return nil }
            return (p.source, d)
        }
        if let s = profile.sleepHours, let (_, d) = read(.sleep) { readings.append(.init(title: "Sleep", value: String(format: "%.1f", s), unit: "h", date: d)) }
        if let r = profile.restHR, let (_, d) = read(.restHR) { readings.append(.init(title: "Resting HR", value: "\(r)", unit: "bpm", date: d)) }
        if let v = profile.hrvMs, let (_, d) = read(.hrv) { readings.append(.init(title: "HRV", value: "\(Int(v.rounded()))", unit: "ms", date: d)) }
        let recovery = HomeDashboard.Recovery(readings: readings)

        // goal: the main goal, what it tracks, what is measured so far (checkpoints), the next step
        var goal: HomeDashboard.Goal? = nil
        if let g = profile.primaryGoal ?? profile.goals.first {
            let sport: Checkpoint.Sport = g.sport == .strength ? .strength : .cycling   // general goals are measured by riding consistency first
            let cps = checkpoints(sport, now: now)
            let first = cps.first
            let noun = sport == .cycling ? "ride" : "session"
            let measured: String
            if let f = first, f.sessions > 0 || f.earliestDate != nil {
                measured = f.reached ? "\(f.sessions) \(noun)\(f.sessions == 1 ? "" : "s") over \(f.countedWeeks) weeks" : "\(f.sessions) \(noun)\(f.sessions == 1 ? "" : "s") recorded" + (f.missing.map { " · \($0)" } ?? "")
            } else {
                measured = "Progress appears after your first logged \(noun)."
            }
            let next = plan.filter { HomeToday.isTraining($0) && !$0.skipped && !ledger.status($0).isCompleted && $0.date >= cal.startOfDay(for: now) && $0.date < cal.date(byAdding: .day, value: 7, to: monday)! && ($0.kind.isRide == (sport == .cycling)) }
            let nextText = next.isEmpty ? nil : "Complete this week's \(next.count) \(sport == .cycling ? (next.count == 1 ? "ride" : "rides") : (next.count == 1 ? "session" : "sessions"))."
            goal = HomeDashboard.Goal(id: g, title: g.title, isMain: profile.primaryGoal == g, measured: measured, detail: GoalInfo.effect(g), next: nextText)
        }

        // compact reminder: today's pending session (the hub holds the card and its actions)
        var reminder: HomeDashboard.Reminder? = nil
        switch h.layout {
        case .single(let s) where s.status == .planned || s.status == .inProgress:
            reminder = .init(title: "\(s.isRide ? "Ride" : s.workout.kind == .strength ? "Strength" : s.workout.kind.title) · \(s.title)" + (s.workout.minutes > 0 ? " · \(Fmt.duration(minutes: s.workout.minutes))" : ""), sub: s.status == .inProgress ? "Open the Training Hub to resume" : "Open the Training Hub to start")
        case .multi(let ss):
            let open = ss.filter { $0.status == .planned || $0.status == .inProgress }
            if !open.isEmpty { reminder = .init(title: open.count == 1 ? "\(open[0].title)" : "\(open.count) sessions today", sub: open.contains { $0.status == .inProgress } ? "Open the Training Hub to resume" : "Open the Training Hub") }
        case .freeSession: reminder = .init(title: "Strength session in progress", sub: "Open the Training Hub to resume")
        default: break
        }

        return HomeDashboard(header: header, ring: ring, cycling: cycling, strength: strengthTile, days: days,
                             weekTitle: "Week · \(HomeDashboardModel.weekRange(monday: monday, calendar: cal))",
                             recovery: recovery, goal: goal, reminder: reminder, hub: HomeDashboardModel.hubState(h))
    }
}
