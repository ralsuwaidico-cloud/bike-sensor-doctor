import SwiftUI

// MARK: - RC3 Strength workout: "What's my next set?"
// The live workout screen leads with ONE card: the exercise and set to do now, the target (reps × weight), a one-tap Log
// with compact adjust buttons, the rest timer and working time against the session's limit. Logging writes exactly the
// same data as ticking a set in the list below (`StrengthSession.exercises[i].sets[j].done`), so history, Progress and
// the coach read one record. No estimated 1RM here (ENG-D6: Progress only).

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

struct NextSetCard: View {
    @EnvironmentObject private var store: Store
    let session: StrengthSession
    let now: Date
    /// When the last set was logged here (starts the rest timer) and that exercise's prescribed rest.
    let lastLoggedAt: Date?
    let lastRest: Int?
    /// The planned session's time limit in minutes (nil = unplanned).
    let limitMinutes: Int?
    let onLogged: (Int?) -> Void
    let onFinish: () -> Void

    private var units: AppSettings.Units { store.settings.units }
    private var step: Double { units == .imperial ? 2.26796 : 2.5 }

    var body: some View {
        let es = session.exercises ?? []
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(clock(session.elapsedSeconds(now: now))).font(.headline.monospacedDigit())
                if let l = limitMinutes { Text("of \(l) min").font(.subheadline).foregroundStyle(session.elapsedSeconds(now: now) > l * 60 ? BC.stale : .secondary) }
                Spacer()
                restView
            }
            if let p = NextSet.pick(es) {
                let e = es[p.entry], st = e.sets[p.set]
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let l = p.label { Text(l).font(.caption.weight(.heavy)).padding(5).background(BC.accent.opacity(0.18), in: Circle()).accessibilityLabel("superset \(l)") }
                    Text(e.name).font(.title3.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Text("Set \(p.set + 1) of \(e.sets.count)").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                }
                Text(NextSet.setText(st, units)).font(DS.number).monospacedDigit().accessibilityIdentifier("nextSetTarget")
                HStack(spacing: DS.s) {
                    adjust("minus", "Fewer reps") { change(p) { $0.reps = max(1, $0.reps - 1) } }
                    adjust("plus", "More reps") { change(p) { $0.reps = min(100, $0.reps + 1) } }
                    if !(st.bodyweight || st.weightKg == nil) {
                        adjust("arrow.down", "Less weight") { change(p) { $0.weightKg = max(0, ($0.weightKg ?? 0) - step) } }
                        adjust("arrow.up", "More weight") { change(p) { $0.weightKg = ($0.weightKg ?? 0) + step } }
                    }
                    Button { log(p, rest: e.restSeconds) } label: { Label("Log set", systemImage: "checkmark").frame(maxWidth: .infinity, minHeight: DS.minTap) }
                        .buttonStyle(.borderedProminent).tint(BC.live).accessibilityIdentifier("logSet")
                }
            } else {
                Text("All sets done").font(.title3.weight(.bold))
                Button(action: onFinish) { Label("Finish workout", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity, minHeight: DS.minTap) }
                    .buttonStyle(.borderedProminent).tint(BC.live).accessibilityIdentifier("nextSetFinish")
            }
        }
        .accessibilityIdentifier("nextSetCard")
    }

    @ViewBuilder private var restView: some View {
        if let t = lastLoggedAt {
            let left = (lastRest ?? 90) - Int(now.timeIntervalSince(t))
            if left > 0 {
                Label(clock(left), systemImage: "timer").font(.headline.monospacedDigit()).foregroundStyle(BC.accent)
                    .accessibilityLabel("Rest \(left) seconds left").accessibilityIdentifier("restTimer")
            } else {
                Label("Go", systemImage: "timer").font(.headline).foregroundStyle(BC.live).accessibilityLabel("Rest done").accessibilityIdentifier("restTimer")
            }
        }
    }
    private func adjust(_ icon: String, _ a11y: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: DS.minTap, height: DS.minTap) }
            .buttonStyle(.bordered).accessibilityLabel(a11y)
    }
    private func change(_ p: NextSet.Pick, _ f: @escaping (inout SetEntry) -> Void) {
        store.updateActiveSession { s in
            guard var es = s.exercises, es.indices.contains(p.entry), es[p.entry].sets.indices.contains(p.set) else { return }
            f(&es[p.entry].sets[p.set]); s.exercises = es
        }
    }
    private func log(_ p: NextSet.Pick, rest: Int?) {
        change(p) { $0.done = true }
        onLogged(rest)
    }
    private func clock(_ s: Int) -> String { String(format: "%d:%02d", max(0, s) / 60, max(0, s) % 60) }
}
