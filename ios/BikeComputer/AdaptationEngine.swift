import Foundation

// MARK: - Adaptive hybrid-athlete coach (deterministic, pure Swift, no UI). Design: ios/ADAPTIVE_COACH.md.
// Loop: Plan → Perform → Log → Rate (check-in) → Analyze → Adapt → Repeat.
// Three separate layers:
//   1. AdaptiveRules        — constraints and bounds (what may change, by how much, which sessions are off-limits)
//   2. TrainingAnalyzer     — quantitative analysis (loads, rolling baselines, trends, fatigue / improvement flags)
//   3. AdaptationExplainer  — template explanations with the actual numbers ("Coach (rules-based)")
// An AI explanation layer is NOT integrated: `CoachExplanationProvider` is only a hook; the rules provider is the one
// in use and the reliable offline fallback. Nothing here claims a model.

/// Everything the engine reads. Built by `Store.adaptationInput(now:)`; tests build it directly.
struct AdaptationInput {
    var profile: RiderProfile
    var plan: [Workout]
    var rides: [RideRecord]
    var strength: [StrengthSession]
    var availability: WeeklyAvailability
    var equipment: EquipmentProfile = EquipmentProfile()
    var catalogue: [Exercise] = []
    var templates: [WorkoutTemplate] = []
    /// Planned exercises of each open strength session AS ORIGINALLY PLANNED (before any coach change), by workout id.
    var originalEntries: [UUID: [ExerciseEntry]] = [:]
    /// Adjustment keys the rider undid / proposal ids the rider declined (never proposed or applied again).
    var dismissed: Set<String> = []
    /// Adjustment keys the rider approved in a proposal (applied like automatic ones while the reason holds).
    var approved: Set<String> = []
    /// Adjustments in force now (kept unchanged when confidence is low: "keep the plan").
    var active: [PlanAdjustment] = []
    var units: AppSettings.Units = .metric
    var now: Date = Date()
    var calendar: Calendar = .current
    /// The rider's explicit "this pain is gone" confirmations (clear an earlier report in that area at once).
    var painClearances: [PainClearance] = []
}

/// "My knees are fine now": the rider's own confirmation that a reported pain has gone (audit G-06).
struct PainClearance: Codable, Equatable { var area: PainArea; var at: Date }

struct AdaptationResult {
    /// Changes to apply to future sessions (automatic ones plus approved ones), each with its why.
    var adjustments: [PlanAdjustment]
    /// Changes that need the rider's OK.
    var proposals: [AdaptiveProposal]
    var summary: AdaptationSummary
    var analysis: TrainingAnalysis
}

// MARK: - Layer 1: rules and constraints
enum AdaptiveRules {
    /// Bounds of one automatic change (brief D).
    static let maxRepsStep = 1                  // reps change by 1 per decision (never more than ±2 in total)
    static let maxWeightStepKg = 2.5            // absolute cap of one load step
    static let maxWeightFraction = 0.05         // … and never more than 5 % of the current load
    static let progressionMaxRPE = 8            // every planned set completed at RPE ≤ 8 …
    static let progressionSessions = 2          // … on the 2 most recent sessions of that exercise
    static let durationFraction = 0.10          // ±10 % duration, rounded to 5 min
    static let majorLoadFraction = 0.10         // > 10 % more planned weekly load → approval
    static let baselineDays = 28                // personal baselines: rolling 4 weeks
    static let painHoldDays = 14                // (kept for reference; since the audit fix pain no longer expires by date)
    static let painMinHoldDays = 7              // a concerning-pain report holds its area at least 7 days …
    static let painClearCheckIns = 2            // … and then until 2 pain-free sessions that loaded that area the same way
    static let fatigueHorizonDays = 7           // fatigue responses touch the next 7 days only
    static let progressionHorizonDays = 14      // progressions: the next session of each exercise within 14 days
    static let minUsableSessions = 2            // fewer usable sessions in 14 days → low confidence, plan kept
    static let legPatterns: Set<MovementPattern> = [.squat, .hinge, .singleLeg]

    /// A session the coach may change ON ITS OWN: future (today included), open, not skipped, not on a fixed day, not
    /// changed by hand, and — for strength — not carrying sets the rider typed or accepted from an insight.
    /// `w` must be the session as originally planned (`restoredOriginal`).
    static func autoEligible(_ w: Workout, now: Date, calendar cal: Calendar) -> Bool {
        guard !w.done, !w.skipped, !w.fixed, !w.edited else { return false }
        guard cal.startOfDay(for: w.date) >= cal.startOfDay(for: now) else { return false }
        if w.kind == .strength, w.plannedEntries != nil, !w.generatedEntries { return false }
        return true
    }
    /// A session a rider-approved change may touch (fixed days allowed, never hand-edited or completed ones).
    static func approvalEligible(_ w: Workout, now: Date, calendar cal: Calendar) -> Bool {
        !w.done && !w.skipped && !w.edited && cal.startOfDay(for: w.date) >= cal.startOfDay(for: now)
    }
    /// One zone step easier (VO2 → threshold → tempo → endurance); nil when already easy or not an interval/tempo ride.
    static func stepDown(_ k: WorkoutKind) -> WorkoutKind? {
        switch k { case .vo2: return .threshold; case .threshold: return .tempo; case .tempo: return .endurance; default: return nil }
    }
    static func roundTo5(_ m: Double) -> Int { max(5, Int((m / 5).rounded()) * 5) }
    /// Session-RPE estimate of a planned session (CR-10), used only to size planned weekly load.
    static func plannedRPE(_ k: WorkoutKind) -> Double {
        switch k {
        case .recovery, .mobility: return 2
        case .endurance: return 3
        case .long: return 4
        case .other: return 4
        case .tempo: return 5
        case .strength: return 6
        case .threshold: return 7
        case .vo2, .ftpTest: return 8
        case .recoveryDay, .rest: return 0
        }
    }
    static func plannedLoad(_ w: Workout) -> Double { w.skipped ? 0 : Double(w.minutes) * plannedRPE(w.kind) }
    /// Does an interval session with `reps` repetitions still fit its planned minutes (15 min warm-up, 10 cool-down)?
    static func intervalsFit(kind k: WorkoutKind, reps: Int, minutes: Int) -> Bool {
        15 + reps * (k.intervalWorkMinutes + k.intervalRestMinutes) + 10 <= minutes
    }

    /// Applies adjustments to a session as originally planned. `entries` = its original planned exercises.
    static func apply(_ adjustments: [PlanAdjustment], to original: Workout, entries: [ExerciseEntry]) -> Workout {
        var x = original
        var e = entries
        var entriesChanged = false
        for a in adjustments {
            switch a.change {
            case .kind(let k):
                x.kind = k
                if k.defaultIntervalReps == nil { x.intervalReps = nil }
            case .intervalReps(let d):
                if let base = x.effectiveIntervalReps { x.intervalReps = max(1, base + d) }
            case .minutes(let d):
                x.minutes = max(15, x.minutes + d)
            case .reps(let id, let d):
                for i in e.indices where e[i].exerciseId == id { for j in e[i].sets.indices { e[i].sets[j].reps = max(1, e[i].sets[j].reps + d) } }
                entriesChanged = true
            case .weight(let id, let kg):
                for i in e.indices where e[i].exerciseId == id {
                    for j in e[i].sets.indices where !e[i].sets[j].bodyweight {
                        if let w = e[i].sets[j].weightKg { e[i].sets[j].weightKg = ((w + kg) * 100).rounded() / 100 }
                    }
                }
                entriesChanged = true
            case .sets(let id, let d):
                for i in e.indices where e[i].exerciseId == id {
                    if d > 0, var last = e[i].sets.last { for _ in 0..<d { last.id = UUID(); last.done = true; e[i].sets.append(last) } }
                    if d < 0 { for _ in 0..<(-d) where e[i].sets.count > 1 { e[i].sets.removeLast() } }
                }
                entriesChanged = true
            case .replace(let id, let newId, let name, let pattern):
                for i in e.indices where e[i].exerciseId == id { e[i].exerciseId = newId; e[i].name = name; e[i].pattern = pattern }
                entriesChanged = true
            }
        }
        if entriesChanged { x.plannedEntries = e }
        return x
    }
}

// MARK: - Layer 2: quantitative analysis
/// One completed session as the analysis sees it. Nothing is invented: a missing value stays nil.
struct SessionSignal: Equatable {
    enum Sport: String { case cycling, strength }
    var sport: Sport
    var date: Date
    var minutes: Int
    /// Subjective effort 1–10: the check-in, else the logged session RPE (strength). Never estimated.
    var effort: Int?
    var performance: Int?
    var pain: PainLevel = .noPain
    var painArea: PainArea? = nil
    /// Sport-neutral internal load in arbitrary units (session-RPE × minutes, Foster 2001); for a ride without a rating,
    /// estimated from verified power or average heart rate (labelled); nil when nothing allows it.
    var load: Double?
    var loadSource: String?
    var plannedMinutes: Int? = nil
    var plannedKind: WorkoutKind? = nil
    var hasHR = false
    var hasVerifiedPower = false
    var hasUnverifiedPower = false
    var hasCheckIn = false
    /// Strength: heavy leg work from evidence (StrengthSession.heavyLegs).
    var legHeavy = false
    var usable: Bool { effort != nil || load != nil }
}

struct FatigueFlag: Equatable {
    enum Scope: String { case cycling, strength, combined }
    var id: String
    var scope: Scope
    var text: String
}

struct TrainingAnalysis: Equatable {
    var sessions: [SessionSignal] = []           // newest first, last 35 days
    var usableRecent = 0                          // usable sessions in the last 14 days
    var unusableRides = 0                         // rides of the last 14 days with no rating, HR or verified power
    var unverifiedPowerOnly = 0                   // … of which had only unverified power
    var acuteLoad: Double? = nil                  // last 7 days
    var chronicWeeklyLoad: Double? = nil          // mean weekly load of the 4 weeks before (needs ≥ 3 weeks of history)
    var acwr: Double? { guard let a = acuteLoad, let c = chronicWeeklyLoad, c > 0 else { return nil }; return a / c }
    var effortBaseline: Double? = nil
    var performanceBaseline: Double? = nil
    var fatigue: [FatigueFlag] = []
    var missed: [Workout] = []
    var repeatedMisses = false
    var painAreas: [PainArea] = []
    /// Concerning-pain areas whose hold could end (≥ 7 days, the last 2 sessions of that activity pain-free): the rider
    /// is asked; the coach never releases them on its own.
    var painReviewDue: [PainArea] = []
    /// Concerning pain reported again within 14 days, or held for more than 14 days: stronger advice.
    var painPersistent: [PainArea] = []
    /// Non-specific discomfort: no progression in that area until a later session of the same activity is rated
    /// without discomfort or pain; nothing is left out.
    var discomfortAreas: [PainArea] = []
    var cyclingImproving = false
    var cyclingImprovingText: String? = nil
    var findings: [String] = []

    var cyclingFatigue: Bool { fatigue.contains { $0.scope == .cycling } }
    var strengthFatigue: Bool { fatigue.contains { $0.scope == .strength } }
    var combinedFatigue: Bool { fatigue.contains { $0.scope == .combined } }
    var anyFatigue: Bool { !fatigue.isEmpty }
    var severeFatigue: Bool { fatigue.count >= 2 }
    var adherenceBlock: Bool { missed.count >= 2 }
    func painBlocks(_ p: MovementPattern) -> Bool { (painAreas + discomfortAreas).contains { $0.patterns.contains(p) } }
    var painBlocksCycling: Bool { painAreas.contains { $0.affectsCycling } }
    var discomfortBlocksCycling: Bool { discomfortAreas.contains { $0.affectsCycling } }
}

enum TrainingAnalyzer {
    /// CR-10 effort anchors for a heart-rate zone (Borg CR-10 / Foster session-RPE scale) — load estimate only.
    static let hrZoneEffort: [Double] = [2, 3, 5, 7, 9]
    /// CR-10 effort from the intensity factor (NP / FTP) of a ride with VERIFIED power — load estimate only.
    static func effort(intensityFactor f: Double) -> Double { f < 0.75 ? 3 : f < 0.85 ? 5 : f < 0.95 ? 7 : f < 1.05 ? 8 : 9 }
    /// Epley estimated one-rep max: w × (1 + reps / 30).
    static func e1RM(weightKg w: Double, reps r: Int) -> Double { w * (1 + Double(r) / 30) }

    static func analyze(_ input: AdaptationInput) -> TrainingAnalysis {
        let cal = input.calendar, now = input.now, p = input.profile
        let today = cal.startOfDay(for: now)
        func daysAgo(_ n: Int) -> Date { cal.date(byAdding: .day, value: -n, to: today)! }
        var out = TrainingAnalysis()
        let horizon = daysAgo(35)

        // --- sessions (completed only; demo rides never count; a strength session in progress lives elsewhere)
        var sessions: [SessionSignal] = []
        for r in input.rides where !r.demo && r.start >= horizon && r.start <= now {
            let minutes = max(1, r.durationS / 60)
            let planned = input.plan.first { $0.kind.isRide && cal.isDate($0.date, inSameDayAs: r.start) }
            var s = SessionSignal(sport: .cycling, date: r.start, minutes: minutes, effort: r.checkIn?.effort, performance: r.checkIn?.performance, load: nil, loadSource: nil)
            s.pain = r.checkIn?.pain ?? .noPain; s.painArea = r.checkIn?.painArea
            s.plannedMinutes = planned?.minutes; s.plannedKind = planned?.kind
            s.hasHR = r.avgHR != nil; s.hasCheckIn = r.checkIn != nil
            s.hasVerifiedPower = r.powerVerified == true && r.avgPower != nil
            s.hasUnverifiedPower = r.powerVerified != true && r.avgPower != nil
            if let e = r.checkIn?.effort { s.load = Double(e * minutes); s.loadSource = "check-in effort × minutes" }
            else if s.hasVerifiedPower, p.ftpW > 0, let np = r.normalizedPower ?? r.avgPower { s.load = effort(intensityFactor: Double(np) / Double(p.ftpW)) * Double(minutes); s.loadSource = "verified power (estimate)" }
            else if let hr = r.avgHR { s.load = hrZoneEffort[hrZone(hr, profile: p) - 1] * Double(minutes); s.loadSource = "average heart rate (estimate)" }
            sessions.append(s)
        }
        for x in input.strength where !x.inProgress && x.date >= horizon && x.date <= now {
            let e = x.checkIn?.effort ?? x.rpe
            var s = SessionSignal(sport: .strength, date: x.date, minutes: max(1, x.minutes), effort: e, performance: x.checkIn?.performance, load: e.map { Double($0 * max(1, x.minutes)) }, loadSource: e == nil ? nil : (x.checkIn != nil ? "check-in effort × minutes" : "session RPE × minutes"))
            s.pain = x.checkIn?.pain ?? .noPain; s.painArea = x.checkIn?.painArea
            s.hasCheckIn = x.checkIn != nil; s.legHeavy = x.heavyLegs
            sessions.append(s)
        }
        sessions.sort { $0.date > $1.date }
        out.sessions = sessions
        let recent14 = sessions.filter { $0.date >= daysAgo(14) }
        out.usableRecent = recent14.filter { $0.usable }.count
        let badRides = recent14.filter { $0.sport == .cycling && !$0.usable }
        out.unusableRides = badRides.count
        out.unverifiedPowerOnly = badRides.filter { $0.hasUnverifiedPower }.count

        // --- loads (audit G-09): acute = the last 7 COMPLETED days (today is still running and not counted), chronic =
        // the mean weekly load of the up-to-4 weeks before them, divided by the weeks actually covered — and only once
        // ≥ 28 days of history exist (≥ 3 weeks before the acute week), so a new rider's repeated week reads ≈ 1.0.
        let loaded = sessions.filter { $0.load != nil }
        let acuteStart = cal.date(byAdding: .day, value: -7, to: today)!
        let recent7 = cal.date(byAdding: .day, value: -6, to: today)!          // the 7 calendar days incl. today (hard-effort count)
        out.acuteLoad = loaded.isEmpty ? nil : loaded.filter { $0.date >= acuteStart && $0.date < today }.reduce(0) { $0 + ($1.load ?? 0) }
        if let oldest = loaded.last?.date, cal.startOfDay(for: oldest) <= daysAgo(28) {
            let chronicStart = max(cal.startOfDay(for: oldest), daysAgo(35))
            let days = Double(cal.dateComponents([.day], from: chronicStart, to: acuteStart).day ?? 28)
            let weeks = max(1.0, days / 7.0)
            let chronic = loaded.filter { $0.date < acuteStart && $0.date >= chronicStart }.reduce(0) { $0 + ($1.load ?? 0) } / weeks
            out.chronicWeeklyLoad = chronic > 0 ? chronic : nil
        }

        // --- personal baselines from check-ins (the 4 weeks before the 2 most recent ones; need ≥ 3)
        let rated = sessions.filter { $0.hasCheckIn }
        let base = Array(rated.dropFirst(2)).filter { $0.date >= daysAgo(AdaptiveRules.baselineDays + 7) }
        if base.count >= 3 {
            out.effortBaseline = Double(base.compactMap { $0.effort }.reduce(0, +)) / Double(base.count)
            out.performanceBaseline = Double(base.compactMap { $0.performance }.reduce(0, +)) / Double(base.count)
        }

        // --- fatigue flags: each needs two consistent sessions (one unusual workout never triggers anything)
        func effortUpPerformanceDown(_ list: [SessionSignal]) -> [SessionSignal]? {
            let r = list.filter { $0.hasCheckIn && $0.effort != nil && $0.performance != nil && $0.date >= daysAgo(10) }
            guard r.count >= 2 else { return nil }
            let last2 = Array(r.prefix(2))
            let eB = out.effortBaseline ?? 6, pB = out.performanceBaseline ?? 7
            return last2.allSatisfy { Double($0.effort!) >= eB + 1.5 && Double($0.performance!) <= pB - 1.5 } ? last2 : nil
        }
        func nums(_ xs: [SessionSignal], _ f: (SessionSignal) -> Int?) -> String { xs.compactMap(f).map(String.init).joined(separator: " and ") }
        let cyc = sessions.filter { $0.sport == .cycling }, str = sessions.filter { $0.sport == .strength }
        let baseText = out.effortBaseline != nil ? String(format: "your 4-week baseline (effort %.1f, performance %.1f)", out.effortBaseline!, out.performanceBaseline!) : "the default reference (effort 6, performance 7) — no 4-week baseline yet"
        if let s = effortUpPerformanceDown(cyc) {
            out.fatigue.append(FatigueFlag(id: "cyc-effort-perf", scope: .cycling, text: "Your last two rides felt harder (effort \(nums(s, { $0.effort }))) while going worse (performance \(nums(s, { $0.performance }))) than \(baseText)."))
        }
        if let s = effortUpPerformanceDown(str) {
            out.fatigue.append(FatigueFlag(id: "str-effort-perf", scope: .strength, text: "Your last two strength sessions felt harder (effort \(nums(s, { $0.effort }))) while going worse (performance \(nums(s, { $0.performance }))) than \(baseText)."))
        }
        func lastTwoVeryHard(_ list: [SessionSignal]) -> [SessionSignal]? {
            let r = list.filter { $0.effort != nil && $0.date >= daysAgo(10) }
            guard r.count >= 2 else { return nil }
            let last2 = Array(r.prefix(2))
            return last2.allSatisfy { $0.effort! >= 9 } ? last2 : nil
        }
        if !out.fatigue.contains(where: { $0.scope == .cycling }), let s = lastTwoVeryHard(cyc) {
            out.fatigue.append(FatigueFlag(id: "cyc-high-effort", scope: .cycling, text: "Your last two rides were rated near-maximal (effort \(nums(s, { $0.effort })) of 10)."))
        }
        if !out.fatigue.contains(where: { $0.scope == .strength }), let s = lastTwoVeryHard(str) {
            out.fatigue.append(FatigueFlag(id: "str-high-effort", scope: .strength, text: "Your last two strength sessions were rated near-maximal (RPE \(nums(s, { $0.effort })) of 10)."))
        }
        let hard7 = sessions.filter { ($0.effort ?? 0) >= 9 && $0.date >= recent7 }
        if hard7.count >= 3, !(out.cyclingFatigue && out.strengthFatigue) {
            out.fatigue.append(FatigueFlag(id: "all-high-effort", scope: .combined, text: "\(hard7.count) sessions in the last 7 days (cycling and lifting together) were rated 9 or 10 out of 10."))
        }
        // rides cut short twice in a row (against the planned minutes of that day)
        let matched = cyc.filter { $0.plannedMinutes != nil && $0.date >= daysAgo(10) }
        if matched.count >= 2, matched.prefix(2).allSatisfy({ Double($0.minutes) < 0.8 * Double($0.plannedMinutes!) }), !out.cyclingFatigue {
            let m = Array(matched.prefix(2))
            let cut: String = m.map { x -> String in "\(x.minutes) of \(x.plannedMinutes ?? 0) min" }.joined(separator: ", ")
            out.fatigue.append(FatigueFlag(id: "cyc-short", scope: .cycling, text: "Your last two rides were cut short (\(cut))."))
        }
        // strength performance below the personal baseline (estimated 1RM, Epley) on two sessions in a row
        var declining: [String] = []
        var improving: [String] = []
        let detailed = input.strength.filter { $0.isDetailed && !$0.inProgress && $0.date <= now && $0.date >= daysAgo(AdaptiveRules.baselineDays + 7) }.sorted { $0.date > $1.date }
        var names: [String: String] = [:]
        var series: [String: [Double]] = [:]
        for s in detailed { for e in s.exercises ?? [] {
            let best = e.doneSets.compactMap { st -> Double? in guard !st.bodyweight, let w = st.weightKg, w > 0 else { return nil }; return e1RM(weightKg: w, reps: st.reps) }.max()
            if let b = best { series[e.exerciseId, default: []].append(b); names[e.exerciseId] = e.name }
        } }
        for (id, v) in series.sorted(by: { $0.key < $1.key }) where v.count >= 4 {
            let rest = Array(v.dropFirst(2)).sorted()
            let median = rest[rest.count / 2]
            if v[0] < median * 0.95 && v[1] < median * 0.95 { declining.append("\(names[id] ?? id) (estimated 1RM \(Int(v[1].rounded())) and \(Int(v[0].rounded())) kg vs \(Int(median.rounded())) kg baseline)") }
            if v[0] > median * 1.025 && v[1] > median * 1.025 { improving.append("\(names[id] ?? id) (estimated 1RM \(Int(v[1].rounded())) and \(Int(v[0].rounded())) kg vs \(Int(median.rounded())) kg baseline)") }
        }
        if !declining.isEmpty, !out.strengthFatigue {
            out.fatigue.append(FatigueFlag(id: "str-decline", scope: .strength, text: "Strength below your 4-week baseline on two sessions in a row: \(declining.joined(separator: "; "))."))
        }
        if let r = out.acwr, r > 1.5, out.chronicWeeklyLoad != nil {
            let ratio = String(format: "%.1f", r)
            // independent review F-15: the acute:chronic ratio is contested (Impellizzeri et al. 2020) — shown as information,
            // never a trigger for automatic reductions
            out.findings.append("This week's combined load (\(Int(out.acuteLoad ?? 0)) AU) is \(ratio) × your 4-week weekly average (\(Int(out.chronicWeeklyLoad ?? 0)) AU). Shown for information; the coach does not change your plan on this number alone.")
        }

        // --- missed sessions (planned, past, no ride / log of that sport on the day). Never crammed in later.
        func missedIn(_ from: Date, _ to: Date) -> (planned: Int, missed: [Workout]) {
            let ws = input.plan.filter { ($0.kind.isRide || $0.kind == .strength) && $0.date >= from && $0.date < to }
            let miss = ws.filter { w in
                guard !w.done else { return false }
                if w.kind.isRide { return !input.rides.contains { !$0.demo && cal.isDate($0.start, inSameDayAs: w.date) } }
                return !input.strength.contains { cal.isDate($0.date, inSameDayAs: w.date) }
            }
            return (ws.count, miss)
        }
        let lastWeek = missedIn(daysAgo(7), today), weekBefore = missedIn(daysAgo(14), daysAgo(7))
        out.missed = lastWeek.missed.sorted { $0.date < $1.date }
        out.repeatedMisses = lastWeek.planned >= 2 && weekBefore.planned >= 2 && lastWeek.missed.count * 2 >= lastWeek.planned && weekBefore.missed.count * 2 >= weekBefore.planned

        // --- pain (audit G-06): a concerning report holds progression in its area until the rider confirms it is gone,
        // or until at least 7 days have passed AND the next 2 sessions that loaded the same area the same way (the same
        // activity: a ride for a riding report, a lift with that movement for a lifting report) were rated pain-free.
        // Pain-free check-ins of other activities (two rides after knee pain from squats) clear nothing.
        struct Exposure { var sport: SessionSignal.Sport; var date: Date; var pain: PainLevel; var area: PainArea?; var patterns: Set<MovementPattern> }
        var exposures: [Exposure] = []
        for r in input.rides where !r.demo && r.start <= now { if let c = r.checkIn { exposures.append(Exposure(sport: .cycling, date: r.start, pain: c.pain, area: c.painArea, patterns: [])) } }
        for x in input.strength where !x.inProgress && x.date <= now {
            guard let c = x.checkIn else { continue }
            exposures.append(Exposure(sport: .strength, date: x.date, pain: c.pain, area: c.painArea, patterns: Self.loadedPatterns(x)))
        }
        exposures.sort { $0.date > $1.date }
        var areas: [PainArea] = []
        for (i, s) in exposures.enumerated() where s.pain == .concerning {
            let area = s.area ?? .other
            guard !areas.contains(area) else { continue }
            if input.painClearances.contains(where: { $0.area == area && $0.at > s.date }) { continue }
            let same = exposures.prefix(i).reversed().filter { x in      // newer ones, oldest first
                // same activity only (pain-free rides never clear lifting pain, G-06). Independent review F-12: the
                // exercises that load the area are left out while it is held, so any pain-free LIFTING session after the
                // minimum hold counts (rated for that area) — otherwise the hold could never clear on its own
                return x.sport == s.sport
            }
            // owner (27 Oct): concerning pain may indicate injury, so it is NEVER released automatically. After the minimum
            // hold, two pain-free sessions of the same activity only make the coach ASK the rider (Coach adjustments).
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: s.date), to: today).day ?? 0
            let held = days < AdaptiveRules.painMinHoldDays
            let reviewDue = !held && same.count >= AdaptiveRules.painClearCheckIns && same.suffix(AdaptiveRules.painClearCheckIns).allSatisfy { $0.pain == .noPain || $0.pain == .soreness }
            areas.append(area)
            if reviewDue { out.painReviewDue.append(area) }
            let repeated = exposures.filter { $0.pain == .concerning && ($0.area ?? .other) == area && $0.date >= daysAgo(14) }.count >= 2
            // review N-06: "persistent" = it came back within 14 days, or it is older than 14 days and the rider has had
            // no two pain-free sessions of that activity since (still ongoing) — not merely an old report
            if repeated || (days > 14 && !reviewDue) { out.painPersistent.append(area) }
        }
        out.painAreas = areas
        // non-specific discomfort: holds progression in that area until a LATER session of the same activity is rated
        // without discomfort or pain (one session); never leaves exercises out
        var disc: [PainArea] = []
        for (i, s) in exposures.enumerated() where s.pain == .discomfort {
            let area = s.area ?? .other
            guard !disc.contains(area), !areas.contains(area), s.date >= daysAgo(14) else { continue }
            let later = exposures.prefix(i).filter { $0.sport == s.sport }
            if !later.contains(where: { $0.pain == .noPain || $0.pain == .soreness }) { disc.append(area) }
        }
        out.discomfortAreas = disc

        // --- cycling improving: the last two rated rides went well at a moderate effort and were completed
        let cycBase = Array(cyc.filter { $0.hasCheckIn }.dropFirst(2)).filter { $0.date >= daysAgo(AdaptiveRules.baselineDays + 7) }
        let cycPerfBase: Double? = cycBase.count >= 3 ? Double(cycBase.compactMap { $0.performance }.reduce(0, +)) / Double(cycBase.count) : nil
        let cycEffortBase: Double? = cycBase.count >= 3 ? Double(cycBase.compactMap { $0.effort }.reduce(0, +)) / Double(cycBase.count) : nil
        let ratedRides = cyc.filter { $0.hasCheckIn && $0.date >= daysAgo(14) }
        if ratedRides.count >= 2 {
            let l2 = Array(ratedRides.prefix(2))
            let ok = l2.allSatisfy { x in
                let completed = x.plannedMinutes.map { pm in Double(x.minutes) >= 0.9 * Double(pm) } ?? true
                // audit G-15: "better than usual", not "as usual" — against the rider's own 4-week baseline when it
                // exists (performance ≥ baseline + 1 and effort ≤ baseline − 1), else a clearly good rating (8 / 5)
                // independent review F-24: the rider's CYCLING baseline (rides only), not one pooled with lifts
                let pNeed = cycPerfBase.map { max(7.0, $0 + 1) } ?? 8, eMax = cycEffortBase.map { min(6.0, $0 - 1) } ?? 5
                return Double(x.performance ?? 0) >= pNeed && Double(x.effort ?? 10) <= eMax && x.pain != .concerning && completed
            }
            if ok {
                out.cyclingImproving = true
                let ref = cycPerfBase != nil ? String(format: "better than your 4-week riding baseline (performance %.1f, effort %.1f)", cycPerfBase!, cycEffortBase ?? 0) : "clearly good ratings (no 4-week riding baseline yet)"
                out.cyclingImprovingText = "Your last two rides went well (performance \(nums(l2, { $0.performance }))) at a moderate effort (\(nums(l2, { $0.effort })) of 10), \(ref), and were completed."
            }
        }

        // --- findings in plain words, with the numbers
        if let a = out.acuteLoad {
            if let c = out.chronicWeeklyLoad { let ratio = String(format: "%.2f", a / c); out.findings.append("Combined load (session effort × minutes): \(Int(a)) AU in the last 7 completed days; your weekly average before that is \(Int(c)) AU (ratio \(ratio)).") }
            else { out.findings.append("Combined load (session effort × minutes): \(Int(a)) AU in the last 7 completed days. A weekly baseline needs 4 weeks of rated sessions.") }
        }
        out.findings += out.fatigue.map { $0.text }
        if !improving.isEmpty { out.findings.append("Above your 4-week baseline: \(improving.joined(separator: "; ")).") }
        if let t = out.cyclingImprovingText { out.findings.append(t) }
        if !out.missed.isEmpty {
            let list: String = out.missed.map { w -> String in AdaptationExplainer.day(w.date) + " " + w.displayTitle.lowercased() }.joined(separator: ", ")
            let tail = out.missed.count >= 2 ? " Missed sessions are not crammed into the coming days and nothing is increased until you are back on track." : ""
            out.findings.append("\(out.missed.count) planned session\(out.missed.count == 1 ? "" : "s") missed in the last 7 days (\(list)).\(tail)")
        }
        if out.unusableRides > 0 { out.findings.append("\(out.unusableRides) recent ride\(out.unusableRides == 1 ? "" : "s") had no check-in, no heart rate and no verified power\(out.unverifiedPowerOnly > 0 ? " (unverified power is not used to judge intensity)" : "") — not used for decisions.") }
        return out
    }

    /// Movement patterns a strength session actually loaded: its logged exercises, else (quick log) its focus.
    static func loadedPatterns(_ x: StrengthSession) -> Set<MovementPattern> {
        let logged = Set((x.exercises ?? []).filter { !$0.doneSets.isEmpty }.map { $0.pattern })
        if !logged.isEmpty { return logged }
        if x.isDetailed { return [] }
        switch x.focus {
        case .fullBody: return [.squat, .hinge, .push, .pull, .core]
        case .lower, .legs: return [.squat, .hinge, .singleLeg]
        case .upper: return [.push, .pull]
        case .push: return [.push]
        case .pull: return [.pull]
        case .custom: return []
        }
    }

    /// 1…5 from the rider's heart-rate zones.
    static func hrZone(_ hr: Int, profile p: RiderProfile) -> Int {
        for (i, z) in p.hrZones.enumerated() where hr < (z.hi ?? Int.max) { return i + 1 }
        return 5
    }
}

// MARK: - Layer 3: explanations (template text — "Coach (rules-based)")
/// Hook for an optional explanation layer (for example a language model rewriting the "why" in other words). NOT
/// integrated in this build: only `RulesExplanationProvider` exists, and every text is labelled "Coach (rules-based)".
protocol CoachExplanationProvider {
    var label: String { get }
    func explain(_ adjustment: PlanAdjustment) -> String
}
struct RulesExplanationProvider: CoachExplanationProvider {
    let label = AdaptationExplainer.label
    func explain(_ adjustment: PlanAdjustment) -> String { adjustment.why }
}

enum AdaptationExplainer {
    static let label = "Coach (rules-based)"
    static let disclaimer = "Rules-based coach: deterministic rules on your logged sessions and check-ins; no AI model is used. Effort and performance scores alone cannot diagnose recovery, overtraining or injury."
    static func day(_ d: Date) -> String { let f = DateFormatter(); f.dateFormat = "EEE d MMM"; return f.string(from: d) }
    static func kg(_ v: Double, _ u: AppSettings.Units) -> String { WeightFmt.text(v, u) }
    static func painAdvice(_ areas: [PainArea], persistent: [PainArea] = []) -> String? {
        guard !areas.isEmpty else { return nil }
        let names = areas.map { $0.title.lowercased() }.joined(separator: ", ")
        var t = "You reported concerning pain (\(names)). Coach-built sessions leave out exercises that load that area; in your own routines those exercises stay but are not progressed — swap or skip them if they hurt. Nothing there is progressed until you confirm it is fine (Coach adjustments › “It's fine now”) — the coach never releases it on its own. After at least a week, if your last two sessions were pain-free, the coach will ask you. Stop whatever hurts. If the pain is sharp, swollen, keeps coming back or gets worse, see a doctor or physiotherapist — the app cannot tell what is causing it."
        if !persistent.isEmpty { t += " It has lasted more than two weeks or come back (\(persistent.map { $0.title.lowercased() }.joined(separator: ", "))): have it assessed before loading it again." }
        return t
    }
    static func discomfortAdvice(_ areas: [PainArea]) -> String {
        let names = areas.map { $0.title.lowercased() }.joined(separator: ", ")
        return "Unusual discomfort (\(names)): nothing is left out, but that area is not progressed until a later session is rated without it. If it turns into pain, report it as pain."
    }
    static func lowConfidenceRequest(_ a: TrainingAnalysis) -> String {
        if a.unusableRides > 0 { return "Not enough reliable data to change your plan: \(a.unusableRides) recent ride\(a.unusableRides == 1 ? "" : "s") had no check-in, no heart rate and no verified power. Rate each session after you finish (performance, effort, pain — 10 seconds) so the coach can adapt. Your plan stays as it is." }
        return "Not enough data yet to change your plan (fewer than 2 rated sessions in 2 weeks). Rate each session after you finish so the coach can adapt. Your plan stays as it is."
    }
}

// MARK: - The engine: analysis → bounded decisions → automatic changes vs proposals
enum AdaptationEngine {
    static func run(_ input: AdaptationInput) -> AdaptationResult {
        let cal = input.calendar, now = input.now
        let today = cal.startOfDay(for: now)
        let a = TrainingAnalyzer.analyze(input)
        let fatigueEnd = cal.date(byAdding: .day, value: AdaptiveRules.fatigueHorizonDays, to: today)!
        let progressEnd = cal.date(byAdding: .day, value: AdaptiveRules.progressionHorizonDays, to: today)!
        // future open sessions as ORIGINALLY planned (the engine always decides from the original, so its output is
        // the complete set of changes wanted now — re-running it never stacks changes)
        let future = input.plan.map { $0.restoredOriginal }
            .filter { !$0.done && !$0.skipped && cal.startOfDay(for: $0.date) >= today }
            .sorted { ($0.date, $0.sequence) < ($1.date, $1.sequence) }
        func auto(_ w: Workout) -> Bool { AdaptiveRules.autoEligible(w, now: now, calendar: cal) }
        func entries(_ w: Workout) -> [ExerciseEntry] { input.originalEntries[w.id] ?? w.plannedEntries ?? [] }
        func make(_ w: Workout, _ c: PlanAdjustment.Change, _ cat: PlanAdjustment.Category, _ summary: String, _ why: String) -> PlanAdjustment {
            PlanAdjustment(workoutId: w.id, change: c, category: cat, summary: summary, why: why, createdAt: now)
        }
        var autoAdj: [PlanAdjustment] = []
        var proposals: [AdaptiveProposal] = []
        var progressions: [PlanAdjustment] = []

        // ---------- B: saved exercises that need equipment the rider does not own (or excluded) → approval only
        var seenReplace: Set<String> = []
        for w in future where w.kind == .strength && w.date < progressEnd && AdaptiveRules.approvalEligible(w, now: now, calendar: cal) {
            for e in entries(w) where !seenReplace.contains(e.exerciseId) {
                guard let ex = input.catalogue.first(where: { $0.id == e.exerciseId }), !input.equipment.canDo(ex) else { continue }
                seenReplace.insert(e.exerciseId)
                let needs = ex.equipment.filter { $0 != "bodyweight" }.joined(separator: ", ")
                let why0 = input.equipment.excluded.contains(ex.id) ? "you marked \(ex.name) as an exercise you cannot do" : "\(ex.name) needs \(needs), which is not in your equipment list"
                if let sub = StrengthProgrammer.substitute(for: ex, input: input, avoiding: Set(entries(w).map { $0.exerciseId })) {
                    let adj = make(w, .replace(exerciseId: ex.id, withId: sub.id, name: sub.name, pattern: sub.pattern), .substitution, "\(ex.name) → \(sub.name)", "On \(AdaptationExplainer.day(w.date)) \(why0). \(sub.name) trains the same movement (\(sub.pattern.title.lowercased())) with equipment you have. Your saved routine is never changed; this replaces it in that session only, and only if you accept.")
                    proposals.append(AdaptiveProposal(id: "replace|\(adj.key)", reason: .replaceExercise, text: "Replace \(ex.name) with \(sub.name) on \(AdaptationExplainer.day(w.date))?", why: adj.why, adjustments: [adj]))
                } else {
                    proposals.append(AdaptiveProposal(id: "replace|\(w.id.uuidString)|\(ex.id)", reason: .replaceExercise, text: "\(ex.name) on \(AdaptationExplainer.day(w.date)): no substitute fits your equipment", why: "On \(AdaptationExplainer.day(w.date)) \(why0), and no exercise of the same movement fits your equipment and exclusions. Change the routine yourself, or add the equipment in Profile › Training profile › Equipment."))
                }
            }
        }
        // ---------- adding / removing weekly sessions → approval only (repeated misses)
        if a.repeatedMisses {
            let splitHint = input.profile.strengthSplit == .pushPullLegs ? " An Upper / Lower or Full Body split needs fewer days for the same work." : ""
            proposals.append(AdaptiveProposal(id: "sessions|\(isoWeek(today, cal))", reason: .sessionCount, text: "Plan one session fewer per week?", why: "In each of the last two weeks half or more of the planned sessions were missed (\(a.missed.count) in the last 7 days). A plan you can keep beats carrying the same one again. The coach never removes a session on its own — change the number of sessions or your days in Profile › Training profile.\(splitHint)"))
        }

        // ---------- low confidence: keep the plan as it is (including changes already in force) and ask for feedback
        let lowConfidence = a.usableRecent < AdaptiveRules.minUsableSessions
        var feedback: String? = nil
        if lowConfidence {
            feedback = AdaptationExplainer.lowConfidenceRequest(a)
            let keep = input.active.filter { adj in future.contains { $0.id == adj.workoutId } }
            return finish(input, a, keep, proposals, confidence: .low, feedback: feedback)
        }

        // ---------- fatigue (each flag already needs 2 consistent sessions): reduce or ease FUTURE sessions only
        if a.anyFatigue {
            let flags = a.fatigue.map { $0.text }.joined(separator: " ")
            // cycling: the next hard ride within 7 days — one zone step easier, or easy (recovery emphasis) when severe
            if let r = future.first(where: { $0.kind.isRide && $0.kind.zone >= 3 && $0.date < fatigueEnd }) {
                let to: WorkoutKind = a.severeFatigue ? .endurance : (AdaptiveRules.stepDown(r.kind) ?? .endurance)
                let cause = a.cyclingFatigue ? "" : a.strengthFatigue ? " Your lifting fatigue counts here too: legs and recovery are shared between both sports." : ""
                let becomes: String
                if a.severeFatigue { becomes = "an easy endurance ride (Zone 2) — recovery emphasis" } else { becomes = "\(to.title.lowercased()) (Zone \(to.zone)), one zone step easier" }
                let why = "\(flags)\(cause) So \(AdaptationExplainer.day(r.date))'s \(r.kind.title.lowercased()) (Zone \(r.kind.zone)) becomes \(becomes), same day, same \(r.minutes) min."
                let adj = make(r, .kind(to: to), a.severeFatigue ? .recovery : .reduction, "\(r.kind.title) → \(to.title) (same \(r.minutes) min)", why)
                if auto(r) { autoAdj.append(adj) }
                else if r.fixed, AdaptiveRules.approvalEligible(r, now: now, calendar: cal) {
                    proposals.append(AdaptiveProposal(id: "fixed|\(adj.key)", reason: .fixedDay, text: "Ease your fixed \(AdaptationExplainer.day(r.date)) \(r.kind.title.lowercased()) to \(to.title.lowercased())?", why: why + " It is a fixed day, so the coach only changes it if you accept.", adjustments: [adj]))
                }
            }
            // severe: the next steady ride 10 % shorter
            if a.severeFatigue, let e = future.first(where: { ($0.kind == .endurance || $0.kind == .long) && $0.date < fatigueEnd && auto($0) }) {
                let d = AdaptiveRules.roundTo5(Double(e.minutes) * AdaptiveRules.durationFraction)
                if e.minutes - d >= 20 { autoAdj.append(make(e, .minutes(delta: -d), .reduction, "\(e.kind.title): \(Fmt.duration(minutes: e.minutes)) → \(Fmt.duration(minutes: e.minutes - d))", "\(flags) Two or more fatigue signals at once, so \(AdaptationExplainer.day(e.date))'s \(e.kind.title.lowercased()) is 10 % shorter (\(d) min less).")) }
            }
            // strength: the next session within 7 days — one set fewer (all exercises when lifting or combined fatigue,
            // leg exercises when the fatigue comes from cycling)
            // the next session within 7 days where a set can still come off (a session the planner already lightened
            // for a key ride may have nothing left to cut; then the following one carries the reduction)
            let all = a.strengthFatigue || a.combinedFatigue
            func cuttable(_ w: Workout) -> [ExerciseEntry] { entries(w).filter { $0.sets.count >= 3 && (all || AdaptiveRules.legPatterns.contains($0.pattern)) } }
            // independent review F-25: a planner-built session that is already a deload for this fatigue is not cut again
            let candidates = future.filter { $0.kind == .strength && $0.date < fatigueEnd && auto($0) && !($0.rationale?.deload ?? false) }
            if let s = candidates.first(where: { !cuttable($0).isEmpty }) ?? candidates.first {
                let es = cuttable(s)
                let cause = all ? "" : " Your legs carry the cycling fatigue, so the leg exercises lose a set; upper-body work stays as planned."
                for e in es.prefix(4) {
                    autoAdj.append(make(s, .sets(exerciseId: e.exerciseId, delta: -1), .reduction, "\(e.name): \(e.sets.count) → \(e.sets.count - 1) sets", "\(flags)\(cause) One set fewer of \(e.name) on \(AdaptationExplainer.day(s.date)) (\(e.sets.count) → \(e.sets.count - 1)); weights and reps stay. No progression until the signals ease."))
                }
                if es.isEmpty, !entries(s).isEmpty {
                    feedback = "\(flags) Your next strength sessions are already at their minimum (2 sets at RPE 6 or less for the legs), so no further sets come off — the easier ride carries the change."
                }
                if es.isEmpty, entries(s).isEmpty, (all || (s.strengthFocus?.loadsLegs ?? false)), s.minutes >= 30 {
                    let d = AdaptiveRules.roundTo5(Double(s.minutes) * AdaptiveRules.durationFraction)
                    autoAdj.append(make(s, .minutes(delta: -d), .reduction, "\(s.displayTitle): \(Fmt.duration(minutes: s.minutes)) → \(Fmt.duration(minutes: s.minutes - d))", "\(flags)\(cause) This session has no exercise list, so it is 10 % shorter instead (\(d) min less)."))
                }
            }
        }

        // ---------- F-15: a large jump in load is never an automatic trigger (the ratio is contested), but the rider is
        // offered an easier next hard ride — their decision
        if let ratio = a.acwr, ratio > 1.5, a.chronicWeeklyLoad != nil, let r = future.first(where: { $0.kind.isRide && $0.kind.zone >= 3 && $0.date < fatigueEnd }), !autoAdj.contains(where: { $0.workoutId == r.id }) {
            let to: WorkoutKind = AdaptiveRules.stepDown(r.kind) ?? .endurance
            let why = String(format: "This week's combined load is %.1f × your recent weekly average. A sudden jump in load is a common reason to ease off, but this number alone is not reliable evidence of fatigue, so the coach only offers the change.", ratio)
            let adj = make(r, .kind(to: to), .reduction, "\(r.kind.title) → \(to.title) (load jump)", why)
            proposals.append(AdaptiveProposal(id: "loadjump|\(adj.key)", reason: .majorLoad, text: "Ease \(AdaptationExplainer.day(r.date))'s \(r.kind.title.lowercased()) to \(to.title.lowercased()) after this week's jump in load?", why: why, adjustments: [adj]))
        }

        // ---------- independent review F-26: concerning pain reported on a ride → the next hard ride within 7 days is eased
        // (one zone step, same minutes); fixed days only on approval. Progression is held by painBlocksCycling below.
        if a.painBlocksCycling, let r = future.first(where: { $0.kind.isRide && $0.kind.zone >= 3 && $0.date < fatigueEnd }), !autoAdj.contains(where: { $0.workoutId == r.id }) {
            let to: WorkoutKind = AdaptiveRules.stepDown(r.kind) ?? .endurance
            let why = "You reported concerning pain (\(a.painAreas.filter { $0.affectsCycling }.map { $0.title.lowercased() }.joined(separator: ", "))) that riding also loads. So \(AdaptationExplainer.day(r.date))'s \(r.kind.title.lowercased()) becomes \(to.title.lowercased()), same \(r.minutes) min, until the area is pain-free again. If the pain persists or is sharp, get it checked."
            let adj = make(r, .kind(to: to), .reduction, "\(r.kind.title) → \(to.title) (pain reported)", why)
            if auto(r) { autoAdj.append(adj) }
            else if r.fixed, AdaptiveRules.approvalEligible(r, now: now, calendar: cal) {
                proposals.append(AdaptiveProposal(id: "fixed|\(adj.key)", reason: .fixedDay, text: "Ease your fixed \(AdaptationExplainer.day(r.date)) \(r.kind.title.lowercased()) because of the pain you reported?", why: why + " It is a fixed day, so the coach only changes it if you accept.", adjustments: [adj]))
            }
        }

        // ---------- progression: only without fatigue, without repeated misses, never where pain was reported
        if !a.anyFatigue && !a.adherenceBlock {
            var seen: Set<String> = []
            // review N-04: no load or rep progression of the rider's routines until the health check allows harder training
            for s in future where s.kind == .strength && s.date < progressEnd && auto(s) && input.profile.readiness.vigorousAllowed {
                for e in entries(s) where !seen.contains(e.exerciseId) {
                    seen.insert(e.exerciseId)                         // only the NEXT session with that exercise
                    if a.painBlocks(e.pattern) { continue }
                    if let adj = strengthDecision(e, session: s, input: input) {
                        if adj.category == .progression { progressions.append(adj) } else { autoAdj.append(adj) }
                    }
                }
            }
            let unverifiedNote = input.rides.contains(where: { $0.powerVerified != true && $0.avgPower != nil }) ? "; unverified power is not used" : ""
            if a.cyclingImproving, !a.painBlocksCycling, let text = a.cyclingImprovingText {
                // M-01 / M-02: no added intervals without a cleared health check or while returning from a break
                let rideReturn = ReturnPhase.detect(dates: input.rides.filter { !$0.demo }.map { $0.start }, now: now, calendar: cal)
                let intensityOK = input.profile.readiness.vigorousAllowed && !(rideReturn?.active ?? false)
                if intensityOK, let r = future.first(where: { ($0.kind == .threshold || $0.kind == .vo2) && $0.date < progressEnd && auto($0) }),
                   let reps = r.effectiveIntervalReps, AdaptiveRules.intervalsFit(kind: r.kind, reps: reps + 1, minutes: r.minutes) {
                    progressions.append(make(r, .intervalReps(delta: 1), .progression, "\(r.kind.title): \(reps) → \(reps + 1) × \(r.kind.intervalWorkMinutes) min", "\(text) So \(AdaptationExplainer.day(r.date))'s \(r.kind.title.lowercased()) gets one more interval (\(reps) → \(reps + 1) × \(r.kind.intervalWorkMinutes) min) inside the same \(r.minutes) min. Judged from your effort and performance ratings\(unverifiedNote)."))
                } else if let e = future.first(where: { ($0.kind == .endurance || $0.kind == .long) && $0.date < progressEnd && auto($0) }) {
                    let d = AdaptiveRules.roundTo5(Double(e.minutes) * AdaptiveRules.durationFraction)
                    let adj = make(e, .minutes(delta: d), .progression, "\(e.kind.title): \(Fmt.duration(minutes: e.minutes)) → \(Fmt.duration(minutes: e.minutes + d))", "\(text) So \(AdaptationExplainer.day(e.date))'s \(e.kind.title.lowercased()) is 10 % longer (\(d) min more).")
                    let (weekMin, budget) = rideWeek(e, input)
                    let dayLimit = dayMinutes(e, input) ?? e.minutes
                    if weekMin + d <= budget, e.minutes + d <= dayLimit { progressions.append(adj) }
                    else {
                        let over: String
                        if weekMin + d > budget { over = "weekly cycling budget (\(Fmt.duration(minutes: weekMin)) planned of \(Fmt.duration(minutes: budget)))" } else { over = "time for that day (\(Fmt.duration(minutes: dayLimit)))" }
                        var b = adj; b.why += " That goes over your \(over), so it needs your OK."
                        proposals.append(AdaptiveProposal(id: "budget|\(b.key)", reason: .budget, text: "Lengthen \(AdaptationExplainer.day(e.date))'s \(e.kind.title.lowercased()) by \(d) min?", why: b.why, adjustments: [b]))
                    }
                }
            }
            // lifting budget: an extra set adds ~2.5 min; over the weekly lifting budget → approval
            var kept: [PlanAdjustment] = []
            for adj in progressions {
                if case .sets(_, let d) = adj.change, d > 0, let w = future.first(where: { $0.id == adj.workoutId }) {
                    let (wk, budget) = liftWeek(w, input)
                    if budget > 0, wk + 3 > budget {
                        proposals.append(AdaptiveProposal(id: "budget|\(adj.key)", reason: .budget, text: "Add a set (\(adj.summary))?", why: adj.why + " It would take the week to \(Fmt.duration(minutes: wk + 3)) of lifting against your \(Fmt.duration(minutes: budget)) budget, so it needs your OK.", adjustments: [adj]))
                        continue
                    }
                }
                kept.append(adj)
            }
            progressions = kept
            // major load increase: more than 10 % of a week's planned load → approval for that week's progressions
            var byWeek: [Date: [PlanAdjustment]] = [:]
            for adj in progressions { if let w = future.first(where: { $0.id == adj.workoutId }) { byWeek[monday(w.date, cal), default: []].append(adj) } }
            for (m, list) in byWeek.sorted(by: { $0.key < $1.key }) {
                let end = cal.date(byAdding: .day, value: 7, to: m)!
                let weekLoad = input.plan.map { $0.restoredOriginal }.filter { $0.date >= m && $0.date < end }.reduce(0) { $0 + AdaptiveRules.plannedLoad($1) }
                let added = list.reduce(0.0) { $0 + loadIncrease($1, future) }
                if weekLoad > 0, added > AdaptiveRules.majorLoadFraction * weekLoad {
                    let pid = "major|" + list.map { $0.key }.sorted().joined(separator: ",")
                    let pct = Int((added / weekLoad * 100).rounded())
                    let what = list.map { $0.summary }.joined(separator: "; ")
                    let why = "Together they add about \(pct) % to that week's planned load (\(Int(added)) of \(Int(weekLoad)) AU). Increases above 10 % need your OK. \(what)."
                    proposals.append(AdaptiveProposal(id: pid, reason: .majorLoad, text: "Apply \(list.count) progression\(list.count == 1 ? "" : "s") for the week of \(AdaptationExplainer.day(m))?", why: why, adjustments: list))
                } else { autoAdj += list }
            }
        }

        let confidence: AdaptationSummary.Confidence = a.usableRecent >= 4 && a.sessions.filter({ $0.hasCheckIn }).count >= 2 ? .high : .medium
        if a.adherenceBlock { feedback = "Sessions were missed this week, so nothing is increased. If the days do not suit you, change them in Plan › Days." }
        return finish(input, a, autoAdj, proposals, confidence: confidence, feedback: feedback)
    }

    /// Splits approved / dismissed, drops proposals the rider declined, writes the summary.
    private static func finish(_ input: AdaptationInput, _ a: TrainingAnalysis, _ adj: [PlanAdjustment], _ props: [AdaptiveProposal], confidence: AdaptationSummary.Confidence, feedback: String?) -> AdaptationResult {
        var out = adj.filter { !input.dismissed.contains($0.key) }
        var pending: [AdaptiveProposal] = []
        for p in props {
            if !p.adjustments.isEmpty, p.adjustments.allSatisfy({ input.approved.contains($0.key) }) { out += p.adjustments.filter { !input.dismissed.contains($0.key) } }
            else if !input.dismissed.contains(p.id), !pending.contains(where: { $0.id == p.id }) { pending.append(p) }
        }
        // one change per key (the first decision wins)
        var seen: Set<String> = []
        out = out.filter { seen.insert($0.key).inserted }
        let s = AdaptationSummary(at: input.now, confidence: confidence, findings: a.findings, feedbackRequest: feedback, painAdvice: AdaptationExplainer.painAdvice(a.painAreas, persistent: a.painPersistent), acuteLoad: a.acuteLoad.map { Int($0) }, chronicLoad: a.chronicWeeklyLoad.map { Int($0) })
        return AdaptationResult(adjustments: out, proposals: pending, summary: s, analysis: a)
    }

    /// Strength progression / hold for the next session of one exercise (brief D rules; equipment B).
    static func strengthDecision(_ e: ExerciseEntry, session s: Workout, input: AdaptationInput) -> PlanAdjustment? {
        let known = input.catalogue.first { $0.id == e.exerciseId }
        if input.equipment.excluded.contains(e.exerciseId) { return nil }
        // quality release: loads of planner-built sessions already follow double progression from the logs (no stacking)
        if s.rationale?.exercise(e.exerciseId) != nil { return nil }
        // an exercise the rider cannot do with their equipment is never progressed (a replacement is proposed instead)
        if let k = known, !input.equipment.canDo(k) { return nil }
        let hist: [(StrengthSession, ExerciseEntry)] = input.strength.filter { !$0.inProgress && $0.date <= input.now }.sorted { $0.date > $1.date }
            .compactMap { ses in ses.exercises?.first(where: { $0.exerciseId == e.exerciseId && !$0.doneSets.isEmpty }).map { (ses, $0) } }
        guard hist.count >= AdaptiveRules.progressionSessions else { return nil }
        let last2 = Array(hist.prefix(AdaptiveRules.progressionSessions))
        let template = s.templateId.flatMap { tid in input.templates.first { $0.id == tid } }
        let target = template?.entries.first(where: { $0.exerciseId == e.exerciseId })?.sets ?? e.sets
        guard !target.isEmpty, !e.sets.isEmpty else { return nil }
        let plannedReps = target.map { $0.reps }
        // audit G-12: a session logged from workout mode carries the sets as planned FOR THAT SESSION (coach changes
        // included, done or not); it is complete when every one of those is done at the routine's reps. A quick log
        // without that record is judged against the routine itself.
        func complete(_ ses: StrengthSession, _ x: ExerciseEntry) -> Bool {
            let r = x.doneSets.map { $0.reps }
            let fromWorkout = ses.startedAt != nil && ses.workoutId != nil && !x.sets.isEmpty
            // independent review F-21: a log linked to its planned session is also judged against that session's own
            // planned sets (coach changes included), however it was logged
            let linkedPlan = ses.workoutId.flatMap { id in input.plan.first { $0.id == id } }.flatMap { $0.plannedEntries?.first { $0.exerciseId == x.exerciseId } }
            let need = fromWorkout ? min(plannedReps.count, x.sets.count) : (linkedPlan.map { min(plannedReps.count, $0.sets.count) } ?? plannedReps.count)
            return r.count >= need && x.doneSets.count == (fromWorkout ? x.sets.count : x.doneSets.count) && zip(r, plannedReps.prefix(need)).allSatisfy { $0 >= $1 }
        }
        func rpe(_ ses: StrengthSession, _ x: ExerciseEntry) -> Int? { x.doneSets.compactMap { $0.rpe }.max() ?? ses.rpe ?? ses.checkIn?.effort }
        let rpes = last2.map { rpe($0.0, $0.1) }
        let dates = last2.map { AdaptationExplainer.day($0.0.date) }.reversed().joined(separator: " and ")
        let repsText = Set(plannedReps).count == 1 ? "\(plannedReps.count) × \(plannedReps[0])" : plannedReps.map(String.init).joined(separator: "/")
        let rpeText = rpes.compactMap { $0 }.map(String.init).reversed().joined(separator: " and ")
        let u = input.units
        // harness P30 (run s10): the evidence must be at the CURRENT prescription — both sessions lifted at least the weight
        // and the reps now planned — as in the planner (audit G-02: "two sessions in a row at that weight"). Without it a
        // routine went up one step after every session (goblet squat 12 → 19 kg in three weeks, one session at each weight).
        let nowTop = e.sets.compactMap { $0.bodyweight ? nil : $0.weightKg }.max()
        let nowReps = e.sets.map { $0.reps }.min() ?? 0
        func atCurrent(_ x: ExerciseEntry) -> Bool {
            if let c = nowTop, c > 0 {
                guard let w = x.doneSets.compactMap({ $0.bodyweight ? nil : $0.weightKg }).max(), w + 0.01 >= c else { return false }
            }
            return (x.doneSets.map { $0.reps }.min() ?? 0) >= nowReps
        }
        if last2.allSatisfy({ complete($0.0, $0.1) && atCurrent($0.1) }), rpes.allSatisfy({ ($0 ?? 99) <= AdaptiveRules.progressionMaxRPE }) {
            let evidence = "You completed every planned set of \(e.name) (\(repsText)) on \(dates) at RPE \(rpeText) — 8 or less both times."
            let currentTop = e.sets.compactMap { $0.bodyweight ? nil : $0.weightKg }.max()
            let ownsIt = known.map { input.equipment.hasEquipment(for: $0) } ?? true
            if let top = currentTop, top > 0, ownsIt {
                let dumbbell = known?.equipment.contains { $0 == "dumbbell" || $0 == "kettlebell" } ?? false
                let step = WeightFmt.step(dumbbell: dumbbell, u)
                // independent review F-17: the same rule as the planner (G-01) — the smallest available step, whatever its
                // percentage of a light load, with a caution above 10 %; never more than one step
                if step <= AdaptiveRules.maxWeightStepKg + 0.0001 {
                    let big = step / top > 0.1 ? " That is a big jump for this weight: if the first set is harder than RPE 8, go back to \(AdaptationExplainer.kg(top, u)) and add a rep instead." : ""
                    return PlanAdjustment(workoutId: s.id, change: .weight(exerciseId: e.exerciseId, deltaKg: step), category: .progression, summary: "\(e.name): \(AdaptationExplainer.kg(top, u)) → \(AdaptationExplainer.kg(top + step, u))\(dumbbell ? " per hand" : "")", why: "\(evidence) So \(AdaptationExplainer.day(s.date)) adds the smallest step, \(AdaptationExplainer.kg(step, u))\(dumbbell ? " per hand" : "") (\(AdaptationExplainer.kg(top, u)) → \(AdaptationExplainer.kg(top + step, u))).\(big) If that weight is not available to you, do one more rep per set instead.", createdAt: input.now)
                }
            }
            let maxReps = e.sets.map { $0.reps }.max() ?? 0
            if maxReps < 20 {
                let reason: String
                if currentTop != nil && !ownsIt { reason = "The equipment for \(e.name) is not in your equipment list, so a rep is added rather than weight." }
                else if currentTop != nil { reason = "The smallest load step would be more than 2.5 kg, so a rep is added instead." }
                else { reason = "No load is recorded for \(e.name), so a rep is added." }
                return PlanAdjustment(workoutId: s.id, change: .reps(exerciseId: e.exerciseId, delta: AdaptiveRules.maxRepsStep), category: .progression, summary: "\(e.name): \(maxReps) → \(maxReps + 1) reps per set", why: "\(evidence) \(reason)", createdAt: input.now)
            }
            if e.sets.count < 5 {
                return PlanAdjustment(workoutId: s.id, change: .sets(exerciseId: e.exerciseId, delta: 1), category: .progression, summary: "\(e.name): \(e.sets.count) → \(e.sets.count + 1) sets", why: "\(evidence) Reps are already 20 per set, so one set is added (about 2.5 min).", createdAt: input.now)
            }
            return nil
        }
        // two sessions in a row short of the planned reps at RPE ≥ 9 → one rep fewer (never below 3)
        if last2.allSatisfy({ !complete($0.0, $0.1) }), rpes.allSatisfy({ ($0 ?? 0) >= 9 }), let minReps = e.sets.map({ $0.reps }).min(), minReps > 3 {
            let did = last2.reversed().map { $0.1.doneSets.map { String($0.reps) }.joined(separator: "/") }.joined(separator: " and ")
            return PlanAdjustment(workoutId: s.id, change: .reps(exerciseId: e.exerciseId, delta: -1), category: .reduction, summary: "\(e.name): one rep fewer per set", why: "On \(dates) you did \(did) reps of \(e.name) against \(repsText) planned, at RPE \(rpeText). Two sessions in a row short of the plan at a very hard effort, so \(AdaptationExplainer.day(s.date)) asks for one rep fewer per set at the same weight.", createdAt: input.now)
        }
        return nil
    }

    // MARK: helpers
    static func monday(_ d: Date, _ cal: Calendar) -> Date { let d0 = cal.startOfDay(for: d); let wd = (cal.component(.weekday, from: d0) + 5) % 7; return cal.date(byAdding: .day, value: -wd, to: d0)! }
    static func isoWeek(_ d: Date, _ cal: Calendar) -> String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: monday(d, cal)) }
    /// Planned riding minutes of the session's week (as originally planned) and the cycling budget.
    static func rideWeek(_ w: Workout, _ input: AdaptationInput) -> (Int, Int) {
        let m = monday(w.date, input.calendar), e = input.calendar.date(byAdding: .day, value: 7, to: m)!
        return (PlanEngine.rideMinutes(input.plan.map { $0.restoredOriginal }.filter { $0.date >= m && $0.date < e }), input.profile.hoursPerWeek * 60)
    }
    static func liftWeek(_ w: Workout, _ input: AdaptationInput) -> (Int, Int) {
        let m = monday(w.date, input.calendar), e = input.calendar.date(byAdding: .day, value: 7, to: m)!
        return (PlanEngine.liftMinutes(input.plan.map { $0.restoredOriginal }.filter { $0.date >= m && $0.date < e }), input.profile.liftingHoursPerWeek * 60)
    }
    /// The rider's own minutes for that day's activity (the availability assignment the session came from).
    static func dayMinutes(_ w: Workout, _ input: AdaptationInput) -> Int? {
        guard let id = w.assignmentId else { return nil }
        for d in input.availability.days { if let x = d.assignments.first(where: { $0.id == id }) { return x.minutes } }
        return nil
    }
    /// Planned-load increase of one progression (AU, session-RPE × minutes).
    static func loadIncrease(_ adj: PlanAdjustment, _ future: [Workout]) -> Double {
        guard let w = future.first(where: { $0.id == adj.workoutId }) else { return 0 }
        switch adj.change {
        case .minutes(let d): return Double(max(0, d)) * AdaptiveRules.plannedRPE(w.kind)
        case .intervalReps(let d): return Double(max(0, d) * (w.kind.intervalWorkMinutes + w.kind.intervalRestMinutes)) * max(0, AdaptiveRules.plannedRPE(w.kind) - 3)
        case .sets(_, let d): return Double(max(0, d)) * 2.5 * AdaptiveRules.plannedRPE(.strength)
        case .reps(_, let d): return d > 0 ? 0.03 * AdaptiveRules.plannedLoad(w) : 0
        case .weight(_, let kg): return kg > 0 ? 0.03 * AdaptiveRules.plannedLoad(w) : 0
        case .kind(let k): return max(0, AdaptiveRules.plannedRPE(k) - AdaptiveRules.plannedRPE(w.kind)) * Double(w.minutes)
        case .replace: return 0
        }
    }
}

// MARK: - B: equipment-aware session building from the rider's own exercises
enum StrengthProgrammer {
    /// Movement patterns of a generated session by type. A custom type named like "core", "joint", "mobility" or
    /// "prehab" becomes a core / single-leg / pulling session (trunk, balance, shoulder health).
    static func patterns(for focus: StrengthFocus, label: String) -> [MovementPattern] {
        switch focus {
        case .fullBody: return [.squat, .push, .hinge, .pull, .core]
        case .upper: return [.push, .pull, .push, .pull]
        case .lower, .legs: return [.squat, .hinge, .singleLeg, .core]
        case .push: return [.push, .push, .push, .core]
        case .pull: return [.pull, .pull, .pull, .core]
        case .custom:
            let l = label.lowercased()
            if ["core", "joint", "mobility", "prehab", "stability"].contains(where: { l.contains($0) }) { return [.core, .singleLeg, .core, .pull] }
            return [.squat, .push, .hinge, .pull, .core]
        }
    }
    /// Exercises the rider can do, in preference order: those in routines they asked to preserve, their own
    /// exercises, those in their other routines, then the catalogue. Never unavailable equipment, never excluded ones.
    static func pool(templates: [WorkoutTemplate], preserved: [UUID], custom: [Exercise], catalogue: [Exercise], equipment: EquipmentProfile) -> [(Exercise, [SetEntry]?)] {
        var out: [(Exercise, [SetEntry]?)] = []
        func add(_ e: Exercise, _ sets: [SetEntry]?) { if equipment.canDo(e), !out.contains(where: { $0.0.id == e.id }) { out.append((e, sets)) } }
        let all = custom + catalogue.filter { c in !custom.contains { $0.id == c.id } }
        func lookup(_ id: String) -> Exercise? { all.first { $0.id == id } }
        for t in templates.filter({ preserved.contains($0.id) }) { for en in t.entries { if let e = lookup(en.exerciseId) { add(e, en.sets) } } }
        for e in custom { add(e, nil) }
        for t in templates.filter({ !preserved.contains($0.id) }) { for en in t.entries { if let e = lookup(en.exerciseId) { add(e, en.sets) } } }
        for e in catalogue { add(e, nil) }
        return out
    }
    static func entries(focus: StrengthFocus, label: String, templates: [WorkoutTemplate], preserved: [UUID], custom: [Exercise], catalogue: [Exercise], equipment: EquipmentProfile) -> [ExerciseEntry] {
        let p = pool(templates: templates, preserved: preserved, custom: custom, catalogue: catalogue, equipment: equipment)
        var used: Set<String> = []
        var out: [ExerciseEntry] = []
        for pat in patterns(for: focus, label: label) {
            guard let pick = p.first(where: { $0.0.pattern == pat && !used.contains($0.0.id) }) else { continue }
            used.insert(pick.0.id)
            let bw = pick.0.equipment.isEmpty || pick.0.equipment == ["bodyweight"]
            let sets = pick.1.map { ss in ss.map { s -> SetEntry in var x = s; x.id = UUID(); x.done = true; return x } } ?? (0..<3).map { _ in SetEntry(reps: pat == .core ? 12 : 10, weightKg: nil, bodyweight: bw, unilateral: pick.0.unilateral) }
            out.append(ExerciseEntry(exercise: pick.0, sets: sets.isEmpty ? [SetEntry(reps: 10, bodyweight: bw)] : sets))
        }
        return out
    }
    /// A doable exercise of the same movement pattern (the rider's own and routine exercises first).
    static func substitute(for ex: Exercise, input: AdaptationInput, avoiding: Set<String>) -> Exercise? {
        let p = pool(templates: input.templates, preserved: input.profile.preservedTemplateIds, custom: input.catalogue.filter { $0.custom }, catalogue: input.catalogue, equipment: input.equipment)
        return p.first { $0.0.pattern == ex.pattern && $0.0.id != ex.id && !avoiding.contains($0.0.id) }?.0
    }
}
