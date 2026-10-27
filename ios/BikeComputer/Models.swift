import Foundation
import Combine

// MARK: - Rider profile (mirrors the board's bc_profile fields that matter to the app)
struct RiderProfile: Codable, Equatable {
    enum Goal: String, Codable, CaseIterable { case fitness, endurance, stronger, climbing, event, weight, progress
        var title: String { switch self { case .fitness: return "General fitness"; case .endurance: return "Ride longer"; case .stronger: return "Get stronger"; case .climbing: return "Climb better"; case .event: return "Prepare for an event"; case .weight: return "Manage weight"; case .progress: return "Measure progress" } }
        var hint: String { switch self { case .fitness: return "health and energy, a few rides a week"; case .endurance: return "aerobic base, Zone 2"; case .stronger: return "more power at the same effort"; case .climbing: return "sustained power and W/kg"; case .event: return "a race, a tour or a long day"; case .weight: return "steady volume, mostly easy"; case .progress: return "see real change, no guesswork" } }
        /// Link v1.2 goal code: 0 fitness, 1 endurance, 2 climbing, 3 event, 4 weight (stronger/progress have no board code → fitness).
        var linkCode: Int { switch self { case .endurance: return 1; case .climbing: return 2; case .event: return 3; case .weight: return 4; default: return 0 } }
        static func from(linkCode c: Int) -> Goal { switch c { case 1: return .endurance; case 2: return .climbing; case 3: return .event; case 4: return .weight; default: return .fitness } }
        static var onboardingChoices: [Goal] { [.fitness, .endurance, .stronger, .climbing, .event, .weight] } }
    enum Level: String, Codable, CaseIterable { case beginner, intermediate, advanced
        var title: String { switch self { case .beginner: return "New to training"; case .intermediate: return "Regular rider"; case .advanced: return "Experienced" } }
        var hint: String { switch self { case .beginner: return "new to training with power"; case .intermediate: return "ride regularly, some structure"; case .advanced: return "years of structured training" } }
        /// Starting-assumption W/kg, same table as the board (bc_exp_wkg_x100): 1.75 / 3.0 / 4.0
        var wkg: Double { switch self { case .beginner: return 1.75; case .intermediate: return 3.0; case .advanced: return 4.0 } }
        var linkCode: Int { switch self { case .beginner: return 0; case .intermediate: return 1; case .advanced: return 2 } }
        static func from(linkCode c: Int) -> Level { c <= 0 ? .beginner : c == 1 ? .intermediate : .advanced } }
    enum FTPHow: String, Codable { case assumed, fromRides, entered, tested
        var label: String { switch self { case .assumed: return "provisional"; case .fromRides: return "estimated"; case .entered: return "entered"; case .tested: return "tested" } }
        var linkCode: Int { switch self { case .assumed: return 0; case .entered: return 1; case .fromRides: return 2; case .tested: return 3 } }
        static func from(linkCode c: Int) -> FTPHow { switch c { case 1: return .entered; case 2: return .fromRides; case 3: return .tested; default: return .assumed } } }
    enum Sport: String, Codable, CaseIterable { case roadCycling, indoorCycling, mountainBike, commuting, running, swimming, strength, other
        var title: String { switch self { case .roadCycling: return "Road cycling"; case .indoorCycling: return "Indoor cycling"; case .mountainBike: return "Mountain bike"; case .commuting: return "Commuting"; case .running: return "Running"; case .swimming: return "Swimming"; case .strength: return "Strength"; case .other: return "Other" } } }

    var name = ""
    var goal: Goal = .endurance
    var hoursPerWeek = 5
    var level: Level = .intermediate
    var weightKg = 75.0
    var heightCm: Int? = nil
    var maxHR: Int? = nil
    var age = 35
    var ftpW: Int = 225
    var ftpHow: FTPHow = .assumed
    var hrPrefWatchFirst = false
    /// Date of the ride an estimated FTP came from (ftpHow == .fromRides); nil otherwise.
    var ftpFromDate: Date? = nil
    /// Build 0.4.0 additions (all optional so an older store.json loads unchanged). nil = the rider did not say.
    var birthYear: Int? = nil
    var restHR: Int? = nil
    var lthr: Int? = nil
    var sports: [Sport] = [.roadCycling]
    /// Monotonic version of the shared athlete settings; bumped on every change the rider makes. Drives profile sync.
    var version: UInt32 = 1
    var updatedAt: Date = Date()
    /// 0.5.0 additions (optional / defaulted so older files load unchanged).
    var gender: String? = nil                       // only if the rider volunteers it
    var bikeName: String? = nil
    var wheelMm: Int = 2096                         // wheel circumference for a speed sensor (syncs to the board with 0.6.0)
    var cadenceLow = 85, cadenceHigh = 95           // preferred cadence range for coaching
    var hrZoneMethod: HRZoneMethod = .maxHR
    enum HRZoneMethod: String, Codable, CaseIterable { case maxHR, lthr
        var title: String { self == .maxHR ? "% of max heart rate" : "% of threshold (LTHR)" } }
    /// 0.6.0 Hybrid Athlete Mode (phone-side only; not part of the Link profile). `hoursPerWeek` stays the CYCLING
    /// budget; lifting has its own budget so the two are never mixed.
    var trainingMode: TrainingMode = .cycling
    var priority: TrainingPriority = .balanced
    var cyclingDaysPerWeek = 3
    var liftDaysPerWeek = 0
    var liftingHoursPerWeek = 0
    /// Preferred training days as the rider stated them in onboarding (0 = Monday); the availability editor refines them.
    var preferredDays: [Int] = []
    /// Adaptive coach (hybrid onboarding, ios/ADAPTIVE_COACH.md). All optional: nil / empty = not answered, the plan
    /// keeps the 0.8.0 behaviour. No split implies a number of days.
    var hybridGoal: HybridGoal? = nil
    var hybridGoalNote: String? = nil
    var trainingDaysPerWeek: Int? = nil
    var strengthSplit: StrengthSplit? = nil
    var customSplit: [SplitSlot] = []
    var cyclingSessionMinutes: Int? = nil
    var strengthSessionMinutes: Int? = nil
    /// Saved routines the rider wants kept as they are; the coach builds sessions around them first.
    var preservedTemplateIds: [UUID] = []
    /// Quality release: FTP evidence. `ftpVerifiedTest` is true only when the FTP came from a completed structured FTP
    /// test ride with verified power; `ftpPowerVerified` records whether the ride an estimate came from had verified
    /// power. Both nil on older files → the FTP is treated as unverified unless it is the provisional assumption.
    var ftpVerifiedTest: Bool? = nil
    var ftpPowerVerified: Bool? = nil
    /// Coach remediation M-01: the pre-participation health check (nil = never answered → no vigorous prescriptions).
    var healthScreen: HealthScreen? = nil
    /// Coach remediation M-06: how quickly the rider recovers in their own words (nil = not answered = normal).
    var recoveryCapacity: RecoveryCapacity? = nil
    /// Heart-rate zone bounds (bpm) from the chosen method: 5 zones.
    var hrZones: [(lo: Int, hi: Int?)] {
        if hrZoneMethod == .lthr, let l = lthr, l > 0 {
            let b = [0.85, 0.89, 0.94, 1.0].map { Int((Double(l) * $0).rounded()) }
            return [(0, b[0]), (b[0], b[1]), (b[1], b[2]), (b[2], b[3]), (b[3], nil)]
        }
        let m = Double(estimatedMaxHR); let b = [0.60, 0.70, 0.80, 0.90].map { Int((m * $0).rounded()) }
        return [(0, b[0]), (b[0], b[1]), (b[1], b[2]), (b[2], b[3]), (b[3], nil)]
    }

    /// Age from the birth year when known, else the stored `age` slider value.
    var effectiveAge: Int { if let y = birthYear, y > 1900 { return max(10, Calendar.current.component(.year, from: Date()) - y) }; return age }
    var maxHRLabel: String { maxHR != nil ? "measured / entered" : "estimated from age" }

    /// The honest confidence label of the FTP ("Verified test", "Estimated from verified power data", "Provisional
    /// estimate", "Unverified"). The 95 %-of-20-minutes estimate is never called a test.
    var ftpLabel: String { ftpConfidence.title }

    var estimatedMaxHR: Int { maxHR ?? Int((208.0 - 0.7 * Double(effectiveAge)).rounded()) }
    mutating func refreshAssumption() { if ftpHow == .assumed { ftpW = Int((weightKg * level.wkg).rounded()) } }
    /// Marks a rider-made change: bumps the sync version and the timestamp.
    mutating func touch(now: Date = Date()) { version &+= 1; if version == 0 { version = 1 }; updatedAt = now }
    static func differIgnoringVersion(_ a: RiderProfile, _ b: RiderProfile) -> Bool {
        var x = a, y = b; x.version = 0; y.version = 0; x.updatedAt = Date(timeIntervalSince1970: 0); y.updatedAt = x.updatedAt
        return x != y
    }

    init() {}
    /// Tolerant decoding: every key missing from an older store.json takes its default (profiles are never dropped on update).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        goal = (try? c.decodeIfPresent(Goal.self, forKey: .goal)) ?? .endurance
        hoursPerWeek = try c.decodeIfPresent(Int.self, forKey: .hoursPerWeek) ?? 5
        level = (try? c.decodeIfPresent(Level.self, forKey: .level)) ?? .intermediate
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg) ?? 75
        heightCm = try c.decodeIfPresent(Int.self, forKey: .heightCm)
        maxHR = try c.decodeIfPresent(Int.self, forKey: .maxHR)
        age = try c.decodeIfPresent(Int.self, forKey: .age) ?? 35
        ftpW = try c.decodeIfPresent(Int.self, forKey: .ftpW) ?? 225
        ftpHow = (try? c.decodeIfPresent(FTPHow.self, forKey: .ftpHow)) ?? .assumed
        hrPrefWatchFirst = try c.decodeIfPresent(Bool.self, forKey: .hrPrefWatchFirst) ?? false
        ftpFromDate = try c.decodeIfPresent(Date.self, forKey: .ftpFromDate)
        birthYear = try c.decodeIfPresent(Int.self, forKey: .birthYear)
        restHR = try c.decodeIfPresent(Int.self, forKey: .restHR)
        lthr = try c.decodeIfPresent(Int.self, forKey: .lthr)
        sports = (try? c.decodeIfPresent([Sport].self, forKey: .sports)) ?? [.roadCycling]
        version = try c.decodeIfPresent(UInt32.self, forKey: .version) ?? 1
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        gender = try c.decodeIfPresent(String.self, forKey: .gender)
        bikeName = try c.decodeIfPresent(String.self, forKey: .bikeName)
        wheelMm = try c.decodeIfPresent(Int.self, forKey: .wheelMm) ?? 2096
        cadenceLow = try c.decodeIfPresent(Int.self, forKey: .cadenceLow) ?? 85
        cadenceHigh = try c.decodeIfPresent(Int.self, forKey: .cadenceHigh) ?? 95
        hrZoneMethod = (try? c.decodeIfPresent(HRZoneMethod.self, forKey: .hrZoneMethod)) ?? .maxHR
        trainingMode = (try? c.decodeIfPresent(TrainingMode.self, forKey: .trainingMode)) ?? .cycling
        priority = (try? c.decodeIfPresent(TrainingPriority.self, forKey: .priority)) ?? .balanced
        cyclingDaysPerWeek = try c.decodeIfPresent(Int.self, forKey: .cyclingDaysPerWeek) ?? 3
        liftDaysPerWeek = try c.decodeIfPresent(Int.self, forKey: .liftDaysPerWeek) ?? 0
        liftingHoursPerWeek = try c.decodeIfPresent(Int.self, forKey: .liftingHoursPerWeek) ?? 0
        preferredDays = (try? c.decodeIfPresent([Int].self, forKey: .preferredDays)) ?? []
        hybridGoal = try? c.decodeIfPresent(HybridGoal.self, forKey: .hybridGoal)
        hybridGoalNote = try? c.decodeIfPresent(String.self, forKey: .hybridGoalNote)
        trainingDaysPerWeek = try? c.decodeIfPresent(Int.self, forKey: .trainingDaysPerWeek)
        strengthSplit = try? c.decodeIfPresent(StrengthSplit.self, forKey: .strengthSplit)
        customSplit = (try? c.decodeIfPresent([SplitSlot].self, forKey: .customSplit)) ?? []
        cyclingSessionMinutes = try? c.decodeIfPresent(Int.self, forKey: .cyclingSessionMinutes)
        strengthSessionMinutes = try? c.decodeIfPresent(Int.self, forKey: .strengthSessionMinutes)
        preservedTemplateIds = (try? c.decodeIfPresent([UUID].self, forKey: .preservedTemplateIds)) ?? []
        ftpVerifiedTest = try? c.decodeIfPresent(Bool.self, forKey: .ftpVerifiedTest)
        ftpPowerVerified = try? c.decodeIfPresent(Bool.self, forKey: .ftpPowerVerified)
        healthScreen = try? c.decodeIfPresent(HealthScreen.self, forKey: .healthScreen)
        recoveryCapacity = try? c.decodeIfPresent(RecoveryCapacity.self, forKey: .recoveryCapacity)
    }

    // MARK: Link v1.2 mapping (docs/LINK_V1_2_SPEC.md)
    /// What the phone sends as the authoritative shared profile.
    func linkMessage(units: AppSettings.Units) -> BCLink.ProfileMessage {
        var m = BCLink.ProfileMessage()
        m.version = version; m.updatedEpochS = UInt32(clamping: Int(updatedAt.timeIntervalSince1970))
        m.name = name; m.ftpW = ftpW; m.ftpHow = ftpHow.linkCode; m.weightKgX10 = Int((weightKg * 10).rounded())
        m.birthYear = birthYear ?? 0; m.maxHR = maxHR ?? 0; m.restHR = restHR ?? 0; m.units = units == .imperial ? 1 : 0
        m.hoursPerWeek = hoursPerWeek; m.level = level.linkCode; m.goal = goal.linkCode; m.lthr = lthr ?? 0
        return m
    }
    /// 1.2.1: the board range-checks a PROFILE_SET as a whole and rejects it (status 2) without saying which field. The phone
    /// checks the same ranges first and names the field so the rider can fix it in Profile.
    func linkValidationIssues() -> [String] {
        var out: [String] = []
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty || n.utf8.count > 24 { out.append("Name must be 1–24 characters") }
        if ftpW != 0, !(50...600).contains(ftpW) { out.append("FTP must be 50–600 W") }
        if !(30...200).contains(weightKg) { out.append("Weight must be 30–200 kg") }
        if let b = birthYear, !(1900...2030).contains(b) { out.append("Birth year must be 1900–2030") }
        if let m = maxHR, !(100...230).contains(m) { out.append("Max heart rate must be 100–230 bpm") }
        if let r = restHR { if !(25...120).contains(r) { out.append("Resting heart rate must be 25–120 bpm") }; if let m = maxHR, r >= m { out.append("Resting heart rate must be below max heart rate") } }
        if let l = lthr, !(80...220).contains(l) { out.append("Threshold heart rate must be 80–220 bpm") }
        if hoursPerWeek > 40 { out.append("Hours per week must be 40 or fewer") }
        return out
    }
    /// Human-readable differences between this profile and what the board reported (only the fields the board carries).
    func differences(from b: BCLink.ProfileMessage, units: AppSettings.Units) -> [ProfileDifference] {
        var out: [ProfileDifference] = []
        func add(_ f: String, _ phone: String, _ board: String) { if phone != board { out.append(ProfileDifference(field: f, phone: phone, board: board)) } }
        if let n = b.name { add("Name", name, n) }
        if let v = b.ftpW { add("FTP", "\(ftpW) W (\(ftpHow.label))", "\(v) W (\(FTPHow.from(linkCode: b.ftpHow ?? 0).label))") }
        if let v = b.weightKgX10 { add("Weight", String(format: "%.1f kg", weightKg), String(format: "%.1f kg", Double(v) / 10)) }
        if let v = b.birthYear { add("Birth year", birthYear.map(String.init) ?? "not set", "\(v)") } else if birthYear != nil { add("Birth year", "\(birthYear!)", "not set") }
        if let v = b.maxHR { add("Max heart rate", maxHR.map { "\($0) bpm" } ?? "estimated", "\(v) bpm") } else if let m = maxHR { add("Max heart rate", "\(m) bpm", "estimated") }
        if let v = b.hoursPerWeek { add("Hours per week", "\(hoursPerWeek) h", "\(v) h") }
        if let v = b.level { add("Experience", level.title, Level.from(linkCode: v).title) }
        if let v = b.goal { add("Goal", Goal.from(linkCode: goal.linkCode).title, Goal.from(linkCode: v).title) }
        if let v = b.units { add("Units", units == .imperial ? "mi, ft" : "km, m", v == 1 ? "mi, ft" : "km, m") }
        return out
    }
    /// Coggan zones from FTP: 55/75/90/105/120/150 %
    var powerZones: [(lo: Int, hi: Int?)] {
        let f = Double(ftpW); let b = [0.55, 0.75, 0.90, 1.05, 1.20, 1.50].map { Int((f * $0).rounded()) }
        return [(0, b[0]), (b[0], b[1]), (b[1], b[2]), (b[2], b[3]), (b[3], b[4]), (b[4], b[5]), (b[5], nil)]
    }
    func zone(forWatts w: Int) -> Int { for (i, z) in powerZones.enumerated() where w < (z.hi ?? Int.max) { return i + 1 }; return 7 }
}

// MARK: - Plan
enum WorkoutKind: String, Codable, CaseIterable {
    case endurance, tempo, threshold, vo2, recovery, long, ftpTest, strength, mobility, other, recoveryDay, rest
    var title: String { switch self { case .endurance: return "Endurance"; case .tempo: return "Tempo"; case .threshold: return "Threshold"; case .vo2: return "VO2 max"; case .recovery: return "Recovery spin"; case .long: return "Long ride"; case .ftpTest: return "FTP test"; case .strength: return "Strength"; case .mobility: return "Mobility / yoga"; case .other: return "Other activity"; case .recoveryDay: return "Recovery day"; case .rest: return "Rest" } }
    var subtitle: String { switch self { case .endurance: return "Zone 2, steady"; case .tempo: return "Zone 3 blocks"; case .threshold: return "Zone 4 intervals"; case .vo2: return "Zone 5 short efforts"; case .recovery: return "Zone 1, easy"; case .long: return "Zone 2, 2 h+"; case .ftpTest: return "20-minute effort"; case .strength: return "off the bike"; case .mobility: return "off the bike, 20–40 min"; case .other: return "run, swim, hike…"; case .recoveryDay: return "rest + sleep focus"; case .rest: return "no training" } }
    var zone: Int { switch self { case .endurance, .long: return 2; case .tempo: return 3; case .threshold, .ftpTest: return 4; case .vo2: return 5; case .recovery: return 1; default: return 0 } }
    var isRide: Bool { zone > 0 }
    var defaultMinutes: Int { switch self { case .long: return 120; case .tempo: return 75; case .threshold: return 70; case .vo2: return 60; case .recovery: return 45; case .strength, .mobility: return 30; case .other: return 60; case .ftpTest: return 60; case .endurance: return 60; default: return 0 } }
    /// Interval sessions (adaptive coach may change the repetitions ±1): default reps, work and recovery minutes.
    var defaultIntervalReps: Int? { switch self { case .threshold: return 3; case .vo2: return 5; default: return nil } }
    var intervalWorkMinutes: Int { switch self { case .threshold: return 8; case .vo2: return 3; default: return 0 } }
    var intervalRestMinutes: Int { switch self { case .threshold, .vo2: return 3; default: return 0 } }
}

struct Workout: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var kind: WorkoutKind
    var minutes: Int
    var done = false
    var skipped = false
    var note = ""
    /// 0.5.0: the rider changed this session by hand (type, duration, move, add). Never regenerated without confirmation.
    var edited = false
    /// 0.6.0 Hybrid: planned body region of a strength session (nil = not specified), and the order of two sessions on
    /// one day (0 first). Older files have neither; both default.
    var strengthFocus: StrengthFocus? = nil
    var sequence = 0
    /// 0.7.0: generated from a FIXED day assignment — the coach never moves or changes it; and the assignment it came from.
    var fixed = false
    var assignmentId: UUID? = nil
    /// 0.8.0: the strength routine assigned to this session (a saved template id), and the planned sets for THIS
    /// session when the rider or an accepted insight changed them (nil = use the template as it is). The template
    /// itself is never modified by either. `templateId == nil` on a strength session = "no routine assigned".
    var templateId: UUID? = nil
    var plannedEntries: [ExerciseEntry]? = nil
    /// true when the rider chose the routine by hand (kept when the week is rebuilt; weekday defaults fill the rest).
    var routineManual = false
    /// Adaptive coach: interval repetitions for threshold / VO2 sessions (nil = the kind's default), whether
    /// `plannedEntries` were built by the coach from the rider's exercises (not typed by the rider), and the session as
    /// planned before the coach's automatic changes (nil = never adjusted).
    var intervalReps: Int? = nil
    var coachOriginal: WorkoutPlanSnapshot? = nil
    /// Stored only when true, so sessions of older builds encode exactly as before (no sync churn).
    var entriesByCoach: Bool? = nil
    var generatedEntries: Bool { get { entriesByCoach ?? false } set { entriesByCoach = newValue ? true : nil } }
    /// Quality release (schema 2, ios/QUALITY_RELEASE.md): HOW the session was completed. nil = not completed. `.recorded`
    /// = a log or a recorded ride backs it; `.marked` = the rider marked it done without detail (WorkoutStatus.completedManual).
    /// `done` stays the persisted "closed" flag and is always written together with this field by the Store.
    var completion: WorkoutCompletion? = nil
    var completedAt: Date? = nil
    /// Duration the rider typed for a manual completion (nil = not stated; never filled in by the app).
    var manualMinutes: Int? = nil
    /// What a data migration changed on this record, with the original values (never silently rewritten).
    var migrationNote: String? = nil
    /// The strength planner's decision factors for a session it generated (Why? per exercise).
    var rationale: SessionRationale? = nil

    init(id: UUID = UUID(), date: Date, kind: WorkoutKind, minutes: Int, done: Bool = false, skipped: Bool = false, note: String = "", edited: Bool = false, strengthFocus: StrengthFocus? = nil, sequence: Int = 0, fixed: Bool = false, templateId: UUID? = nil) {
        self.id = id; self.date = date; self.kind = kind; self.minutes = minutes; self.done = done; self.skipped = skipped; self.note = note; self.edited = edited
        self.strengthFocus = strengthFocus; self.sequence = sequence; self.fixed = fixed; self.templateId = templateId
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decode(Date.self, forKey: .date)
        kind = (try? c.decode(WorkoutKind.self, forKey: .kind)) ?? .other
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        skipped = try c.decodeIfPresent(Bool.self, forKey: .skipped) ?? false
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        edited = try c.decodeIfPresent(Bool.self, forKey: .edited) ?? false
        strengthFocus = try? c.decodeIfPresent(StrengthFocus.self, forKey: .strengthFocus)
        sequence = try c.decodeIfPresent(Int.self, forKey: .sequence) ?? 0
        fixed = (try? c.decodeIfPresent(Bool.self, forKey: .fixed)) ?? false
        assignmentId = try? c.decodeIfPresent(UUID.self, forKey: .assignmentId)
        templateId = try? c.decodeIfPresent(UUID.self, forKey: .templateId)
        plannedEntries = try? c.decodeIfPresent([ExerciseEntry].self, forKey: .plannedEntries)
        routineManual = (try? c.decodeIfPresent(Bool.self, forKey: .routineManual)) ?? false
        intervalReps = try? c.decodeIfPresent(Int.self, forKey: .intervalReps)
        entriesByCoach = (try? c.decodeIfPresent(Bool.self, forKey: .entriesByCoach)) == true ? true : nil
        coachOriginal = try? c.decodeIfPresent(WorkoutPlanSnapshot.self, forKey: .coachOriginal)
        completion = try? c.decodeIfPresent(WorkoutCompletion.self, forKey: .completion)
        completedAt = try? c.decodeIfPresent(Date.self, forKey: .completedAt)
        manualMinutes = try? c.decodeIfPresent(Int.self, forKey: .manualMinutes)
        migrationNote = try? c.decodeIfPresent(String.self, forKey: .migrationNote)
        rationale = try? c.decodeIfPresent(SessionRationale.self, forKey: .rationale)
    }
    /// "Strength · Lower body" when a region is planned.
    var displayTitle: String {
        if kind == .strength, let f = strengthFocus {
            if f == .custom, !note.isEmpty { return "Strength · \(note)" }      // a custom split slot, e.g. "Core / joints"
            return "Strength · \(f.title)"
        }
        return kind.title
    }
    /// Interval repetitions in force (threshold 3 × 8 min, VO2 5 × 3 min unless the coach changed them).
    var effectiveIntervalReps: Int? { kind.defaultIntervalReps.map { intervalReps ?? $0 } }
    /// The interval structure the live ride coach runs — the SAME one the plan, Home and the steps show (audit G-11:
    /// the ride screen used to run threshold as 4 × 8 min / 4 min while the plan said 3 × 8 min / 3 min easy).
    var liveIntervalPlan: IntervalPlan? {
        guard let r = effectiveIntervalReps, kind.intervalWorkMinutes > 0 else { return nil }
        return IntervalPlan(workSec: kind.intervalWorkMinutes * 60, restSec: kind.intervalRestMinutes * 60, repeats: max(1, r))
    }
    /// Title with the assigned routine's name when one is assigned (the calendar shows the rider's own workout name).
    func displayTitle(routine: WorkoutTemplate?) -> String { if kind == .strength, let r = routine { return r.name }; return displayTitle }

    struct Step: Equatable { let name: String; let duration: String; let target: String }
    /// Steps with power targets from the rider's FTP; HR targets appear only when the rider has an HR source (the caller decides).
    func steps(ftp: Int) -> [Step] {
        let z = { (lo: Double, hi: Double) in "\(Int(Double(ftp) * lo))–\(Int(Double(ftp) * hi)) W" }
        switch kind {
        case .endurance: return [.init(name: "Warm-up", duration: "10 min", target: "\(z(0.45, 0.6)) · 85–95 rpm"), .init(name: "Main", duration: "\(max(5, minutes - 15)) min", target: "\(z(0.65, 0.75)) (Z2) · 85–95 rpm"), .init(name: "Cool-down", duration: "5 min", target: "under \(Int(Double(ftp) * 0.5)) W")]
        case .tempo: return [.init(name: "Warm-up", duration: "15 min", target: z(0.5, 0.65)), .init(name: "Block 1", duration: "15 min", target: "\(z(0.84, 0.9)) (Z3) · 85–90 rpm"), .init(name: "Easy", duration: "10 min", target: "\(Int(Double(ftp) * 0.55)) W"), .init(name: "Block 2", duration: "15 min", target: "\(z(0.84, 0.9)) (Z3)"), .init(name: "Cool-down", duration: "10 min", target: "under \(Int(Double(ftp) * 0.5)) W")]
        case .threshold: let r = effectiveIntervalReps ?? 3; return [.init(name: "Warm-up", duration: "15 min", target: z(0.5, 0.65)), .init(name: "\(r) × 8 min", duration: "\(r * 8) min", target: "\(z(0.93, 1.02)) (Z4) · 3 min easy between"), .init(name: "Cool-down", duration: "10 min", target: "under \(Int(Double(ftp) * 0.5)) W")]
        case .vo2: let r = effectiveIntervalReps ?? 5; return [.init(name: "Warm-up", duration: "15 min", target: z(0.5, 0.65)), .init(name: "\(r) × 3 min", duration: "\(r * 3) min", target: "\(z(1.06, 1.18)) (Z5) · 3 min easy between"), .init(name: "Cool-down", duration: "10 min", target: "under \(Int(Double(ftp) * 0.5)) W")]
        case .recovery: return [.init(name: "Easy spin", duration: "\(minutes) min", target: "under \(Int(Double(ftp) * 0.58)) W · 90+ rpm")]
        case .long: return [.init(name: "Warm-up", duration: "15 min", target: z(0.5, 0.65)), .init(name: "Main", duration: "\(max(10, minutes - 25)) min", target: "\(z(0.65, 0.75)) (Z2) · eat every 30 min"), .init(name: "Cool-down", duration: "10 min", target: "under \(Int(Double(ftp) * 0.5)) W")]
        case .ftpTest: return [.init(name: "Warm-up", duration: "20 min", target: "with 3 × 1 min fast"), .init(name: "Test", duration: "20 min", target: "as hard as you can hold steady"), .init(name: "Cool-down", duration: "10 min", target: "easy")]
        case .strength: return [.init(name: "Circuit", duration: "3 × 10 min", target: "squats, lunges, plank · bodyweight")]
        case .mobility: return [.init(name: "Flow", duration: "\(minutes) min", target: "hips, back, calves")]
        case .other: return [.init(name: "Activity", duration: "\(minutes) min", target: "counted as training load, not as a ride")]
        case .recoveryDay, .rest: return []
        }
    }
    /// Expected training benefit, in plain words (for the Home table).
    var benefit: String {
        switch kind {
        case .endurance, .long: return "aerobic fitness"
        case .tempo: return "sustainable power"
        case .threshold, .ftpTest: return "FTP / threshold"
        case .vo2: return "top-end power"
        case .recovery, .recoveryDay, .rest: return "recovery"
        case .strength: return "strength, injury prevention"
        case .mobility: return "mobility"
        case .other: return "general load"
        }
    }
    /// Short structure, e.g. "3 × 8 min Z4" (for the Home table).
    var structureText: String {
        switch kind {
        case .endurance: return "steady Z2"
        case .tempo: return "2 × 15 min Z3"
        case .threshold: return "\(effectiveIntervalReps ?? 3) × 8 min Z4"
        case .vo2: return "\(effectiveIntervalReps ?? 5) × 3 min Z5"
        case .recovery: return "easy Z1"
        case .long: return "steady Z2, fuel every 30 min"
        case .ftpTest: return "20-min test"
        case .strength: return "3 × 10 min circuit"
        case .mobility: return "flow"
        case .other: return "free"
        case .recoveryDay: return "light movement"
        case .rest: return "—"
        }
    }
    var why: String {
        switch kind {
        case .endurance: return "Builds the aerobic base. Steady Zone 2 is where most of the adaptation happens."
        case .tempo: return "Two steady tempo blocks raise sustainable power without the fatigue of intervals."
        case .threshold: return "Threshold work moves your FTP; it is placed after steady weeks."
        case .vo2: return "Short hard efforts raise the ceiling; only after the base is in place."
        case .recovery: return "The day after a hard session: light pressure, high cadence."
        case .long: return "Your long ride. Steady Zone 2, eat every 30 minutes."
        case .ftpTest: return "A fresh measurement so the plan uses a real number, not an assumption."
        case .strength: return "Optional. Skip if the legs are heavy."
        case .mobility: return "Keeps you supple between hard days."
        case .other: return "Counts toward your weekly load so the coach does not overload the bike days."
        case .recoveryDay: return "A deliberate recovery day: light movement, early night."
        case .rest: return "Rest is part of the plan: adaptation happens here."
        }
    }
}

// MARK: - Rides
/// The ONE answer to "may watts drive coaching?" (audit G-05). The pipeline marks power readings `.good` only when
/// this is true (`SensorHub.refresh(powerVerified:)`), rides store it in `RideRecord.powerVerified`, the adaptive coach
/// uses verified power only, and the live ride coach falls back to heart rate / the rider's own steady output when it
/// is false. No power meter can pass a verification check in this build (the 60-second check of the Android
/// prototype is not ported), so it is false: power is shown and recorded, labelled "unverified", and advisory only.
enum PowerTrust {
    static let meterVerified = false
}

struct RideRecord: Codable, Identifiable, Equatable {
    enum Recorder: String, Codable { case board, phone, health }
    var id = UUID()
    /// Apple Health workout UUID when the ride was imported from Health (0.6.0); nil otherwise.
    var healthUUID: String? = nil
    var boardRideId: Int? = nil
    /// Which board recorded it (BLE address or CoreBluetooth id); nil for phone-only rides.
    var boardId: String? = nil
    /// Seconds the phone did not observe during a phone-only ride (app suspended); nil/0 = none.
    var gapSeconds: Int? = nil
    var start: Date
    var durationS: Int
    var distanceM: Int
    var avgPower: Int?; var maxPower: Int?; var normalizedPower: Int?
    var avgCadence: Int?
    var avgHR: Int?; var maxHR: Int?
    var kj: Int?
    var zoneSeconds: [Int] = Array(repeating: 0, count: 7)
    var recorder: Recorder
    var sources: [String]
    var demo = false
    var samples: [Sample] = []      /* 1 Hz, kept for graphs; nil fields = no data that second */
    /// Adaptive coach: the rider's post-ride check-in, and whether the ride's power was verified (nil = unknown →
    /// treated as unverified: never used to progress intensity). Optional, so older files decode unchanged.
    var checkIn: CheckIn? = nil
    var powerVerified: Bool? = nil
    struct Sample: Codable, Equatable { var t: Int; var w: Int?; var cad: Int?; var hr: Int?; var speedCms: Int?; var lat: Double?; var lon: Double?; var alt: Double?
        /// true = this second was not observed (phone suspended); shown as a gap, never filled in
        var gap: Bool? = nil }

    var title: String { recorder == .phone ? "Ride (phone only)" : recorder == .health ? "Ride (Apple Health)" : "Ride" }
    var dateKnown: Bool { start.timeIntervalSince1970 > 1_600_000_000 }

    /// Best mean power over `seconds` from the 1 Hz samples. Requires power on ≥ 95 % of the window's seconds and the
    /// window to fit the ride; nil otherwise (never extrapolated).
    func bestMeanPower(seconds n: Int) -> Int? {
        let ws = samples.map { $0.w }
        guard ws.count >= n, n > 0 else { return nil }
        var sum = 0, have = 0, best: Int? = nil
        for i in 0..<ws.count {
            if let w = ws[i] { sum += w; have += 1 }
            if i >= n, let w = ws[i - n] { sum -= w; have -= 1 }
            if i >= n - 1, have * 100 >= n * 95 { let m = sum / max(1, have); best = max(best ?? 0, m) }
        }
        return best
    }
    var best20: Int? { bestMeanPower(seconds: 1200) }
    var best60: Int? { bestMeanPower(seconds: 3600) }
    var recordedBy: String { recorder == .board ? "BikeComputer" : recorder == .health ? "Apple Health" : "this phone" }
    /// Stable identity across imports and devices: Health UUID, board id + ride id, else the local id.
    var sourceId: String {
        if let h = healthUUID { return "health:\(h)" }
        if let b = boardRideId { return "board:\(boardId ?? "?"):\(b)" }
        return "phone:\(id.uuidString)"
    }
    var hasPower: Bool { avgPower != nil }
    var hasTrack: Bool { samples.contains { $0.lat != nil } }
}

// MARK: - Settings
struct AppSettings: Codable, Equatable {
    enum Units: String, Codable, CaseIterable { case metric, imperial; var title: String { self == .metric ? "km, m" : "mi, ft" } }
    enum HRPref: String, Codable, CaseIterable { case strap, watch
        var title: String { self == .strap ? "Strap / band via BikeComputer first" : "Apple Watch first" } }
    var units: Units = .metric
    /// Phone-only mode: the phone records even when a BikeComputer is connected (its live values are still shown).
    var phoneOnlyMode = false
    var hrPref: HRPref = .strap
    var keepScreenOn = true
    /// Build 0.4.0: connect to the remembered BikeComputer automatically whenever it is in range (background included).
    var autoConnectBoard = true
    /// Which optional connections the rider turned on. Only these (plus what the ride configuration needs) may show a red "!".
    var enabledConnections: Set<String> = ["board", "watch"]
    /// Apple Health: the rider asked for it in onboarding/Connections. "Connected" is still decided by HealthKit's own authorization status.
    var appleHealthWanted = false
    var appleHealthExportRides = false
    /// 0.5.0: appearance (system / light / dark), the background-recording notice, and the coach frequency.
    enum Appearance: String, Codable, CaseIterable { case system, light, dark; var title: String { rawValue.capitalized } }
    var appearance: Appearance = .system
    var backgroundNotice = true
    enum CoachTalk: String, Codable, CaseIterable { case quiet, normal, frequent; var title: String { rawValue.capitalized } }
    var coachTalk: CoachTalk = .normal
    var coachEnabled = true
    /// 0.6.0: import cycling + strength workouts from Apple Health when the rider asks (and on launch while on).
    var appleHealthImportWorkouts = false
    var lastHealthImport: Date? = nil
    /// Cyclift 1.0: Bluetooth sensors paired directly with this phone (heart rate, power, speed/cadence), by peripheral id.
    var bleSensors: [PairedSensor] = []
    /// Cyclift 1.0: the live ride layout (Ride › settings or the quick switch on the ride screen). Presentation only.
    var rideLayout: RideLayout = .coach
    /// Adaptive coach: small bounded changes to future sessions are applied automatically (always listed, undoable).
    var autoAdapt = true

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        units = (try? c.decodeIfPresent(Units.self, forKey: .units)) ?? .metric
        phoneOnlyMode = try c.decodeIfPresent(Bool.self, forKey: .phoneOnlyMode) ?? false
        hrPref = (try? c.decodeIfPresent(HRPref.self, forKey: .hrPref)) ?? .strap
        keepScreenOn = try c.decodeIfPresent(Bool.self, forKey: .keepScreenOn) ?? true
        autoConnectBoard = try c.decodeIfPresent(Bool.self, forKey: .autoConnectBoard) ?? true
        enabledConnections = (try? c.decodeIfPresent(Set<String>.self, forKey: .enabledConnections)) ?? ["board", "watch"]
        appleHealthWanted = try c.decodeIfPresent(Bool.self, forKey: .appleHealthWanted) ?? false
        appleHealthExportRides = try c.decodeIfPresent(Bool.self, forKey: .appleHealthExportRides) ?? false
        appearance = (try? c.decodeIfPresent(Appearance.self, forKey: .appearance)) ?? .system
        backgroundNotice = try c.decodeIfPresent(Bool.self, forKey: .backgroundNotice) ?? true
        coachTalk = (try? c.decodeIfPresent(CoachTalk.self, forKey: .coachTalk)) ?? .normal
        coachEnabled = try c.decodeIfPresent(Bool.self, forKey: .coachEnabled) ?? true
        appleHealthImportWorkouts = try c.decodeIfPresent(Bool.self, forKey: .appleHealthImportWorkouts) ?? false
        lastHealthImport = try c.decodeIfPresent(Date.self, forKey: .lastHealthImport)
        bleSensors = (try? c.decodeIfPresent([PairedSensor].self, forKey: .bleSensors)) ?? []
        rideLayout = (try? c.decodeIfPresent(RideLayout.self, forKey: .rideLayout)) ?? .coach
        autoAdapt = (try? c.decodeIfPresent(Bool.self, forKey: .autoAdapt)) ?? true
    }
}

/// One field where the phone and the board disagree (shown before the rider confirms the phone profile replaces the board's).
struct ProfileDifference: Identifiable, Equatable { var id: String { field }; let field: String; let phone: String; let board: String }

/// Per-board record of the profile sync: which version the board acknowledged, when, and the board's own profile at first pairing.
struct BoardSyncRecord: Codable, Equatable {
    var boardId: String
    var ackedVersion: UInt32 = 0
    var ackedAt: Date? = nil
    /// true once the rider confirmed on this phone that the phone profile replaces the board's shared settings.
    var confirmed = false
    var boardFirmware: String? = nil
    var settingsVersion: UInt32 = 0
}

extension UUID: @retroactive Identifiable { public var id: UUID { self } }

// MARK: - Store (local JSON file with a schema version; cloud sync comes with the account service)
/// One file `store.json` in Application Support. `schema` lets a future build migrate instead of dropping data; build 15
/// writes schema 1 and still imports the build-14 per-file layout (profile.json / plan.json / rides.json / tiles.json).
struct StoreFile: Codable, Equatable {
    /// 2 = quality release: explicit workout completion states, soft-delete trash, strength preferences (migrateV2).
    static let currentSchema = 2
    var schema = StoreFile.currentSchema
    var profile = RiderProfile()
    var settings = AppSettings()
    var plan: [Workout] = []
    var rides: [RideRecord] = []
    var tiles: [String] = Store.defaultTiles
    var onboarded = false
    var guest = true
    var appleUserId: String? = nil
    var createdAt = Date()
    var ftpSuggestion: FTPSuggestion? = nil
    /// 0.4.0: profile-sync bookkeeping per board (keyed by board id) and the onboarding stage reached.
    var boardSync: [BoardSyncRecord] = []
    var onboardingStage = 0
    /// 0.5.0: the rider's weekly availability; nil = not set yet (a suggestion from the weekly hours is used).
    var availability: WeeklyAvailability? = nil
    /// 0.6.0: strength sessions (quick logs and Apple Health imports) — their hours are kept apart from riding.
    var strength: [StrengthSession] = []
    /// 0.7.0: reusable workout templates, the rider's own exercises, and the coach proposals applied (for Undo).
    var templates: [WorkoutTemplate] = []
    var customExercises: [Exercise] = []
    var appliedProposals: [AppliedProposal] = []
    /// 0.8.0: default routine per weekday (Monday = 0 … Sunday = 6, template id), equipment the rider owns / exercises
    /// excluded, the strength session in progress (resumable after a restart) and insights the rider ignored.
    var weekdayRoutines: [Int: UUID] = [:]
    var equipment = EquipmentProfile()
    var activeSession: StrengthSession? = nil
    var ignoredInsights: [String] = []
    /// Adaptive coach: active automatic adjustments, keys the rider undid or declined, keys the rider approved,
    /// pending approval proposals and the last analysis.
    var adaptations: [PlanAdjustment] = []
    var dismissedAdaptations: [String] = []
    var approvedAdaptations: [String] = []
    var adaptiveProposals: [AdaptiveProposal] = []
    var lastAdaptation: AdaptationSummary? = nil
    var painClearances: [PainClearance] = []
    /// Quality release: the rider's strength-programming preferences (swaps, favourites, discomfort, temporary
    /// unavailability), deleted records kept for Undo, and the human-readable log of data corrections a migration made.
    var strengthPrefs = StrengthPrefs()
    var trash: [TrashItem] = []
    var migrationLog: [String] = []

    /// Explicit because both init(from:) and encode(to:) are hand-written (the compiler then synthesises no keys).
    enum CodingKeys: String, CodingKey {
        case schema, profile, settings, plan, rides, tiles, onboarded, guest, appleUserId, createdAt, ftpSuggestion, boardSync, onboardingStage, availability
        case strength, templates, customExercises, appliedProposals, weekdayRoutines, equipment, activeSession, ignoredInsights
        case adaptations, dismissedAdaptations, approvedAdaptations, adaptiveProposals, lastAdaptation, painClearances
        case strengthPrefs, trash, migrationLog
    }

    init(schema: Int = StoreFile.currentSchema, profile: RiderProfile = RiderProfile(), settings: AppSettings = AppSettings(), plan: [Workout] = [], rides: [RideRecord] = [], tiles: [String] = Store.defaultTiles, onboarded: Bool = false, guest: Bool = true, appleUserId: String? = nil, createdAt: Date = Date()) {
        self.schema = schema; self.profile = profile; self.settings = settings; self.plan = plan; self.rides = rides; self.tiles = tiles
        self.onboarded = onboarded; self.guest = guest; self.appleUserId = appleUserId; self.createdAt = createdAt
    }
    init(schema: Int = StoreFile.currentSchema, profile: RiderProfile, settings: AppSettings, plan: [Workout], rides: [RideRecord], tiles: [String], onboarded: Bool, guest: Bool, appleUserId: String?, createdAt: Date, ftpSuggestion: FTPSuggestion?) {
        self.init(schema: schema, profile: profile, settings: settings, plan: plan, rides: rides, tiles: tiles, onboarded: onboarded, guest: guest, appleUserId: appleUserId, createdAt: createdAt)
        self.ftpSuggestion = ftpSuggestion
    }

    /// Tolerant decoding: a key missing from an older file takes its default instead of failing the whole load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schema = try c.decodeIfPresent(Int.self, forKey: .schema) ?? 1
        profile = try c.decodeIfPresent(RiderProfile.self, forKey: .profile) ?? RiderProfile()
        settings = try c.decodeIfPresent(AppSettings.self, forKey: .settings) ?? AppSettings()
        plan = try c.decodeIfPresent([Workout].self, forKey: .plan) ?? []
        rides = try c.decodeIfPresent([RideRecord].self, forKey: .rides) ?? []
        tiles = try c.decodeIfPresent([String].self, forKey: .tiles) ?? Store.defaultTiles
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? false
        guest = try c.decodeIfPresent(Bool.self, forKey: .guest) ?? true
        appleUserId = try c.decodeIfPresent(String.self, forKey: .appleUserId)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        ftpSuggestion = try c.decodeIfPresent(FTPSuggestion.self, forKey: .ftpSuggestion)
        boardSync = (try? c.decodeIfPresent([BoardSyncRecord].self, forKey: .boardSync)) ?? []
        onboardingStage = try c.decodeIfPresent(Int.self, forKey: .onboardingStage) ?? 0
        availability = try? c.decodeIfPresent(WeeklyAvailability.self, forKey: .availability)
        if let a = availability, a.days.count != 7 { availability = nil }
        strength = (try? c.decodeIfPresent([StrengthSession].self, forKey: .strength)) ?? []
        templates = (try? c.decodeIfPresent([WorkoutTemplate].self, forKey: .templates)) ?? []
        customExercises = (try? c.decodeIfPresent([Exercise].self, forKey: .customExercises)) ?? []
        appliedProposals = (try? c.decodeIfPresent([AppliedProposal].self, forKey: .appliedProposals)) ?? []
        if let wr = try? c.decodeIfPresent([String: String].self, forKey: .weekdayRoutines) { weekdayRoutines = Dictionary(uniqueKeysWithValues: wr.compactMap { k, v in Int(k).flatMap { i in UUID(uuidString: v).map { (i, $0) } } }) }
        equipment = (try? c.decodeIfPresent(EquipmentProfile.self, forKey: .equipment)) ?? EquipmentProfile()
        activeSession = try? c.decodeIfPresent(StrengthSession.self, forKey: .activeSession)
        ignoredInsights = (try? c.decodeIfPresent([String].self, forKey: .ignoredInsights)) ?? []
        adaptations = (try? c.decodeIfPresent([PlanAdjustment].self, forKey: .adaptations)) ?? []
        dismissedAdaptations = (try? c.decodeIfPresent([String].self, forKey: .dismissedAdaptations)) ?? []
        approvedAdaptations = (try? c.decodeIfPresent([String].self, forKey: .approvedAdaptations)) ?? []
        adaptiveProposals = (try? c.decodeIfPresent([AdaptiveProposal].self, forKey: .adaptiveProposals)) ?? []
        lastAdaptation = try? c.decodeIfPresent(AdaptationSummary.self, forKey: .lastAdaptation)
        painClearances = (try? c.decodeIfPresent([PainClearance].self, forKey: .painClearances)) ?? []
        strengthPrefs = (try? c.decodeIfPresent(StrengthPrefs.self, forKey: .strengthPrefs)) ?? StrengthPrefs()
        trash = (try? c.decodeIfPresent([TrashItem].self, forKey: .trash)) ?? []
        migrationLog = (try? c.decodeIfPresent([String].self, forKey: .migrationLog)) ?? []
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schema, forKey: .schema); try c.encode(profile, forKey: .profile); try c.encode(settings, forKey: .settings); try c.encode(plan, forKey: .plan)
        try c.encode(rides, forKey: .rides); try c.encode(tiles, forKey: .tiles); try c.encode(onboarded, forKey: .onboarded); try c.encode(guest, forKey: .guest)
        try c.encodeIfPresent(appleUserId, forKey: .appleUserId); try c.encode(createdAt, forKey: .createdAt); try c.encodeIfPresent(ftpSuggestion, forKey: .ftpSuggestion)
        try c.encode(boardSync, forKey: .boardSync); try c.encode(onboardingStage, forKey: .onboardingStage); try c.encodeIfPresent(availability, forKey: .availability)
        try c.encode(strength, forKey: .strength); try c.encode(templates, forKey: .templates); try c.encode(customExercises, forKey: .customExercises); try c.encode(appliedProposals, forKey: .appliedProposals)
        try c.encode(Dictionary(uniqueKeysWithValues: weekdayRoutines.map { (String($0.key), $0.value.uuidString) }), forKey: .weekdayRoutines)
        try c.encode(equipment, forKey: .equipment); try c.encodeIfPresent(activeSession, forKey: .activeSession); try c.encode(ignoredInsights, forKey: .ignoredInsights)
        try c.encode(adaptations, forKey: .adaptations); try c.encode(dismissedAdaptations, forKey: .dismissedAdaptations); try c.encode(approvedAdaptations, forKey: .approvedAdaptations)
        try c.encode(adaptiveProposals, forKey: .adaptiveProposals); try c.encodeIfPresent(lastAdaptation, forKey: .lastAdaptation); try c.encode(painClearances, forKey: .painClearances)
        try c.encode(strengthPrefs, forKey: .strengthPrefs); try c.encode(trash, forKey: .trash); try c.encode(migrationLog, forKey: .migrationLog)
    }

    /// Migration entry point. Unknown (newer) schemas are kept as they are; older ones are upgraded step by step.
    static func migrate(_ f: StoreFile, now: Date = Date(), calendar: Calendar = .current) -> StoreFile {
        var f = f
        if f.schema < 1 { f.schema = 1 }          /* schema 0 never shipped; placeholder for the pattern */
        if f.tiles.isEmpty { f.tiles = Store.defaultTiles }
        if f.rides.contains(where: { $0.zoneSeconds.count != 7 }) { for i in f.rides.indices where f.rides[i].zoneSeconds.count != 7 { f.rides[i].zoneSeconds = Array(repeating: 0, count: 7) } }
        if f.schema < 2 { f = StoreMigration.v2(f, now: now, calendar: calendar) }
        return f
    }
}

/// An FTP the app proposes from a real ride. Applied only when the rider taps Accept; a tested (entered) FTP is never
/// replaced without that tap either.
struct FTPSuggestion: Codable, Equatable {
    var watts: Int
    var best20: Int
    var best60: Int?
    var rideId: UUID
    var rideDate: Date
    var previousFTP: Int
    /// Quality release: whether the ride's power was verified, and whether the ride was a planned FTP test (structured
    /// protocol). Only both together make an accepted value a "Verified test". nil on older files = no.
    var powerVerified: Bool? = nil
    var testProtocol: Bool? = nil
}

/// A coach proposal the rider accepted, with the workout as it was before — so it can be undone.
struct AppliedProposal: Codable, Equatable, Identifiable {
    var id: String
    var text: String
    var before: Workout
    var appliedAt: Date
}

final class Store: ObservableObject {
    static let defaultTiles = ["power", "cadence", "hr", "speed", "time", "dist"]
    /// Any rider-made change (including through SwiftUI bindings) bumps the profile version so connected boards get it.
    @Published var profile = RiderProfile() { didSet { if !loading, RiderProfile.differIgnoringVersion(oldValue, profile) { profile.touch() }; persist() } }
    @Published var settings = AppSettings() { didSet { persist() } }
    @Published var onboarded = false { didSet { persist() } }
    @Published var guest = true { didSet { persist() } }
    @Published var appleUserId: String? { didSet { persist() } }
    @Published var plan: [Workout] = [] { didSet { persist() } }
    @Published var rides: [RideRecord] = [] { didSet { persist() } }
    @Published var tiles: [String] = Store.defaultTiles { didSet { persist() } }
    @Published var ftpSuggestion: FTPSuggestion? { didSet { persist() } }
    @Published var boardSync: [BoardSyncRecord] = [] { didSet { persist() } }
    @Published var onboardingStage = 0 { didSet { persist() } }
    @Published var availability: WeeklyAvailability? { didSet { persist() } }
    @Published var strength: [StrengthSession] = [] { didSet { persist() } }
    @Published var templates: [WorkoutTemplate] = [] { didSet { persist() } }
    @Published var customExercises: [Exercise] = [] { didSet { persist() } }
    @Published var appliedProposals: [AppliedProposal] = [] { didSet { persist() } }
    @Published var weekdayRoutines: [Int: UUID] = [:] { didSet { persist() } }
    @Published var equipment = EquipmentProfile() { didSet { persist() } }
    @Published var activeSession: StrengthSession? = nil { didSet { persist() } }
    @Published var ignoredInsights: [String] = [] { didSet { persist() } }
    @Published var adaptations: [PlanAdjustment] = [] { didSet { persist() } }
    @Published var dismissedAdaptations: [String] = [] { didSet { persist() } }
    @Published var approvedAdaptations: [String] = [] { didSet { persist() } }
    @Published var adaptiveProposals: [AdaptiveProposal] = [] { didSet { persist() } }
    @Published var lastAdaptation: AdaptationSummary? = nil { didSet { persist() } }
    /// The rider's "this pain is gone" confirmations (audit G-06).
    @Published var painClearances: [PainClearance] = [] { didSet { persist() } }
    @Published var strengthPrefs = StrengthPrefs() { didSet { persist() } }
    @Published var trash: [TrashItem] = [] { didSet { persist() } }
    @Published var migrationLog: [String] = [] { didSet { persist() } }
    /// The last deletion that can still be undone from the snackbar (not persisted; the record itself is in `trash`).
    @Published var undoToast: UndoToast? = nil
    /// Sessions the planner / adaptive coach rebuilt after the latest check-in, as they were before (one-tap Undo).
    @Published var checkInRebuild: CheckInRebuild? = nil
    @Published private(set) var lastSaveError: String?

    let dir: URL
    private var loading = true
    private var createdAt = Date()

    static var defaultDirectory: URL {
        let u = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("BikeComputer", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    init(directory: URL = Store.defaultDirectory, generatePlan: Bool = true) {
        dir = directory
        UITestSupport.prepareStoreDirectory(dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var migrated = false
        if let f: StoreFile = Self.read(dir.appendingPathComponent("store.json")) { let m = StoreFile.migrate(f); migrated = f.schema < 2; apply(m) }
        else if let legacy = legacyImport() { apply(StoreFile.migrate(legacy)); migrated = true }
        loading = false
        purgeTrash()
        if generatePlan { ensurePlan(); refreshRideSafety() }
        // schema-2 upgrade: coach-generated future sessions are rebuilt by the personalised planner (never edited ones)
        if migrated { refreshGeneratedSessions(); persist() }
        if !FileManager.default.fileExists(atPath: dir.appendingPathComponent("store.json").path) { persist() }
    }

    private func apply(_ f: StoreFile) {
        profile = f.profile; settings = f.settings; plan = f.plan; rides = f.rides; tiles = f.tiles
        onboarded = f.onboarded; guest = f.guest; appleUserId = f.appleUserId; createdAt = f.createdAt; ftpSuggestion = f.ftpSuggestion
        boardSync = f.boardSync; onboardingStage = f.onboardingStage; availability = f.availability; strength = f.strength
        templates = f.templates; customExercises = f.customExercises; appliedProposals = f.appliedProposals
        weekdayRoutines = f.weekdayRoutines; equipment = f.equipment; activeSession = f.activeSession; ignoredInsights = f.ignoredInsights
        adaptations = f.adaptations; dismissedAdaptations = f.dismissedAdaptations; approvedAdaptations = f.approvedAdaptations
        adaptiveProposals = f.adaptiveProposals; lastAdaptation = f.lastAdaptation; painClearances = f.painClearances
        strengthPrefs = f.strengthPrefs; trash = f.trash; migrationLog = f.migrationLog
    }

    var snapshot: StoreFile {
        var f = StoreFile(profile: profile, settings: settings, plan: plan, rides: rides, tiles: tiles, onboarded: onboarded, guest: guest, appleUserId: appleUserId, createdAt: createdAt, ftpSuggestion: ftpSuggestion)
        f.boardSync = boardSync; f.onboardingStage = onboardingStage; f.availability = availability; f.strength = strength
        f.templates = templates; f.customExercises = customExercises; f.appliedProposals = appliedProposals
        f.weekdayRoutines = weekdayRoutines; f.equipment = equipment; f.activeSession = activeSession; f.ignoredInsights = ignoredInsights
        f.adaptations = adaptations; f.dismissedAdaptations = dismissedAdaptations; f.approvedAdaptations = approvedAdaptations
        f.adaptiveProposals = adaptiveProposals; f.lastAdaptation = lastAdaptation; f.painClearances = painClearances
        f.strengthPrefs = strengthPrefs; f.trash = trash; f.migrationLog = migrationLog
        return f
    }

    // MARK: profile sync bookkeeping
    func syncRecord(for boardId: String) -> BoardSyncRecord { boardSync.first { $0.boardId == boardId } ?? BoardSyncRecord(boardId: boardId) }
    func setSyncRecord(_ r: BoardSyncRecord) { if let i = boardSync.firstIndex(where: { $0.boardId == r.boardId }) { boardSync[i] = r } else { boardSync.append(r) } }
    /// Rider-made profile change: bump the version so connected boards receive it.
    func updateProfile(_ change: (inout RiderProfile) -> Void) { var p = profile; change(&p); if p != profile { profile = p } }   /* didSet bumps the version */

    /// Build-14 layout: separate JSON files + UserDefaults flags. Imported once, then superseded by store.json.
    private func legacyImport() -> StoreFile? {
        var f = StoreFile(); var any = false
        if let p: RiderProfile = Self.read(dir.appendingPathComponent("profile.json")) { f.profile = p; any = true }
        if let w: [Workout] = Self.read(dir.appendingPathComponent("plan.json")) { f.plan = w; any = true }
        if let r: [RideRecord] = Self.read(dir.appendingPathComponent("rides.json")) { f.rides = r; any = true }
        if let t: [String] = Self.read(dir.appendingPathComponent("tiles.json")) { f.tiles = t; any = true }
        let ud = UserDefaults.standard
        if ud.object(forKey: "bc.onboarded") != nil { f.onboarded = ud.bool(forKey: "bc.onboarded"); any = true }
        if let g = ud.object(forKey: "bc.guest") as? Bool { f.guest = g }
        if let a = ud.string(forKey: "bc.appleUser") { f.appleUserId = a; f.guest = false }
        return any ? f : nil
    }

    /// The availability in force: the rider's own, else a suggestion from the weekly hours (never stored until edited).
    var effectiveAvailability: WeeklyAvailability { availability ?? WeeklyAvailability.suggested(for: profile) }

    /// Makes sure this week and next week exist. Cyclift A5: only a week with NO entries is generated; a week that
    /// already exists is never rebuilt here (a removed session used to trigger a rebuild that dropped hand edits,
    /// assigned routines and done flags). Called at launch and when the calendar day changes.
    func ensurePlan(now: Date = Date()) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let weekday = (cal.component(.weekday, from: today) + 5) % 7   // Monday = 0
        let monday = cal.date(byAdding: .day, value: -weekday, to: today)!
        let a = effectiveAvailability
        var next = plan, added = false
        for k in 0..<2 {
            let m = cal.date(byAdding: .day, value: 7 * k, to: monday)!, e = cal.date(byAdding: .day, value: 7, to: m)!
            if !next.contains(where: { $0.date >= m && $0.date < e }) { next += applyWeekdayRoutines(PlanEngine.week(starting: m, profile: profile, availability: a, returning: cyclingReturnPhase(now: now), trainingWeeks: consecutiveTrainingWeeks(before: m))); added = true }
        }
        if added { plan = next.sorted { $0.date < $1.date } }
    }

    // MARK: routines on the calendar (0.8.0)
    /// Monday = 0 … Sunday = 6 for a date.
    static func weekdayIndex(_ d: Date, calendar cal: Calendar = .current) -> Int { (cal.component(.weekday, from: d) + 5) % 7 }
    /// Fills freshly generated strength sessions with the weekday's default routine (if one is set and still exists).
    func applyWeekdayRoutines(_ ws: [Workout]) -> [Workout] {
        // the planner sees the NEW week (its rides for interference, its lifts for the session index and the weekly
        // volume share), not the week being replaced
        var ctx: PlannerContext? = nil
        if profile.trainingMode.includesLifting, ws.contains(where: { $0.kind == .strength && $0.templateId == nil }), let lo = ws.map({ $0.date }).min(), let hi = ws.map({ $0.date }).max() {
            let cal = Calendar.current
            let m = TrainingLedger.monday(of: lo, calendar: cal), e = cal.date(byAdding: .day, value: 7, to: TrainingLedger.monday(of: hi, calendar: cal))!
            var c = plannerContext(); c.plan = plan.filter { $0.date < m || $0.date >= e } + ws; ctx = c
        }
        return ws.map { w in
            guard w.kind == .strength, w.templateId == nil else { return w }
            if let t = weekdayRoutines[Store.weekdayIndex(w.date)], templates.contains(where: { $0.id == t }) { var x = w; x.templateId = t; return x }
            // adaptive coach (with or without a chosen split): a session without a routine is built by the planner
            return programmedSession(w, ctx: ctx)
        }
    }
    func template(_ id: UUID?) -> WorkoutTemplate? { id.flatMap { i in templates.first { $0.id == i } } }
    func routine(for w: Workout) -> WorkoutTemplate? { w.kind == .strength ? template(w.templateId) : nil }
    /// Planned entries for a session: the session's own (edited / accepted insight), else the template prefilled from
    /// the last completed use of that template.
    func plannedEntries(for w: Workout) -> [ExerciseEntry] {
        if let e = w.plannedEntries, !e.isEmpty { return e }
        guard let t = routine(for: w) else { return [] }
        return t.prefilled(from: lastSession(template: t))
    }
    /// Assigns a routine to one session. `nil` removes the assignment (the template is untouched). Returns the budget
    /// warning text when the routine's estimated duration would push the week over the lifting budget (assignment still
    /// made; the UI shows the warning so the rider can decide).
    @discardableResult
    func assign(template t: WorkoutTemplate?, to w: Workout) -> String? {
        guard let i = plan.firstIndex(where: { $0.id == w.id }), !plan[i].done else { return nil }
        plan[i].templateId = t?.id; plan[i].plannedEntries = nil; plan[i].routineManual = t != nil
        if let t { plan[i].minutes = t.estimatedMinutes; if t.focus != .custom { plan[i].strengthFocus = t.focus } }
        return liftingBudgetWarning(weekOf: plan[i].date)
    }
    /// Sets (or clears) the default routine for a weekday and applies it to that weekday's not-yet-done, not manually
    /// assigned strength sessions in the current and coming weeks.
    @discardableResult
    func setWeekdayRoutine(_ t: WorkoutTemplate?, weekday: Int, now: Date = Date()) -> String? {
        if let t { weekdayRoutines[weekday] = t.id } else { weekdayRoutines.removeValue(forKey: weekday) }
        let today = Calendar.current.startOfDay(for: now)
        var touched: [Date] = []
        for i in plan.indices where plan[i].kind == .strength && !plan[i].done && !plan[i].routineManual && plan[i].date >= today && Store.weekdayIndex(plan[i].date) == weekday {
            plan[i].templateId = t?.id; plan[i].plannedEntries = nil
            if let t { if !plan[i].edited { plan[i].minutes = t.estimatedMinutes }; if t.focus != .custom { plan[i].strengthFocus = t.focus } }
            touched.append(plan[i].date)
        }
        guard t != nil else { return nil }
        return touched.sorted().lazy.compactMap { self.liftingBudgetWarning(weekOf: $0) }.first
    }
    /// Lifting minutes planned in the week of `date` against the budget; nil when within budget or no budget.
    func liftingBudgetWarning(weekOf date: Date) -> String? {
        let b = profile.liftingHoursPerWeek * 60
        guard b > 0 else { return nil }
        let planned = PlanEngine.liftMinutes(workouts(weekOf: date))
        guard planned > b else { return nil }
        return "Lifting this week is now \(Fmt.duration(minutes: planned)) against your \(Fmt.duration(minutes: b)) budget (\(Fmt.duration(minutes: planned - b)) over). Shorten a routine, skip a session or raise the budget in Profile › Training profile."
    }
    /// Deleting a template clears weekday defaults and per-session sets; open sessions show "routine removed"; completed sessions keep their log.
    func deleteTemplateEverywhere(_ t: WorkoutTemplate) {
        templates.removeAll { $0.id == t.id }
        // open sessions keep the (now dangling) id so they show "routine removed — choose another" instead of silently
        // turning into a generic session; their own planned sets are dropped with the routine. Completed ones are untouched.
        for i in plan.indices where plan[i].templateId == t.id && !plan[i].done { plan[i].plannedEntries = nil; plan[i].routineManual = false }
        weekdayRoutines = weekdayRoutines.filter { $0.value != t.id }
    }

    // MARK: workout mode (0.8.0): start → record sets → pause/resume → finish; partial sessions survive a restart
    /// Starts a strength session for a planned workout (or an unplanned one). Refuses while another is in progress.
    @discardableResult
    func startStrengthSession(for w: Workout?, template t: WorkoutTemplate?, entries: [ExerciseEntry], name: String? = nil, now: Date = Date()) -> Bool {
        guard activeSession == nil else { return false }
        if let id = w?.id, plan.first(where: { $0.id == id })?.done == true { return false }   // already completed: no second log
        // quality release: a session planned for a later day cannot be started (move it to today first)
        if let w, Calendar.current.startOfDay(for: w.date) > Calendar.current.startOfDay(for: now) { return false }
        var s = StrengthSession(date: now, minutes: 0, focus: t?.focus ?? w?.strengthFocus ?? .custom, customName: name ?? t?.name ?? "", workoutId: w?.id)
        s.templateId = t?.id
        s.exercises = entries.map { e in var x = e; x.sets = x.sets.map { st in var y = st; y.done = false; return y }; return x }
        s.startedAt = now
        activeSession = s
        return true
    }
    func updateActiveSession(_ change: (inout StrengthSession) -> Void) { guard var s = activeSession else { return }; change(&s); activeSession = s }
    func pauseActiveSession(now: Date = Date()) { updateActiveSession { if $0.pausedAt == nil { $0.pausedAt = now } } }
    func resumeActiveSession(now: Date = Date()) { updateActiveSession { if let p = $0.pausedAt { $0.pausedSeconds += Int(now.timeIntervalSince(p)); $0.pausedAt = nil } } }
    /// Finishes the active session: only completed sets are kept; duration = measured working time (rounded, never a
    /// made-up minimum). Adds it to history (marking the planned session done) and clears the active one. Returns the
    /// stored session. Quality release: a session that had planned exercises but NO set ticked as done is NOT saved
    /// (returns nil, the session stays active) — the UI offers "Mark done without details" or Discard instead.
    @discardableResult
    func finishActiveSession(rpe: Int?, notes: String, now: Date = Date()) -> StrengthSession? {
        guard var s = activeSession else { return nil }
        if Store.finishWouldSaveNothing(s) { return nil }
        if s.pausedAt != nil { s.pausedSeconds += Int(now.timeIntervalSince(s.pausedAt!)); s.pausedAt = nil }
        s.finishedAt = now
        s.minutes = max(0, (s.elapsedSeconds(now: now) + 30) / 60)
        s.rpe = rpe; s.notes = notes
        s.exercises = s.exercises?.map { e in var x = e; x.sets = x.sets.filter { $0.done }; return x }.filter { !$0.sets.isEmpty }
        if (s.exercises ?? []).isEmpty { s.exercises = nil }
        activeSession = nil
        _ = addStrength(s)
        return s
    }
    func discardActiveSession() { activeSession = nil }

    // MARK: insights (0.8.0): Accept edits one session's planned sets; Ignore remembers; Undo restores
    @discardableResult
    func acceptInsight(_ ins: WorkoutInsight, for w: Workout, alsoTemplate: Bool) -> Bool {
        guard let c = ins.change, let i = plan.firstIndex(where: { $0.id == w.id }), !plan[i].done else { return false }
        let before = plan[i]
        var entries = plannedEntries(for: plan[i])
        InsightEngine.apply(c, to: &entries)
        plan[i].plannedEntries = entries
        appliedProposals.append(AppliedProposal(id: "insight-\(ins.id)", text: ins.text, before: before, appliedAt: Date()))
        if alsoTemplate, let tid = plan[i].templateId, let ti = templates.firstIndex(where: { $0.id == tid }) { var e = templates[ti].entries; InsightEngine.apply(c, to: &e); templates[ti].entries = e; templates[ti].updatedAt = Date() }
        if appliedProposals.count > 20 { appliedProposals.removeFirst(appliedProposals.count - 20) }
        return true
    }
    func ignoreInsight(_ ins: WorkoutInsight) { if !ignoredInsights.contains(ins.id) { ignoredInsights.append(ins.id); if ignoredInsights.count > 50 { ignoredInsights.removeFirst() } } }

    /// What the centre tab button means today (local calendar date, actual scheduled activities, completion).
    enum TodayAction: Equatable, Identifiable {
        case ride(Workout), train(Workout), choose([Workout]), rest, doneToday(next: Workout?), inProgress
        var id: String { switch self { case .ride(let w): return "ride-\(w.id)"; case .train(let w): return "train-\(w.id)"; case .choose(let ws): return "choose-\(ws.map { $0.id.uuidString }.joined())"; case .rest: return "rest"; case .doneToday: return "done"; case .inProgress: return "inprogress" } }
    }
    func todayAction(now: Date = Date(), calendar cal: Calendar = .current) -> TodayAction {
        if activeSession != nil { return .inProgress }
        let items = plan.filter { cal.isDate($0.date, inSameDayAs: now) && $0.kind != .rest && $0.kind != .recoveryDay && !$0.skipped }.sorted { $0.sequence < $1.sequence }
        let open = items.filter { !$0.done }
        if items.isEmpty { return .rest }
        if open.isEmpty {
            let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))!
            let next = plan.filter { $0.date >= tomorrow && $0.kind != .rest && $0.kind != .recoveryDay && !$0.done && !$0.skipped }.min { $0.date < $1.date }
            return .doneToday(next: next)
        }
        let rides = open.filter { $0.kind.isRide }, lifts = open.filter { $0.kind == .strength }
        if !rides.isEmpty, !lifts.isEmpty { return .choose(open) }
        if let r = rides.first { return .ride(r) }
        if let l = lifts.first { return .train(l) }
        return .choose(open)
    }

    /// Rebuilds one week from the availability. Hand-edited sessions are kept unless `replaceEdited` is true (the
    /// caller asks the rider first). Past days and completed sessions are never touched.
    /// The availability fitted to both budgets, with the conflicts and the trims the fit had to make (for Fix plan).
    var fitReport: (availability: WeeklyAvailability, conflicts: [PlanConflict], trimmed: [String]) { WeeklyAvailability.fit(effectiveAvailability, profile: profile) }

    @discardableResult
    func regenerate(weekOf date: Date, replaceEdited: Bool) -> [String] {
        let cal = Calendar.current
        let d0 = cal.startOfDay(for: date)
        let wd = (cal.component(.weekday, from: d0) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: d0)!
        let sunday = cal.date(byAdding: .day, value: 7, to: monday)!
        let today = cal.startOfDay(for: Date())
        let fresh = applyWeekdayRoutines(PlanEngine.week(starting: monday, profile: profile, availability: effectiveAvailability, returning: cyclingReturnPhase(), trainingWeeks: consecutiveTrainingWeeks(before: monday)))
        var next = plan.filter { !($0.date >= monday && $0.date < sunday) }
        let old = plan.filter { $0.date >= monday && $0.date < sunday }
        for day in 0..<7 {
            let date = cal.date(byAdding: .day, value: day, to: monday)!
            let existing = old.filter { cal.isDate($0.date, inSameDayAs: date) }
            let keep = existing.filter { $0.done || cal.startOfDay(for: $0.date) < today || ($0.edited && !replaceEdited) }
            if keep.isEmpty {
                // a hand-assigned routine on a replaced strength session carries over to the new session of that day
                let manual = existing.first { $0.kind == .strength && $0.routineManual && $0.templateId != nil }
                next.append(contentsOf: fresh.filter { cal.isDate($0.date, inSameDayAs: date) }.map { w in
                    guard w.kind == .strength, let m = manual else { return w }
                    var x = w; x.templateId = m.templateId; x.plannedEntries = m.plannedEntries; x.routineManual = true; return x })
            } else { next.append(contentsOf: keep) }
        }
        plan = next.sorted { $0.date < $1.date }
        return PlanEngine.changes(from: old, to: plan.filter { $0.date >= monday && $0.date < sunday })
    }
    /// Hand-edited sessions in a week (so the UI can ask before replacing them).
    func editedCount(weekOf date: Date) -> Int { workouts(weekOf: date).filter { $0.edited && !$0.done }.count }

    var today: Workout? { plan.first { Calendar.current.isDateInToday($0.date) } }
    func workouts(weekOf date: Date) -> [Workout] {
        let cal = Calendar.current; let d0 = cal.startOfDay(for: date)
        let wd = (cal.component(.weekday, from: d0) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: d0)!
        let sunday = cal.date(byAdding: .day, value: 7, to: monday)!
        return plan.filter { $0.date >= monday && $0.date < sunday }.sorted { $0.date < $1.date }
    }
    func update(_ w: Workout) { if let i = plan.firstIndex(where: { $0.id == w.id }) { plan[i] = w } }
    /// A change the rider made by hand: saved and flagged so regeneration asks first.
    func edit(_ w: Workout) { var x = w; x.edited = true; update(x) }
    /// Removes a planned session (soft: kept in `trash` with Undo; logs that completed it are kept as extra sessions).
    func remove(_ w: Workout) { deleteWorkout(w) }
    func add(_ w: Workout) { var x = w; x.edited = true; plan.append(x); plan.sort { $0.date < $1.date } }
    func swapDays(_ a: Workout, _ b: Workout) {
        guard let i = plan.firstIndex(where: { $0.id == a.id }), let j = plan.firstIndex(where: { $0.id == b.id }) else { return }
        let da = plan[i].date; plan[i].date = plan[j].date; plan[j].date = da
        plan[i].edited = true; plan[j].edited = true
    }

    /// Adds a finished ride. Demo rides never enter history; a board ride already imported (same board ride id) is
    /// ignored, so a ride can never appear twice or under two recorders.
    @discardableResult
    func addRide(_ r: RideRecord) -> Bool {
        guard !r.demo else { return false }
        if let b = r.boardRideId, rides.contains(where: { $0.boardRideId == b && $0.recorder == .board }) { return false }
        if rides.contains(where: { $0.id == r.id }) { return false }
        rides.insert(r, at: 0)
        if let t = today, t.kind.isRide, !t.done, Calendar.current.isDate(r.start, inSameDayAs: t.date) { var w = t; w.done = true; w.completion = .recorded; w.completedAt = Date(); update(w) }
        considerFTP(from: r)
        return true
    }
    func deleteRide(_ r: RideRecord) { rides.removeAll { $0.id == r.id }; if ftpSuggestion?.rideId == r.id { ftpSuggestion = nil } }

    // MARK: strength sessions (0.6.0) — quick logs and Apple Health imports; hours kept apart from riding
    /// Adds a strength session unless the same one is already stored (same Health UUID, or start within ±2 min and
    /// a similar duration). Marks today's planned strength session done when the log is for today.
    @discardableResult
    func addStrength(_ s: StrengthSession) -> Bool {
        if let h = s.healthUUID, strength.contains(where: { $0.healthUUID == h }) { return false }
        if strength.contains(where: { $0.id == s.id }) { return false }
        // A5: one completed log per planned workout. A detailed log replaces a quick log of the same workout; a quick
        // log (or import) for a workout that already has a log is refused instead of counted twice.
        if let wid = s.workoutId, let j = strength.firstIndex(where: { $0.workoutId == wid }) {
            if s.isDetailed && !strength[j].isDetailed { strength.remove(at: j) } else if !s.isDetailed { return false }
        }
        if strength.contains(where: { StrengthSession.sameSession($0, s) }) { return false }
        var s = s
        let cal = Calendar.current
        // quality release: the link to a planned session is explicit and stored on the log. A log never completes a
        // session planned for a later day; without a link, the open strength session of the log's own day is the one
        // it represents (unless the rider saved it as an extra session).
        if let wid = s.workoutId, let w = plan.first(where: { $0.id == wid }), cal.startOfDay(for: w.date) > cal.startOfDay(for: s.date) { s.workoutId = nil }
        if s.workoutId == nil, s.unplanned != true, let w = plan.filter({ $0.kind == .strength && !$0.done && !$0.skipped && cal.isDate($0.date, inSameDayAs: s.date) }).min(by: { $0.sequence < $1.sequence }) { s.workoutId = w.id }
        strength.insert(s, at: 0)
        strength.sort { $0.date > $1.date }
        if let wid = s.workoutId, let i = plan.firstIndex(where: { $0.id == wid }) { plan[i].done = true; plan[i].completion = .recorded; plan[i].completedAt = s.date; plan[i].manualMinutes = nil }
        consumeTemporaryBlocks()
        // 0.8.0: a completed session never rewrites its template (exercise order, sets and notes stay as the rider saved
        // them); the next use is prefilled from this session via lastSession(template:).
        if let t = s.templateId, let i = templates.firstIndex(where: { $0.id == t }) { templates[i].lastUsed = s.date }
        // loads of coach-built future sessions follow the newest logged performance
        if s.isDetailed { refreshGeneratedSessions() }
        return true
    }
    /// Deletes a log (soft: kept in `trash` with Undo); the planned session it completed goes back to planned.
    func deleteStrength(_ s: StrengthSession) { deleteStrengthLog(s) }
    func updateStrength(_ s: StrengthSession) { if let i = strength.firstIndex(where: { $0.id == s.id }) { strength[i] = s } }

    // MARK: exercises and templates (0.7.0)
    var allExercises: [Exercise] { customExercises + ExerciseCatalogue.builtIn.filter { b in !customExercises.contains { $0.id == b.id } } }
    func addCustomExercise(_ e: Exercise) { var x = e; x.custom = true; if x.id.isEmpty { x.id = "custom-\(UUID().uuidString)" }; customExercises.insert(x, at: 0) }
    func removeCustomExercise(_ e: Exercise) { customExercises.removeAll { $0.id == e.id } }
    func saveTemplate(_ t: WorkoutTemplate) { if let i = templates.firstIndex(where: { $0.id == t.id }) { templates[i] = t } else { templates.insert(t, at: 0) } }
    func deleteTemplate(_ t: WorkoutTemplate) { templates.removeAll { $0.id == t.id } }
    func lastSession(template t: WorkoutTemplate) -> StrengthSession? { strength.filter { $0.templateId == t.id && $0.isDetailed }.max { $0.date < $1.date } }

    // MARK: coach proposals (0.7.0): applied only on Accept, always undoable; fixed days and manual edits are refused
    @discardableResult
    func apply(_ p: CoachProposal, allowFixed: Bool = false) -> Bool {
        func target(_ id: UUID) -> Int? { plan.firstIndex { $0.id == id && (allowFixed || !$0.fixed) && !$0.edited && !$0.done } }
        switch p.change {
        case .move(let id, let to):
            guard let i = target(id) else { return false }
            let before = plan[i]; plan[i].date = to
            appliedProposals.append(AppliedProposal(id: p.id, text: p.text, before: before, appliedAt: Date()))
        case .kind(let id, let k):
            guard let i = target(id) else { return false }
            let before = plan[i]; plan[i].kind = k
            appliedProposals.append(AppliedProposal(id: p.id, text: p.text, before: before, appliedAt: Date()))
        case .minutes(let id, let m):
            guard let i = target(id) else { return false }
            let before = plan[i]; plan[i].minutes = m
            appliedProposals.append(AppliedProposal(id: p.id, text: p.text, before: before, appliedAt: Date()))
        case .focus(let id, let f):
            guard let i = target(id) else { return false }
            let before = plan[i]; plan[i].strengthFocus = f
            appliedProposals.append(AppliedProposal(id: p.id, text: p.text, before: before, appliedAt: Date()))
        }
        if appliedProposals.count > 20 { appliedProposals.removeFirst(appliedProposals.count - 20) }
        return true
    }
    /// Restores the workout as it was before the most recent accepted proposal (if it still exists and is not done).
    @discardableResult
    func undoLastProposal() -> Bool {
        guard let last = appliedProposals.last else { return false }
        appliedProposals.removeLast()
        guard let i = plan.firstIndex(where: { $0.id == last.before.id }), !plan[i].done else { return false }
        plan[i] = last.before
        return true
    }
    /// Imports a ride that Apple Health knows about and the phone/board do not (start ±2 min, similar duration). Source
    /// "Apple Health"; no power, cadence or samples are invented.
    @discardableResult
    func importHealthRide(start: Date, durationS: Int, distanceM: Int?, kj: Int?, avgHR: Int?, healthUUID: String) -> Bool {
        if rides.contains(where: { $0.healthUUID == healthUUID }) { return false }
        if rides.contains(where: { abs($0.start.timeIntervalSince(start)) <= 120 && abs($0.durationS - durationS) <= max(60, durationS / 10) }) { return false }
        var r = RideRecord(start: start, durationS: durationS, distanceM: distanceM ?? 0, recorder: .health, sources: ["Apple Health"])
        r.kj = kj; r.avgHR = avgHR; r.healthUUID = healthUUID
        let at = rides.firstIndex { $0.start < r.start } ?? rides.count
        rides.insert(r, at: at)
        return true
    }

    // MARK: FTP from rides
    /// 0.95 × best 20-minute power (Coggan). Proposed only; needs ≥ 2 % difference from the current FTP.
    static func proposedFTP(best20: Int) -> Int { Int((Double(best20) * 0.95).rounded()) }
    func considerFTP(from r: RideRecord) {
        guard !r.demo, let b20 = r.best20 else { return }
        let w = Self.proposedFTP(best20: b20)
        guard abs(w - profile.ftpW) * 50 >= profile.ftpW else { return }       /* < 2 % change: nothing to propose */
        if let s = ftpSuggestion, s.rideDate > r.start { return }               /* keep the newer suggestion */
        var sug = FTPSuggestion(watts: w, best20: b20, best60: r.best60, rideId: r.id, rideDate: r.start, previousFTP: profile.ftpW)
        sug.powerVerified = r.powerVerified == true
        sug.testProtocol = plan.contains { $0.kind == .ftpTest && Calendar.current.isDate($0.date, inSameDayAs: r.start) }
        ftpSuggestion = sug
    }
    /// Same rule for a board summary that carries best20 but no samples.
    func considerFTP(boardBest20 b20: Int, ride r: RideRecord) {
        let w = Self.proposedFTP(best20: b20)
        guard abs(w - profile.ftpW) * 50 >= profile.ftpW else { return }
        if let s = ftpSuggestion, s.rideDate > r.start { return }
        ftpSuggestion = FTPSuggestion(watts: w, best20: b20, best60: nil, rideId: r.id, rideDate: r.start, previousFTP: profile.ftpW)
    }
    /// Accepting a suggestion: a planned FTP test ride with verified power becomes a verified test; any other ride an
    /// estimate whose confidence follows the ride's power verification (ios/QUALITY_RELEASE.md, FTP confidence).
    func acceptFTPSuggestion() {
        guard let s = ftpSuggestion else { return }
        let verified = s.powerVerified == true
        let test = verified && s.testProtocol == true
        updateProfile { $0.ftpW = s.watts; $0.ftpHow = test ? .tested : .fromRides; $0.ftpFromDate = s.rideDate; $0.ftpPowerVerified = verified; $0.ftpVerifiedTest = test }
        ftpSuggestion = nil
    }
    func dismissFTPSuggestion() { ftpSuggestion = nil }

    // MARK: board history import (ios/SYNC_PROPOSAL.md) — the board owns these rides
    /// Returns true when a record was added or merged. Keyed by board id + start time (or ride id when the clock was unknown).
    @discardableResult
    func importBoardRide(_ b: BCLink.RideSummary, boardId: String) -> Bool {
        guard !b.demo else { return false }
        let start = b.startEpochS > 0 ? Date(timeIntervalSince1970: TimeInterval(b.startEpochS)) : Date(timeIntervalSince1970: 0)
        // 1. exact key match → refresh totals, keep samples
        if let i = rides.firstIndex(where: { $0.recorder == .board && $0.boardId == boardId && (b.startEpochS > 0 ? abs($0.start.timeIntervalSince(start)) < 1 : $0.boardRideId == b.id) }) {
            rides[i] = Self.merge(rides[i], with: b, boardId: boardId, start: start); return true
        }
        // 2. the phone's live mirror of the same ride (same board ride id, start within 10 min, not yet keyed)
        if let i = rides.firstIndex(where: { $0.recorder == .board && $0.boardRideId == b.id && ($0.boardId == nil || $0.boardId == boardId) && (b.startEpochS == 0 || abs($0.start.timeIntervalSince(start)) < 600) }) {
            rides[i] = Self.merge(rides[i], with: b, boardId: boardId, start: start); return true
        }
        // 3. new ride the phone never saw
        var r = RideRecord(start: start, durationS: b.durationS, distanceM: b.distanceM, recorder: .board, sources: ["BikeComputer"])
        r.powerVerified = PowerTrust.meterVerified
        r = Self.merge(r, with: b, boardId: boardId, start: start)
        let at = rides.firstIndex { $0.start < r.start } ?? rides.count
        rides.insert(r, at: at)
        if let b20 = b.best20 { considerFTP(boardBest20: b20, ride: r) }
        return true
    }
    private static func merge(_ r0: RideRecord, with b: BCLink.RideSummary, boardId: String, start: Date) -> RideRecord {
        var r = r0
        r.boardRideId = b.id; r.boardId = boardId
        if b.startEpochS > 0 { r.start = start }
        r.durationS = b.durationS; r.distanceM = b.distanceM
        r.avgPower = b.avgPower; r.maxPower = b.maxPower; r.avgCadence = b.avgCadence; r.avgHR = b.avgHR; r.maxHR = b.maxHR; r.kj = b.kj
        if b.zonesValid { r.zoneSeconds = b.zoneS }
        var src = ["BikeComputer"]
        if b.avgPower != nil { src.append("Power meter") }
        if b.avgHR != nil { src.append("Heart rate") }
        if b.distSrc != 0 { src.append("GPS") }
        if r.hasTrack { src.append("Phone GPS") }
        r.sources = src
        return r
    }
    func highestBoardRideId(for boardId: String) -> Int { rides.filter { $0.boardId == boardId }.compactMap { $0.boardRideId }.max() ?? 0 }

    /// Weekly totals for Progress (last `weeks` weeks, oldest first).
    struct WeekTotal: Identifiable { var id: Date { monday }; let monday: Date; let minutes: Int; let km: Double; let rides: Int }
    func weekTotals(weeks: Int = 8) -> [WeekTotal] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let thisMonday = cal.date(byAdding: .day, value: -wd, to: today)!
        return (0..<weeks).reversed().map { k in
            let m = cal.date(byAdding: .day, value: -7 * k, to: thisMonday)!
            let e = cal.date(byAdding: .day, value: 7, to: m)!
            let rs = rides.filter { $0.start >= m && $0.start < e }
            return WeekTotal(monday: m, minutes: rs.reduce(0) { $0 + $1.durationS } / 60, km: Double(rs.reduce(0) { $0 + $1.distanceM }) / 1000, rides: rs.count)
        }
    }

    /// Weekly lifting totals (0.6.0), kept apart from riding. Quality release: from the one query layer
    /// (TrainingLedger), so Home, Plan, Progress and History count the same sessions.
    struct StrengthWeekTotal: Identifiable { var id: Date { monday }; let monday: Date; let minutes: Int; let sessions: Int; var week: TrainingLedger.SportWeek? = nil }
    func strengthWeekTotals(weeks: Int = 8, now: Date = Date()) -> [StrengthWeekTotal] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let thisMonday = cal.date(byAdding: .day, value: -wd, to: today)!
        let l = ledger
        return (0..<weeks).reversed().map { k in
            let m = cal.date(byAdding: .day, value: -7 * k, to: thisMonday)!
            let w = l.lifting(weekOf: m)
            return StrengthWeekTotal(monday: m, minutes: w.minutes, sessions: w.completed, week: w)
        }
    }

    /// Guideline 5.1.1(v): everything the app stores about the rider can be removed in-app.
    func resetAll() {
        loading = true
        rides = []; plan = []; profile = RiderProfile(); settings = AppSettings(); onboarded = false; guest = true; appleUserId = nil; ftpSuggestion = nil
        tiles = Store.defaultTiles; createdAt = Date(); boardSync = []; onboardingStage = 0; availability = nil; strength = []
        templates = []; customExercises = []; appliedProposals = []
        weekdayRoutines = [:]; equipment = EquipmentProfile(); activeSession = nil; ignoredInsights = []
        adaptations = []; dismissedAdaptations = []; approvedAdaptations = []; adaptiveProposals = []; lastAdaptation = nil; painClearances = []
        strengthPrefs = StrengthPrefs(); trash = []; migrationLog = []; undoToast = nil
        loading = false
        for n in ["store.json", "profile.json", "plan.json", "rides.json", "tiles.json"] { try? FileManager.default.removeItem(at: dir.appendingPathComponent(n)) }
        for k in ["bc.onboarded", "bc.guest", "bc.appleUser"] { UserDefaults.standard.removeObject(forKey: k) }
        ensurePlan()
    }

    // MARK: persistence
    private func persist() {
        guard !loading else { return }
        do {
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
            let d = try enc.encode(snapshot)
            try d.write(to: dir.appendingPathComponent("store.json"), options: .atomic)
            lastSaveError = nil
        } catch { lastSaveError = error.localizedDescription }
    }
    private static func read<T: Decodable>(_ url: URL) -> T? {
        guard let d = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let v = try? dec.decode(T.self, from: d) { return v }
        return try? JSONDecoder().decode(T.self, from: d)      /* build-14 files used the default date encoding */
    }
}

// MARK: - Coach (rules). Deterministic plain-word notes; no model is involved in this build and the UI says "Coach (rules)".
enum Coach {
    /// ONE line for the top of Home: "Today: 45-minute easy endurance ride to improve aerobic fitness."
    static func todayLine(_ t: Workout?) -> String {
        guard let t else { return "Today: nothing planned." }
        switch t.kind {
        case .rest: return "Today: rest day — adaptation happens here."
        case .recoveryDay: return "Today: recovery day — light movement, early night."
        case .strength, .mobility, .other: return "Today: \(Fmt.duration(minutes: t.minutes)) \(t.displayTitle.lowercased()) session off the bike for \(t.benefit)."
        case .recovery: return "Today: \(Fmt.duration(minutes: t.minutes)) easy recovery spin to loosen the legs."
        case .ftpTest: return "Today: FTP test — \(t.minutes) minutes with a 20-minute all-out effort for a real number."
        default: return "Today: \(Fmt.duration(minutes: t.minutes)) \(t.kind.title.lowercased()) ride (Zone \(t.kind.zone)) to improve \(t.benefit)."
        }
    }
    /// "Why this workout?" — uses only what the app actually has: the plan, recent rides, the FTP label. Never sleep,
    /// HRV or recovery data (no source is connected in this build), and says so.
    static func why(_ t: Workout?, store s: Store) -> String {
        guard let t else { return "No session is planned for today." }
        var parts: [String] = [t.why]
        let cal = Calendar.current
        let recent = s.rides.filter { $0.start > cal.date(byAdding: .day, value: -7, to: Date())! }
        if let last = s.rides.first {
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: last.start), to: cal.startOfDay(for: Date())).day ?? 0
            var l = days == 0 ? "You rode today" : days == 1 ? "Your last ride was yesterday" : "Your last ride was \(days) days ago"
            l += " (\(Fmt.duration(seconds: last.durationS))" + (last.avgPower.map { ", \($0) W average" } ?? ", no power data") + ")."
            parts.append(l)
            if days >= 1, days <= 2, last.avgPower.map({ s.profile.zone(forWatts: $0) >= 3 }) == true, t.kind.zone <= 2 { parts.append("Yesterday's effort was hard, so today stays easy on purpose.") }
        } else { parts.append("No rides are recorded yet, so the plan starts from your goal, hours and level only.") }
        if !recent.isEmpty { parts.append("This week so far: \(Fmt.duration(seconds: recent.reduce(0) { $0 + $1.durationS })) in \(recent.count) ride\(recent.count == 1 ? "" : "s") of your \(s.profile.hoursPerWeek) h.") }
        parts.append("Goal: \(s.profile.goal.title.lowercased()); level: \(s.profile.level.title.lowercased()).")
        if s.profile.ftpHow == .assumed { parts.append("Targets use a provisional FTP of \(s.profile.ftpW) W; they will tighten once a real 20-minute effort is recorded.") }
        parts.append("No sleep, HRV or recovery source is connected, so recovery is not part of this recommendation.")
        return parts.joined(separator: " ")
    }
    /// Alternatives for today: one easier, one shorter, one off the bike.
    static func alternatives(for t: Workout) -> [Workout] {
        var out: [Workout] = []
        if t.kind.zone > 1 { var a = t; a.kind = .recovery; a.minutes = max(30, t.minutes / 2); out.append(a) }
        if t.minutes > 45 { var b = t; b.minutes = max(30, t.minutes * 2 / 3); out.append(b) }
        if t.kind.isRide { var c = t; c.kind = .mobility; c.minutes = 30; out.append(c) }
        if !t.kind.isRide { var d = t; d.kind = .endurance; d.minutes = 45; out.append(d) }
        return out
    }
    static func homeNote(store s: Store, device: DeviceLink?) -> String {
        let last = s.rides.first
        guard let t = s.today else { return "No plan for today." }
        var out = ""
        if let l = last, let p = l.avgPower { out += "Last ride: \(Fmt.duration(seconds: l.durationS)) at \(p) W" + (l.avgHR.map { ", HR \($0)" } ?? "") + ". " }
        else if let l = last { out += "Last ride: \(Fmt.duration(seconds: l.durationS)), \(String(format: "%.1f", Double(l.distanceM) / 1000)) km (no power data). " }
        else { out += "No rides recorded yet. " }
        switch t.kind {
        case .rest: out += "Today is a rest day."
        case .recoveryDay: out += "Recovery day: light movement, early night."
        default: out += "Today: \(t.kind.title.lowercased()), \(Fmt.duration(minutes: t.minutes))."
        }
        if s.profile.ftpHow == .assumed { out += " Your FTP is still an assumption; a steady 20-minute effort in a real ride will replace it." }
        return out
    }
    static func rideSummary(_ r: RideRecord, profile p: RiderProfile) -> String {
        guard let avg = r.avgPower else { return "Recorded on the phone without a power meter: distance and time are real, no power analysis is possible. Connect the BikeComputer for watts." }
        let z = p.zone(forWatts: avg)
        var s = "Average \(avg) W is Zone \(z) for your FTP of \(p.ftpW) W (\(p.ftpLabel))."
        if let hr = r.avgHR { s += String(format: " Efficiency %.2f W per beat.", Double(avg) / Double(hr)) }
        if r.durationS >= 1200, p.ftpHow == .assumed { s += " No qualifying 20-minute effort yet (needs a steady block clearly harder than the rest)." }
        return s
    }
}
