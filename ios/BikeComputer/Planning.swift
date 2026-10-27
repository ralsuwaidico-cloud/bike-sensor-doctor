import Foundation

// MARK: - One formatter for every duration shown as text ("1 h 40 min", never "1.66667 h")
enum Fmt {
    static func duration(minutes m: Int) -> String {
        if m <= 0 { return "0 min" }
        let h = m / 60, mm = m % 60
        if h == 0 { return "\(mm) min" }
        return mm == 0 ? "\(h) h" : "\(h) h \(mm) min"
    }
    static func duration(seconds s: Int) -> String { duration(minutes: (s + 30) / 60) }
    /// Compact form for narrow cells: "1h40", "45′", "2h".
    static func compact(minutes m: Int) -> String {
        if m <= 0 { return "—" }
        let h = m / 60, mm = m % 60
        if h == 0 { return "\(mm)′" }
        return mm == 0 ? "\(h)h" : "\(h)h\(String(format: "%02d", mm))"
    }
    static func km(_ meters: Int, imperial: Bool) -> String { imperial ? String(format: "%.1f mi", Double(meters) / 1609.34) : String(format: "%.1f km", Double(meters) / 1000) }
}

// MARK: - Per-day sport assignment (0.7.0): what exactly happens each day
enum CyclingType: String, Codable, CaseIterable {
    case zone2, tempo, threshold, intervals, recovery, long, custom
    var title: String { switch self { case .zone2: return "Zone 2 / endurance"; case .tempo: return "Tempo"; case .threshold: return "Threshold"; case .intervals: return "Intervals"; case .recovery: return "Recovery"; case .long: return "Long ride"; case .custom: return "Custom" } }
    var short: String { switch self { case .zone2: return "Zone 2"; case .tempo: return "Tempo"; case .threshold: return "Threshold"; case .intervals: return "Intervals"; case .recovery: return "Recovery"; case .long: return "Long"; case .custom: return "Custom" } }
    var kind: WorkoutKind { switch self { case .zone2: return .endurance; case .tempo: return .tempo; case .threshold: return .threshold; case .intervals: return .vo2; case .recovery: return .recovery; case .long: return .long; case .custom: return .endurance } }
    var defaultMinutes: Int { kind.defaultMinutes }
    var isHard: Bool { kind.zone >= 3 }
}

struct DayAssignment: Codable, Identifiable, Equatable {
    enum Sport: String, Codable { case cycling, strength }
    var id = UUID()
    var sport: Sport
    var cyclingType: CyclingType? = nil
    var strengthType: StrengthFocus? = nil
    var minutes: Int
    /// Fixed = the coach never moves or changes it; flexible = the coach may propose changes within the budget.
    var fixed = false

    init(id: UUID = UUID(), sport: Sport, cyclingType: CyclingType? = nil, strengthType: StrengthFocus? = nil, minutes: Int, fixed: Bool = false) {
        self.id = id; self.sport = sport; self.cyclingType = cyclingType; self.strengthType = strengthType; self.minutes = minutes; self.fixed = fixed
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        sport = (try? c.decodeIfPresent(Sport.self, forKey: .sport)) ?? .cycling
        cyclingType = try? c.decodeIfPresent(CyclingType.self, forKey: .cyclingType)
        strengthType = try? c.decodeIfPresent(StrengthFocus.self, forKey: .strengthType)
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
        fixed = try c.decodeIfPresent(Bool.self, forKey: .fixed) ?? false
    }
    var title: String { sport == .cycling ? (cyclingType?.title ?? "Ride") : (strengthType?.title ?? "Strength") }
    var short: String { sport == .cycling ? (cyclingType?.short ?? "Ride") : (strengthType?.short ?? "Lift") }
    /// Equality by content: two schedules with the same activities are the same schedule whatever the row ids.
    static func == (a: DayAssignment, b: DayAssignment) -> Bool { a.sport == b.sport && a.cyclingType == b.cyclingType && a.strengthType == b.strengthType && a.minutes == b.minutes && a.fixed == b.fixed }
}

// MARK: - Weekly availability: the rider chooses the days, the engine plans around them
struct DayAvailability: Codable, Equatable {
    enum Activity: String, Codable, CaseIterable {
        case cycle, lift, both, other, rest
        var title: String { switch self { case .cycle: return "Cycling"; case .lift: return "Strength"; case .both: return "Both"; case .other: return "Other"; case .rest: return "Rest" } }
        var short: String { switch self { case .cycle: return "Cycle"; case .lift: return "Lift"; case .both: return "Both"; case .other: return "Other"; case .rest: return "Rest" } }
        var icon: String { switch self { case .cycle: return "bicycle"; case .lift: return "dumbbell"; case .both: return "plus.circle"; case .other: return "figure.run"; case .rest: return "moon.zzz" } }
        var cycles: Bool { self == .cycle || self == .both }
        var lifts: Bool { self == .lift || self == .both }
    }
    /// Legacy summary fields (0.5.0/0.6.0 files): kept in sync with `assignments` so older code paths and files agree.
    var activity: Activity
    var minutes: Int
    var liftMinutes: Int? = nil
    /// 0.7.0: the exact activities of the day. Empty = rest. Derived from the legacy fields when a file lacks it.
    var assignments: [DayAssignment] = []
    /// A flexible day: the coach may use it (or not) and move sessions onto it; a day with only fixed assignments is fixed.
    var flexible = false
    /// "Other" minutes (run, swim…) — not cycling, not lifting.
    var otherMinutes = 0

    init(activity: Activity, minutes: Int, liftMinutes: Int? = nil) {
        self.activity = activity; self.minutes = minutes; self.liftMinutes = liftMinutes
        assignments = DayAvailability.legacyAssignments(activity: activity, minutes: minutes, liftMinutes: liftMinutes)
        otherMinutes = activity == .other ? minutes : 0
    }
    init(assignments: [DayAssignment], flexible: Bool = false, otherMinutes: Int = 0) {
        self.assignments = assignments; self.flexible = flexible; self.otherMinutes = otherMinutes
        activity = .rest; minutes = 0
        syncLegacy()
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activity = (try? c.decodeIfPresent(Activity.self, forKey: .activity)) ?? .rest
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
        liftMinutes = try c.decodeIfPresent(Int.self, forKey: .liftMinutes)
        flexible = (try? c.decodeIfPresent(Bool.self, forKey: .flexible)) ?? false
        otherMinutes = (try? c.decodeIfPresent(Int.self, forKey: .otherMinutes)) ?? (activity == .other ? minutes : 0)
        if let a = try? c.decodeIfPresent([DayAssignment].self, forKey: .assignments) { assignments = a; syncLegacy() }
        else { assignments = DayAvailability.legacyAssignments(activity: activity, minutes: minutes, liftMinutes: liftMinutes) }
    }
    static func legacyAssignments(activity: Activity, minutes: Int, liftMinutes: Int?) -> [DayAssignment] {
        switch activity {
        case .rest, .other: return []
        case .cycle: return [DayAssignment(sport: .cycling, cyclingType: nil, minutes: minutes)]
        case .lift: return [DayAssignment(sport: .strength, strengthType: nil, minutes: minutes)]
        case .both: return [DayAssignment(sport: .cycling, cyclingType: nil, minutes: minutes), DayAssignment(sport: .strength, strengthType: nil, minutes: liftMinutes ?? 30)]
        }
    }
    /// Keeps the legacy summary in step with the assignments (called after every edit).
    mutating func syncLegacy() {
        let c = assignments.filter { $0.sport == .cycling }, s = assignments.filter { $0.sport == .strength }
        if !c.isEmpty && !s.isEmpty { activity = .both; minutes = c.reduce(0) { $0 + $1.minutes }; liftMinutes = s.reduce(0) { $0 + $1.minutes } }
        else if !c.isEmpty { activity = .cycle; minutes = c.reduce(0) { $0 + $1.minutes }; liftMinutes = nil }
        else if !s.isEmpty { activity = .lift; minutes = s.reduce(0) { $0 + $1.minutes }; liftMinutes = nil }
        else if otherMinutes > 0 { activity = .other; minutes = otherMinutes; liftMinutes = nil }
        else { activity = .rest; minutes = 0; liftMinutes = nil }
    }
    var cycleMinutes: Int { assignments.filter { $0.sport == .cycling }.reduce(0) { $0 + $1.minutes } }
    var liftingMinutes: Int { assignments.filter { $0.sport == .strength }.reduce(0) { $0 + $1.minutes } }
    var cycles: Bool { assignments.contains { $0.sport == .cycling } }
    var lifts: Bool { assignments.contains { $0.sport == .strength } }
    var isRest: Bool { assignments.isEmpty && otherMinutes == 0 }
    /// Cycling / Strength / Both / Rest / Flexible — the brief's day marks.
    var mark: String { flexible && isRest ? "Flexible" : isRest ? "Rest" : (cycles && lifts) ? "Both" : cycles ? "Cycling" : lifts ? "Strength" : "Other" }
    var fixedCount: Int { assignments.filter { $0.fixed }.count }
    var totalMinutes: Int { cycleMinutes + liftingMinutes + otherMinutes }
}

/// One budget problem the engine refuses to plan through silently, with the ways to resolve it.
struct PlanConflict: Equatable, Identifiable {
    enum Sport: String { case cycling, lifting }
    var id: String { sport.rawValue }
    var sport: Sport
    var plannedMinutes: Int
    var budgetMinutes: Int
    var overMinutes: Int { plannedMinutes - budgetMinutes }
    /// Concrete options; the first is applied by `fit` when the rider has not chosen.
    var options: [String]
    var text: String { "Your \(sport.rawValue) days add up to \(Fmt.duration(minutes: plannedMinutes)) against a \(Fmt.duration(minutes: budgetMinutes)) \(sport.rawValue) budget — \(Fmt.duration(minutes: overMinutes)) over." }
}

struct WeeklyAvailability: Codable, Equatable {
    /// Seven entries, Monday first.
    var days: [DayAvailability]
    static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let longDayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    init(days: [DayAvailability]) { self.days = days }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        days = (try? c.decodeIfPresent([DayAvailability].self, forKey: .days)) ?? []
        if days.count != 7 { days = Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7) }
    }

    /// A sensible starting schedule from the rider's weekly hours: more hours → more cycling days, Saturday is the long ride.
    static func suggested(hoursPerWeek h: Int) -> WeeklyAvailability {
        var d = Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7)
        d[5] = DayAvailability(activity: .cycle, minutes: min(180, max(60, h * 20)))       // Saturday long
        d[1] = DayAvailability(activity: .cycle, minutes: 60)                                // Tuesday
        d[2] = DayAvailability(activity: .cycle, minutes: 70)                                // Wednesday (quality)
        d[4] = DayAvailability(activity: .cycle, minutes: 45)                                // Friday easy
        d[6] = DayAvailability(activity: .lift, minutes: 30)                                 // Sunday strength
        if h >= 6 { d[3] = DayAvailability(activity: .cycle, minutes: 60) }
        if h <= 3 { d[1] = DayAvailability(activity: .rest, minutes: 0); d[4] = DayAvailability(activity: .rest, minutes: 0) }
        return WeeklyAvailability(days: d)
    }
    /// A schedule from the rider's mode, frequencies, priority, budgets and preferred days. Cycling mode keeps the
    /// 0.5.0 suggestion. Lifts go on non-adjacent days where possible; the longest ride lands on Saturday (or the first
    /// preferred weekend day); a "Both" day is used only when the rider wants more sessions than days. Never exceeds
    /// either budget: per-session minutes are the budget divided by the frequency.
    static func suggested(for p: RiderProfile) -> WeeklyAvailability {
        guard p.trainingMode != .cycling else {
            // audit G-20: the requested number of rides (the 0.5.0 template is trimmed: shortest non-long rides go
            // first), and no off-bike session the rider did not ask for
            var t = suggested(hoursPerWeek: p.hoursPerWeek)
            for i in t.days.indices where t.days[i].lifts && !t.days[i].cycles { t.days[i] = DayAvailability(activity: .rest, minutes: 0) }
            let want = max(1, p.cyclingDaysPerWeek)
            var rideDays = t.days.indices.filter { t.days[$0].cycles }
            while rideDays.count > want, let drop = rideDays.filter({ $0 != 5 }).min(by: { t.days[$0].cycleMinutes < t.days[$1].cycleMinutes }) {
                t.days[drop] = DayAvailability(activity: .rest, minutes: 0); rideDays.removeAll { $0 == drop }
            }
            for i in [3, 1, 4, 6, 0, 2] where rideDays.count < want && !t.days[i].cycles && !rideDays.contains(where: { abs($0 - i) == 0 }) {
                t.days[i] = DayAvailability(activity: .cycle, minutes: 60); rideDays.append(i)
            }
            return WeeklyAvailability.fit(t, profile: p).availability
        }
        var d = Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7)
        var preferred = p.preferredDays.isEmpty ? [1, 3, 5, 6, 2, 4, 0] : p.preferredDays + [1, 3, 5, 6, 2, 4, 0].filter { !p.preferredDays.contains($0) }
        // adaptive coach: the rider's total training days (the preferred days first); the other days are rest days
        if let n = p.trainingDaysPerWeek, n >= 1, n < 7 { preferred = Array(preferred.prefix(n)) }
        let trainingDays = preferred
        let split: StrengthSplit? = p.trainingMode.includesLifting ? p.strengthSplit : nil
        let rides = p.trainingMode.includesCycling ? max(0, min(p.trainingDaysPerWeek != nil ? 10 : 6, p.cyclingDaysPerWeek)) : 0
        let lifts = max(0, min(p.trainingDaysPerWeek != nil ? 10 : 6, p.liftDaysPerWeek))
        let rideBudget = p.hoursPerWeek * 60, liftBudget = max(1, p.liftingHoursPerWeek) * 60
        var rideMin = rides > 0 ? max(30, rideBudget / rides) : 0
        var liftMin = lifts > 0 ? max(20, liftBudget / lifts) : 0
        if let m = p.strengthSessionMinutes, m > 0, liftMin > 0 { liftMin = min(liftMin, max(15, m)) }
        var order = preferred
        if rides > 0, let wk = order.first(where: { $0 >= 5 }) {
            // long ride = 1.5 × the others, with the rest shrunk so the week stays inside the budget
            let longMin = rides > 1 ? min(240, (rideBudget * 3) / (2 * rides + 1)) : rideBudget
            rideMin = rides > 1 ? max(30, (rideBudget - longMin) / (rides - 1)) : 0
            d[wk] = DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: longMin >= 90 ? .long : .zone2, minutes: longMin)]); order.removeAll { $0 == wk }
        }
        if let m = p.cyclingSessionMinutes, m > 0, rideMin > 0 { rideMin = min(rideMin, max(20, m)) }
        var ridesLeft = rides - d.filter { $0.cycles }.count
        var liftsLeft = lifts
        var takeRide = p.priority != .strength
        var qualityPlaced = false
        for day in order where ridesLeft > 0 || liftsLeft > 0 {
            if (takeRide && ridesLeft > 0) || liftsLeft == 0 {
                // with a strength split the quality ride is left to the plan engine, which keeps it off leg days
                // F-03: rides are left untyped so the week builder applies the goal-based intensity and the block's easy
                // week to every flexible ride (it picks the one quality session)
                let t: CyclingType? = nil
                _ = qualityPlaced
                d[day] = DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: t, minutes: rideMin)]); ridesLeft -= 1
            } else { d[day] = DayAvailability(assignments: [DayAssignment(sport: .strength, strengthType: nil, minutes: liftMin)]); liftsLeft -= 1 }
            if ridesLeft > 0, liftsLeft > 0 { takeRide.toggle() }
        }
        // audit G-17 / M-06: the single-sport days chosen above keep their sports' counts, but the lifts move to the
        // combination of those days with the most rest between them (≥ 48 h, ≥ 72 h for older riders or slow
        // recovery, when the days allow), so two lifts never sit on back-to-back days when another layout exists
        let used = (0..<7).filter { i in d[i].assignments.count == 1 && (d[i].assignments[0].sport == .strength || (d[i].assignments[0].sport == .cycling && order.contains(i))) }
        let liftDays0 = used.filter { d[$0].assignments[0].sport == .strength }
        if liftDays0.count >= 2 {
            func gap(_ a: Int, _ b: Int) -> Int { let x = abs(a - b); return min(x, 7 - x) }
            func minGap(_ ds: [Int]) -> Int { var m = 7; for i in ds.indices { for j in ds.indices where j > i { m = min(m, gap(ds[i], ds[j])) } }; return m }
            func combos(_ xs: [Int], _ k: Int) -> [[Int]] { if k == 0 { return [[]] }; if xs.count < k { return [] }; let h = xs[0], t = Array(xs.dropFirst()); return combos(t, k - 1).map { [h] + $0 } + combos(t, k) }
            let want = p.recovery.reduced ? 3 : 2
            let rank: (Int) -> Int = { order.firstIndex(of: $0) ?? 9 }
            let best = combos(used, liftDays0.count).max { a, b in
                let ga = min(minGap(a), want), gb = min(minGap(b), want)
                if ga != gb { return ga < gb }
                // tie: stay as close as possible to the rider's own day order (fewer moved lifts first)
                let ma = a.filter { !liftDays0.contains($0) }.count, mb = b.filter { !liftDays0.contains($0) }.count
                if ma != mb { return ma > mb }
                return a.map(rank).reduce(0, +) > b.map(rank).reduce(0, +)
            } ?? liftDays0
            if Set(best) != Set(liftDays0), min(minGap(best), want) > min(minGap(liftDays0), want) {
                let liftA = liftDays0.map { d[$0].assignments[0] }
                let rideDays0 = used.filter { d[$0].assignments[0].sport == .cycling }
                let rideA = rideDays0.sorted { rank($0) < rank($1) }.map { d[$0].assignments[0] }
                let newRideDays = used.filter { !best.contains($0) }.sorted { rank($0) < rank($1) }
                for (k, day) in best.sorted().enumerated() { d[day] = DayAvailability(assignments: [liftA[k]]) }
                for (k, day) in newRideDays.enumerated() where k < rideA.count { d[day] = DayAvailability(assignments: [rideA[k]]) }
            }
        }
        // more sessions than days: pair the remaining lifts with rides (upper body, so legs are not loaded twice) and
        // the remaining rides with lifts — never an extra day
        var i = 0
        while liftsLeft > 0, i < 7 {
            if d[i].cycles, !d[i].lifts { var a = d[i].assignments; a.append(DayAssignment(sport: .strength, strengthType: split != nil ? nil : .upper, minutes: liftMin)); d[i] = DayAvailability(assignments: a); liftsLeft -= 1 }
            i += 1
        }
        i = 0
        while ridesLeft > 0, i < 7 {
            if d[i].lifts, !d[i].cycles { var a = d[i].assignments; a.append(DayAssignment(sport: .cycling, cyclingType: .zone2, minutes: rideMin)); d[i] = DayAvailability(assignments: a); ridesLeft -= 1 }
            i += 1
        }
        // adaptive coach: still more sessions than slots (frequency above the training days) → a further session on
        // the training day with the fewest, never a new day
        var extraGuard = 0
        while p.trainingDaysPerWeek != nil, ridesLeft > 0 || liftsLeft > 0, !trainingDays.isEmpty, extraGuard < 40 {
            extraGuard += 1
            guard let day = trainingDays.min(by: { (d[$0].assignments.count, $0) < (d[$1].assignments.count, $1) }) else { break }
            var a = d[day].assignments
            if liftsLeft > 0, ridesLeft == 0 || !d[day].lifts { a.append(DayAssignment(sport: .strength, strengthType: nil, minutes: liftMin)); liftsLeft -= 1 }
            else { a.append(DayAssignment(sport: .cycling, cyclingType: .zone2, minutes: rideMin)); ridesLeft -= 1 }
            d[day] = DayAvailability(assignments: a)
        }
        return fit(WeeklyAvailability(days: d), profile: p).availability
    }

    var cycleMinutes: Int { days.reduce(0) { $0 + $1.cycleMinutes } }
    var cycleDays: Int { days.filter { $0.cycles }.count }
    var liftMinutes: Int { days.reduce(0) { $0 + $1.liftingMinutes } }
    var liftDays: Int { days.filter { $0.lifts }.count }
    var totalMinutes: Int { days.reduce(0) { $0 + $1.totalMinutes } }
    var fixedAssignments: Int { days.reduce(0) { $0 + $1.fixedCount } }

    /// Budget check without changing anything: one conflict per sport that is over.
    func conflicts(profile p: RiderProfile) -> [PlanConflict] {
        var out: [PlanConflict] = []
        let cb = p.hoursPerWeek * 60, lb = p.liftingHoursPerWeek * 60
        if p.trainingMode.includesCycling, cycleMinutes > cb {
            let longest = days.enumerated().flatMap { i, d in d.assignments.filter { $0.sport == .cycling }.map { (i, $0) } }.max { $0.1.minutes < $1.1.minutes }
            var o = ["Raise the cycling budget to \(Fmt.duration(minutes: cycleMinutes)) in Profile › Training profile"]
            if let l = longest { o.append("Shorten \(WeeklyAvailability.dayNames[l.0])'s \(l.1.short.lowercased()) ride to \(Fmt.duration(minutes: max(20, l.1.minutes - (cycleMinutes - cb))))") }
            if cycleDays > 1 { o.append("Drop one cycling day") }
            out.append(PlanConflict(sport: .cycling, plannedMinutes: cycleMinutes, budgetMinutes: cb, options: o))
        }
        if p.trainingMode.includesLifting, lb > 0, liftMinutes > lb {
            let longest = days.enumerated().flatMap { i, d in d.assignments.filter { $0.sport == .strength }.map { (i, $0) } }.max { $0.1.minutes < $1.1.minutes }
            var o = ["Raise the lifting budget to \(Fmt.duration(minutes: liftMinutes)) in Profile › Training profile"]
            if let l = longest { o.append("Shorten \(WeeklyAvailability.dayNames[l.0])'s lift to \(Fmt.duration(minutes: max(15, l.1.minutes - (liftMinutes - lb))))") }
            if liftDays > 1 { o.append("Drop one lifting day") }
            out.append(PlanConflict(sport: .lifting, plannedMinutes: liftMinutes, budgetMinutes: lb, options: o))
        }
        return out
    }

    /// Makes the week fit both budgets WITHOUT adding days: flexible assignments are shortened first (longest first,
    /// 5-minute steps, never under 20 min riding / 15 min lifting), then fixed ones. Returns what was trimmed so the
    /// UI can show it and ask; the plan generated from the result can never exceed a budget by a minute.
    static func fit(_ a: WeeklyAvailability, profile p: RiderProfile) -> (availability: WeeklyAvailability, conflicts: [PlanConflict], trimmed: [String]) {
        var w = a
        let conflicts = a.conflicts(profile: p)
        var trimmed: [String] = []
        func trim(sport: DayAssignment.Sport, budget: Int, floor: Int) {
            var total = w.days.reduce(0) { $0 + $1.assignments.filter { $0.sport == sport }.reduce(0) { $0 + $1.minutes } }
            var guardLoop = 0
            while total > budget, guardLoop < 10_000 {
                guardLoop += 1
                // candidates: flexible first, longest first
                var best: (day: Int, idx: Int)? = nil
                var bestKey = (fixed: 2, minutes: -1)
                for (di, d) in w.days.enumerated() { for (ai, x) in d.assignments.enumerated() where x.sport == sport && x.minutes > floor {
                    let key = (fixed: x.fixed ? 1 : 0, minutes: x.minutes)
                    if key.fixed < bestKey.fixed || (key.fixed == bestKey.fixed && key.minutes > bestKey.minutes) { bestKey = key; best = (di, ai) }
                } }
                guard let b = best else { break }
                let step = min(5, total - budget, w.days[b.day].assignments[b.idx].minutes - floor)
                guard step > 0 else { break }
                w.days[b.day].assignments[b.idx].minutes -= step
                w.days[b.day].syncLegacy()
                total -= step
                let name = "\(WeeklyAvailability.dayNames[b.day]) \(w.days[b.day].assignments[b.idx].short.lowercased())"
                if let i = trimmed.firstIndex(where: { $0.hasPrefix(name) }) { trimmed[i] = "\(name): now \(Fmt.duration(minutes: w.days[b.day].assignments[b.idx].minutes))" } else { trimmed.append("\(name): now \(Fmt.duration(minutes: w.days[b.day].assignments[b.idx].minutes))") }
            }
        }
        if p.trainingMode.includesCycling { trim(sport: .cycling, budget: p.hoursPerWeek * 60, floor: 20) }
        if p.trainingMode.includesLifting, p.liftingHoursPerWeek > 0 { trim(sport: .strength, budget: p.liftingHoursPerWeek * 60, floor: 15) }
        return (w, conflicts, trimmed)
    }

    /// Consistency check for the onboarding/editor preview: frequency vs days, durations vs budgets.
    func consistency(profile p: RiderProfile) -> [String] {
        var out: [String] = []
        if p.trainingMode.includesCycling, cycleDays != p.cyclingDaysPerWeek { out.append("You asked for \(p.cyclingDaysPerWeek) rides a week but assigned \(cycleDays) cycling day\(cycleDays == 1 ? "" : "s").") }
        if p.trainingMode.includesLifting, liftDays != p.liftDaysPerWeek { out.append("You asked for \(p.liftDaysPerWeek) lifts a week but assigned \(liftDays) strength day\(liftDays == 1 ? "" : "s").") }
        for c in conflicts(profile: p) { out.append(c.text) }
        return out
    }
}

// MARK: - Plan engine (deterministic, built around the availability; never over budget)
enum PlanEngine {
    /// The week for `monday`, one Workout per assignment (rest days produce a rest entry so every day has a card).
    /// Rules: a day's sessions are ordered by the rider's priority; the long ride goes to the longest cycling
    /// assignment that has no type; one quality session is picked for untyped rides; a leg-loading lift is not placed
    /// next to a hard ride when a choice exists; fixed assignments keep their exact type and minutes. The availability
    /// is fitted to both budgets first, so a generated week can never exceed either budget.
    /// Coach remediation: `returning` (M-02, from logged rides) and the health check (M-01, `p.readiness`) cap what a
    /// generated week may contain. Fixed rides the rider typed are never changed; they get a visible warning instead.
    static func week(starting monday: Date, profile p: RiderProfile, availability raw: WeeklyAvailability, returning: ReturnPhase? = nil, trainingWeeks: Int? = nil, calendar cal: Calendar = .current) -> [Workout] {
        let a = WeeklyAvailability.fit(raw, profile: p).availability
        let readiness = p.readiness
        let d = { (i: Int) in cal.date(byAdding: .day, value: i, to: monday)! }
        // --- cycling types for untyped (nil/custom-less) assignments
        var cycTypes: [UUID: WorkoutKind] = [:]
        let cyc: [(day: Int, a: DayAssignment)] = a.days.enumerated().flatMap { i, dd in dd.assignments.filter { $0.sport == .cycling }.map { (i, $0) } }
        for c in cyc { if let t = c.a.cyclingType { cycTypes[c.a.id] = t.kind } }
        let untyped = cyc.filter { $0.a.cyclingType == nil }
        // --- strength focus per lift assignment (typed ones keep theirs)
        let lifts: [(day: Int, a: DayAssignment)] = a.days.enumerated().flatMap { i, dd in dd.assignments.filter { $0.sport == .strength }.map { (i, $0) } }
        let untypedLifts = lifts.filter { $0.a.strengthType == nil }
        let focusCycle: [StrengthFocus] = lifts.count <= 1 ? [.fullBody] : lifts.count == 2 ? [.lower, .upper] : [.lower, .push, .pull, .upper, .fullBody, .lower]
        // a neighbouring hard-typed ride weighs 2, any neighbouring ride 1 (its type may still become hard), a same-day ride 2
        func load(_ i: Int) -> Int { a.days[i].assignments.contains { $0.sport == .cycling && ($0.cyclingType?.isHard ?? false) } ? 2 : (a.days[i].cycles ? 1 : 0) }
        func adjHard(_ i: Int) -> Int { load((i + 1) % 7) + load((i + 6) % 7) + (a.days[i].cycles ? 2 : 0) }
        var focus: [UUID: StrengthFocus] = [:]
        for l in lifts { if let t = l.a.strengthType { focus[l.a.id] = t } }
        // adaptive coach: a chosen split is followed in day order (its rotation, not a fixed number of days)
        let split: StrengthSplit? = p.trainingMode.includesLifting ? p.strengthSplit : nil
        var slotFor: [UUID: SplitSlot] = [:]
        if let split {
            let seq = StrengthSplit.sessions(split: split, slots: p.customSplit, count: untypedLifts.count, offset: StrengthSplit.weekIndex(of: monday, calendar: cal) * untypedLifts.count)
            for (n, l) in untypedLifts.enumerated() where n < seq.count { focus[l.a.id] = seq[n].focus; slotFor[l.a.id] = seq[n] }
        } else {
            let liftOrder = untypedLifts.sorted { (adjHard($0.day), $0.day) < (adjHard($1.day), $1.day) }
            for (n, l) in liftOrder.enumerated() {
                var f = focusCycle[n % focusCycle.count]
                if a.days[l.day].cycles, f.loadsLegs { f = .upper }        // same-day ride: do not load the legs twice
                focus[l.a.id] = f
            }
        }
        let legDays = Set(lifts.filter { focus[$0.a.id]?.loadsLegs == true }.map { $0.day })
        func adjacentToLegs(_ i: Int) -> Bool { legDays.contains((i + 1) % 7) || legDays.contains((i + 6) % 7) }
        /// With a split, a leg session may share a day with a ride: that ride is never the quality one.
        func legClash(_ i: Int) -> Bool { adjacentToLegs(i) || (split != nil && legDays.contains(i)) }
        // long ride: the longest untyped assignment (prefer not next to a leg day); quality: second longest ≥ 45 min
        // M-05 block position: weeks of consecutive riding before this one (from logs). Every `deloadEvery`-th week is an
        // easier week (no interval session, long ride 20 % shorter); otherwise threshold intervals build by one
        // repetition per week of the block, within the session's minutes. 3:1 / 2:1 loading is common coaching
        // practice, not an evidence-derived rule (ios/COACH_REMEDIATION.md).
        let every = p.recovery.deloadEvery
        let blockPos = trainingWeeks.map { $0 % every }
        let easyWeek = blockPos == every - 1
        var thresholdReps: Int? = nil
        if let pos = blockPos, !easyWeek { thresholdReps = 3 + min(pos, 2) }     // the target; the largest count that fits is used (F-07)
        // M-05 intensity by goal and level: beginners tempo; performance goals (stronger, climbing, event) threshold;
        // health / endurance / weight goals tempo; advanced performance riders with ≥ 4 rides add one VO2 session
        let performanceGoal = p.goal == .stronger || p.goal == .climbing || p.goal == .event
        let hard: WorkoutKind = p.level == .beginner ? .tempo : (performanceGoal ? .threshold : .tempo)
        // review P3-14 (N-09 residual): days typed by older versions (or by the rider without fixing them) follow the goal
        // too — a typed interval day harder than the goal and level allow is planned at the goal's intensity, with a note
        // saying how to keep it (mark the day fixed). Fixed days are never changed. The availability itself is unchanged.
        let maxTyped: WorkoutKind = (p.level == .advanced && performanceGoal) ? .vo2 : hard
        var goalNote: [UUID: String] = [:]
        for c in cyc where !c.a.fixed {
            if let k = cycTypes[c.a.id], k.zone >= 3, k.zone > maxTyped.zone {
                cycTypes[c.a.id] = maxTyped
                goalNote[c.a.id] = "Your goal (\(p.goal.title.lowercased())) and level plan \(maxTyped.title.lowercased()) here rather than \(k.title.lowercased()). To keep \(k.title.lowercased()) on this day, mark it as fixed in your availability."
            }
        }
        // G-18: one long ride a week — an untyped ride only becomes "long" when the rider has not typed one
        let typedLong = cyc.contains { $0.a.cyclingType == .long }
        if let longest = untyped.max(by: { ($0.a.minutes, adjacentToLegs($0.day) ? 0 : 1) < ($1.a.minutes, adjacentToLegs($1.day) ? 0 : 1) }) {
            cycTypes[longest.a.id] = longest.a.minutes >= 90 && !typedLong ? .long : .endurance
            let alreadyHard = cyc.contains { $0.a.cyclingType?.isHard ?? false }
            if !alreadyHard, cyc.count >= 2, !easyWeek {
                // not the day before the long ride, and (F-16) not the day after it unless the rider is advanced
                let eligible = untyped.filter { $0.a.id != longest.a.id && $0.a.minutes >= 45 && ($0.day + 1) % 7 != longest.day && (p.level == .advanced || ($0.day + 6) % 7 != longest.day) }
                let preferred = eligible.filter { !legClash($0.day) }
                // G-10: when every candidate sits next to a leg day, cycling- and balanced-priority riders still get the
                // least-conflicting one (the strength planner lightens that leg session); strength priority keeps legs first
                let fallback = eligible.filter { !(split != nil && legDays.contains($0.day)) }
                let pool = !preferred.isEmpty ? preferred : (p.priority == .strength ? [] : fallback)
                if let q = pool.max(by: { $0.a.minutes < $1.a.minutes }) {
                    cycTypes[q.a.id] = hard
                    if let next = untyped.first(where: { $0.day == (q.day + 1) % 7 }), cycTypes[next.a.id] == nil { cycTypes[next.a.id] = .recovery }
                    if p.level == .advanced, performanceGoal, cyc.count >= 4, !p.recovery.reduced {
                        let busy = Set([q.day, longest.day])
                        let second = eligible.filter { c in c.a.id != q.a.id && cycTypes[c.a.id] == nil && c.a.minutes >= 45 && !busy.contains(where: { b in let g = abs(b - c.day); return min(g, 7 - g) < 2 }) && !legClash(c.day) }
                        if let v = second.max(by: { $0.a.minutes < $1.a.minutes }) { cycTypes[v.a.id] = .vo2 }
                    }
                }
            }
        }
        // one primary entry per day first (rest days included), then the extra sessions of multi-activity days
        var primary: [Workout] = [], extras: [Workout] = []
        for i in 0..<7 {
            let day = a.days[i]
            if day.isRest { primary.append(Workout(date: d(i), kind: .rest, minutes: 0)); continue }
            var items: [Workout] = []
            if day.otherMinutes > 0 { items.append(Workout(date: d(i), kind: .other, minutes: max(15, day.otherMinutes))) }
            let ordered = day.assignments.sorted { x, y in
                let xs = x.sport == .cycling ? 0 : 1, ys = y.sport == .cycling ? 0 : 1
                return p.priority == .strength ? xs > ys : xs < ys
            }
            for (n, x) in ordered.enumerated() {
                let date = d(i).addingTimeInterval(TimeInterval(n))
                if x.sport == .cycling {
                    var k = cycTypes[x.id] ?? (x.minutes < 40 ? .recovery : .endurance)
                    var minutes = max(20, x.minutes)
                    var safetyCap: SafetyOriginal? = nil          // F-08: generation-time caps are reversible too
                    var note = goalNote[x.id] ?? (x.cyclingType == .custom ? "custom ride" : "")
                    if !x.fixed, easyWeek, k.zone >= 3 { k = .endurance; note = "Easier week (week \(every) of your \(every)-week block): no interval session." }
                    if !x.fixed, easyWeek, k == .long { minutes = max(60, Int((Double(minutes) * 0.8 / 5).rounded()) * 5); note = "Easier week (week \(every) of your \(every)-week block): the long ride is 20 % shorter and there is no interval session." }
                    if x.fixed {
                        if k.zone > readiness.maxRideZone, let r = readiness.restriction { note = "Caution: \(r). This fixed ride is kept as you set it — ride it easy until then." }
                    } else {
                        if k.zone > readiness.maxRideZone { k = .endurance; note = "Planned easy because \(readiness.restriction ?? "of your health check")." }
                        if let cap = readiness.maxRideMinutes, minutes > cap { minutes = cap; note = "Kept to \(Fmt.duration(minutes: cap)) because \(readiness.restriction ?? "of your health check")." }
                        if let r = returning, r.active, k.zone >= 3 || k == .long || minutes > 60 {
                            let base = minutes
                            if k.zone >= 3 || k == .long { k = .endurance }
                            minutes = max(30, Int((Double(base) * r.rideFactor / 5).rounded()) * 5)
                            note = "Back after \(r.weeksText) off: steady riding at about \(Int((r.rideFactor * 100).rounded())) % of the usual time, building back over \(ReturnPhase.phaseSessions) rides."
                            safetyCap = SafetyOriginal(kind: cycTypes[x.id] ?? (base < 40 ? .recovery : .endurance), minutes: base, intervalReps: nil, note: "")
                        }
                    }
                    var w = Workout(date: date, kind: k, minutes: minutes, sequence: n)
                    w.fixed = x.fixed; w.assignmentId = x.id
                    if var c = safetyCap, c.kind != k || c.minutes != minutes {
                        if c.kind == .threshold, let t = thresholdReps, let r = stride(from: t, through: 3, by: -1).first(where: { AdaptiveRules.intervalsFit(kind: .threshold, reps: $0, minutes: c.minutes) }), r != 3 { c.intervalReps = r }
                        w.safetyOriginal = c
                    }
                    if !x.fixed, k == .threshold, let target = thresholdReps, let r = stride(from: target, through: k.defaultIntervalReps ?? 3, by: -1).first(where: { AdaptiveRules.intervalsFit(kind: k, reps: $0, minutes: minutes) }), r != (k.defaultIntervalReps ?? r) {
                        w.intervalReps = r; note = "Week \((blockPos ?? 0) + 1) of your \(every)-week block: \(r) × \(k.intervalWorkMinutes) min."
                    }
                    w.note = note
                    items.append(w)
                } else {
                    var w = Workout(date: date, kind: .strength, minutes: max(15, x.minutes), strengthFocus: focus[x.id] ?? .fullBody, sequence: n)
                    w.fixed = x.fixed; w.assignmentId = x.id
                    if let slot = slotFor[x.id] {
                        if slot.focus == .custom, !slot.label.isEmpty { w.note = slot.label }
                        if let t = slot.templateId { w.templateId = t }
                    }
                    items.append(w)
                }
            }
            primary.append(items[0]); extras.append(contentsOf: items.dropFirst())
        }
        var out = primary + extras
        // M-01 / F-01: symptoms or "supervised only" → no sessions are planned (rest days with the reason); the rider's
        // availability (fixed days included) is kept and comes back as soon as the check allows training
        if !readiness.trainingAllowed {
            out = out.map { w in
                guard w.kind != .rest else { return w }
                var r = w
                r.kind = .rest; r.minutes = 0; r.intervalReps = nil
                r.note = "No training planned: \(readiness.restriction ?? "see a doctor first")."
                r.safetyOriginal = SafetyOriginal(kind: w.kind, minutes: w.minutes, intervalReps: w.intervalReps, note: w.note)
                return r
            }
        }
        return out
    }
    static func rideMinutes(_ w: [Workout]) -> Int { w.filter { $0.kind.isRide && !$0.skipped }.reduce(0) { $0 + $1.minutes } }
    static func liftMinutes(_ w: [Workout]) -> Int { w.filter { $0.kind == .strength && !$0.skipped }.reduce(0) { $0 + $1.minutes } }
    static func totalMinutes(_ w: [Workout]) -> Int { w.filter { !$0.skipped }.reduce(0) { $0 + $1.minutes } }

    /// When the planned riding time is over the rider's weekly hours (only possible after manual edits): concrete
    /// adjustments, never a silent cut.
    static func suggestions(for week: [Workout], hoursPerWeek h: Int) -> [String] {
        let planned = rideMinutes(week), limit = h * 60
        guard planned > limit else { return [] }
        let over = planned - limit
        var out = ["Planned riding is \(Fmt.duration(minutes: planned)) against your \(h) h limit — \(Fmt.duration(minutes: over)) over."]
        let rides = week.filter { $0.kind.isRide && !$0.skipped }.sorted { $0.minutes > $1.minutes }
        if let l = rides.first { out.append("Shorten \(l.date.shortDay)'s \(l.kind.title.lowercased()) from \(Fmt.duration(minutes: l.minutes)) to \(Fmt.duration(minutes: max(30, l.minutes - over))).") }
        if rides.count >= 3, let e = rides.last(where: { $0.kind == .endurance || $0.kind == .recovery }) { out.append("Or skip \(e.date.shortDay)'s \(e.kind.title.lowercased()) (\(Fmt.duration(minutes: e.minutes))).") }
        out.append("Or raise the weekly limit in Profile › Training profile if \(Fmt.duration(minutes: planned)) is realistic for you.")
        return out
    }
    /// Lifting budget, kept apart from riding. Empty when no lifting budget is set.
    static func liftSuggestions(for week: [Workout], liftingHours h: Int) -> [String] {
        guard h > 0 else { return [] }
        let planned = liftMinutes(week), limit = h * 60
        guard planned > limit else { return [] }
        let over = planned - limit
        var out = ["Planned lifting is \(Fmt.duration(minutes: planned)) against your \(h) h lifting budget — \(Fmt.duration(minutes: over)) over."]
        let lifts = week.filter { $0.kind == .strength && !$0.skipped }.sorted { $0.minutes > $1.minutes }
        if let l = lifts.first { out.append("Shorten \(l.date.shortDay)'s \(l.displayTitle.lowercased()) from \(Fmt.duration(minutes: l.minutes)) to \(Fmt.duration(minutes: max(20, l.minutes - over))).") }
        if lifts.count >= 2, let e = lifts.last { out.append("Or drop \(e.date.shortDay)'s \(e.displayTitle.lowercased()).") }
        return out
    }
    /// Meaningful differences between two weeks (for "what changed" when the mode or schedule changes).
    static func changes(from old: [Workout], to new: [Workout], calendar cal: Calendar = .current) -> [String] {
        var out: [String] = []
        let or = rideMinutes(old), nr = rideMinutes(new), ol = liftMinutes(old), nl = liftMinutes(new)
        if or != nr { out.append("Riding \(Fmt.duration(minutes: or)) → \(Fmt.duration(minutes: nr))") }
        if ol != nl { out.append("Lifting \(Fmt.duration(minutes: ol)) → \(Fmt.duration(minutes: nl))") }
        let oc = old.filter { $0.kind.isRide && !$0.skipped }.count, nc = new.filter { $0.kind.isRide && !$0.skipped }.count
        if oc != nc { out.append("\(oc) → \(nc) rides") }
        let os = old.filter { $0.kind == .strength && !$0.skipped }.count, ns = new.filter { $0.kind == .strength && !$0.skipped }.count
        if os != ns { out.append("\(os) → \(ns) lifts") }
        for i in 0..<7 {
            let od = old.filter { cal.component(.weekday, from: $0.date) == (i + 1) % 7 + 1 && $0.kind != .rest }.map { $0.displayTitle }.sorted()
            let nd = new.filter { cal.component(.weekday, from: $0.date) == (i + 1) % 7 + 1 && $0.kind != .rest }.map { $0.displayTitle }.sorted()
            if od != nd, out.count < 6 { out.append("\(WeeklyAvailability.dayNames[i]): \(od.isEmpty ? "rest" : od.joined(separator: " + ")) → \(nd.isEmpty ? "rest" : nd.joined(separator: " + "))") }
        }
        return out
    }
}

// MARK: - Historical timeline (rides + strength + past workouts, deduplicated, stable source ids)
struct TimelineEntry: Identifiable, Equatable {
    enum Status: String { case completed, planned, skipped, missed, imported, review = "needs review" }
    var id: String
    var date: Date
    var title: String
    var minutes: Int
    var distanceM: Int?
    var avgHR: Int?, maxHR: Int?
    var avgPower: Int?, normalizedPower: Int?
    var cadence: Int?
    var zoneSeconds: [Int]
    var tss: Int?
    var status: Status
    var rideId: UUID?
    var workoutId: UUID?
    var recorder: String?
    var strengthId: UUID? = nil
    var detail: String? = nil
    var isStrength: Bool { strengthId != nil || (rideId == nil && title.hasPrefix("Strength")) }
}

enum Timeline {
    /// Training Stress Score from normalized power and FTP only; nil when either is missing (never estimated).
    static func tss(normalizedPower np: Int?, durationS s: Int, ftp: Int) -> Int? {
        guard let np, np > 0, ftp > 0, s > 0 else { return nil }
        let v = Double(s) * Double(np) * Double(np) / (Double(ftp) * Double(ftp) * 3600) * 100
        return Int(v.rounded())
    }
    /// Same ride recorded twice (board sync + phone mirror, or two imports): same stable source id, or starts within
    /// 5 minutes of each other with the same recorder. The record with more data wins.
    static func dedupe(_ rides: [RideRecord]) -> [RideRecord] {
        var out: [RideRecord] = []
        for r in rides.sorted(by: { ($0.samples.count, $0.avgPower != nil ? 1 : 0) > ($1.samples.count, $1.avgPower != nil ? 1 : 0) }) {
            let dup = out.contains { o in
                if let a = o.boardRideId, let b = r.boardRideId, a == b, (o.boardId == nil || r.boardId == nil || o.boardId == r.boardId) { return true }
                if let a = o.healthUUID, let b = r.healthUUID, a == b { return true }
                return abs(o.start.timeIntervalSince(r.start)) < 300 && o.recorder == r.recorder && abs(o.durationS - r.durationS) < 120
            }
            if !dup { out.append(r) }
        }
        return out.sorted { $0.start > $1.start }
    }
    static func build(rides: [RideRecord], plan: [Workout], ftp: Int, strength: [StrengthSession] = [], now: Date = Date(), calendar cal: Calendar = .current) -> [TimelineEntry] {
        let today = cal.startOfDay(for: now)
        var out: [TimelineEntry] = []
        let rs = dedupe(rides)
        for r in rs {
            let imported = r.recorder == .health
            out.append(TimelineEntry(id: "ride-\(r.sourceId)", date: r.start, title: r.recorder == .board ? "Ride" : imported ? "Ride (Apple Health)" : "Ride (phone)", minutes: r.durationS / 60, distanceM: r.distanceM,
                                     avgHR: r.avgHR, maxHR: r.maxHR, avgPower: r.avgPower, normalizedPower: r.normalizedPower, cadence: r.avgCadence, zoneSeconds: r.zoneSeconds,
                                     tss: tss(normalizedPower: r.normalizedPower, durationS: r.durationS, ftp: ftp), status: imported ? .imported : .completed, rideId: r.id, workoutId: nil, recorder: r.recordedBy))
        }
        // quality release: states come from the one query layer (TrainingLedger) — same as Home, Plan and Progress
        let ledger = TrainingLedger(plan: plan, strength: strength, rides: rides, calendar: cal)
        for s in strength {
            var detail = s.isDetailed ? "\(s.exerciseCount) exercise\(s.exerciseCount == 1 ? "" : "s") · \(s.setCount) sets" : nil
            if s.awaitingReview { detail = (detail.map { $0 + " · " } ?? "") + "not counted until you confirm it" }
            let status: TimelineEntry.Status = s.awaitingReview ? .review : s.isImported ? .imported : .completed
            out.append(TimelineEntry(id: "str-\(s.sourceId)", date: s.date, title: s.title, minutes: s.minutes, distanceM: nil, avgHR: nil, maxHR: nil, avgPower: nil, normalizedPower: nil, cadence: nil, zoneSeconds: [], tss: nil, status: status, rideId: nil, workoutId: s.workoutId, recorder: s.source == "manual" ? (s.isDetailed ? "detailed log" : "quick log") + (s.rpe.map { " · RPE \($0)" } ?? "") : s.source, strengthId: s.id, detail: detail))
        }
        for w in plan where w.kind != .rest {
            let past = cal.startOfDay(for: w.date) < today
            if w.kind.isRide, rs.contains(where: { cal.isDate($0.start, inSameDayAs: w.date) }) { continue }
            if w.kind == .strength, ledger.log(for: w) != nil { continue }
            let st = ledger.status(w)
            if st == .completedManual {
                out.append(TimelineEntry(id: "wo-\(w.id.uuidString)", date: w.date, title: w.displayTitle, minutes: w.manualMinutes ?? 0, distanceM: nil, avgHR: nil, maxHR: nil, avgPower: nil, normalizedPower: nil, cadence: nil, zoneSeconds: [], tss: nil, status: .completed, rideId: nil, workoutId: w.id, recorder: "marked done (no details)"))
                continue
            }
            guard past else { continue }     // future sessions live in the plan, not the timeline
            let status: TimelineEntry.Status = st == .skipped ? .skipped : .missed
            out.append(TimelineEntry(id: "wo-\(w.id.uuidString)", date: w.date, title: w.displayTitle, minutes: w.minutes, distanceM: nil, avgHR: nil, maxHR: nil, avgPower: nil, normalizedPower: nil, cadence: nil, zoneSeconds: [], tss: nil, status: status, rideId: nil, workoutId: w.id, recorder: nil))
        }
        return out.sorted { $0.date > $1.date }
    }
    /// Values of one metric, oldest first, for a sparkline; nil when fewer than 5 points exist.
    static func trend(_ entries: [TimelineEntry], _ pick: (TimelineEntry) -> Int?) -> [Int]? {
        let v = entries.sorted { $0.date < $1.date }.compactMap(pick)
        return v.count >= 5 ? Array(v.suffix(20)) : nil
    }
}
