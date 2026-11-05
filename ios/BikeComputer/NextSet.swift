import Foundation

// MARK: - RC3 Strength workout: the "next set" rule, split out of StrengthNextSet.swift (W13) so it is testable without SwiftUI.

/// Which set comes next. Exercises go in order; inside a superset the group alternates (the member with the fewest
/// done sets goes first, ties in list order), so A1 → A2 → A1 …
enum NextSet {
    struct Pick: Equatable {
        let entry: Int
        let set: Int
        /// "A1", "A2" … for a superset member, nil otherwise.
        let label: String?
    }
    static func pick(_ es: [ExerciseEntry]) -> Pick? {
        guard let first = es.firstIndex(where: { e in e.sets.contains { !$0.done } }) else { return nil }
        var idx = first
        if let g = es[first].superset {
            let openIdx = es.indices.filter { i in es[i].superset == g && es[i].sets.contains { !$0.done } }
            idx = openIdx.min { es[$0].doneSets.count < es[$1].doneSets.count } ?? first
        }
        guard let s = es[idx].sets.firstIndex(where: { !$0.done }) else { return nil }
        return Pick(entry: idx, set: s, label: label(es, idx))
    }
    static func label(_ es: [ExerciseEntry], _ idx: Int) -> String? {
        guard let g = es[idx].superset else { return nil }
        let members = es.indices.filter { es[$0].superset == g }
        guard let pos = members.firstIndex(of: idx) else { return nil }
        return "\(g)\(pos + 1)"
    }
    /// The heaviest done set of each exercise (bodyweight sets: the most reps) — the finish summary's "top set".
    static func topSet(_ e: ExerciseEntry) -> SetEntry? {
        let done = e.doneSets
        guard !done.isEmpty else { return nil }
        return done.max { a, b in
            let wa = a.weightKg ?? 0, wb = b.weightKg ?? 0
            return wa == wb ? a.reps < b.reps : wa < wb
        }
    }
    static func setText(_ s: SetEntry, _ units: AppSettings.Units) -> String {
        let reps = "\(s.reps)\(s.unilateral ? "/side" : "")"
        if s.bodyweight || s.weightKg == nil { return "BW × \(reps)" }
        return "\(WeightFmt.text(s.weightKg ?? 0, units)) × \(reps)"
    }
}

