import Foundation

// MARK: - Adaptive hybrid-athlete coach: stored types (docs: ios/ADAPTIVE_COACH.md)
// Everything here is phone-side only (never part of the Link profile) and every stored field is optional or
// decoded with a default, so store.json files written by builds 24 … 40 load unchanged.

// MARK: Post-workout check-in (brief C)

enum PainLevel: String, Codable, CaseIterable {
    /// Raw value "none" (named noPain so it never collides with Optional.none).
    /// Coach remediation (owner, 27 Oct): three levels. Soreness = normal post-exercise muscle soreness (no change).
    /// Discomfort = non-specific discomfort in one area (that area is not progressed until a later session of the same
    /// activity is rated without it; nothing is left out). Concerning = pain that may indicate injury (the area's loading
    /// patterns are left out and only the rider can release it — the coach never clears it on its own).
    case noPain = "none", soreness, discomfort, concerning
    var title: String { switch self { case .noPain: return "None"; case .soreness: return "Normal soreness"; case .discomfort: return "Unusual discomfort"; case .concerning: return "Concerning pain" } }
    var short: String { switch self { case .noPain: return "None"; case .soreness: return "Soreness"; case .discomfort: return "Discomfort"; case .concerning: return "Pain" } }
    var needsArea: Bool { self == .discomfort || self == .concerning }
}

/// Where a concerning pain was felt — only used to stop progressing that area. Never a diagnosis.
enum PainArea: String, Codable, CaseIterable {
    case upperBody, back, hipsLegs, knees, other
    var title: String { switch self { case .upperBody: return "Shoulders / arms"; case .back: return "Back / core"; case .hipsLegs: return "Hips / legs"; case .knees: return "Knees"; case .other: return "Elsewhere / not sure" } }
    /// Movement patterns whose progression stops after a concerning-pain report in this area.
    var patterns: Set<MovementPattern> {
        switch self {
        case .upperBody: return [.push, .pull, .carry]
        case .back: return [.hinge, .core, .squat, .carry]
        case .hipsLegs: return [.squat, .hinge, .singleLeg]
        case .knees: return [.squat, .singleLeg]
        case .other: return Set(MovementPattern.allCases)
        }
    }
    /// Riding loads legs, knees and back; an unknown area stops cycling progression too.
    var affectsCycling: Bool { self != .upperBody }
}

/// The fast check-in after every ride or strength session: performance and effort 1–10, pain, an optional note.
struct CheckIn: Codable, Equatable {
    /// 1–10, 10 = excellent performance relative to expectations.
    var performance: Int
    /// 1–10, 10 = maximal effort (session RPE).
    var effort: Int
    var pain: PainLevel = .noPain
    var painArea: PainArea? = nil
    var note: String = ""
    var at: Date = Date()

    init(performance: Int, effort: Int, pain: PainLevel = .noPain, painArea: PainArea? = nil, note: String = "", at: Date = Date()) {
        self.performance = min(10, max(1, performance)); self.effort = min(10, max(1, effort))
        self.pain = pain; self.painArea = pain.needsArea ? (painArea ?? .other) : nil; self.note = note; self.at = at
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        performance = min(10, max(1, (try? c.decodeIfPresent(Int.self, forKey: .performance)) ?? 5))
        effort = min(10, max(1, (try? c.decodeIfPresent(Int.self, forKey: .effort)) ?? 5))
        pain = (try? c.decodeIfPresent(PainLevel.self, forKey: .pain)) ?? .noPain
        painArea = try? c.decodeIfPresent(PainArea.self, forKey: .painArea)
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
        at = (try? c.decodeIfPresent(Date.self, forKey: .at)) ?? Date(timeIntervalSince1970: 0)
    }
}

// MARK: Hybrid onboarding answers (brief A)

enum HybridGoal: String, Codable, CaseIterable {
    case strength, cyclingEndurance, balanced, generalFitness, custom
    var title: String { switch self { case .strength: return "Strength"; case .cyclingEndurance: return "Cycling endurance"; case .balanced: return "Balanced hybrid"; case .generalFitness: return "General fitness"; case .custom: return "Custom" } }
    /// The sport protected when time is short (existing TrainingPriority).
    var priority: TrainingPriority { switch self { case .strength: return .strength; case .cyclingEndurance: return .cycling; default: return .balanced } }
}

/// A strength split never implies a number of days: the rotation is repeated for as many sessions as the rider wants.
enum StrengthSplit: String, Codable, CaseIterable {
    case fullBody, pushPullLegs, upperLower, custom
    var title: String { switch self { case .fullBody: return "Full Body"; case .pushPullLegs: return "Push / Pull / Legs"; case .upperLower: return "Upper / Lower"; case .custom: return "Custom" } }
    var short: String { switch self { case .fullBody: return "Full Body"; case .pushPullLegs: return "PPL"; case .upperLower: return "Upper/Lower"; case .custom: return "Custom" } }
    var rotation: [StrengthFocus] {
        switch self {
        case .fullBody: return [.fullBody]
        case .pushPullLegs: return [.push, .pull, .legs]
        case .upperLower: return [.upper, .lower]
        case .custom: return []
        }
    }
    /// The strength sessions of one week in order. Custom slots are interleaved (2 × Full body + 1 × Core gives
    /// Full body, Core, Full body) so the same type is not stacked; a count different from the slots' sum repeats or
    /// truncates the sequence.
    /// `offset` continues the rotation across weeks (audit G-07): week n starts where week n − 1 stopped, so PPL with
    /// 2 lifts a week trains push, pull · legs, push · pull, legs … instead of never reaching legs.
    static func sessions(split: StrengthSplit, slots: [SplitSlot], count: Int, offset: Int = 0) -> [SplitSlot] {
        guard count > 0 else { return [] }
        var base: [SplitSlot]
        if split == .custom {
            var left = slots.map { max(1, $0.perWeek) }
            base = []
            var guardN = 0
            while left.contains(where: { $0 > 0 }), guardN < 100 {
                guardN += 1
                for i in slots.indices where left[i] > 0 { base.append(slots[i]); left[i] -= 1 }
            }
            if base.isEmpty { base = [SplitSlot(focus: .fullBody)] }
        } else {
            base = split.rotation.map { SplitSlot(focus: $0) }
        }
        if base.isEmpty { base = [SplitSlot(focus: .fullBody)] }
        let o = ((offset % base.count) + base.count) % base.count
        return (0..<count).map { base[($0 + o) % base.count] }
    }
    /// Weeks since a fixed Monday (5 Jan 2026), for `offset`: the rotation position of a week never depends on when
    /// the plan was generated.
    static func weekIndex(of monday: Date, calendar cal: Calendar = .current) -> Int {
        let ref = cal.date(from: DateComponents(year: 2026, month: 1, day: 5)) ?? Date(timeIntervalSince1970: 0)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: ref), to: cal.startOfDay(for: monday)).day ?? 0
        return Int((Double(days) / 7).rounded(.down))
    }
}

/// One entry of a custom split: a session type (or one of the rider's routines) and how often per week.
struct SplitSlot: Codable, Equatable, Identifiable {
    var id = UUID()
    var focus: StrengthFocus = .fullBody
    /// Name of a custom session type, e.g. "Core / joints" (used when focus == .custom).
    var label: String = ""
    /// The rider's routine for this slot (nil = the coach builds the session from the rider's exercises).
    var templateId: UUID? = nil
    var perWeek: Int = 1

    init(id: UUID = UUID(), focus: StrengthFocus = .fullBody, label: String = "", templateId: UUID? = nil, perWeek: Int = 1) {
        self.id = id; self.focus = focus; self.label = label; self.templateId = templateId; self.perWeek = perWeek
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        focus = (try? c.decodeIfPresent(StrengthFocus.self, forKey: .focus)) ?? .fullBody
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? ""
        templateId = try? c.decodeIfPresent(UUID.self, forKey: .templateId)
        perWeek = max(1, (try? c.decodeIfPresent(Int.self, forKey: .perWeek)) ?? 1)
    }
    var title: String { focus == .custom ? (label.isEmpty ? "Custom" : label) : focus.title }
}

// MARK: Automatic adjustments (brief D/E)

/// A planned session as the plan made it, before the coach changed it (kept on every adjusted session so each change
/// can be undone and "Restore original plan" is exact).
struct WorkoutPlanSnapshot: Codable, Equatable {
    var kind: WorkoutKind
    var minutes: Int
    var plannedEntries: [ExerciseEntry]?
    var intervalReps: Int?
    var generatedEntries: Bool

    init(kind: WorkoutKind, minutes: Int, plannedEntries: [ExerciseEntry]?, intervalReps: Int?, generatedEntries: Bool) {
        self.kind = kind; self.minutes = minutes; self.plannedEntries = plannedEntries; self.intervalReps = intervalReps; self.generatedEntries = generatedEntries
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try? c.decodeIfPresent(WorkoutKind.self, forKey: .kind)) ?? .other
        minutes = (try? c.decodeIfPresent(Int.self, forKey: .minutes)) ?? 0
        plannedEntries = try? c.decodeIfPresent([ExerciseEntry].self, forKey: .plannedEntries)
        intervalReps = try? c.decodeIfPresent(Int.self, forKey: .intervalReps)
        generatedEntries = (try? c.decodeIfPresent(Bool.self, forKey: .generatedEntries)) ?? false
    }
}

extension Workout {
    var planSnapshot: WorkoutPlanSnapshot { WorkoutPlanSnapshot(kind: kind, minutes: minutes, plannedEntries: plannedEntries, intervalReps: intervalReps, generatedEntries: generatedEntries) }
    /// The session with the coach's automatic changes taken out (itself when it was never adjusted).
    var restoredOriginal: Workout {
        guard let o = coachOriginal else { return self }
        var x = self
        x.kind = o.kind; x.minutes = o.minutes; x.plannedEntries = o.plannedEntries; x.intervalReps = o.intervalReps; x.generatedEntries = o.generatedEntries
        x.coachOriginal = nil
        return x
    }
    var coachAdjusted: Bool { coachOriginal != nil }
}

/// One bounded change to one future session, with the plain "why" and the numbers behind it.
struct PlanAdjustment: Codable, Equatable, Identifiable {
    enum Change: Codable, Equatable {
        case reps(exerciseId: String, delta: Int)
        case weight(exerciseId: String, deltaKg: Double)
        case sets(exerciseId: String, delta: Int)
        case kind(to: WorkoutKind)
        case intervalReps(delta: Int)
        case minutes(delta: Int)
        /// Approval only: replace one exercise of the session with a doable one (never applied silently).
        case replace(exerciseId: String, withId: String, name: String, pattern: MovementPattern)

        var key: String {
            switch self {
            case .reps(let e, _): return "reps:\(e)"
            case .weight(let e, _): return "weight:\(e)"
            case .sets(let e, _): return "sets:\(e)"
            case .kind: return "kind"
            case .intervalReps: return "intervals"
            case .minutes: return "minutes"
            case .replace(let e, _, _, _): return "replace:\(e)"
            }
        }
    }
    enum Category: String, Codable { case progression, reduction, recovery, substitution }

    var workoutId: UUID
    var change: Change
    var category: Category
    /// "Goblet squat: 20 kg → 21 kg"
    var summary: String
    /// Plain-language reason with the actual numbers.
    var why: String
    var createdAt: Date = Date()

    var key: String { "\(workoutId.uuidString)|\(change.key)" }
    var id: String { key }
}

/// A change the coach may not make on its own (fixed day, session count, split, replacing a saved exercise, over a
/// budget, a major load increase). Accept approves exactly the listed adjustments; Not now dismisses it.
struct AdaptiveProposal: Codable, Equatable, Identifiable {
    enum Reason: String, Codable {
        case fixedDay, sessionCount, split, replaceExercise, budget, majorLoad
        var title: String { switch self { case .fixedDay: return "Fixed day"; case .sessionCount: return "Sessions per week"; case .split: return "Strength split"; case .replaceExercise: return "Saved exercise"; case .budget: return "Time budget"; case .majorLoad: return "Bigger load increase" } }
    }
    var id: String
    var reason: Reason
    var text: String
    var why: String
    /// Empty = advice only (the rider changes it in Profile › Training profile or the routine).
    var adjustments: [PlanAdjustment] = []
}

/// What the last analysis saw, for the Adjustments view ("Coach (rules-based)").
struct AdaptationSummary: Codable, Equatable {
    enum Confidence: String, Codable { case low, medium, high
        var title: String { switch self { case .low: return "low — plan kept"; case .medium: return "medium"; case .high: return "high" } } }
    var at: Date
    var confidence: Confidence
    var findings: [String]
    var feedbackRequest: String? = nil
    var painAdvice: String? = nil
    var acuteLoad: Int? = nil
    var chronicLoad: Int? = nil
    var label: String = AdaptationExplainer.label

    init(at: Date, confidence: Confidence, findings: [String], feedbackRequest: String? = nil, painAdvice: String? = nil, acuteLoad: Int? = nil, chronicLoad: Int? = nil) {
        self.at = at; self.confidence = confidence; self.findings = findings; self.feedbackRequest = feedbackRequest; self.painAdvice = painAdvice; self.acuteLoad = acuteLoad; self.chronicLoad = chronicLoad
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = (try? c.decodeIfPresent(Date.self, forKey: .at)) ?? Date(timeIntervalSince1970: 0)
        confidence = (try? c.decodeIfPresent(Confidence.self, forKey: .confidence)) ?? .low
        findings = (try? c.decodeIfPresent([String].self, forKey: .findings)) ?? []
        feedbackRequest = try? c.decodeIfPresent(String.self, forKey: .feedbackRequest)
        painAdvice = try? c.decodeIfPresent(String.self, forKey: .painAdvice)
        acuteLoad = try? c.decodeIfPresent(Int.self, forKey: .acuteLoad)
        chronicLoad = try? c.decodeIfPresent(Int.self, forKey: .chronicLoad)
        label = (try? c.decodeIfPresent(String.self, forKey: .label)) ?? AdaptationExplainer.label
    }
}

/// Review N-15 / P3-12: short definitions so the rider can classify what they feel (coaching guidance, not a diagnosis).
func painDefinition(_ p: PainLevel) -> String {
    switch p {
    case .noPain: return "Nothing unusual."
    case .soreness: return "Soreness: a dull ache in the muscles you trained (not in a joint), 1–3 days after training, that eases as you warm up."
    case .discomfort: return "Discomfort: something feels off in one spot, but it is not sharp, not in a joint and does not change how you move."
    case .concerning: return "Pain: sharp or stabbing; in or around a joint; with swelling; changes how you move; or joint pain still there the next day."
    }
}
