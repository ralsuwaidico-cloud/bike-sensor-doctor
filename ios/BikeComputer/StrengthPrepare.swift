import Foundation

// Training Hub v1.4 — what the strength preparation screen shows (sheet 01a "J2 Prepare", sheet G3), as plain values
// built from the session's own planned entries. Nothing here starts, changes or saves anything. Foundation only, so the
// Linux harness tests it.

struct PrepareRow: Equatable, Identifiable {
    let id: String
    let name: String
    /// "3 × 10" on its own; inside a superset only the repetitions ("10") — the rounds are in the group's heading.
    let target: String
}

struct PrepareGroup: Equatable, Identifiable {
    let id: String
    /// The superset letter ("A") when these exercises are done back to back; nil for a single exercise.
    let superset: String?
    let rounds: Int?
    let rows: [PrepareRow]
    var heading: String? { superset.map { "Superset \($0)" + (rounds.map { " · \($0) round\($0 == 1 ? "" : "s")" } ?? "") } }
}

enum StrengthPrepare {
    /// What one set asks for: "10", "10 / side", "30 s". Only what the plan holds; a weight is not part of this line.
    static func amount(_ s: SetEntry) -> String {
        if let sec = s.seconds, sec > 0 { return "\(sec) s" }
        return s.unilateral ? "\(s.reps) / side" : "\(s.reps)"
    }
    /// "3 × 10" when every set asks for the same; "3 sets" when they differ (the recorder shows each).
    static func target(_ e: ExerciseEntry, inSuperset: Bool) -> String {
        guard let first = e.sets.first else { return "" }
        let same = e.sets.allSatisfy { amount($0) == amount(first) }
        if inSuperset { return same ? amount(first) : "varies" }
        return same ? "\(e.sets.count) × \(amount(first))" : "\(e.sets.count) sets"
    }
    /// Consecutive entries that share a superset letter form one group; everything else stands alone, in plan order.
    static func groups(_ entries: [ExerciseEntry]) -> [PrepareGroup] {
        var out: [PrepareGroup] = []
        var i = 0
        while i < entries.count {
            let e = entries[i]
            if let letter = e.superset, !letter.isEmpty {
                var j = i
                while j < entries.count, entries[j].superset == letter { j += 1 }
                if j - i >= 2 {
                    let members = Array(entries[i..<j])
                    out.append(PrepareGroup(id: "superset-\(letter)-\(i)", superset: letter, rounds: members.map { $0.sets.count }.max(),
                                            rows: members.map { PrepareRow(id: $0.id.uuidString, name: $0.name, target: target($0, inSuperset: true)) }))
                    i = j; continue
                }
            }
            out.append(PrepareGroup(id: e.id.uuidString, superset: nil, rounds: nil, rows: [PrepareRow(id: e.id.uuidString, name: e.name, target: target(e, inSuperset: false))]))
            i += 1
        }
        return out
    }
    /// The equipment the planned exercises name, in the order first needed, without "bodyweight". Empty = none needed.
    static func equipment(_ entries: [ExerciseEntry], library: [Exercise]) -> [String] {
        var seen: [String] = []
        for e in entries {
            guard let ex = library.first(where: { $0.id == e.exerciseId }) else { continue }
            for q in ex.equipment where q != "bodyweight" && !seen.contains(q) { seen.append(q) }
        }
        return seen
    }
    /// "About 35 min · dumbbell, bench" — the planned length and the equipment; "bodyweight" when nothing is needed.
    static func summary(minutes: Int, equipment: [String], known: Bool) -> String {
        var parts: [String] = []
        if minutes > 0 { parts.append("About \(Fmt.duration(minutes: minutes))") }
        if known { parts.append(equipment.isEmpty ? "bodyweight" : equipment.map(equipmentWord).joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }
    /// How a piece of equipment reads in a sentence (sheet 01a: "dumbbells, bench, band"). Things used in pairs or sets
    /// are plural; nothing else about the library's own word is changed.
    static func equipmentWord(_ e: String) -> String {
        switch e {
        case "dumbbell": return "dumbbells"
        case "kettlebell": return "kettlebells"
        default: return e
        }
    }
    /// The session's name under an overline that already says "Strength": "Strength · Full body" reads "Full body".
    /// A name that is only "Strength", or a routine's own name, is kept as it is.
    static func title(_ name: String) -> String {
        let prefix = "Strength · "
        guard name.hasPrefix(prefix), name.count > prefix.count else { return name }
        return String(name.dropFirst(prefix.count))
    }
    /// "Strength · planned today" / "Strength · planned Thu 19 Nov".
    static func overline(date: Date, now: Date = Date(), calendar cal: Calendar = .current) -> String {
        if cal.isDate(date, inSameDayAs: now) { return "Strength · planned today" }
        let f = DateFormatter(); f.dateFormat = "EEE d MMM"
        return "Strength · planned \(f.string(from: date))"
    }
}
