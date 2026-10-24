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
        case cycle, lift, other, rest
        var title: String { switch self { case .cycle: return "Cycle"; case .lift: return "Lift"; case .other: return "Other"; case .rest: return "Rest" } }
        var icon: String { switch self { case .cycle: return "bicycle"; case .lift: return "dumbbell"; case .other: return "figure.run"; case .rest: return "moon.zzz" } }
    }
    var activity: Activity
    var minutes: Int
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
    var cycleMinutes: Int { days.filter { $0.activity == .cycle }.reduce(0) { $0 + $1.minutes } }
    var cycleDays: Int { days.filter { $0.activity == .cycle }.count }
    var totalMinutes: Int { days.filter { $0.activity != .rest }.reduce(0) { $0 + $1.minutes } }
}

// MARK: - Plan engine (deterministic, built around the availability)
enum PlanEngine {
    /// The week for `monday`: rest days stay empty, lift days get strength, other days get "other", cycling days get a
    /// ride mix (long on the longest day, one quality session, recovery after it, endurance elsewhere), each at the
    /// rider's preferred duration. Never exceeds a day's minutes; the weekly total is reported, not silently cut.
    static func week(starting monday: Date, profile p: RiderProfile, availability a: WeeklyAvailability, calendar cal: Calendar = .current) -> [Workout] {
        let d = { (i: Int) in cal.date(byAdding: .day, value: i, to: monday)! }
        let cyc = a.days.enumerated().filter { $0.element.activity == .cycle }
        var kinds = [Int: WorkoutKind]()
        if let longest = cyc.max(by: { $0.element.minutes < $1.element.minutes }) { kinds[longest.offset] = longest.element.minutes >= 90 ? .long : .endurance }
        let hard: WorkoutKind = p.level == .beginner ? .tempo : (p.goal == .stronger || p.goal == .climbing ? .threshold : .tempo)
        if cyc.count >= 2 {
            // quality session: the second-longest day that is not right before the long day, needs ≥ 45 min
            let longIdx = kinds.keys.first
            let candidates = cyc.filter { $0.offset != longIdx && $0.element.minutes >= 45 && (longIdx == nil || ($0.offset + 1) % 7 != longIdx!) }
            if let q = candidates.max(by: { $0.element.minutes < $1.element.minutes }) {
                kinds[q.offset] = hard
                // the cycling day right after the quality session is a recovery spin
                if let next = cyc.first(where: { $0.offset == (q.offset + 1) % 7 }), kinds[next.offset] == nil { kinds[next.offset] = .recovery }
            }
        }
        return (0..<7).map { i in
            let day = a.days[i]
            switch day.activity {
            case .rest: return Workout(date: d(i), kind: .rest, minutes: 0)
            case .lift: return Workout(date: d(i), kind: .strength, minutes: max(15, day.minutes))
            case .other: return Workout(date: d(i), kind: .other, minutes: max(15, day.minutes))
            case .cycle:
                let k = kinds[i] ?? (day.minutes < 40 ? .recovery : .endurance)
                return Workout(date: d(i), kind: k, minutes: max(20, day.minutes))
            }
        }
    }
    static func rideMinutes(_ w: [Workout]) -> Int { w.filter { $0.kind.isRide && !$0.skipped }.reduce(0) { $0 + $1.minutes } }
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
    static func build(rides: [RideRecord], plan: [Workout], ftp: Int, now: Date = Date(), calendar cal: Calendar = .current) -> [TimelineEntry] {
        let today = cal.startOfDay(for: now)
        var out: [TimelineEntry] = []
        let rs = dedupe(rides)
        for r in rs {
            out.append(TimelineEntry(id: "ride-\(r.id.uuidString)", date: r.start, title: r.recorder == .board ? "Ride" : "Ride (phone)", minutes: r.durationS / 60, distanceM: r.distanceM,
                                     avgHR: r.avgHR, maxHR: r.maxHR, avgPower: r.avgPower, normalizedPower: r.normalizedPower, cadence: r.avgCadence, zoneSeconds: r.zoneSeconds,
                                     tss: tss(normalizedPower: r.normalizedPower, durationS: r.durationS, ftp: ftp), status: .completed, rideId: r.id, workoutId: nil, recorder: r.recordedBy))
        }
        // past workouts that are not rides matched by a recorded ride on that day
        for w in plan where cal.startOfDay(for: w.date) < today && w.kind != .rest {
            let hasRide = rs.contains { cal.isDate($0.start, inSameDayAs: w.date) }
            if w.kind.isRide, hasRide { continue }                 // the ride entry already represents it
            let status: TimelineEntry.Status = w.done ? .completed : w.skipped ? .skipped : .missed
            out.append(TimelineEntry(id: "wo-\(w.id.uuidString)", date: w.date, title: w.kind.title, minutes: w.minutes, distanceM: nil, avgHR: nil, maxHR: nil, avgPower: nil, normalizedPower: nil, cadence: nil, zoneSeconds: [], tss: nil, status: status, rideId: nil, workoutId: w.id, recorder: nil))
        }
        return out.sorted { $0.date > $1.date }
    }
    /// Values of one metric, oldest first, for a sparkline; nil when fewer than 5 points exist.
    static func trend(_ entries: [TimelineEntry], _ pick: (TimelineEntry) -> Int?) -> [Int]? {
        let v = entries.sorted { $0.date < $1.date }.compactMap(pick)
        return v.count >= 5 ? Array(v.suffix(20)) : nil
    }
}
