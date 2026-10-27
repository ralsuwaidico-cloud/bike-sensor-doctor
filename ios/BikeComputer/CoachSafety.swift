import Foundation

// MARK: - Coach safety layer (coach remediation, ios/COACH_REMEDIATION.md)
//
// M-01  Health screening before vigorous prescriptions (threshold / VO2 / FTP-test rides, heavy lifting at RPE ≥ 8).
//       Questions paraphrase the general section of the PAR-Q+ (Warburton et al. 2011, Health & Fitness Journal of
//       Canada 4(2):3–23) plus pregnancy, following the ACSM pre-participation screening logic (Riebe et al. 2015,
//       MSSE 47(11):2473–2479): symptoms or known disease → medical clearance before vigorous exercise.
//       This is a COACHING GATE, not a medical assessment: the app never diagnoses and never stores more than yes/no.
// M-02  Return to training after a break: loads and intensity restart below the last logged ones (detraining:
//       Mujika & Padilla 2000, Sports Med 30(2):79–87 / 30(3):145–154). The exact percentages are coaching heuristics.

/// Pre-participation health check. Stored on the rider profile; nil = never answered.
struct HealthScreen: Codable, Equatable {
    var answeredAt: Date? = nil
    /// A doctor has said there is a heart condition or high blood pressure.
    var heartOrBloodPressure = false
    /// Chest pain at rest, in daily activities or during exercise.
    var chestPain = false
    /// Lost balance through dizziness or lost consciousness in the last 12 months.
    var dizzinessOrFainting = false
    /// Another chronic medical condition has been diagnosed.
    var otherChronicCondition = false
    /// Currently taking prescribed medication for a chronic condition.
    var chronicMedication = false
    /// A bone, joint or soft-tissue problem that more activity could make worse.
    var boneJointProblem = false
    /// A doctor has said exercise should only be medically supervised.
    var supervisedOnly = false
    /// Currently pregnant or gave birth in the last 6 months.
    var pregnancy = false
    /// The rider confirms a doctor or qualified health professional cleared them for vigorous training.
    var clearedAt: Date? = nil

    enum Status: String, Codable { case notAnswered, clear, needsClearance, cleared }

    var anyYes: Bool { heartOrBloodPressure || chestPain || dizzinessOrFainting || otherChronicCondition || chronicMedication || boneJointProblem || supervisedOnly || pregnancy }

    var status: Status {
        guard answeredAt != nil else { return .notAnswered }
        if !anyYes { return .clear }
        // supervised-only and chest pain are never self-cleared for unsupervised vigorous work by an app button alone:
        // the rider must state a clearance, which is recorded with its date
        return clearedAt != nil ? .cleared : .needsClearance
    }

    static let questions: [(key: WritableKeyPath<HealthScreen, Bool>, text: String)] = [
        (\.heartOrBloodPressure, "Has a doctor ever said you have a heart condition or high blood pressure?"),
        (\.chestPain, "Do you get chest pain at rest, in daily activities or when you exercise?"),
        (\.dizzinessOrFainting, "In the last 12 months, have you lost your balance through dizziness or lost consciousness?"),
        (\.otherChronicCondition, "Have you been diagnosed with another chronic medical condition?"),
        (\.chronicMedication, "Do you take prescribed medication for a chronic condition?"),
        (\.boneJointProblem, "Do you have a bone, joint or soft-tissue problem that more activity could make worse?"),
        (\.supervisedOnly, "Has a doctor said you should only exercise under medical supervision?"),
        (\.pregnancy, "Are you pregnant, or did you give birth in the last 6 months?"),
    ]
}

/// What the coach may prescribe, derived from the health check, the break state and age. One place, read by the
/// cycling plan, the strength planner and the adaptive engine.
struct CoachReadiness: Equatable {
    var screen: HealthScreen.Status
    /// Vigorous prescriptions (threshold, VO2, FTP test; lifting at RPE ≥ 8) are allowed.
    var vigorousAllowed: Bool { screen == .clear || screen == .cleared }
    /// Highest strength RPE the planner may prescribe.
    var maxStrengthRPE: Int { vigorousAllowed ? 10 : 7 }
    /// Highest ride zone the generator may plan (fixed rides the rider typed are kept and warned instead).
    var maxRideZone: Int { vigorousAllowed ? 5 : 2 }

    /// Short reason for notes and Why? texts; nil when nothing is restricted.
    var restriction: String? {
        switch screen {
        case .clear, .cleared: return nil
        case .notAnswered: return "the health check in Profile has not been answered yet, so hard intervals and near-maximal lifting are not planned"
        case .needsClearance: return "your health check answers mean a doctor should clear you before hard training, so hard intervals and near-maximal lifting are not planned until you confirm that clearance in Profile"
        }
    }

    init(profile p: RiderProfile) { screen = p.healthScreen?.status ?? .notAnswered }
    init(screen: HealthScreen.Status) { self.screen = screen }
}

// MARK: - Return to training (M-02)
/// Where the rider is relative to a training break, from logged dates only (never from planned sessions).
struct ReturnPhase: Equatable {
    /// Days of the break that ended most recently (or that is still going on).
    var breakDays: Int
    /// Sessions logged since the break ended.
    var sessionsSince: Int
    /// The break is still going on (nothing logged since).
    var ongoing: Bool

    /// A gap of at least this many days counts as a break.
    static let breakThresholdDays = 21
    /// The return phase lasts this many logged sessions.
    static let phaseSessions = 3

    var active: Bool { sessionsSince < ReturnPhase.phaseSessions }

    /// Load multiplier for the first sessions back, by length of the break (coaching heuristic, see header).
    var loadFactor: Double {
        switch breakDays {
        case ..<28: return 0.95
        case 28..<56: return 0.9
        case 56..<112: return 0.8
        default: return 0.7
        }
    }
    var weeksText: String { breakDays >= 14 ? "\(breakDays / 7) weeks" : "\(breakDays) days" }

    /// nil = no recent break (or no history at all: a new rider is not "returning").
    static func detect(dates raw: [Date], now: Date, calendar cal: Calendar = .current) -> ReturnPhase? {
        let today = cal.startOfDay(for: now)
        let days = Array(Set(raw.filter { $0 <= now }.map { cal.startOfDay(for: $0) })).sorted(by: >)
        guard let latest = days.first else { return nil }
        let sinceLatest = cal.dateComponents([.day], from: latest, to: today).day ?? 0
        if sinceLatest >= breakThresholdDays { return ReturnPhase(breakDays: sinceLatest, sessionsSince: 0, ongoing: true) }
        // the most recent gap ≥ threshold between consecutive training days, and the sessions after it
        var count = 1
        for i in 1..<max(1, days.count) where i < days.count {
            let gap = cal.dateComponents([.day], from: days[i], to: days[i - 1]).day ?? 0
            if gap >= breakThresholdDays {
                let r = ReturnPhase(breakDays: gap, sessionsSince: count, ongoing: false)
                return r.active ? r : nil
            }
            count += 1
            if count >= phaseSessions { return nil }
        }
        return nil
    }
}

extension RiderProfile {
    var readiness: CoachReadiness { CoachReadiness(profile: self) }
}

extension Store {
    /// Riding days the coach can see: recorded or imported rides, and planned rides the rider marked done.
    func ridingDays() -> [Date] {
        rides.filter { !$0.demo }.map { $0.start } + plan.filter { $0.kind.isRide && $0.completion == .marked }.map { $0.date }
    }
    /// Lifting days: counted strength logs and strength sessions marked done.
    func liftingDays() -> [Date] {
        strength.filter { !$0.awaitingReview && !$0.inProgress }.map { $0.date } + plan.filter { $0.kind == .strength && $0.completion == .marked }.map { $0.date }
    }
    /// M-02 for cycling: only riders with some riding history (≥ 3 riding days) can be "returning".
    func cyclingReturnPhase(now: Date = Date()) -> ReturnPhase? {
        let d = ridingDays()
        guard Set(d.map { Calendar.current.startOfDay(for: $0) }).count >= 3 else { return nil }
        return ReturnPhase.detect(dates: d, now: now)
    }
    func liftingReturnPhase(now: Date = Date()) -> ReturnPhase? {
        let d = liftingDays()
        guard Set(d.map { Calendar.current.startOfDay(for: $0) }).count >= 3 else { return nil }
        return ReturnPhase.detect(dates: d, now: now)
    }
}

// MARK: - Age, recovery capacity (M-06), rest intervals (M-03), starting loads (M-04)
//
// Older adults: resistance training stays effective and is recommended 2–3 days a week with progressive loading
// (Fragala et al. 2019, NSCA position statement, J Strength Cond Res 33(8):2019–2052); recovery between sessions for
// the same muscles takes longer, so volume per week and the deload cadence are adjusted. The factors below (×0.8 volume,
// deload every 3rd week, ≥ 72 h between sessions loading the same muscles) are COACHING HEURISTICS, not evidence-derived
// thresholds. Rest between sets follows ACSM 2009 (Ratamess et al., MSSE 41(3):687–708): 2–3 min for heavy multi-joint
// lifts, 1–2 min for lighter / assistance work; hypertrophy work benefits from rests above 60 s (Grgic et al. 2018,
// Sports Med 48(1):137–151; Schoenfeld et al. 2016, JSCR 30(7):1805–1812).

enum RecoveryCapacity: String, Codable, CaseIterable {
    case low, normal, high
    var title: String { switch self { case .low: return "Slower than most"; case .normal: return "About average"; case .high: return "Faster than most" } }
    var hint: String { switch self { case .low: return "often still tired or sore two days after a hard session"; case .normal: return "fresh again within a day or two"; case .high: return "rarely sore, recovers overnight" } }
}

/// Programming adjustments from age and stated recovery capacity. One place, read by the planner and the week builder.
struct RecoveryProfile: Equatable {
    var age: Int
    var capacity: RecoveryCapacity
    var older: Bool { age >= 60 }
    var reduced: Bool { older || capacity == .low }
    /// Weekly working sets multiplier.
    var volumeFactor: Double { (older && capacity == .low) ? 0.7 : reduced ? 0.8 : (capacity == .high ? 1.1 : 1.0) }
    /// A lighter week every N weeks of consecutive training.
    var deloadEvery: Int { reduced ? 3 : 4 }
    /// Minimum hours between two sessions loading the same muscles.
    var minHoursSameMuscles: Int { reduced ? 72 : 48 }
    var reason: String? {
        switch (older, capacity) {
        case (true, .low): return "you are \(age) and said you recover slower than most"
        case (true, _): return "you are \(age); recovery between sessions takes longer with age"
        case (false, .low): return "you said you recover slower than most"
        case (false, .high): return "you said you recover faster than most"
        default: return nil
        }
    }
    init(profile p: RiderProfile) { age = p.effectiveAge; capacity = p.recoveryCapacity ?? .normal }
}

extension RiderProfile { var recovery: RecoveryProfile { RecoveryProfile(profile: self) } }

enum RestPrescription {
    /// Seconds between sets for a role and goal.
    static func seconds(role: StrengthPlanner.Role, goal: StrengthPrefs.Goal, reduced: Bool) -> Int {
        var s: Int
        switch (role, goal) {
        case (.main, .strength): s = 180
        case (.main, _): s = 150
        case (.secondary, .strength): s = 150
        case (.secondary, _): s = 105
        case (.accessory, _): s = 75
        case (.core, _): s = 60
        }
        if reduced, role == .main || role == .secondary { s += 30 }
        return s
    }
    static func text(_ s: Int) -> String {
        if s >= 120 { let m = Double(s) / 60; return m == m.rounded() ? "\(Int(m)) min" : String(format: "%.1f min", m).replacingOccurrences(of: ".5", with: "½") }
        return "\(s) s"
    }
}

enum StartingLoad {
    /// How to find a first working weight without guessing a number for the rider (no bodyweight formula is reliable).
    static func guidance(_ e: Exercise, reps range: ClosedRange<Int>, beginner: Bool) -> String {
        let eq = Set(e.equipment.map { $0.lowercased() })
        var first: String
        if eq.contains("barbell") { first = "Start with the empty bar (usually 20 kg, 15 kg for a women's bar)" }
        else if eq.contains("dumbbell") || eq.contains("kettlebell") { first = "Start with a weight you could lift 15 or more times" }
        else if eq.contains("machine") || eq.contains("cable") { first = "Start near the lightest setting" }
        else { first = "Start light" }
        let stopAt = beginner ? 4 : 3
        return "New exercise — find your working weight. \(first), do \(range.upperBound) easy reps, then add a small step each set (about 5–10 %) until \(range.lowerBound) reps feel like you could do \(stopAt) more. Use that weight for the working sets and log it; the coach progresses from your log. No weight is copied from another exercise."
    }
}
