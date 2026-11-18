import Foundation

// Progress v2.3 — the sections under the compact hero ("Your development"): Endurance development · Strength
// development · Training consistency · Time in zones. Pure values built from the athlete's own records; the screen
// only draws them. (Design: PROGRESS v2.3 full-length sheet PH4. The sheet's figures are illustrative samples.)
//
// HONESTY RULES
// • Every number is counted or measured from recorded rides and logged sessions. A week without a ride is a gap.
// • The direction words compare two measured averages and say so ("higher than the 4 weeks before"); nothing here is
//   called "improving", and nothing is said with fewer than two weeks on each side.
// • No stage, "next evolution" or evolution timeline: the criteria are not approved, so those parts of the sheet are
//   not built here (the hero says so).

struct ProgressDevelopment: Equatable {
    enum Direction: Equatable { case higher, lower, same
        var symbol: String { switch self { case .higher: return "arrow.up.right"; case .lower: return "arrow.down.right"; case .same: return "arrow.right" } }
        func text(_ what: String) -> String {
            switch self {
            case .higher: return "Higher than the \(what) before"
            case .lower: return "Lower than the \(what) before"
            case .same: return "About the same as the \(what) before"
            }
        }
    }

    struct Endurance: Equatable {
        /// Average riding minutes per week over the last full weeks (up to 4).
        var averageMinutes: Int
        var fullWeeks: Int
        var direction: Direction?
        /// Riding minutes per week, oldest first; the last value is the current, unfinished week.
        var weeks: [Int]
        var firstLabel: String
        var lastLabel: String
        /// Best 20-minute power, only when power was measured ("221 W · 208 W in the 6 weeks before").
        var powerLine: String?
    }
    struct Strength: Equatable {
        struct Range: Equatable { var title: String; var note: String; var from: Double; var to: Double; var fromText: String; var toText: String }
        var liftName: String
        var sessions: Int
        /// The latest recorded top set, in kilograms and as logged ("100 kg × 3").
        var latestKg: Double
        var latestText: String
        var direction: Direction?
        var ranges: [Range]
    }
    struct Consistency: Equatable {
        struct Week: Equatable { var rides: Int; var lifts: Int }
        var active: Int
        var total: Int
        var weeks: [Week]
        var firstLabel: String
        var lastLabel: String
    }
    struct Zones: Equatable {
        /// Per cent of measured time in the two easiest zones.
        var easyPercent: Int
        var basis: String
        var hours: String
        var shares: [Int]
    }

    var endurance: Endurance?
    var strength: Strength?
    var consistency: Consistency?
    var zones: Zones?
    /// Why Time in zones is absent, when it is ("not measurable: no FTP and no HR zones").
    var zonesMissing: String?

    // MARK: building

    static func direction(recent: Double, before: Double) -> Direction? {
        guard before > 0 else { return nil }
        let change = (recent - before) / before
        return change >= 0.05 ? .higher : (change <= -0.05 ? .lower : .same)
    }
    private static func label(_ d: Date, _ cal: Calendar) -> String {
        let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = "d MMM"; return f.string(from: d)
    }

    /// `riding` and `lifting` are weekly buckets, oldest first, ending with the current week.
    static func endurance(_ riding: [WeekBucket], best20: (recent: Int?, before: Int?), show: Bool, weeks n: Int = 12, calendar cal: Calendar = .current) -> Endurance? {
        let w = Array(riding.suffix(n + 1))
        guard show, w.count >= 2, w.contains(where: { $0.minutes > 0 }) else { return nil }
        let full = Array(w.dropLast())                         // the current week is not finished
        let recent = Array(full.suffix(4)), before = Array(full.dropLast(recent.count).suffix(4))
        func avg(_ b: [WeekBucket]) -> Double { b.isEmpty ? 0 : Double(b.reduce(0) { $0 + $1.minutes }) / Double(b.count) }
        let dir = recent.count >= 2 && before.count >= 2 ? direction(recent: avg(recent), before: avg(before)) : nil
        var power: String?
        if let r = best20.recent {
            power = "Best 20-minute power \(r) W" + (best20.before.map { " · \($0) W in the 6 weeks before" } ?? "")
        }
        return Endurance(averageMinutes: Int(avg(recent).rounded()), fullWeeks: recent.count, direction: dir, weeks: w.map(\.minutes),
                         firstLabel: label(w[0].start, cal), lastLabel: label(w[w.count - 1].start, cal), powerLine: power)
    }

    /// The lift with the most logged sessions (at least two), from the app's own lift summaries.
    static func strength(_ lifts: [LiftSummary], weight: (Double) -> String) -> Strength? {
        guard let l = lifts.filter({ $0.topSets.count >= 2 }).max(by: { ($0.topSets.count, $1.name) < ($1.topSets.count, $0.name) }),
              let first = l.topSets.first, let last = l.topSets.last else { return nil }
        var ranges = [Strength.Range(title: "Recorded top set", note: "\(weight(first.weightKg)) × \(first.reps) → \(weight(last.weightKg)) × \(last.reps)",
                                     from: first.weightKg, to: last.weightKg, fromText: weight(first.weightKg), toText: weight(last.weightKg))]
        let est = l.topSets.compactMap(\.e1RM)
        if l.e1RMTrendAvailable, let a = est.first, let b = est.last {
            ranges.insert(.init(title: "Estimated 1RM", note: "estimate · \(est.count) qualifying sessions", from: a, to: b, fromText: weight(a), toText: weight(b)), at: 0)
        }
        // direction: the mean top-set weight of the last two sessions against the two before
        var dir: Direction?
        if l.topSets.count >= 4 {
            let k = l.topSets.map(\.weightKg), n = k.count
            dir = direction(recent: (k[n - 1] + k[n - 2]) / 2, before: (k[n - 3] + k[n - 4]) / 2)
        }
        return Strength(liftName: l.name, sessions: l.topSets.count, latestKg: last.weightKg, latestText: "\(weight(last.weightKg)) × \(last.reps)", direction: dir, ranges: ranges)
    }

    static func consistency(riding: [WeekBucket], lifting: [WeekBucket], weeks n: Int = 14, calendar cal: Calendar = .current) -> Consistency? {
        let starts = Array(Set(riding.map(\.start)).union(lifting.map(\.start))).sorted().suffix(n)
        guard !starts.isEmpty else { return nil }
        let r = Dictionary(riding.map { ($0.start, $0.sessions) }, uniquingKeysWith: { a, _ in a })
        let l = Dictionary(lifting.map { ($0.start, $0.sessions) }, uniquingKeysWith: { a, _ in a })
        let weeks = starts.map { Consistency.Week(rides: r[$0] ?? 0, lifts: l[$0] ?? 0) }
        guard weeks.contains(where: { $0.rides + $0.lifts > 0 }) else { return nil }
        return Consistency(active: weeks.filter { $0.rides + $0.lifts > 0 }.count, total: weeks.count, weeks: weeks,
                           firstLabel: label(starts.first!, cal), lastLabel: label(starts.last!, cal))
    }

    static func zones(_ c: CyclingAnalytics) -> (zones: Zones?, missing: String?) {
        let total = c.zoneSeconds.reduce(0, +)
        guard total > 0, c.zoneSeconds.count >= 2 else { return (nil, c.rides > 0 ? c.zoneBasis : nil) }
        // whole per cents that add up to 100 (largest remainders), so the bar and its labels agree
        let exact = c.zoneSeconds.map { Double($0) * 100 / Double(total) }
        var shares = exact.map { Int($0) }
        let order = exact.indices.sorted { exact[$0] - Double(shares[$0]) > exact[$1] - Double(shares[$1]) }
        for i in order.prefix(max(0, 100 - shares.reduce(0, +))) { shares[i] += 1 }
        let h = Double(total) / 3600
        return (Zones(easyPercent: shares[0] + shares[1], basis: c.zoneBasis, hours: h >= 10 ? "\(Int(h.rounded())) h" : String(format: "%.1f h", h), shares: shares), nil)
    }

    var isEmpty: Bool { endurance == nil && strength == nil && consistency == nil && zones == nil }
}
