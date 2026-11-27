import Foundation

// Key Metrics hub — the owner's approved design direction (27 Nov 2026, 11:40; final visual approval pending).
// Sixteen metrics in four categories, each with its own page, built ONLY on what Cyclift already stores:
//   · Resting heart rate, HRV, Sleep duration — the per-day Apple Health log (`RecoveryLog`) and the existing personal
//     range (`RecoveryAnalysis`): the 28 days before the latest reading, at least 7 readings.
//   · Strength progression — the recorded strength history, compared with the approved Day-page rule
//     (`DayReviewModel.exercise`): exercise by exercise, green or red only when like is compared with like.
//   · Personal baselines — the three existing personal ranges, listed. Nothing is added to them.
//   · Stress & soreness — only the soreness answers given in session reviews. Stress is not collected.
// Everything else has NO data source in the app and says so: blood oxygen, respiratory rate, sleep stages, daily steps
// and a daily active-calorie total are not read from Apple Health (no new permission is requested — owner's decision
// 8); daily energy waits for the journal; heart-rate-zone history is not kept across days. Recovery readiness, training
// strain and recovery-vs-strain are NOT calculated: no score is invented (decision 7). A missing value is nil, never 0.
// This file reads only; it changes no record.

enum KeyMetricID: String, CaseIterable, Identifiable {
    case restingHR, hrv, spo2, respiratory
    case sleepDuration, sleepStages, dailyEnergy, stressSoreness
    case steps, activeCalories, hrZones, strength
    case readiness, strain, recoveryVsStrain, baselines
    /// Not among the sixteen: FTP stays in Performance Settings and is an optional Home metric (owner's decision 1), and
    /// so is Weight (owner, 27 Nov 2026, 13:20). Neither has a tile in the hub.
    case ftp, weight
    var id: String { rawValue }

    var name: String {
        switch self {
        case .restingHR: return "Resting heart rate"
        case .hrv: return "HRV"
        case .spo2: return "Blood oxygen (SpO₂)"
        case .respiratory: return "Respiratory rate"
        case .sleepDuration: return "Sleep duration"
        case .sleepStages: return "Sleep stages"
        case .dailyEnergy: return "Daily energy"
        case .stressSoreness: return "Stress & soreness"
        case .steps: return "Daily steps"
        case .activeCalories: return "Active calories"
        case .hrZones: return "Heart rate zones"
        case .strength: return "Strength progression"
        case .readiness: return "Recovery readiness"
        case .strain: return "Training strain"
        case .recoveryVsStrain: return "Recovery vs. strain"
        case .baselines: return "Personal baselines"
        case .ftp: return "FTP"
        case .weight: return "Weight"
        }
    }
    /// The short title on a hub card (owner, 27 Nov 2026, 15:26). The page itself keeps the full name.
    var shortName: String {
        switch self {
        case .restingHR: return "Resting HR"
        case .spo2: return "Blood oxygen"
        case .sleepDuration: return "Sleep"
        case .dailyEnergy: return "Energy"
        case .steps: return "Steps"
        case .hrZones: return "HR zones"
        case .strength: return "Strength"
        case .readiness: return "Readiness"
        case .strain: return "Strain"
        case .baselines: return "Baselines"
        default: return name
        }
    }
    var icon: String {
        switch self {
        case .restingHR: return "heart.fill"
        case .hrv: return "waveform.path.ecg"
        case .spo2: return "lungs.fill"
        case .respiratory: return "wind"
        case .sleepDuration: return "moon.fill"
        case .sleepStages: return "bed.double.fill"
        case .dailyEnergy: return "bolt.heart"
        case .stressSoreness: return "figure.cooldown"
        case .steps: return "figure.walk"
        case .activeCalories: return "flame.fill"
        case .hrZones: return "chart.bar.fill"
        case .strength: return "dumbbell.fill"
        case .readiness: return "gauge.medium"
        case .strain: return "speedometer"
        case .recoveryVsStrain: return "arrow.left.arrow.right"
        case .baselines: return "ruler"
        case .ftp: return "bolt.fill"
        case .weight: return "scalemass.fill"
        }
    }
    /// The Apple Health reading behind this metric, where the app already stores one.
    var healthKind: HealthSample.Kind? {
        switch self { case .restingHR: return .restingHR; case .hrv: return .hrv; case .sleepDuration: return .sleep; default: return nil }
    }
    /// The short reason shown on a tile that has no source in the app.
    var unavailableLine: String? {
        switch self {
        case .spo2, .respiratory, .sleepStages, .steps, .hrZones: return "Not collected yet"
        case .activeCalories: return "Daily total not collected yet"
        case .dailyEnergy: return "Needs the journal"
        case .readiness, .strain, .recoveryVsStrain: return "No score is calculated"
        default: return nil
        }
    }
    /// The full explanation on the metric's own page.
    var unavailableDetail: String {
        switch self {
        case .spo2: return "Cyclift does not read blood oxygen from Apple Health. Reading it needs a new Apple Health permission, which Cyclift does not ask for today. Until that changes this page stays empty — nothing is estimated."
        case .respiratory: return "Cyclift does not read respiratory rate from Apple Health. Reading it needs a new Apple Health permission, which Cyclift does not ask for today. Until that changes this page stays empty — nothing is estimated."
        case .sleepStages: return "Cyclift keeps the total time asleep for each night and nothing about its stages. Until stages are stored this page stays empty — nothing is estimated."
        case .steps: return "Cyclift does not read steps from Apple Health. Reading them needs a new Apple Health permission, which Cyclift does not ask for today. Until that changes this page stays empty — nothing is estimated."
        case .activeCalories: return "Cyclift reads energy only for single workouts, not a total for the day. Until a daily total is stored this page stays empty — nothing is estimated."
        case .dailyEnergy: return "Daily energy is something you enter yourself in the Sleep & wellness journal, which is not available yet. Nothing is guessed in the meantime."
        case .hrZones: return "Time in zone is kept inside each recorded ride's results. Cyclift keeps no heart-rate-zone history across days yet, and rides recorded with a power meter store power zones instead. Until that history exists this page stays empty — nothing is estimated."
        case .readiness: return "Cyclift does not calculate a readiness score. There is no validated way yet to combine your readings into one number, so none is shown."
        case .strain: return "Cyclift does not calculate a training-strain score. There is no validated definition of it for this app yet, so none is shown."
        case .recoveryVsStrain: return "Cyclift calculates neither a recovery score nor a strain score, so there is nothing to set against each other."
        default: return ""
        }
    }
}

enum KeyMetricCategory: String, CaseIterable, Identifiable {
    case heart, sleep, activity, advanced
    var id: String { rawValue }
    var title: String {
        switch self { case .heart: return "Heart & recovery"; case .sleep: return "Sleep & wellness"; case .activity: return "Activity & performance"; case .advanced: return "Advanced insights" }
    }
    var metrics: [KeyMetricID] {
        switch self {
        case .heart: return [.restingHR, .hrv, .spo2, .respiratory]
        case .sleep: return [.sleepDuration, .sleepStages, .dailyEnergy, .stressSoreness]
        case .activity: return [.steps, .activeCalories, .hrZones, .strength]
        case .advanced: return [.readiness, .strain, .recoveryVsStrain, .baselines]
        }
    }
}

struct KeyMetricTile: Equatable, Identifiable {
    var metric: KeyMetricID
    /// nil = nothing to show; drawn as a dash, never as zero.
    var value: String?
    var unit: String
    /// Source and time, or the reason there is no value.
    var line: String
    /// The one concise status on a hub card: where the value stands, or the short reason there is none. Sources and
    /// detailed comparisons stay on the metric's own page.
    var status: String = ""
    /// Strength progression only: the judged change against the previous session.
    var verdict: DayVerdict? = nil
    /// True when the metric has a value the athlete can put on Home.
    var measurable: Bool
    var onHome: Bool
    var id: String { metric.rawValue }
    var spoken: String { value.map { "\(metric.name), \($0) \(unit), \(line)" } ?? "\(metric.name), no value, \(line)" }
}

struct KeyMetricsHub: Equatable {
    struct Section: Equatable, Identifiable {
        var category: KeyMetricCategory
        /// "2 of 4 available"
        var count: String
        var tiles: [KeyMetricTile]
        var id: String { category.rawValue }
    }
    var sections: [Section]
    /// The metrics on Home, in order; empty when the athlete has made no choice and Home shows its defaults.
    var home: [KeyMetricID]
    var homeIsDefault: Bool
    var hasAny: Bool { sections.contains { $0.tiles.contains { $0.value != nil } } }
    /// The carousel's position dot for a scroll fraction (0 = start, 1 = end) over `count` cards.
    static func dot(fraction: Double, count: Int) -> Int { count <= 1 ? 0 : min(count - 1, max(0, Int((min(max(fraction, 0), 1) * Double(count - 1)).rounded()))) }
    func tile(_ m: KeyMetricID) -> KeyMetricTile? { sections.flatMap(\.tiles).first { $0.metric == m } }
}

/// The athlete's own choice of Home metrics. It is kept in the athlete's settings (`AppSettings.homeMetrics`), so it is
/// in the stored record itself: backup copies, export and updates carry it. nil = no choice made = Home shows exactly
/// what it showed before.
enum KeyMetricsPrefs {
    static let limit = 4
    /// Stored names as metrics: unknown names and repeats dropped, four at most, in the athlete's order.
    static func clean(_ names: [String]) -> [KeyMetricID] {
        var seen = Set<KeyMetricID>()
        return names.compactMap { KeyMetricID(rawValue: $0) }.filter { seen.insert($0).inserted }.prefix(limit).map { $0 }
    }
    /// The extra Home options that are not among the sixteen (owner's decisions of 27 Nov 2026): FTP and Weight.
    static let extras: [KeyMetricID] = [.ftp, .weight]
}

// MARK: - one health reading over time (resting heart rate, HRV, sleep duration)

struct KeyMetricPoint: Equatable, Identifiable {
    var id: Int
    var start: Date
    /// nil = no reading in this period.
    var value: Double?
    var count: Int
    var source: String?
    var date: Date?
    var isWeek: Bool
    var top: String
    var bottom: String
    /// "Tuesday 10 Nov" / "Week of 16–22 Nov"
    var title: String
    var short: String
    /// Against the athlete's current usual range; nil when there is no range or no reading.
    var standing: RecoveryMetric.Standing?
    /// A week only: the stored readings the average was taken from, oldest first — so the average can be checked.
    var records: [RecoveryEntry] = []
}

struct KeyMetricHealthDetail: Equatable {
    var metric: KeyMetricID
    var kind: HealthSample.Kind
    /// Whether this read is turned on in Connections.
    var enabled: Bool
    var latest: String?
    var unit: String
    /// "Wed 25 Nov · 07:06"
    var when: String
    var source: String
    /// "Inside your usual range · 49–57 bpm" / "No usual range yet · 3 of the 7 earlier readings needed" / "No reading"
    var standingLine: String
    var period: Int
    var points: [KeyMetricPoint]
    var caption: String
    var low: Double?
    var high: Double?
    var bandLow: Double?
    var bandHigh: Double?
    var rangeText: String?
    var rangeBasis: String
    var summary: String
    /// Most recent first.
    var recent: [RecoveryEntry]
    var stored: Int
    var hasAny: Bool { stored > 0 }
    var hasInPeriod: Bool { points.contains { $0.value != nil } }
}

// MARK: - strength progression, one exercise at a time

struct StrengthProgressPoint: Equatable, Identifiable {
    var id: Int
    var session: UUID
    var date: Date
    var top: Double?
    var reps: Int
    var sets: Int
    var volume: Double?
    var summary: String
}

struct StrengthProgress: Equatable {
    struct Choice: Equatable, Identifiable { var id: String; var name: String; var sessions: Int }
    var exercises: [Choice]
    var selected: String?
    var name: String
    var period: Int
    /// Sessions of this exercise in the period, oldest first.
    var points: [StrengthProgressPoint]
    /// The latest session of this exercise against the one before it, by the Day page's rule. nil = fewer than one session.
    var comparison: DayExercise?
    var latestDate: Date?
    var previousDate: Date?
    var summary: String
    var hasAny: Bool { !exercises.isEmpty }
    static let measures = ["load", "reps", "sets", "volume"]
    static let measureTitles = ["Top load", "Reps", "Sets", "Volume"]
    func value(_ p: StrengthProgressPoint, measure: Int) -> Double? {
        switch measure { case 0: return p.top; case 1: return Double(p.reps); case 2: return Double(p.sets); default: return p.volume }
    }
}

struct KeyMetricSoreness: Equatable {
    struct Answer: Equatable, Identifiable { var id: String; var date: Date; var answer: String; var session: String }
    /// Most recent first; only what the athlete answered. An unanswered review is not listed and is not "none".
    var answers: [Answer]
    var sessions: Int
    var summary: String
}

enum KeyMetricsModel {
    static let periodTitles = ["7 days", "30 days", "90 days"]
    static let periodIDs = ["7", "30", "90"]
    static let periodDays = [7, 30, 90]

    private static func fmt(_ pattern: String, _ d: Date, _ cal: Calendar) -> String { let f = DateFormatter(); f.calendar = cal; f.timeZone = cal.timeZone; f.dateFormat = pattern; return f.string(from: d) }
    static func noun(_ k: HealthSample.Kind) -> String { RecoveryDashModel.noun(k) }
    static func unitWord(_ k: HealthSample.Kind, _ n: Int) -> String { k == .sleep ? (n == 1 ? "night" : "nights") : (n == 1 ? "reading" : "readings") }
    /// The number alone ("53", "7 h 12 min") and its unit ("bpm", "").
    static func parts(_ k: HealthSample.Kind, _ v: Double) -> (value: String, unit: String) {
        switch k {
        case .sleep: return (Fmt.duration(minutes: Int((v * 60).rounded())), "")
        case .restingHR: return ("\(Int(v.rounded()))", "bpm")
        case .hrv: return ("\(Int(v.rounded()))", "ms")
        case .weight: return (String(format: "%.1f", v), "kg")
        }
    }
    static func rangeText(_ k: HealthSample.Kind, _ b: RecoveryMetric.Baseline) -> String {
        if k == .sleep { return "\(Fmt.duration(minutes: Int((max(0, b.low) * 60).rounded()))) – \(Fmt.duration(minutes: Int((b.high * 60).rounded())))" }
        return RecoveryAnalysis.rangeText(k, b)
    }
    static func standingWord(_ s: RecoveryMetric.Standing) -> String {
        switch s { case .lower: return "Below"; case .higher: return "Above"; case .typical: return "Inside"; case .noBaseline: return "" }
    }
    static func axis(_ k: HealthSample.Kind, _ v: Double) -> String { RecoveryDashboard.axis(k, v) }

    /// The graph's scale: round steps that hold every reading drawn and the usual range.
    static func scale(_ k: HealthSample.Kind, values: [Double], band: (Double, Double)?) -> (low: Double, high: Double)? {
        guard !values.isEmpty else { return nil }
        let all = values + (band.map { [$0.0, $0.1] } ?? [])
        let step: Double = k == .sleep ? 0.5 : 5
        var a = (all.min()! / step).rounded(.down) * step, b = (all.max()! / step).rounded(.up) * step
        if b - a < step * 2 { a -= step; b += step }
        a = max(0, a)
        if Int(((b - a) / step).rounded()) % 2 != 0 { b += step }
        return (a, b)
    }

    static func health(_ metric: KeyMetricID, log: RecoveryLog, enabled: [HealthSample.Kind], period asked: Int, now: Date, calendar cal: Calendar = .current) -> KeyMetricHealthDetail? {
        guard let k = metric.healthKind else { return nil }
        let period = min(max(asked, 0), 2)
        let m = RecoveryAnalysis.metric(k, log: log, now: now, calendar: cal)
        let xs = log.entries(k).sorted { $0.date < $1.date }
        let today = cal.startOfDay(for: now)
        let band: (Double, Double)? = m.baseline.map { (max(0, $0.low), $0.high) }
        func standing(_ v: Double?) -> RecoveryMetric.Standing? {
            guard let v, let b = m.baseline else { return nil }
            return v < b.low ? .lower : v > b.high ? .higher : .typical
        }
        var points: [KeyMetricPoint] = []
        if period < 2 {
            let n = periodDays[period]
            for i in 0..<n {
                let day = cal.date(byAdding: .day, value: -(n - 1 - i), to: today)!
                let key = RecoveryLog.dayKey(day, calendar: cal)
                let e = xs.last { RecoveryLog.dayKey($0.date, calendar: cal) == key }
                points.append(KeyMetricPoint(id: i, start: day, value: e?.value, count: e == nil ? 0 : 1, source: e.map { $0.source ?? "Apple Health" }, date: e?.date, isWeek: false,
                                             top: n == 7 ? fmt("EEE", day, cal) : "", bottom: n == 7 ? fmt("d", day, cal) : "",
                                             title: fmt("EEEE d MMM", day, cal), short: fmt("EEE d MMM", day, cal), standing: standing(e?.value)))
            }
        } else {
            let thisMonday = TrainingLedger.monday(of: now, calendar: cal)
            let n = 13
            for i in 0..<n {
                let from = cal.date(byAdding: .day, value: -7 * (n - 1 - i), to: thisMonday)!, to = cal.date(byAdding: .day, value: 7, to: from)!
                let r = RecoveryDashModel.reading(k, log, from: from, to: to)
                points.append(KeyMetricPoint(id: i, start: from, value: r.value, count: r.count, source: r.source, date: r.date, isWeek: true,
                                             top: fmt("d", from, cal), bottom: fmt("MMM", from, cal),
                                             title: "Week of \(ConsistencyModel.range(from, calendar: cal))", short: fmt("d MMM", from, cal), standing: nil,
                                             records: xs.filter { $0.date >= from && $0.date < to }))
            }
        }
        let vs = points.compactMap(\.value)
        let sc = scale(k, values: vs, band: period < 2 ? band : nil)
        let nounK = noun(k)
        let caption: String
        switch period {
        case 0: caption = "\(k.title) · one reading a day · last 7 days"
        case 1: caption = "\(k.title) · one reading a day · \(fmt("d MMM", points.first!.start, cal)) – \(fmt("d MMM", points.last!.start, cal))"
        default: caption = "\(k.title) · WEEKLY AVERAGES · each point is the average of that week's readings · last 13 weeks"
        }
        // the standing line and the range
        var line = "No reading"
        var rangeBasis = "A usual range needs at least \(RecoveryAnalysis.minBaselineRecords) of your own readings in the \(RecoveryAnalysis.baselineDays) days before the latest one."
        var rangeTextValue: String? = nil
        if let l = m.latest {
            if let b = m.baseline, m.standing != .noBaseline {
                let r = rangeText(k, b)
                line = "\(standingWord(m.standing)) your usual range · \(r)"
                rangeTextValue = r
                rangeBasis = "From \(b.records) \(unitWord(k, b.records)) in the \(RecoveryAnalysis.baselineDays) days before the latest one."
            } else {
                let from = cal.date(byAdding: .day, value: -RecoveryAnalysis.baselineDays, to: cal.startOfDay(for: l.date)) ?? l.date
                let have = xs.filter { $0.date >= from && $0.id != l.id }.count
                line = "No usual range yet · \(have) of the \(RecoveryAnalysis.minBaselineRecords) earlier readings needed"
            }
        }
        // the one summary, in fixed sentences
        var s: [String] = []
        if xs.isEmpty { s.append("There are no \(nounK) readings yet, so there is nothing to describe.") }
        else if vs.isEmpty { s.append("There is no \(nounK) reading in \(period == 2 ? "the last 13 weeks" : "the last \(periodDays[period]) days").") }
        else {
            let within = period == 2 ? xs.filter { $0.date >= points.first!.start } : xs.filter { $0.date >= points.first!.start && $0.date < cal.date(byAdding: .day, value: 1, to: today)! }
            let n = within.count, avg = within.reduce(0) { $0 + $1.value } / Double(max(n, 1))
            let span = period == 2 ? "the last 13 weeks" : "the last \(periodDays[period]) days"
            s.append(n == 1 ? "One \(nounK) reading in \(span): \(RecoveryAnalysis.valueText(k, avg))." : "Over \(span) your recorded \(nounK) averaged \(RecoveryAnalysis.valueText(k, avg)), from \(n) \(unitWord(k, n)).")
            switch m.standing {
            case .typical: s.append("The latest reading is inside your usual range.")
            case .lower: s.append("The latest reading is below your usual range.")
            case .higher: s.append("The latest reading is above your usual range.")
            case .noBaseline: s.append("There is no usual range yet to compare the latest reading with.")
            }
        }
        let p = m.latest.map { parts(k, $0.value) }
        return KeyMetricHealthDetail(metric: metric, kind: k, enabled: enabled.contains(k), latest: p?.value, unit: p?.unit ?? "",
                                     when: m.latest.map { "\(fmt("EEE d MMM", $0.date, cal)) · \(fmt("HH:mm", $0.date, cal))" } ?? "",
                                     source: m.latest.map { $0.source ?? "Apple Health" } ?? "", standingLine: line, period: period, points: points, caption: caption,
                                     low: sc?.low, high: sc?.high, bandLow: period < 2 ? band?.0 : nil, bandHigh: period < 2 ? band?.1 : nil,
                                     rangeText: rangeTextValue, rangeBasis: rangeBasis, summary: s.joined(separator: " "),
                                     recent: Array(xs.reversed().prefix(14)), stored: xs.count)
    }

    /// What the Coach card says about one chosen point. Describes the reading; draws no health conclusion.
    static func pointInsight(_ p: KeyMetricPoint, kind k: HealthSample.Kind) -> String {
        let n = noun(k)
        guard let v = p.value else { return p.isWeek ? "There is no \(n) reading in the \(p.title.prefix(1).lowercased() + p.title.dropFirst())." : "There is no \(n) reading for \(p.title)." }
        let text = RecoveryAnalysis.valueText(k, v)
        if p.isWeek { return "In the \(p.title.prefix(1).lowercased() + p.title.dropFirst()) your recorded \(n) averaged \(text), from \(p.count) \(unitWord(k, p.count))." }
        switch p.standing {
        case .lower?: return "On \(p.title) your recorded \(n) was \(text), below your usual range. One reading outside the range is not a pattern, and Cyclift draws no health conclusion from it."
        case .higher?: return "On \(p.title) your recorded \(n) was \(text), above your usual range. One reading outside the range is not a pattern, and Cyclift draws no health conclusion from it."
        case .typical?: return "On \(p.title) your recorded \(n) was \(text), inside your usual range."
        default: return "On \(p.title) your recorded \(n) was \(text)."
        }
    }
    static func about(_ k: HealthSample.Kind) -> String {
        switch k {
        case .restingHR: return "Resting heart rate is read from Apple Health, one value a day, as your watch or another source recorded it. Cyclift compares it only with your own earlier readings. It is not a medical measurement and Cyclift draws no health conclusion from it."
        case .hrv: return "HRV (heart-rate variability) is read from Apple Health, one value a day, as your watch recorded it. It differs widely from person to person, so Cyclift compares it only with your own earlier readings. It is not a medical measurement and Cyclift draws no health conclusion from it."
        case .sleep: return "Sleep duration is the time asleep for one night as Apple Health holds it, taken from a single source so a night is never counted twice. Cyclift compares it only with your own earlier nights. It is not a sleep recommendation."
        case .weight: return ""
        }
    }

    // MARK: strength

    private static func done(_ s: StrengthSession, _ id: String) -> ExerciseEntry? { (s.exercises ?? []).first { $0.exerciseId == id && !$0.doneSets.isEmpty } }

    static func strength(_ logs: [StrengthSession], selected asked: String?, period askedPeriod: Int, measure: Int, units u: AppSettings.Units, now: Date, calendar cal: Calendar = .current) -> StrengthProgress {
        let period = min(max(askedPeriod, 0), 2)
        let detailed = logs.filter(\.isDetailed).sorted { $0.date < $1.date }
        var count: [String: (name: String, n: Int, last: Date)] = [:]
        for s in detailed { for e in (s.exercises ?? []) where !e.doneSets.isEmpty {
            let c = count[e.exerciseId]; count[e.exerciseId] = (e.name, (c?.n ?? 0) + 1, max(c?.last ?? s.date, s.date))
        } }
        let choices = count.sorted { $0.value.n != $1.value.n ? $0.value.n > $1.value.n : $0.value.last != $1.value.last ? $0.value.last > $1.value.last : $0.value.name < $1.value.name }
            .map { StrengthProgress.Choice(id: $0.key, name: $0.value.name, sessions: $0.value.n) }
        guard let sel = choices.first(where: { $0.id == asked }) ?? choices.first else {
            return StrengthProgress(exercises: [], selected: nil, name: "", period: period, points: [], comparison: nil, latestDate: nil, previousDate: nil,
                                    summary: "There are no recorded strength sessions with exercises yet, so there is nothing to describe.")
        }
        let with = detailed.compactMap { s in done(s, sel.id).map { (s, $0) } }
        let from = cal.date(byAdding: .day, value: -(periodDays[period] - 1), to: cal.startOfDay(for: now))!
        let inPeriod = with.filter { $0.0.date >= from }.suffix(12)
        let points = inPeriod.enumerated().map { i, p in
            StrengthProgressPoint(id: i, session: p.0.id, date: p.0.date, top: DayReviewModel.topLoad(p.1), reps: p.1.totalReps, sets: p.1.doneSets.count, volume: p.1.tonnageKg, summary: p.1.summary(units: u))
        }
        var comparison: DayExercise? = nil
        if let cur = with.last {
            let prev = with.count >= 2 ? with[with.count - 2] : nil
            // reported effort of the two sessions, where both state it — the Day page's rule
            let eDelta: Int? = cur.0.rpe != nil && prev?.0.rpe != nil ? cur.0.rpe! - prev!.0.rpe! : nil
            comparison = DayReviewModel.exercise(planned: nil, current: cur.1, previous: prev?.1, effortDelta: eDelta, units: u)
        }
        // the one summary: how often the chosen figure rose and fell from one session to the next, and the latest comparison
        let progress = StrengthProgress(exercises: choices, selected: sel.id, name: sel.name, period: period, points: points, comparison: comparison,
                                        latestDate: with.last?.0.date, previousDate: with.count >= 2 ? with[with.count - 2].0.date : nil, summary: "")
        let m = min(max(measure, 0), 3), word = StrengthProgress.measureTitles[m].lowercased()
        var s: [String] = []
        let span = "the last \(periodDays[period]) days"
        if points.isEmpty { s.append("No \(sel.name) session is recorded in \(span).") }
        else if points.count == 1 { s.append("One \(sel.name) session is recorded in \(span), so there is nothing to compare within it.") }
        else {
            var up = 0, down = 0
            for i in 1..<points.count { if let a = progress.value(points[i - 1], measure: m), let b = progress.value(points[i], measure: m) { if b > a + 0.05 { up += 1 } else if b < a - 0.05 { down += 1 } } }
            s.append("You recorded \(points.count) \(sel.name) sessions in \(span). From one session to the next, \(word) was higher \(up) time\(up == 1 ? "" : "s") and lower \(down) time\(down == 1 ? "" : "s").")
        }
        if let c = comparison, c.previous != nil { s.append("Latest session against the one before: \(c.change.prefix(1).lowercased() + c.change.dropFirst()).") }
        var out = progress; out.summary = s.joined(separator: " ")
        return out
    }

    // MARK: soreness

    static func soreness(rides: [RideRecord], strength: [StrengthSession], now: Date, calendar cal: Calendar = .current) -> KeyMetricSoreness {
        let from = cal.date(byAdding: .day, value: -90, to: now) ?? now
        var answers: [KeyMetricSoreness.Answer] = []
        var sessions = 0
        for r in rides where r.start >= from {
            sessions += 1
            if let p = r.review?.pain ?? r.checkIn?.pain { answers.append(.init(id: "r-\(r.id.uuidString)", date: r.start, answer: p.title, session: "Ride")) }
        }
        for l in strength where l.date >= from {
            sessions += 1
            if let p = l.review?.pain ?? l.checkIn?.pain { answers.append(.init(id: "s-\(l.id.uuidString)", date: l.date, answer: p.title, session: l.title)) }
        }
        answers.sort { $0.date > $1.date }
        let summary: String
        if sessions == 0 { summary = "There are no recorded sessions in the last 90 days, so there is nothing to describe." }
        else if answers.isEmpty { summary = "None of your \(sessions) recorded sessions in the last 90 days has a soreness answer. An unanswered review is not counted as no soreness." }
        else { summary = "You answered the soreness question after \(answers.count) of your \(sessions) recorded sessions in the last 90 days. An unanswered review is not counted as no soreness." }
        return KeyMetricSoreness(answers: answers, sessions: sessions, summary: summary)
    }
}

extension Store {
    /// The Home metrics as the hub and the chooser see them: the athlete's saved choice, else the metrics Home shows by default.
    func keyMetricsHomeChoice(now: Date = Date()) -> (ids: [KeyMetricID], isDefault: Bool) {
        if let saved = settings.homeMetrics { return (KeyMetricsPrefs.clean(saved), false) }
        // what Home shows without a choice: the three readings, Weight when a weight reading exists, FTP unless strength-only
        var ids: [KeyMetricID] = [.restingHR, .hrv, .sleepDuration]
        if enabledHealthReads.contains(.weight), recoveryLog.entries(.weight).last != nil { ids.append(.weight) }
        if profile.trainingMode != .strength { ids.append(.ftp) }
        return (ids, true)
    }
    /// Stores the athlete's choice in their settings. false = it was not stored, so nothing may be shown as chosen.
    @discardableResult
    func setKeyMetricsHome(_ ids: [KeyMetricID]) -> Bool {
        settings.homeMetrics = Array(ids.prefix(KeyMetricsPrefs.limit)).map(\.rawValue)
        return lastSaveError == nil
    }

    func keyMetricsHealth(_ m: KeyMetricID, period: Int, now: Date = Date(), calendar cal: Calendar = .current) -> KeyMetricHealthDetail? {
        KeyMetricsModel.health(m, log: recoveryLog, enabled: enabledHealthReads, period: period, now: now, calendar: cal)
    }
    func keyMetricsStrength(selected: String?, period: Int, measure: Int, now: Date = Date(), calendar cal: Calendar = .current) -> StrengthProgress {
        KeyMetricsModel.strength(strength, selected: selected, period: period, measure: measure, units: settings.units, now: now, calendar: cal)
    }
    func keyMetricsSoreness(now: Date = Date()) -> KeyMetricSoreness { KeyMetricsModel.soreness(rides: rides, strength: strength, now: now) }
    /// The three existing personal ranges, as the Recovery dashboard words them.
    func keyMetricsBaselines(now: Date = Date(), calendar cal: Calendar = .current) -> [RecoveryRow] {
        RecoveryDashModel.build(log: recoveryLog, enabled: enabledHealthReads, metric: .sleep, now: now, calendar: cal).rows
    }
    var ftpIsKnown: Bool { profile.ftpHow != .assumed && profile.ftpW > 0 }

    /// One tile of the hub. Reads only.
    func keyMetricTile(_ m: KeyMetricID, home: [KeyMetricID], now: Date = Date(), calendar cal: Calendar = .current) -> KeyMetricTile {
        let on = home.contains(m)
        func none(_ line: String) -> KeyMetricTile { KeyMetricTile(metric: m, value: nil, unit: "", line: line, status: line, measurable: false, onHome: on) }
        if let k = m.healthKind {
            let r = RecoveryAnalysis.metric(k, log: recoveryLog, now: now, calendar: cal)
            guard let l = r.latest else { return none(enabledHealthReads.contains(k) ? "No reading yet" : "Apple Health not connected") }
            let p = KeyMetricsModel.parts(k, l.value)
            let f = DateFormatter(); f.calendar = cal; f.dateFormat = cal.isDate(l.date, inSameDayAs: now) ? "'Today' HH:mm" : "EEE d MMM"
            let status: String
            switch r.standing { case .typical: status = "Inside your usual range"; case .lower: status = "Below your usual range"; case .higher: status = "Above your usual range"; case .noBaseline: status = "No usual range yet" }
            return KeyMetricTile(metric: m, value: p.value, unit: p.unit, line: "\(f.string(from: l.date)) · \(l.source ?? "Apple Health")", status: status, measurable: true, onHome: on)
        }
        switch m {
        case .strength:
            let s = keyMetricsStrength(selected: nil, period: 2, measure: 0, now: now, calendar: cal)
            guard s.hasAny, let c = s.comparison else { return none("No strength session") }
            let top = c.metrics.first { $0.id.hasSuffix("-load") }?.current
            let value = top ?? c.metrics.first { $0.id.hasSuffix("-reps") }?.current.map { "\($0) reps" }
            return KeyMetricTile(metric: m, value: value, unit: s.name, line: c.previous == nil ? "One session so far" : c.change, status: c.previous == nil ? "\(s.name) · one session so far" : "\(s.name) · \(c.change.prefix(1).lowercased() + c.change.dropFirst())", verdict: c.verdict, measurable: value != nil, onHome: on)
        case .stressSoreness:
            let s = keyMetricsSoreness(now: now)
            guard let a = s.answers.first else { return none("No soreness answer yet") }
            let f = DateFormatter(); f.calendar = cal; f.dateFormat = "EEE d MMM"
            return KeyMetricTile(metric: m, value: a.answer, unit: "", line: "Soreness · \(f.string(from: a.date)) review · stress not collected", status: "Soreness, from your \(f.string(from: a.date)) review", measurable: true, onHome: on)
        case .baselines:
            let rows = keyMetricsBaselines(now: now, calendar: cal)
            let have = rows.filter { $0.trend.contains("your usual range") }.count
            guard rows.contains(where: { $0.latest != nil }) else { return none("No readings yet") }
            return KeyMetricTile(metric: m, value: "\(have) of \(rows.count)", unit: "ranges", line: have == 0 ? "More readings needed" : "Sleep, resting HR and HRV", status: have == 0 ? "More readings needed" : "Sleep, resting HR and HRV", measurable: false, onHome: on)
        case .ftp:
            guard ftpIsKnown else { return none("Not set in Performance Settings") }
            return KeyMetricTile(metric: m, value: "\(profile.ftpW)", unit: "W", line: profile.ftpLabel, status: profile.ftpLabel, measurable: true, onHome: on)
        case .weight:
            guard enabledHealthReads.contains(.weight), let l = RecoveryAnalysis.metric(.weight, log: recoveryLog, now: now, calendar: cal).latest else {
                return none(enabledHealthReads.contains(.weight) ? "No reading yet" : "Not turned on in Connections")
            }
            let p = KeyMetricsModel.parts(.weight, l.value)
            let f = DateFormatter(); f.calendar = cal; f.dateFormat = "EEE d MMM"
            return KeyMetricTile(metric: m, value: p.value, unit: p.unit, line: "\(f.string(from: l.date)) · \(l.source ?? "Apple Health")", status: "\(f.string(from: l.date))", measurable: true, onHome: on)
        default:
            return none(m.unavailableLine ?? "Not available")
        }
    }

    /// The Key Metrics hub for this athlete's own records. Reads only.
    func keyMetricsHub(now: Date = Date(), calendar cal: Calendar = .current) -> KeyMetricsHub {
        let choice = keyMetricsHomeChoice(now: now)
        let sections = KeyMetricCategory.allCases.map { c -> KeyMetricsHub.Section in
            let tiles = c.metrics.map { keyMetricTile($0, home: choice.ids, now: now, calendar: cal) }
            let n = tiles.filter { $0.value != nil }.count
            return KeyMetricsHub.Section(category: c, count: "\(n) of \(tiles.count) available", tiles: tiles)
        }
        return KeyMetricsHub(sections: sections, home: choice.ids, homeIsDefault: choice.isDefault)
    }

    /// The Home rows for a saved choice, in the athlete's order. `defaults` are the rows Home builds anyway; the three
    /// health readings and FTP are taken from there unchanged, so their look and their existing destinations stay as approved.
    func keyMetricsHomeRows(_ chosen: [KeyMetricID], defaults: [CyHomeMetric], now: Date = Date(), calendar cal: Calendar = .current) -> [CyHomeMetric] {
        chosen.compactMap { m -> CyHomeMetric? in
            switch m {
            case .restingHR: return defaults.first { $0.id == HealthSample.Kind.restingHR.rawValue } ?? HomeV23Builder.metric(.restingHR, nil)
            case .hrv: return defaults.first { $0.id == HealthSample.Kind.hrv.rawValue } ?? HomeV23Builder.metric(.hrv, nil)
            case .sleepDuration: return defaults.first { $0.id == HealthSample.Kind.sleep.rawValue } ?? HomeV23Builder.metric(.sleep, nil)
            case .weight:
                // the row Home already builds for a weight reading, unchanged; with no reading it is an empty row
                return defaults.first { $0.id == HealthSample.Kind.weight.rawValue }
                    ?? HomeV23Builder.metric(.weight, enabledHealthReads.contains(.weight) ? RecoveryAnalysis.metric(.weight, log: recoveryLog, now: now, calendar: cal) : nil)
            case .ftp:
                return defaults.first { $0.id == "ftp" } ?? CyHomeMetric(id: "ftp", icon: "bolt.fill", name: "FTP", value: ftpIsKnown ? "\(profile.ftpW)" : nil, unit: "W", trend: nil, trendLevel: .neutral,
                                                                       explanation: "Functional threshold power sets your riding zones.", source: profile.ftpLabel, history: [], historyUnit: "W",
                                                                       baseline: ftpIsKnown ? profile.ftpLabel : nil, direction: .none)
            default:
                let t = keyMetricTile(m, home: chosen, now: now, calendar: cal)
                // the row shows the bare figure; its unit and what it is compared with sit beside and beneath it
                var value = t.value, unit = t.unit
                if m == .strength, let v = t.value, let space = v.lastIndex(of: " ") { value = String(v[..<space]); unit = String(v[v.index(after: space)...]) }
                return CyHomeMetric(id: m.rawValue, icon: m.icon, name: m == .strength ? "Strength" : m == .stressSoreness ? "Soreness" : m.name, value: value, unit: unit, trend: nil, trendLevel: .neutral,
                                    explanation: t.line, source: t.line, history: [], historyUnit: unit, baseline: m == .strength ? t.unit : nil, direction: .none)
            }
        }
    }
}
