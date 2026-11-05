import SwiftUI

// MARK: - RC3 Strength workout: "What's my next set?"
// The live workout screen leads with ONE card: the exercise and set to do now, the target (reps × weight), a one-tap Log
// with compact adjust buttons, the rest timer and working time against the session's limit. Logging writes exactly the
// same data as ticking a set in the list below (`StrengthSession.exercises[i].sets[j].done`), so history, Progress and
// the coach read one record. No estimated 1RM here (ENG-D6: Progress only).

// `NextSet` (the pick rule) lives in NextSet.swift (Foundation only) so the Linux harness tests the executor order.

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
