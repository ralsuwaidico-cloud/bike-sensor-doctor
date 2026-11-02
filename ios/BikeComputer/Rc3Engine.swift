import Foundation

// MARK: - RC3 engine additions (ios/ENGINE_API_RC3.md)
// Rules from blueprint/engine/WP2_APPROVAL.md: ENG-E1 / E3 / E5 (FTP state, effort targets, ride steps that add up),
// ENG-D6 (top set first, e1RM only when reliable), ENG-K1 (checkpoints need time AND sessions), ENG-J2 / J3 (changes reach
// planned weeks only after preview; history is append-only). Pure Foundation: compiled by the Linux coach harness too.

// MARK: Goals (r7 S2: goals across both sports with one primary)
enum GoalID: String, Codable, CaseIterable, Identifiable {
    // cycling
    case endurance, power, sprint, climbing, event
    // strength
    case muscle, strength, stamina, maintain
    // general
    case fitness
    var id: String { rawValue }
    enum Sport: String { case cycling, strength, general }

    /// Accepts current values and older / merged names. "Aerobic fitness" is the same training as Endurance (r7 merge);
    /// the caller keeps the original string in `RiderProfile.legacyGoal`.
    init?(legacy raw: String) {
        if let g = GoalID(rawValue: raw) { self = g; return }
        switch raw.lowercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "") {
        case "aerobicfitness", "aerobic", "buildaerobicfitness", "improveendurance", "rideslonger", "ridelonger": self = .endurance
        case "increaseftp", "ftp", "stronger", "raiseftp": self = .power
        case "buildmuscle", "hypertrophy": self = .muscle
        case "maxstrength", "maximalstrength": self = .strength
        case "generalfitness", "health": self = .fitness
        default: return nil
        }
    }
    var title: String {
        switch self {
        case .endurance: return "Endurance"; case .power: return "Power"; case .sprint: return "Sprint"; case .climbing: return "Climbing"; case .event: return "Event"
        case .muscle: return "Muscle"; case .strength: return "Strength"; case .stamina: return "Stamina"; case .maintain: return "Maintain"
        case .fitness: return "Fitness"
        }
    }
    var sport: Sport {
        switch self {
        case .endurance, .power, .sprint, .climbing, .event: return .cycling
        case .muscle, .strength, .stamina, .maintain: return .strength
        case .fitness: return .general
        }
    }
    /// The build-121 cycling goal the week builder reads (board goal code comes from it).
    var cyclingGoal: RiderProfile.Goal? {
        switch self {
        case .endurance: return .endurance; case .power, .sprint: return .stronger; case .climbing: return .climbing; case .event: return .event
        case .fitness: return .fitness
        default: return nil
        }
    }
    /// The strength-programming goal the planner reads.
    var strengthGoal: StrengthPrefs.Goal? {
        switch self {
        case .muscle: return .hypertrophy; case .strength: return .strength; case .stamina: return .enduranceSupport; case .maintain: return .general
        default: return nil
        }
    }
    static func from(cyclingGoal g: RiderProfile.Goal) -> GoalID {
        switch g { case .endurance: return .endurance; case .stronger: return .power; case .climbing: return .climbing; case .event: return .event; case .fitness, .weight, .progress: return .fitness }
    }
}

// MARK: Explicit training pause
struct TrainingPause: Codable, Equatable {
    enum Reason: String, Codable, CaseIterable { case unwell, injured, away
        var title: String { switch self { case .unwell: return "Unwell"; case .injured: return "Injured"; case .away: return "Away" } } }
    var since: Date
    var reason: Reason
}

// MARK: FTP state (ENG-E1): unknown / entered / estimated / tested — only the last three can produce watts
enum FTPSource: String, Codable, CaseIterable {
    case unknown, entered, estimated, tested
    var title: String { switch self { case .unknown: return "Unknown"; case .entered: return "Entered"; case .estimated: return "Estimated"; case .tested: return "Tested" } }
}

extension RiderProfile {
    /// The build-121 starting assumption (W/kg) is not an FTP: `ftpHow == .assumed` means Unknown.
    var ftpKnown: Bool { ftpHow != .assumed && ftpW > 0 }
    var ftpSource: FTPSource {
        switch ftpHow {
        case .assumed: return .unknown
        case .entered: return .entered
        case .fromRides: return .estimated
        case .tested: return ftpVerifiedTest == true ? .tested : .entered     // a test result without a recorded test ride
        }
    }
    /// The FTP value, nil when unknown.
    var ftpValue: Int? { ftpKnown ? ftpW : nil }
    /// The FTP watt targets use: nil when unknown; 5 % lower when known but not verified (build-121 conservative rule).
    var targetFTP: Int? {
        guard ftpKnown else { return nil }
        return ftpConfidence.isConfident ? ftpW : Int((Double(ftpW) * 0.95).rounded())
    }
    /// "250 W" or "Unknown".
    var ftpDisplay: String { ftpKnown ? "\(ftpW) W" : "Unknown" }
    /// Sets the FTP from an athlete answer. `nil` / `.unknown` = "I don't know". S2-0 (GR-22): choosing Entered /
    /// Estimated / Tested WITHOUT a number never keeps or invents a value — the FTP stays Unknown until watts are typed.
    mutating func setFTP(_ watts: Int?, source: FTPSource, at: Date = Date()) {
        guard let w = watts, w > 0, source != .unknown else {
            ftpW = 0; ftpHow = .assumed; ftpVerifiedTest = nil; ftpPowerVerified = nil; ftpFromDate = nil
            setProvenance(.ftp, nil)
            return
        }
        switch source {
        case .unknown: return
        case .entered: ftpW = w; ftpHow = .entered; ftpVerifiedTest = nil; ftpPowerVerified = nil; setProvenance(.ftp, ValueProvenance(source: .entered, recordedAt: at))
        case .estimated: ftpW = w; ftpHow = .fromRides; setProvenance(.ftp, ValueProvenance(source: .estimatedFromRides, recordedAt: at))
        case .tested: ftpW = w; ftpHow = .tested; setProvenance(.ftp, ValueProvenance(source: ftpVerifiedTest == true ? .measuredTest : .entered, recordedAt: at))
        }
    }
    /// Goals in force: the r7 list, else the build-121 goal mapped (never empty).
    var effectiveGoals: [GoalID] { goals.isEmpty ? [GoalID.from(cyclingGoal: goal)] : goals }
    var effectivePrimaryGoal: GoalID { primaryGoal ?? effectiveGoals[0] }
    /// Age from the full date of birth (nil without one).
    var ageFromBirth: Int? {
        guard let d = dateOfBirth else { return nil }
        return Calendar.current.dateComponents([.year], from: d, to: Date()).year
    }
}

// MARK: Ride steps (ENG-E5) with effort / heart-rate / power targets (ENG-E3)
struct RideStep: Equatable {
    enum Role: String { case warmUp, steady, work, recover, easy, coolDown, test }
    var name: String
    var minutes: Int
    var role: Role
    /// CR-10 effort (always present).
    var rpe: ClosedRange<Int>
    /// Heart-rate zone 1–5 (nil for the test effort).
    var hrZone: Int?
    /// Fraction of FTP for power targets (nil = no power target for this step).
    var powerFraction: ClosedRange<Double>?
    /// Watts — only when the FTP is known (never from an assumed FTP).
    func watts(ftp: Int?) -> ClosedRange<Int>? {
        guard let f = ftp, f > 0, let p = powerFraction else { return nil }
        return Int((Double(f) * p.lowerBound).rounded())...Int((Double(f) * p.upperBound).rounded())
    }
    /// "RPE 5–6 · HR Z3 138–152 bpm" / "214–229 W · RPE 5–6" / "RPE 5–6".
    func targetText(ftp: Int?, hrZones: [(lo: Int, hi: Int?)]?) -> String {
        var parts: [String] = []
        if let w = watts(ftp: ftp) { parts.append("\(w.lowerBound)–\(w.upperBound) W") }
        parts.append(rpe.lowerBound == rpe.upperBound ? "RPE \(rpe.lowerBound)" : "RPE \(rpe.lowerBound)–\(rpe.upperBound)")
        if let z = hrZone, let zs = hrZones, z >= 1, z <= zs.count {
            let b = zs[z - 1]
            parts.append(b.hi.map { "HR Z\(z) \(b.lo)–\($0) bpm" } ?? "HR Z\(z) \(b.lo)+ bpm")
        }
        if role == .test { parts.append("as hard as you can hold steady") }
        return parts.joined(separator: " · ")
    }
}

enum RideSteps {
    static let pairHRHint = "Pair a heart-rate strap for heart-rate targets"
    static func easy(_ name: String, _ m: Int, _ role: RideStep.Role) -> RideStep { RideStep(name: name, minutes: m, role: role, rpe: 2...3, hrZone: 1, powerFraction: 0.45...0.60) }
    static func work(for k: WorkoutKind) -> (rpe: ClosedRange<Int>, zone: Int, power: ClosedRange<Double>) {
        switch k {
        case .tempo: return (5...6, 3, 0.84...0.90)
        case .threshold: return (7...8, 4, 0.93...1.02)
        case .vo2: return (8...9, 5, 1.06...1.18)
        case .recovery: return (1...2, 1, 0.40...0.55)
        default: return (3...4, 2, 0.65...0.75)               // endurance / long
        }
    }
    /// Warm-up and cool-down by length (ENG-E5): 15 / 10 min from 60 min, else 10 / 5.
    static func ends(_ minutes: Int) -> (w: Int, c: Int) { minutes >= 60 ? (15, 10) : (10, 5) }

    /// Interval repetitions that fit (largest n ≤ wanted with W + n × (work + rest) + C ≤ minutes); 0 when none fits.
    static func fittedReps(kind k: WorkoutKind, minutes: Int, wanted: Int) -> Int {
        let wk = k.intervalWorkMinutes, rs = k.intervalRestMinutes
        guard wk > 0 else { return 0 }
        let e = ends(minutes)
        var n = max(1, wanted)
        while n > 0, e.w + n * (wk + rs) + e.c > minutes { n -= 1 }
        return n
    }

    /// Every ride kind × every length: the steps add up to the session's minutes exactly (RIDE-001 / AT-E5-2).
    static func build(_ w: Workout) -> [RideStep] {
        let m = max(0, w.minutes), k = w.kind
        guard k.isRide, m > 0 else { return [] }
        if k == .ftpTest {
            guard m >= 35 else { return [easy("Easy", m, .steady)] }
            let test = 20, cool = m >= 50 ? 10 : 5, warm = m - test - cool
            return [easy("Warm-up", warm, .warmUp),
                    RideStep(name: "Test", minutes: test, role: .test, rpe: 9...10, hrZone: nil, powerFraction: nil),
                    easy("Cool-down", cool, .coolDown)]
        }
        let wt = work(for: k)
        func steady(_ name: String, _ minutes: Int) -> RideStep { RideStep(name: name, minutes: minutes, role: .steady, rpe: wt.rpe, hrZone: wt.zone, powerFraction: wt.power) }
        if m < 30 || k == .recovery && m < 30 { return [steady(k == .recovery ? "Easy spin" : "Steady", m)] }
        let e = ends(m), main = m - e.w - e.c
        var out: [RideStep] = [easy("Warm-up", e.w, .warmUp)]
        switch k {
        case .tempo:
            let n = max(1, (main + 5) / 20)
            var used = 0
            for i in 0..<n {
                if i > 0 { out.append(easy("Easy", 5, .recover)); used += 5 }
                out.append(RideStep(name: "Block \(i + 1)", minutes: 15, role: .work, rpe: wt.rpe, hrZone: wt.zone, powerFraction: wt.power)); used += 15
            }
            if main - used > 0 { out.append(easy("Easy", main - used, .easy)) }
            if main - used < 0 { return [steady("Tempo", m)] }                 // cannot happen for m ≥ 30; kept as a guard
        case .threshold, .vo2:
            let n = fittedReps(kind: k, minutes: m, wanted: w.effectiveIntervalReps ?? (k.defaultIntervalReps ?? 3))
            if n == 0 { out.append(steady("Steady", main)); break }
            let wk = k.intervalWorkMinutes, rs = k.intervalRestMinutes
            for i in 0..<n {
                out.append(RideStep(name: "Interval \(i + 1)", minutes: wk, role: .work, rpe: wt.rpe, hrZone: wt.zone, powerFraction: wt.power))
                out.append(easy("Easy", rs, .recover))
            }
            let left = main - n * (wk + rs)
            if left > 0 { out.append(easy("Easy", left, .easy)) }
        default:
            out.append(steady(k == .long ? "Long steady" : k == .recovery ? "Easy spin" : "Steady", main))
        }
        out.append(easy("Cool-down", e.c, .coolDown))
        return out
    }
}

extension Workout {
    /// ENG-E5 steps; their minutes add up to `minutes`.
    var rideSteps: [RideStep] { RideSteps.build(self) }
    /// Interval repetitions that fit this session's minutes (the live coach and the plan use the same number).
    var fittedIntervalReps: Int? {
        guard let r = effectiveIntervalReps, kind.intervalWorkMinutes > 0 else { return nil }
        return RideSteps.fittedReps(kind: kind, minutes: minutes, wanted: r)
    }
}

// MARK: Strength performance (ENG-D6)
struct LiftPoint: Equatable {
    var date: Date
    var weightKg: Double
    var reps: Int
    /// Estimated 1RM (Brzycki with effective reps) — nil unless the set qualifies.
    var e1RM: Double?
}

struct LiftSummary: Equatable, Identifiable {
    var id: String { exerciseId }
    var exerciseId: String
    var name: String
    /// Measured: the heaviest load completed per session (ties → more reps), oldest first.
    var topSets: [LiftPoint]
    /// Sessions whose top set qualifies for an estimated 1RM.
    var qualifyingSessions: Int { topSets.filter { $0.e1RM != nil }.count }
    /// A trend needs ≥ 3 qualifying sessions (otherwise "not enough data").
    var e1RMTrendAvailable: Bool { qualifyingSessions >= StrengthPerformance.minSessionsForTrend }
    var latest: LiftPoint? { topSets.last }
}

enum StrengthPerformance {
    static let minSessionsForTrend = 3
    /// Brzycki: load × 36 / (37 − r_eff), r_eff = reps + (10 − RPE). Only RPE ≥ 8, 1 ≤ r_eff ≤ 10, load > 0.
    static func e1RM(weightKg w: Double, reps: Int, rpe: Int?) -> Double? {
        guard let r = rpe, r >= 8, r <= 10, w > 0, reps >= 1 else { return nil }
        let eff = reps + (10 - r)
        guard (1...10).contains(eff) else { return nil }
        return w * 36 / Double(37 - eff)
    }
    /// Externally loaded (barbell / dumbbell / kettlebell / machine / cable), not bodyweight, hold or per-side.
    static func loadedLift(_ e: ExerciseEntry, set s: SetEntry) -> Bool {
        !s.bodyweight && !s.unilateral && (s.weightKg ?? 0) > 0 && !DurationModel.isHoldName(e.name)
    }
    /// The session's top working set of one exercise: heaviest completed load, ties → more reps. nil = nothing loaded.
    static func topSet(_ e: ExerciseEntry, date: Date) -> LiftPoint? {
        let done = e.sets.filter { $0.done && ($0.weightKg ?? 0) > 0 && !$0.bodyweight }
        guard let best = done.max(by: { a, b in (a.weightKg ?? 0, a.reps) < (b.weightKg ?? 0, b.reps) }) else { return nil }
        let est = loadedLift(e, set: best) ? e1RM(weightKg: best.weightKg ?? 0, reps: best.reps, rpe: best.rpe) : nil
        return LiftPoint(date: date, weightKg: best.weightKg ?? 0, reps: best.reps, e1RM: est)
    }
    /// Per-lift history from counted logs (never from planned sets), newest window `since`.
    static func lifts(logs: [StrengthSession], since: Date? = nil) -> [LiftSummary] {
        var by: [String: LiftSummary] = [:]
        for s in logs.sorted(by: { $0.date < $1.date }) where !s.awaitingReview && !s.inProgress && (since.map { s.date >= $0 } ?? true) {
            for e in s.exercises ?? [] {
                guard let p = topSet(e, date: s.date) else { continue }
                by[e.exerciseId, default: LiftSummary(exerciseId: e.exerciseId, name: e.name, topSets: [])].topSets.append(p)
            }
        }
        return by.values.sorted { ($0.topSets.count, $0.name) > ($1.topSets.count, $1.name) }
    }
}

// MARK: Checkpoints (ENG-K1)
struct Checkpoint: Equatable {
    enum Sport: String { case cycling, strength }
    enum Performance: String { case improved, flat, declined, notEnoughData }
    var sport: Sport
    var weeks: Int
    var reached: Bool
    var countedWeeks: Int
    var sessions: Int
    /// Earliest date it can be reached (time only); nil when the clock hasn't started (no completed session yet).
    var earliestDate: Date?
    /// What is missing, e.g. "1 more ride" / "2 more weeks" / "Starts with your first completed ride".
    var missing: String?
    var performance: Performance
}

enum Checkpoints {
    static let marks = [4, 8, 12]
    /// - Parameters: completed: dates of completed sessions of the sport; pausedWeeks: Mondays of weeks paused.
    static func compute(sport: Checkpoint.Sport, completed: [Date], pausedWeeks: Set<Date>, performance: Checkpoint.Performance, now: Date, calendar cal: Calendar = .current) -> [Checkpoint] {
        let noun = sport == .cycling ? "ride" : "strength session"
        guard let first = completed.filter({ $0 <= now }).min() else {
            return marks.map { Checkpoint(sport: sport, weeks: $0, reached: false, countedWeeks: 0, sessions: 0, earliestDate: nil, missing: "Starts with your first completed \(noun)", performance: .notEnoughData) }
        }
        let start = cal.startOfDay(for: first)
        let days = cal.dateComponents([.day], from: start, to: cal.startOfDay(for: now)).day ?? 0
        let elapsed = max(0, days / 7)
        let pausedInside = pausedWeeks.filter { $0 >= TrainingLedger.monday(of: start, calendar: cal) && $0 <= now }.count
        let counted = max(0, elapsed - pausedInside)
        let n = completed.filter { $0 >= start && $0 <= now }.count
        return marks.map { N in
            let reached = counted >= N && n >= N
            var miss: [String] = []
            if n < N { let k = N - n; miss.append("\(k) more \(noun)\(k == 1 ? "" : "s")") }
            if counted < N { let k = N - counted; miss.append("\(k) more week\(k == 1 ? "" : "s")") }
            let earliest = cal.date(byAdding: .day, value: 7 * (N + pausedInside), to: start)
            return Checkpoint(sport: sport, weeks: N, reached: reached, countedWeeks: counted, sessions: n, earliestDate: earliest,
                              missing: reached ? nil : miss.joined(separator: " · "), performance: reached ? performance : .notEnoughData)
        }
    }
    /// Strength performance at a checkpoint: from lifts with ≥ 3 qualifying sessions; heavier top set (or e1RM) → improved.
    static func strengthPerformance(_ lifts: [LiftSummary]) -> Checkpoint.Performance {
        let usable = lifts.filter { $0.topSets.count >= StrengthPerformance.minSessionsForTrend }
        guard !usable.isEmpty else { return .notEnoughData }
        var up = 0, down = 0
        for l in usable {
            guard let a = l.topSets.first, let b = l.topSets.last else { continue }
            let va = a.e1RM ?? a.weightKg, vb = b.e1RM ?? b.weightKg
            if vb > va * 1.02 { up += 1 } else if vb < va * 0.98 { down += 1 }
        }
        return up > down ? .improved : down > up ? .declined : .flat
    }
    /// Cycling performance needs two FTP values from verified power or tests (entered values are not evidence).
    static func cyclingPerformance(ftpEvidence: [(date: Date, watts: Int)]) -> Checkpoint.Performance {
        let e = ftpEvidence.sorted { $0.date < $1.date }
        guard e.count >= 2, let a = e.first, let b = e.last else { return .notEnoughData }
        if Double(b.watts) > Double(a.watts) * 1.02 { return .improved }
        if Double(b.watts) < Double(a.watts) * 0.98 { return .declined }
        return .flat
    }
    /// Adherence per week (done ÷ planned from the sessions in the plan for that week — each week counts the plan
    /// version in force), paused weeks excluded.
    static func adherence(plan: [Workout], completedIds: Set<UUID>, pausedWeeks: Set<Date>, from: Date, to: Date, calendar cal: Calendar = .current) -> [(monday: Date, planned: Int, done: Int)] {
        var by: [Date: (Int, Int)] = [:]
        for w in plan where (w.kind.isRide || w.kind == .strength) && w.date >= from && w.date < to {
            let m = TrainingLedger.monday(of: w.date, calendar: cal)
            if pausedWeeks.contains(m) { continue }
            var x = by[m] ?? (0, 0)
            x.0 += 1; if completedIds.contains(w.id) { x.1 += 1 }
            by[m] = x
        }
        return by.keys.sorted().map { ($0, by[$0]!.0, by[$0]!.1) }
    }
}

// MARK: Plan changes and versions (ENG-J2 / J3)
enum PlanChangeCause: String, Codable, CaseIterable {
    case edit, equipment, days, minutes, goal, priority, split, strengthLevel, ftp, coach, profile, migration, undo
    var title: String {
        switch self {
        case .edit: return "Session edit"; case .equipment: return "Equipment"; case .days: return "Training days"; case .minutes: return "Session length"
        case .goal: return "Goals"; case .priority: return "Priority"; case .split: return "Strength split"; case .strengthLevel: return "Strength level"
        case .ftp: return "FTP"; case .coach: return "Coach"; case .profile: return "Training settings"; case .migration: return "Update"; case .undo: return "Undo"
        }
    }
}

/// Everything the plan is generated from. A change to any of these goes through a preview (`proposePlanChange`).
struct PlanInputs: Codable, Equatable {
    var profile: RiderProfile
    var availability: WeeklyAvailability?
    var equipment: EquipmentProfile
    var strengthPrefs: StrengthPrefs
    /// True when the change can alter planned sessions (otherwise save directly, no preview needed).
    func planningDiffers(from o: PlanInputs) -> Bool {
        var a = profile, b = o.profile
        // fields that don't change what is planned
        a.name = ""; b.name = ""; a.bikeName = nil; b.bikeName = nil; a.gender = nil; b.gender = nil
        a.version = 0; b.version = 0; a.updatedAt = Date(timeIntervalSince1970: 0); b.updatedAt = a.updatedAt
        a.wheelMm = 0; b.wheelMm = 0; a.hrPrefWatchFirst = false; b.hrPrefWatchFirst = false
        a.sports = []; b.sports = []; a.heightCm = nil; b.heightCm = nil
        return a != b || availability != o.availability || equipment != o.equipment || strengthPrefs != o.strengthPrefs
    }
}

struct PlanVersion: Codable, Equatable, Identifiable {
    var id = UUID()
    var createdAt: Date
    /// First session in scope.
    var effectiveDate: Date
    var cause: PlanChangeCause
    /// Sessions in scope as they were, and as applied.
    var before: [Workout]
    var after: [Workout]
    /// Planning inputs before the change (Undo restores them with the sessions).
    var inputsBefore: PlanInputs?
    var summary: [String]
    var proposalId: UUID?
}

struct PlanChangeProposal: Identifiable, Equatable {
    let id: UUID
    let cause: PlanChangeCause
    let createdAt: Date
    let inputs: PlanInputs
    let inputsBefore: PlanInputs
    /// Sessions that will be replaced, their replacements, and in-scope sessions kept (hand-edited, fixed, started).
    let before: [Workout]
    let after: [Workout]
    let kept: [Workout]
    let summary: [String]
    var effectiveDate: Date? { (before.map(\.date) + after.map(\.date)).min() }
    var changesSessions: Bool { before != after }
}

extension Store {
    var planInputs: PlanInputs { PlanInputs(profile: profile, availability: availability, equipment: equipment, strengthPrefs: strengthPrefs) }

    /// Locked = never in a proposal's scope: done, skipped, completed in any way, being recorded, or with a log.
    func sessionLocked(_ w: Workout) -> Bool {
        w.done || w.skipped || w.completion != nil || activeSession?.workoutId == w.id || strength.contains { $0.workoutId == w.id }
    }

    /// ENG-J2: one week-level proposal for the current unfinished session and every future open session. Nothing is
    /// saved; `applyPlanChange` saves the inputs and the sessions together and records a plan version.
    @discardableResult
    func proposePlanChange(cause: PlanChangeCause, inputs new: PlanInputs, now: Date = Date()) -> UUID {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let open = plan.filter { cal.startOfDay(for: $0.date) >= today }
        var mondays = Set(open.map { TrainingLedger.monday(of: $0.date, calendar: cal) })
        if mondays.isEmpty { mondays.insert(TrainingLedger.monday(of: now, calendar: cal)) }
        var before: [Workout] = [], after: [Workout] = [], kept: [Workout] = []
        let a = new.availability ?? WeeklyAvailability.suggested(for: new.profile)
        var ctx = plannerContext(now: now)
        ctx.profile = new.profile; ctx.prefs = new.strengthPrefs; ctx.equipment = new.equipment
        for m in mondays.sorted() {
            let fresh = applyWeekdayRoutines(PlanEngine.week(starting: m, profile: new.profile, availability: a, returning: cyclingReturnPhase(now: now), trainingWeeks: consecutiveTrainingWeeks(before: m)))
            for i in 0..<7 {
                guard let day = cal.date(byAdding: .day, value: i, to: m), day >= today else { continue }
                let old = plan.filter { cal.isDate($0.date, inSameDayAs: day) }
                let locked = old.filter { sessionLocked($0) || $0.edited || $0.fixed }
                if !locked.isEmpty { kept += old.filter { !sessionLocked($0) }; continue }        // the day is the athlete's / already started
                var nd = fresh.filter { cal.isDate($0.date, inSameDayAs: day) }
                // same kind on the same day keeps its id, so a session that didn't change isn't listed
                for (k, x) in nd.enumerated() {
                    if let o = old.first(where: { $0.kind == x.kind && $0.sequence == x.sequence }) { nd[k].id = o.id; nd[k].date = o.date }
                }
                // strength sessions get their exercises now, so the preview shows the real session
                for k in nd.indices where nd[k].kind == .strength && nd[k].templateId == nil {
                    var c = ctx; c.plan = plan.filter { !cal.isDate($0.date, inSameDayAs: day) } + nd
                    let v = rebuiltPrescription(for: nd[k], prefersSupersets: new.strengthPrefs.prefersSupersets, ctx: c, origin: .coach)
                    let b = v.report.outcome == .block || v.entries.isEmpty ? StrengthPlanner.build(for: nd[k], ctx: c) : StrengthPlanner.Built(entries: v.entries, rationale: v.rationale)
                    nd[k].plannedEntries = b.entries; nd[k].generatedEntries = true; nd[k].rationale = b.rationale
                }
                if Store.sameSessions(old, nd) { continue }
                before += old; after += nd
            }
        }
        let summary = PlanEngine.changes(from: before, to: after)
        let p = PlanChangeProposal(id: UUID(), cause: cause, createdAt: now, inputs: new, inputsBefore: planInputs, before: before, after: after, kept: kept, summary: summary)
        pendingPlanChanges[p.id] = p
        return p.id
    }

    /// Same sessions ignoring ids and planned exercise ids (what the athlete would see as "no change").
    static func sameSessions(_ a: [Workout], _ b: [Workout]) -> Bool {
        func key(_ w: Workout) -> String { "\(w.kind.rawValue)|\(w.minutes)|\(w.strengthFocus?.rawValue ?? "-")|\(w.sequence)|\(w.intervalReps ?? 0)|\((w.plannedEntries ?? []).map { "\($0.exerciseId):\($0.sets.count)" }.joined(separator: ","))" }
        return a.map(key).sorted() == b.map(key).sorted()
    }

    /// Applies a proposal: inputs and sessions together, one plan version. false = the plan changed meanwhile (stale) or
    /// the proposal is gone; nothing is saved then.
    @discardableResult
    func applyPlanChange(_ id: UUID, now: Date = Date()) -> Bool {
        guard let p = pendingPlanChanges[id] else { return false }
        // stale: a session in scope was completed, started or edited since the preview
        for b in p.before { guard let cur = plan.first(where: { $0.id == b.id }), cur == b, !sessionLocked(cur) else { pendingPlanChanges.removeValue(forKey: id); return false } }
        transaction {
            profile = p.inputs.profile; availability = p.inputs.availability; equipment = p.inputs.equipment; strengthPrefs = p.inputs.strengthPrefs
            if p.changesSessions {
                let ids = Set(p.before.map(\.id))
                plan = (plan.filter { !ids.contains($0.id) } + p.after).sorted { ($0.date, $0.sequence) < ($1.date, $1.sequence) }
                planVersions.append(PlanVersion(createdAt: now, effectiveDate: p.effectiveDate ?? now, cause: p.cause, before: p.before, after: p.after, inputsBefore: p.inputsBefore, summary: p.summary, proposalId: p.id))
            }
        }
        pendingPlanChanges.removeValue(forKey: id)
        return true
    }
    func discardPlanChange(_ id: UUID) { pendingPlanChanges.removeValue(forKey: id) }

    /// ENG-J3 Undo: a NEW proposal that restores the version's inputs and its 'before' sessions that are still unstarted.
    /// Completed ones stay (listed as kept); the version log only grows.
    /// Owner 2 Nov: Undo restores THIS version's previous state and never silently discards a later change. Undo is
    /// refused (with the reason) when a later version touched the same days or later changed the plan inputs, or when the
    /// open sessions of those days no longer match what this version left (changed since by any other action).
    func undoBlockedReason(version vid: UUID, now: Date = Date()) -> String? {
        guard let i = planVersions.firstIndex(where: { $0.id == vid }) else { return "This change is no longer in the history." }
        let v = planVersions[i]
        let cal = Calendar.current
        let days = Set((v.before + v.after).map { cal.startOfDay(for: $0.date) })
        for later in planVersions[(i + 1)...] {
            let ld = Set((later.before + later.after).map { cal.startOfDay(for: $0.date) })
            if !ld.isDisjoint(with: days) || (v.inputsBefore != nil && later.inputsBefore != nil) {
                return "Changed again later (\(later.cause.title.lowercased()), \(later.createdAt.shortDay)). Undo that change first."
            }
        }
        for d in days where d >= cal.startOfDay(for: now) {
            let cur = plan.filter { cal.isDate($0.date, inSameDayAs: d) && !sessionLocked($0) }.sorted { $0.id.uuidString < $1.id.uuidString }
            let left = v.after.filter { cal.isDate($0.date, inSameDayAs: d) }.filter { a in cur.contains { $0.id == a.id } || !plan.contains { $0.id == a.id && sessionLocked($0) } }.sorted { $0.id.uuidString < $1.id.uuidString }
            if cur != left { return "The sessions of \(d.shortDay) were changed after this. Undo would overwrite that, so it is not offered." }
        }
        return nil
    }

    func proposeUndo(version vid: UUID, now: Date = Date()) -> UUID? {
        guard undoBlockedReason(version: vid, now: now) == nil else { return nil }
        guard let v = planVersions.first(where: { $0.id == vid }) else { return nil }
        var before: [Workout] = [], after: [Workout] = [], kept: [Workout] = []
        let cal = Calendar.current
        let days = Set((v.before + v.after).map { cal.startOfDay(for: $0.date) })
        for d in days.sorted() {
            let cur = plan.filter { cal.isDate($0.date, inSameDayAs: d) }
            if cur.contains(where: sessionLocked) || d < cal.startOfDay(for: now) { kept += cur; continue }
            before += cur; after += v.before.filter { cal.isDate($0.date, inSameDayAs: d) }
        }
        let inputs = v.inputsBefore ?? planInputs
        let p = PlanChangeProposal(id: UUID(), cause: .undo, createdAt: now, inputs: inputs, inputsBefore: planInputs, before: before, after: after, kept: kept, summary: PlanEngine.changes(from: before, to: after))
        pendingPlanChanges[p.id] = p
        return p.id
    }

    /// Convenience for screens: change the inputs in a closure, get a proposal id back (nil = nothing that affects the
    /// plan changed: the inputs were saved directly).
    func proposePlanChange(cause: PlanChangeCause, now: Date = Date(), _ change: (inout PlanInputs) -> Void) -> UUID? {
        var x = planInputs
        change(&x)
        guard x.planningDiffers(from: planInputs) else {
            transaction { profile = x.profile; availability = x.availability; equipment = x.equipment; strengthPrefs = x.strengthPrefs }
            return nil
        }
        return proposePlanChange(cause: cause, inputs: x, now: now)
    }

    /// The one way a screen changes training inputs: the proposal id to preview, or nil when it was saved straight away —
    /// nothing that affects planning changed, or no planned session changes (then the inputs are applied with a plan
    /// version and no extra screen). Completed workouts are never in scope.
    func proposeOrApplyPlanChange(cause: PlanChangeCause, now: Date = Date(), _ change: (inout PlanInputs) -> Void) -> UUID? {
        guard let id = proposePlanChange(cause: cause, now: now, change) else { return nil }
        if let p = pendingPlanChanges[id], !p.changesSessions, applyPlanChange(id, now: now) { return nil }
        return id
    }

    // MARK: training pause
    func pauseTraining(reason: TrainingPause.Reason, now: Date = Date()) {
        updateProfile { $0.trainingPause = TrainingPause(since: now, reason: reason) }
    }
    func resumeTraining(now: Date = Date()) {
        guard let p = profile.trainingPause else { return }
        updateProfile { $0.pauseHistory.append(DateInterval(start: min(p.since, now), end: now)); $0.trainingPause = nil }
    }
    /// Mondays of weeks that were (at least 4 days) paused — not counted by checkpoints or adherence.
    func pausedWeeks(now: Date = Date()) -> Set<Date> {
        let cal = Calendar.current
        var spans = profile.pauseHistory
        if let p = profile.trainingPause { spans.append(DateInterval(start: min(p.since, now), end: now)) }
        var out: Set<Date> = []
        for s in spans {
            var m = TrainingLedger.monday(of: s.start, calendar: cal)
            while m < s.end {
                let e = cal.date(byAdding: .day, value: 7, to: m)!
                let overlap = max(0, min(e, s.end).timeIntervalSince(max(m, s.start)))
                if overlap >= 4 * 86_400 { out.insert(m) }
                m = e
            }
        }
        return out
    }

    // MARK: Progress inputs (one source for Plan, workout screens and Progress)
    /// Completed ride dates (recorded / imported rides + planned rides marked done) and strength dates (counted logs +
    /// strength sessions marked done).
    func completedDates(_ sport: Checkpoint.Sport) -> [Date] { sport == .cycling ? ridingDays() : liftingDays() }
    func liftSummaries(since: Date? = nil) -> [LiftSummary] { StrengthPerformance.lifts(logs: strength, since: since) }
    /// FTP evidence for checkpoints: FTP-test rides with verified power (0.95 × best 20 min).
    func ftpEvidence() -> [(date: Date, watts: Int)] {
        let cal = Calendar.current
        let testDays = plan.filter { $0.kind == .ftpTest }.map { cal.startOfDay(for: $0.date) }
        return rides.filter { r in !r.demo && r.powerVerified == true && testDays.contains(cal.startOfDay(for: r.start)) }
            .compactMap { r in r.bestMeanPower(seconds: 1200).map { (r.start, Store.proposedFTP(best20: $0)) } }
    }
    func checkpoints(_ sport: Checkpoint.Sport, now: Date = Date()) -> [Checkpoint] {
        let perf: Checkpoint.Performance = sport == .cycling ? Checkpoints.cyclingPerformance(ftpEvidence: ftpEvidence()) : Checkpoints.strengthPerformance(liftSummaries())
        return Checkpoints.compute(sport: sport, completed: completedDates(sport), pausedWeeks: pausedWeeks(now: now), performance: perf, now: now)
    }

    // MARK: goals (r7 S2)
    /// Saves goals with one primary and keeps the build-121 fields the planner and the board read in step.
    func setGoals(_ g: [GoalID], primary: GoalID?) -> PlanInputs {
        var x = planInputs
        x.profile.goals = g
        x.profile.primaryGoal = primary ?? g.first
        if let c = (x.profile.primaryGoal?.cyclingGoal ?? g.compactMap(\.cyclingGoal).first) { x.profile.goal = c }
        if let s = (x.profile.primaryGoal?.strengthGoal ?? g.compactMap(\.strengthGoal).first) { x.strengthPrefs.goal = s }
        return x
    }
}

// MARK: Schema 3 migration (idempotent; never deletes; original values kept in the log)
extension StoreMigration {
    static func v3(_ f0: StoreFile, now: Date = Date(), calendar cal: Calendar = .current) -> StoreFile {
        var f = f0
        guard f.schema < 3 else { return f }
        var log: [String] = []
        // E1 / AT-E1-2: the W/kg starting assumption becomes Unknown (value kept only as history, never for targets)
        if f.profile.ftpHow == .assumed {
            log.append("FTP: the starting assumption (\(f.profile.ftpW) W) is now 'Unknown'. Rides use effort and heart-rate targets until you enter or test your FTP.")
        }
        // r7 goals: the build-121 goal becomes the primary cycling goal; the original value is kept
        if f.profile.goals.isEmpty {
            var g: [GoalID] = []
            if f.profile.trainingMode.includesCycling { g.append(GoalID.from(cyclingGoal: f.profile.goal)) }
            if f.profile.trainingMode.includesLifting {
                let s: GoalID
                switch f.strengthPrefs.goal ?? (f.profile.hybridGoal == .strength ? .strength : .general) {
                case .strength: s = .strength; case .hypertrophy: s = .muscle; case .enduranceSupport: s = .stamina; case .general: s = .maintain
                }
                g.append(s)
            }
            if g.isEmpty { g = [GoalID.from(cyclingGoal: f.profile.goal)] }
            f.profile.goals = g
            f.profile.primaryGoal = (f.profile.priority == .strength ? g.first { $0.sport == .strength } : nil) ?? g.first
            if f.profile.legacyGoal == nil { f.profile.legacyGoal = f.profile.goal.rawValue }
        }
        // A1 / AT-A1-2: lifting experience is never copied from the cycling level — Beginner until confirmed once
        if f.profile.trainingMode.includesLifting, f.strengthPrefs.experience == nil {
            f.profile.confirmStrengthLevel = true
            log.append("Strength level: not set before. Sessions use Beginner doses until you confirm it in Profile.")
        }
        // C2 / AT-C2-3: the session length the athlete was actually getting (hours ÷ sessions), flagged to confirm once
        if f.profile.trainingMode.includesLifting, f.profile.strengthSessionMinutes == nil, f.profile.liftDaysPerWeek > 0 {
            f.profile.strengthSessionMinutes = max(20, max(1, f.profile.liftingHoursPerWeek) * 60 / f.profile.liftDaysPerWeek)
            f.profile.confirmSessionLength = true
            log.append("Strength session length: \(f.profile.strengthSessionMinutes!) min (from \(f.profile.liftingHoursPerWeek) h over \(f.profile.liftDaysPerWeek) sessions) — please confirm it in Profile.")
        }
        // H1 / AT-H1-3: equipment not set stays 'not set' (provisional bodyweight), never 'owns everything'
        if !f.equipment.isSet, f.profile.trainingMode.includesLifting {
            log.append("Equipment: not set yet, so new coach-built sessions use bodyweight exercises until you set it.")
        }
        f.schema = 3
        if !log.isEmpty { f.migrationLog += log }
        return f
    }
}

// MARK: Schema 4 migration — S2-0 data integrity (ios/S20_DATA_INTEGRITY.md). Idempotent; never deletes a workout, log or ride.
extension StoreMigration {
    /// Values of earlier builds: a value that equals the old fabricated default and shows no sign of athlete entry becomes
    /// Unknown; every other value is kept but marked `.legacyUnverified` with `needsConfirmation` — it is never relabelled
    /// as entered because its provenance cannot be established from the file.
    static func v4(_ f0: StoreFile, now: Date = Date(), calendar cal: Calendar = .current) -> StoreFile {
        var f = f0
        guard f.schema < 4 else { return f }
        var log: [String] = []
        var p = f.profile
        // Weight: build ≤ 127 wrote 75.0 for every athlete who never touched the stepper. Exactly 75.0 with no provenance
        // cannot be told apart from a real 75.0 → Unknown, and the athlete is asked once (a real 75 kg takes two taps).
        if let w = p.weightKg, p.provenance[ProfileField.weight.rawValue] == nil {
            if w == 75.0 { p.weightKg = nil; log.append("Weight: the earlier build showed 75 kg as a sample value. It is now 'Not set' — enter your weight in Profile for W/kg and lifting loads.") }
            else { p.setProvenance(.weight, .legacy(p.updatedAt)); log.append("Weight \(String(format: "%.1f", w)) kg: kept from the earlier build; please confirm it in Profile.") }
        }
        // Age: the 35-year default never came from the athlete. A date of birth or a birth year is the only real source.
        if p.dateOfBirth == nil, p.birthYear == nil, let a = p.age {
            // the slider's default was 35: exactly 35 is indistinguishable from "never touched" → Unknown; any other value
            // was moved by the athlete and is kept as unverified
            if a == 35 { p.age = nil; log.append("Age: the earlier build assumed 35. Heart-rate zones are unavailable until you enter your date of birth or max heart rate.") }
            else { p.setProvenance(.dateOfBirth, .legacy(p.updatedAt)); log.append("Age \(a): kept from the earlier build; please enter your date of birth in Profile to confirm it.") }
        }
        if p.dateOfBirth != nil || p.birthYear != nil {
            p.age = nil     // a birth date / year is the real source; the old slider value is redundant
            if p.provenance[ProfileField.dateOfBirth.rawValue] == nil { p.setProvenance(.dateOfBirth, .legacy(p.updatedAt)) }
        }
        // FTP: the W/kg assumption (ftpHow == .assumed) is Unknown; any other value keeps its label but is flagged legacy.
        if p.ftpHow == .assumed || p.ftpW <= 0 {
            if p.ftpW > 0 { log.append("FTP: the starting assumption (\(p.ftpW) W) is removed. FTP is Unknown until you enter or test it; rides use effort and heart-rate targets.") }
            p.ftpW = 0; p.ftpHow = .assumed; p.setProvenance(.ftp, nil)
        } else if p.provenance[ProfileField.ftp.rawValue] == nil {
            let src: ValueSource = p.ftpHow == .fromRides ? .estimatedFromRides : (p.ftpHow == .tested && p.ftpVerifiedTest == true) ? .measuredTest : .legacyUnverified
            p.setProvenance(.ftp, ValueProvenance(source: src, recordedAt: p.ftpFromDate ?? p.updatedAt, needsConfirmation: src == .legacyUnverified))
            if src == .legacyUnverified { log.append("FTP \(p.ftpW) W (\(p.ftpHow.label)): kept from the earlier build as unverified; please confirm it in Profile.") }
        }
        if let m = p.maxHR, m > 0, p.provenance[ProfileField.maxHR.rawValue] == nil { p.setProvenance(.maxHR, .legacy(p.updatedAt)) }
        if let r = p.restHR, r > 0, p.provenance[ProfileField.restHR.rawValue] == nil { p.setProvenance(.restHR, .legacy(p.updatedAt)) }
        f.profile = p
        // Energy (GR-45): build ≤ 127 stored a Health-imported ride's active kcal × 4.184 in `kj` and showed it "from power".
        // The conversion is exact and the source is unambiguous (recorder == .health), so it is converted back and labelled.
        for i in f.rides.indices where f.rides[i].energy == nil {
            if f.rides[i].recorder == .health, let k = f.rides[i].kj {
                f.rides[i].energy = EnergyValue(kind: .activeKcalAppleHealth, value: Int((Double(k) / 4.184).rounded()))
                f.rides[i].kj = nil
            } else if let k = f.rides[i].kj, f.rides[i].avgPower != nil {
                f.rides[i].energy = EnergyValue(kind: .workFromPowerKJ, value: k)
            } else if let k = f.rides[i].kj {
                f.rides[i].energy = EnergyValue(kind: .legacyUnverified, value: k)      /* a kJ figure without power: origin unknown */
            }
        }
        let converted = f0.rides.filter { $0.recorder == .health && $0.kj != nil }.count
        if converted > 0 { log.append("Apple Health rides: \(converted) energy figure(s) were stored in the wrong unit and shown as work from power. They are now shown as Apple Health active energy (kcal, an estimate).") }
        f.schema = 4
        if !log.isEmpty { f.migrationLog += log }
        return f
    }
}
