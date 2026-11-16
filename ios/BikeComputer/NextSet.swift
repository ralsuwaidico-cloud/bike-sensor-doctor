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
        guard let first = es.firstIndex(where: { e in e.sets.contains { $0.isOpen } }) else { return nil }
        var idx = first
        if let g = es[first].superset {
            let openIdx = es.indices.filter { i in es[i].superset == g && es[i].sets.contains { $0.isOpen } }
            // rounds are counted by the sets already dealt with — done or skipped — so a skipped set keeps the alternation
            func handled(_ i: Int) -> Int { es[i].sets.filter { !$0.isOpen }.count }
            idx = openIdx.min { handled($0) < handled($1) } ?? first
        }
        guard let s = es[idx].sets.firstIndex(where: { $0.isOpen }) else { return nil }
        return Pick(entry: idx, set: s, label: label(es, idx))
    }
    /// Training Hub v1.4 "Next exercise" line: the first DIFFERENT exercise that would come up if the sets were logged
    /// in order from here (inside a superset that is the partner; otherwise the next exercise in the list). nil = the
    /// exercise on screen is the last one with open sets.
    static func following(_ es: [ExerciseEntry]) -> Pick? {
        guard let now = pick(es) else { return nil }
        var sim = es
        var guardCount = 0
        while let p = pick(sim), guardCount < 500 {
            if p.entry != now.entry { return p }
            sim[p.entry].sets[p.set].done = true
            guardCount += 1
        }
        return nil
    }
    /// Training Hub v1.4 rest rule. `logged` is the set about to be logged (still open in `es`).
    /// Ordinary exercise: its own prescribed rest. Superset: no rest while another member still has its set of this
    /// round to do; once the round is complete, the longest prescribed rest of the members. nil = no rest.
    static func restAfter(_ es: [ExerciseEntry], logged p: Pick) -> Int? {
        guard es.indices.contains(p.entry) else { return nil }
        guard let g = es[p.entry].superset else { return es[p.entry].restSeconds }
        var sim = es
        if sim[p.entry].sets.indices.contains(p.set) { sim[p.entry].sets[p.set].done = true }
        func handled(_ i: Int) -> Int { sim[i].sets.filter { !$0.isOpen }.count }
        let members = sim.indices.filter { sim[$0].superset == g }
        let round = handled(p.entry)
        let roundOpen = members.contains { $0 != p.entry && handled($0) < round && sim[$0].sets.contains { $0.isOpen } }
        if roundOpen { return nil }
        return members.compactMap { sim[$0].restSeconds }.max()
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
        if let t = s.seconds { return "\(t) s hold" }
        let reps = "\(s.reps)\(s.unilateral ? "/side" : "")"
        if let a = s.addedKg { return "BW + \(WeightFmt.text(a, units)) × \(reps)" }
        if let a = s.assistKg { return "BW − \(WeightFmt.text(a, units)) assist × \(reps)" }
        if s.bodyweight || s.weightKg == nil { return "BW × \(reps)" }
        return "\(WeightFmt.text(s.weightKg ?? 0, units)) × \(reps)"
    }
}

