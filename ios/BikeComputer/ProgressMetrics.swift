import Foundation

// MARK: - Progress maths (RC2-UX milestone 1). Pure Foundation, no SwiftUI: unit-tested on the simulator and on Linux.
// The views (TrendCharts.swift, ProgressView.swift) only draw what these functions return. Every weekly figure comes
// from the one query layer (TrainingLedger), so Progress, Plan and Home always agree.

struct WeekBucket: Identifiable, Equatable {
    var id: Date { start }
    /// Monday 00:00 of the week.
    let start: Date
    var minutes: Int
    var sessions: Int
    var km: Double = 0
    /// Completed sessions without a recorded duration (counted as sessions, add no minutes).
    var unknownDuration: Int = 0
    /// Planned (not skipped) sessions of the week and their planned minutes; 0 when nothing was planned.
    var plannedSessions: Int = 0
    var plannedMinutes: Int = 0
}

enum ChartRange: String, CaseIterable, Identifiable {
    case w4 = "4 wk", w8 = "8 wk", w12 = "12 wk", w16 = "16 wk", y1 = "1 yr"
    var id: String { rawValue }
    var weeks: Int {
        switch self { case .w4: return 4; case .w8: return 8; case .w12: return 12; case .w16: return 16; case .y1: return 52 }
    }
    /// Nominal label rhythm (the drawn labels come from `TrendChartMath.axisLabels`, which measures them).
    func labelStride(accessibility: Bool) -> Int {
        let base: Int
        switch self { case .w4: base = 1; case .w8: base = 2; case .w12: base = 3; case .w16: base = 4; case .y1: base = 13 }
        return accessibility ? base * 2 : base
    }
    /// The ranges worth offering: 4 to 16 weeks always; 1 year only when there is training older than 16 weeks.
    static func available(_ b: [WeekBucket]) -> [ChartRange] {
        let older = b.dropLast(16).contains { $0.sessions > 0 || $0.minutes > 0 }
        return older ? allCases : [.w4, .w8, .w12, .w16]
    }
}

/// What the detailed chart plots. Riding: minutes per week (the riding target is in hours). Strength: sessions per week
/// (consistency; lifting minutes are often missing or typed, so a minutes bar would mislead — RC2 showed a 1-minute sliver).
enum TrendMetric: String, CaseIterable, Identifiable {
    case riding = "Riding", strength = "Strength"
    var id: String { rawValue }
    func value(_ b: WeekBucket) -> Double { self == .riding ? Double(b.minutes) : Double(b.sessions) }
    func planned(_ b: WeekBucket) -> Double { self == .riding ? Double(b.plannedMinutes) : Double(b.plannedSessions) }
    var singular: String { self == .riding ? "ride" : "session" }
    var plural: String { self == .riding ? "rides" : "sessions" }
    /// The question the chart answers (shown under its title).
    var question: String { self == .riding ? "Riding time per week, done against planned" : "Strength sessions per week, done against planned" }
    var unitName: String { self == .riding ? "time" : "sessions" }
    func axisText(_ v: Double) -> String { self == .riding ? TrendChartMath.minuteAxisText(v) : "\(Int(v))" }
    func ticks(max: Double) -> [Double] { self == .riding ? TrendChartMath.minuteTicks(maxMinutes: Int(max.rounded(.up))) : TrendChartMath.countTicks(maxCount: Int(max.rounded(.up))) }
}

enum TrendChartMath {
    static let weekSeconds: TimeInterval = 7 * 86_400

    /// Mondays of the last `count` weeks ending with the week of `now`, oldest first.
    static func mondays(endingAt now: Date, count: Int, calendar cal: Calendar = .current) -> [Date] {
        let m = TrainingLedger.monday(of: now, calendar: cal)
        return (0..<max(1, count)).reversed().map { cal.date(byAdding: .day, value: -7 * $0, to: m)! }
    }

    /// Weekly buckets from the ledger. `riding` = rides (+ rides marked done); otherwise lifting sessions. Planned
    /// figures are the week's planned, not skipped, sessions (the same numbers Plan shows as "Planned this week").
    static func buckets(_ ledger: TrainingLedger, riding: Bool, weeks: Int, now: Date, calendar cal: Calendar = .current) -> [WeekBucket] {
        mondays(endingAt: now, count: weeks, calendar: cal).map { m in
            let w = riding ? ledger.riding(weekOf: m) : ledger.lifting(weekOf: m)
            var km = 0.0
            if riding {
                let e = cal.date(byAdding: .day, value: 7, to: m)!
                km = Double(ledger.rides.filter { $0.start >= m && $0.start < e }.reduce(0) { $0 + $1.distanceM }) / 1000
            }
            return WeekBucket(start: m, minutes: w.minutes, sessions: w.completed, km: km, unknownDuration: w.unknownDuration,
                              plannedSessions: w.planned, plannedMinutes: w.plannedMinutes)
        }
    }

    /// The last `weeks` buckets (the window a range shows: it always ends with the current week).
    static func window(_ b: [WeekBucket], weeks: Int) -> [WeekBucket] { Array(b.suffix(max(1, weeks))) }

    /// The buckets inside the visible window that starts at `scrollStart` and spans `weeks` weeks.
    static func visible(_ b: [WeekBucket], scrollStart: Date, weeks: Int, calendar cal: Calendar = .current) -> [WeekBucket] {
        let s = TrainingLedger.monday(of: scrollStart.addingTimeInterval(3 * 86_400), calendar: cal)   // nearest Monday
        let e = cal.date(byAdding: .day, value: 7 * weeks, to: s)!
        return b.filter { $0.start >= s && $0.start < e }
    }

    struct Summary: Equatable { var averageMinutes: Int; var totalMinutes: Int; var sessions: Int; var weeks: Int; var rangeText: String }
    static func summary(_ v: [WeekBucket], calendar cal: Calendar = .current) -> Summary {
        guard let first = v.first, let last = v.last else { return Summary(averageMinutes: 0, totalMinutes: 0, sessions: 0, weeks: 0, rangeText: "") }
        let total = v.reduce(0) { $0 + $1.minutes }
        let end = cal.date(byAdding: .day, value: 6, to: last.start)!
        return Summary(averageMinutes: Int((Double(total) / Double(v.count)).rounded()), totalMinutes: total, sessions: v.reduce(0) { $0 + $1.sessions }, weeks: v.count, rangeText: rangeText(first.start, end, calendar: cal))
    }

    /// "12–18 Oct", "28 Sep – 4 Oct", "29 Dec 2025 – 4 Jan 2026" (year only when the range crosses a year or is not this year).
    static func rangeText(_ a: Date, _ b: Date, now: Date = Date(), calendar cal: Calendar = .current) -> String {
        let df = DateFormatter(); df.locale = Locale(identifier: "en_GB"); df.calendar = cal; df.timeZone = cal.timeZone
        let ya = cal.component(.year, from: a), yb = cal.component(.year, from: b), yn = cal.component(.year, from: now)
        let sameMonth = cal.component(.month, from: a) == cal.component(.month, from: b) && ya == yb
        if ya != yb {
            df.dateFormat = "d MMM yyyy"; return "\(df.string(from: a)) – \(df.string(from: b))"
        }
        let year = ya != yn ? " \(ya)" : ""
        if sameMonth {
            df.dateFormat = "d"; let d1 = df.string(from: a); df.dateFormat = "d MMM"
            return "\(d1)–\(df.string(from: b))\(year)"
        }
        df.dateFormat = "d MMM"
        return "\(df.string(from: a)) – \(df.string(from: b))\(year)"
    }

    /// "12–18 Oct · 2 h 05 min · 3 rides"
    static func callout(_ b: WeekBucket, singular: String, plural: String, calendar cal: Calendar = .current, now: Date = Date()) -> String {
        let end = cal.date(byAdding: .day, value: 6, to: b.start)!
        var t = "\(rangeText(b.start, end, now: now, calendar: cal)) · \(clock(b.minutes)) · \(b.sessions) \(b.sessions == 1 ? singular : plural)"
        if b.unknownDuration > 0 { t += " (\(b.unknownDuration) without duration)" }
        return t
    }

    /// "2 h 05 min", "45 min", "0 min".
    static func clock(_ m: Int) -> String { m >= 60 ? String(format: "%d h %02d min", m / 60, m % 60) : "\(m) min" }

    /// The bucket whose week contains `d`.
    static func bucket(at d: Date?, in b: [WeekBucket], calendar cal: Calendar = .current) -> WeekBucket? {
        guard let d else { return nil }
        let m = TrainingLedger.monday(of: d, calendar: cal)
        return b.first { $0.start == m }
    }

    /// Where a scrolling chart would open: the window that ends with the most recent week.
    static func initialScrollStart(_ b: [WeekBucket], weeks: Int, calendar cal: Calendar = .current) -> Date {
        guard let last = b.last?.start else { return Date() }
        let s = cal.date(byAdding: .day, value: -7 * (weeks - 1), to: last)!
        return max(s, b.first?.start ?? s)
    }

    /// Every n-th week, phased so that the oldest week of a `w`-week window is labelled (kept for the label tests).
    static func labelDates(_ b: [WeekBucket], stride n: Int, visibleWeeks w: Int) -> [Date] {
        let starts = b.map { $0.start }
        guard !starts.isEmpty, n > 0 else { return [] }
        let phase = max(0, w - 1) % n
        return starts.enumerated().filter { (starts.count - 1 - $0.offset) % n == phase }.map { $0.element }
    }
    /// Y grid in whole hours (kept for the older tests; the chart uses `minuteTicks`).
    static func yTicks(maxMinutes: Int) -> [Double] {
        let hours = max(1.0, Double(maxMinutes) / 60)
        let step = max(1, Int((hours / 4).rounded(.up)))
        return stride(from: 0, through: Double(Int(hours.rounded(.up)) + step), by: Double(step)).map { $0 * 60 }
    }
    /// Label stride widened until neighbours are `minSpacing` apart (RC2 first fix; kept for its tests).
    static func drawnStride(base: Int, plotWidth: Double, weeks: Int, minSpacing: Double) -> Int {
        guard plotWidth > 0, weeks > 0 else { return max(1, base) }
        let perWeek = plotWidth / Double(weeks)
        var n = max(1, base)
        while Double(n) * perWeek < minSpacing && n < weeks { n += max(1, base) }
        return n
    }

    static func axisLabel(_ d: Date, calendar cal: Calendar = .current) -> String {
        let df = DateFormatter(); df.locale = Locale(identifier: "en_GB"); df.calendar = cal; df.timeZone = cal.timeZone; df.dateFormat = "d MMM"
        return df.string(from: d)
    }

    // MARK: axis (milestone 1): measured labels, adaptive density, never overlapping

    struct AxisLabel: Equatable { var index: Int; var text: String; var centre: Double; var width: Double }
    /// Strides tried, smallest first: every week, every 2nd … every 26th.
    static let strides = [1, 2, 3, 4, 6, 8, 13, 26, 52]
    /// Date labels under a bar chart of `starts.count` weeks drawn `plotWidth` points wide (week i is centred at
    /// (i + 0.5) × plotWidth / count). Each label is measured with `width`; the newest week anchors the rhythm; the stride
    /// is the smallest at which neighbouring labels keep `gap` points of air. A label that would leave
    /// [−leftRoom, plotWidth + rightRoom] is left out rather than clipped. Overlap is impossible by construction and tested.
    static func axisLabels(_ starts: [Date], plotWidth: Double, gap: Double = 8, leftRoom: Double = 0, rightRoom: Double = 0,
                           width: (String) -> Double, calendar cal: Calendar = .current) -> [AxisLabel] {
        let n = starts.count
        guard n > 0, plotWidth > 0 else { return [] }
        let slot = plotWidth / Double(n)
        let all = starts.enumerated().map { i, d -> AxisLabel in
            let t = axisLabel(d, calendar: cal)
            return AxisLabel(index: i, text: t, centre: (Double(i) + 0.5) * slot, width: width(t))
        }
        func fits(_ l: AxisLabel) -> Bool {
            let lo: Double = l.centre - l.width / 2, hi: Double = l.centre + l.width / 2
            return lo >= -leftRoom && hi <= plotWidth + rightRoom
        }
        func apart(_ a: AxisLabel, _ b: AxisLabel) -> Bool {
            let need: Double = (a.width + b.width) / 2 + gap
            return b.centre - a.centre >= need
        }
        for s in strides {
            let idx: [Int] = Array(Swift.stride(from: n - 1, through: 0, by: -s)).reversed()
            let picked: [AxisLabel] = idx.map { all[$0] }.filter(fits)
            guard !picked.isEmpty else { continue }
            var ok = true
            for k in 1..<max(1, picked.count) where !apart(picked[k - 1], picked[k]) { ok = false }
            if ok { return picked }
        }
        return []
    }

    /// Riding y grid: 0 plus up to four steps of 30 min, 1 h, 2 h, 3 h …
    static func minuteTicks(maxMinutes: Int) -> [Double] {
        let m = max(30, maxMinutes)
        let step = [30, 60, 120, 180, 240, 360, 480, 600].first { (m + $0 - 1) / $0 <= 4 } ?? 720
        let top = ((m + step - 1) / step) * step
        return Swift.stride(from: 0, through: top, by: step).map(Double.init)
    }
    /// Session-count grid: whole numbers, at most about five lines.
    static func countTicks(maxCount: Int) -> [Double] {
        let m = max(2, maxCount)
        let step = m <= 5 ? 1 : m <= 10 ? 2 : 5
        let top = ((m + step - 1) / step) * step
        return Swift.stride(from: 0, through: top, by: step).map(Double.init)
    }
    /// "0", "30 min", "1 h", "1 h 30".
    static func minuteAxisText(_ v: Double) -> String {
        let m = Int(v.rounded())
        if m == 0 { return "0" }
        if m < 60 { return "\(m) min" }
        return m % 60 == 0 ? "\(m / 60) h" : "\(m / 60) h \(m % 60)"
    }

    // MARK: selection and range texts

    struct WeekDetail: Equatable { var title: String; var value: String; var done: String; var planned: String; var note: String? }
    /// What a tapped bar shows: the week, the exact value with its unit, done and planned, and anything partial.
    static func detail(_ b: WeekBucket, metric: TrendMetric, now: Date = Date(), calendar cal: Calendar = .current) -> WeekDetail {
        let end = cal.date(byAdding: .day, value: 6, to: b.start)!
        let current = b.start == TrainingLedger.monday(of: now, calendar: cal)
        let title = (current ? "This week so far · " : "Week of ") + rangeText(b.start, end, now: now, calendar: cal)
        let n = b.sessions, p = b.plannedSessions
        let value: String, done: String, planned: String
        switch metric {
        case .riding:
            value = Fmt.duration(minutes: b.minutes)
            done = "Done: \(Fmt.duration(minutes: b.minutes)) · \(n) \(n == 1 ? "ride" : "rides")" + (b.km > 0 ? String(format: " · %.1f km", b.km) : "")
            planned = p > 0 ? "Planned: \(Fmt.duration(minutes: b.plannedMinutes)) · \(p) \(p == 1 ? "ride" : "rides")" : "Planned: nothing"
        case .strength:
            value = "\(n) \(n == 1 ? "session" : "sessions")"
            done = "Done: \(n) \(n == 1 ? "session" : "sessions") · \(Fmt.duration(minutes: b.minutes)) recorded"
            planned = p > 0 ? "Planned: \(p) \(p == 1 ? "session" : "sessions") · \(Fmt.duration(minutes: b.plannedMinutes))" : "Planned: nothing"
        }
        let note: String? = b.unknownDuration > 0
            ? "\(b.unknownDuration) marked done without a duration: counted as \(b.unknownDuration == 1 ? "a session" : "sessions"), adds no time."
            : nil
        return WeekDetail(title: title, value: value, done: done, planned: planned, note: note)
    }

    struct RangeSummary: Equatable { var title: String; var value: String; var line: String }
    /// The header when no bar is selected: the average over the FULL weeks of the range (the current week is still
    /// running, so it is left out of the average but kept in the totals).
    static func rangeSummary(_ v: [WeekBucket], metric: TrendMetric, now: Date = Date(), calendar cal: Calendar = .current) -> RangeSummary {
        guard let first = v.first, let last = v.last else { return RangeSummary(title: "No weeks", value: "—", line: "") }
        let thisMonday = TrainingLedger.monday(of: now, calendar: cal)
        // M1 review (run 101, 1 yr): weeks before the first week with any data are not "weeks without training" — a rider with
        // 16 weeks of history got "55 min average of 51 full weeks". The average starts at the first week with data.
        let firstData = v.firstIndex { $0.sessions > 0 || $0.minutes > 0 || $0.plannedSessions > 0 } ?? 0
        let full = v[firstData...].filter { $0.start < thisMonday }
        let range = rangeText(first.start, cal.date(byAdding: .day, value: 6, to: last.start)!, now: now, calendar: cal)
        let sessions = v.reduce(0) { $0 + $1.sessions }, minutes = v.reduce(0) { $0 + $1.minutes }
        let k = full.count
        switch metric {
        case .riding:
            let avg = k > 0 ? Int((Double(full.reduce(0) { $0 + $1.minutes }) / Double(k)).rounded()) : minutes
            return RangeSummary(title: k > 0 ? "Average per week" : "This week so far", value: Fmt.duration(minutes: avg),
                                line: "\(range) · total \(Fmt.duration(minutes: minutes)) · \(sessions) \(sessions == 1 ? "ride" : "rides")" + (k > 0 ? " · average of \(k) full \(k == 1 ? "week" : "weeks")" : ""))
        case .strength:
            let active = full.filter { $0.sessions > 0 }.count
            let avg = k > 0 ? Double(full.reduce(0) { $0 + $1.sessions }) / Double(k) : Double(sessions)
            return RangeSummary(title: k > 0 ? "Average per week" : "This week so far", value: String(format: avg == avg.rounded() ? "%.0f" : "%.1f", avg) + (avg == 1 ? " session" : " sessions"),
                                line: "\(range) · \(sessions) \(sessions == 1 ? "session" : "sessions")" + (k > 0 ? " · lifted in \(active) of \(k) full \(k == 1 ? "week" : "weeks")" : ""))
        }
    }

    /// True when the window has nothing to draw: no session done and nothing planned (an empty state replaces the chart).
    static func isEmpty(_ v: [WeekBucket]) -> Bool { !v.contains { $0.sessions > 0 || $0.minutes > 0 || $0.plannedSessions > 0 } }

    // MARK: at a glance

    /// Full weeks before the current one, newest last, limited to `weeks` and to weeks since `firstActivity` (a rider who
    /// started three weeks ago is never told "1 of 8 weeks").
    static func fullWeeks(_ b: [WeekBucket], weeks: Int, firstActivity: Date?, now: Date = Date(), calendar cal: Calendar = .current) -> [WeekBucket] {
        let thisMonday = TrainingLedger.monday(of: now, calendar: cal)
        let since = firstActivity.map { TrainingLedger.monday(of: $0, calendar: cal) } ?? thisMonday
        return Array(b.filter { $0.start < thisMonday && $0.start >= since }.suffix(weeks))
    }
    /// The Monday of the first week with any completed session in either list.
    static func firstActivity(_ lists: [[WeekBucket]]) -> Date? {
        lists.compactMap { $0.first { $0.sessions > 0 }?.start }.min()
    }
}

/// The Level-1 cards on Progress: what happened this week and whether it is on track. Pure: built from the same buckets
/// as the chart; the view only lays them out.
struct ProgressGlance: Equatable {
    struct Card: Equatable, Identifiable {
        var id: String
        var title: String
        var value: String
        var detail: String
        /// Which detailed chart the card opens (nil = the FTP card).
        var opens: TrendMetric?
    }
    var cards: [Card]

    struct Input {
        var riding: [WeekBucket]
        var lifting: [WeekBucket]
        var showRiding: Bool
        var showLifting: Bool
        /// Sets logged this week (detailed strength logs).
        var setsThisWeek: Int
        /// Weekly riding target in minutes (Profile hours × 60); 0 = none.
        var ridingTargetMinutes: Int
        var ftpW: Int
        /// "tested", "entered", "estimated", "estimated · unverified"
        var ftpBadge: String
        /// Best 20-minute power of rides in the last 8 weeks and in the 8 weeks before (nil = no ride with power).
        var best20Recent: Int?
        var best20Before: Int?
        var now: Date = Date()
    }

    static func make(_ i: Input, calendar cal: Calendar = .current) -> ProgressGlance {
        var cards: [Card] = []
        let first = TrendChartMath.firstActivity([i.riding, i.lifting])
        let r = i.riding.last, l = i.lifting.last
        if i.showRiding, let r {
            let last4 = TrendChartMath.fullWeeks(i.riding, weeks: 4, firstActivity: first, now: i.now, calendar: cal)
            let avg = last4.isEmpty ? nil : Int((Double(last4.reduce(0) { $0 + $1.minutes }) / Double(last4.count)).rounded())
            let plannedPart = r.plannedSessions > 0 ? "of \(Fmt.duration(minutes: r.plannedMinutes)) planned" : "nothing planned"
            cards.append(Card(id: "glanceRiding", title: "Riding this week", value: Fmt.duration(minutes: r.minutes),
                              detail: "\(plannedPart) · \(r.sessions) \(r.sessions == 1 ? "ride" : "rides")" + (r.unknownDuration > 0 ? " (\(r.unknownDuration) without duration)" : "") + (avg.map { " · \(last4.count)-wk avg \(Fmt.duration(minutes: $0))" } ?? ""),
                              opens: .riding))
        }
        if i.showLifting, let l {
            let last8 = TrendChartMath.fullWeeks(i.lifting, weeks: 8, firstActivity: first, now: i.now, calendar: cal)
            let active = last8.filter { $0.sessions > 0 }.count
            var parts: [String] = []
            parts.append(l.minutes > 0 ? "\(Fmt.duration(minutes: l.minutes)) recorded" : "no time recorded")
            if l.unknownDuration > 0 { parts.append("\(l.unknownDuration) without duration") }
            if i.setsThisWeek > 0 { parts.append("\(i.setsThisWeek) sets") }
            if !last8.isEmpty { parts.append("lifted in \(active) of the last \(last8.count) \(last8.count == 1 ? "week" : "weeks")") }
            cards.append(Card(id: "glanceStrength", title: "Strength this week", value: l.plannedSessions > 0 ? "\(l.sessions) of \(l.plannedSessions)" : "\(l.sessions)",
                              detail: (l.plannedSessions > 0 ? "sessions done of planned · " : "sessions · ") + parts.joined(separator: " · "), opens: .strength))
        }
        if i.showRiding || i.showLifting {
            let rs = i.showRiding ? (r?.sessions ?? 0) : 0, ls = i.showLifting ? (l?.sessions ?? 0) : 0
            let rw = TrendChartMath.fullWeeks(i.riding, weeks: 4, firstActivity: first, now: i.now, calendar: cal)
            let lw = TrendChartMath.fullWeeks(i.lifting, weeks: 4, firstActivity: first, now: i.now, calendar: cal)
            let k = max(rw.count, lw.count)
            let total = (i.showRiding ? rw.reduce(0) { $0 + $1.sessions } : 0) + (i.showLifting ? lw.reduce(0) { $0 + $1.sessions } : 0)
            var detail: [String] = []
            if i.showRiding && i.showLifting { detail.append("\(rs) \(rs == 1 ? "ride" : "rides") + \(ls) \(ls == 1 ? "lift" : "lifts")") }
            if k > 0 { detail.append(String(format: "%.1f a week over the last %d %@", Double(total) / Double(k), k, k == 1 ? "week" : "weeks")) }
            else { detail.append("averages start after your first full week") }
            cards.append(Card(id: "glanceFrequency", title: "Sessions this week", value: "\(rs + ls)", detail: detail.joined(separator: " · "), opens: i.showRiding ? .riding : .strength))
        }
        if i.showRiding, i.ridingTargetMinutes > 0 {
            let last4 = TrendChartMath.fullWeeks(i.riding, weeks: 4, firstActivity: first, now: i.now, calendar: cal)
            if last4.isEmpty {
                cards.append(Card(id: "glanceGoal", title: "Weekly riding target", value: Fmt.duration(minutes: i.ridingTargetMinutes),
                                  detail: "measured after your first full week", opens: .riding))
            } else {
                let met = last4.filter { $0.minutes >= i.ridingTargetMinutes }.count
                cards.append(Card(id: "glanceGoal", title: "Weekly riding target", value: "\(met) of \(last4.count)",
                                  detail: "full weeks with at least \(Fmt.duration(minutes: i.ridingTargetMinutes)) of riding", opens: .riding))
            }
        }
        if i.showRiding {
            let trend: String
            switch (i.best20Recent, i.best20Before) {
            case let (a?, b?): trend = "best 20 min \(a) W in the last 8 weeks, \(a >= b ? "+" : "−")\(abs(a - b)) W on the 8 weeks before"
            case let (a?, nil): trend = "best 20 min \(a) W in the last 8 weeks"
            default: trend = "no ride with power in the last 16 weeks"
            }
            cards.append(Card(id: "glanceFTP", title: "FTP", value: "\(i.ftpW) W", detail: "\(i.ftpBadge) · \(trend)", opens: nil))
        }
        return ProgressGlance(cards: cards)
    }

    /// Best 20-minute power in the last 8 weeks and in the 8 weeks before (rides with power only; nothing estimated).
    static func best20Trend(_ rides: [RideRecord], now: Date = Date(), calendar cal: Calendar = .current) -> (recent: Int?, before: Int?) {
        let m = TrainingLedger.monday(of: now, calendar: cal)
        let a = cal.date(byAdding: .day, value: -7 * 7, to: m)!, b = cal.date(byAdding: .day, value: -7 * 15, to: m)!
        var recent: Int? = nil, before: Int? = nil
        for r in rides where !r.demo && r.start >= b {
            guard let p = r.best20 else { continue }
            if r.start >= a { recent = max(recent ?? 0, p) } else { before = max(before ?? 0, p) }
        }
        return (recent, before)
    }
}
