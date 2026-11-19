import SwiftUI

// Training Hub v1.4 — correcting a set that is already logged, in the redesigned recorder (··· › Correct a logged set).
//
// PROVISIONAL LAYOUT. Sheet 04c draws Undo, skipped sets, pause and the exercise forms; it does not draw a page for
// changing a set logged earlier. Until one is approved this page lists the logged sets of the running session with the
// same − / + steps and the same value forms as the recorder (reps or seconds; weight, added weight or assistance).
//
// ONE RECORDING LOGIC: every change goes through the store's existing `updateActiveSession`; nothing is stored in a
// new place and nothing is saved here — the workout is saved only by Finish › Save, exactly as before.
// "Not done" returns the set to the recorder as an open set (it is logged again there); it never deletes it.

struct StrengthCorrectV14: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cyTheme) private var theme

    private var units: AppSettings.Units { store.settings.units }
    private var step: Double { units == .imperial ? 2.26796 : 2.5 }

    struct Row: Identifiable {
        let entry: Int
        let set: Int
        let name: String
        let label: String?
        let value: SetEntry
        var id: String { "\(entry)-\(set)" }
    }
    private var rows: [Row] {
        let es = store.activeSession?.exercises ?? []
        var out: [Row] = []
        for i in es.indices {
            for j in es[i].sets.indices where es[i].sets[j].done {
                out.append(Row(entry: i, set: j, name: es[i].name, label: NextSet.label(es, i), value: es[i].sets[j]))
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if rows.isEmpty {
                Text("No set is logged yet. A logged set can be corrected here until the workout is saved.")
                    .font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .padding(CySpace.l).accessibilityIdentifier("correctEmpty")
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(rows) { r in row(r) }
                    }
                    .padding(.horizontal, CySpace.l).padding(.bottom, CySpace.xl)
                }
            }
        }
        .background(theme.background.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("strengthCorrectV14")
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LOGGED SETS" + (CycliftLab.isLab ? " · DEMO DATA" : "")).font(CyFont.overline).tracking(1.2).foregroundStyle(theme.textSecondary)
                Text("Correct a set").font(CyFont.display).foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("correctTitle")
            }
            Spacer(minLength: 8)
            Button("Done") { dismiss() }
                .font(CyFont.label.weight(.semibold)).foregroundStyle(theme.accent)
                .frame(minWidth: CyHit.min, minHeight: CyHit.min).contentShape(Rectangle()).buttonStyle(.plain)
                .accessibilityIdentifier("correctDone")
        }
        .padding(.horizontal, CySpace.l).padding(.top, CySpace.l).padding(.bottom, CySpace.s)
    }

    private func row(_ r: Row) -> some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.name).font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Text(r.label.map { "\($0) · round \(r.set + 1)" } ?? "Set \(r.set + 1)").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 8)
                Text(NextSet.setText(r.value, units)).font(CyFont.value).foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.trailing).accessibilityIdentifier("correctValue-\(r.id)")
            }
            controls(r)
        }
        .padding(.vertical, CySpace.m)
        .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("correctRow-\(r.id)")
    }

    private func controls(_ r: Row) -> some View {
        HStack(spacing: CySpace.s) {
            if r.value.seconds != nil {
                pair("Seconds", id: "Reps", r,
                     minus: { $0.seconds = max(5, ($0.seconds ?? 30) - 5) }, plus: { $0.seconds = min(600, ($0.seconds ?? 30) + 5) })
            } else {
                pair("Reps", id: "Reps", r,
                     minus: { $0.reps = max(1, $0.reps - 1) }, plus: { $0.reps = min(100, $0.reps + 1) })
            }
            weightPair(r)
            Spacer(minLength: 4)
            Button("Not done") { change(r) { $0.done = false } }
                .font(CyFont.label.weight(.semibold)).foregroundStyle(theme.textSecondary)
                .frame(minWidth: CyHit.min, minHeight: CyHit.min).contentShape(Rectangle()).buttonStyle(.plain)
                .accessibilityHint("The set goes back to the workout as a set still to do").accessibilityIdentifier("correctUnlog-\(r.id)")
        }
    }
    @ViewBuilder private func weightPair(_ r: Row) -> some View {
        let s = step
        if r.value.addedKg != nil {
            pair("Added", id: "Weight", r, minus: { $0.addedKg = max(s, ($0.addedKg ?? s) - s) }, plus: { $0.addedKg = ($0.addedKg ?? 0) + s })
        } else if r.value.assistKg != nil {
            pair("Assist", id: "Weight", r, minus: { $0.assistKg = max(s, ($0.assistKg ?? s) - s) }, plus: { $0.assistKg = ($0.assistKg ?? 0) + s })
        } else if !r.value.bodyweight && r.value.weightKg != nil {
            pair("Weight", id: "Weight", r, minus: { $0.weightKg = max(0, ($0.weightKg ?? 0) - s) }, plus: { $0.weightKg = ($0.weightKg ?? 0) + s })
        }
    }
    private func pair(_ title: String, id: String, _ r: Row, minus: @escaping (inout SetEntry) -> Void, plus: @escaping (inout SetEntry) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).font(CyFont.overline).tracking(1.2).foregroundStyle(theme.textSecondary)
            HStack(spacing: CySpace.s) {
                stepButton("minus", "Less \(title.lowercased())", id: "correct\(id)Minus-\(r.id)") { change(r, minus) }
                stepButton("plus", "More \(title.lowercased())", id: "correct\(id)Plus-\(r.id)") { change(r, plus) }
            }
        }
    }
    private func stepButton(_ icon: String, _ label: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(theme.textPrimary)
                .frame(width: CyHit.min, height: CyHit.min).overlay(Circle().strokeBorder(theme.border, lineWidth: 1.2)).contentShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }

    private func change(_ r: Row, _ f: @escaping (inout SetEntry) -> Void) {
        store.updateActiveSession { s in
            guard var es = s.exercises, es.indices.contains(r.entry), es[r.entry].sets.indices.contains(r.set) else { return }
            f(&es[r.entry].sets[r.set]); s.exercises = es
        }
        CyRecorderMemory.shared.refreshLogged(store.activeSession, units: units)     // the recorder's "Logged" line follows
    }
}
