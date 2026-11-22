import Foundation

// MARK: - Onboarding v3 (Stage 2 / V1): the pure layer behind the five stages and the Profile editors
//
// Foundation only, so the rules are unit-tested on the Linux harness and on CI:
//  • `OnboardingWeek` — the coach's proposed week from Stage A + B, the tap cycle, the feasibility line, and the one
//    mapping from a week on screen to the availability + profile fields the planner reads (ONE implementation, used by
//    onboarding Stage C and by Profile › Your week).
//  • `GoalInfo` — the one-line effect of each goal and the emphasis chart behind Stage B.
//  • `OnboardingApproach` — the three-line "approach" of Stage E and the first-workout pick from a dry-run plan.
//  • `OnboardingAnswers` — every answer and where it lands (ios/V1_ONBOARDING_PROFILE_DEVICES.md "Field → destination");
//    no answer never becomes a value (S2-0).
//
// Honesty rules kept here: nothing is invented (no sample weight, age or FTP), the proposal never overrides the days the
// athlete set, and the preview is a dry run of the real planner (`PlanEngine.week`) — the same inputs Approve saves.

/// The state of one day in the week builder.
enum DayKind: String, CaseIterable, Codable {
    case ride, lift, both, rest
    var icon: String { switch self { case .ride: return "bicycle"; case .lift: return "dumbbell"; case .both: return "figure.mixed.cardio"; case .rest: return "moon" } }
    var title: String { switch self { case .ride: return "Cycling"; case .lift: return "Strength"; case .both: return "Cycling and strength"; case .rest: return "Rest" } }
    var rides: Bool { self == .ride || self == .both }
    var lifts: Bool { self == .lift || self == .both }
}

/// Onboarding equipment presets mapped onto the one equipment record the planner reads (`EquipmentProfile`).
/// "Not sure" = not set → provisional bodyweight plan; a full gym is never assumed.
enum EquipmentPreset: String, CaseIterable, Hashable, Codable {
    case gym, home, bodyweight, notSure
    var title: String { switch self { case .gym: return "Gym"; case .home: return "Home"; case .bodyweight: return "Bodyweight"; case .notSure: return "Not sure" } }
    static let homeKit: Set<String> = ["dumbbell", "bench", "band", "pull-up bar", "kettlebell"]
    static var gymKit: Set<String> { Set(ExerciseCatalogue.equipmentOptions.filter { $0 != "bodyweight" }) }
    static func of(_ e: EquipmentProfile) -> EquipmentPreset {
        if !e.isSet { return .notSure }
        if e.owned.isEmpty { return .bodyweight }
        if e.owned.isSuperset(of: gymKit) { return .gym }
        return .home
    }
    /// Keeps the athlete's exclusions; replaces only what is owned.
    func apply(to e: EquipmentProfile) -> EquipmentProfile {
        switch self {
        case .gym: return EquipmentProfile(owned: Self.gymKit, excluded: e.excluded, confirmed: true)
        case .home: return EquipmentProfile(owned: Self.homeKit, excluded: e.excluded, confirmed: true)
        case .bodyweight: return EquipmentProfile(owned: [], excluded: e.excluded, confirmed: true)
        case .notSure: return EquipmentProfile(owned: [], excluded: e.excluded, confirmed: nil)
        }
    }
}

// MARK: - Equipment environments and the equipment catalogue (Build your week — owner decision 22 Nov 2026, 13:34)
//
// Gym | Home | Bodyweight | Custom are training ENVIRONMENTS — presets, not limits on what an athlete can own. Each
// has its own editable checklist; switching environments never deletes another one's selections. Nothing is shown or
// stored as available unless the athlete ticked it or the preset they chose provides it, and the preset's ticks are
// visible and editable. "Not sure" is not an environment (the older `EquipmentPreset` above still serves the older
// onboarding and the Profile editors, unchanged).
//
// The catalogue is one extensible list for every sport. An item whose `planner` name is set is one the existing
// strength planner understands (its own vocabulary, `ExerciseCatalogue.equipmentOptions`); ticking it changes which
// exercises can be offered. Every other item is stored exactly as chosen and changes NO generated training — and is
// labelled so.

enum EquipmentGroup: String, CaseIterable {
    case strength, cycling, running, swimming, mobility
    var title: String {
        switch self {
        case .strength: return "Strength"
        case .cycling: return "Cycling"
        case .running: return "Running"
        case .swimming: return "Swimming"
        case .mobility: return "Mobility and recovery"
        }
    }
    /// Owner decision 22 Nov 2026 (14:36): the lists for sports other than strength are PROVISIONAL and incomplete —
    /// a place to record what an athlete has, not exercise-planning support. Nothing in them changes any training.
    var isProvisional: Bool { self != .strength }
}

struct EquipmentItem: Identifiable, Equatable {
    /// Canonical identifier — what is stored. For an item the strength planner understands it IS the planner's name.
    let id: String
    let title: String
    let group: EquipmentGroup
    /// true = the strength planner uses it to choose exercises today.
    let planner: Bool
    /// For a future individual machine type (a leg press, a lat pulldown …): the grouped item it belongs to. None is
    /// listed yet — the planner knows machines only as the one grouped "Weight machines" item ("machine"), which stays
    /// as it is; an individual type added later names it here, so older selections of the group keep their meaning.
    var partOf: String? = nil
}

enum EquipmentCatalogue {
    static let items: [EquipmentItem] = [
        .init(id: "barbell", title: "Barbell", group: .strength, planner: true),
        .init(id: "dumbbell", title: "Dumbbells", group: .strength, planner: true),
        .init(id: "kettlebell", title: "Kettlebell", group: .strength, planner: true),
        .init(id: "bench", title: "Bench", group: .strength, planner: true),
        .init(id: "cable", title: "Cable machine", group: .strength, planner: true),
        .init(id: "machine", title: "Weight machines (leg press and others)", group: .strength, planner: true),
        .init(id: "band", title: "Resistance bands", group: .strength, planner: true),
        .init(id: "pull-up bar", title: "Pull-up bar", group: .strength, planner: true),
        .init(id: "trap bar", title: "Trap bar", group: .strength, planner: true),
        .init(id: "squat rack", title: "Squat rack", group: .strength, planner: false),
        .init(id: "dip bars", title: "Dip bars", group: .strength, planner: false),
        .init(id: "gymnastic rings", title: "Gymnastic rings", group: .strength, planner: false),
        .init(id: "weighted vest", title: "Weighted vest", group: .strength, planner: false),
        .init(id: "exercise mat", title: "Exercise mat", group: .mobility, planner: false),
        .init(id: "foam roller", title: "Foam roller", group: .mobility, planner: false),
        .init(id: "yoga blocks", title: "Yoga blocks", group: .mobility, planner: false),
        .init(id: "indoor trainer", title: "Indoor trainer", group: .cycling, planner: false),
        .init(id: "power meter", title: "Power meter", group: .cycling, planner: false),
        .init(id: "heart-rate strap", title: "Heart-rate strap", group: .cycling, planner: false),
        .init(id: "treadmill", title: "Treadmill", group: .running, planner: false),
        .init(id: "running watch", title: "Running watch", group: .running, planner: false),
        .init(id: "pool access", title: "Pool access", group: .swimming, planner: false),
        .init(id: "pull buoy", title: "Pull buoy", group: .swimming, planner: false),
        .init(id: "kickboard", title: "Kickboard", group: .swimming, planner: false),
        .init(id: "swim fins", title: "Swim fins", group: .swimming, planner: false),
    ]
    static func item(_ id: String) -> EquipmentItem? { items.first { $0.id == id } }
    /// Catalogue order, known items only, no duplicates.
    static func ordered(_ ids: [String]) -> [String] { items.map(\.id).filter(Set(ids).contains) }
    static func search(_ q: String) -> [EquipmentItem] {
        let t = q.trimmingCharacters(in: .whitespaces).lowercased()
        return t.isEmpty ? items : items.filter { $0.title.lowercased().contains(t) || $0.group.title.lowercased().contains(t) }
    }
    /// The grouped machines item the planner understands. Kept under this identifier for compatibility.
    static let machines = "machine"
    /// What the planner is told is owned: the ticked items, plus the group of any ticked individual type (`partOf`).
    static func plannerOwned(_ ids: [String]) -> Set<String> {
        Set(ids).union(ids.compactMap { item($0)?.partOf })
    }
    /// How many of the app's strength exercises the EXISTING planner could offer with this equipment — its own rule
    /// (`EquipmentProfile.hasEquipment`), nothing estimated. Items the planner does not understand change nothing.
    static func eligibleExercises(_ ids: [String]) -> (can: Int, of: Int) {
        let e = EquipmentProfile(owned: plannerOwned(ids), confirmed: true)
        let all = ExerciseCatalogue.builtIn
        return (all.filter { e.hasEquipment(for: $0) }.count, all.count)
    }
}

enum EquipmentEnvironment: String, CaseIterable, Hashable, Codable {
    case gym, home, bodyweight, custom
    var title: String {
        switch self { case .gym: return "Gym"; case .home: return "Home"; case .bodyweight: return "Bodyweight"; case .custom: return "Custom" }
    }
    /// The checklist this environment opens with (the owner's lists of 22 Nov 2026; "Leg press" is offered as "Weight
    /// machines", the planner's one name for leg press and the other machines). Custom lists the whole catalogue.
    var checklist: [String] {
        switch self {
        case .gym: return ["barbell", "dumbbell", "bench", "cable", "squat rack", "machine", "kettlebell", "band"]
        case .home: return ["dumbbell", "band", "kettlebell", "bench", "pull-up bar", "exercise mat", "barbell"]
        case .bodyweight: return ["pull-up bar", "dip bars", "band", "gymnastic rings", "weighted vest", "exercise mat", "dumbbell"]
        case .custom: return EquipmentCatalogue.items.map(\.id)
        }
    }
    /// The SUGGESTED STARTING SELECTION before the athlete edits it — shown ticked, reviewed and changed in the checklist;
    /// not a guarantee that a gym has every machine (owner, 22 Nov 2026, 14:36). Gym: its checklist (not every piece of
    /// equipment that exists). Home: the app's existing home kit. Bodyweight and Custom: nothing.
    var preset: [String] {
        switch self {
        case .gym: return checklist
        case .home: return EquipmentCatalogue.ordered(Array(EquipmentPreset.homeKit))
        case .bodyweight, .custom: return []
        }
    }
    /// The athlete's saved selection for this environment, or the preset when they have never edited it.
    func selection(in sets: [String: [String]]?) -> [String] { sets?[rawValue].map(EquipmentCatalogue.ordered) ?? preset }
    /// An existing athlete's stored equipment, read as an environment (nothing is changed by reading it).
    static func of(_ e: EquipmentProfile) -> EquipmentEnvironment? {
        guard e.isSet else { return nil }
        switch EquipmentPreset.of(e) { case .gym: return .gym; case .home: return .home; case .bodyweight: return .bodyweight; case .notSure: return nil }
    }
}

// MARK: - Goals: one-line effect and the emphasis behind Stage B

enum GoalInfo {
    /// What the goal means in one line (shown on the card).
    static func line(_ g: GoalID) -> String {
        switch g {
        case .endurance: return "Ride longer, steadier"
        case .power: return "More sustainable power"
        case .event: return "Be ready on the day"
        case .climbing: return "Hold power uphill"
        case .sprint: return "Faster short efforts"
        case .strength: return "Lift more weight"
        case .muscle: return "Add size and volume"
        case .stamina: return "Keep going longer"
        case .maintain: return "Keep strength, stay mobile"
        case .fitness: return "Feel better, move more"
        }
    }
    /// How the goal shapes training and what measures it (the "effect" line under the main goal) — rules that exist in
    /// the planner today; no promised outcome.
    static func effect(_ g: GoalID) -> String {
        switch g {
        case .endurance: return "Most riding stays easy (Zone 2) with one short tempo block a week; weekly riding time is the measure."
        case .power: return "One threshold session a week plus a long easy ride; progress is measured only by a tested FTP."
        case .event: return "Long rides build toward the date; the last two weeks taper. Progress = longest ride and consistency."
        case .climbing: return "Tempo and threshold work at low cadence; long rides keep the base. Measured by tested FTP and W/kg."
        case .sprint: return "Short hard efforts with full recovery on one ride a week; the rest stays easy. Measured by consistency."
        case .strength: return "Main lifts at 5–8 reps with longer rest; weight rises when you hit the top of the range. Measured by top sets."
        case .muscle: return "8–12 reps, more working sets per muscle each week. Measured by weekly working sets and top sets."
        case .stamina: return "12–15 reps with short rest; sets per session rise before loads do. Measured by sets done and top sets held."
        case .maintain: return "Two or three full-body sessions that hold your current loads. Measured by sessions done and top sets held."
        case .fitness: return "Balanced easy riding and full-body lifting. Measured by consistency first, then riding time and top sets."
        }
    }
    static func icon(_ g: GoalID) -> String {
        switch g {
        case .endurance: return "point.topleft.down.to.point.bottomright.curvepath"
        case .power: return "bolt.fill"
        case .event: return "flag.fill"
        case .climbing: return "chart.line.uptrend.xyaxis"
        case .sprint: return "hare.fill"
        case .strength: return "dumbbell.fill"
        case .muscle: return "figure.strengthtraining.traditional"
        case .stamina: return "arrow.triangle.2.circlepath"
        case .maintain: return "leaf.fill"
        case .fitness: return "heart.fill"
        }
    }
    struct Group: Identifiable, Equatable { var id: String { title }; let title: String; let goals: [GoalID] }
    /// The goal cards offered for a training type, grouped (cycling, strength, general).
    static func choices(for mode: TrainingMode) -> [Group] {
        var out: [Group] = []
        if mode.includesCycling { out.append(Group(title: "Cycling", goals: [.endurance, .power, .climbing, .sprint, .event])) }
        if mode.includesLifting { out.append(Group(title: "Strength", goals: [.strength, .muscle, .stamina, .maintain])) }
        out.append(Group(title: "General", goals: [.fitness]))
        return out
    }
    /// Shares of the week by emphasis (easy riding, hard riding, strength, rest) for the main goal — the small bar under
    /// the goal cards. Sums to 7 parts.
    struct Emphasis: Equatable { var easyRiding = 0, hardRiding = 0, strength = 0, rest = 0 }
    static func emphasis(mode: TrainingMode, primary: GoalID?, priority: TrainingPriority) -> Emphasis {
        var e = Emphasis()
        if mode.includesCycling {
            e.easyRiding = 3; e.hardRiding = 1
            if primary == .power || primary == .climbing { e.easyRiding = 2; e.hardRiding = 2 }
            if primary == .endurance || primary == .event { e.easyRiding = 4 }
        }
        if mode.includesLifting {
            e.strength = 2
            if primary == .strength || primary == .muscle { e.strength = 3 }
        }
        if mode == .hybrid {
            if priority == .cycling { e.easyRiding += 1; e.strength = max(1, e.strength - 1) }
            if priority == .strength { e.strength += 1; e.easyRiding = max(1, e.easyRiding - 1) }
        }
        e.rest = max(1, 7 - (e.easyRiding + e.hardRiding + e.strength))
        // seven parts in all: trim the largest training share until it fits (at least one rest part stays)
        while e.easyRiding + e.hardRiding + e.strength + e.rest > 7 {
            if e.easyRiding >= e.hardRiding && e.easyRiding >= e.strength { e.easyRiding -= 1 }
            else if e.strength >= e.hardRiding { e.strength -= 1 }
            else { e.hardRiding -= 1 }
        }
        return e
    }
}

// MARK: - The week: proposal, tap cycle, feasibility, and the one mapping into the planner's inputs

enum OnboardingWeek {
    /// A realistic first week from Stage A + B (the coach proposes; the athlete edits). Indices 0 = Monday.
    static func propose(mode: TrainingMode, cyclingLevel: RiderProfile.Level, strengthLevel: StrengthPrefs.Experience?, priority: TrainingPriority) -> [DayKind] {
        let beginner: Bool = {
            switch mode {
            case .cycling: return cyclingLevel == .beginner
            case .strength: return (strengthLevel ?? .beginner) == .beginner
            case .hybrid: return cyclingLevel == .beginner && (strengthLevel ?? .beginner) == .beginner
            }
        }()
        switch mode {
        case .cycling: return beginner ? [.rest, .ride, .rest, .ride, .rest, .ride, .rest] : [.rest, .ride, .ride, .rest, .ride, .ride, .rest]
        case .strength: return beginner ? [.lift, .rest, .lift, .rest, .lift, .rest, .rest] : [.lift, .lift, .rest, .lift, .lift, .rest, .rest]
        case .hybrid:
            switch priority {
            case .cycling: return [.lift, .ride, .rest, .lift, .rest, .ride, .ride]
            case .strength: return [.lift, .ride, .lift, .rest, .lift, .ride, .rest]
            case .balanced: return [.lift, .ride, .lift, .rest, .lift, .ride, .rest]
            }
        }
    }
    /// The states a tap cycles through for a training type (ride → lift → both (two-a-day) → rest).
    static func cycle(mode: TrainingMode, twoADay: Bool) -> [DayKind] {
        switch mode {
        case .cycling: return [.ride, .rest]
        case .strength: return [.lift, .rest]
        case .hybrid: return twoADay ? [.ride, .lift, .both, .rest] : [.ride, .lift, .rest]
        }
    }
    static func next(_ k: DayKind, mode: TrainingMode, twoADay: Bool) -> DayKind {
        let order = cycle(mode: mode, twoADay: twoADay)
        let at = order.firstIndex(of: k) ?? (order.count - 1)
        return order[(at + 1) % order.count]
    }
    /// A day normalised to the training type (switching type never loses a day: a ride day in Strength mode becomes a
    /// lift day; "both" collapses to a ride unless two-a-day is on).
    static func normalise(_ k: DayKind, mode: TrainingMode, twoADay: Bool) -> DayKind {
        switch (mode, k) {
        case (.cycling, .lift), (.cycling, .both): return .ride
        case (.strength, .ride), (.strength, .both): return .lift
        case (.hybrid, .both): return twoADay ? .both : .ride
        default: return k
        }
    }
    /// The saved availability as week kinds (for the editors), normalised to the type.
    static func kinds(of a: WeeklyAvailability?, mode: TrainingMode, twoADay: Bool) -> [DayKind]? {
        guard let a else { return nil }
        return a.days.map { d in normalise(d.cycles && d.lifts ? .both : d.cycles ? .ride : d.lifts ? .lift : .rest, mode: mode, twoADay: twoADay) }
    }
    static func rides(_ k: [DayKind]) -> Int { k.filter(\.rides).count }
    static func lifts(_ k: [DayKind]) -> Int { k.filter(\.lifts).count }
    static func minutes(_ k: [DayKind], ride: Int, lift: Int) -> Int { rides(k) * ride + lifts(k) * lift }

    /// The feasibility line under the week: time, rest, spacing. `ok` = nothing to warn about. Never blocks (the
    /// athlete's availability is never overridden); `blocking` only when there is no training day at all.
    struct Feasibility: Equatable { var ok: Bool; var blocking: Bool; var text: String }
    static func feasibility(_ k: [DayKind], mode: TrainingMode, ride: Int, lift: Int, strengthLevel: StrengthPrefs.Experience?) -> Feasibility {
        let r = rides(k), l = lifts(k), rest = k.filter { $0 == .rest }.count
        if r + l == 0 { return Feasibility(ok: false, blocking: true, text: "Pick at least one training day.") }
        if mode == .hybrid && r == 0 { return Feasibility(ok: false, blocking: true, text: "Hybrid needs at least one ride day.") }
        if mode == .hybrid && l == 0 { return Feasibility(ok: false, blocking: true, text: "Hybrid needs at least one strength day.") }
        var notes: [String] = []
        if rest == 0 { notes.append("no rest day — recovery will suffer") }
        var streak = 0, longest = 0
        for d in k + k.prefix(2) { streak = d == .rest ? 0 : streak + 1; longest = max(longest, streak) }
        if longest >= 4 { notes.append("\(longest) training days in a row") }
        if k.filter({ $0 == .both }).count > 1 { notes.append("two double days — keep one easy") }
        if l >= 4, (strengthLevel ?? .beginner) == .beginner { notes.append("4 lifts is a lot for a first block") }
        let spaced = (0..<7).allSatisfy { i in !k[i].lifts || !k[(i + 1) % 7].lifts }
        let time = durationText(minutes(k, ride: ride, lift: lift))
        if notes.isEmpty {
            return Feasibility(ok: true, blocking: false, text: "\(time) a week · \(rest) rest day\(rest == 1 ? "" : "s")\(l > 1 && spaced ? " · lifts ≥ 48 h apart" : "")")
        }
        return Feasibility(ok: false, blocking: false, text: "\(time) a week · " + notes.joined(separator: " · "))
    }
    static func durationText(_ m: Int) -> String { m % 60 == 0 ? "\(m / 60) h" : m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min" }

    /// The availability exactly as shown: one assignment per session at the session length.
    static func availability(_ k: [DayKind], ride: Int, lift: Int) -> WeeklyAvailability {
        WeeklyAvailability(days: k.map { d in
            switch d {
            case .ride: return DayAvailability(assignments: [DayAssignment(sport: .cycling, minutes: ride)])
            case .lift: return DayAvailability(assignments: [DayAssignment(sport: .strength, minutes: lift)])
            case .both: return DayAvailability(assignments: [DayAssignment(sport: .cycling, minutes: ride), DayAssignment(sport: .strength, minutes: lift)])
            case .rest: return DayAvailability(activity: .rest, minutes: 0)
            }
        })
    }
    /// Writes the week into the planner's inputs: firm per-day minutes (weekIsExplicit), the training days as preferred
    /// days, and the frequencies / weekly budgets the planner still reads kept in step. The ONE place this happens.
    static func write(_ k: [DayKind], ride: Int, lift: Int, into x: inout PlanInputs) {
        x.availability = availability(k, ride: ride, lift: lift)
        let r = rides(k), l = lifts(k)
        x.profile.weekIsExplicit = true
        x.profile.preferredDays = k.indices.filter { k[$0] != .rest }
        x.profile.trainingDaysPerWeek = x.profile.preferredDays.count
        if x.profile.trainingMode.includesCycling, r > 0 {
            x.profile.cyclingDaysPerWeek = r
            x.profile.cyclingSessionMinutes = ride
            x.profile.hoursPerWeek = max(1, Int((Double(r * ride) / 60).rounded(.up)))
        }
        if x.profile.trainingMode.includesLifting {
            x.profile.liftDaysPerWeek = l
            x.profile.strengthSessionMinutes = lift
            x.profile.liftingHoursPerWeek = l == 0 ? 0 : max(1, Int((Double(l * lift) / 60).rounded(.up)))
            x.profile.confirmSessionLength = nil
        } else {
            x.profile.liftDaysPerWeek = 0; x.profile.liftingHoursPerWeek = 0
        }
    }
    /// The same, from the athlete's chosen schedule: every plannable session keeps ITS OWN minutes (nothing is averaged
    /// or copied between days). The single "typical" lengths the planner also reads are the most frequent chosen ones.
    static func write(schedule w: ChosenWeek.Week, into x: inout PlanInputs) {
        x.availability = ChosenWeek.availability(w)
        let k = ChosenWeek.kinds(w)
        let r = rides(k), l = lifts(k)
        x.profile.weekIsExplicit = true
        x.profile.preferredDays = k.indices.filter { k[$0] != .rest }
        x.profile.trainingDaysPerWeek = x.profile.preferredDays.count
        if x.profile.trainingMode.includesCycling, r > 0 {
            x.profile.cyclingDaysPerWeek = r
            if let t = ChosenWeek.typicalMinutes(w, engine: .cycling) { x.profile.cyclingSessionMinutes = t }
            x.profile.hoursPerWeek = max(1, Int((Double(ChosenWeek.minutes(w, engine: .cycling)) / 60).rounded(.up)))
        }
        if x.profile.trainingMode.includesLifting {
            x.profile.liftDaysPerWeek = l
            if let t = ChosenWeek.typicalMinutes(w, engine: .strength) { x.profile.strengthSessionMinutes = t }
            x.profile.liftingHoursPerWeek = l == 0 ? 0 : max(1, Int((Double(ChosenWeek.minutes(w, engine: .strength)) / 60).rounded(.up)))
            x.profile.confirmSessionLength = nil
        } else {
            x.profile.liftDaysPerWeek = 0; x.profile.liftingHoursPerWeek = 0
        }
    }
    static let defaultRideMinutes = 60
    static let defaultLiftMinutes = 30
}

// MARK: - The athlete's chosen week (Build your week — owner decision 21 Nov 2026, 21:18)
//
// A new athlete starts with seven rest days and decides each training day: an activity from THEIR roster, its own
// duration, up to two sessions a day. This is the athlete's chosen schedule — availability and preferred activities —
// not a generated programme. Sessions of sports Cyclift plans today are passed to the planner with exactly these
// minutes; sessions of other sports are saved and never turned into cycling or strength.

/// One chosen session: a roster activity (catalogue identifier) and its length.
struct ChosenSession: Codable, Equatable, Hashable {
    var activity: String
    var minutes: Int
}

enum ChosenWeek {
    typealias Week = [[ChosenSession]]
    static let maxPerDay = 2
    static var empty: Week { Array(repeating: [], count: 7) }

    static func engine(_ id: String) -> RosterEngine? { AthleticRoster.activity(id)?.planning }
    /// The length a newly added session starts at — the app's existing ride and strength defaults; 30 minutes for a
    /// sport without a planner. A starting point for the stepper, not a prescription.
    static func defaultMinutes(_ id: String) -> Int {
        engine(id) == .cycling ? OnboardingWeek.defaultRideMinutes : OnboardingWeek.defaultLiftMinutes
    }
    static func range(_ id: String) -> ClosedRange<Int> { engine(id) == .strength ? 15...120 : AthleticRoster.activity(id)?.family == .cycling ? 20...300 : 10...300 }
    static func step(_ id: String) -> Int { engine(id) == .cycling ? 10 : 5 }

    /// Seven days, known activities only, minutes inside the activity's range, at most two sessions a day. Any two
    /// roster activities may share a day, the same sport or the same activity twice included (owner decision 21 Nov
    /// 2026, 22:22); each is stored separately, in the order chosen.
    static func normalised(_ w: Week?) -> Week {
        var out = empty
        for (i, day) in (w ?? []).prefix(7).enumerated() {
            out[i] = day.filter { AthleticRoster.activity($0.activity) != nil }.prefix(maxPerDay).map { s in
                let r = range(s.activity)
                return ChosenSession(activity: s.activity, minutes: min(r.upperBound, max(r.lowerBound, s.minutes)))
            }
        }
        return out
    }
    /// A tap on an activity in the day editor adds one session of it at its starting length. Nothing already chosen is
    /// replaced; a third session is not added.
    static func adding(_ id: String, to day: [ChosenSession]) -> [ChosenSession] {
        guard AthleticRoster.activity(id) != nil, day.count < maxPerDay else { return day }
        return day + [ChosenSession(activity: id, minutes: defaultMinutes(id))]
    }

    // --- what the planner is given: plannable sessions only

    static func kinds(_ w: Week) -> [DayKind] {
        normalised(w).map { day in
            let r = day.contains { engine($0.activity) == .cycling }, l = day.contains { engine($0.activity) == .strength }
            return r && l ? .both : r ? .ride : l ? .lift : .rest
        }
    }
    static func hasPlannable(_ w: Week) -> Bool { w.contains { $0.contains { engine($0.activity) != nil } } }
    /// The sessions of sports Cyclift plans today (what the Blueprint's plan covers).
    static func plannable(_ w: Week) -> Week { normalised(w).map { $0.filter { engine($0.activity) != nil } } }
    static func availability(_ w: Week) -> WeeklyAvailability {
        WeeklyAvailability(days: normalised(w).map { day in
            // every session the planner can genuinely handle, each with its own minutes — rides first, as the planner's
            // own week writes them. Two rides or two strength sessions on a day are both passed (the planner schedules
            // both; verified by testThePlannerTakesEveryPlannableSessionOfTheChosenWeek). Other sports are not passed.
            let a: [DayAssignment] = day.filter { engine($0.activity) == .cycling }.map { DayAssignment(sport: .cycling, minutes: $0.minutes) }
                + day.filter { engine($0.activity) == .strength }.map { DayAssignment(sport: .strength, minutes: $0.minutes) }
            return a.isEmpty ? DayAvailability(activity: .rest, minutes: 0) : DayAvailability(assignments: a)
        })
    }
    static func minutes(_ w: Week, engine e: RosterEngine) -> Int { w.joined().filter { engine($0.activity) == e }.reduce(0) { $0 + $1.minutes } }
    /// The most frequent chosen length for an engine (the longer one on a tie); nil when none is chosen.
    static func typicalMinutes(_ w: Week, engine e: RosterEngine) -> Int? {
        var n: [Int: Int] = [:]
        for s in w.joined() where engine(s.activity) == e { n[s.minutes, default: 0] += 1 }
        return n.max { ($0.value, $0.key) < ($1.value, $1.key) }?.key
    }
    /// An existing athlete's saved availability as a schedule (their choices are kept, never reset): each saved ride
    /// or strength session with its saved minutes, named by the roster's main activity for that engine.
    static func from(_ a: WeeklyAvailability?, roster ids: [String]) -> Week? {
        guard let a, a.days.count == 7 else { return nil }
        let acts = ids.compactMap { AthleticRoster.activity($0) }
        let ride = acts.first { $0.planning == .cycling }?.id ?? "roadCycling"
        let lift = acts.first { $0.planning == .strength }?.id ?? "strength"
        return normalised(a.days.map { d in
            d.assignments.map { ChosenSession(activity: $0.sport == .cycling ? ride : lift, minutes: $0.minutes) }
        })
    }

    // --- the weekly summary

    struct Totals: Equatable { var minutes = 0, sessions = 0, trainingDays = 0, restDays = 7 }
    static func totals(_ w: Week) -> Totals {
        let n = normalised(w)
        let days = n.filter { !$0.isEmpty }.count
        return Totals(minutes: n.joined().reduce(0) { $0 + $1.minutes }, sessions: n.joined().count, trainingDays: days, restDays: 7 - days)
    }
    /// "Cycling 2 h · Strength 1 h 30 min · Running 45 min" — by sport, in the order first scheduled.
    static func bySport(_ w: Week) -> [(sport: String, minutes: Int)] {
        var order: [RosterFamily] = [], sum: [RosterFamily: Int] = [:]
        for s in normalised(w).joined() {
            guard let f = AthleticRoster.activity(s.activity)?.family else { continue }
            if sum[f] == nil { order.append(f) }
            sum[f, default: 0] += s.minutes
        }
        return order.map { ($0.title, sum[$0] ?? 0) }
    }
    /// The week's checks. Blocking ONLY when there is no training session at all. Owner decision 21 Nov 2026 (22:22): a
    /// cycling-and-strength athlete is NOT required to schedule both sports — a roster activity does not have to appear
    /// in every week — so the older "hybrid needs a ride day and a strength day" block is not applied to the chosen
    /// week. That is safe: the planner plans exactly the sessions it is given, and a week with only rides or only
    /// strength sessions yields only those (testAHybridAthleteMayScheduleOneSportOnly). The other notes are the
    /// planner's existing ones, counted over every chosen session; none of them blocks.
    /// Owner decision 22 Nov 2026 (14:36): a week with any strength session the planner builds needs a training
    /// environment (Gym, Home, Bodyweight or Custom) before Continue. Never asked of a week without one.
    static func needsEnvironment(_ w: Week) -> Bool { normalised(w).joined().contains { engine($0.activity) == .strength } }
    static func feasibility(_ w: Week, strengthLevel: StrengthPrefs.Experience?) -> OnboardingWeek.Feasibility {
        let n = normalised(w), t = totals(n), k = kinds(n)
        if t.sessions == 0 { return .init(ok: false, blocking: true, text: "Pick at least one training day.") }
        var notes: [String] = []
        if t.restDays == 0 { notes.append("no rest day — recovery will suffer") }
        var streak = 0, longest = 0
        for d in n + n.prefix(2) { streak = d.isEmpty ? 0 : streak + 1; longest = max(longest, streak) }
        if longest >= 4 { notes.append("\(min(longest, 7)) training days in a row") }
        if n.filter({ $0.count > 1 }).count > 1 { notes.append("two double days — keep one easy") }
        let l = n.joined().filter { engine($0.activity) == .strength }.count
        if l >= 4, (strengthLevel ?? .beginner) == .beginner { notes.append("4 lifts is a lot for a first block") }
        let spaced = (0..<7).allSatisfy { i in !k[i].lifts || !k[(i + 1) % 7].lifts }
        let time = OnboardingWeek.durationText(t.minutes)
        if notes.isEmpty {
            return .init(ok: true, blocking: false, text: "\(time) a week · \(t.restDays) rest day\(t.restDays == 1 ? "" : "s")\(l > 1 && spaced ? " · lifts ≥ 48 h apart" : "")")
        }
        return .init(ok: false, blocking: false, text: "\(time) a week · " + notes.joined(separator: " · "))
    }
}

// MARK: - Stage E: the approach and the first workout (from a dry-run plan)

enum OnboardingApproach {
    /// Three lines, each true for these answers (planner rules ENG-D1, E1/E3, H1, C2, hybrid spacing).
    static func lines(primary: GoalID?, mode: TrainingMode, kinds: [DayKind], liftMinutes: Int, ftpKnown: Bool, ftpWatts: Int?, equipmentProvisional: Bool) -> [String] {
        var out: [String] = []
        if let g = primary {
            var first = GoalInfo.effect(g).split(separator: ";").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? GoalInfo.effect(g)
            if !first.hasSuffix(".") { first += "." }
            out.append("\(g.title): \(first)")
        } else { out.append("A balanced first block.") }
        let l = OnboardingWeek.lifts(kinds), r = OnboardingWeek.rides(kinds)
        if mode.includesLifting, l > 0 {
            out.append(l <= 3 ? "\(l) short lift\(l == 1 ? "" : "s") as full body — not split by muscle, \(liftMinutes) min each." : "\(l) lifts, upper and lower alternating.")
        } else if r > 0 {
            out.append("\(r) ride\(r == 1 ? "" : "s"), mostly easy, one steadier.")
        }
        if mode.includesCycling {
            out.append(ftpKnown && ftpWatts != nil ? "Power targets from your \(ftpWatts!) W FTP." : "FTP Unknown: heart rate or effort guides rides, never guessed watts.")
        } else {
            out.append(equipmentProvisional ? "Bodyweight until you confirm equipment." : "Loads start from what you log in week 1.")
        }
        if mode == .hybrid, l > 0, r > 0, out.count < 3 { out.append("Hard rides are kept away from leg-heavy lifts.") }
        return Array(out.prefix(3))
    }
    /// The first planned training session on or after today (rest days skipped).
    static func firstWorkout(in plan: [Workout], from today: Date, calendar cal: Calendar = .current) -> Workout? {
        let d0 = cal.startOfDay(for: today)
        return plan.filter { $0.date >= d0 && ($0.kind.isRide || $0.kind == .strength) }.sorted { ($0.date, $0.sequence) < ($1.date, $1.sequence) }.first
    }
}

// MARK: - Every answer and its destination (one authoritative profile; no answer → nothing invented)

/// What the five stages ask, as plain values. `apply` is the only mapping from answers to the planner's inputs; the
/// onboarding and the Profile editors both write through it. Fields left nil leave the stored value untouched
/// (onboarding) and never produce a default (a missing weight stays Unknown, a missing FTP stays Unknown).
struct OnboardingAnswers: Equatable {
    // Stage A
    var name: String? = nil
    var mode: TrainingMode? = nil
    var cyclingLevel: RiderProfile.Level? = nil
    var strengthLevel: StrengthPrefs.Experience? = nil
    var priority: TrainingPriority? = nil
    var dateOfBirth: Date? = nil
    var weightKg: Double? = nil
    /// Height in whole centimetres (the stored unit). nil leaves the stored value untouched; never a default.
    var heightCm: Int? = nil
    /// Onboarding v3.4 roster: the stored sports list, in roster order (the first plannable sport of a domain is its
    /// main sport — see AthleticRoster). nil leaves the stored list untouched.
    var sports: [RiderProfile.Sport]? = nil
    /// The multi-sport roster (owner decision 20 Nov 2026): catalogue identifiers in roster order, first = main sport.
    /// nil leaves the stored selection untouched. When given, the older `sports` list is written from it as well.
    var activities: [String]? = nil
    // Stage B
    var goals: [GoalID]? = nil
    var primaryGoal: GoalID? = nil
    /// Every selected goal in the order chosen, planned and saved-only alike (`RosterGoals` identifiers), and the one
    /// main goal. nil leaves the stored values untouched. `goals` / `primaryGoal` above stay what the planner reads.
    var goalIDs: [String]? = nil
    var mainGoalID: String? = nil
    // Stage C
    var week: [DayKind]? = nil
    /// Build your week (owner decision 21 Nov 2026, 21:18): the athlete's own schedule — per day, up to two sessions,
    /// each a roster activity with its own duration. When set it is the authoritative week: the planner's availability
    /// is written from its plannable sessions with exactly these minutes, and every session (planned sport or not) is
    /// stored on the profile. nil = not chosen here (the older `week` + week-wide minutes path is used, unchanged).
    var schedule: [[ChosenSession]]? = nil
    /// The profile-only outcome: the schedule is saved, nothing plan-shaped is written from it.
    var scheduleOnly = false
    var rideMinutes: Int? = nil
    var liftMinutes: Int? = nil
    var equipment: EquipmentPreset? = nil
    /// Build your week (22 Nov 2026): the chosen training environment and each environment's own equipment selection
    /// (identifiers of `EquipmentCatalogue`). nil = not chosen there; the older `equipment` preset path is then used.
    var environment: EquipmentEnvironment? = nil
    var equipmentSets: [String: [String]]? = nil
    var supersets: Bool? = nil
    // Stage D
    var ftpWatts: Int? = nil
    var ftpSource: FTPSource? = nil     // .entered / .tested with a value; .unknown clears

    /// Writes the answers into the planner's inputs (profile, availability, equipment, strength preferences).
    func apply(to x: inout PlanInputs, now: Date = Date()) {
        if let n = name?.trimmingCharacters(in: .whitespaces), !n.isEmpty { x.profile.name = n }
        if let m = mode {
            x.profile.trainingMode = m
            switch m {
            case .cycling: x.profile.priority = .cycling
            case .strength: x.profile.priority = .strength
            case .hybrid: x.profile.priority = priority ?? .balanced
            }
        } else if let p = priority, x.profile.trainingMode == .hybrid { x.profile.priority = p }
        if let ids = activities {
            x.profile.activities = AthleticRoster.unique(ids.filter { AthleticRoster.activity($0) != nil })
            x.profile.sports = AthleticRoster.legacySports(ids)
        } else if let s = sports { x.profile.sports = s }
        if let l = cyclingLevel { x.profile.level = l }
        if let s = strengthLevel { x.strengthPrefs.experience = s; x.profile.confirmStrengthLevel = nil }
        // re-applying the same value never re-dates it (resume and keystrokes call this repeatedly)
        if let d = dateOfBirth, d != x.profile.dateOfBirth || x.profile.provenance(.dateOfBirth).source != .entered { x.profile.setDateOfBirth(d, at: now) }
        if let w = weightKg, w != x.profile.weightKg || x.profile.provenance(.weight).source != .entered { x.profile.setWeight(w, source: .entered, at: now) }
        if let h = heightCm, BodyMeasure.heightRangeCm.contains(h) { x.profile.heightCm = h }
        if let g = goals, !g.isEmpty {
            x.profile.goals = g
            x.profile.primaryGoal = (primaryGoal.flatMap { g.contains($0) ? $0 : nil }) ?? g.first
            if let c = (x.profile.primaryGoal?.cyclingGoal ?? g.compactMap(\.cyclingGoal).first) { x.profile.goal = c }
            if let s = (x.profile.primaryGoal?.strengthGoal ?? g.compactMap(\.strengthGoal).first) { x.strengthPrefs.goal = s }
        }
        if let ids = goalIDs {
            let sel = RosterGoals.Selection(ids: ids, main: mainGoalID)
            x.profile.activityGoals = sel.savedOnly
            x.profile.mainGoalID = sel.main.flatMap { ids.contains($0) ? $0 : nil }
        }
        if let s = schedule {
            let w = ChosenWeek.normalised(s)
            x.profile.chosenWeek = w
            if !scheduleOnly, ChosenWeek.hasPlannable(w) { OnboardingWeek.write(schedule: w, into: &x) }
        } else if let w = week {
            OnboardingWeek.write(w, ride: rideMinutes ?? x.profile.cyclingSessionMinutes ?? OnboardingWeek.defaultRideMinutes,
                                 lift: liftMinutes ?? x.profile.strengthSessionMinutes ?? OnboardingWeek.defaultLiftMinutes, into: &x)
        } else {
            if let r = rideMinutes { x.profile.cyclingSessionMinutes = r }
            if let l = liftMinutes { x.profile.strengthSessionMinutes = l; x.profile.confirmSessionLength = nil }
        }
        if let env = environment {
            // exactly what is ticked for the chosen environment — never more; the athlete's exercise exclusions are kept
            x.equipment = EquipmentProfile(owned: EquipmentCatalogue.plannerOwned(env.selection(in: equipmentSets)), excluded: x.equipment.excluded, confirmed: true)
            x.profile.equipmentEnvironment = env.rawValue
        } else if let e = equipment { x.equipment = e.apply(to: x.equipment) }
        if let s = equipmentSets { x.profile.equipmentSets = s }      // every environment's selection, kept when another is chosen
        if let s = supersets { x.strengthPrefs.prefersSupersets = s }
        if let src = ftpSource {
            if src == .unknown { x.profile.setFTP(nil, source: .unknown) }
            else if let w = ftpWatts, (50...600).contains(w) { x.profile.setFTP(w, source: src) }
        }
    }
}

// MARK: - Devices: the ecosystem cards (Stage D and Profile › Devices) — pure over the real device states

/// One row of the ecosystem: the device, what it provides, its real state and the ONE action that works today.
struct DeviceCardModel: Identifiable, Equatable {
    enum Action: Equatable { case none, connectHealth, connectBoard, pairSensor, openDetail }
    var id: String
    var name: String
    var systemImage: String
    var provides: String
    var state: DeviceState
    var detail: String
    var lastSyncedAt: Date?
    var action: Action
    var actionTitle: String?
}

extension DeviceState {
    /// The presentational state (a case added later falls back to "problem" rather than hiding the device).
    var cy: CyDeviceState {
        switch self {
        case .notPaired: return .notPaired
        case .paired: return .paired
        case .connected: return .connected
        case .receivingData: return .receiving
        case .problem: return .problem
        @unknown default: return .problem
        }
    }
}

/// Builds the device cards from the real link signals (the hub's device states). Pure over the status dictionary.
enum DeviceCards {
    /// The hub's source ids (kept here so the rules stay Foundation-only).
    static let healthId = "apple-health", watchId = "watch", boardId = "bikecomputer"
    struct Sensor: Equatable { var id: String; var name: String; var provides: String; var hasHR: Bool; var hasPower: Bool; var hasCadence: Bool }
    static func build(states: [String: DeviceStatus], mode: TrainingMode, bleSensors: [Sensor], healthAvailable: Bool, boardRemembered: Bool) -> [DeviceCardModel] {
        var out: [DeviceCardModel] = []
        func st(_ id: String) -> DeviceStatus? { states[id] }
        let health = st(healthId)
        let healthOn = health?.state.isConnectedOrBetter ?? false
        out.append(DeviceCardModel(id: healthId, name: "Apple Health", systemImage: "heart.text.square.fill", provides: "Workouts, weight, resting HR, HRV, sleep",
                                   state: health?.state ?? .notPaired, detail: health?.detail ?? (healthAvailable ? "not set up" : "not available on this device"), lastSyncedAt: health?.lastSyncedAt,
                                   action: healthAvailable ? (healthOn ? .openDetail : .connectHealth) : .none,
                                   actionTitle: healthAvailable ? (healthOn ? "Manage" : "Connect") : nil))
        let watch = st(watchId)
        out.append(DeviceCardModel(id: watchId, name: "Apple Watch", systemImage: "applewatch", provides: "Heart rate while you train",
                                   state: watch?.state ?? .notPaired, detail: watch?.detail ?? "not set up", lastSyncedAt: watch?.lastSyncedAt, action: .openDetail, actionTitle: "Manage"))
        if mode.includesCycling {
            let board = st(boardId)
            let boardOn = (board?.state.isConnectedOrBetter ?? false) || boardRemembered
            out.append(DeviceCardModel(id: boardId, name: "Cyclift BikeComputer", systemImage: "circle.hexagongrid.circle", provides: "Live ride display and recording",
                                       state: board?.state ?? .notPaired, detail: board?.detail ?? "not set up", lastSyncedAt: board?.lastSyncedAt,
                                       action: boardOn ? .openDetail : .connectBoard, actionTitle: boardOn ? "Manage" : "Connect"))
            for s in bleSensors {
                let d = st(s.id)
                let icon = s.hasPower ? "bolt.fill" : s.hasHR ? "heart.fill" : "gauge.with.dots.needle.33percent"
                out.append(DeviceCardModel(id: s.id, name: s.name, systemImage: icon, provides: s.provides,
                                           state: d?.state ?? .paired, detail: d?.detail ?? "paired", lastSyncedAt: d?.lastSyncedAt, action: .openDetail, actionTitle: "Manage"))
            }
            if !bleSensors.contains(where: { $0.hasHR }) { out.append(DeviceCardModel(id: "add.hr", name: "Heart-rate strap", systemImage: "heart.fill", provides: "Bluetooth chest or arm strap", state: .notPaired, detail: "not set up", lastSyncedAt: nil, action: .pairSensor, actionTitle: "Pair")) }
            if !bleSensors.contains(where: { $0.hasPower }) { out.append(DeviceCardModel(id: "add.power", name: "Power meter", systemImage: "bolt.fill", provides: "Bluetooth power and cadence", state: .notPaired, detail: "not set up", lastSyncedAt: nil, action: .pairSensor, actionTitle: "Pair")) }
            if !bleSensors.contains(where: { $0.hasCadence }) { out.append(DeviceCardModel(id: "add.cadence", name: "Cadence / speed sensor", systemImage: "gauge.with.dots.needle.33percent", provides: "Bluetooth cadence and speed", state: .notPaired, detail: "not set up", lastSyncedAt: nil, action: .pairSensor, actionTitle: "Pair")) }
        }
        return out
    }
}

// MARK: - Onboarding › Connect your devices (owner's approved direction, 22 Nov 2026, 15:55)
//
// Five integrations, always in this order: Apple Health, Apple Watch, WHOOP, Garmin, Bluetooth devices. Every one is
// optional. A row says only what is true: Connected, Not connected, Coming soon (no integration exists), or — in
// Cyclift Lab, which connects to nothing — Not available in Lab. An action is offered only where pressing it starts a
// real connection or opens a real settings screen; there are no decorative buttons. The Cyclift BikeComputer and the
// separate bike-sensors row are not on this page (the BikeComputer keeps its own settings elsewhere; supported cycling
// and heart-rate sensors are paired under Bluetooth devices). FTP is not asked here (it stays in Performance settings).

struct OnbConnection: Identifiable, Equatable {
    enum Status: Equatable {
        case connected, notConnected, comingSoon, notInLab
        var word: String {
            switch self {
            case .connected: return "Connected"; case .notConnected: return "Not connected"
            case .comingSoon: return "Coming soon"; case .notInLab: return "Not available in Lab"
            }
        }
        var symbol: String {
            switch self {
            case .connected: return "checkmark.circle.fill"; case .notConnected: return "circle"
            case .comingSoon: return "clock"; case .notInLab: return "circle.dashed"
            }
        }
    }
    enum Action: Equatable {
        case connectHealth, manageHealth, manageWatch, pairBluetooth
        var title: String {
            switch self { case .connectHealth: return "Connect"; case .manageHealth, .manageWatch: return "Manage"; case .pairBluetooth: return "Pair" }
        }
    }
    let id: String
    let name: String
    let icon: String
    let detail: String
    let status: Status
    /// More exact words than the status where they help ("2 paired"); otherwise nil.
    var note: String? = nil
    var action: Action? = nil
}

enum OnbConnections {
    static let order = ["health", "watch", "whoop", "garmin", "bluetooth"]
    /// What the redesigned main app knows, read from the existing connection services (nothing is requested by reading).
    struct Live: Equatable {
        var healthAvailable = false, healthConnected = false
        var watchConnected = false
        var bluetoothPaired = 0
    }
    /// `live == nil` is Cyclift Lab: no service is consulted and no action exists.
    static func rows(live: Live?) -> [OnbConnection] {
        let lab = live == nil
        let l = live ?? Live()
        return [
            OnbConnection(id: "health", name: "Apple Health", icon: "heart", detail: "Connect your health and activity data",
                          status: lab ? .notInLab : l.healthConnected ? .connected : .notConnected,
                          note: !lab && !l.healthAvailable ? "Not available on this device" : nil,
                          action: lab || !l.healthAvailable ? nil : l.healthConnected ? .manageHealth : .connectHealth),
            OnbConnection(id: "watch", name: "Apple Watch", icon: "applewatch", detail: "Connect your Apple Watch",
                          status: lab ? .notInLab : l.watchConnected ? .connected : .notConnected, action: lab ? nil : .manageWatch),
            // no WHOOP or Garmin integration exists in the app: said so, with no button
            OnbConnection(id: "whoop", name: "WHOOP", icon: "waveform.path.ecg", detail: "Connect your WHOOP", status: .comingSoon),
            OnbConnection(id: "garmin", name: "Garmin", icon: "arrow.triangle.2.circlepath", detail: "Connect your Garmin", status: .comingSoon),
            OnbConnection(id: "bluetooth", name: "Bluetooth devices", icon: "dot.radiowaves.left.and.right", detail: "Connect your sensors and devices",
                          status: lab ? .notInLab : l.bluetoothPaired > 0 ? .connected : .notConnected,
                          note: !lab && l.bluetoothPaired > 0 ? "\(l.bluetoothPaired) paired" : nil, action: lab ? nil : .pairBluetooth),
        ]
    }
    /// The Plan changes starting point for a NEW athlete in the redesigned onboarding: explicit approval before changes
    /// ("Always ask me") — applied once, when the redesigned onboarding opens for an athlete who has not finished it.
    /// The choice itself is NOT on any onboarding page (owner, 22 Nov 2026, 16:34): it lives in Profile › App
    /// preferences › Coach. An athlete for whom it was already applied, or who finished onboarding under an earlier
    /// version, keeps the stored value untouched.
    static func startingPlanChanges(asked: Bool?, onboarded: Bool, current: Bool) -> (autoAdapt: Bool, asked: Bool?) {
        guard asked != true, !onboarded else { return (current, asked) }
        return (false, true)
    }
}

// MARK: - Onboarding › Athlete Evolution (owner's approved direction, 22 Nov 2026, 17:33)
//
// Six stages, G0–G5, that the athlete can EXPLORE on the page: tapping one shows its orbital form, its name and a short
// description. Exploring is presentation only — it is never stored and never becomes the athlete's stage.
//
// Three statuses are kept apart and must never be confused:
//   · Exploring — the stage being looked at on the rail.
//   · Estimated — from onboarding answers, labelled "Estimated · based on your answers".
//   · Verified  — from approved performance criteria and actual recorded evidence.
// No assessment method is approved yet, so the athlete's actual standing is always `.notAssessed` ("Starting stage not
// yet assessed"). `estimated` and `verified` exist so the design can show them once a policy is approved; nothing in
// the app produces them today. The names and descriptions are PROVISIONAL working labels, not assessment criteria.

struct EvolutionStageInfo: Equatable, Identifiable {
    let index: Int
    let name: String
    let summary: String
    var id: Int { index }
    var code: String { "G\(index)" }
}

enum EvolutionStages {
    static let all: [EvolutionStageInfo] = [
        .init(index: 0, name: "Origin", summary: "Where every athlete begins: first sessions and a new routine."),
        .init(index: 1, name: "Foundation", summary: "Regular training and sound basics taking hold."),
        .init(index: 2, name: "Development", summary: "Consistent weeks and steady, visible progress."),
        .init(index: 3, name: "Performance", summary: "Structured training that shows in results."),
        .init(index: 4, name: "Refinement", summary: "Well-balanced training, tuned in its details."),
        .init(index: 5, name: "Mastery", summary: "Excellence sustained across seasons."),
    ]
    static func stage(_ i: Int) -> EvolutionStageInfo? { all.indices.contains(i) ? all[i] : nil }
}

enum EvolutionStanding: Equatable {
    case notAssessed
    case estimated(Int)
    case verified(Int)
    var title: String {
        switch self {
        case .notAssessed: return "Starting stage not yet assessed"
        case .estimated(let i): return EvolutionStages.stage(i).map { "\($0.code) · \($0.name)" } ?? "Starting stage not yet assessed"
        case .verified(let i): return EvolutionStages.stage(i).map { "\($0.code) · \($0.name)" } ?? "Starting stage not yet assessed"
        }
    }
    /// The label that tells an estimate from a verified stage. nil when there is no stage to label.
    var basis: String? {
        switch self {
        case .notAssessed: return nil
        case .estimated: return "Estimated · based on your answers"
        case .verified: return "Verified · from your recorded training"
        }
    }
    /// The stage the athlete actually holds, if any — never the one being explored.
    var stage: Int? { switch self { case .notAssessed: return nil; case .estimated(let i), .verified(let i): return i } }
}

enum EvolutionPage {
    /// The athlete's actual standing. No assessment policy is approved, so it is not assessed — whatever was answered,
    /// recorded or tapped. (When a policy is approved, this is the one place it is applied.)
    static func standing() -> EvolutionStanding { .notAssessed }

    /// What the athlete declared, sport by sport, from THEIR roster: "Cycling · Intermediate", "Strength · Beginner",
    /// and — for a sport whose experience onboarding does not ask yet — "Running · experience not asked yet". Nothing
    /// is assumed for a sport.
    static func declared(roster ids: [String], cyclingLevel: String?, strengthLevel: String?) -> [String] {
        var seen: [RosterFamily] = [], out: [String] = []
        for a in ids.compactMap({ AthleticRoster.activity($0) }) where !seen.contains(a.family) {
            seen.append(a.family)
            let level: String? = a.family == .cycling ? cyclingLevel : a.family == .strength ? strengthLevel : nil
            out.append("\(a.family.title) · \(level ?? "experience not asked yet")")
        }
        return out
    }
    /// The evidence line: what is actually recorded, and — truthfully — which of the athlete's sports cannot be
    /// recorded yet. Nothing is invented for a sport without a recorder.
    static func evidence(roster ids: [String], rides: Int, lifts: Int) -> (title: String, note: String) {
        let acts = ids.compactMap { AthleticRoster.activity($0) }
        var parts: [String] = []
        if rides > 0 { parts.append("\(rides) ride\(rides == 1 ? "" : "s")") }
        if lifts > 0 { parts.append("\(lifts) strength session\(lifts == 1 ? "" : "s")") }
        let title = parts.isEmpty ? "Nothing recorded yet" : parts.joined(separator: " · ")
        var waiting: [String] = []
        for a in acts where a.recording == nil && !waiting.contains(a.family.title) { waiting.append(a.family.title) }
        let canRecord = acts.isEmpty || acts.contains { $0.recording != nil }
        if !canRecord { return (title, "Recording for your sports is coming soon.") }
        return (title, waiting.isEmpty ? "Your recorded sessions will count." : "Recorded sessions will count. \(waiting.joined(separator: ", ")): recording coming soon.")
    }
}

// MARK: - Profile › Devices & Connections (sheet P06): one row per device family, state in a word and a shape

/// The six connection states of sheet P06. Told apart by word and symbol, never by colour.
enum ProfileConnection: String, CaseIterable, Equatable {
    case receiving, connected, paired, disconnected, unavailable, notConfigured
    var word: String {
        switch self {
        case .receiving: return "Receiving"; case .connected: return "Connected"; case .paired: return "Paired"
        case .disconnected: return "Disconnected"; case .unavailable: return "Unavailable"; case .notConfigured: return "Not configured"
        }
    }
    var symbol: String {
        switch self {
        case .receiving: return "dot.radiowaves.left.and.right"; case .connected: return "circle.fill"; case .paired: return "circle"
        case .disconnected: return "circle.slash"; case .unavailable: return "circle.dashed"; case .notConfigured: return "plus"
        }
    }
    /// Best first: used to show one state for a family of several sensors.
    var rank: Int { switch self { case .receiving: return 5; case .connected: return 4; case .paired: return 3; case .disconnected: return 2; case .unavailable: return 1; case .notConfigured: return 0 } }
}

struct ProfileDeviceRow: Identifiable, Equatable {
    /// The redesigned page a row opens (Shell/CyProfileDevices.swift). `.nothing` = a stated limit, opens nothing.
    enum Opens: Equatable { case health, watch, board, sensors, phone, diagnostics, nothing }
    var id: String
    var title: String
    var summary: String
    var state: ProfileConnection?
    var opens: Opens
}

/// Which of the three sensor rows of sheet P06 a sensor paired with this phone belongs to — the same order of
/// precedence as its icon on the existing devices screen (a power meter also reports cadence; it is a power meter).
enum ProfileSensorFamily: String, CaseIterable, Equatable {
    case hr, power, other
    var title: String { switch self { case .hr: return "Heart-rate sensors"; case .power: return "Power meters"; case .other: return "Other sensors" } }
    var purpose: String {
        switch self {
        case .hr: return "Straps and bands that send heart rate to this iPhone."
        case .power: return "Meters that send power and cadence to this iPhone."
        case .other: return "Speed and cadence sensors paired with this iPhone."
        }
    }
    static func of(hasHR: Bool, hasPower: Bool) -> ProfileSensorFamily { hasPower ? .power : hasHR ? .hr : .other }
}

/// "This iPhone" (sheet P06) and Permissions (sheet P08 F2): each permission in one plain word, from the real state.
enum ProfilePhoneWords {
    enum Notifications: Equatable { case allowed, notAllowed, notAsked, unknown }
    static let labNote = "Not used in Cyclift Lab"
    static func bluetooth(off: Bool, unauthorized: Bool, unsupported: Bool) -> String {
        unsupported ? "Not available" : unauthorized ? "Not allowed" : off ? "Off" : "On"
    }
    static func location(authorized: Bool, denied: Bool) -> String { authorized ? "Allowed" : denied ? "Not allowed" : "Not asked yet" }
    static func notifications(_ n: Notifications) -> String {
        switch n { case .allowed: return "Allowed"; case .notAllowed: return "Not allowed"; case .notAsked: return "Not asked yet"; case .unknown: return "Checking…" }
    }
    static func health(available: Bool, writeAuthorized: Bool, wanted: Bool) -> String {
        !available ? "Not available" : writeAuthorized ? "On" : wanted ? "Not allowed" : "Off"
    }
    /// The row's one summary line, e.g. "Bluetooth on · location allowed".
    static func summary(bluetooth: String, location: String) -> String { "Bluetooth \(bluetooth.lowercased()) · location \(location.lowercased())" }
}

enum ProfileDeviceRows {
    /// The link's real state in the sheet's six words. A problem caused by Bluetooth or a permission being off is
    /// "Unavailable" (it cannot be used until that changes); any other problem is "Disconnected" (the link was lost).
    static func connection(_ s: DeviceState, usable: Bool = true) -> ProfileConnection {
        guard usable else { return .unavailable }
        switch s {
        case .notPaired: return .notConfigured
        case .paired: return .paired
        case .connected, .stale: return .connected
        case .receivingData: return .receiving
        case .problem(let reason):
            let r = reason.lowercased()
            return ["bluetooth is off", "permission", "not allowed", "denied", "not available"].contains { r.contains($0) } ? .unavailable : .disconnected
        }
    }

    /// One row per family, from the same cards the existing devices screen is built from (DeviceCards.build).
    static func build(cards: [DeviceCardModel], healthAvailable: Bool, cycling: Bool) -> [ProfileDeviceRow] {
        func card(_ id: String) -> DeviceCardModel? { cards.first { $0.id == id } }
        func line(_ c: DeviceCardModel) -> String {
            if case .problem(let reason) = c.state { return reason }
            if case .stale = c.state { return "No recent data" }
            return c.detail.isEmpty ? c.provides : c.detail.prefix(1).uppercased() + c.detail.dropFirst()
        }
        var out: [ProfileDeviceRow] = []
        if let h = card(DeviceCards.healthId) {
            out.append(ProfileDeviceRow(id: "health", title: "Apple Health", summary: healthAvailable ? line(h) : "Not available on this device",
                                        state: connection(h.state, usable: healthAvailable), opens: .health))
        }
        if let w = card(DeviceCards.watchId) { out.append(ProfileDeviceRow(id: "watch", title: "Apple Watch", summary: line(w), state: connection(w.state), opens: .watch)) }
        if cycling, let b = card(DeviceCards.boardId) { out.append(ProfileDeviceRow(id: "board", title: "Cyclift BikeComputer", summary: line(b), state: connection(b.state), opens: .board)) }
        out.append(ProfileDeviceRow(id: "cywatch", title: "Cyclift Watch", summary: "A future device", state: .unavailable, opens: .nothing))
        if cycling {
            func family(_ id: String, _ title: String, _ image: String, _ empty: String) -> ProfileDeviceRow {
                let own = cards.filter { $0.systemImage == image && !$0.id.hasPrefix("add.") }
                guard let best = own.max(by: { connection($0.state).rank < connection($1.state).rank }) else {
                    return ProfileDeviceRow(id: id, title: title, summary: empty, state: .notConfigured, opens: .sensors)
                }
                return ProfileDeviceRow(id: id, title: title, summary: own.map(\.name).joined(separator: ", "), state: connection(best.state), opens: .sensors)
            }
            out.append(family("hr", "Heart-rate sensors", "heart.fill", "Add a sensor"))
            out.append(family("power", "Power meters", "bolt.fill", "Add a meter"))
            out.append(family("other", "Other sensors", "gauge.with.dots.needle.33percent", "Speed · cadence"))
        }
        out.append(ProfileDeviceRow(id: "diagnostics", title: "Connection diagnostics", summary: "What is arriving right now", state: nil, opens: .diagnostics))
        return out
    }

    /// The page's rows with "This iPhone" in the sheet's place: after the sensors, before Connection diagnostics.
    static func withPhone(_ rows: [ProfileDeviceRow], summary: String) -> [ProfileDeviceRow] {
        var out = rows
        let phone = ProfileDeviceRow(id: "phone", title: "This iPhone", summary: summary, state: nil, opens: .phone)
        if let i = out.firstIndex(where: { $0.id == "diagnostics" }) { out.insert(phone, at: i) } else { out.append(phone) }
        return out
    }

    /// Cyclift Lab: the same rows, every one Unavailable — Lab connects to nothing and asks for no permission.
    /// Each row still opens its page so the page can be looked at; the page says the same thing and offers no action.
    static func lab(cycling: Bool) -> [ProfileDeviceRow] {
        let off = "Switched off in Cyclift Lab"
        var out = [ProfileDeviceRow(id: "health", title: "Apple Health", summary: off, state: .unavailable, opens: .health),
                   ProfileDeviceRow(id: "watch", title: "Apple Watch", summary: off, state: .unavailable, opens: .watch)]
        if cycling { out.append(ProfileDeviceRow(id: "board", title: "Cyclift BikeComputer", summary: off, state: .unavailable, opens: .board)) }
        out.append(ProfileDeviceRow(id: "cywatch", title: "Cyclift Watch", summary: "A future device", state: .unavailable, opens: .nothing))
        if cycling { for f in ProfileSensorFamily.allCases { out.append(ProfileDeviceRow(id: f.rawValue, title: f.title, summary: off, state: .unavailable, opens: .sensors)) } }
        out.append(ProfileDeviceRow(id: "phone", title: "This iPhone", summary: "Bluetooth and location are not used in Cyclift Lab", state: nil, opens: .phone))
        return out
    }
}


// MARK: - Body measurements (About you, Profile › Personal details)
//
// Owner decision, 20 Nov 2026 (Screen 2): the athlete may give height as well as weight; BMI is weight in kilograms
// divided by height in metres squared. It is a description only: it is never a body-fat figure and never an input to
// training load. Nothing here is estimated: a missing or out-of-range measurement gives no BMI at all.
// Stored units: kilograms (Double, one decimal) and whole centimetres (Int) — `RiderProfile.weightKg` / `.heightCm`.
enum BodyMeasure {
    /// Heights accepted from the athlete. Outside it the entry is treated as not given (same rule as weight, 30–200 kg).
    static let heightRangeCm: ClosedRange<Int> = 120...230
    static let weightRangeKg: ClosedRange<Double> = 30...200
    static let cmPerInch = 2.54

    static let lbPerKg = 2.20462
    /// A typed weight in the shown unit → kilograms to one decimal within 30–200 kg; anything else = not given.
    /// (The rule the app already had in the editors; they now call this one.)
    static func parseWeightKg(_ s: String, imperial: Bool) -> Double? {
        guard let v = Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")) else { return nil }
        let kg = imperial ? v / lbPerKg : v
        return weightRangeKg.contains(kg) ? (kg * 10).rounded() / 10 : nil
    }
    /// A typed height in centimetres ("178", "178.4", "178,4") → whole centimetres, or nil.
    static func parseHeightCm(_ s: String) -> Int? {
        let t = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !t.isEmpty, let v = Double(t), v.isFinite else { return nil }
        let cm = Int(v.rounded())
        return heightRangeCm.contains(cm) ? cm : nil
    }
    /// Typed feet and inches → whole centimetres, or nil. Feet are required; blank inches mean 0; inches must be 0…11.
    static func heightCm(feet: String, inches: String) -> Int? {
        let f = feet.trimmingCharacters(in: .whitespaces), i = inches.trimmingCharacters(in: .whitespaces)
        guard let ft = Int(f), ft >= 0 else { return nil }
        let inch: Int
        if i.isEmpty { inch = 0 } else { guard let v = Int(i), (0...11).contains(v) else { return nil }; inch = v }
        let cm = Int((Double(ft * 12 + inch) * cmPerInch).rounded())
        return heightRangeCm.contains(cm) ? cm : nil
    }
    /// Whole centimetres → feet and inches (nearest inch).
    static func feetInches(_ cm: Int) -> (feet: Int, inches: Int) {
        let total = Int((Double(cm) / cmPerInch).rounded())
        return (total / 12, total % 12)
    }
    /// "178 cm" or "5 ft 10 in".
    static func heightText(_ cm: Int, imperial: Bool) -> String {
        if imperial { let x = feetInches(cm); return "\(x.feet) ft \(x.inches) in" }
        return "\(cm) cm"
    }
    /// BMI = kg / m², to one decimal. nil unless BOTH measurements are present and inside their accepted ranges.
    static func bmi(weightKg: Double?, heightCm: Int?) -> Double? {
        guard let w = weightKg, let h = heightCm, weightRangeKg.contains(w), heightRangeCm.contains(h) else { return nil }
        let m = Double(h) / 100
        return (w / (m * m) * 10).rounded() / 10
    }

    // About you for a NEW athlete (owner decision 20 Nov 2026, 18:24): first name, date of birth, weight and height are
    // all required before Continue. This is only the onboarding rule: an existing athlete's record is never rejected or
    // rewritten because a measurement is missing, and Profile keeps accepting a blank height.
    static func aboutYouComplete(name: String?, dateOfBirth: Date?, weightKg: Double?, heightCm: Int?) -> Bool {
        aboutYouPrompt(name: name, dateOfBirth: dateOfBirth, weightKg: weightKg, heightCm: heightCm) == nil
    }
    /// One sentence naming what is still needed, or nil when all four are there and valid.
    static func aboutYouPrompt(name: String?, dateOfBirth: Date?, weightKg: Double?, heightCm: Int?) -> String? {
        var need: [String] = []
        if (name ?? "").trimmingCharacters(in: .whitespaces).isEmpty { need.append("first name") }
        if dateOfBirth == nil { need.append("date of birth") }
        if !(weightKg.map { weightRangeKg.contains($0) } ?? false) { need.append("weight") }
        if !(heightCm.map { heightRangeCm.contains($0) } ?? false) { need.append("height") }
        guard !need.isEmpty else { return nil }
        let list = need.count == 1 ? need[0] : need.dropLast().joined(separator: ", ") + " and " + need[need.count - 1]
        return "Add your \(list) to continue."
    }
    /// Why a typed weight is not accepted, in the unit shown; nil when it is blank or valid.
    static func weightIssue(_ text: String, imperial: Bool) -> String? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, parseWeightKg(text, imperial: imperial) == nil else { return nil }
        return imperial ? "Weight must be between 67 and 440 lb." : "Weight must be between 30 and 200 kg."
    }
    /// Why a typed height is not accepted, in the unit shown; nil when it is blank or valid.
    static func heightIssue(cm text: String) -> String? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, parseHeightCm(text) == nil else { return nil }
        return "Height must be between 120 and 230 cm."
    }
    static func heightIssue(feet: String, inches: String) -> String? {
        let blank = feet.trimmingCharacters(in: .whitespaces).isEmpty && inches.trimmingCharacters(in: .whitespaces).isEmpty
        guard !blank, heightCm(feet: feet, inches: inches) == nil else { return nil }
        return "Height must be between 4 ft 0 in and 7 ft 6 in, with inches from 0 to 11."
    }

    // Date of birth typed as day, month and year (Gregorian, whatever calendar the iPhone is set to).
    enum BirthIssue: Equatable { case incomplete, notADate, future, tooYoung, tooOld
        var text: String {
            switch self {
            case .incomplete: return "Enter day, month and a four-digit year."
            case .notADate: return "That date does not exist."
            case .future: return "A date of birth cannot be in the future."
            case .tooYoung: return "Cyclift is for athletes aged 13 and over."
            case .tooOld: return "Please check the year."
            }
        }
    }
    enum BirthEntry: Equatable { case date(Date), issue(BirthIssue) }
    static let minAge = 13, maxAge = 100
    static var gregorian: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone.current; return c }
    /// Validates the three typed parts: a real calendar date (leap years included), not in the future, age 13–100 —
    /// the same limits the earlier date wheel had.
    static func birthDate(day: String, month: String, year: String, now: Date = Date()) -> BirthEntry {
        let ds = day.trimmingCharacters(in: .whitespaces), ms = month.trimmingCharacters(in: .whitespaces), ys = year.trimmingCharacters(in: .whitespaces)
        guard let d = Int(ds), let m = Int(ms), let y = Int(ys), ys.count == 4 else { return .issue(.incomplete) }
        let cal = gregorian
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = 12
        guard (1...12).contains(m), (1...31).contains(d), let date = cal.date(from: c) else { return .issue(.notADate) }
        let back = cal.dateComponents([.year, .month, .day], from: date)
        guard back.year == y, back.month == m, back.day == d else { return .issue(.notADate) }      // 31 Apr, 29 Feb in a common year
        if date > now { return .issue(.future) }
        let age = cal.dateComponents([.year], from: date, to: now).year ?? 0
        if age < minAge { return .issue(.tooYoung) }
        if age > maxAge { return .issue(.tooOld) }
        return .date(date)
    }
    /// The three parts of a stored date, for showing it again in the entry sheet.
    static func birthParts(_ date: Date) -> (day: String, month: String, year: String) {
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return (String(c.day ?? 0), String(c.month ?? 0), String(c.year ?? 0))
    }
}


// MARK: - What onboarding writes (kept free of the interface so it is tested without it)

enum OnboardingOutcome {
    /// Writes the answers into the one athlete record through the same inputs the planner reads.
    static func commit(_ a: OnboardingAnswers, to store: Store) {
        var x = store.planInputs
        a.apply(to: &x)
        store.updateProfile { $0 = x.profile }
        if store.availability != x.availability { store.availability = x.availability }
        if store.equipment != x.equipment { store.equipment = x.equipment }
        if store.strengthPrefs != x.strengthPrefs { store.strengthPrefs = x.strengthPrefs }
    }

    /// The planner on the inputs Approve will save — nothing persisted. (Moved here unchanged from OnboardingFlow so
    /// the logic tests can run it.)
    static func dryRun(_ a: OnboardingAnswers, store: Store, kinds: [DayKind], ride: Int, lift: Int, weekOffset: Int) -> [Workout] {
        var x = store.planInputs
        var draft = a; draft.week = kinds; draft.rideMinutes = ride; draft.liftMinutes = lift
        draft.apply(to: &x)
        guard let av = x.availability else { return [] }
        let cal = Calendar.current
        let d0 = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: d0) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd + 7 * weekOffset, to: d0) ?? d0
        return PlanEngine.week(starting: monday, profile: x.profile, availability: av)
    }
    static func storedSchedule(_ store: Store) -> [[ChosenSession]]? {
        let p = store.profile
        if let w = p.chosenWeek { return ChosenWeek.normalised(w) }
        guard p.weekIsExplicit == true else { return nil }
        return ChosenWeek.from(store.availability, roster: AthleticRoster.roster(of: p))
    }

    /// The profile-only outcome (owner decision 21 Nov 2026): the athlete's profile, sports, goals and preferences are
    /// saved and they enter Cyclift WITHOUT a training plan, because nothing they chose can be planned today. No
    /// session is generated, no plan version is recorded, and no cycling or strength goal or type is assigned: the
    /// stored goals are exactly the ones chosen, and the marker keeps the planner from ever filling the calendar.
    static func createProfileOnly(_ a: OnboardingAnswers, store: Store) {
        var x = a
        x.week = nil; x.mode = nil; x.priority = nil; x.scheduleOnly = true      // nothing plan-shaped is written; the chosen schedule itself is saved
        commit(x, to: store)
        store.updateProfile { $0.profileOnly = true }
        store.onboardingStage = 0
        store.dropUnapprovedPlan()                               // placeholders from before set-up never become a plan, on any date
        store.onboarded = true
    }
}

// MARK: - The training mix of a proposed week (Goals page summary card)
//
// Owner decision, 21 Nov 2026 (13:38): the main-goal card shows a segmented training-mix bar and its legend, and the
// bar "must reflect the athlete's selected sports and actual proposed training distribution" — nothing hardcoded,
// nothing invented. So the shares are COUNTED from a week the real planner produced for this athlete's answers (the
// same dry run the Blueprint shows); `GoalInfo.emphasis`, a fixed table per goal, is not used for it. No planned
// session in the week = no shares = no bar.
enum TrainingMix {
    enum Part: String, CaseIterable {
        case easyRiding, hardRiding, strength, other, rest
        var title: String {
            switch self {
            case .easyRiding: return "Easy riding"
            case .hardRiding: return "Hard riding"
            case .strength: return "Strength"
            case .other: return "Other"
            case .rest: return "Rest"
            }
        }
    }
    struct Share: Equatable { let part: Part; let count: Int }

    static func part(of k: WorkoutKind) -> Part? {
        switch k {
        case .rest, .recoveryDay: return nil
        case .strength: return .strength
        case .mobility, .other: return .other
        default: return k.zone >= 3 ? .hardRiding : .easyRiding       // rides: zone 3 and above is hard (as Workout.isHard)
        }
    }
    /// Sessions of each kind in one planned week, then the days of the seven with no session. Empty when nothing is planned.
    static func shares(of week: [Workout], calendar cal: Calendar = .current) -> [Share] {
        var n: [Part: Int] = [:]
        var days = Set<Date>()
        for w in week {
            guard let p = part(of: w.kind) else { continue }
            n[p, default: 0] += 1
            days.insert(cal.startOfDay(for: w.date))
        }
        guard !days.isEmpty else { return [] }
        n[.rest] = max(0, 7 - days.count)
        return Part.allCases.compactMap { p in (n[p] ?? 0) > 0 ? Share(part: p, count: n[p] ?? 0) : nil }
    }
    /// "Easy riding 2, Hard riding 1, Strength 3, Rest 2" — what VoiceOver and the checks read.
    static func summary(_ s: [Share]) -> String { s.map { "\($0.part.title) \($0.count)" }.joined(separator: ", ") }
}
