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

// MARK: - Weekly availability: the rider chooses the days, the engine plans around them
struct DayAvailability: Codable, Equatable {
    enum Activity: String, Codable, CaseIterable {
        case cycle, lift, both, other, rest
        var title: String { switch self { case .cycle: return "Cycle"; case .lift: return "Lift"; case .both: return "Ride + lift"; case .other: return "Other"; case .rest: return "Rest" } }
        var short: String { switch self { case .cycle: return "Cycle"; case .lift: return "Lift"; case .both: return "Both"; case .other: return "Other"; case .rest: return "Rest" } }
        var icon: String { switch self { case .cycle: return "bicycle"; case .lift: return "dumbbell"; case .both: return "plus.circle"; case .other: return "figure.run"; case .rest: return "moon.zzz" } }
        var cycles: Bool { self == .cycle || self == .both }
        var lifts: Bool { self == .lift || self == .both }
    }
    var activity: Activity
    /// Minutes for the day's main activity (riding minutes on a "Ride + lift" day).
    var minutes: Int
    /// 0.6.0: lifting minutes on a "Ride + lift" day (nil for every other day; older files never carry it).
    var liftMinutes: Int? = nil

    init(activity: Activity, minutes: Int, liftMinutes: Int? = nil) { self.activity = activity; self.minutes = minutes; self.liftMinutes = liftMinutes }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activity = (try? c.decodeIfPresent(Activity.self, forKey: .activity)) ?? .rest
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
        liftMinutes = try c.decodeIfPresent(Int.self, forKey: .liftMinutes)
    }
    var cycleMinutes: Int { activity.cycles ? minutes : 0 }
    var liftingMinutes: Int { activity == .lift ? minutes : activity == .both ? (liftMinutes ?? 30) : 0 }
}

struct WeeklyAvailability: Codable, Equatable {
    /// Seven entries, Monday first.
    var days: [DayAvailability]
    static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let longDayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

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
    /// 0.6.0: a schedule from the rider's mode, frequencies, priority, budgets and preferred days. Cycling mode keeps the
    /// 0.5.0 suggestion. Lifts go on non-adjacent days where possible; the longest ride lands on Saturday (or the first
    /// preferred weekend day); a "Ride + lift" day is used only when the rider wants more sessions than days.
    static func suggested(for p: RiderProfile) -> WeeklyAvailability {
        guard p.trainingMode != .cycling else { return suggested(hoursPerWeek: p.hoursPerWeek) }
        var d = Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7)
        let preferred = p.preferredDays.isEmpty ? [1, 3, 5, 6, 2, 4, 0] : p.preferredDays + [1, 3, 5, 6, 2, 4, 0].filter { !p.preferredDays.contains($0) }
        let rides = p.trainingMode.includesCycling ? max(0, min(6, p.cyclingDaysPerWeek)) : 0
        let lifts = max(0, min(6, p.liftDaysPerWeek))
        let rideMin = rides > 0 ? max(30, (p.hoursPerWeek * 60) / rides) : 0
        let liftMin = lifts > 0 ? max(20, (max(1, p.liftingHoursPerWeek) * 60) / lifts) : 0
        var order = preferred
        // the long ride takes the first weekend day in the preference list
        if rides > 0, let wk = order.first(where: { $0 >= 5 }) { d[wk] = DayAvailability(activity: .cycle, minutes: min(240, rideMin + rideMin / 2)); order.removeAll { $0 == wk } }
        var ridesLeft = rides - d.filter { $0.activity.cycles }.count
        var liftsLeft = lifts
        // alternate by priority so neither sport takes every good day
        var takeRide = p.priority != .strength
        for day in order where ridesLeft > 0 || liftsLeft > 0 {
            if (takeRide && ridesLeft > 0) || liftsLeft == 0 { d[day] = DayAvailability(activity: .cycle, minutes: rideMin); ridesLeft -= 1 }
            else { d[day] = DayAvailability(activity: .lift, minutes: liftMin); liftsLeft -= 1 }
            if ridesLeft > 0, liftsLeft > 0 { takeRide.toggle() }
        }
        // more sessions than days: pair the remaining lifts with rides (ride first unless strength is the priority)
        var i = 0
        while liftsLeft > 0, i < 7 { if d[i].activity == .cycle { d[i] = DayAvailability(activity: .both, minutes: d[i].minutes, liftMinutes: liftMin); liftsLeft -= 1 }; i += 1 }
        return WeeklyAvailability(days: d)
    }
    var cycleMinutes: Int { days.reduce(0) { $0 + $1.cycleMinutes } }
    var cycleDays: Int { days.filter { $0.activity.cycles }.count }
    var liftMinutes: Int { days.reduce(0) { $0 + $1.liftingMinutes } }
    var liftDays: Int { days.filter { $0.activity.lifts }.count }
    var totalMinutes: Int { days.reduce(0) { $0 + ($1.activity == .rest ? 0 : $1.cycleMinutes + $1.liftingMinutes + ($1.activity == .other ? $1.minutes : 0)) } }
}

// MARK: - Plan engine (deterministic, built around the availability)
enum PlanEngine {
    /// The week for `monday`. Entries 0…6 are one session per day (rest days stay rest, lift days get strength, other
    /// days get "other", cycling days get a ride mix: long on the longest day, one quality session, recovery after it,
    /// endurance elsewhere), each at the rider's preferred duration. A "Ride + lift" day adds its strength session
    /// AFTER the first seven entries (ordered by priority within the day via `sequence`). Rules stated in "Why?":
    /// a hard ride (Zone 3+) and a leg-loading lift are not on consecutive days when the availability leaves a choice
    /// (a long Zone 2 ride does not count as hard for this rule).
    /// Never exceeds a day's minutes; weekly totals are reported, not silently cut.
    static func week(starting monday: Date, profile p: RiderProfile, availability a: WeeklyAvailability, calendar cal: Calendar = .current) -> [Workout] {
        let d = { (i: Int) in cal.date(byAdding: .day, value: i, to: monday)! }
        let cyc = a.days.enumerated().filter { $0.element.activity.cycles }
        let liftIdx = a.days.enumerated().filter { $0.element.activity.lifts }.map { $0.offset }
        // strength focus per lift day: 1 → full body; 2 → lower + upper; 3 → lower, push, pull; 4+ → lower, push, pull, upper, full…
        let focusCycle: [StrengthFocus] = liftIdx.count <= 1 ? [.fullBody] : liftIdx.count == 2 ? [.lower, .upper] : [.lower, .push, .pull, .upper, .fullBody, .lower]
        // the leg-loading session goes to the lift day with the fewest cycling days next to it (hard rides live there)
        func adjCycles(_ i: Int) -> Int { (a.days[(i + 1) % 7].activity.cycles ? 1 : 0) + (a.days[(i + 6) % 7].activity.cycles ? 1 : 0) + (a.days[i].activity == .both ? 2 : 0) }
        let liftOrder = liftIdx.enumerated().sorted { (adjCycles($0.element), $0.offset) < (adjCycles($1.element), $1.offset) }.map { $0.element }
        var focus = [Int: StrengthFocus]()
        for (n, i) in liftOrder.enumerated() { focus[i] = focusCycle[n % focusCycle.count] }
        // on a Ride + lift day the lift is upper-body so the legs are not loaded twice
        for i in liftIdx where a.days[i].activity == .both { focus[i] = liftIdx.count == 1 ? .upper : (focus[i]?.loadsLegs == true ? .upper : focus[i]) }
        let legDays = Set(liftIdx.filter { focus[$0]?.loadsLegs == true })
        func adjacentToLegs(_ i: Int) -> Bool { legDays.contains((i + 1) % 7) || legDays.contains((i + 6) % 7) }

        var kinds = [Int: WorkoutKind]()
        func longScore(_ e: (offset: Int, element: DayAvailability)) -> (Int, Int) { (e.element.minutes, adjacentToLegs(e.offset) ? 0 : 1) }
        if let longest = cyc.max(by: { longScore($0) < longScore($1) }) { kinds[longest.offset] = longest.element.minutes >= 90 ? .long : .endurance }
        let hard: WorkoutKind = p.level == .beginner ? .tempo : (p.goal == .stronger || p.goal == .climbing ? .threshold : .tempo)
        if cyc.count >= 2 {
            // quality session: the second-longest day that is not right before the long day, needs ≥ 45 min; prefer a day
            // that is not next to a leg-loading lift (hybrid rule), fall back to any eligible day
            let longIdx = kinds.keys.first
            let eligible = cyc.filter { $0.offset != longIdx && $0.element.minutes >= 45 && (longIdx == nil || ($0.offset + 1) % 7 != longIdx!) }
            let preferred = eligible.filter { !adjacentToLegs($0.offset) }
            if let q = (preferred.isEmpty ? eligible : preferred).max(by: { $0.element.minutes < $1.element.minutes }) {
                kinds[q.offset] = hard
                if let next = cyc.first(where: { $0.offset == (q.offset + 1) % 7 }), kinds[next.offset] == nil { kinds[next.offset] = .recovery }
            }
        }
        var out: [Workout] = (0..<7).map { i in
            let day = a.days[i]
            switch day.activity {
            case .rest: return Workout(date: d(i), kind: .rest, minutes: 0)
            case .lift: return Workout(date: d(i), kind: .strength, minutes: max(15, day.minutes), strengthFocus: focus[i])
            case .other: return Workout(date: d(i), kind: .other, minutes: max(15, day.minutes))
            case .cycle, .both:
                let k = kinds[i] ?? (day.minutes < 40 ? .recovery : .endurance)
                return Workout(date: d(i), kind: k, minutes: max(20, day.minutes), sequence: (day.activity == .both && p.priority == .strength) ? 1 : 0)
            }
        }
        for i in 0..<7 where a.days[i].activity == .both {
            out.append(Workout(date: d(i).addingTimeInterval(1), kind: .strength, minutes: max(15, a.days[i].liftingMinutes), strengthFocus: focus[i], sequence: p.priority == .strength ? 0 : 1))
        }
        return out
    }
    static func rideMinutes(_ w: [Workout]) -> Int { w.filter { $0.kind.isRide && !$0.skipped }.reduce(0) { $0 + $1.minutes } }
    static func liftMinutes(_ w: [Workout]) -> Int { w.filter { $0.kind == .strength && !$0.skipped }.reduce(0) { $0 + $1.minutes } }
    static func totalMinutes(_ w: [Workout]) -> Int { w.filter { !$0.skipped }.reduce(0) { $0 + $1.minutes } }

    /// When the planned riding time is over the rider's weekly hours: concrete adjustments, never a silent cut.
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
    /// Lifting budget, kept apart from riding (0.6.0). Empty when no lifting budget is set.
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
}

// MARK: - Historical timeline (rides + past workouts, deduplicated)
struct TimelineEntry: Identifiable, Equatable {
    enum Status: String { case completed, planned, skipped, missed }
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
}

enum Timeline {
    /// Training Stress Score from normalized power and FTP only; nil when either is missing (never estimated).
    static func tss(normalizedPower np: Int?, durationS s: Int, ftp: Int) -> Int? {
        guard let np, np > 0, ftp > 0, s > 0 else { return nil }
        let v = Double(s) * Double(np) * Double(np) / (Double(ftp) * Double(ftp) * 3600) * 100
        return Int(v.rounded())
    }
    /// Same ride recorded twice (board sync + phone mirror, or two imports): same board ride id, or starts within
    /// 5 minutes of each other with the same recorder. The record with more data wins.
    static func dedupe(_ rides: [RideRecord]) -> [RideRecord] {
        var out: [RideRecord] = []
        for r in rides.sorted(by: { ($0.samples.count, $0.avgPower != nil ? 1 : 0) > ($1.samples.count, $1.avgPower != nil ? 1 : 0) }) {
            let dup = out.contains { o in
                if let a = o.boardRideId, let b = r.boardRideId, a == b, (o.boardId == nil || r.boardId == nil || o.boardId == r.boardId) { return true }
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
            out.append(TimelineEntry(id: "ride-\(r.id.uuidString)", date: r.start, title: r.recorder == .board ? "Ride" : r.recorder == .health ? "Ride (Apple Health)" : "Ride (phone)", minutes: r.durationS / 60, distanceM: r.distanceM,
                                     avgHR: r.avgHR, maxHR: r.maxHR, avgPower: r.avgPower, normalizedPower: r.normalizedPower, cadence: r.avgCadence, zoneSeconds: r.zoneSeconds,
                                     tss: tss(normalizedPower: r.normalizedPower, durationS: r.durationS, ftp: ftp), status: .completed, rideId: r.id, workoutId: nil, recorder: r.recordedBy))
        }
        // strength sessions (quick logs + Health imports), already deduplicated by the store
        for s in strength {
            out.append(TimelineEntry(id: "str-\(s.id.uuidString)", date: s.date, title: s.title, minutes: s.minutes, distanceM: nil, avgHR: nil, maxHR: nil, avgPower: nil, normalizedPower: nil, cadence: nil, zoneSeconds: [], tss: nil, status: .completed, rideId: nil, workoutId: nil, recorder: s.source == "manual" ? "quick log" + (s.rpe.map { " · RPE \($0)" } ?? "") : s.source, strengthId: s.id))
        }
        // past workouts that are not represented by a recorded ride / logged session on that day
        for w in plan where cal.startOfDay(for: w.date) < today && w.kind != .rest {
            let hasRide = rs.contains { cal.isDate($0.start, inSameDayAs: w.date) }
            if w.kind.isRide, hasRide { continue }                 // the ride entry already represents it
            if w.kind == .strength, strength.contains(where: { cal.isDate($0.date, inSameDayAs: w.date) }) { continue }
            let status: TimelineEntry.Status = w.done ? .completed : w.skipped ? .skipped : .missed
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
