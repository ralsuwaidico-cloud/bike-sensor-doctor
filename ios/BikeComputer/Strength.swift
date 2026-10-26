import Foundation

// MARK: - Exercise catalogue (0.7.0). Built-in list in Resources/exercises.json plus the rider's own exercises.
// The movement pattern of a logged exercise is the ONLY source of "coverage" (squat / hinge / single-leg / core /
// push / pull); a session label such as "Full body" never becomes coverage.

enum MovementPattern: String, Codable, CaseIterable {
    case squat, hinge, push, pull, singleLeg, core, carry, other
    var title: String { switch self { case .squat: return "Squat"; case .hinge: return "Hinge"; case .push: return "Push"; case .pull: return "Pull"; case .singleLeg: return "Single-leg"; case .core: return "Core"; case .carry: return "Carry"; case .other: return "Other" } }
    /// The patterns the coach checks for coverage (carry/other are counted but never required).
    static let coverage: [MovementPattern] = [.squat, .hinge, .singleLeg, .core, .push, .pull]
}

struct Exercise: Codable, Identifiable, Equatable, Hashable {
    var id: String
    var name: String
    var aliases: [String] = []
    var equipment: [String] = []
    var pattern: MovementPattern = .other
    var muscles: [String] = []
    var unilateral = false
    /// true for exercises the rider created (editable, removable).
    var custom = false

    init(id: String, name: String, aliases: [String] = [], equipment: [String] = [], pattern: MovementPattern = .other, muscles: [String] = [], unilateral: Bool = false, custom: Bool = false) {
        self.id = id; self.name = name; self.aliases = aliases; self.equipment = equipment; self.pattern = pattern; self.muscles = muscles; self.unilateral = unilateral; self.custom = custom
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Exercise"
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        equipment = try c.decodeIfPresent([String].self, forKey: .equipment) ?? []
        pattern = (try? c.decodeIfPresent(MovementPattern.self, forKey: .pattern)) ?? .other
        muscles = try c.decodeIfPresent([String].self, forKey: .muscles) ?? []
        unilateral = try c.decodeIfPresent(Bool.self, forKey: .unilateral) ?? false
        custom = try c.decodeIfPresent(Bool.self, forKey: .custom) ?? false
    }
    var equipmentText: String { equipment.isEmpty ? "—" : equipment.joined(separator: ", ") }
}

struct ExerciseCatalogue {
    private struct File: Decodable { var exercises: [Exercise] }
    static let builtIn: [Exercise] = {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json") ?? Bundle.main.url(forResource: "exercises", withExtension: "json", subdirectory: "Resources"),
              let d = try? Data(contentsOf: url), let f = try? JSONDecoder().decode(File.self, from: d) else { return [] }
        return f.exercises
    }()
    /// Search by name, alias, equipment, movement pattern or muscle; empty query lists everything (custom first).
    static func search(_ query: String, in all: [Exercise], pattern: MovementPattern? = nil, equipment: String? = nil) -> [Exercise] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        var r = all.filter { e in
            (pattern == nil || e.pattern == pattern!) && (equipment == nil || e.equipment.contains { $0.lowercased() == equipment!.lowercased() })
        }
        if !q.isEmpty {
            r = r.filter { e in
                e.name.lowercased().contains(q) || e.aliases.contains { $0.lowercased().contains(q) } || e.equipment.contains { $0.lowercased().contains(q) }
                    || e.pattern.title.lowercased().contains(q) || e.pattern.rawValue.lowercased().contains(q) || e.muscles.contains { $0.lowercased().contains(q) }
            }
            // name matches first, then alias/other matches
            r.sort { a, b in
                let an = a.name.lowercased().hasPrefix(q) ? 0 : a.name.lowercased().contains(q) ? 1 : 2
                let bn = b.name.lowercased().hasPrefix(q) ? 0 : b.name.lowercased().contains(q) ? 1 : 2
                return an != bn ? an < bn : (a.custom != b.custom ? a.custom : a.name < b.name)
            }
        } else { r.sort { a, b in a.custom != b.custom ? a.custom : a.name < b.name } }
        return r
    }
    static let equipmentOptions = ["bodyweight", "barbell", "dumbbell", "kettlebell", "cable", "machine", "band", "trap bar", "bench", "pull-up bar"]
}

// MARK: - Equipment the rider owns and exercises they cannot do (0.8.0)
/// Everything the coach suggests is filtered by this; a saved exercise is never swapped silently.
struct EquipmentProfile: Codable, Equatable {
    /// Owned equipment (catalogue vocabulary). Empty = not set yet → nothing is filtered out.
    var owned: Set<String> = []
    /// Exercise ids the rider cannot or does not want to perform.
    var excluded: Set<String> = []
    var isSet: Bool { !owned.isEmpty }
    enum CodingKeys: String, CodingKey { case owned, excluded }

    init(owned: Set<String> = [], excluded: Set<String> = []) { self.owned = owned; self.excluded = excluded }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        owned = Set((try? c.decodeIfPresent([String].self, forKey: .owned)) ?? [])
        excluded = Set((try? c.decodeIfPresent([String].self, forKey: .excluded)) ?? [])
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(owned.sorted(), forKey: .owned); try c.encode(excluded.sorted(), forKey: .excluded)
    }
    /// An exercise is doable when it is not excluded and (when equipment is set) every piece it needs is owned.
    /// Bodyweight exercises need nothing; "bench" is treated as owned when a dumbbell or barbell is owned and the
    /// rider did not say otherwise only if they listed it — no guessing: it must be in the list.
    func canDo(_ e: Exercise) -> Bool {
        if excluded.contains(e.id) { return false }
        return hasEquipment(for: e)
    }
    /// Equipment only (exclusions not considered): every piece the exercise needs is owned. Names are compared in the
    /// catalogue vocabulary, so "Dumbbells" or "dumbbells " written by an older build still means "dumbbell".
    func hasEquipment(for e: Exercise) -> Bool {
        guard isSet else { return true }
        let have = Set(owned.map(EquipmentProfile.normalised))
        let need = e.equipment.map(EquipmentProfile.normalised).filter { $0 != "bodyweight" }
        return need.allSatisfy { have.contains($0) }
    }
    static func normalised(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ExerciseCatalogue.equipmentOptions.contains(t) { return t }
        if t.hasSuffix("s"), ExerciseCatalogue.equipmentOptions.contains(String(t.dropLast())) { return String(t.dropLast()) }
        if t.hasSuffix("es"), ExerciseCatalogue.equipmentOptions.contains(String(t.dropLast(2))) { return String(t.dropLast(2)) }
        return t
    }
    static let allOptions: [String] = ExerciseCatalogue.equipmentOptions.filter { $0 != "bodyweight" }
}

// MARK: - Weight display (A5): storage is always kilograms; the rider's units decide what is shown and typed
enum WeightFmt {
    static let lbPerKg = 2.2046226218
    static func unit(_ u: AppSettings.Units) -> String { u == .imperial ? "lb" : "kg" }
    static func value(_ kg: Double, _ u: AppSettings.Units) -> Double { u == .imperial ? kg * lbPerKg : kg }
    /// "20", "22.5", "44.1" — one decimal at most, trailing ".0" dropped.
    static func number(_ kg: Double, _ u: AppSettings.Units) -> String {
        let r = (value(kg, u) * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", r)
    }
    static func text(_ kg: Double, _ u: AppSettings.Units) -> String { "\(number(kg, u)) \(unit(u))" }
    /// What the rider typed, in their units, back to kilograms. Empty or invalid → nil (not recorded).
    static func parse(_ s: String, _ u: AppSettings.Units) -> Double? {
        guard let v = Double(s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")), v >= 0, v.isFinite else { return nil }
        return u == .imperial ? v / lbPerKg : v
    }
    /// Progression step for loaded exercises, stored in kg: metric 1 kg (dumbbell / kettlebell, per hand) or 2.5 kg;
    /// imperial 2.5 lb or 5 lb — the usual plate / dumbbell steps of each system.
    static func step(dumbbell: Bool, _ u: AppSettings.Units) -> Double {
        u == .imperial ? (dumbbell ? 2.5 : 5) / lbPerKg : (dumbbell ? 1 : 2.5)
    }
}

// MARK: - Detailed logging: exercises → sets; supersets; templates

struct SetEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var reps: Int = 8
    /// nil = bodyweight (or not recorded)
    var weightKg: Double? = nil
    var bodyweight = false
    /// one side at a time (reps are per side)
    var unilateral = false
    var rpe: Int? = nil
    var done = true

    init(id: UUID = UUID(), reps: Int = 8, weightKg: Double? = nil, bodyweight: Bool = false, unilateral: Bool = false, rpe: Int? = nil, done: Bool = true) {
        self.id = id; self.reps = reps; self.weightKg = weightKg; self.bodyweight = bodyweight; self.unilateral = unilateral; self.rpe = rpe; self.done = done
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        reps = try c.decodeIfPresent(Int.self, forKey: .reps) ?? 0
        weightKg = try c.decodeIfPresent(Double.self, forKey: .weightKg)
        bodyweight = try c.decodeIfPresent(Bool.self, forKey: .bodyweight) ?? false
        unilateral = try c.decodeIfPresent(Bool.self, forKey: .unilateral) ?? false
        rpe = try c.decodeIfPresent(Int.self, forKey: .rpe)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? true
    }
    /// Load × reps for progression; bodyweight sets count reps only (weight unknown → not comparable to loaded sets).
    var tonnageKg: Double? { guard !bodyweight, let w = weightKg else { return nil }; return w * Double(reps) * (unilateral ? 2 : 1) }
    var text: String { text(units: .metric) }
    func text(units u: AppSettings.Units) -> String {
        let w = bodyweight ? "BW" : weightKg.map { WeightFmt.text($0, u) } ?? "—"
        return "\(reps)\(unilateral ? "/side" : "") × \(w)" + (rpe.map { " @\($0)" } ?? "")
    }
}

struct ExerciseEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var exerciseId: String
    var name: String
    var pattern: MovementPattern
    var sets: [SetEntry] = []
    /// Entries sharing a group letter are a superset (performed back to back).
    var superset: String? = nil
    var notes = ""

    init(id: UUID = UUID(), exercise: Exercise, sets: [SetEntry] = [], superset: String? = nil, notes: String = "") {
        self.id = id; exerciseId = exercise.id; name = exercise.name; pattern = exercise.pattern; self.sets = sets; self.superset = superset; self.notes = notes
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        exerciseId = try c.decodeIfPresent(String.self, forKey: .exerciseId) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Exercise"
        pattern = (try? c.decodeIfPresent(MovementPattern.self, forKey: .pattern)) ?? .other
        sets = try c.decodeIfPresent([SetEntry].self, forKey: .sets) ?? []
        superset = try c.decodeIfPresent(String.self, forKey: .superset)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
    var doneSets: [SetEntry] { sets.filter { $0.done } }
    var tonnageKg: Double? { let t = doneSets.compactMap { $0.tonnageKg }; return t.isEmpty ? nil : t.reduce(0, +) }
    var totalReps: Int { doneSets.reduce(0) { $0 + $1.reps } }
    var summary: String { summary(units: .metric) }
    func summary(units u: AppSettings.Units) -> String { doneSets.isEmpty ? "no sets" : "\(doneSets.count) × " + (Set(doneSets.map { $0.text(units: u) }).count == 1 ? doneSets[0].text(units: u) : "\(doneSets.map { $0.reps }.min() ?? 0)–\(doneSets.map { $0.reps }.max() ?? 0) reps") }
}

/// A reusable workout template: the exercise list with the sets as last performed (prefilled on the next use).
struct WorkoutTemplate: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var focus: StrengthFocus = .custom
    var entries: [ExerciseEntry]
    var updatedAt = Date()
    var lastUsed: Date? = nil

    init(id: UUID = UUID(), name: String, focus: StrengthFocus = .custom, entries: [ExerciseEntry], updatedAt: Date = Date(), lastUsed: Date? = nil, minutesEstimate: Int? = nil) {
        self.id = id; self.name = name; self.focus = focus; self.entries = entries; self.updatedAt = updatedAt; self.lastUsed = lastUsed; self.minutesEstimate = minutesEstimate
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Template"
        focus = (try? c.decodeIfPresent(StrengthFocus.self, forKey: .focus)) ?? .custom
        entries = try c.decodeIfPresent([ExerciseEntry].self, forKey: .entries) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        lastUsed = try c.decodeIfPresent(Date.self, forKey: .lastUsed)
        minutesEstimate = try? c.decodeIfPresent(Int.self, forKey: .minutesEstimate)
    }
    /// Planned duration: the rider's own estimate when set, else ~2.5 min per planned set (+5 min warm-up), 15–180.
    var minutesEstimate: Int? = nil
    var estimatedMinutes: Int {
        if let m = minutesEstimate, m > 0 { return m }
        let sets = entries.reduce(0) { $0 + $1.sets.count }
        return min(180, max(15, 5 + Int((Double(sets) * 2.5).rounded())))
    }
    var exerciseNames: String { entries.map { $0.name }.joined(separator: " · ") }
    var setCount: Int { entries.reduce(0) { $0 + $1.sets.count } }
    /// Entries for the next use: exercise order, supersets and notes always from the template; the sets carry the values
    /// of the most recent detailed session that used it — but only when that session is newer than the template's last
    /// edit (an edited template wins), and never with fewer sets than the template plans (a partial session does not
    /// shrink the next one).
    func prefilled(from last: StrengthSession?) -> [ExerciseEntry] {
        func fresh(_ s: SetEntry) -> SetEntry { var t = s; t.id = UUID(); t.done = true; return t }
        let usable = last.flatMap { l in l.date >= updatedAt ? l.exercises : nil }
        return entries.map { e in
            var x = e; x.id = UUID()
            if let ex = usable, let prev = ex.first(where: { $0.exerciseId == e.exerciseId }), !prev.sets.isEmpty {
                let n = max(prev.sets.count, e.sets.count)
                x.sets = (0..<n).map { i in fresh(i < prev.sets.count ? prev.sets[i] : e.sets[i]) }
            } else { x.sets = x.sets.map(fresh) }
            return x
        }
    }
}

// MARK: - Analysis from detailed logs only

struct CoverageReport: Equatable {
    /// Days in the window on which the pattern was trained (from detailed logs). nil for a pattern when NO detailed
    /// log exists at all → "unknown", never "missing".
    var sessionsByPattern: [MovementPattern: Int]
    var detailedSessions: Int
    var quickOnlySessions: Int
    var pushSets: Int, pullSets: Int
    var known: Bool { detailedSessions > 0 }
    func count(_ p: MovementPattern) -> Int { sessionsByPattern[p] ?? 0 }
    var missing: [MovementPattern] { known ? MovementPattern.coverage.filter { count($0) == 0 } : [] }
}

struct ProgressionPoint: Equatable { var date: Date; var tonnageKg: Double?; var topWeightKg: Double?; var reps: Int }
struct ExerciseProgression: Identifiable, Equatable {
    var id: String { exerciseId }
    var exerciseId: String; var name: String
    var points: [ProgressionPoint]          // oldest first
    enum Trend: String { case up, flat, down, insufficient }
    /// Compares the mean tonnage of the last 2 sessions with the 2 before; needs ≥ 4 sessions with load.
    var trend: Trend {
        let t = points.compactMap { $0.tonnageKg }
        guard t.count >= 4 else { return .insufficient }
        let recent = t.suffix(2).reduce(0, +) / 2, before = t.dropLast(2).suffix(2).reduce(0, +) / 2
        guard before > 0 else { return .insufficient }
        let d = (recent - before) / before
        return d > 0.03 ? .up : d < -0.03 ? .down : .flat
    }
}

enum StrengthAnalysis {
    static func coverage(_ sessions: [StrengthSession], since: Date) -> CoverageReport {
        let recent = sessions.filter { $0.date >= since }
        var by: [MovementPattern: Int] = [:]
        var detailed = 0, quick = 0, push = 0, pull = 0
        for s in recent {
            guard let ex = s.exercises, !ex.isEmpty else { quick += 1; continue }
            detailed += 1
            for p in Set(ex.map { $0.pattern }) { by[p, default: 0] += 1 }
            push += ex.filter { $0.pattern == .push }.reduce(0) { $0 + $1.doneSets.count }
            pull += ex.filter { $0.pattern == .pull }.reduce(0) { $0 + $1.doneSets.count }
        }
        return CoverageReport(sessionsByPattern: by, detailedSessions: detailed, quickOnlySessions: quick, pushSets: push, pullSets: pull)
    }
    /// Per-exercise progression from detailed logs (oldest first), only for exercises logged ≥ 2 times.
    static func progression(_ sessions: [StrengthSession]) -> [ExerciseProgression] {
        var map: [String: (String, [ProgressionPoint])] = [:]
        for s in sessions.sorted(by: { $0.date < $1.date }) {
            for e in s.exercises ?? [] where !e.doneSets.isEmpty {
                let top = e.doneSets.compactMap { $0.bodyweight ? nil : $0.weightKg }.max()
                map[e.exerciseId, default: (e.name, [])].1.append(ProgressionPoint(date: s.date, tonnageKg: e.tonnageKg, topWeightKg: top, reps: e.totalReps))
            }
        }
        return map.filter { $0.value.1.count >= 2 }.map { ExerciseProgression(exerciseId: $0.key, name: $0.value.0, points: $0.value.1) }.sorted { $0.name < $1.name }
    }
}

// MARK: - Next workout insight (0.8.0): ONE actionable item from completed sessions, labelled suggestion vs finding

/// What the rider sees on Home and on the scheduled strength screen. `change` is applied only on Accept, and only to
/// the planned sets of THAT session (the template is touched only when the rider also asks for it).
struct WorkoutInsight: Equatable, Identifiable, Codable {
    enum Kind: String, Codable { case progression, hold, coverage, interference, insufficient }
    enum Label: String, Codable { case suggestion, finding }
    /// A concrete, undoable edit to one exercise's planned sets.
    struct SetChange: Equatable, Codable { var exerciseId: String; var repsDelta: Int; var weightDeltaKg: Double }
    var id: String
    var kind: Kind
    var label: Label
    var text: String
    var why: String
    var evidence: String            // e.g. "2 sessions, 12 Oct and 19 Oct" or "insufficient evidence"
    var change: SetChange? = nil
    var exerciseName: String? = nil
}

enum InsightEngine {
    /// Rules (all from completed, detailed sessions; quick logs only feed interference):
    /// 1. Interference: a demanding ride is planned within 1 day after this strength session and the routine loads
    ///    the legs → finding + suggestion to keep leg work light (no set change; the rider decides).
    /// 2. Progression: for an exercise in the routine logged ≥ 2 times, the last session hit every planned rep with
    ///    RPE ≤ 8 (or no RPE recorded but all reps done and the one before was at least as heavy) → +1 rep (bodyweight /
    ///    unknown load) or +2.5 kg (loaded, dumbbell +1 kg per hand… we use +2.5 kg for barbell/machine, +1 kg for
    ///    dumbbell/kettlebell); labelled suggestion.
    /// 3. Hold: last session had RPE ≥ 9 or missed reps on that exercise → keep weight; labelled finding.
    /// 4. Coverage: ≥ 3 detailed sessions in 28 days and a coverage pattern never trained → "consider adding …",
    ///    suggestion, only exercises the rider can do are named.
    /// 5. Otherwise: insufficient evidence, say so.
    static func next(routine: WorkoutTemplate?, planned: [ExerciseEntry], sessions: [StrengthSession], plan: [Workout], equipment: EquipmentProfile, catalogue: [Exercise], on date: Date, now: Date = Date(), calendar cal: Calendar = .current, units: AppSettings.Units = .metric) -> WorkoutInsight {
        // completed, detailed sessions only (a session in progress lives in Store.activeSession, never here)
        let detailed = sessions.filter { $0.isDetailed && !$0.inProgress }.sorted { $0.date > $1.date }
        let day = cal.startOfDay(for: date)
        let fmt = DateFormatter(); fmt.dateFormat = "d MMM"
        // 1. interference
        let loadsLegs = planned.contains { [.squat, .hinge, .singleLeg].contains($0.pattern) && $0.sets.count >= 2 } || (routine?.focus.loadsLegs ?? false)
        if loadsLegs {
            let hard = plan.first { w in w.kind.isRide && w.kind.zone >= 3 && !w.skipped && !w.done && { let d = cal.startOfDay(for: w.date); return d > day && (cal.dateComponents([.day], from: day, to: d).day ?? 99) <= 1 }() }
            if let h = hard {
                return WorkoutInsight(id: "interf-\(h.id.uuidString.prefix(6))", kind: .interference, label: .suggestion,
                                      text: "Keep the leg work light today — a \(h.kind.title.lowercased()) ride is planned on \(h.date.shortDay).",
                                      why: "Heavy squats, hinges or lunges the day before a hard ride usually mean tired legs for the quality intervals. Your routine is not changed; do the leg exercises at a lighter weight or fewer sets, or move the ride if that day is flexible.",
                                      evidence: "from the plan: \(h.kind.title) \(h.date.shortDay)")
            }
        }
        // 2/3. progression or hold, exercise by exercise in routine order. The target is what the rider PLANNED (the
        //      routine's sets), never the last performance itself, so a partial or missed session cannot look "all hit".
        for e in planned {
            let known = catalogue.first { $0.id == e.exerciseId }
            if equipment.excluded.contains(e.exerciseId) { continue }      // the rider said they cannot do it: no advice on it
            let history: [(date: Date, rpe: Int?, entry: ExerciseEntry)] = detailed.compactMap { s in
                s.exercises?.first(where: { $0.exerciseId == e.exerciseId && !$0.doneSets.isEmpty }).map { (date: s.date, rpe: s.rpe, entry: $0) }
            }
            guard history.count >= 2 else { continue }
            let last = history[0], prev = history[1]
            let target = routine?.entries.first(where: { $0.exerciseId == e.exerciseId })?.sets ?? e.sets
            let plannedReps = target.map { $0.reps }
            let lastReps = last.entry.doneSets.map { $0.reps }
            let allHit = !lastReps.isEmpty && lastReps.count >= plannedReps.count && zip(lastReps, plannedReps).allSatisfy { $0 >= $1 }
            let maxRPE = last.entry.doneSets.compactMap { $0.rpe }.max() ?? last.rpe
            let lastTop = last.entry.doneSets.compactMap { $0.bodyweight ? nil : $0.weightKg }.max()
            let prevTop = prev.entry.doneSets.compactMap { $0.bodyweight ? nil : $0.weightKg }.max()
            let ev = "\(history.count) sessions, \(fmt.string(from: prev.date)) and \(fmt.string(from: last.date)) · completed sets of \(e.name) only"
            if let r = maxRPE, r >= 9 { return WorkoutInsight(id: "hold-\(e.exerciseId)", kind: .hold, label: .finding, text: "Keep \(e.name) at the same weight — last time was RPE \(r).", why: "The last session of \(e.name) was rated very hard (RPE \(r)). Repeating the same load lets you consolidate it before adding more.", evidence: ev, exerciseName: e.name) }
            if !allHit {
                let shortSets = lastReps.count < plannedReps.count
                return WorkoutInsight(id: "hold-\(e.exerciseId)", kind: .hold, label: .finding, text: "Repeat \(e.name) at the same weight — not every planned \(shortSets ? "set" : "rep") was completed last time.", why: "Last session: \(lastReps.map(String.init).joined(separator: "/")) reps in \(lastReps.count) completed set\(lastReps.count == 1 ? "" : "s") against \(plannedReps.map(String.init).joined(separator: "/")) planned. Hit the plan first, then progress. Only sets you ticked as done are counted.", evidence: ev, exerciseName: e.name)
            }
            if (maxRPE ?? 8) <= 8 {
                let notRegressed = lastTop == nil || prevTop == nil || lastTop! >= prevTop!
                guard notRegressed else { continue }
                let dumbbell = known?.equipment.contains { $0 == "dumbbell" || $0 == "kettlebell" } ?? false
                // load is suggested only when the exercise is loaded and the rider (as far as we know) owns its equipment
                let canLoad = lastTop != nil && (known.map { equipment.hasEquipment(for: $0) } ?? true)
                let step = WeightFmt.step(dumbbell: dumbbell, units)
                let change = canLoad ? WorkoutInsight.SetChange(exerciseId: e.exerciseId, repsDelta: 0, weightDeltaKg: step) : WorkoutInsight.SetChange(exerciseId: e.exerciseId, repsDelta: 1, weightDeltaKg: 0)
                let what = canLoad ? "add \(WeightFmt.text(step, units))\(dumbbell ? " per hand" : "") to \(e.name)" : "add one rep per set to \(e.name)"
                let loadNote: String
                if canLoad { loadNote = " Cyclift does not know which weights you own (fixed dumbbells or plates may not allow this step); if the next weight is not available, do one more rep per set instead." }
                else if lastTop != nil { loadNote = " A rep is suggested rather than more weight because the equipment for \(e.name) is not in your equipment list." }
                else { loadNote = "" }
                return WorkoutInsight(id: "prog-\(e.exerciseId)", kind: .progression, label: .suggestion, text: "Suggestion: \(what).",
                                      why: "You completed every planned set and rep of \(e.name) last time\(maxRPE.map { " at RPE \($0)" } ?? "")\(lastTop.map { " with \(WeightFmt.text($0, units))" } ?? ""), and the session before was not heavier. A small step keeps progress without a jump.\(loadNote) Accept changes only this session's planned sets; your template stays as it is unless you choose to update it.",
                                      evidence: ev, change: change, exerciseName: e.name)
            }
        }
        // 4. coverage from detailed logs; only exercises the rider can do (equipment owned, not excluded) are named
        let since = cal.date(byAdding: .day, value: -28, to: cal.startOfDay(for: now))!
        let cov = StrengthAnalysis.coverage(detailed, since: since)
        if cov.detailedSessions >= 3, let miss = cov.missing.first(where: { $0 != .carry }) {
            let candidates = catalogue.filter { c in c.pattern == miss && equipment.canDo(c) && !planned.contains { p in p.exerciseId == c.id } }
            let p = miss.title.lowercased()
            let text = candidates.first.map { "Consider adding a \(p) exercise (e.g. \($0.name))." } ?? "Consider adding a \(p) exercise — none in the list fits your equipment and exclusions, so add one of your own."
            return WorkoutInsight(id: "cov-\(miss.rawValue)", kind: .coverage, label: .suggestion, text: text,
                                  why: "In \(cov.detailedSessions) detailed sessions over 4 weeks no \(p) movement was logged. This is read from your logged exercises only; a session labelled “full body” is not counted as coverage. Suggested exercises are limited to equipment you own and leave out exercises you marked as ones you cannot do.",
                                  evidence: "\(cov.detailedSessions) detailed sessions, 28 days")
        }
        // 5. insufficient
        let n = detailed.count
        return WorkoutInsight(id: "none", kind: .insufficient, label: .finding,
                              text: n == 0 ? "No exercise history yet — log sets in a session and the coach can suggest progression next time." : "Not enough history for a progression call yet (\(n) detailed session\(n == 1 ? "" : "s"); needs 2 of the same exercise).",
                              why: "Progression suggestions compare at least two completed sessions of the same exercise (reps, weight and effort). Until then the coach makes no claim.", evidence: "insufficient evidence")
    }

    /// Applies a progression change to the planned entries of one session (not the template).
    static func apply(_ c: WorkoutInsight.SetChange, to entries: inout [ExerciseEntry]) {
        for i in entries.indices where entries[i].exerciseId == c.exerciseId {
            for j in entries[i].sets.indices {
                entries[i].sets[j].reps = max(1, entries[i].sets[j].reps + c.repsDelta)
                if c.weightDeltaKg != 0, let w = entries[i].sets[j].weightKg, !entries[i].sets[j].bodyweight { entries[i].sets[j].weightKg = w + c.weightDeltaKg }
            }
        }
    }
}

// MARK: - Store helpers for routines, duplicate logs and insights (A5 hardening; pure reads over the Store's data)
extension Store {
    /// What a strength session's routine is: none chosen, a saved template, or a template that no longer exists
    /// (deleted here or on another device) — the UI then says "routine removed — choose another".
    enum RoutineState: Equatable {
        case none, assigned(WorkoutTemplate), removed
    }
    func routineState(for w: Workout) -> RoutineState {
        guard w.kind == .strength, let id = w.templateId else { return .none }
        if let t = template(id) { return .assigned(t) }
        return .removed
    }
    func isRoutineRemoved(_ w: Workout) -> Bool { routineState(for: w) == .removed }

    /// A completed session that a new log for this planned workout (or, without one, for this day's already-completed
    /// strength session) would duplicate. nil = nothing logged yet / a genuinely extra session.
    func existingLog(forWorkout id: UUID?, on date: Date, calendar cal: Calendar = .current) -> StrengthSession? {
        if let id {
            if let s = strength.first(where: { $0.workoutId == id }) { return s }
            if let w = plan.first(where: { $0.id == id }), w.done { return strength.first { cal.isDate($0.date, inSameDayAs: w.date) } }
            return nil
        }
        // no planned workout given: only when every strength session planned that day is already done
        let planned = plan.filter { $0.kind == .strength && !$0.skipped && cal.isDate($0.date, inSameDayAs: date) }
        guard !planned.isEmpty, planned.allSatisfy({ $0.done }) else { return nil }
        return strength.first { s in cal.isDate(s.date, inSameDayAs: date) && (s.workoutId.map { wid in planned.contains { $0.id == wid } } ?? false) }
            ?? strength.first { cal.isDate($0.date, inSameDayAs: date) }
    }

    /// The open strength session of a day (for quick logs started from Home, so the right one is marked done).
    func openStrength(on date: Date, calendar cal: Calendar = .current) -> Workout? {
        plan.filter { $0.kind == .strength && !$0.done && !$0.skipped && cal.isDate($0.date, inSameDayAs: date) }.min { $0.sequence < $1.sequence }
    }

    /// The insight for a session (or for Home without one), in the rider's units.
    func insight(for w: Workout?, entries: [ExerciseEntry], now: Date = Date()) -> WorkoutInsight {
        InsightEngine.next(routine: w.flatMap { routine(for: $0) }, planned: entries, sessions: strength, plan: plan, equipment: equipment, catalogue: allExercises, on: w?.date ?? now, now: now, units: settings.units)
    }
    /// The insight accepted most recently for this workout, while it is still the last applied change (so Undo is exact).
    func lastAcceptedInsight(for workoutId: UUID?) -> AppliedProposal? {
        guard let id = workoutId, let last = appliedProposals.last, last.id.hasPrefix("insight-"), last.before.id == id else { return nil }
        return last
    }
    func unignoreInsight(_ id: String) { ignoredInsights.removeAll { $0 == id } }
}
