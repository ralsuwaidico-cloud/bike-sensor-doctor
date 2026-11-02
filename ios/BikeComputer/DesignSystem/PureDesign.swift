import Foundation

// MARK: - Cyclift design system: pure logic (Foundation only, unit-tested on the Linux harness and on CI)
//
// Everything a component needs that is not drawing lives here: the honesty tag vocabulary, sport identity, day-cell
// states, device states, chart normalisation and the texts of the empty / insufficient-data states. The SwiftUI
// components in this folder are thin views over these types, so the rules (what a tag says, what "needs 2 more rides"
// reads like, how a ring clamps) are testable without a simulator.

/// Where a number comes from. Every visible value in the app carries one (owner rule: never show an estimate as a
/// measurement, never show a guessed value at all).
enum SourceTag: String, Codable, CaseIterable, Equatable {
    /// From a sensor or a recording (heart-rate strap, power meter, GPS, the board).
    case measured
    /// The athlete typed it (a weight, a logged set, an entered FTP).
    case logged
    /// A formula with a known error (estimated 1RM, age-predicted max heart rate).
    case estimated
    /// No value, and nothing is guessed in its place.
    case unknown
    /// The value exists in principle but the data to compute it is not there yet.
    case needsData

    var label: String {
        switch self {
        case .measured: return "Measured"
        case .logged: return "Logged"
        case .estimated: return "Estimated"
        case .unknown: return "Unknown"
        case .needsData: return "Needs data"
        }
    }
    /// Short VoiceOver suffix ("… , measured").
    var spoken: String { label.lowercased() }
}

/// Sport identity: the same icon and tint everywhere (owner rule 2 of the visual system).
enum CySport: String, Codable, CaseIterable, Equatable {
    case cycling, strength, recovery, goal, insight

    var icon: String {
        switch self {
        case .cycling: return "bicycle"
        case .strength: return "dumbbell"
        case .recovery: return "moon"
        case .goal: return "target"
        case .insight: return "sparkles"
        }
    }
    var title: String {
        switch self {
        case .cycling: return "Cycling"
        case .strength: return "Strength"
        case .recovery: return "Recovery"
        case .goal: return "Goal"
        case .insight: return "Insight"
        }
    }
}

/// What a day of the week holds.
enum CyDaySport: String, Codable, CaseIterable, Equatable {
    case rest, cycling, strength, both

    var icons: [String] {
        switch self {
        case .rest: return ["moon"]
        case .cycling: return ["bicycle"]
        case .strength: return ["dumbbell"]
        case .both: return ["bicycle", "dumbbell"]
        }
    }
    var spoken: String {
        switch self {
        case .rest: return "rest"
        case .cycling: return "ride"
        case .strength: return "strength"
        case .both: return "ride and strength"
        }
    }
    /// Tap order in onboarding and Plan: ride → lift → (both, only when two-a-day is allowed) → rest.
    func next(allowBoth: Bool) -> CyDaySport {
        switch self {
        case .cycling: return .strength
        case .strength: return allowBoth ? .both : .rest
        case .both: return .rest
        case .rest: return .cycling
        }
    }
}

/// Status of a planned day.
enum CyDayStatus: String, Codable, CaseIterable, Equatable {
    case planned, done, missed, none

    var spoken: String? {
        switch self {
        case .planned: return "planned"
        case .done: return "done"
        case .missed: return "missed"
        case .none: return nil
        }
    }
}

/// One cell of the week strip.
struct CyDay: Identifiable, Equatable {
    var id: Int                 // 0 = Monday … 6 = Sunday
    var shortName: String       // "Mon"
    var longName: String        // "Monday"
    var sport: CyDaySport
    var status: CyDayStatus
    var isToday: Bool = false

    /// VoiceOver: "Today, Wednesday, strength, done".
    var accessibilityLabel: String {
        var parts: [String] = []
        parts.append(isToday ? "Today, \(longName)" : longName)
        parts.append(sport.spoken)
        if let s = status.spoken { parts.append(s) }
        return parts.joined(separator: ", ")
    }
}

/// One cell of the month calendar.
struct CyMonthDay: Identifiable, Equatable {
    var id: Int                 // day-of-month, negative/greater for padding cells
    var number: Int
    var inMonth: Bool
    var sport: CyDaySport
    var status: CyDayStatus
    var isToday: Bool = false
}

/// Connection state of a device. "Connected" is paired and reachable; "receiving" means measurements are arriving now.
/// Paired-but-silent is never shown as receiving (owner rule).
enum CyDeviceState: String, Codable, CaseIterable, Equatable {
    case notPaired, paired, connected, receiving, problem

    var label: String {
        switch self {
        case .notPaired: return "Not connected"
        case .paired: return "Paired"
        case .connected: return "Connected"
        case .receiving: return "Receiving live data"
        case .problem: return "Connection problem"
        }
    }
    var icon: String {
        switch self {
        case .notPaired: return "circle.dashed"
        case .paired: return "link"
        case .connected: return "checkmark.circle"
        case .receiving: return "dot.radiowaves.left.and.right"
        case .problem: return "exclamationmark.triangle"
        }
    }
}

/// Banner kinds (info = lavender, warn = amber, bad = red, success = mint).
enum CyBannerKind: String, CaseIterable, Equatable { case info, warn, bad, success }

/// Pure helpers used by the views.
enum CyDesign {
    /// Ring / progress fraction: NaN, infinities and out-of-range values never reach the drawing code.
    static func clampFraction(_ x: Double) -> Double {
        guard x.isFinite else { return 0 }
        return min(1, max(0, x))
    }

    /// "3 of 5" style ring label; `planned == 0` reads "0 of 0" (never divides).
    static func ringFraction(done: Int, planned: Int) -> Double {
        guard planned > 0 else { return 0 }
        return clampFraction(Double(done) / Double(planned))
    }

    /// Bars normalised to 0…1 against the largest of the values and the plan line (so a plan line above every bar still
    /// fits). Nil values (no data) stay nil.
    static func normalise(_ values: [Double?], planLine: Double? = nil) -> [Double?] {
        let present = values.compactMap { $0 }.filter { $0.isFinite && $0 >= 0 }
        var top = present.max() ?? 0
        if let p = planLine, p.isFinite, p > top { top = p }
        guard top > 0 else { return values.map { $0 == nil ? nil : 0 } }
        return values.map { v in v.flatMap { $0.isFinite && $0 >= 0 ? clampFraction($0 / top) : nil } }
    }

    /// A chart is drawn only with enough real points; otherwise the insufficient-data state is shown.
    static func hasEnoughData(_ values: [Double?], minimum: Int) -> Bool {
        values.compactMap { $0 }.count >= minimum
    }

    /// "Needs 2 more rides" / "Needs 1 more week" — the single wording for every insufficient-data state.
    static func needsMoreText(missing: Int, unit: String) -> String {
        let n = max(1, missing)
        return "Needs \(n) more \(n == 1 ? unit : CyDesign.plural(unit))"
    }

    static func plural(_ unit: String) -> String {
        if unit.hasSuffix("s") { return unit }
        return unit + "s"
    }

    /// Percent text for rings ("60%"), rounded, never above 100.
    static func percentText(_ fraction: Double) -> String {
        "\(Int((clampFraction(fraction) * 100).rounded()))%"
    }

    /// Minutes → "1h 33m" / "58 min" / "0 min".
    static func minutesText(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m >= 60 { return m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m" }
        return "\(m) min"
    }

    /// Rest-timer ring: remaining ÷ total, clamped; a zero total is "done".
    static func timerFraction(remaining: Double, total: Double) -> Double {
        guard total > 0, remaining.isFinite else { return 0 }
        return clampFraction(remaining / total)
    }

    /// mm:ss for timers.
    static func timerText(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Weekday short names, Monday first (the strips are always Monday-first, like Plan).
    static let weekdayShort = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let weekdayLong = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    /// Index 0…6 (Monday first) of a date.
    static func mondayFirstIndex(_ date: Date, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    /// Month grid: leading padding cells so the 1st lands on its weekday (Monday first), then the days, then trailing
    /// padding to complete the last week. `sportFor`/`statusFor` resolve each day of the month.
    static func monthGrid(year: Int, month: Int, today: Date? = nil, calendar: Calendar = .current,
                          sportFor: (Int) -> CyDaySport = { _ in .rest }, statusFor: (Int) -> CyDayStatus = { _ in .none }) -> [CyMonthDay] {
        var comps = DateComponents(); comps.year = year; comps.month = month; comps.day = 1
        guard let first = calendar.date(from: comps), let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let lead = mondayFirstIndex(first, calendar: calendar)
        var cells: [CyMonthDay] = []
        for i in 0..<lead { cells.append(CyMonthDay(id: -(i + 1), number: 0, inMonth: false, sport: .rest, status: .none)) }
        let todayDay: Int? = today.flatMap { t in
            calendar.component(.year, from: t) == year && calendar.component(.month, from: t) == month ? calendar.component(.day, from: t) : nil
        }
        for d in range {
            cells.append(CyMonthDay(id: d, number: d, inMonth: true, sport: sportFor(d), status: statusFor(d), isToday: todayDay == d))
        }
        while cells.count % 7 != 0 { cells.append(CyMonthDay(id: 100 + cells.count, number: 0, inMonth: false, sport: .rest, status: .none)) }
        return cells
    }

    /// Interval timeline heights: intensity 0…1 mapped to a minimum visible height so an easy step is still a bar.
    static func barHeight(intensity: Double, maxHeight: Double, minHeight: Double = 6) -> Double {
        let f = clampFraction(intensity)
        return max(minHeight, f * maxHeight)
    }
}
