import Foundation

// Checkpoint D (master order §4): Progress analytics from SAVED records only — rides (`RideRecord`), strength sessions
// (`StrengthSession`) and the plan. Nothing is estimated as measured: a value that was not recorded is nil and the
// screen says why. A workout is counted once even when it exists as a Cyclift recording AND an Apple Health import.
// Foundation only; tested on CI and (where the model allows) on the Linux harness.

enum ProgressPeriod: String, CaseIterable, Equatable {
    case week = "Week", month = "Month", quarter = "3 months", year = "Year"
    var days: Int { switch self { case .week: return 7; case .month: return 30; case .quarter: return 91; case .year: return 365 } }
    var title: String { rawValue }
}

/// A value that was measured, with how many records contributed — never shown as a plain number without its basis.
struct Measured<T: Equatable>: Equatable { var value: T; var records: Int }

struct PersonalRecord: Equatable, Identifiable {
    var id: String { kind }
    var kind: String              // "Longest ride", "Best 20-min power", "Heaviest back squat"
    var value: String             // "92.4 km", "262 W", "100 kg × 5"
    var date: Date
    var recordId: UUID?
}

struct CyclingAnalytics: Equatable {
    var period: ProgressPeriod
    var rides: Int
    var distanceKm: Measured<Double>?        // only rides that recorded a distance
    var minutes: Int
    var avgSpeedKmh: Measured<Double>?       // distance ÷ moving time over rides with both
    var avgPower: Measured<Int>?             // duration-weighted over rides that measured power
    var avgHR: Measured<Int>?
    var avgCadence: Measured<Int>?
    var powerTrend: [(week: Date, w: Int)]   // weekly average power (weeks with measured power only)
    var hrTrend: [(week: Date, bpm: Int)]
    var cadenceTrend: [(week: Date, rpm: Int)]
    var zoneSeconds: [Int]                   // 7 power zones from samples when FTP known; else 5 HR zones; empty = not measurable
    var zoneBasis: String                    // "power zones (FTP 240 W)" / "heart-rate zones" / "not measurable: no FTP and no HR zones"
    var consistency: (weeks: Int, active: Int) // weeks in the period with ≥ 1 ride
    var records: [PersonalRecord]
    var comparison: String?                  // "Distance +12 % vs the previous 30 days (6 vs 5 rides)" — only with ≥ 2 rides on both sides
    static func == (a: CyclingAnalytics, b: CyclingAnalytics) -> Bool { a.period == b.period && a.rides == b.rides && a.minutes == b.minutes && a.records == b.records && a.zoneSeconds == b.zoneSeconds }
}

struct StrengthAnalytics: Equatable {
    struct ExerciseLine: Equatable, Identifiable { var id: String; var name: String; var sessions: Int; var sets: Int; var topWeightKg: Double?; var topReps: Int; var lastDate: Date; var trend: String }  // trend: "+5 kg over 4 sessions" / "steady" / "bodyweight"
    var period: ProgressPeriod
    var sessions: Int
    var detailedSessions: Int                // sessions with logged sets (the others are quick logs: counted, not analysed)
    var sets: Int, reps: Int
    var tonnageKg: Measured<Double>?         // Σ reps × kg over weighted sets only; bodyweight sets excluded and said so
    var exercises: [ExerciseLine]            // most frequent first
    var records: [PersonalRecord]
    var consistency: (weeks: Int, active: Int)
    var muscleCoverage: [(group: String, sets: Int)]   // from the exercise catalogue; empty when the sessions have no catalogue exercises
    static func == (a: StrengthAnalytics, b: StrengthAnalytics) -> Bool { a.period == b.period && a.sessions == b.sessions && a.sets == b.sets && a.records == b.records }
}

struct GoalProgress: Equatable {
    var title: String                        // "Riding time this week"
    var detail: String                       // "2 h 10 of 3 h planned"
    var fraction: Double                     // 0…1
}

enum ProgressAnalytics {
    // MARK: de-duplication (same workout through Health, Watch and Cyclift)
    /// Rides are one record each; an Apple Health import that starts within 3 min of a Cyclift recording of similar
    /// length is the same ride and is dropped (the Cyclift record wins because it carries samples and sources).
    static func dedupRides(_ rides: [RideRecord]) -> [RideRecord] {
        let own = rides.filter { !$0.demo && $0.recorder != .health }
        let imports = rides.filter { !$0.demo && $0.recorder == .health }
        var out = own
        for i in imports where !own.contains(where: { abs($0.start.timeIntervalSince(i.start)) < 180 && abs($0.durationS - i.durationS) < max(120, i.durationS / 10) }) { out.append(i) }
        return out.sorted { $0.start < $1.start }
    }
    static func dedupStrength(_ s: [StrengthSession]) -> [StrengthSession] {
        let own = s.filter { !$0.isImported }; let imports = s.filter { $0.isImported }
        var out = own
        for i in imports where !own.contains(where: { abs($0.date.timeIntervalSince(i.date)) < 3 * 3600 && Calendar.current.isDate($0.date, inSameDayAs: i.date) }) { out.append(i) }
        return out.sorted { $0.date < $1.date }
    }

    static func range(_ p: ProgressPeriod, now: Date, calendar cal: Calendar) -> (from: Date, to: Date) {
        let to = now
        let from: Date = p == .week ? TrainingLedger.monday(of: now, calendar: cal) : cal.date(byAdding: .day, value: -(p.days - 1), to: cal.startOfDay(for: now))!
        return (from, to)
    }
    static func weeksIn(_ from: Date, _ to: Date, calendar cal: Calendar) -> [Date] {
        var m = TrainingLedger.monday(of: from, calendar: cal); var out: [Date] = []
        while m <= to { out.append(m); m = cal.date(byAdding: .day, value: 7, to: m)! }
        return out
    }

    // MARK: cycling
    static func cycling(rides allRides: [RideRecord], period: ProgressPeriod, ftpW: Int?, hrZones: [(lo: Int, hi: Int?)]?, now: Date = Date(), calendar cal: Calendar = .current) -> CyclingAnalytics {
        let all = dedupRides(allRides)
        let (from, to) = range(period, now: now, calendar: cal)
        let rs = all.filter { $0.start >= from && $0.start <= to }
        let minutes = rs.reduce(0) { $0 + $1.durationS / 60 }
        let withD = rs.filter { $0.distanceM > 0 }
        let distanceKm: Measured<Double>? = withD.isEmpty ? nil : Measured(value: Double(withD.reduce(0) { $0 + $1.distanceM }) / 1000, records: withD.count)
        let moving = withD.reduce(0) { $0 + $1.durationS }
        let avgSpeed: Measured<Double>? = (withD.isEmpty || moving == 0) ? nil : Measured(value: Double(withD.reduce(0) { $0 + $1.distanceM }) / 1000 / (Double(moving) / 3600), records: withD.count)
        func weighted(_ f: (RideRecord) -> Int?) -> Measured<Int>? {
            let v = rs.compactMap { r in f(r).map { (Double($0), Double(r.durationS)) } }
            guard !v.isEmpty else { return nil }; let w = v.reduce(0.0) { $0 + $1.1 }; guard w > 0 else { return nil }
            return Measured(value: Int((v.reduce(0.0) { $0 + $1.0 * $1.1 } / w).rounded()), records: v.count)
        }
        let weeks = weeksIn(from, to, calendar: cal)
        func trend(_ f: (RideRecord) -> Int?) -> [(Date, Int)] {
            weeks.compactMap { m in let e = cal.date(byAdding: .day, value: 7, to: m)!; let v = rs.filter { $0.start >= m && $0.start < e }.compactMap { r in f(r).map { (Double($0), Double(r.durationS)) } }; let w = v.reduce(0.0) { $0 + $1.1 }; return v.isEmpty || w == 0 ? nil : (m, Int((v.reduce(0.0) { $0 + $1.0 * $1.1 } / w).rounded())) }
        }
        // zone distribution from the recorded samples (1 Hz): power zones when the FTP is known, else HR zones, else none
        var zones: [Int] = []; var basis = "not measurable: no FTP and no heart-rate zones"
        if let ftp = ftpW, ftp > 0, rs.contains(where: { $0.samples.contains { $0.w != nil } }) {
            zones = Array(repeating: 0, count: 7); basis = "power zones (FTP \(ftp) W), from recorded samples"
            for r in rs { for s in r.samples { if let w = s.w { let z = PowerZones.zone(w, ftp: ftp); if z >= 1 { zones[z - 1] += 1 } } } }
        } else if let hz = hrZones, !hz.isEmpty, rs.contains(where: { $0.samples.contains { $0.hr != nil } }) {
            zones = Array(repeating: 0, count: hz.count); basis = "heart-rate zones, from recorded samples"
            for r in rs { for s in r.samples { if let h = s.hr { for (i, z) in hz.enumerated() where h >= z.lo && (z.hi == nil || h <= z.hi!) { zones[i] += 1; break } } } }
        }
        let active = weeks.filter { m in let e = cal.date(byAdding: .day, value: 7, to: m)!; return rs.contains { $0.start >= m && $0.start < e } }.count
        // personal records from ALL saved (non-demo) rides, not just the period
        var recs: [PersonalRecord] = []
        if let r = all.filter({ $0.distanceM > 0 }).max(by: { $0.distanceM < $1.distanceM }) { recs.append(PersonalRecord(kind: "Longest ride", value: String(format: "%.1f km", Double(r.distanceM) / 1000), date: r.start, recordId: r.id)) }
        if let r = all.max(by: { $0.durationS < $1.durationS }), r.durationS > 0 { recs.append(PersonalRecord(kind: "Longest time", value: Fmt.duration(minutes: r.durationS / 60), date: r.start, recordId: r.id)) }
        if let r = all.compactMap({ r in r.best20.map { (r, $0) } }).max(by: { $0.1 < $1.1 }) { recs.append(PersonalRecord(kind: "Best 20-min power", value: "\(r.1) W", date: r.0.start, recordId: r.0.id)) }
        if let r = all.filter({ $0.distanceM > 0 && $0.durationS >= 600 }).max(by: { Double($0.distanceM) / Double($0.durationS) < Double($1.distanceM) / Double($1.durationS) }) { recs.append(PersonalRecord(kind: "Fastest average speed", value: String(format: "%.1f km/h", Double(r.distanceM) / 1000 / (Double(r.durationS) / 3600)), date: r.start, recordId: r.id)) }
        // comparison with the previous period — only when both sides have enough rides to mean something
        var comparison: String? = nil
        if period != .year {
            let prevFrom = cal.date(byAdding: .day, value: -period.days, to: from)!
            let prev = all.filter { $0.start >= prevFrom && $0.start < from }
            if rs.count >= 2 && prev.count >= 2 {
                let dNow = rs.reduce(0) { $0 + $1.distanceM }, dPrev = prev.reduce(0) { $0 + $1.distanceM }
                if dPrev > 0 { let pct = Int((Double(dNow - dPrev) / Double(dPrev) * 100).rounded()); comparison = "Distance \(pct >= 0 ? "+" : "")\(pct) % vs the previous \(period.days) days (\(rs.count) vs \(prev.count) rides)" }
                else { comparison = "\(rs.count) rides vs \(prev.count) in the previous \(period.days) days" }
            }
        }
        return CyclingAnalytics(period: period, rides: rs.count, distanceKm: distanceKm, minutes: minutes, avgSpeedKmh: avgSpeed, avgPower: weighted(\.avgPower), avgHR: weighted(\.avgHR), avgCadence: weighted(\.avgCadence),
                                powerTrend: trend(\.avgPower).map { (week: $0.0, w: $0.1) }, hrTrend: trend(\.avgHR).map { (week: $0.0, bpm: $0.1) }, cadenceTrend: trend(\.avgCadence).map { (week: $0.0, rpm: $0.1) },
                                zoneSeconds: zones, zoneBasis: basis, consistency: (weeks.count, active), records: recs, comparison: comparison)
    }

    // MARK: strength
    static func strength(sessions allSessions: [StrengthSession], period: ProgressPeriod, catalogue: [Exercise] = ExerciseCatalogue.builtIn, now: Date = Date(), calendar cal: Calendar = .current) -> StrengthAnalytics {
        let all = dedupStrength(allSessions)
        let (from, to) = range(period, now: now, calendar: cal)
        let ss = all.filter { $0.date >= from && $0.date <= to }
        let detailed = ss.filter(\.isDetailed)
        var sets = 0, reps = 0, tonnage = 0.0, weightedSets = 0
        var byEx: [String: (name: String, sessions: Set<UUID>, sets: Int, top: Double?, topReps: Int, last: Date, history: [(Date, Double?)])] = [:]
        var groups: [String: Int] = [:]
        let muscles: [String: [String]] = Dictionary(uniqueKeysWithValues: catalogue.map { ($0.id, $0.muscles) })
        for s in detailed { for e in s.exercises ?? [] {
            let done = e.doneSets; guard !done.isEmpty else { continue }
            sets += done.count; reps += done.reduce(0) { $0 + $1.reps * ($1.unilateral ? 2 : 1) }
            let topW = done.compactMap { $0.bodyweight ? nil : $0.weightKg }.max()
            for d in done where !d.bodyweight, let w = d.weightKg { tonnage += w * Double(d.reps); weightedSets += 1 }
            var x = byEx[e.exerciseId] ?? (e.name, [], 0, nil, 0, s.date, [])
            x.sessions.insert(s.id); x.sets += done.count; x.top = [x.top, topW].compactMap { $0 }.max(); x.topReps = max(x.topReps, done.map(\.reps).max() ?? 0); x.last = max(x.last, s.date); x.history.append((s.date, topW))
            byEx[e.exerciseId] = x
            for g in muscles[e.exerciseId] ?? [] { groups[g, default: 0] += done.count }
        } }
        let lines: [StrengthAnalytics.ExerciseLine] = byEx.map { id, x in
            let h = x.history.sorted { $0.0 < $1.0 }.compactMap(\.1)
            let trend: String = h.count < 2 ? (x.top == nil ? "bodyweight" : "first sessions") : (h.last! - h.first! > 0.5 ? String(format: "+%.1f kg over %d sessions", h.last! - h.first!, h.count) : h.last! - h.first! < -0.5 ? String(format: "%.1f kg over %d sessions", h.last! - h.first!, h.count) : "steady")
            return StrengthAnalytics.ExerciseLine(id: id, name: x.name, sessions: x.sessions.count, sets: x.sets, topWeightKg: x.top, topReps: x.topReps, lastDate: x.last, trend: trend)
        }.sorted { $0.sets > $1.sets }
        let weeks = weeksIn(from, to, calendar: cal)
        let active = weeks.filter { m in let e = cal.date(byAdding: .day, value: 7, to: m)!; return ss.contains { $0.date >= m && $0.date < e } }.count
        // records from ALL detailed sessions: heaviest set per exercise (top 5 exercises by frequency)
        var recs: [PersonalRecord] = []
        var allByEx: [String: (name: String, w: Double, reps: Int, date: Date, id: UUID, count: Int)] = [:]
        for s in all.filter(\.isDetailed) { for e in s.exercises ?? [] { for d in e.doneSets where !d.bodyweight, let w = d.weightKg { var cur = allByEx[e.exerciseId]; if cur == nil || w > cur!.w || (w == cur!.w && d.reps > cur!.reps) { cur = (e.name, w, d.reps, s.date, s.id, (cur?.count ?? 0) + 1) } else { cur!.count += 1 }; allByEx[e.exerciseId] = cur } } }
        for (_, r) in allByEx.sorted(by: { $0.value.count > $1.value.count }).prefix(5) { recs.append(PersonalRecord(kind: "Heaviest \(r.name.lowercased())", value: String(format: "%.1f kg × %d", r.w, r.reps), date: r.date, recordId: r.id)) }
        return StrengthAnalytics(period: period, sessions: ss.count, detailedSessions: detailed.count, sets: sets, reps: reps, tonnageKg: weightedSets > 0 ? Measured(value: tonnage, records: weightedSets) : nil,
                                 exercises: lines, records: recs, consistency: (weeks.count, active), muscleCoverage: groups.sorted { $0.value > $1.value }.map { (group: $0.key, sets: $0.value) })
    }

    // MARK: goals (from the profile's weekly hours and the ledger's recorded minutes — this week only)
    static func goals(riding: TrainingLedger.SportWeek, lifting: TrainingLedger.SportWeek, hoursPerWeek: Int, liftingHoursPerWeek: Int, includesCycling: Bool, includesStrength: Bool) -> [GoalProgress] {
        var out: [GoalProgress] = []
        if includesCycling, hoursPerWeek > 0 { let goal = hoursPerWeek * 60; out.append(GoalProgress(title: "Riding time this week", detail: "\(Fmt.duration(minutes: riding.minutes)) of \(Fmt.duration(minutes: goal)) in your week", fraction: min(1, Double(riding.minutes) / Double(goal)))) }
        if includesStrength, liftingHoursPerWeek > 0 { let goal = liftingHoursPerWeek * 60; out.append(GoalProgress(title: "Lifting time this week", detail: "\(Fmt.duration(minutes: lifting.minutes)) of \(Fmt.duration(minutes: goal)) in your week", fraction: min(1, Double(lifting.minutes) / Double(goal)))) }
        if riding.planned + lifting.planned > 0 { let d = riding.plannedDone + lifting.plannedDone, p = riding.planned + lifting.planned; out.append(GoalProgress(title: "Planned sessions this week", detail: "\(d) of \(p) done", fraction: Double(d) / Double(p))) }
        return out
    }
}
