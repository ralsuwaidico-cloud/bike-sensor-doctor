import Foundation

// MARK: - Personalised strength programming (quality release). Deterministic rules, no model, every decision explained.
//
// Inputs: goal, hybrid priority, strength experience, split / session type, weekly frequency, session minutes,
// equipment (incl. custom items and temporary unavailability), favourites and swap preferences, recent and planned
// cycling load, logged lifting performance (only LOGGED sets of the SAME exercise), check-in pain and fatigue.
// Principles (general, established): progressive overload by double progression from logged data, movement-pattern
// coverage, weekly volume per region scaled by experience and priority, rep ranges by goal, fatigue management and
// deloads, and concurrent-training interference (no heavy lower body within ~24 h before a key ride or the day after a
// long / hard ride; less lower-body volume in high cycling-load weeks). Fixed days, session types and the rider's own
// routines are never changed here: the planner only fills coach-built sessions.

// MARK: Exercise metadata
enum MovementSlot: String, Codable, CaseIterable {
    case squat, hinge, lunge, horizontalPush, verticalPush, horizontalPull, verticalPull, core, carry, arms, calves, accessory
    var title: String {
        switch self {
        case .squat: return "squat"; case .hinge: return "hip hinge"; case .lunge: return "lunge / single-leg"
        case .horizontalPush: return "horizontal push"; case .verticalPush: return "vertical push"
        case .horizontalPull: return "horizontal pull"; case .verticalPull: return "vertical pull"
        case .core: return "core / trunk"; case .carry: return "loaded carry"; case .arms: return "arms (isolation)"
        case .calves: return "calves"; case .accessory: return "accessory"
        }
    }
    /// The coarse pattern used for coverage elsewhere in the app.
    var family: MovementPattern {
        switch self {
        case .squat: return .squat; case .hinge: return .hinge; case .lunge: return .singleLeg
        case .horizontalPush, .verticalPush: return .push; case .horizontalPull, .verticalPull: return .pull
        case .core: return .core; case .carry: return .carry; case .arms, .calves, .accessory: return .other
        }
    }
    var isLower: Bool { self == .squat || self == .hinge || self == .lunge || self == .calves }
}

/// Loading characteristics used for pain restrictions and "similar loading" flags. Not a diagnosis.
enum LoadTag: String, Codable, CaseIterable {
    case kneeFlexion, spinalLoad, overhead, wristExtension, impact
    var title: String {
        switch self {
        case .kneeFlexion: return "deep knee bending under load"
        case .spinalLoad: return "heavy loading through the spine"
        case .overhead: return "arms overhead"
        case .wristExtension: return "weight on bent wrists"
        case .impact: return "jumping / impact"
        }
    }
    static func forPain(_ a: PainArea) -> Set<LoadTag> {
        switch a {
        case .knees: return [.kneeFlexion, .impact]
        case .back: return [.spinalLoad]
        case .upperBody: return [.overhead, .wristExtension]
        case .hipsLegs: return [.kneeFlexion, .impact, .spinalLoad]
        case .other: return []
        }
    }
}

struct ExerciseMeta: Equatable {
    var slot: MovementSlot
    var primary: [String]
    var secondary: [String]
    /// 1 = simple / machine / bodyweight basics, 2 = standard free-weight compound, 3 = technical or very demanding.
    var difficulty: Int
    var tags: Set<LoadTag>
    var compound: Bool
}

enum ExerciseLibrary {
    /// Equipment that is needed IN ADDITION to the load (a bench, a bar to hang from).
    static let accessories: Set<String> = ["bench", "pull-up bar"]
    /// Built-in exercises that hang from a bar although the catalogue lists them as bodyweight.
    static let needsBar: Set<String> = ["ex-100", "ex-101", "ex-102", "ex-119", "ex-132"]

    /// What an exercise needs: every item of `all`, and one item of `anyOf` (empty = no load equipment needed).
    /// The catalogue lists alternatives ("dumbbell, kettlebell" = either) plus accessories ("barbell, bench" = both).
    static func requirement(_ e: Exercise) -> (all: Set<String>, anyOf: Set<String>) {
        let eq = Set(e.equipment.map(EquipmentProfile.normalised))
        var all = eq.intersection(accessories)
        if needsBar.contains(e.id) { all.insert("pull-up bar") }
        let rest = eq.subtracting(accessories).subtracting(["bodyweight"])
        return (all, eq.contains("bodyweight") ? [] : rest)
    }

    static func meta(_ e: Exercise) -> ExerciseMeta {
        let n = e.name.lowercased()
        func has(_ ks: [String]) -> Bool { ks.contains { n.contains($0) } }
        var slot: MovementSlot
        var compound = true
        switch e.pattern {
        case .squat:
            slot = .squat; if has(["leg extension", "wall sit", "sissy"]) { compound = false }
        case .hinge:
            slot = .hinge; if has(["leg curl", "hamstring curl", "back extension", "reverse hyper", "pull-through"]) { compound = false }
        case .singleLeg:
            if has(["calf"]) { slot = .calves; compound = false } else { slot = .lunge }
        case .push:
            if has(["triceps", "skull", "pushdown"]) { slot = .arms; compound = false }
            else if has(["raise", "fly", "pec deck"]) { slot = .accessory; compound = false }
            else if has(["overhead", "shoulder press", "push press", "arnold", "pike", "handstand", "landmine press", "kettlebell press", "military"]) { slot = .verticalPush }
            else { slot = .horizontalPush }
        case .pull:
            if has(["curl"]) { slot = .arms; compound = false }
            else if has(["shrug", "face pull", "pull-apart", "rear delt", "upright"]) { slot = .accessory; compound = false }
            else if has(["pull-up", "chin-up", "pulldown"]) { slot = .verticalPull; if has(["straight-arm"]) { compound = false } }
            else { slot = .horizontalPull }
        case .core: slot = .core; compound = false
        case .carry: slot = .carry
        case .other: slot = has(["calf"]) ? .calves : .accessory; compound = false
        }
        var tags = Set<LoadTag>()
        let barbell = e.equipment.map(EquipmentProfile.normalised).contains("barbell")
        if (slot == .squat || slot == .lunge) && !has(["glute bridge", "hip thrust"]) { tags.insert(.kneeFlexion) }
        if has(["leg press", "leg extension", "jump", "step-up", "step-down", "pistol", "cossack", "sissy"]) { tags.insert(.kneeFlexion) }
        if barbell && (slot == .squat || slot == .hinge || slot == .horizontalPull) && !has(["hip thrust", "glute bridge", "landmine"]) { tags.insert(.spinalLoad) }
        if e.pattern == .hinge && has(["good morning", "deadlift", "clean", "rack pull"]) && !has(["single-leg"]) { tags.insert(.spinalLoad) }
        if slot == .verticalPush || has(["overhead", "pull-up", "chin-up", "hanging", "toes to bar", "handstand"]) { tags.insert(.overhead) }
        if has(["push-up", "front squat", "front-rack", "renegade"]) { tags.insert(.wristExtension) }
        if has(["jump", "clean"]) { tags.insert(.impact) }
        var diff: Int
        if has(["clean", "snatch", "pistol", "handstand", "nordic", "overhead squat", "toes to bar", "zercher", "skater", "ab wheel", "copenhagen", "stir the pot", "kroc", "sissy"]) { diff = 3 }
        else if has(["pull-up", "chin-up", "dip", "hanging", "bulgarian", "sumo", "deadlift", "front squat", "back squat", "overhead press", "bench press", "barbell row", "t-bar", "push press", "good morning", "pendlay", "meadows"]) && !has(["bench dip", "assisted", "dumbbell bench"]) { diff = 2 }
        else if e.equipment.contains("machine") || e.equipment.contains("cable") || !compound || e.equipment == ["bodyweight"] || e.equipment.contains("dumbbell") || e.equipment.contains("kettlebell") || e.equipment.contains("band") { diff = 1 }
        else { diff = 2 }
        var primary = Array(e.muscles.prefix(2)), secondary = Array(e.muscles.dropFirst(2))
        if primary.isEmpty {
            switch slot {
            case .squat: primary = ["quads", "glutes"]; case .hinge: primary = ["hamstrings", "glutes"]; case .lunge: primary = ["quads", "glutes"]
            case .horizontalPush: primary = ["chest", "triceps"]; case .verticalPush: primary = ["shoulders", "triceps"]
            case .horizontalPull: primary = ["back", "biceps"]; case .verticalPull: primary = ["back", "biceps"]
            case .core: primary = ["core"]; case .carry: primary = ["grip", "core"]; case .arms: primary = ["arms"]; case .calves: primary = ["calves"]; case .accessory: primary = []
            }
        }
        if secondary.isEmpty, slot == .lunge { secondary = ["balance", "hip stability"] }
        return ExerciseMeta(slot: slot, primary: primary, secondary: secondary, difficulty: diff, tags: tags, compound: compound)
    }
}

// MARK: Rider preferences for strength programming (persisted in the store)
enum SwapReason: String, Codable, CaseIterable, Identifiable {
    case todayOnly, alwaysPrefer, noEquipment, temporarilyUnavailable, discomfort
    var id: String { rawValue }
    var title: String {
        switch self {
        case .todayOnly: return "Today only"
        case .alwaysPrefer: return "Always prefer this"
        case .noEquipment: return "I don't have this equipment"
        case .temporarilyUnavailable: return "Equipment temporarily unavailable"
        case .discomfort: return "Causes discomfort"
        }
    }
    var detail: String {
        switch self {
        case .todayOnly: return "Only this session changes."
        case .alwaysPrefer: return "Future coach-built sessions use it instead."
        case .noEquipment: return "Removed from your equipment; never recommended again."
        case .temporarilyUnavailable: return "Avoided until a date or for a number of sessions."
        case .discomfort: return "Excluded; similar movements are flagged for you to check."
        }
    }
}

struct AvoidEntry: Codable, Equatable { var exerciseId: String; var reason: SwapReason; var at: Date }
struct TemporaryBlock: Codable, Equatable, Identifiable {
    var id = UUID()
    var exerciseId: String
    var until: Date?
    var sessionsLeft: Int?
    var at: Date
    func active(now: Date) -> Bool { (until.map { $0 > now } ?? true) && (sessionsLeft.map { $0 > 0 } ?? true) && !(until == nil && sessionsLeft == nil) }
}
struct SwapRecord: Codable, Equatable { var from: String; var to: String; var reason: SwapReason; var at: Date; var workoutId: UUID? }

struct StrengthPrefs: Codable, Equatable {
    enum Experience: String, Codable, CaseIterable {
        case beginner, intermediate, advanced
        var title: String { switch self { case .beginner: return "New to lifting"; case .intermediate: return "Some lifting experience"; case .advanced: return "Experienced lifter" } }
        var maxDifficulty: Int { switch self { case .beginner: return 1; case .intermediate: return 2; case .advanced: return 3 } }
    }
    enum Goal: String, Codable, CaseIterable {
        case strength, hypertrophy, enduranceSupport, general
        var title: String { switch self { case .strength: return "Maximal strength"; case .hypertrophy: return "Muscle size"; case .enduranceSupport: return "Support my cycling"; case .general: return "General strength" } }
    }
    var experience: Experience? = nil
    var goal: Goal? = nil
    var favourites: [String] = []
    /// replaced exercise id → the exercise the rider always wants instead
    var alwaysPrefer: [String: String] = [:]
    var avoid: [AvoidEntry] = []
    var reviewFlags: [String] = []
    var temporary: [TemporaryBlock] = []
    var swapHistory: [SwapRecord] = []

    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        experience = try? c.decodeIfPresent(Experience.self, forKey: .experience)
        goal = try? c.decodeIfPresent(Goal.self, forKey: .goal)
        favourites = (try? c.decodeIfPresent([String].self, forKey: .favourites)) ?? []
        alwaysPrefer = (try? c.decodeIfPresent([String: String].self, forKey: .alwaysPrefer)) ?? [:]
        avoid = (try? c.decodeIfPresent([AvoidEntry].self, forKey: .avoid)) ?? []
        reviewFlags = (try? c.decodeIfPresent([String].self, forKey: .reviewFlags)) ?? []
        temporary = (try? c.decodeIfPresent([TemporaryBlock].self, forKey: .temporary)) ?? []
        swapHistory = (try? c.decodeIfPresent([SwapRecord].self, forKey: .swapHistory)) ?? []
    }
    func avoids(_ id: String) -> Bool { avoid.contains { $0.exerciseId == id } }
    func blocked(_ id: String, now: Date) -> Bool { temporary.contains { $0.exerciseId == id && $0.active(now: now) } }
}

// MARK: The planner's decision record (stored on the session it built; drives "Why?")
struct ExerciseRationale: Codable, Equatable {
    var exerciseId: String
    var role: String
    var slot: String
    var dose: String
    var load: String
    var cycling: String?
    var progressed: Bool
    var targetRPE: Int?
}
struct SessionRationale: Codable, Equatable {
    var generatedAt: Date
    var goal: String
    var notes: [String]
    var exercises: [ExerciseRationale]
    var deload: Bool
    func exercise(_ id: String) -> ExerciseRationale? { exercises.first { $0.exerciseId == id } }
}

/// Everything the planner reads. Built by `Store.plannerContext()`; tests build it directly.
struct PlannerContext {
    var profile: RiderProfile
    var prefs: StrengthPrefs = StrengthPrefs()
    var equipment: EquipmentProfile = EquipmentProfile()
    var catalogue: [Exercise] = []
    var templates: [WorkoutTemplate] = []
    /// Counted logs only (no record awaiting review, nothing in progress).
    var logs: [StrengthSession] = []
    var rides: [RideRecord] = []
    var plan: [Workout] = []
    var painAreas: [PainArea] = []
    var fatigue = false
    /// Shared hold (audit G-03): when the adaptive coach says "nothing is increased" (≥ 2 missed sessions in the last
    /// 7 days), the planner holds every load, rep and hold time too. The text completes "Held — …".
    var progressionHold: String? = nil
    var units: AppSettings.Units = .metric
    var now = Date()
    var calendar: Calendar = .current
    /// Coach remediation M-02: the lifting return phase (from logged dates; nil = no recent break).
    var returning: ReturnPhase? = nil
    /// Coach remediation M-01: what may be prescribed (health check).
    var readiness: CoachReadiness { profile.readiness }

    var experience: StrengthPrefs.Experience {
        if let e = prefs.experience { return e }
        switch profile.level { case .beginner: return .beginner; case .intermediate: return .intermediate; case .advanced: return .advanced }
    }
    var goal: StrengthPrefs.Goal {
        if let g = prefs.goal { return g }
        switch profile.hybridGoal {
        case .strength?: return .strength
        case .cyclingEndurance?: return .enduranceSupport
        case .balanced?, .generalFitness?: return .general
        default:
            if profile.trainingMode == .strength { return .hypertrophy }
            switch profile.priority { case .cycling: return .enduranceSupport; case .strength: return .strength; case .balanced: return .general }
        }
    }
    /// Priority as the planner sees it (strength mode = strength first).
    var priority: TrainingPriority { profile.trainingMode == .strength ? .strength : (profile.trainingMode == .cycling ? .cycling : profile.priority) }
    var painTags: Set<LoadTag> { painAreas.reduce(into: Set<LoadTag>()) { $0.formUnion(LoadTag.forPain($1)) } }
}

// MARK: - The planner
enum StrengthPlanner {
    enum Role: String { case main = "main lift", secondary = "secondary lift", accessory = "accessory", core = "core" }
    struct SlotSpec { var slot: MovementSlot; var role: Role; var hint: String? = nil }

    /// Movement slots of one session type, most important first (time trimming drops from the end).
    static func slots(focus: StrengthFocus, label: String, goal: StrengthPrefs.Goal, sessionIndex: Int) -> [SlotSpec] {
        let altVertical: MovementSlot = sessionIndex % 2 == 0 ? .verticalPull : .verticalPush
        switch focus {
        case .fullBody:
            if goal == .enduranceSupport {
                return [.init(slot: .squat, role: .main), .init(slot: .hinge, role: .main), .init(slot: .lunge, role: .secondary), .init(slot: .horizontalPull, role: .secondary),
                        .init(slot: .horizontalPush, role: .secondary), .init(slot: .core, role: .core), .init(slot: altVertical, role: .accessory), .init(slot: .carry, role: .accessory)]
            }
            return [.init(slot: .squat, role: .main), .init(slot: .hinge, role: .main), .init(slot: .horizontalPush, role: .secondary), .init(slot: .horizontalPull, role: .secondary),
                    .init(slot: .core, role: .core), .init(slot: altVertical, role: .accessory), .init(slot: .lunge, role: .accessory), .init(slot: .carry, role: .accessory)]
        case .upper:
            return [.init(slot: .horizontalPush, role: .main), .init(slot: .horizontalPull, role: .main), .init(slot: .verticalPush, role: .secondary), .init(slot: .verticalPull, role: .secondary),
                    .init(slot: .accessory, role: .accessory, hint: "rear shoulders"), .init(slot: .core, role: .core), .init(slot: .arms, role: .accessory, hint: "biceps")]
        case .lower, .legs:
            return [.init(slot: .squat, role: .main), .init(slot: .hinge, role: .main), .init(slot: .lunge, role: .secondary), .init(slot: .core, role: .core),
                    .init(slot: .calves, role: .accessory), .init(slot: .carry, role: .accessory)]
        case .push:
            return [.init(slot: .horizontalPush, role: .main), .init(slot: .verticalPush, role: .main), .init(slot: .horizontalPush, role: .secondary),
                    .init(slot: .arms, role: .accessory, hint: "triceps"), .init(slot: .accessory, role: .accessory, hint: "shoulders"), .init(slot: .core, role: .core)]
        case .pull:
            return [.init(slot: .verticalPull, role: .main), .init(slot: .horizontalPull, role: .main), .init(slot: .horizontalPull, role: .secondary),
                    .init(slot: .accessory, role: .accessory, hint: "rear shoulders"), .init(slot: .arms, role: .accessory, hint: "biceps"), .init(slot: .carry, role: .accessory)]
        case .custom:
            let l = label.lowercased()
            if ["core", "joint", "mobility", "prehab", "stability"].contains(where: { l.contains($0) }) {
                return [.init(slot: .core, role: .core), .init(slot: .lunge, role: .secondary), .init(slot: .accessory, role: .accessory, hint: "rear shoulders"), .init(slot: .core, role: .core), .init(slot: .carry, role: .accessory)]
            }
            return slots(focus: .fullBody, label: "", goal: goal, sessionIndex: sessionIndex)
        }
    }

    // MARK: availability
    /// Can the rider do this exercise now: not excluded or avoided, equipment owned and not temporarily unavailable,
    /// no loading that a recent pain report restricts.
    static func available(_ e: Exercise, ctx: PlannerContext) -> Bool {
        if ctx.equipment.excluded.contains(e.id) || ctx.prefs.avoids(e.id) || ctx.prefs.blocked(e.id, now: ctx.now) { return false }
        if !ctx.equipment.canDo(e) { return false }
        if !ExerciseLibrary.meta(e).tags.isDisjoint(with: ctx.painTags) { return false }
        return true
    }

    static func history(_ id: String, ctx: PlannerContext) -> [(session: StrengthSession, entry: ExerciseEntry)] {
        ctx.logs.filter { !$0.isImported && $0.date <= ctx.now }.sorted { $0.date > $1.date }
            .compactMap { s in s.exercises?.first(where: { $0.exerciseId == id && !$0.doneSets.isEmpty }).map { (s, $0) } }
    }

    private static func score(_ e: Exercise, _ m: ExerciseMeta, spec: SlotSpec, ctx: PlannerContext) -> Double {
        var sc = 0.0
        if ctx.prefs.favourites.contains(e.id) { sc += 6 }
        let preserved = ctx.templates.filter { ctx.profile.preservedTemplateIds.contains($0.id) }
        if preserved.contains(where: { t in t.entries.contains { $0.exerciseId == e.id } }) { sc += 4 }
        else if ctx.templates.contains(where: { t in t.entries.contains { $0.exerciseId == e.id } }) { sc += 2 }
        if e.custom { sc += 2 }
        if !history(e.id, ctx: ctx).isEmpty { sc += 3 }
        if (spec.role == .main || spec.role == .secondary) && m.compound { sc += 3 }
        // main / secondary lifts: prefer exercises the rider can load with equipment they own (a loaded hinge beats a
        // bodyweight bridge as the main lift; progression needs a load)
        if spec.role == .main || spec.role == .secondary {
            let loadOptions = Set(e.equipment.map(EquipmentProfile.normalised)).subtracting(ExerciseLibrary.accessories).subtracting(["bodyweight"])
            let owned = Set(ctx.equipment.owned.map(EquipmentProfile.normalised))
            if !loadOptions.isEmpty && (!ctx.equipment.isSet || !loadOptions.isDisjoint(with: owned)) { sc += 2 }
        }
        switch ctx.experience {
        case .beginner: if m.difficulty == 1 { sc += 2 }
        case .intermediate: if m.difficulty == 2 && spec.role == .main { sc += 1 }
        case .advanced: if m.difficulty >= 2 && spec.role == .main { sc += 2 }
        }
        if ctx.goal == .enduranceSupport, m.slot.isLower, e.unilateral { sc += 2 }
        if ctx.goal == .strength, spec.role == .main, e.equipment.contains("barbell") { sc += 1 }
        if !ctx.equipment.isSet {
            let r = ExerciseLibrary.requirement(e)
            if r.all.isEmpty && (r.anyOf.isEmpty || r.anyOf.contains("dumbbell")) { sc += 1 }
        }
        if let h = spec.hint, m.primary.contains(where: { $0.contains(h) || h.contains($0) }) { sc += 3 }
        if ctx.prefs.reviewFlags.contains(e.id) { sc -= 8 }
        sc += preferenceBonus(e, m, spec: spec, ctx: ctx).bonus
        return sc
    }

    /// Audit G-19: explicit, explained preferences instead of alphabetical ties. Coaching heuristics:
    /// - cycling-focused riders: a Romanian deadlift over a conventional deadlift as the hinge (similar hamstring and
    ///   glute work with less fatigue for the legs and back that rides need);
    /// - beginners: a goblet squat over barbell / machine squats (self-limiting load, easy to learn).
    static func preferenceBonus(_ e: Exercise, _ m: ExerciseMeta, spec: SlotSpec, ctx: PlannerContext) -> (bonus: Double, reason: String?) {
        let n = e.name.lowercased()
        if m.slot == .hinge, ctx.goal == .enduranceSupport || ctx.priority == .cycling, n.contains("romanian") {
            return (1.5, "Chosen over a conventional deadlift: similar hamstring and glute work with less fatigue for the legs you ride on.")
        }
        if m.slot == .squat, ctx.experience == .beginner, n.contains("goblet") {
            return (1.5, "Chosen as a first squat: the weight held in front keeps you upright and is easy to learn.")
        }
        return (0, nil)
    }

    /// The best doable exercise for a slot (deterministic: score, then name). Honours "always prefer".
    static func pick(_ spec: SlotSpec, ctx: PlannerContext, used: Set<String>) -> Exercise? {
        let maxDiff = ctx.experience.maxDifficulty
        var cands = ctx.catalogue.filter { e in !used.contains(e.id) && ExerciseLibrary.meta(e).slot == spec.slot && available(e, ctx: ctx) }
        if cands.isEmpty { return nil }
        let withinLevel = cands.filter { ExerciseLibrary.meta($0).difficulty <= maxDiff }
        if !withinLevel.isEmpty { cands = withinLevel }
        let ranked = cands.map { ($0, score($0, ExerciseLibrary.meta($0), spec: spec, ctx: ctx)) }.sorted { a, b in a.1 != b.1 ? a.1 > b.1 : a.0.name < b.0.name }
        guard var best = ranked.first?.0 else { return nil }
        if let pref = ctx.prefs.alwaysPrefer[best.id], let p = ctx.catalogue.first(where: { $0.id == pref }), !used.contains(p.id), available(p, ctx: ctx) { best = p }
        return best
    }

    // MARK: dose
    static func dose(role: Role, goal: StrengthPrefs.Goal, experience: StrengthPrefs.Experience) -> (reps: ClosedRange<Int>, rpe: Int) {
        var r: (ClosedRange<Int>, Int)
        switch (goal, role) {
        case (_, .core): r = (10...15, 7)
        case (.strength, .main): r = (4...6, 8)
        case (.strength, .secondary): r = (6...8, 8)
        case (.strength, .accessory): r = (8...12, 8)
        case (.hypertrophy, .main): r = (6...10, 8)
        case (.hypertrophy, .secondary): r = (8...12, 8)
        case (.hypertrophy, .accessory): r = (10...15, 8)
        case (.enduranceSupport, .main): r = (5...8, 7)
        case (.enduranceSupport, .secondary): r = (8...10, 7)
        case (.enduranceSupport, .accessory): r = (10...12, 7)
        case (.general, .main): r = (6...10, 7)
        case (.general, .secondary): r = (8...12, 7)
        case (.general, .accessory): r = (10...15, 7)
        }
        if experience == .beginner {
            r.1 = min(r.1, 7)
            if r.0.lowerBound < 6 { r.0 = 6...max(8, r.0.upperBound) }
        }
        return r
    }

    static func goalReason(_ g: StrengthPrefs.Goal) -> String {
        switch g {
        case .strength: return "Your goal is maximal strength: few reps with heavier loads on the main lifts."
        case .hypertrophy: return "Your goal is muscle size: moderate reps with enough sets per muscle each week."
        case .enduranceSupport: return "Your goal is to support your cycling: strong legs and trunk with low fatigue, so main lifts stay heavy but short of failure."
        case .general: return "Your goal is general strength: balanced moderate reps across all movement patterns."
        }
    }

    // MARK: weekly context
    struct WeekContext {
        var hardRideNext: Workout?
        var hardRideSameDayAfter: Workout?
        var hardRideBefore: String?
        var highCyclingLoad: Bool
        var highLoadReason: String?
        var deload: Bool
        var deloadReason: String?
        var sessionIndex: Int
        var sessionsHitting: [String: Int]
    }

    static func isKeyRide(_ w: Workout) -> Bool { w.kind.isRide && !w.skipped && (w.kind.zone >= 3 || w.kind == .long || w.minutes >= 120) }

    static func weekContext(for w: Workout, ctx: PlannerContext) -> WeekContext {
        let cal = ctx.calendar
        let day = cal.startOfDay(for: w.date)
        let next = cal.date(byAdding: .day, value: 1, to: day)!, prev = cal.date(byAdding: .day, value: -1, to: day)!
        let hardNext = ctx.plan.filter { isKeyRide($0) && cal.isDate($0.date, inSameDayAs: next) }.min { $0.date < $1.date }
        let sameAfter = ctx.plan.first { isKeyRide($0) && cal.isDate($0.date, inSameDayAs: day) && $0.sequence > w.sequence }
        var before: String? = nil
        if let p = ctx.plan.first(where: { isKeyRide($0) && cal.isDate($0.date, inSameDayAs: prev) }) { before = "\(p.kind.title.lowercased()) planned the day before (\(p.date.shortDay))" }
        if before == nil, let r = ctx.rides.first(where: { !$0.demo && cal.isDate($0.start, inSameDayAs: prev) && ($0.durationS >= 5400 || hardShare($0) >= 0.4) }) { before = "a \(Fmt.duration(seconds: r.durationS)) ride the day before" }
        // audit G-13: a key ride EARLIER the same day counts like one the day before (≈ 6 h apart is the usual advice
        // for same-day concurrent sessions; Robineau et al. 2016, JSCR 30(3):672–683)
        if before == nil, let e = ctx.plan.first(where: { isKeyRide($0) && cal.isDate($0.date, inSameDayAs: day) && $0.sequence < w.sequence }) { before = "your \(e.kind.title.lowercased()) earlier today (leave about 6 hours between them if you can)" }
        if before == nil, let r = ctx.rides.first(where: { !$0.demo && cal.isDate($0.start, inSameDayAs: day) && $0.start < w.date && ($0.durationS >= 5400 || hardShare($0) >= 0.4) }) { before = "a \(Fmt.duration(seconds: r.durationS)) ride earlier today" }
        // weekly cycling load
        let monday = TrainingLedger.monday(of: w.date, calendar: cal)
        let end = cal.date(byAdding: .day, value: 7, to: monday)!
        let weekRides = ctx.plan.filter { $0.kind.isRide && !$0.skipped && $0.date >= monday && $0.date < end }
        let hardCount = weekRides.filter { $0.kind.zone >= 3 }.count
        let plannedMin = weekRides.reduce(0) { $0 + $1.minutes }
        var avg = 0
        let prevWeeks = (1...3).map { k -> Int in
            let m = cal.date(byAdding: .day, value: -7 * k, to: monday)!, e = cal.date(byAdding: .day, value: 7, to: m)!
            return ctx.rides.filter { !$0.demo && $0.start >= m && $0.start < e }.reduce(0) { $0 + $1.durationS } / 60
        }
        if prevWeeks.allSatisfy({ $0 > 0 }) { avg = prevWeeks.reduce(0, +) / 3 }
        var high = false, why: String? = nil
        if hardCount >= 2 { high = true; why = "\(hardCount) hard rides are planned this week" }
        else if avg > 0, plannedMin * 100 > avg * 130 { high = true; why = "this week's planned riding (\(Fmt.duration(minutes: plannedMin))) is well above your recent average (\(Fmt.duration(minutes: avg)))" }
        // deload: every 4th consecutive training week, or fatigue signals from check-ins
        // F-09: the same block clock as the cycling easy week (rides + lifts, quick logs included)
        let activity = Set((ctx.logs.map { $0.date } + ctx.rides.filter { !$0.demo }.map { $0.start } + ctx.plan.filter { $0.completion == .marked }.map { $0.date }).map { cal.startOfDay(for: $0) })
        let plannedMondays = Set(ctx.plan.filter { $0.kind.isRide || $0.kind == .strength }.map { TrainingLedger.monday(of: $0.date, calendar: cal) })
        let streak = BlockClock.weeks(before: monday, activity: activity, plannedMondays: plannedMondays, now: ctx.now, calendar: cal)
        var deload = false, dWhy: String? = nil
        if ctx.fatigue { deload = true; dWhy = "your recent check-ins show fatigue" }
        else {
            let every = ctx.profile.recovery.deloadEvery
            if streak >= every - 1 && streak % every == every - 1 { deload = true; dWhy = "this is week \(streak + 1) of consecutive training — a lighter week lets the work sink in\(every < 4 ? " (every \(every)rd week because \(ctx.profile.recovery.reason ?? "of your recovery"))" : "")" }
        }
        // which sessions of the week train which region, and this session's index among its type
        let lifts = ctx.plan.filter { $0.kind == .strength && !$0.skipped && $0.date >= monday && $0.date < end }.sorted { $0.date < $1.date }
        var hit: [String: Int] = [:]
        for l in lifts { for r in regions(l.strengthFocus ?? .fullBody, label: l.note) { hit[r, default: 0] += 1 } }
        let idx = lifts.filter { ($0.strengthFocus ?? .fullBody) == (w.strengthFocus ?? .fullBody) }.firstIndex { $0.id == w.id } ?? 0
        return WeekContext(hardRideNext: hardNext, hardRideSameDayAfter: sameAfter, hardRideBefore: before, highCyclingLoad: high, highLoadReason: why, deload: deload, deloadReason: dWhy, sessionIndex: idx, sessionsHitting: hit)
    }
    static func hardShare(_ r: RideRecord) -> Double {
        let t = r.zoneSeconds.reduce(0, +); guard t > 0, r.zoneSeconds.count == 7 else { return 0 }
        return Double(r.zoneSeconds[2...].reduce(0, +)) / Double(t)
    }
    static func regions(_ f: StrengthFocus, label: String) -> [String] {
        switch f {
        case .fullBody: return ["lower", "push", "pull", "core"]
        case .upper: return ["push", "pull", "core"]
        case .lower, .legs: return ["lower", "core"]
        case .push: return ["push", "core"]
        case .pull: return ["pull", "core"]
        case .custom:
            let l = label.lowercased()
            return ["core", "joint", "mobility", "prehab", "stability"].contains(where: { l.contains($0) }) ? ["core", "lower"] : ["lower", "push", "pull", "core"]
        }
    }
    static func region(_ s: MovementSlot) -> String {
        switch s { case .squat, .hinge, .lunge, .calves: return "lower"; case .horizontalPush, .verticalPush: return "push"; case .horizontalPull, .verticalPull: return "pull"; case .arms: return "arms"; case .core, .carry: return "core"; case .accessory: return "accessory" }
    }

    /// Weekly working sets per region (lower / push / pull) before this session's share.
    static func weeklySets(region: String, ctx: PlannerContext, week: WeekContext) -> Double {
        var base: Double
        switch ctx.experience { case .beginner: base = 8; case .intermediate: base = 12; case .advanced: base = 16 }
        let lower = region == "lower"
        switch ctx.priority {
        case .strength: base *= 1.0
        case .balanced: base *= lower ? 0.7 : 0.85
        case .cycling: base *= lower ? 0.5 : 0.6
        }
        if ctx.goal == .hypertrophy { base *= 1.1 }
        if lower && week.highCyclingLoad { base *= 0.75 }
        if week.deload { base *= 0.6 }
        // M-06: age / stated recovery capacity
        base *= ctx.profile.recovery.volumeFactor
        return base
    }

    // MARK: building one session
    struct Built { var entries: [ExerciseEntry]; var rationale: SessionRationale }

    static func build(for w: Workout, ctx: PlannerContext) -> Built {
        let goal = ctx.goal, exp = ctx.experience
        let week = weekContext(for: w, ctx: ctx)
        let specs = slots(focus: w.strengthFocus ?? .fullBody, label: w.note, goal: goal, sessionIndex: week.sessionIndex)
        var used: Set<String> = []
        var picked: [(SlotSpec, Exercise)] = []
        for s in specs { if let e = pick(s, ctx: ctx, used: used) { used.insert(e.id); picked.append((s, e)) } }
        // sets per exercise: the region's weekly sets shared by the sessions that train it, weighted by role
        let maxSets: Int = exp == .beginner ? 3 : exp == .intermediate ? 4 : 5
        var sets: [Int] = Array(repeating: 2, count: picked.count)
        let weights: [Double] = picked.map { $0.0.role == .main ? 1.3 : $0.0.role == .secondary ? 1.0 : 0.7 }
        for r in ["lower", "push", "pull"] {
            let idx = picked.indices.filter { region(ExerciseLibrary.meta(picked[$0].1).slot) == r }
            guard !idx.isEmpty else { continue }
            let share = weeklySets(region: r, ctx: ctx, week: week) / Double(max(1, week.sessionsHitting[r] ?? 1))
            let wsum = idx.reduce(0.0) { $0 + weights[$1] }
            for i in idx { sets[i] = min(maxSets, max(2, Int((share * weights[i] / wsum).rounded()))) }
        }
        for i in picked.indices where picked[i].0.role == .core || ["arms", "accessory", "core"].contains(region(ExerciseLibrary.meta(picked[i].1).slot)) {
            sets[i] = picked[i].0.role == .core ? (week.deload ? 2 : 3) : min(3, max(2, sets[i]))
        }
        // a main lift always gets at least 3 working sets before deload / interference reductions
        for i in picked.indices where picked[i].0.role == .main { sets[i] = min(maxSets, max(3, sets[i])) }
        // interference: lower body light before a key ride / after a long or hard one
        let nearKeyRide = week.hardRideNext != nil || week.hardRideSameDayAfter != nil || week.hardRideBefore != nil
        // audit G-14: strength priority keeps the leg work as planned; the ride is the one to keep easy
        let strengthFirst = ctx.priority == .strength
        let legsKept = nearKeyRide && !strengthFirst
        var interferenceText: String? = nil
        if let n = week.hardRideNext { interferenceText = "\(n.kind.title) on \(n.date.shortDay) is a key ride: lower-body work today stays light (one set fewer, 3+ reps in reserve) so your legs are fresh for it." }
        else if let s = week.hardRideSameDayAfter { interferenceText = "Your \(s.kind.title.lowercased()) is later today: lift first only if you must; lower-body work stays light (one set fewer, 3+ reps in reserve)." }
        else if let b = week.hardRideBefore { interferenceText = "After \(b): lower-body work stays light (one set fewer, 3+ reps in reserve) while your legs recover." }
        if strengthFirst, nearKeyRide {
            // independent review F-20: no advice that contradicts the plan — a hard ride next to the leg session is one the
            // rider fixed (the week builder never puts one there for strength priority), so suggest moving it instead
            let hardOne = [week.hardRideNext, week.hardRideSameDayAfter].compactMap { $0 }.first { $0.kind.zone >= 3 }
            if let h = hardOne { interferenceText = "Strength is your priority, so the leg work stays as planned. Your \(h.kind.title.lowercased()) on \(h.date.shortDay) is next to it — if your legs feel heavy, move that ride by a day." }
            else {
                let which = week.hardRideNext.map { "\($0.kind.title.lowercased()) on \($0.date.shortDay)" } ?? week.hardRideSameDayAfter.map { "\($0.kind.title.lowercased()) later today" } ?? week.hardRideBefore ?? "the ride next to it"
                interferenceText = "Strength is your priority, so the leg work stays as planned. The \(which) is a steady ride; keep it conversational."
            }
        }
        // independent review F-23: cycling-focused riders still get one heavy lower-body dose a week (heavy strength work
        // helps cycling economy and performance: Rønnestad & Mujika 2014, Scand J Med Sci Sports 24(4):603–612) — when
        // every lower session of the week sits next to a key ride, the first one keeps its main lifts heavy
        var protectHeavyLegs = false
        if legsKept, ctx.priority == .cycling || goal == .enduranceSupport {
            let cal = ctx.calendar
            let monday = TrainingLedger.monday(of: w.date, calendar: cal), end = cal.date(byAdding: .day, value: 7, to: monday)!
            let lowerLifts = ctx.plan.filter { $0.kind == .strength && !$0.skipped && $0.date >= monday && $0.date < end && ($0.strengthFocus ?? .fullBody).loadsLegs }.sorted { $0.date < $1.date }
            let free = lowerLifts.contains { l in let c = weekContext(for: l, ctx: ctx); return c.hardRideNext == nil && c.hardRideSameDayAfter == nil && c.hardRideBefore == nil }
            if !free, lowerLifts.first?.id == w.id || lowerLifts.isEmpty { protectHeavyLegs = true }
        }
        // dose, load and explanation per exercise
        var entries: [ExerciseEntry] = []
        var rats: [ExerciseRationale] = []
        for (i, (spec, e)) in picked.enumerated() {
            let m = ExerciseLibrary.meta(e)
            var d = dose(role: spec.role, goal: goal, experience: exp)
            // F-02: no heavy low-rep work until the health check allows vigorous training
            if let lo = ctx.readiness.minStrengthReps, d.reps.lowerBound < lo { d.reps = lo...max(lo + 4, d.reps.upperBound) }
            // bodyweight-only with the rider's equipment: higher reps (a load cannot be added)
            if bodyweightOnly(e, ctx: ctx), !isHold(e) { d.reps = max(10, d.reps.lowerBound)...max(15, d.reps.upperBound) }
            var n = sets[i]
            var cyclingNote: String? = nil
            if m.slot.isLower && legsKept && protectHeavyLegs && spec.role == .main {
                n = max(3, n); d.rpe = min(d.rpe, 7)
                cyclingNote = "Every leg session this week sits next to a key ride, so this one keeps its main lift heavy (\(n) sets, RPE 7) — once a week is enough to keep the strength that helps your riding; the other leg work stays light."
            }
            else if m.slot.isLower && legsKept { n = max(2, n - 1); d.rpe = min(d.rpe, 6); cyclingNote = interferenceText }
            else if m.slot.isLower && strengthFirst && nearKeyRide { cyclingNote = interferenceText }      // G-14: flagged, not lightened
            else if m.slot.isLower && week.highCyclingLoad { cyclingNote = "Lower-body volume is reduced this week because \(week.highLoadReason ?? "your cycling load is high")." }
            if week.deload { n = max(2, n - 1); d.rpe = min(d.rpe, 6) }
            else if let r = ctx.returning, r.active { n = max(2, n - 1); d.rpe = min(d.rpe, 7) }
            d.rpe = min(d.rpe, ctx.readiness.maxStrengthRPE)
            let painBlocked = ctx.painAreas.contains { $0.patterns.contains(m.slot.family) }
            let load = prescribeLoad(e, meta: m, reps: d.reps, sets: n, painBlocked: painBlocked || week.deload, ctx: ctx)
            var entry = ExerciseEntry(exercise: e, sets: (0..<n).map { _ in SetEntry(reps: load.reps, weightKg: load.weight, bodyweight: load.bodyweight, unilateral: e.unilateral) })
            if spec.slot == .core, isHold(e) { entry.notes = "Hold \(load.reps) s per set" }
            let rest = RestPrescription.seconds(role: spec.role, goal: goal, reduced: ctx.profile.recovery.reduced)
            entry.restSeconds = rest
            entries.append(entry)
            let repsText = isHold(e) ? "\(n) × \(load.reps) s holds" : "\(n) × \(d.reps.lowerBound)–\(d.reps.upperBound)\(e.unilateral ? " per side" : "")"
            var doseText = "\(repsText) at about RPE \(d.rpe) (\(10 - d.rpe) reps in reserve). As your \(spec.role.rawValue) for \(m.slot.title), it gets \(n) set\(n == 1 ? "" : "s") — \(setsReason(region(m.slot), ctx: ctx, week: week))"
            doseText += " Rest about \(RestPrescription.text(rest)) between sets\(spec.role == .main || spec.role == .secondary ? " so the next set keeps its quality" : "")."
            if week.deload { doseText += " Deload: \(week.deloadReason ?? "lighter week")." }
            rats.append(ExerciseRationale(exerciseId: e.id, role: spec.role.rawValue, slot: m.slot.title, dose: doseText, load: load.why, cycling: cyclingNote, progressed: load.progressed, targetRPE: d.rpe))
        }
        // time fit: drop the least important exercises, then sets, until the session fits its minutes
        // minutes per set = about 45 s of work + the prescribed rest (M-03)
        func estimate() -> Double { 6 + entries.reduce(0.0) { $0 + Double($1.sets.count) * (0.75 + Double($1.restSeconds ?? 90) / 60) } }
        // keep movement coverage: first take sets off (least important exercise first, never below 2; main lifts keep
        // 3), only then leave whole exercises out from the end
        var trimmed: [String] = []
        let before = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.sets.count) })
        let limit = Double(max(15, w.minutes))
        var guardN = 0
        while estimate() > limit, guardN < 60 {
            guardN += 1
            let floor: (Int) -> Int = { rats[$0].role == Role.main.rawValue ? 3 : 2 }
            guard let j = entries.indices.reversed().first(where: { entries[$0].sets.count > floor($0) }) else { break }
            entries[j].sets.removeLast()
        }
        // audit G-08: keep the four main patterns (squat, hinge, push, pull) as long as possible — first leave out
        // accessories / core from the end, then take main lifts to 2 sets, and only then drop one main pattern
        func family(_ i: Int) -> MovementPattern? { ctx.catalogue.first { $0.id == entries[i].exerciseId }.map { ExerciseLibrary.meta($0).slot.family } }
        func essential(_ i: Int) -> Bool { [Role.main.rawValue, Role.secondary.rawValue].contains(rats[i].role) && [.squat, .hinge, .push, .pull].contains(family(i) ?? .other) }
        while estimate() > limit, entries.count > 3, let j = entries.indices.reversed().first(where: { !essential($0) }) { trimmed.append(entries.remove(at: j).name); rats.remove(at: j) }
        if estimate() > limit {
            while estimate() > limit, let j = entries.indices.reversed().first(where: { rats[$0].role == Role.main.rawValue && entries[$0].sets.count > 2 }) { entries[j].sets.removeLast() }
        }
        // still too long: leave out one main pattern, a different one in each session of the week (pull, hinge, push,
        // squat), so the week as a whole keeps all four
        let dropOrder: [MovementPattern] = [.pull, .hinge, .push, .squat]
        var k = 0
        while estimate() > limit, entries.count > 2, k < 8 {
            let want = dropOrder[(week.sessionIndex + k) % dropOrder.count]
            k += 1
            guard let j = entries.indices.last(where: { family($0) == want }) else { continue }
            trimmed.append(entries.remove(at: j).name); rats.remove(at: j)
        }
        while estimate() > limit, entries.count > 2 { trimmed.append(entries.removeLast().name); rats.removeLast() }
        for i in entries.indices where entries[i].sets.count < (before[entries[i].id] ?? 0) { rats[i].dose += " Trimmed to \(entries[i].sets.count) sets so the session fits \(Fmt.duration(minutes: w.minutes))." }
        var notes: [String] = [goalReason(goal)]
        if let t = interferenceText { notes.append(t) }
        if week.highCyclingLoad, let r = week.highLoadReason { notes.append("Lower-body volume is reduced by a quarter this week because \(r).") }
        if week.deload, let r = week.deloadReason { notes.append("Deload week: fewer sets and lighter efforts because \(r).") }
        if !trimmed.isEmpty { notes.append("To fit \(Fmt.duration(minutes: w.minutes)), these were left out: \(trimmed.joined(separator: ", ")).") }
        if !ctx.equipment.isSet { notes.append("Your equipment is not set, so exercises that need only dumbbells or bodyweight are preferred. Set it in Profile › Training profile › Equipment.") }
        if let h = ctx.progressionHold { notes.append("Loads and reps are held: \(h).") }
        if let r = ctx.returning, r.active { notes.append("Back after \(r.weeksText) off: one set fewer per exercise, efforts at RPE 7 or less, and loads restart below your last logged ones for your first \(ReturnPhase.phaseSessions) sessions.") }
        if let r = ctx.profile.recovery.reason, ctx.profile.recovery.volumeFactor != 1 { notes.append("Weekly volume is \(ctx.profile.recovery.volumeFactor < 1 ? "lower" : "a little higher") (×\(String(format: "%.1f", ctx.profile.recovery.volumeFactor))) because \(r)\(ctx.profile.recovery.reduced ? ", with longer rests and a lighter week every \(ctx.profile.recovery.deloadEvery)rd week" : "").") }
        if let r = ctx.readiness.restriction { notes.append("Efforts are capped at RPE \(ctx.readiness.maxStrengthRPE) because \(r).") }
        if !ctx.painAreas.isEmpty { notes.append("You reported pain (\(ctx.painAreas.map { $0.title.lowercased() }.joined(separator: ", "))): exercises that load that area this way are left out and not progressed.") }
        if w.fixed { notes.append("Fixed day: the day and session type are yours; only the exercises were filled in.") }
        let r = SessionRationale(generatedAt: ctx.now, goal: goal.title, notes: notes, exercises: rats, deload: week.deload)
        return Built(entries: entries, rationale: r)
    }

    /// F-11: a barbell-only exercise is never prescribed below the empty bar (20 kg / 45 lb); below it, reps come down instead.
    static func barFloor(_ e: Exercise, ctx: PlannerContext) -> Double? {
        let eq = Set(e.equipment.map { $0.lowercased() })
        guard eq.contains("barbell"), eq.subtracting(["barbell", "bench", "rack", "plates", "bodyweight"]).isEmpty else { return nil }
        return ctx.units == .imperial ? 20.41 : 20
    }

    static func bodyweightOnly(_ e: Exercise, ctx: PlannerContext) -> Bool {
        let loadOptions = Set(e.equipment.map(EquipmentProfile.normalised)).subtracting(ExerciseLibrary.accessories).subtracting(["bodyweight"])
        let owned = Set(ctx.equipment.owned.map(EquipmentProfile.normalised))
        return loadOptions.isEmpty || (ctx.equipment.isSet && loadOptions.isDisjoint(with: owned))
    }
    static func isHold(_ e: Exercise) -> Bool { let n = e.name.lowercased(); return ["plank", "hold", "wall sit", "hollow"].contains { n.contains($0) } }

    static func setsReason(_ region: String, ctx: PlannerContext, week: WeekContext) -> String {
        let exp = ctx.experience.title.lowercased()
        switch region {
        case "lower": return "weekly leg volume is scaled for \(exp) and a \(ctx.priority.title.lowercased()) priority\(week.highCyclingLoad ? ", reduced for this week's cycling load" : "") and shared across \(week.sessionsHitting["lower"] ?? 1) session\((week.sessionsHitting["lower"] ?? 1) == 1 ? "" : "s")."
        case "push", "pull": return "weekly upper-body volume is scaled for \(exp) and a \(ctx.priority.title.lowercased()) priority, shared across \(week.sessionsHitting[region] ?? 1) session\((week.sessionsHitting[region] ?? 1) == 1 ? "" : "s")."
        default: return "accessory and trunk work stays at 2–3 sets."
        }
    }

    struct Load { var weight: Double?; var reps: Int; var bodyweight: Bool; var progressed: Bool; var why: String }

    /// Load and reps from LOGGED sets of this exact exercise only (double progression). Never copied from another one.
    /// Audit fixes (vs 2b2c104): a load increase needs TWO logged sessions in a row with every set at the top of the
    /// range at a known effort ≤ RPE 8 (G-02); an unknown effort is not evidence (G-02 / X04); the step is the smallest
    /// one available, whatever its percentage of a light load (G-01); two failed sessions at RPE ≥ 9 bring the load down
    /// (G-16); a shared hold (missed sessions, pain, deload) stops every kind of progression (G-03).
    static func prescribeLoad(_ e: Exercise, meta m: ExerciseMeta, reps range: ClosedRange<Int>, sets: Int, painBlocked: Bool, ctx: PlannerContext) -> Load {
        let req = ExerciseLibrary.requirement(e)
        let loadOptions = Set(e.equipment.map(EquipmentProfile.normalised)).subtracting(ExerciseLibrary.accessories).subtracting(["bodyweight"])
        let owned = Set(ctx.equipment.owned.map(EquipmentProfile.normalised))
        let loadable = !loadOptions.isEmpty && (!ctx.equipment.isSet || !loadOptions.isDisjoint(with: owned))
        let bw = !loadable && req.anyOf.isEmpty
        let readinessHold: String? = ctx.readiness.vigorousAllowed ? nil : "Held — no load increases until the health check allows harder training."
        let holdWhy: String? = painBlocked ? "Held — no progression while pain is reported or during a deload." : (ctx.progressionHold.map { "Held — \($0)." } ?? readinessHold)
        let hist = history(e.id, ctx: ctx)
        func effort(_ x: (session: StrengthSession, entry: ExerciseEntry)) -> Int? { x.entry.doneSets.compactMap { $0.rpe }.max() ?? x.session.rpe ?? x.session.checkIn?.effort }
        if isHold(e) {
            let h = hist.first.map { $0.entry.doneSets.map { $0.reps }.min() ?? 30 } ?? 30
            let known = hist.first.flatMap { effort($0) }
            let grow = holdWhy == nil && known.map { $0 <= 8 } == true && h < 60
            let next = grow ? min(60, h + 5) : h
            let why: String
            if hist.isEmpty { why = "Start with 30-second holds with good form." }
            else if let hw = holdWhy { why = "Last logged hold: \(h) s. \(hw)" }
            else if known == nil { why = "Last logged hold: \(h) s. No effort was logged, so the hold stays the same — log how hard it felt and it can grow." }
            else { why = "Last logged hold: \(h) s. \(grow ? "5 s longer this time." : "Kept the same.")" }
            return Load(weight: nil, reps: max(20, next), bodyweight: true, progressed: grow && !hist.isEmpty, why: why)
        }
        let df = DateFormatter(); df.dateFormat = "d MMM"
        guard let last = hist.first else {
            if bw { return Load(weight: nil, reps: range.lowerBound, bodyweight: true, progressed: false, why: "Bodyweight. Aim for \(range.lowerBound)–\(range.upperBound) controlled reps; when every set reaches \(range.upperBound), the next session adds reps or a harder variation.") }
            return Load(weight: nil, reps: range.lowerBound, bodyweight: false, progressed: false, why: StartingLoad.guidance(e, reps: range, beginner: ctx.experience == .beginner))
        }
        func topWeight(_ x: (session: StrengthSession, entry: ExerciseEntry)) -> Double? { x.entry.doneSets.compactMap { $0.bodyweight ? nil : $0.weightKg }.max() }
        let done = last.entry.doneSets
        let reps = done.map { $0.reps }
        let top = topWeight(last)
        let rpe = effort(last)
        let when = df.string(from: last.session.date)
        let lastText = "Last logged \(when): \(done.count) × \(reps.map(String.init).joined(separator: "/"))" + (top.map { " @ \(WeightFmt.text($0, ctx.units))" } ?? (done.first?.bodyweight == true ? " bodyweight" : ""))
        let rpeText = rpe.map { " at RPE \($0)" } ?? ""
        let minReps = reps.min() ?? range.lowerBound
        // M-02: this exercise was last logged three or more weeks ago → restart below that load, no progression
        let gapDays = ctx.calendar.dateComponents([.day], from: ctx.calendar.startOfDay(for: last.session.date), to: ctx.calendar.startOfDay(for: ctx.now)).day ?? 0
        if gapDays >= ReturnPhase.breakThresholdDays {
            let phase = ReturnPhase(breakDays: gapDays, sessionsSince: 0, ongoing: true)
            if let w = top {
                let dumbbellR = e.equipment.contains("dumbbell") || e.equipment.contains("kettlebell")
                let stepR = WeightFmt.step(dumbbell: dumbbellR, ctx.units)
                let target = w * phase.loadFactor
                let floorKg = barFloor(e, ctx: ctx)
                let next = max(floorKg ?? stepR, min(w - stepR, (target / stepR).rounded(.down) * stepR))
                if next >= w {
                    return Load(weight: w, reps: range.lowerBound, bodyweight: false, progressed: false, why: "\(lastText)\(rpeText) — \(phase.weeksText) ago. The empty bar is the lightest load, so the weight stays and the reps restart at \(range.lowerBound); it builds back up from your new logs.")
                }
                let pct = Int(((1 - next / w) * 100).rounded())
                return Load(weight: (next * 100).rounded() / 100, reps: range.lowerBound, bodyweight: false, progressed: false, why: "\(lastText)\(rpeText) — \(phase.weeksText) ago. After a break strength and work capacity drop, so the weight restarts about \(pct) % lower (\(WeightFmt.text(next, ctx.units))) at \(range.lowerBound) reps; it builds back up from your new logs.")
            }
            let r0 = max(range.lowerBound, min(minReps, range.upperBound)) - (minReps > range.lowerBound ? 1 : 0)
            return Load(weight: nil, reps: max(range.lowerBound, r0), bodyweight: true, progressed: false, why: "\(lastText) — \(phase.weeksText) ago. After a break, reps restart at \(max(range.lowerBound, r0)) and build back up from your new logs.")
        }
        if let hw = holdWhy {
            return Load(weight: top, reps: max(range.lowerBound, min(minReps, range.upperBound)), bodyweight: top == nil && bw, progressed: false, why: "\(lastText)\(rpeText). \(hw)")
        }
        let unknownEffort = "No effort (RPE) was logged, so nothing is increased: an unrated session is not evidence that it was easy. Log RPE next time and the coach can progress it."
        guard let w = top else {
            if rpe == nil { return Load(weight: nil, reps: max(range.lowerBound, min(minReps, range.upperBound)), bodyweight: true, progressed: false, why: "\(lastText). \(unknownEffort)") }
            if minReps < range.lowerBound || (rpe ?? 0) >= 9 { return Load(weight: nil, reps: max(range.lowerBound, min(minReps, range.upperBound)), bodyweight: true, progressed: false, why: "\(lastText)\(rpeText): it was very hard or short of \(range.lowerBound) reps, so the reps stay the same.") }
            let next = min(range.upperBound, max(range.lowerBound, minReps + 1))
            return Load(weight: nil, reps: next, bodyweight: true, progressed: next > minReps, why: "\(lastText)\(rpeText). \(next > minReps ? "One more rep per set (\(next))" : "Every set is at the top of the range — keep \(next) reps and slow the lowering, or choose a harder variation"); weight progression needs a logged load.")
        }
        let minSets = min(sets, 2)
        /// Every set at the top of the range, at THIS weight, at a known effort ≤ RPE 8.
        func atTop(_ x: (session: StrengthSession, entry: ExerciseEntry)) -> Bool {
            let d = x.entry.doneSets
            return d.count >= minSets && d.allSatisfy { $0.reps >= range.upperBound } && topWeight(x) == w && (effort(x).map { $0 <= 8 } ?? false)
        }
        /// Short of the bottom of the range at RPE ≥ 9 (or reps clearly missed), at THIS weight.
        func failed(_ x: (session: StrengthSession, entry: ExerciseEntry)) -> Bool {
            let r = x.entry.doneSets.map { $0.reps }.min() ?? 0
            return topWeight(x) == w && r < range.lowerBound && (effort(x) ?? 0) >= 9
        }
        let last2 = Array(hist.prefix(2))
        let dumbbell = e.equipment.contains("dumbbell") || e.equipment.contains("kettlebell")
        let step = WeightFmt.step(dumbbell: dumbbell, ctx.units)
        if rpe == nil {
            return Load(weight: w, reps: max(range.lowerBound, min(minReps, range.upperBound)), bodyweight: false, progressed: false, why: "\(lastText). \(unknownEffort)")
        }
        if last2.count == 2, last2.allSatisfy(atTop) {
            let next = ((w + step) * 100).rounded() / 100
            let pct = Int((step / w * 100).rounded())
            let big = step / w > 0.1 ? " That is a big jump for this weight: if the first set is harder than RPE 8, go back to \(WeightFmt.text(w, ctx.units)) and add a rep instead." : ""
            return Load(weight: next, reps: range.lowerBound, bodyweight: false, progressed: true, why: "\(lastText)\(rpeText): every set reached the top of the range (\(range.upperBound)) on two sessions in a row at RPE 8 or less. The smallest step available, \(WeightFmt.text(step, ctx.units))\(dumbbell ? " per hand" : "") (\(pct) %), back to \(range.lowerBound) reps.\(big) If that weight is not available, add a rep instead.")
        }
        if atTop(last) {
            return Load(weight: w, reps: range.upperBound, bodyweight: false, progressed: false, why: "\(lastText)\(rpeText): every set reached the top of the range (\(range.upperBound)). Same weight once more — the weight goes up after two sessions like this in a row, never after one.")
        }
        if last2.count == 2, last2.allSatisfy(failed) {
            let down = max(step, ((w * 0.9) / step).rounded(.down) * step)
            let next = max(barFloor(e, ctx: ctx) ?? 0, min(w - step, down))
            if next > 0, next < w {
                return Load(weight: (next * 100).rounded() / 100, reps: range.lowerBound, bodyweight: false, progressed: false, why: "\(lastText)\(rpeText): two sessions in a row short of \(range.lowerBound) reps at a very hard effort. The weight comes down to \(WeightFmt.text(next, ctx.units)) (about 10 % less) so every set reaches \(range.lowerBound) clean reps; it builds back up from there.")
            }
        }
        if minReps < range.lowerBound || (rpe ?? 0) >= 9 {
            return Load(weight: w, reps: range.lowerBound, bodyweight: false, progressed: false, why: "\(lastText)\(rpeText): \(minReps < range.lowerBound ? "some sets fell short of \(range.lowerBound) reps" : "it was very hard"). Same weight, aim for \(range.lowerBound) reps on every set before adding anything.")
        }
        let next = min(range.upperBound, max(range.lowerBound, minReps + 1))
        return Load(weight: w, reps: next, bodyweight: false, progressed: next > minReps, why: "\(lastText)\(rpeText). Same weight, one more rep per set (\(next)) — double progression: reps first, weight once every set reaches \(range.upperBound) on two sessions in a row.")
    }

    // MARK: Why? for any session (planner-built or the rider's own routine)
    struct WhyLine: Identifiable, Equatable { var id: String { title }; var title: String; var text: String }

    static func why(entry: ExerciseEntry, workout w: Workout, ctx: PlannerContext, routineName: String?) -> [WhyLine] {
        let e = ctx.catalogue.first { $0.id == entry.exerciseId } ?? Exercise(id: entry.exerciseId, name: entry.name, pattern: entry.pattern)
        let m = ExerciseLibrary.meta(e)
        var out: [WhyLine] = []
        let muscles = m.primary.joined(separator: ", ") + (m.secondary.isEmpty ? "" : " (also \(m.secondary.joined(separator: ", ")))")
        out.append(WhyLine(title: "Muscles and movement", text: "\(m.slot.title.capitalizingFirst) pattern\(muscles.isEmpty ? "" : " — \(muscles)")\(e.unilateral ? ", one side at a time" : "")."))
        out.append(WhyLine(title: "For your goal", text: goalLine(m, goal: ctx.goal)))
        if let r = preferenceBonus(e, m, spec: SlotSpec(slot: m.slot, role: .main), ctx: ctx).reason { out.append(WhyLine(title: "Why this exercise", text: r)) }
        let week = weekContext(for: w, ctx: ctx)
        out.append(WhyLine(title: "Place in your week", text: placeLine(w, week: week, ctx: ctx)))
        if let r = w.rationale?.exercise(entry.exerciseId) {
            out.append(WhyLine(title: "Sets, reps and effort", text: r.dose))
            out.append(WhyLine(title: "Load", text: r.load))
        } else {
            let reps = entry.sets.map { $0.reps }
            let repText = reps.isEmpty ? "no sets" : Set(reps).count == 1 ? "\(reps.count) × \(reps[0])" : "\(reps.count) sets of \(reps.min()!)–\(reps.max()!)"
            out.append(WhyLine(title: "Sets, reps and effort", text: routineName.map { "\(repText) as set in your routine “\($0)”. The coach does not rewrite your routine; it only suggests changes you can accept." } ?? "\(repText) as set for this session."))
            let hist = history(e.id, ctx: ctx)
            out.append(WhyLine(title: "Load", text: hist.first.map { h in "Last logged \(h.session.date.dayAndDate): \(h.entry.summary(units: ctx.units))." } ?? "No logged sets of this exercise yet — find your working weight: start light, stop 2–3 reps before failure."))
        }
        let legs = m.slot.isLower
        var cyc: String
        if let r = w.rationale?.exercise(entry.exerciseId), let c = r.cycling { cyc = c }
        else if legs, let n = week.hardRideNext { cyc = "\(n.kind.title) on \(n.date.shortDay) is a key ride — keep this light today (stop with 3+ reps in reserve)." }
        else if legs, let b = week.hardRideBefore { cyc = "After \(b), keep this light while your legs recover." }
        else if legs { cyc = "No key ride within a day of this session, so normal effort is fine for your legs." }
        else { cyc = "Upper-body and trunk work does not compete with your cycling legs." }
        out.append(WhyLine(title: "With your rides", text: cyc))
        if ctx.prefs.reviewFlags.contains(e.id) { out.append(WhyLine(title: "Check", text: "Flagged for review: it loads the body like an exercise you said causes discomfort. Swap it if it bothers you.")) }
        return out
    }
    static func goalLine(_ m: ExerciseMeta, goal: StrengthPrefs.Goal) -> String {
        switch (goal, m.slot.isLower) {
        case (.enduranceSupport, true): return "Leg strength and single-leg control carry straight over to pedalling force and to staying stable on the bike."
        case (.enduranceSupport, false): return m.slot == .core || m.slot == .carry ? "A strong trunk keeps your position and power transfer steady on long rides." : "Upper-body pulling and pushing balances the riding position and keeps shoulders healthy."
        case (.strength, _): return m.compound ? "A compound lift where heavier, lower-rep sets build maximal strength." : "An accessory that supports the main lifts and evens out weak links."
        case (.hypertrophy, _): return "Trains \(m.primary.first ?? "the target muscle") through a full range with enough sets to grow."
        case (.general, _): return "Part of a balanced week that covers every movement pattern."
        }
    }
    static func placeLine(_ w: Workout, week: WeekContext, ctx: PlannerContext) -> String {
        let cal = ctx.calendar
        let monday = TrainingLedger.monday(of: w.date, calendar: cal), end = cal.date(byAdding: .day, value: 7, to: monday)!
        let lifts = ctx.plan.filter { $0.kind == .strength && !$0.skipped && $0.date >= monday && $0.date < end }.sorted { $0.date < $1.date }
        let n = (lifts.firstIndex { $0.id == w.id } ?? 0) + 1
        var t = "\(w.date.dayAndDate): strength session \(n) of \(max(1, lifts.count)) this week (\(w.displayTitle.lowercased()))."
        if week.deload { t += " Deload week." }
        return t
    }

    // MARK: Swap — ranked alternatives (only exercises the rider can actually do)
    struct SwapOption: Identifiable, Equatable { var id: String { exercise.id }; var exercise: Exercise; var reasons: [String]; var flagged: Bool; var score: Double }

    static func alternatives(for entry: ExerciseEntry, in w: Workout, entries: [ExerciseEntry], ctx: PlannerContext, limit: Int = 8) -> [SwapOption] {
        let orig = ctx.catalogue.first { $0.id == entry.exerciseId } ?? Exercise(id: entry.exerciseId, name: entry.name, pattern: entry.pattern)
        let m0 = ExerciseLibrary.meta(orig)
        let inSession = Set(entries.map { $0.exerciseId })
        var out: [SwapOption] = []
        for c in ctx.catalogue where c.id != orig.id && !inSession.contains(c.id) && available(c, ctx: ctx) {
            let m = ExerciseLibrary.meta(c)
            var sc = 0.0; var why: [String] = []
            let shared = m.primary.filter { m0.primary.contains($0) }
            if m.slot == m0.slot { sc += 10; why.append("same movement (\(m.slot.title))") }
            else if m.slot.family == m0.slot.family && m.slot.family != .other { sc += 5; why.append("similar movement (\(m.slot.family.title.lowercased()))") }
            else if shared.isEmpty { continue }
            if !shared.isEmpty { sc += Double(min(3, shared.count)) * 2; why.append("same main muscles: \(shared.joined(separator: ", "))") }
            if m.compound == m0.compound { sc += 2 }
            if m.difficulty > ctx.experience.maxDifficulty { sc -= 3; why.append("more technical") } else if m.difficulty < m0.difficulty { why.append("simpler") }
            if ctx.prefs.favourites.contains(c.id) { sc += 3; why.append("a favourite") }
            if !history(c.id, ctx: ctx).isEmpty { sc += 1; why.append("you have logged it") }
            if ctx.goal == .enduranceSupport, m.slot.isLower, c.unilateral { sc += 1 }
            let req = ExerciseLibrary.requirement(c)
            let uses = req.all.union(req.anyOf.intersection(ctx.equipment.isSet ? Set(ctx.equipment.owned.map(EquipmentProfile.normalised)) : req.anyOf))
            why.append(uses.isEmpty ? "no equipment needed" : "uses \(uses.sorted().joined(separator: ", "))")
            let flagged = ctx.prefs.reviewFlags.contains(c.id)
            if flagged { sc -= 4 }
            out.append(SwapOption(exercise: c, reasons: why, flagged: flagged, score: sc))
        }
        return Array(out.sorted { a, b in a.score != b.score ? a.score > b.score : a.exercise.name < b.exercise.name }.prefix(limit))
    }

    /// The replacement entry: same number of sets and the same reps (stimulus kept close); the weight only from the
    /// NEW exercise's own logged sets, otherwise "find your working weight".
    static func swappedEntry(old: ExerciseEntry, to e: Exercise, ctx: PlannerContext) -> ExerciseEntry {
        let m = ExerciseLibrary.meta(e)
        let reps = old.sets.map { $0.reps }
        let lo = reps.min() ?? 8, hi = max(lo, reps.max() ?? 10)
        let load = prescribeLoad(e, meta: m, reps: lo...hi, sets: max(1, old.sets.count), painBlocked: false, ctx: ctx)
        let n = max(1, old.sets.count)
        var x = ExerciseEntry(exercise: e, sets: (0..<n).map { i in SetEntry(reps: i < reps.count ? reps[i] : lo, weightKg: load.weight, bodyweight: load.bodyweight, unilateral: e.unilateral) }, superset: old.superset, notes: load.weight == nil && !load.bodyweight ? "Find your working weight" : "")
        if isHold(e) { x.notes = "Hold \(load.reps) s per set"; x.sets = x.sets.map { var s = $0; s.reps = load.reps; return s } }
        return x
    }
}

extension String { var capitalizingFirst: String { prefix(1).uppercased() + dropFirst() } }

// MARK: - Store side: context, regeneration of coach-built sessions, swaps
extension Store {
    func plannerContext(now: Date = Date()) -> PlannerContext {
        let analysis = TrainingAnalyzer.analyze(adaptationInput(now: now))
        let hold: String? = analysis.adherenceBlock ? "\(analysis.missed.count) planned sessions were missed in the last 7 days, so nothing is increased until you are back on track" : nil
        return PlannerContext(profile: profile, prefs: strengthPrefs, equipment: equipment, catalogue: allExercises, templates: templates,
                              logs: strength.filter { !$0.awaitingReview && !$0.inProgress }, rides: rides, plan: plan,
                              painAreas: analysis.painAreas, fatigue: analysis.strengthFatigue || analysis.combinedFatigue, progressionHold: hold, units: settings.units, now: now,
                              returning: liftingReturnPhase(now: now))
    }

    /// Coach-built future sessions (never ones the rider edited, completed, skipped or started) are rebuilt from the
    /// current preferences, equipment and logged performance. A session the adaptive coach adjusted keeps its
    /// adjustment on top of the new base (it is recomputed on the next check-in).
    func refreshGeneratedSessions(now: Date = Date()) {
        refreshRideSafety(now: now)
        // audit G-04: "Coach decides" (no split chosen) gets real exercises too — the week builder already gives each
        // lift a focus (lower / upper / full body), so the planner fills it like any other coach-built session
        guard profile.trainingMode.includesLifting else { return }
        let today = Calendar.current.startOfDay(for: now)
        let ctx = plannerContext(now: now)
        var p = plan
        var changed = false
        for i in p.indices {
            let w = p[i]
            guard w.kind == .strength, w.templateId == nil, !w.done, !w.skipped, !w.edited, w.date >= today, activeSession?.workoutId != w.id else { continue }
            guard w.generatedEntries || w.plannedEntries == nil else { continue }
            var c = ctx; c.plan = p
            let b = StrengthPlanner.build(for: w, ctx: c)
            guard !b.entries.isEmpty else { continue }
            var x = w
            if var o = x.coachOriginal { if o.plannedEntries?.map({ $0.exerciseId }) != b.entries.map({ $0.exerciseId }) || o.plannedEntries?.map({ $0.sets.map { $0.reps } }) != b.entries.map({ $0.sets.map { $0.reps } }) { o.plannedEntries = b.entries; x.coachOriginal = o } }
            else if x.plannedEntries?.map({ $0.exerciseId }) != b.entries.map({ $0.exerciseId }) || x.plannedEntries?.map({ $0.sets.map { $0.reps } }) != b.entries.map({ $0.sets.map { $0.reps } }) || x.plannedEntries?.map({ $0.sets.map { $0.weightKg } }) != b.entries.map({ $0.sets.map { $0.weightKg } }) { x.plannedEntries = b.entries }
            x.generatedEntries = true
            if x.rationale?.exercises != b.rationale.exercises || x.rationale?.notes != b.rationale.notes { x.rationale = b.rationale }
            if x != w { p[i] = x; changed = true }
        }
        if changed { plan = p }
    }

    /// A completed log uses up one session of every "N sessions" temporary block; expired blocks are removed.
    func consumeTemporaryBlocks(now: Date = Date()) {
        guard !strengthPrefs.temporary.isEmpty else { return }
        var p = strengthPrefs
        for i in p.temporary.indices { if let n = p.temporary[i].sessionsLeft { p.temporary[i].sessionsLeft = max(0, n - 1) } }
        p.temporary.removeAll { !$0.active(now: now) }
        if p != strengthPrefs { strengthPrefs = p }
    }

    /// Swap one exercise of a planned session. Returns a short confirmation for the UI.
    @discardableResult
    func applySwap(workoutId: UUID, entryId: UUID, to new: Exercise, reason: SwapReason, until: Date? = nil, sessions: Int? = nil, now: Date = Date()) -> String? {
        guard let i = plan.firstIndex(where: { $0.id == workoutId }) else { return nil }
        var entries = plannedEntries(for: plan[i])
        guard let k = entries.firstIndex(where: { $0.id == entryId }) else { return nil }
        let old = entries[k]
        let oldEx = allExercises.first { $0.id == old.exerciseId } ?? Exercise(id: old.exerciseId, name: old.name, pattern: old.pattern)
        let ctx = plannerContext(now: now)
        entries[k] = StrengthPlanner.swappedEntry(old: old, to: new, ctx: ctx)
        plan[i].plannedEntries = entries
        plan[i].edited = true                      // the rider's choice for this session; the coach does not override it
        plan[i].generatedEntries = false
        var p = strengthPrefs
        let msg: String
        switch reason {
        case .todayOnly:
            msg = "\(new.name) replaces \(old.name) in this session only."
        case .alwaysPrefer:
            p.alwaysPrefer[old.exerciseId] = new.id
            if !p.favourites.contains(new.id) { p.favourites.append(new.id) }
            msg = "\(new.name) will be used instead of \(old.name) in coach-built sessions. Your saved routines are not changed."
        case .noEquipment:
            let req = ExerciseLibrary.requirement(oldEx)
            let missing = req.all.union(req.anyOf)
            var eq = equipment
            if !eq.isSet { eq.owned = Set(EquipmentProfile.allOptions).subtracting(missing) }
            else { eq.owned = Set(eq.owned.filter { !missing.contains(EquipmentProfile.normalised($0)) }) }
            if eq.owned.isEmpty { eq.owned = ["bodyweight"] }
            equipment = eq
            msg = "Removed \(missing.sorted().joined(separator: ", ")) from your equipment. \(old.name) and anything else needing it will not be recommended. Check the list in Profile › Equipment."
        case .temporarilyUnavailable:
            p.temporary.append(TemporaryBlock(exerciseId: old.exerciseId, until: until, sessionsLeft: until == nil ? (sessions ?? 3) : sessions, at: now))
            let df = DateFormatter(); df.dateFormat = "d MMM"
            msg = until.map { "\(old.name) is avoided until \(df.string(from: $0))." } ?? "\(old.name) is avoided for the next \(sessions ?? 3) sessions."
        case .discomfort:
            if !p.avoids(old.exerciseId) { p.avoid.append(AvoidEntry(exerciseId: old.exerciseId, reason: .discomfort, at: now)) }
            let m0 = ExerciseLibrary.meta(oldEx)
            let similar = allExercises.filter { c in
                guard c.id != oldEx.id, c.id != new.id else { return false }
                let m = ExerciseLibrary.meta(c)
                return m.slot == m0.slot && (!m.tags.isDisjoint(with: m0.tags) || !Set(m.primary).isDisjoint(with: Set(m0.primary)))
            }
            for s in similar where !p.reviewFlags.contains(s.id) { p.reviewFlags.append(s.id) }
            msg = "\(old.name) is excluded. \(similar.count) similar movement\(similar.count == 1 ? " is" : "s are") flagged for you to check. If the discomfort persists, consider getting it checked by a doctor or physiotherapist."
        }
        p.swapHistory.append(SwapRecord(from: old.exerciseId, to: new.id, reason: reason, at: now, workoutId: workoutId))
        if p.swapHistory.count > 60 { p.swapHistory.removeFirst(p.swapHistory.count - 60) }
        if p != strengthPrefs { strengthPrefs = p }
        refreshGeneratedSessions(now: now)
        return msg
    }
}
