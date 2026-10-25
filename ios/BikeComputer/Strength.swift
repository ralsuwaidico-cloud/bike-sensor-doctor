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
    static let equipmentOptions = ["bodyweight", "barbell", "dumbbell", "kettlebell", "cable", "machine", "band", "trap bar", "bench"]
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
    var text: String {
        let w = bodyweight ? "BW" : weightKg.map { $0 == $0.rounded() ? "\(Int($0)) kg" : String(format: "%.1f kg", $0) } ?? "—"
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
    var summary: String { doneSets.isEmpty ? "no sets" : "\(doneSets.count) × " + (Set(doneSets.map { $0.text }).count == 1 ? doneSets[0].text : "\(doneSets.map { $0.reps }.min() ?? 0)–\(doneSets.map { $0.reps }.max() ?? 0) reps") }
}

/// A reusable workout template: the exercise list with the sets as last performed (prefilled on the next use).
struct WorkoutTemplate: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var focus: StrengthFocus = .custom
    var entries: [ExerciseEntry]
    var updatedAt = Date()
    var lastUsed: Date? = nil

    init(id: UUID = UUID(), name: String, focus: StrengthFocus = .custom, entries: [ExerciseEntry], updatedAt: Date = Date(), lastUsed: Date? = nil) {
        self.id = id; self.name = name; self.focus = focus; self.entries = entries; self.updatedAt = updatedAt; self.lastUsed = lastUsed
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Template"
        focus = (try? c.decodeIfPresent(StrengthFocus.self, forKey: .focus)) ?? .custom
        entries = try c.decodeIfPresent([ExerciseEntry].self, forKey: .entries) ?? []
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        lastUsed = try c.decodeIfPresent(Date.self, forKey: .lastUsed)
    }
    /// Entries prefilled from the most recent detailed session that used this template (or the template's own values).
    func prefilled(from last: StrengthSession?) -> [ExerciseEntry] {
        guard let last, let ex = last.exercises else { return entries.map { e in var x = e; x.id = UUID(); x.sets = x.sets.map { s in var t = s; t.id = UUID(); t.done = true; return t }; return x } }
        return entries.map { e in
            var x = e; x.id = UUID()
            if let prev = ex.first(where: { $0.exerciseId == e.exerciseId }), !prev.sets.isEmpty { x.sets = prev.sets.map { s in var t = s; t.id = UUID(); t.done = true; return t } }
            else { x.sets = x.sets.map { s in var t = s; t.id = UUID(); t.done = true; return t } }
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
