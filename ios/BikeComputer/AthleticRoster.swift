import Foundation

// Onboarding Screen 3 — the Athletic Roster. Owner decision of 20 Nov 2026 (23:04): Cyclift is a multi-sport athletic
// platform, not a cycling-and-strength application with a list of other interests.
//
// Three things are kept apart (the decision's words):
//   1. SELECTED ACTIVITIES — what the athlete practises. Any catalogue activity can be selected, any number of them,
//      and any of them can be the main sport. Stored in `RiderProfile.activities` (catalogue identifiers, roster order;
//      the first one is the main sport).
//   2. SUPPORTED RECORDING — what Cyclift can log today: `RosterActivity.recording`.
//   3. SUPPORTED PLANNING — what Cyclift can schedule today: `RosterActivity.planning`.
// Selecting an activity grants nothing: the catalogue says what the existing engines do, in words, and nothing is
// planned or measured for an activity they do not cover.
//
// The stored training type (`TrainingMode`) and lead (`TrainingPriority`) still come from the PLANNABLE activities in
// the roster, exactly as before, because the planner has two engines today: cycling and gym strength.
//
// Storage is additive: `RiderProfile.sports` (the older, closed list) keeps receiving the activities it can name, so an
// older build reads the same record as before and simply does not see the newer selections.

enum RosterDomain: String, CaseIterable { case endurance, strength, recovery
    var title: String { switch self { case .endurance: return "Endurance"; case .strength: return "Strength"; case .recovery: return "Recovery" } }
}

/// The sport an activity is a discipline of. The athlete's identity is derived from the families selected.
enum RosterFamily: String, CaseIterable { case cycling, strength, running, swimming, walking, recovery
    var title: String {
        switch self {
        case .cycling: return "Cycling"; case .strength: return "Strength"; case .running: return "Running"
        case .swimming: return "Swimming"; case .walking: return "Walking & hiking"; case .recovery: return "Mobility & recovery"
        }
    }
    /// The word for an athlete of this one sport.
    var athlete: String {
        switch self {
        case .cycling: return "Cyclist"; case .strength: return "Strength athlete"; case .running: return "Runner"
        case .swimming: return "Swimmer"; case .walking: return "Walker"; case .recovery: return "Mobility & recovery"
        }
    }
    /// The word used in "Running/Strength hybrid".
    var short: String { switch self { case .walking: return "Walking"; case .recovery: return "Mobility"; default: return title } }
    var domain: RosterDomain { switch self { case .strength: return .strength; case .recovery: return .recovery; default: return .endurance } }
}

/// Which existing engine, if any, serves an activity.
enum RosterEngine: Equatable { case cycling, strength }

/// What Cyclift does for an activity today, told in words. Derived from `planning` and `recording`; never chosen freely.
enum RosterCapability: Int, CaseIterable {
    /// Cyclift plans and records it with an engine built for it.
    case plansAndRecords
    /// Planned and recorded with the general cycling or gym engine — not discipline-specific.
    case sharedRecorder
    /// In the roster only: Cyclift neither plans nor records it yet.
    case selectionOnly

    var mark: String { switch self { case .plansAndRecords: return "●"; case .sharedRecorder: return "◐"; case .selectionOnly: return "○" } }
    var plannable: Bool { self != .selectionOnly }
}

struct RosterActivity: Identifiable, Equatable {
    /// Catalogue identifier — what is stored. Never reused for a different activity.
    let id: String
    let title: String
    let family: RosterFamily
    /// The engine that schedules it today; nil = Cyclift cannot plan it.
    let planning: RosterEngine?
    /// The recorder that logs it today; nil = Cyclift cannot record it.
    let recording: RosterEngine?
    /// True when the engine was built for exactly this activity (road cycling, gym training).
    let native: Bool
    /// The older stored identifier, where one exists (kept in `RiderProfile.sports` for older builds).
    let legacy: RiderProfile.Sport?

    var domain: RosterDomain { family.domain }
    var capability: RosterCapability { planning == nil ? .selectionOnly : native ? .plansAndRecords : .sharedRecorder }
    /// The honest sentence shown under the name.
    var capabilityWords: String {
        switch (planning, native) {
        case (.cycling?, true), (.strength?, true): return "Planned · recorded"
        case (.cycling?, false): return "Planned and recorded as general cycling"
        case (.strength?, false): return "Planned and recorded as gym training"
        case (nil, _): return recording == nil ? "In your roster · not planned or recorded yet" : "In your roster · recorded, not planned yet"
        }
    }
}

enum AthleticRoster {
    /// The activity catalogue, in library order. It is a list: a new activity is one more line, with its true
    /// planning and recording support. Identifiers that existed before keep their meaning.
    static let library: [RosterActivity] = [
        .init(id: "roadCycling", title: "Road cycling", family: .cycling, planning: .cycling, recording: .cycling, native: true, legacy: .roadCycling),
        .init(id: "indoorCycling", title: "Indoor cycling", family: .cycling, planning: .cycling, recording: .cycling, native: false, legacy: .indoorCycling),
        .init(id: "mountainBike", title: "Mountain bike", family: .cycling, planning: .cycling, recording: .cycling, native: false, legacy: .mountainBike),
        .init(id: "gravel", title: "Gravel", family: .cycling, planning: .cycling, recording: .cycling, native: false, legacy: nil),
        .init(id: "commuting", title: "Commuting", family: .cycling, planning: .cycling, recording: .cycling, native: false, legacy: .commuting),
        .init(id: "strength", title: "Gym training", family: .strength, planning: .strength, recording: .strength, native: true, legacy: .strength),
        .init(id: "freeWeights", title: "Free weights", family: .strength, planning: .strength, recording: .strength, native: false, legacy: nil),
        .init(id: "machines", title: "Machines", family: .strength, planning: .strength, recording: .strength, native: false, legacy: nil),
        .init(id: "bodyweight", title: "Bodyweight", family: .strength, planning: nil, recording: nil, native: false, legacy: nil),
        .init(id: "calisthenics", title: "Calisthenics", family: .strength, planning: nil, recording: nil, native: false, legacy: nil),
        .init(id: "running", title: "Road running", family: .running, planning: nil, recording: nil, native: false, legacy: .running),
        .init(id: "treadmill", title: "Treadmill running", family: .running, planning: nil, recording: nil, native: false, legacy: nil),
        .init(id: "trailRunning", title: "Trail running", family: .running, planning: nil, recording: nil, native: false, legacy: nil),
        .init(id: "swimming", title: "Pool swimming", family: .swimming, planning: nil, recording: nil, native: false, legacy: .swimming),
        .init(id: "openWater", title: "Open-water swimming", family: .swimming, planning: nil, recording: nil, native: false, legacy: nil),
        .init(id: "walking", title: "Walking", family: .walking, planning: nil, recording: nil, native: false, legacy: nil),
        .init(id: "hiking", title: "Hiking", family: .walking, planning: nil, recording: nil, native: false, legacy: nil),
        .init(id: "mobility", title: "Stretching & mobility", family: .recovery, planning: nil, recording: nil, native: false, legacy: nil),
        .init(id: "breathing", title: "Breathing", family: .recovery, planning: nil, recording: nil, native: false, legacy: nil),
        .init(id: "sauna", title: "Sauna & cold", family: .recovery, planning: nil, recording: nil, native: false, legacy: nil),
    ]
    static func activity(_ id: String) -> RosterActivity? { library.first { $0.id == id } }
    static func activity(_ s: RiderProfile.Sport) -> RosterActivity? { library.first { $0.legacy == s } }

    /// One activity per sport, offered before anything is chosen: no sport is put ahead of the others by the app
    /// beyond the order of this list.
    static let starters = ["roadCycling", "strength", "running", "swimming", "walking", "mobility"]

    // MARK: stored forms

    /// The roster of a stored profile: the selected activities if they were ever saved; otherwise the older sports
    /// list, read as it always was. Unknown identifiers (from a newer catalogue) are dropped from view, never rewritten.
    static func roster(of p: RiderProfile) -> [String] {
        if let a = p.activities { return unique(a.filter { activity($0) != nil }) }
        return unique(p.sports.compactMap { activity($0)?.id })
    }
    /// The older stored list for a roster: the activities it can name, in roster order.
    static func legacySports(_ ids: [String]) -> [RiderProfile.Sport] {
        var seen = Set<RiderProfile.Sport>()
        return unique(ids).compactMap { activity($0)?.legacy }.filter { seen.insert($0).inserted }
    }

    /// The older "Other sports" list in Profile ticks or unticks one sport of the closed list. When the athlete also has
    /// a saved multi-sport roster, the same activity is added to or removed from it, so the two never disagree.
    static func toggleLegacy(_ sp: RiderProfile.Sport, in p: inout RiderProfile) {
        let on = p.sports.contains(sp)
        if on { p.sports.removeAll { $0 == sp } } else { p.sports.append(sp) }
        guard let ids = p.activities, let id = activity(sp)?.id else { return }
        p.activities = on ? removing(id, from: ids) : adding(id, to: ids)
    }

    // MARK: what the page shows

    struct Page: Equatable {
        /// The first activity in the roster — the athlete's main sport, whatever Cyclift supports for it.
        var main: RosterActivity?
        /// The activities the two existing engines plan from (first plannable of each).
        var mainEndurance: RosterActivity?
        var mainStrength: RosterActivity?
        /// The rows drawn under "Main sport(s)": the main sport, then the planned sports if they are not it.
        var mains: [RosterActivity]
        /// Everything else in the roster, in roster order.
        var also: [RosterActivity]
        /// The stored training type the roster means; nil = nothing in it can be planned today.
        var mode: TrainingMode?
        /// Up to four activities not in the roster yet.
        var suggestions: [RosterActivity]
        var showsLead: Bool { mode == .hybrid }
        var isEmpty: Bool { main == nil }
        /// The roster has activities, but none Cyclift can plan today.
        var hasOnlyUnsupported: Bool { mode == nil && main != nil }
    }

    static func view(_ ids: [String]) -> Page {
        let acts = unique(ids).compactMap { activity($0) }
        let endurance = acts.first { $0.planning == .cycling }
        let strength = acts.first { $0.planning == .strength }
        let mode: TrainingMode? = endurance != nil && strength != nil ? .hybrid : endurance != nil ? .cycling : strength != nil ? .strength : nil
        var mains: [RosterActivity] = []
        for x in [acts.first, endurance, strength] { if let x, !mains.contains(x) { mains.append(x) } }
        let also = acts.filter { !mains.contains($0) }
        let chosen = Set(acts.map(\.id)), families = Set(acts.map(\.family))
        // two sports not represented yet, then two further disciplines of the chosen sports, then the rest
        let pool = library.filter { !chosen.contains($0.id) }
        let fresh = starters.compactMap { activity($0) }.filter { !chosen.contains($0.id) && !families.contains($0.family) }
        let siblings = pool.filter { families.contains($0.family) }
        var seen = Set<String>()
        let suggestions = acts.isEmpty ? starters.compactMap { activity($0) } : Array((fresh.prefix(2) + siblings.prefix(2) + fresh.dropFirst(2) + siblings.dropFirst(2)).filter { seen.insert($0.id).inserted }.prefix(4))
        return Page(main: acts.first, mainEndurance: endurance, mainStrength: strength, mains: mains, also: also, mode: mode, suggestions: suggestions)
    }

    static func unique(_ ids: [String]) -> [String] { var seen = Set<String>(); return ids.filter { seen.insert($0).inserted } }

    /// Any catalogue activity can be added; there is no limit on how many.
    static func adding(_ id: String, to ids: [String]) -> [String] {
        guard activity(id) != nil, !ids.contains(id) else { return unique(ids) }
        return unique(ids) + [id]
    }
    static func removing(_ id: String, from ids: [String]) -> [String] { unique(ids).filter { $0 != id } }

    /// "Make main": the activity moves to the front of the roster. Nothing else is removed or reordered. Any selected
    /// activity can be the main sport — being main is the athlete's statement, not a claim of support.
    static func makingMain(_ id: String, in ids: [String]) -> [String] {
        guard activity(id) != nil, ids.contains(id) else { return unique(ids) }
        return [id] + unique(ids).filter { $0 != id }
    }

    /// The stored priority for a roster: only a hybrid roster has a lead; a single-engine roster follows its engine.
    static func priority(for mode: TrainingMode?, chosen: TrainingPriority?) -> TrainingPriority? {
        switch mode {
        case .hybrid?: return chosen ?? .balanced
        case .cycling?: return .cycling
        case .strength?: return .strength
        case nil: return nil
        }
    }

    // MARK: identity — from what was actually selected

    /// The sports in the roster, in roster order (the main sport's family first). Mobility & recovery only counts as a
    /// sport when nothing else was selected.
    static func families(_ ids: [String]) -> [RosterFamily] {
        var seen = Set<RosterFamily>()
        let all = unique(ids).compactMap { activity($0)?.family }.filter { seen.insert($0).inserted }
        let training = all.filter { $0 != .recovery }
        return training.isEmpty ? all : training
    }

    /// "Cyclist" · "Runner" · "Running/Strength hybrid" · "Multisport endurance athlete" · "Multisport athlete".
    static func identity(_ ids: [String]) -> String {
        let f = families(ids)
        switch f.count {
        case 0: return "No activity selected yet"
        case 1: return f[0].athlete
        case 2 where f.contains(.strength):
            let other = f.first { $0 != .strength }!
            return "\(other.short)/Strength hybrid"
        default:
            return f.contains(.strength) ? "Multisport athlete" : "Multisport endurance athlete"
        }
    }

    /// The identity with the balance of a hybrid plan, e.g. "Cycling/Strength hybrid · balanced".
    static func identityLine(_ ids: [String], priority: TrainingPriority?) -> String {
        let v = view(ids), name = identity(ids)
        guard v.mode == .hybrid else { return name }
        let p = priority ?? .balanced
        return "\(name) · \(p == .strength ? "strength-led" : p == .cycling ? "endurance-led" : "balanced")"
    }

    /// What Cyclift can and cannot do for this roster today, in one honest sentence (nil for an empty roster). Kept
    /// short enough to be read in full above the Continue button: up to two activities are named, more are counted
    /// (fast check 28 showed the longer wording cut off on screen).
    static func supportLine(_ ids: [String]) -> String? {
        let acts = unique(ids).compactMap { activity($0) }
        guard !acts.isEmpty else { return nil }
        let planned = acts.filter { $0.planning != nil }, unplanned = acts.filter { $0.planning == nil }
        func list(_ xs: [RosterActivity]) -> String {
            let t = xs.map(\.title); return t.count <= 1 ? (t.first ?? "") : t.dropLast().joined(separator: ", ") + " and " + t[t.count - 1]
        }
        if acts.count > 2 {
            if unplanned.isEmpty { return "Cyclift will plan and record all \(acts.count) activities." }
            if planned.isEmpty { return "All \(acts.count) are in your roster. Cyclift cannot plan or record them yet." }
            return "Cyclift will plan and record \(planned.count) of your \(acts.count) activities. The other \(unplanned.count == 1 ? "one is" : "\(unplanned.count) are") not planned or recorded yet."
        }
        if planned.isEmpty { return "\(list(unplanned)) \(unplanned.count == 1 ? "is" : "are") in your roster. Cyclift cannot plan or record \(unplanned.count == 1 ? "it" : "them") yet." }
        if unplanned.isEmpty { return "Cyclift will plan and record \(list(planned))." }
        return "Cyclift will plan and record \(list(planned)). \(list(unplanned)) is not planned or recorded yet."
    }
}

// MARK: - Goals for the roster (onboarding Screen 4 — owner decision of 21 Nov 2026, 00:30)
//
// The Goals page follows the athlete's actual roster: cycling goals for a cyclist, strength goals for a strength
// athlete, running goals for a runner, and so on. Two kinds of goal are kept apart, as the decision requires:
//   • PLANNED — a goal the existing planner builds sessions for (`planner` is its stored `GoalID`).
//   • SAVED ONLY — a goal the athlete can record for a sport Cyclift does not plan yet. It is stored and shown, and
//     it prescribes nothing: no session, load or measure is ever derived from it.
// Any number of goals can be chosen; exactly one of them is the main goal.

struct RosterGoal: Identifiable, Equatable {
    /// Stored identifier. A planned goal uses its `GoalID` raw value, so both kinds share one main-goal field.
    let id: String
    let title: String
    /// What the goal means, in a few words (shown on the card).
    let line: String
    let icon: String
    /// nil = general.
    let family: RosterFamily?
    /// The planner goal behind it; nil = saved only.
    let planner: GoalID?
}

enum RosterGoals {
    struct Group: Identifiable, Equatable {
        var id: String { title }
        let title: String
        let family: RosterFamily?
        /// True when the planner builds sessions for these goals with this roster.
        let planned: Bool
        let goals: [RosterGoal]
    }

    private static func planner(_ g: GoalID, _ family: RosterFamily?) -> RosterGoal {
        RosterGoal(id: g.rawValue, title: g.title, line: GoalInfo.line(g), icon: GoalInfo.icon(g), family: family, planner: g)
    }
    private static func saved(_ id: String, _ title: String, _ line: String, _ icon: String, _ family: RosterFamily) -> RosterGoal {
        RosterGoal(id: id, title: title, line: line, icon: icon, family: family, planner: nil)
    }
    static let cycling: [RosterGoal] = [GoalID.endurance, .power, .climbing, .sprint, .event].map { planner($0, .cycling) }
    static let strength: [RosterGoal] = [GoalID.strength, .muscle, .stamina, .maintain].map { planner($0, .strength) }
    static let general = planner(.fitness, nil)
    /// Goals that can be saved for sports without a planner. Titles and lines describe the aim only.
    static let savedOnly: [RosterFamily: [RosterGoal]] = [
        .running: [saved("runDistance", "Distance", "Run further", "point.topleft.down.to.point.bottomright.curvepath", .running),
                   saved("runPace", "Pace", "Run faster", "hare.fill", .running),
                   saved("runRace", "Race", "Be ready on the day", "flag.fill", .running)],
        .swimming: [saved("swimDistance", "Distance", "Swim further", "point.topleft.down.to.point.bottomright.curvepath", .swimming),
                    saved("swimTechnique", "Technique", "Swim more efficiently", "water.waves", .swimming),
                    saved("swimEvent", "Event", "Be ready on the day", "flag.fill", .swimming)],
        .walking: [saved("walkDaily", "Daily walking", "Move every day", "figure.walk", .walking),
                   saved("walkFurther", "Longer walks", "Go further on foot", "figure.hiking", .walking)],
        .recovery: [saved("mobilityRange", "Mobility", "Move more freely", "figure.mind.and.body", .recovery),
                    saved("recoveryHabit", "Recovery", "Recover between sessions", "leaf.fill", .recovery)],
        // strength disciplines Cyclift does not plan (bodyweight, calisthenics) when no gym activity is in the roster
        .strength: [saved("bodyStrength", "Strength", "Get stronger with bodyweight", "figure.strengthtraining.functional", .strength),
                    saved("bodySkill", "Skills", "Learn new movements", "figure.gymnastics", .strength)],
        .cycling: [],
    ]
    static var all: [RosterGoal] { cycling + strength + RosterFamily.allCases.flatMap { savedOnly[$0] ?? [] } + [general] }
    static func goal(_ id: String) -> RosterGoal? { all.first { $0.id == id } }

    /// The goal groups for a roster, in roster order, General last. A sport appears only if the athlete selected it.
    static func groups(roster ids: [String]) -> [Group] {
        let v = AthleticRoster.view(ids)
        var seen = Set<RosterFamily>(), out: [Group] = []
        for f in AthleticRoster.unique(ids).compactMap({ AthleticRoster.activity($0)?.family }) where seen.insert(f).inserted {
            switch f {
            case .cycling: out.append(Group(title: "Cycling", family: f, planned: true, goals: cycling))      // every cycling activity is planned
            case .strength:
                if v.mainStrength != nil { out.append(Group(title: "Strength", family: f, planned: true, goals: strength)) }
                else { out.append(Group(title: "Strength", family: f, planned: false, goals: savedOnly[f] ?? [])) }
            default: out.append(Group(title: f == .walking ? "Walking" : f == .recovery ? "Mobility & recovery" : f.title, family: f, planned: false, goals: savedOnly[f] ?? []))
            }
        }
        if !out.isEmpty { out.append(Group(title: "General", family: nil, planned: v.mode != nil, goals: [general])) }
        return out
    }

    /// The athlete's goals: every selected goal in the order chosen, and the one main goal.
    struct Selection: Equatable {
        var ids: [String] = []
        var main: String? = nil

        /// Choosing a goal adds it; choosing it again removes it. There is always exactly one main goal while any goal
        /// is selected: the first one chosen until the athlete stars another.
        mutating func toggle(_ id: String) {
            if let i = ids.firstIndex(of: id) { ids.remove(at: i) } else { ids.append(id) }
            settle()
        }
        /// Starring a selected goal makes it the main goal. No other goal is removed.
        mutating func setMain(_ id: String) { if ids.contains(id) { main = id } }
        /// Drops goals the roster no longer offers (a sport was removed) and repairs the main goal.
        mutating func keep(offered groups: [Group]) {
            let ok = Set(groups.flatMap(\.goals).map(\.id))
            ids = ids.filter { ok.contains($0) }
            settle()
        }
        private mutating func settle() {
            var seen = Set<String>(); ids = ids.filter { seen.insert($0).inserted }
            if let m = main, ids.contains(m) { return }
            main = ids.first
        }
        /// The goals the planner receives, in the order chosen.
        var plannerGoals: [GoalID] { ids.compactMap { RosterGoals.goal($0)?.planner } }
        /// The planner's main goal: the main goal if the planner knows it, otherwise the first planner goal chosen.
        var plannerMain: GoalID? { main.flatMap { RosterGoals.goal($0)?.planner } ?? plannerGoals.first }
        /// Goals stored for sports without a planner.
        var savedOnly: [String] { ids.filter { RosterGoals.goal($0).map { $0.planner == nil } ?? false } }
    }

    /// The explanation under the cards. A planned goal gets the planner's own rule (existing text). A saved-only goal,
    /// or any goal in a roster Cyclift cannot plan, says plainly that nothing is prescribed for it.
    static func explanation(main id: String?, roster ids: [String], selection: Selection) -> (title: String, text: String)? {
        guard let id, let g = goal(id) else { return nil }
        let v = AthleticRoster.view(ids)
        let sport = g.family.map { $0 == .walking ? "walking" : $0 == .recovery ? "mobility and recovery" : $0.title.lowercased() } ?? "general"
        let head = "\(g.title) · main goal"
        guard v.mode != nil else {
            return (head, "Saved as your main goal. Cyclift cannot plan \(g.family == nil ? "this roster" : sport) yet, so no sessions are prescribed. Add cycling or gym training to build a plan.")
        }
        if let p = g.planner { return (head, GoalInfo.effect(p)) }
        if let other = selection.plannerMain {
            return (head, "Saved as your main goal. Cyclift does not plan \(sport) yet, so nothing is prescribed for it; your plan follows \(other.title).")
        }
        return (head, "Saved as your main goal. Cyclift does not plan \(sport) yet, so nothing is prescribed for it. Choose a goal Cyclift can plan as well.")
    }
}
