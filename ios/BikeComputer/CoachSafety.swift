import Foundation

// MARK: - Coach safety layer (coach remediation, ios/COACH_REMEDIATION.md)
//
// M-01  Health screening before training is planned. The questions paraphrase the general section of the PAR-Q+
//       (Warburton et al. 2011, Health & Fitness Journal of Canada 4(2):3–17; www.eparmedx.com) plus pregnancy and a
//       current-illness question, and follow the ACSM pre-participation screening logic (Riebe et al. 2015, MSSE
//       47(11):2473–2479): signs or symptoms (chest pain, fainting / dizziness) → stop and get medical clearance before any
//       exercise programme; known disease / medication → moderate exercise, medical clearance before vigorous work.
//       Independent review F-01/F-13: symptoms and "supervised only" STOP plan generation; supervised-only can never be
//       cleared in the app; clearance for symptoms needs an explicit statement with a date; every question needs an
//       explicit answer (none pre-set); answers expire after 12 months. This is a COACHING GATE, not a medical
//       assessment: the app never diagnoses and stores yes/no only.
// M-02  Return to training after a break: loads and riding time restart below the last logged ones and ramp back
//       (detraining: Mujika & Padilla 2000, Sports Med 30(2):79–87). The exact percentages are coaching heuristics.

/// Pre-participation health check. Stored on the rider profile; nil = never answered.
struct HealthScreen: Codable, Equatable {
    var answeredAt: Date? = nil
    /// A doctor has said there is a heart condition or high blood pressure.
    var heartOrBloodPressure = false
    /// Chest pain at rest, in daily activities or during exercise.
    var chestPain = false
    /// Lost balance through dizziness or lost consciousness in the last 12 months (not from over-breathing in hard exercise).
    var dizzinessOrFainting = false
    /// Another chronic medical condition has been diagnosed.
    var otherChronicCondition = false
    /// Currently taking prescribed medication for a chronic condition.
    var chronicMedication = false
    /// A bone, joint or soft-tissue problem that more activity could make worse (a past problem that no longer limits
    /// you does not count).
    var boneJointProblem = false
    /// A doctor has said exercise should only be medically supervised.
    var supervisedOnly = false
    /// Currently pregnant or gave birth in the last 6 months.
    var pregnancy = false
    /// Currently ill (e.g. a fever or infection) or recovering from an illness or operation.
    var currentIllness = false
    /// The rider states that a doctor examined them and cleared them for unrestricted training, on this date.
    var clearedAt: Date? = nil
    /// The question set these answers belong to; answers to an older set count as not answered (asked again).
    var questionSet: Int? = HealthScreen.currentQuestionSet
    static let currentQuestionSet = 2

    enum Status: String, Codable { case notAnswered, clear, needsClearance, cleared, stop, paused }

    init() {}
    /// Tolerant decoding (review N-12): answers saved by earlier builds decode with their known questions; a missing
    /// question stays false and the older question set counts as not answered, so the form asks again pre-filled.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        answeredAt = try? c.decodeIfPresent(Date.self, forKey: .answeredAt)
        heartOrBloodPressure = (try? c.decodeIfPresent(Bool.self, forKey: .heartOrBloodPressure)) ?? false
        chestPain = (try? c.decodeIfPresent(Bool.self, forKey: .chestPain)) ?? false
        dizzinessOrFainting = (try? c.decodeIfPresent(Bool.self, forKey: .dizzinessOrFainting)) ?? false
        otherChronicCondition = (try? c.decodeIfPresent(Bool.self, forKey: .otherChronicCondition)) ?? false
        chronicMedication = (try? c.decodeIfPresent(Bool.self, forKey: .chronicMedication)) ?? false
        boneJointProblem = (try? c.decodeIfPresent(Bool.self, forKey: .boneJointProblem)) ?? false
        supervisedOnly = (try? c.decodeIfPresent(Bool.self, forKey: .supervisedOnly)) ?? false
        pregnancy = (try? c.decodeIfPresent(Bool.self, forKey: .pregnancy)) ?? false
        currentIllness = (try? c.decodeIfPresent(Bool.self, forKey: .currentIllness)) ?? false
        clearedAt = try? c.decodeIfPresent(Date.self, forKey: .clearedAt)
        questionSet = try? c.decodeIfPresent(Int.self, forKey: .questionSet)
    }

    static let validityDays = 365

    /// Symptoms / supervision: no training is planned until cleared (supervised-only: never in the app).
    var stopAnswers: Bool { chestPain || dizzinessOrFainting || supervisedOnly }
    var anyYes: Bool { heartOrBloodPressure || chestPain || dizzinessOrFainting || otherChronicCondition || chronicMedication || boneJointProblem || supervisedOnly || pregnancy || currentIllness }
    /// A doctor's clearance can be recorded in the app: not for "supervised only", and not needed for a temporary
    /// illness (the rider answers again when recovered).
    var clearable: Bool { (heartOrBloodPressure || chestPain || dizzinessOrFainting || otherChronicCondition || chronicMedication || boneJointProblem || pregnancy) && !supervisedOnly }
    /// The recorded clearance counts only when it is recent relative to the answers (review N-08: within the 12 months
    /// before them, or after them).
    var clearanceValid: Bool { guard let c = clearedAt, let a = answeredAt else { return false }; return c >= a.addingTimeInterval(-Double(Self.validityDays) * 86_400) }

    func status(now: Date = Date()) -> Status {
        // review N-07: a "see a doctor" result never expires into "not answered" — it stays until answered again
        let stopNow = supervisedOnly || (stopAnswers && !clearanceValid)
        guard let at = answeredAt, now.timeIntervalSince(at) < Double(Self.validityDays) * 86_400, questionSet == Self.currentQuestionSet else {
            return answeredAt != nil && stopNow ? .stop : .notAnswered
        }
        if !anyYes { return .clear }
        if stopNow { return .stop }
        // review N-05 / PAR-Q+: a temporary illness delays training; no doctor needed — answer again when recovered
        if currentIllness { return .paused }
        if !clearable { return .clear }
        return clearanceValid ? .cleared : .needsClearance
    }
    var status: Status { status() }

    static let questions: [(key: WritableKeyPath<HealthScreen, Bool>, text: String)] = [
        (\.heartOrBloodPressure, "Has a doctor ever said you have a heart condition or high blood pressure?"),
        (\.chestPain, "Do you get chest pain at rest, in daily activities or when you exercise?"),
        (\.dizzinessOrFainting, "In the last 12 months, have you lost your balance through dizziness or lost consciousness? (Not light-headedness from breathing hard during intense exercise.)"),
        (\.otherChronicCondition, "Have you been diagnosed with another chronic medical condition?"),
        (\.chronicMedication, "Do you take prescribed medication for a chronic condition?"),
        (\.boneJointProblem, "Do you have a bone, joint or soft-tissue problem now that more activity could make worse?"),
        (\.supervisedOnly, "Has a doctor said you should only exercise under medical supervision?"),
        (\.pregnancy, "Are you pregnant, or did you give birth in the last 6 months?"),
        (\.currentIllness, "Are you ill right now, or recovering from an illness or operation?"),
    ]
}

/// What the coach may prescribe, derived from the health check. One place, read by the week builder, the strength
/// planner, the ride safety refresh and the adaptive engine.
struct CoachReadiness: Equatable {
    var screen: HealthScreen.Status
    /// Any training may be planned (false: symptoms / supervised-only → "see a doctor", no sessions generated).
    var trainingAllowed: Bool { screen != .stop && screen != .paused }
    /// Vigorous prescriptions (tempo and harder rides, heavy lifting, load progression) are allowed.
    var vigorousAllowed: Bool { screen == .clear || screen == .cleared }
    /// Highest strength RPE the planner may prescribe (independent review F-02: lower while clearance is pending).
    var maxStrengthRPE: Int { switch screen { case .clear, .cleared: return 10; case .notAnswered: return 7; case .needsClearance, .stop, .paused: return 6 } }
    /// Fewest reps per set while not cleared (no heavy 4–6 rep work).
    var minStrengthReps: Int? { vigorousAllowed ? nil : 8 }
    /// Highest ride zone the generator may plan.
    var maxRideZone: Int { vigorousAllowed ? 5 : 2 }
    /// Longest generated ride while not cleared (F-14), minutes.
    var maxRideMinutes: Int? { vigorousAllowed ? nil : 120 }

    /// Short reason for notes and Why? texts; nil when nothing is restricted.
    var restriction: String? {
        switch screen {
        case .clear, .cleared: return nil
        case .notAnswered: return "the health check in Profile has not been answered (or is more than a year old), so only easy-to-moderate training is planned"
        case .needsClearance: return "your health check answers mean a doctor should clear you before hard training, so only easy-to-moderate training is planned until you record that clearance in Profile"
        case .stop: return "your health check answers mean you should see a doctor before training, so Cyclift plans no sessions until then"
        case .paused: return "you said you are ill or recovering, so Cyclift plans no sessions until you answer the health check again when you feel well"
        }
    }

    init(profile p: RiderProfile, now: Date = Date()) { screen = p.healthScreen?.status(now: now) ?? .notAnswered }
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
    /// Riding time for the first rides back (F-08): shorter after longer breaks, ramping back to 100 % over the phase.
    var rideFactor: Double {
        let f: Double
        switch breakDays { case ..<28: f = 0.85; case 28..<56: f = 0.75; case 56..<112: f = 0.65; default: f = 0.6 }
        return min(1, f + (1 - f) * Double(sessionsSince) / Double(ReturnPhase.phaseSessions))
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
// lifts, 1–2 min for lighter / assistance work; hypertrophy work benefits from rests above 60 s (Grgic et al. 2017,
// Eur J Sport Sci 17(8):983–993 — volume and pages not verified; Schoenfeld et al. 2016, JSCR 30(7):1805–1812).

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

/// M-05 / F-04 / F-09: one block clock for both sports. A week counts as a training week when something was logged in it
/// (rides, lifts, sessions marked done) — or, for the current and later weeks, when sessions are planned in it (so a week
/// generated on Monday morning, before anything is logged, still knows where it sits in the block).
enum BlockClock {
    static func weeks(before monday: Date, activity: Set<Date>, plannedMondays: Set<Date>, now: Date, calendar cal: Calendar = .current) -> Int {
        let currentMonday = TrainingLedger.monday(of: now, calendar: cal)
        var n = 0
        for k in 1...26 {
            let m = cal.date(byAdding: .day, value: -7 * k, to: monday)!, e = cal.date(byAdding: .day, value: 7, to: m)!
            let trained = activity.contains { $0 >= m && $0 < e }
            let planned = m >= currentMonday && plannedMondays.contains(m)
            if trained || planned { n += 1 } else { break }
        }
        return n
    }
}

extension Store {
    var activityDays: Set<Date> { Set((ridingDays() + liftingDays()).map { Calendar.current.startOfDay(for: $0) }) }
    var plannedMondays: Set<Date> { Set(plan.filter { $0.kind.isRide || $0.kind == .strength }.map { TrainingLedger.monday(of: $0.date) }) }
    /// M-05: training weeks in a row right before `monday` (shared by the cycling easy week and the strength deload).
    func consecutiveTrainingWeeks(before monday: Date, now: Date = Date(), calendar cal: Calendar = .current) -> Int {
        BlockClock.weeks(before: monday, activity: activityDays, plannedMondays: plannedMondays, now: now, calendar: cal)
    }
}

struct SafetyOriginal: Codable, Equatable {
    var kind: WorkoutKind; var minutes: Int; var intervalReps: Int?; var note: String
    /// The adaptive coach's original snapshot before the cap was applied to it (F-05), restored with the session.
    var coachSnapshot: WorkoutPlanSnapshot? = nil
}

extension Store {
    /// M-01 / M-02 for sessions generated BEFORE the health check or a break was known (weeks are generated up to two
    /// weeks ahead): at launch, day change and check-ins, future coach-generated sessions are capped like the week builder
    /// would cap them now — and restored to what was generated once the cap no longer applies (screen answered or
    /// cleared, return phase over). Rides the adaptive coach adjusted are capped on their original too (F-05), so a later
    /// coach run cannot lift the cap. Fixed and hand-edited sessions are only stopped for a "see a doctor" answer; a
    /// session is never made harder than it was generated.
    func refreshRideSafety(now: Date = Date()) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let readiness = CoachReadiness(profile: profile, now: now)
        let back = cyclingReturnPhase(now: now)
        var p = plan, changed = false
        for i in p.indices {
            let w = p[i]
            guard !w.done, !w.skipped, w.completion == nil, cal.startOfDay(for: w.date) >= today, activeSession?.workoutId != w.id else { continue }
            let isRideOrStopped = w.kind.isRide || (w.kind == .rest && w.safetyOriginal != nil) || (!readiness.trainingAllowed && w.kind == .strength)
            guard isRideOrStopped else { continue }
            let userOwned = w.fixed || w.edited
            // review N-01: a session the rider edited is theirs — its safety original is dropped (never restored over
            // the edit); only a "see a doctor" / illness answer still pauses it
            if w.edited && readiness.trainingAllowed {
                if w.safetyOriginal != nil, w.kind != .rest { var x = w; x.safetyOriginal = nil; p[i] = x; changed = true }
                if w.kind != .rest { continue }
            }
            if userOwned && readiness.trainingAllowed && w.safetyOriginal == nil { continue }
            // the base: what was generated (before any safety cap), with the adaptive coach's own change on top
            let o = w.safetyOriginal ?? SafetyOriginal(kind: w.kind, minutes: w.minutes, intervalReps: w.intervalReps, note: w.note)
            var x = w
            x.kind = o.kind; x.minutes = o.minutes; x.intervalReps = o.intervalReps; x.note = o.note
            if let so = w.safetyOriginal?.coachSnapshot { x.coachOriginal = so }
            var origSnap = x.coachOriginal
            func capRide(_ k: inout WorkoutKind, _ m: inout Int, _ r: inout Int?, base: Int) -> String? {
                var why: String? = nil
                if k.zone > readiness.maxRideZone, let t = readiness.restriction { k = .endurance; r = nil; why = "Planned easy because \(t)." }
                if let cap = readiness.maxRideMinutes, m > cap, let t = readiness.restriction { m = cap; why = "Kept to \(Fmt.duration(minutes: cap)) because \(t)." }
                if let b = back, b.active, k.zone >= 3 || k == .long || m > 60 {
                    if k.zone >= 3 || k == .long { k = .endurance; r = nil }
                    m = max(30, Int((Double(base) * b.rideFactor / 5).rounded()) * 5)
                    why = "Back after \(b.weeksText) off: steady riding at about \(Int((b.rideFactor * 100).rounded())) % of the usual time, building back over \(ReturnPhase.phaseSessions) rides."
                }
                return why
            }
            if !readiness.trainingAllowed {
                x.kind = .rest; x.minutes = 0; x.intervalReps = nil
                x.note = "No training planned: \(readiness.restriction ?? "see a doctor first")."
            } else if x.kind.isRide, !userOwned {
                var k = x.kind, m = x.minutes, r = x.intervalReps
                if let why = capRide(&k, &m, &r, base: o.minutes) { x.kind = k; x.minutes = m; x.intervalReps = r; x.note = why }
                if var snap = origSnap {
                    var sk = snap.kind, sm = snap.minutes, sr = snap.intervalReps
                    _ = capRide(&sk, &sm, &sr, base: snap.minutes)
                    snap.kind = sk; snap.minutes = sm; snap.intervalReps = sr
                    origSnap = snap
                }
            }
            let capped = x.kind != o.kind || x.minutes != o.minutes || x.intervalReps != o.intervalReps
            if capped {
                var so = o; so.coachSnapshot = w.safetyOriginal?.coachSnapshot ?? w.coachOriginal
                x.safetyOriginal = so
                if origSnap != x.coachOriginal { x.coachOriginal = origSnap }
            } else { x.safetyOriginal = nil; x.note = o.note }
            if x != w { p[i] = x; changed = true }
        }
        if changed { plan = p }
    }
}

extension Store {
    /// Independent review F-06: the rider's own routine after a break. For a session still to come, every exercise whose
    /// last log is three or more weeks old restarts lighter (by the same break-length factor as coach-built sessions,
    /// rounded down to the smallest step, never below the empty bar), with a note. Computed when shown — the routine
    /// and the stored session are never rewritten.
    func returnAdjusted(_ entries: [ExerciseEntry], for w: Workout, now: Date = Date()) -> [ExerciseEntry] {
        let cal = Calendar.current
        // review N-10: a session the rider edited keeps the weights they typed
        guard !w.done, w.completion == nil, !w.edited, cal.startOfDay(for: w.date) >= cal.startOfDay(for: now) else { return entries }
        let logs = strength.filter { !$0.awaitingReview && !$0.inProgress && !$0.isImported && $0.date <= now }
        return entries.map { e in
            // review N-03: entries already reduced (and saved back by an edit, swap or accepted insight) are not reduced again
            if e.notes.contains("Back after") { return e }
            guard let top = e.sets.compactMap({ $0.bodyweight ? nil : $0.weightKg }).max(), top > 0,
                  let last = logs.filter({ s in (s.exercises ?? []).contains { $0.exerciseId == e.exerciseId && !$0.doneSets.isEmpty } }).map({ $0.date }).max() else { return e }
            let gap = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: now)).day ?? 0
            guard gap >= ReturnPhase.breakThresholdDays else { return e }
            let phase = ReturnPhase(breakDays: gap, sessionsSince: 0, ongoing: true)
            let ex = allExercises.first { $0.id == e.exerciseId }
            let dumbbell = ex?.equipment.contains { $0 == "dumbbell" || $0 == "kettlebell" } ?? false
            let step = WeightFmt.step(dumbbell: dumbbell, settings.units)
            let floorKg = ex.flatMap { x -> Double? in
                let eq = Set(x.equipment.map { $0.lowercased() })
                return eq.contains("barbell") && eq.subtracting(["barbell", "bench", "rack", "plates", "bodyweight"]).isEmpty ? (settings.units == .imperial ? 20.41 : 20) : nil
            }
            let target = max(floorKg ?? step, ((top * phase.loadFactor) / step).rounded(.down) * step)
            guard target < top else { return e }
            var x = e
            x.sets = e.sets.map { var st = $0; if let kg = st.weightKg, !st.bodyweight { st.weightKg = min(kg, (target * 100).rounded() / 100) }; return st }
            let pct = Int(((1 - target / top) * 100).rounded())
            let note = "Back after \(phase.weeksText): about \(pct) % lighter (\(WeightFmt.text(target, settings.units))) for now; your routine is unchanged."
            x.notes = x.notes.isEmpty ? note : x.notes + " " + note
            return x
        }
    }
}
