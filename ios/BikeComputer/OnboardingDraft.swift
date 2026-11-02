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
    static let defaultRideMinutes = 60
    static let defaultLiftMinutes = 30
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
    // Stage B
    var goals: [GoalID]? = nil
    var primaryGoal: GoalID? = nil
    // Stage C
    var week: [DayKind]? = nil
    var rideMinutes: Int? = nil
    var liftMinutes: Int? = nil
    var equipment: EquipmentPreset? = nil
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
        if let l = cyclingLevel { x.profile.level = l }
        if let s = strengthLevel { x.strengthPrefs.experience = s; x.profile.confirmStrengthLevel = nil }
        // re-applying the same value never re-dates it (resume and keystrokes call this repeatedly)
        if let d = dateOfBirth, d != x.profile.dateOfBirth || x.profile.provenance(.dateOfBirth).source != .entered { x.profile.setDateOfBirth(d, at: now) }
        if let w = weightKg, w != x.profile.weightKg || x.profile.provenance(.weight).source != .entered { x.profile.setWeight(w, source: .entered, at: now) }
        if let g = goals, !g.isEmpty {
            x.profile.goals = g
            x.profile.primaryGoal = (primaryGoal.flatMap { g.contains($0) ? $0 : nil }) ?? g.first
            if let c = (x.profile.primaryGoal?.cyclingGoal ?? g.compactMap(\.cyclingGoal).first) { x.profile.goal = c }
            if let s = (x.profile.primaryGoal?.strengthGoal ?? g.compactMap(\.strengthGoal).first) { x.strengthPrefs.goal = s }
        }
        if let w = week {
            OnboardingWeek.write(w, ride: rideMinutes ?? x.profile.cyclingSessionMinutes ?? OnboardingWeek.defaultRideMinutes,
                                 lift: liftMinutes ?? x.profile.strengthSessionMinutes ?? OnboardingWeek.defaultLiftMinutes, into: &x)
        } else {
            if let r = rideMinutes { x.profile.cyclingSessionMinutes = r }
            if let l = liftMinutes { x.profile.strengthSessionMinutes = l; x.profile.confirmSessionLength = nil }
        }
        if let e = equipment { x.equipment = e.apply(to: x.equipment) }
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
