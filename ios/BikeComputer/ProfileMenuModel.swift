import Foundation

// MARK: - Checkpoint C correction pass (owner 6 Nov addendum): the Profile Quick Menu's facts.
// Read-only views of values the app already stores (profile, strength preferences, availability, equipment, settings,
// device states). Computing them never writes: no plan, preference or setting changes by opening the menu or its pages.
// Editing always goes to the existing editors, whose plan-affecting changes end in the preview → approve → undo flow.

struct ProfileFact: Equatable, Identifiable {
    enum Edit: String, Equatable { case personal, typeExperience, goals, week, equipment, preferences, strengthProgramming, ftp, heartRate }
    var title: String
    var value: String
    var note: String? = nil            // source / read-only remark, e.g. "Apple Health · 3 Nov", "no editor yet"
    var edit: Edit? = nil              // the existing editor that changes it (nil = read-only here)
    var id: String { title }
}
struct ProfileFactSection: Equatable, Identifiable {
    var title: String
    var facts: [ProfileFact]
    var id: String { title }
}

struct ProfileMenuHeader: Equatable {
    var initials: String               // "R" / "RA"; "" when no name is stored (the view shows a person glyph)
    var name: String?                  // nil = no name stored (never a placeholder presented as real)
    var athleteType: String            // "Hybrid · balanced" / "Cycling" / "Strength"
}

enum ProfileMenuModel {
    static func initials(_ name: String) -> String {
        let p = name.split(separator: " ").filter { !$0.isEmpty }
        return p.prefix(2).map { String($0.prefix(1)).uppercased() }.joined()
    }
    static func age(_ dob: Date, now: Date, calendar cal: Calendar = .current) -> Int {
        cal.dateComponents([.year], from: dob, to: now).year ?? 0
    }
    static func supersetText(_ v: Bool?) -> String {
        switch v {
        case true?: return "On — paired when the exercises allow it"
        case false?: return "Off"
        case nil: return "Not set — no supersets"
        }
    }
    static func height(_ cm: Int?, units: AppSettings.Units) -> String {
        guard let cm, cm > 0 else { return "Not recorded" }
        if units == .imperial { let inches = Int((Double(cm) / 2.54).rounded()); return "\(inches / 12) ft \(inches % 12) in" }
        return "\(cm) cm"
    }
    static func sourceNote(_ p: ValueProvenance) -> String? {
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy"   // Foundation-only formatting (the harness has no .formatted)
        let when = p.recordedAt.map { " · \(f.string(from: $0))" } ?? ""
        switch p.source {
        case .unknown: return nil
        case .appleHealth: return "Apple Health\(when)"
        case .legacyUnverified: return "From an earlier version — please confirm"
        default: return "Entered by you\(when)"
        }
    }
}

extension Store {
    func profileMenuHeader() -> ProfileMenuHeader {
        let p = profile
        let n = p.name.trimmingCharacters(in: .whitespaces)
        let type = p.trainingMode == .hybrid ? "Hybrid · \(p.priority.title.lowercased())" : ProfileText.mode(p.trainingMode)
        return ProfileMenuHeader(initials: ProfileMenuModel.initials(n), name: n.isEmpty ? nil : n, athleteType: type)
    }

    /// My Profile: the stored personal and athlete facts.
    func profileMyFacts(now: Date = Date()) -> [ProfileFactSection] {
        let p = profile
        var personal: [ProfileFact] = []
        let n = p.name.trimmingCharacters(in: .whitespaces)
        personal.append(ProfileFact(title: "Name", value: n.isEmpty ? "Not set" : n, edit: .personal))
        if let dob = p.dateOfBirth {
            personal.append(ProfileFact(title: "Age", value: "\(ProfileMenuModel.age(dob, now: now))", note: ProfileMenuModel.sourceNote(p.provenance(.dateOfBirth)), edit: .personal))
        } else { personal.append(ProfileFact(title: "Age", value: "Not set", note: "needed for heart-rate zones", edit: .personal)) }
        personal.append(ProfileFact(title: "Height", value: ProfileMenuModel.height(p.heightCm, units: settings.units), note: "read-only — no editor in this version"))
        let wKnown = p.provenance(.weight).source != .unknown && p.weightKg != nil
        personal.append(ProfileFact(title: "Weight", value: wKnown && p.weightKg != nil ? WeightFmt.text(p.weightKg!, settings.units) : "Not set", note: wKnown ? ProfileMenuModel.sourceNote(p.provenance(.weight)) : "needed for loads and W/kg", edit: .personal))
        var athlete: [ProfileFact] = [ProfileFact(title: "Athlete type", value: profileMenuHeader().athleteType, edit: .typeExperience)]
        if p.trainingMode.includesCycling { athlete.append(ProfileFact(title: "Riding level", value: ProfileText.level(p.level), edit: .typeExperience)) }
        if p.trainingMode.includesLifting { athlete.append(ProfileFact(title: "Lifting experience", value: strengthPrefs.experience.map(ProfileText.strengthLevel) ?? "Not set", edit: .typeExperience)) }
        return [ProfileFactSection(title: "Personal", facts: personal), ProfileFactSection(title: "Athlete", facts: athlete)]
    }

    /// Goals & Training Preferences: the saved values in three groups.
    func profilePreferenceFacts() -> [ProfileFactSection] {
        let p = profile
        // goals
        var goals: [ProfileFact] = [ProfileFact(title: "Main goal", value: p.effectivePrimaryGoal.title, edit: .goals)]
        let others = p.effectiveGoals.filter { $0 != p.effectivePrimaryGoal }.map(\.title)
        if !others.isEmpty { goals.append(ProfileFact(title: "Other goals", value: others.joined(separator: ", "), edit: .goals)) }
        if p.trainingMode.includesLifting {
            let g = plannerContext().goal
            goals.append(ProfileFact(title: "Strength goal", value: g.title, note: strengthPrefs.goal == nil ? "follows your main goal" : "set by you", edit: .strengthProgramming))
        }
        if p.trainingMode.includesCycling { goals.append(ProfileFact(title: "Cycling focus", value: p.goal.title, edit: .goals)) }
        // structure
        let days = effectiveAvailability.days
        func names(_ f: (DayAvailability) -> Bool) -> String {
            let n = days.indices.filter { f(days[$0]) }.map { WeeklyAvailability.dayNames[$0] }
            return n.isEmpty ? "none" : n.joined(separator: ", ")
        }
        var structure: [ProfileFact] = []
        if p.trainingMode.includesCycling { structure.append(ProfileFact(title: "Ride days", value: names { $0.cycles }, edit: .week)) }
        if p.trainingMode.includesLifting { structure.append(ProfileFact(title: "Lift days", value: names { $0.lifts }, edit: .week)) }
        if p.trainingMode.includesCycling { structure.append(ProfileFact(title: "Ride length", value: p.cyclingSessionMinutes.map { Fmt.duration(minutes: $0) } ?? "Coach decides", edit: .week)) }
        if p.trainingMode.includesLifting { structure.append(ProfileFact(title: "Lift length", value: p.strengthSessionMinutes.map { Fmt.duration(minutes: $0) } ?? "Coach decides", edit: .week)) }
        var freq: [String] = []
        if p.trainingMode.includesCycling { freq.append("\(p.cyclingDaysPerWeek) ride\(p.cyclingDaysPerWeek == 1 ? "" : "s")") }
        if p.trainingMode.includesLifting { freq.append("\(p.liftDaysPerWeek) lift\(p.liftDaysPerWeek == 1 ? "" : "s")") }
        structure.append(ProfileFact(title: "Sessions per week", value: freq.joined(separator: " · "), edit: .week))
        if p.trainingMode == .hybrid { structure.append(ProfileFact(title: "Strength / cycling balance", value: p.priority.title, edit: .typeExperience)) }
        if p.trainingMode.includesLifting {
            structure.append(ProfileFact(title: "Supersets", value: ProfileMenuModel.supersetText(strengthPrefs.prefersSupersets), edit: .week))
            structure.append(ProfileFact(title: "Strength split", value: p.strengthSplit?.title ?? "Coach decides", edit: .preferences))
            structure.append(ProfileFact(title: "Lifting experience", value: strengthPrefs.experience.map(ProfileText.strengthLevel) ?? "Not set", edit: .typeExperience))
        }
        if p.trainingMode.includesCycling { structure.append(ProfileFact(title: "Riding level", value: ProfileText.level(p.level), edit: .typeExperience)) }
        structure.append(ProfileFact(title: "Recovery", value: ProfileText.recovery(p.recoveryCapacity ?? .normal), edit: .preferences))
        // equipment
        var equip: [ProfileFact] = []
        if p.trainingMode.includesLifting {
            let e = equipment
            let v = e.isProvisional ? "Not sure yet" : e.owned.isEmpty ? "Bodyweight only" : EquipmentPreset.of(e) == .gym ? "Full gym" : "\(e.owned.count) items"
            equip.append(ProfileFact(title: "Gym equipment", value: v, edit: .equipment))
            let avoided = strengthPrefs.avoid.count
            equip.append(ProfileFact(title: "Avoided exercises", value: avoided == 0 ? "None" : "\(avoided)", edit: .strengthProgramming))
            if !strengthPrefs.temporary.isEmpty { equip.append(ProfileFact(title: "Temporary limits", value: "\(strengthPrefs.temporary.count)", edit: .strengthProgramming)) }
        }
        if p.trainingMode.includesCycling {
            equip.append(ProfileFact(title: "FTP", value: "\(p.ftpDisplay) · \(p.ftpSource.title)", edit: .ftp))
            equip.append(ProfileFact(title: "Heart-rate zones", value: p.maxHRForZones.map { "max \($0)\(p.maxHRIsEstimate ? " (est.)" : "")" } ?? "not set", edit: .heartRate))
            equip.append(ProfileFact(title: "Cycling devices", value: "see Devices & Connections", note: "live states are shown there"))
        }
        return [ProfileFactSection(title: "Training goals", facts: goals), ProfileFactSection(title: "Training structure", facts: structure), ProfileFactSection(title: "Equipment", facts: equip)]
    }

    /// The menu rows' one-line summaries — the same values the pages show.
    func profileMenuLines(connectedDevices: Int, healthReadsOn: Bool) -> (profile: String, preferences: String, connections: String, settings: String) {
        let h = profileMenuHeader()
        let p = profile
        var pref = [p.effectivePrimaryGoal.title]
        let days = effectiveAvailability.days.filter { $0.cycles || $0.lifts }.count
        pref.append("\(days) day\(days == 1 ? "" : "s")")
        if p.trainingMode.includesLifting { pref.append(strengthPrefs.prefersSupersets == true ? "supersets on" : "supersets off") }
        let conn = (connectedDevices == 0 ? "No device connected" : "\(connectedDevices) connected") + (healthReadsOn ? " · Health reads on" : "")
        let set = "\(settings.units == .metric ? "Metric" : "Imperial") · \(settings.appearance.title)"
        return ((h.name ?? "Name not set") + " · " + h.athleteType, pref.joined(separator: " · "), conn, set)
    }
}

enum ProfileText {
    static func mode(_ m: TrainingMode) -> String { switch m { case .cycling: return "Cycling"; case .strength: return "Strength"; case .hybrid: return "Hybrid" } }
    static func level(_ l: RiderProfile.Level) -> String { switch l { case .beginner: return "Beginner"; case .intermediate: return "Intermediate"; case .advanced: return "Advanced" } }
    static func recovery(_ r: RecoveryCapacity) -> String { switch r { case .low: return "Slow"; case .normal: return "Average"; case .high: return "Fast" } }
    static func strengthLevel(_ e: StrengthPrefs.Experience) -> String { switch e { case .beginner: return "Beginner"; case .intermediate: return "Intermediate"; case .advanced: return "Advanced" } }
    /// "Endurance" or "Endurance +1" (primary goal first).
    static func goals(_ p: RiderProfile) -> String {
        let g = p.effectiveGoals
        let first = p.effectivePrimaryGoal.title
        return g.count > 1 ? "\(first) +\(g.count - 1)" : first
    }
}
