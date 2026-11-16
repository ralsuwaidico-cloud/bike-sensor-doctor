import Foundation

// Onboarding v3.4 Page 2 — the Athletic Roster (ONBOARDING_V34_PAGE2_ATHLETIC_ROSTER). Pure rules over the stored
// values the app already has: `RiderProfile.sports` (the roster), `trainingMode` and `priority`. No new stored field.
//
// • The roster is the stored sports list. Its ORDER carries the main sport: the first plannable endurance sport is the
//   main endurance sport, and the strength sport is the main strength sport. ("Main-sport flag" as its own field is
//   not approved; order needs no storage change.)
// • Capability is told in words, four kinds, and decides what can be chosen and what can be main.
// • Activities the app cannot store yet are listed as "future" and cannot be selected: nothing is pretended.

enum RosterDomain: String, CaseIterable { case endurance, strength, recovery
    var title: String { switch self { case .endurance: return "Endurance"; case .strength: return "Strength"; case .recovery: return "Recovery" } }
}

enum RosterCapability: Int, CaseIterable {
    /// Cyclift plans and records it.
    case plansAndRecords
    /// Recorded with a recorder Cyclift already has (planned as cycling).
    case sharedRecorder
    /// Not supported yet — saved as an interest only.
    case interestOnly
    /// Cannot be saved yet: listed so the athlete sees it is known, never selectable.
    case future

    var mark: String { switch self { case .plansAndRecords: return "●"; case .sharedRecorder: return "◐"; case .interestOnly: return "◌"; case .future: return "○" } }
    var words: String {
        switch self {
        case .plansAndRecords: return "Cyclift plans and records"
        case .sharedRecorder: return "Planned and recorded as cycling"
        case .interestOnly: return "Not supported yet — saved as interest"
        case .future: return "Coming later — cannot be saved yet"
        }
    }
    var plannable: Bool { self == .plansAndRecords || self == .sharedRecorder }
    var selectable: Bool { self != .future }
}

struct RosterActivity: Identifiable, Equatable {
    let id: String
    let title: String
    let domain: RosterDomain
    let capability: RosterCapability
    /// The stored identifier; nil for an activity the app cannot store yet.
    let sport: RiderProfile.Sport?
}

enum AthleticRoster {
    /// Every activity the page knows, in library order. Titles follow the design ("Gym training" is the stored strength sport).
    static let library: [RosterActivity] = [
        RosterActivity(id: "roadCycling", title: "Road cycling", domain: .endurance, capability: .plansAndRecords, sport: .roadCycling),
        RosterActivity(id: "strength", title: "Gym training", domain: .strength, capability: .plansAndRecords, sport: .strength),
        RosterActivity(id: "indoorCycling", title: "Indoor cycling", domain: .endurance, capability: .sharedRecorder, sport: .indoorCycling),
        RosterActivity(id: "mountainBike", title: "Mountain bike", domain: .endurance, capability: .sharedRecorder, sport: .mountainBike),
        RosterActivity(id: "commuting", title: "Commuting", domain: .endurance, capability: .sharedRecorder, sport: .commuting),
        RosterActivity(id: "running", title: "Running", domain: .endurance, capability: .interestOnly, sport: .running),
        RosterActivity(id: "swimming", title: "Swimming", domain: .endurance, capability: .interestOnly, sport: .swimming),
        RosterActivity(id: "walking", title: "Walking", domain: .endurance, capability: .future, sport: nil),
        RosterActivity(id: "bodyweight", title: "Bodyweight training", domain: .strength, capability: .future, sport: nil),
        RosterActivity(id: "mobility", title: "Stretching & mobility", domain: .recovery, capability: .future, sport: nil),
        RosterActivity(id: "breathing", title: "Breathing", domain: .recovery, capability: .future, sport: nil),
        RosterActivity(id: "sauna", title: "Sauna & cold", domain: .recovery, capability: .future, sport: nil),
    ]
    static func activity(_ s: RiderProfile.Sport) -> RosterActivity? { library.first { $0.sport == s } }

    /// What the page shows for a roster.
    struct Page: Equatable {
        var mainEndurance: RosterActivity?
        var mainStrength: RosterActivity?
        /// Plannable sports that are not main, then interests — in roster order.
        var also: [RosterActivity]
        /// The stored training type the roster means; nil = no plannable sport yet (Continue unavailable).
        var mode: TrainingMode?
        /// Up to four activities Cyclift can plan and record that are not in the roster yet.
        var suggestions: [RosterActivity]
        var showsLead: Bool { mode == .hybrid }
        var hasOnlyUnsupported: Bool { mode == nil && !also.isEmpty }
    }

    static func view(_ sports: [RiderProfile.Sport]) -> Page {
        let acts = unique(sports).compactMap(activity)
        let endurance = acts.first { $0.domain == .endurance && $0.capability.plannable }
        let strength = acts.first { $0.domain == .strength && $0.capability.plannable }
        let also = acts.filter { $0 != endurance && $0 != strength }
        let mode: TrainingMode? = endurance != nil && strength != nil ? .hybrid : endurance != nil ? .cycling : strength != nil ? .strength : nil
        let chosen = Set(acts.map(\.id))
        // other domain first, then the shared-recorder sports (design §10.3)
        let pool = library.filter { $0.capability.plannable && !chosen.contains($0.id) }
        let missingDomainFirst = pool.sorted { a, b in
            func rank(_ x: RosterActivity) -> Int {
                let domainMissing = (x.domain == .endurance && endurance == nil) || (x.domain == .strength && strength == nil)
                return (domainMissing ? 0 : 2) + (x.capability == .plansAndRecords ? 0 : 1)
            }
            return rank(a) < rank(b)
        }
        return Page(mainEndurance: endurance, mainStrength: strength, also: also, mode: mode, suggestions: Array(missingDomainFirst.prefix(4)))
    }

    static func unique(_ sports: [RiderProfile.Sport]) -> [RiderProfile.Sport] {
        var seen = Set<RiderProfile.Sport>(); return sports.filter { seen.insert($0).inserted }
    }

    static func adding(_ s: RiderProfile.Sport, to sports: [RiderProfile.Sport]) -> [RiderProfile.Sport] {
        guard let a = activity(s), a.capability.selectable, !sports.contains(s) else { return unique(sports) }
        return unique(sports) + [s]
    }
    static func removing(_ s: RiderProfile.Sport, from sports: [RiderProfile.Sport]) -> [RiderProfile.Sport] { unique(sports).filter { $0 != s } }

    /// "Make main": the sport moves to the front of the roster, so it is the first plannable sport of its domain.
    /// A sport Cyclift cannot plan is never made main (the roster is returned unchanged).
    static func makingMain(_ s: RiderProfile.Sport, in sports: [RiderProfile.Sport]) -> [RiderProfile.Sport] {
        guard let a = activity(s), a.capability.plannable, sports.contains(s) else { return unique(sports) }
        return [s] + unique(sports).filter { $0 != s }
    }

    /// The stored priority for a roster: only a hybrid roster has a lead; a single-domain roster follows its domain.
    static func priority(for mode: TrainingMode?, chosen: TrainingPriority?) -> TrainingPriority? {
        switch mode {
        case .hybrid?: return chosen ?? .balanced
        case .cycling?: return .cycling
        case .strength?: return .strength
        case nil: return nil
        }
    }

    /// "Road cycling + Gym training · balanced" — the identity line (led sport first; Balanced keeps endurance first).
    static func identityLine(_ sports: [RiderProfile.Sport], priority: TrainingPriority?) -> String {
        let v = view(sports)
        switch (v.mainEndurance, v.mainStrength) {
        case let (e?, s?):
            let p = priority ?? .balanced
            let lead = p == .strength ? "strength-led" : p == .cycling ? "endurance-led" : "balanced"
            return p == .strength ? "\(s.title) + \(e.title) · \(lead)" : "\(e.title) + \(s.title) · \(lead)"
        case let (e?, nil): return e.title
        case let (nil, s?): return s.title
        default: return "No planned sport yet"
        }
    }
}
