import Foundation

// Checkpoint E — Recovery. Pure model: a per-day log of Apple Health readings (one entry per kind per day, with the
// source and the sample time), freshness, a conservative "typical range" from the last 28 days, and ONE actionable
// recommendation. There is no readiness score (master order 8 Nov §5): every statement names the reading, its source
// and when it was recorded, and says "outside your usual range", never a diagnosis.

/// One reading kept in the history: the value, the day it belongs to, where Apple Health got it, and the sample time.
struct RecoveryEntry: Codable, Equatable, Identifiable {
    var kind: HealthSample.Kind
    var value: Double
    /// Sample end (sleep: end of the night). The calendar day of this date is the entry's day.
    var date: Date
    /// Apple Health source name (e.g. "Apple Watch", a sleep app). nil for readings logged before the source was kept.
    var source: String?
    var id: String { "\(kind.rawValue)-\(RecoveryLog.dayKey(date))" }
}

/// Append-only per-day history, bounded to `keepDays`. Later samples for the same kind and day replace earlier ones.
struct RecoveryLog: Codable, Equatable {
    var entries: [RecoveryEntry] = []
    static let keepDays = 90

    static func dayKey(_ d: Date, calendar cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.year, .month, .day], from: d); return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
    /// Merges samples; returns how many entries were added or replaced. Pure apart from `self`.
    @discardableResult
    mutating func merge(_ samples: [HealthSample], now: Date = Date(), calendar cal: Calendar = .current) -> Int {
        var changed = 0
        for s in samples {
            let e = RecoveryEntry(kind: s.kind, value: s.value, date: s.date, source: s.source)
            if let i = entries.firstIndex(where: { $0.id == e.id }) {
                if entries[i] != e, s.date >= entries[i].date { entries[i] = e; changed += 1 }
            } else { entries.append(e); changed += 1 }
        }
        if changed > 0 {
            let cutoff = cal.date(byAdding: .day, value: -RecoveryLog.keepDays, to: now) ?? now
            entries = entries.filter { $0.date >= cutoff }.sorted { $0.date < $1.date }
        }
        return changed
    }
    func entries(_ k: HealthSample.Kind) -> [RecoveryEntry] { entries.filter { $0.kind == k } }
}

enum RecoveryFreshness: Equatable {
    case fresh          // < 24 h old
    case aging          // 1–3 days
    case stale          // older than 3 days
    case missing
    var word: String { switch self { case .fresh: return "fresh"; case .aging: return "older than a day"; case .stale: return "stale"; case .missing: return "no reading" } }
    static func of(_ date: Date?, now: Date) -> RecoveryFreshness {
        guard let d = date else { return .missing }
        let h = now.timeIntervalSince(d) / 3600
        return h < 24 ? .fresh : h < 72 ? .aging : .stale
    }
}

/// What a reading means against the athlete's own recent readings — conservative, in plain words.
struct RecoveryMetric: Equatable, Identifiable {
    enum Standing: Equatable { case typical, lower, higher, noBaseline }
    struct Baseline: Equatable { var low: Double; var high: Double; var records: Int; var days: Int }
    var kind: HealthSample.Kind
    var latest: RecoveryEntry?
    var freshness: RecoveryFreshness
    var baseline: Baseline?
    var standing: Standing
    /// "Apple Watch · Sat 7 Nov, 07:12 · fresh"
    var sourceLine: String
    /// One sentence, never a conclusion about the body: "7.9 h, inside your usual 7.1–8.2 h over 21 nights."
    var explanation: String
    /// Last 14 days, oldest first (nil = no reading that day), with day labels.
    var series: [Double?]
    var labels: [String]
    var id: String { kind.rawValue }
    /// True when the reading is outside the usual range in the direction that usually goes with fatigue
    /// (less sleep, lower HRV, higher resting HR). Weight never counts.
    var flagged: Bool {
        switch kind { case .sleep, .hrv: return standing == .lower; case .restingHR: return standing == .higher; case .weight: return false }
    }
}

/// The one recommendation (master order §5: "one actionable recommendation").
struct RecoveryAdvice: Equatable {
    enum Kind: Equatable { case hold, trainAsPlanned, watch, easier, noData }
    var kind: Kind
    var title: String
    var detail: String
    /// The readings the advice rests on, each with source and time, so the athlete can check it.
    var basis: [String]
}

enum RecoveryAnalysis {
    static let baselineDays = 28
    static let minBaselineRecords = 7
    static let seriesDays = 14

    static func metric(_ k: HealthSample.Kind, log: RecoveryLog, now: Date, calendar cal: Calendar = .current) -> RecoveryMetric {
        let xs = log.entries(k).sorted { $0.date < $1.date }
        let latest = xs.last
        let fresh = RecoveryFreshness.of(latest?.date, now: now)
        // baseline: the 28 days before the latest reading's day, needs ≥ 7 records; interquartile range widened by half
        var baseline: RecoveryMetric.Baseline? = nil
        if let l = latest {
            let from = cal.date(byAdding: .day, value: -baselineDays, to: cal.startOfDay(for: l.date)) ?? l.date
            let prior = xs.filter { $0.date >= from && $0.id != l.id }.map(\.value).sorted()
            if prior.count >= minBaselineRecords {
                let q1 = quantile(prior, 0.25), q3 = quantile(prior, 0.75)
                let margin = max((q3 - q1) * 0.5, minimumMargin(k))
                baseline = .init(low: q1 - margin, high: q3 + margin, records: prior.count, days: baselineDays)
            }
        }
        var standing: RecoveryMetric.Standing = .noBaseline
        if let l = latest, let b = baseline { standing = l.value < b.low ? .lower : l.value > b.high ? .higher : .typical }
        // series: last 14 days ending today
        let today = cal.startOfDay(for: now)
        var series: [Double?] = []; var labels: [String] = []
        let f = DateFormatter(); f.dateFormat = "E"
        for i in stride(from: seriesDays - 1, through: 0, by: -1) {
            let day = cal.date(byAdding: .day, value: -i, to: today)!
            let key = RecoveryLog.dayKey(day, calendar: cal)
            series.append(xs.last { RecoveryLog.dayKey($0.date, calendar: cal) == key }?.value)
            labels.append(i % 2 == 0 ? String(f.string(from: day).prefix(2)) : "")
        }
        return RecoveryMetric(kind: k, latest: latest, freshness: fresh, baseline: baseline, standing: standing,
                              sourceLine: sourceLine(latest, fresh), explanation: explain(k, latest, baseline, standing, fresh), series: series, labels: labels)
    }

    static func metrics(log: RecoveryLog, enabled: [HealthSample.Kind], now: Date, calendar cal: Calendar = .current) -> [RecoveryMetric] {
        let order: [HealthSample.Kind] = [.sleep, .restingHR, .hrv, .weight]
        return order.filter { enabled.contains($0) }.map { metric($0, log: log, now: now, calendar: cal) }
    }

    /// ONE recommendation. Order of precedence: health hold → no fresh readings → two or more fresh readings outside
    /// the usual range → one → train as planned. Weight never influences it. Nothing here is a readiness score.
    static func advice(_ ms: [RecoveryMetric], trainingAllowed: Bool, todayIsRest: Bool, now: Date) -> RecoveryAdvice {
        if !trainingAllowed {
            return RecoveryAdvice(kind: .hold, title: "Training is on hold", detail: "Your health check put training on hold. Recovery readings do not change that — review the health check when you are ready.", basis: [])
        }
        let considered = ms.filter { $0.kind != .weight }
        let fresh = considered.filter { $0.freshness == .fresh && $0.latest != nil }
        if fresh.isEmpty {
            let what = considered.isEmpty ? "No recovery reads are turned on." : "No reading from the last 24 hours."
            return RecoveryAdvice(kind: .noData, title: todayIsRest ? "Rest as planned" : "Train as planned", detail: "\(what) Cyclift only comments on readings it has: wear the watch overnight or turn on the reads in Connections, and this page will say what it found.", basis: considered.compactMap { $0.latest == nil ? nil : "\($0.kind.title): \($0.sourceLine)" })
        }
        let flagged = fresh.filter(\.flagged)
        let basis = fresh.map { "\($0.kind.title): \($0.explanation) \($0.sourceLine)." }
        let withBaseline = fresh.filter { $0.baseline != nil }
        if flagged.count >= 2 {
            let names = flagged.map { $0.kind.title.lowercased() }.joined(separator: " and ")
            return RecoveryAdvice(kind: .easier, title: todayIsRest ? "Keep today easy" : "Make today's session easier",
                                  detail: todayIsRest ? "Your \(names) are outside your usual range today. A rest day is already planned — keep it light." :
                                    "Your \(names) are outside your usual range today. Shorten today's session or drop it one zone, and keep the plan otherwise. One day's readings are not a diagnosis; if this repeats for several days, consider a rest day.", basis: basis)
        }
        if flagged.count == 1 {
            let m = flagged[0]
            return RecoveryAdvice(kind: .watch, title: todayIsRest ? "Rest as planned" : "Train as planned — and notice how it feels",
                                  detail: "\(m.kind.title) is outside your usual range today while the other readings are typical. Start the session as planned; if it feels unusually hard in the first ten minutes, shorten it.", basis: basis)
        }
        if withBaseline.isEmpty {
            return RecoveryAdvice(kind: .trainAsPlanned, title: todayIsRest ? "Rest as planned" : "Train as planned",
                                  detail: "Today's readings are recorded, but fewer than \(minBaselineRecords) earlier days exist to compare them with. Cyclift says nothing about them until it has your usual range.", basis: basis)
        }
        return RecoveryAdvice(kind: .trainAsPlanned, title: todayIsRest ? "Rest as planned" : "Train as planned",
                              detail: "Today's readings are inside your usual range from the last \(baselineDays) days.", basis: basis)
    }

    // MARK: words
    static func sourceLine(_ e: RecoveryEntry?, _ f: RecoveryFreshness) -> String {
        guard let e else { return "No reading" }
        let df = DateFormatter(); df.dateFormat = "EEE d MMM, HH:mm"
        return [e.source ?? "Apple Health", df.string(from: e.date), f.word].joined(separator: " · ")
    }
    static func valueText(_ k: HealthSample.Kind, _ v: Double) -> String {
        switch k {
        case .sleep: let h = Int(v), m = Int(((v - Double(h)) * 60).rounded()); return m == 60 ? "\(h + 1) h 00" : "\(h) h \(String(format: "%02d", m))"
        case .restingHR: return "\(Int(v.rounded())) bpm"
        case .hrv: return "\(Int(v.rounded())) ms"
        case .weight: return String(format: "%.1f kg", v)
        }
    }
    static func rangeText(_ k: HealthSample.Kind, _ b: RecoveryMetric.Baseline) -> String {
        switch k {
        case .sleep: return String(format: "%.1f–%.1f h", max(0, b.low), b.high)
        case .restingHR: return "\(Int(b.low.rounded()))–\(Int(b.high.rounded())) bpm"
        case .hrv: return "\(Int(max(0, b.low).rounded()))–\(Int(b.high.rounded())) ms"
        case .weight: return String(format: "%.1f–%.1f kg", b.low, b.high)
        }
    }
    static func explain(_ k: HealthSample.Kind, _ e: RecoveryEntry?, _ b: RecoveryMetric.Baseline?, _ s: RecoveryMetric.Standing, _ f: RecoveryFreshness) -> String {
        guard let e else { return "No \(k.title.lowercased()) reading in Apple Health yet." }
        let v = valueText(k, e.value)
        let unit = k == .sleep ? "nights" : "days"
        guard let b else { return "\(v). Fewer than \(minBaselineRecords) earlier \(unit) in the last \(baselineDays) days, so there is no usual range to compare with yet." }
        let r = rangeText(k, b)
        let stale = f == .fresh ? "" : " This reading is \(f.word)."
        switch s {
        case .typical: return "\(v), inside your usual \(r) over \(b.records) \(unit).\(stale)"
        case .lower: return "\(v), below your usual \(r) over \(b.records) \(unit).\(stale)"
        case .higher: return "\(v), above your usual \(r) over \(b.records) \(unit).\(stale)"
        case .noBaseline: return v
        }
    }
    static func minimumMargin(_ k: HealthSample.Kind) -> Double { switch k { case .sleep: return 0.5; case .restingHR: return 3; case .hrv: return 5; case .weight: return 0.5 } }
    static func quantile(_ sorted: [Double], _ q: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let pos = q * Double(sorted.count - 1); let i = Int(pos.rounded(.down)); let frac = pos - Double(i)
        return i + 1 < sorted.count ? sorted[i] * (1 - frac) + sorted[i + 1] * frac : sorted[i]
    }
}
