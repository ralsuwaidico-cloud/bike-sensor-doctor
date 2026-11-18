import SwiftUI

// Training Hub v1.4 — the strength recorder (design sheets 01a J3–J4, 04a–04c, 06e–06f). Full screen; one primary
// exercise and the next exercise; fixed control positions; one-tap Log set; rest on the clock; Undo; save first,
// review afterwards and optional. Shown where CyProduct.redesign is on (StrengthSessionView switches to it).
//
// ONE RECORDING LOGIC. This screen draws the app's existing active session and changes it only through the existing
// Store functions: updateActiveSession, pause / resume, finishActiveSession (the one durable save), discard. The order
// of sets, including superset alternation, is the existing NextSet rule. Nothing is stored in a new place.
//
// NOT BUILT, AND NOT PRETENDED (each is a pending item of the v1.4 approval)
// • The optional review after saving is Redesign/ReviewV14.swift (three sliders, nothing pre-filled); its storage
//   limits are written there.
// • A stored round-rest value for supersets. The rule used: no rest between the members of a round; after the round,
//   the longest prescribed rest of its members. (Which value applies is still an open choice of the design.)
//
// ADDED WITH THE OWNER'S APPROVAL OF 16 NOV 2026 (optional fields; older records unchanged — see SetEntry)
// • Skip this set / skip this exercise (never counted as done; remembered as a count when the workout is saved).
// • Timed sets, added-weight sets and assisted sets, chosen per exercise under ···.
// • "Save unknown" as a state: the app's save reports success or failure only.

/// Rest and Undo live outside the screen so they survive minimising and coming back (v1.4 correction C). In memory
/// only: they belong to the running session and end with it.
@MainActor final class CyRecorderMemory: ObservableObject {
    static let shared = CyRecorderMemory()
    struct Logged: Equatable { var sessionId: UUID; var entry: Int; var set: Int; var text: String; var number: Int; var skippedSets: [Int] = [] }
    @Published var restEndsAt: Date? = nil
    @Published var lastLogged: Logged? = nil
    func clear() { restEndsAt = nil; lastLogged = nil }
}

struct StrengthRecorderV14: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dts
    @ObservedObject private var memory = CyRecorderMemory.shared
    @State private var now = Date()
    @State private var finishing = false
    @State private var allExercises = false
    @State private var confirmDiscard = false
    @State private var pausedByFinish = false
    @State private var savedSummary: FinishSummary? = nil
    /// Pending: Save was tapped and the result is not known yet (06e X4). Nothing is shown as saved.
    @State private var saving = false
    /// Unknown: the store accepted the save, but reading the file back did not find the workout (06f X7).
    @State private var unconfirmed: StrengthSession? = nil
    @State private var checks = 0
    @State private var lastCheck: SaveCheck? = nil
    /// After a confirmed save: the saved session, shown until the athlete leaves or opens the optional review.
    @State private var saved: StrengthSession? = nil
    @State private var review = false
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var units: AppSettings.Units { store.settings.units }
    private var step: Double { units == .imperial ? 2.26796 : 2.5 }

    var body: some View {
        Group {
            if let done = saved { savedView(done) }
            else if let u = unconfirmed { unconfirmedPage(u) }
            else if saving { CySavingPage(detail: "\(savedSummary?.title ?? "Workout") · your sets are still on this phone") }
            else if finishing, let s = store.activeSession { finishPage(s) }
            else if let s = store.activeSession { recorder(s) }
            else { nothing }
        }
        .background(theme.background.ignoresSafeArea())
        .onReceive(timer) { now = $0 }
        .onAppear { if let m = memory.lastLogged, m.sessionId != store.activeSession?.id { memory.clear() } }
        .sheet(isPresented: $allExercises) { StrengthSessionView(legacy: true) }
        .fullScreenCover(isPresented: $review, onDismiss: { dismiss() }) {
            if let s = saved { ReviewV14(target: .strength(s.id)) { review = false }.cyThemeRoot() }
        }
        .alert("Discard this workout?", isPresented: Binding(get: { confirmDiscard && !finishing }, set: { confirmDiscard = $0 })) {
            Button("Discard", role: .destructive) { store.discardActiveSession(); memory.clear(); dismiss() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Nothing is saved. The planned session stays open.") }
        // Lab runs 12–15: an identifier on a plain container replaced the identifiers of the controls directly inside it
        // (Log set could not be found). The screen is an accessibility container of its own, so every control keeps its own.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("strengthRecorderV14")
    }

    private var nothing: some View {
        VStack(spacing: CySpace.l) {
            Text("No workout in progress").font(CyFont.title).foregroundStyle(theme.textPrimary)
            Button("Close") { dismiss() }.frame(minHeight: CyHit.min).accessibilityIdentifier("recorderClose")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: recorder

    private func recorder(_ s: StrengthSession) -> some View {
        let es = s.exercises ?? []
        let pick = NextSet.pick(es)
        return VStack(alignment: .leading, spacing: 0) {
            header(s)
            if let p = pick {
                let e = es[p.entry], st = e.sets[p.set]
                ScrollView {
                    VStack(alignment: .leading, spacing: CySpace.l) {
                        exerciseHead(es, p, e)
                        targetLine(s, p, e, st)
                        values(p, st)
                        restRow(e)
                        loggedRow(s)
                        nextRow(es)
                    }
                    .padding(.horizontal, CySpace.l).padding(.top, CySpace.m)
                }
                bigButton("Log set", id: "logSet") { log(s, p, e, st) }
            } else {
                Spacer()
                VStack(alignment: .leading, spacing: CySpace.s) {
                    Text("All sets logged").font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(theme.textPrimary)
                        .accessibilityIdentifier("recorderAllDone")
                    loggedRow(s)
                    Text("Finish saves the sets you logged. You can still correct any set under ··· › All exercises.")
                        .font(CyFont.callout).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, CySpace.l)
                Spacer()
                bigButton("Finish workout", id: "nextSetFinish") { beginFinish() }
            }
        }
    }

    /// Identity strip: the Train mark (the way out — the session keeps running), the session and its exact state,
    /// Pause / Resume and Finish. Fixed positions.
    private func header(_ s: StrengthSession) -> some View {
        let paused = s.pausedAt != nil
        return HStack(spacing: CySpace.s) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down").font(.system(size: 15, weight: .bold)).foregroundStyle(theme.textOnAccent)
                    .frame(width: 36, height: 36).background(Circle().fill(theme.accent))
                    .frame(width: CyHit.min, height: CyHit.min).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Minimise").accessibilityHint("The workout keeps running. Open it again from the Train button")
            .accessibilityIdentifier("recorderMinimise")
            VStack(alignment: .leading, spacing: 0) {
                // Cyclift Lab: this screen covers the Lab strip, so it says itself that the athlete is the demo athlete
                Text((s.customName.isEmpty ? "Strength workout" : s.customName) + (CycliftLab.isLab ? " · DEMO DATA" : "")).font(CyFont.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
                    .accessibilityIdentifier("recorderName")
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(clock(s.elapsedSeconds(now: now))).font(CyFont.metricSmall).foregroundStyle(paused ? theme.textSecondary : theme.textPrimary)
                        .accessibilityIdentifier("recorderClock")
                    Text(paused ? "Paused · time is not counting" : "Recording").font(CyFont.caption).foregroundStyle(paused ? theme.warning : theme.textSecondary)
                        .accessibilityIdentifier("recorderState")
                }
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 4)
            Button { if paused { store.resumeActiveSession() } else { store.pauseActiveSession() } } label: {
                Image(systemName: paused ? "play.fill" : "pause.fill").font(.body.weight(.bold)).foregroundStyle(theme.textPrimary)
                    .frame(width: CyHit.min, height: CyHit.min).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel(paused ? "Resume" : "Pause").accessibilityIdentifier("recorderPause")
            Button("Finish") { beginFinish() }
                .font(CyFont.label.weight(.semibold)).foregroundStyle(theme.textPrimary)
                .frame(minWidth: CyHit.min, minHeight: CyHit.min).contentShape(Rectangle()).buttonStyle(.plain)
                .accessibilityIdentifier("finishWorkout")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, CySpace.s).padding(.vertical, 4)
    }

    private func exerciseHead(_ es: [ExerciseEntry], _ p: NextSet.Pick, _ e: ExerciseEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(overline(es, p, e)).font(CyFont.overline).tracking(1.2).foregroundStyle(theme.textSecondary)
                .accessibilityIdentifier("recorderOverline")
            Text(e.name).font(.system(.largeTitle, design: .rounded).weight(.bold)).foregroundStyle(theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("recorderExercise")
            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(Array(e.sets.enumerated()), id: \.offset) { i, st in
                        Capsule().fill(st.done ? theme.textPrimary : Color.clear)
                            .overlay(Capsule().strokeBorder(i == p.set ? theme.textPrimary : theme.textTertiary, lineWidth: 1.5))
                            .frame(width: 22, height: 6)
                    }
                }
                .accessibilityHidden(true)
                Text("Set \(p.set + 1) of \(e.sets.count)").font(CyFont.label).monospacedDigit().foregroundStyle(theme.textPrimary)
                    .accessibilityIdentifier("recorderSet")
            }
        }
    }
    /// "EXERCISE 1 OF 4" — or, in a superset, the member and the round in words.
    private func overline(_ es: [ExerciseEntry], _ p: NextSet.Pick, _ e: ExerciseEntry) -> String {
        if let l = p.label, let g = e.superset {
            let rounds = es.filter { $0.superset == g }.map { $0.sets.count }.max() ?? e.sets.count
            return "SUPERSET \(g) · \(l) · ROUND \(p.set + 1) OF \(rounds)"
        }
        return "EXERCISE \(p.entry + 1) OF \(es.count)"
    }

    /// The planned target beside what was done last time. A target is shown only when the plan holds one.
    private func targetLine(_ s: StrengthSession, _ p: NextSet.Pick, _ e: ExerciseEntry, _ st: SetEntry) -> some View {
        let planned = s.workoutId.flatMap { id in store.plan.first { $0.id == id } }?.plannedEntries?.first { $0.exerciseId == e.exerciseId }
        let target = planned.flatMap { $0.sets.indices.contains(p.set) ? $0.sets[p.set] : $0.sets.last }
        return HStack(alignment: .firstTextBaseline) {
            Text(target.map { "Target \(NextSet.setText($0, units))" } ?? "No planned target").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                .accessibilityIdentifier("recorderTarget")
            Spacer(minLength: 8)
            Text(previous(e).map { "Last time \($0)" } ?? "No previous log").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                .multilineTextAlignment(.trailing).accessibilityIdentifier("recorderLast")
        }
    }
    private func previous(_ e: ExerciseEntry) -> String? {
        for s in store.strength.sorted(by: { $0.date > $1.date }) {
            if let x = s.exercises?.first(where: { $0.exerciseId == e.exerciseId }), let top = NextSet.topSet(x) { return NextSet.setText(top, units) }
        }
        return nil
    }

    private func values(_ p: NextSet.Pick, _ st: SetEntry) -> some View {
        let layout = dts.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: CySpace.l)) : AnyLayout(HStackLayout(alignment: .top, spacing: 0))
        return layout {
            if let t = st.seconds {
                valueColumn("SECONDS", "\(t)", unit: "s hold", id: "Reps",
                            minus: { change(p) { $0.seconds = max(5, ($0.seconds ?? 30) - 5) } }, plus: { change(p) { $0.seconds = min(600, ($0.seconds ?? 30) + 5) } })
            } else {
                valueColumn("REPS", "\(st.reps)", unit: st.unilateral ? "per side" : nil, id: "Reps",
                            minus: { change(p) { $0.reps = max(1, $0.reps - 1) } }, plus: { change(p) { $0.reps = min(100, $0.reps + 1) } })
            }
            if let a = st.addedKg {
                valueColumn("ADDED WEIGHT", "+" + WeightFmt.number(a, units), unit: WeightFmt.unit(units), id: "Weight",
                            minus: { change(p) { $0.addedKg = max(step, ($0.addedKg ?? step) - step) } }, plus: { change(p) { $0.addedKg = ($0.addedKg ?? 0) + step } })
            } else if let a = st.assistKg {
                valueColumn("ASSISTANCE", "−" + WeightFmt.number(a, units), unit: WeightFmt.unit(units) + " help", id: "Weight",
                            minus: { change(p) { $0.assistKg = max(step, ($0.assistKg ?? step) - step) } }, plus: { change(p) { $0.assistKg = ($0.assistKg ?? 0) + step } })
            } else if st.bodyweight || st.weightKg == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WEIGHT").font(CyFont.overline).tracking(1.2).foregroundStyle(theme.textSecondary)
                    Text("Body").font(.system(size: 56, weight: .heavy, design: .rounded)).foregroundStyle(theme.textPrimary).minimumScaleFactor(0.5).lineLimit(1)
                        .accessibilityIdentifier("recorderWeight")
                    Text(st.seconds != nil ? "Timed hold — no weight to set" : "Bodyweight — no weight to set").font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                valueColumn("WEIGHT", WeightFmt.number(st.weightKg ?? 0, units), unit: WeightFmt.unit(units), id: "Weight",
                            minus: { change(p) { $0.weightKg = max(0, ($0.weightKg ?? 0) - step) } }, plus: { change(p) { $0.weightKg = ($0.weightKg ?? 0) + step } })
            }
        }
        .padding(.vertical, CySpace.s)
        .overlay(alignment: .top) { Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true) }
        .overlay(alignment: .bottom) { Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true) }
    }
    private func valueColumn(_ title: String, _ value: String, unit: String?, id: String, minus: @escaping () -> Void, plus: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(CyFont.overline).tracking(1.2).foregroundStyle(theme.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(size: 56, weight: .heavy, design: .rounded)).monospacedDigit().foregroundStyle(theme.textPrimary)
                    .minimumScaleFactor(0.5).lineLimit(1).accessibilityIdentifier("recorder\(id)")
                if let u = unit { Text(u).font(CyFont.callout).foregroundStyle(theme.textSecondary) }
            }
            HStack(spacing: CySpace.m) {
                stepButton("minus", "Less \(title.lowercased())", id: "recorder\(id)Minus", minus)
                stepButton("plus", "More \(title.lowercased())", id: "recorder\(id)Plus", plus)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }
    private func stepButton(_ icon: String, _ label: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(theme.textPrimary)
                .frame(width: 48, height: 48).overlay(Circle().strokeBorder(theme.border, lineWidth: 1.2)).contentShape(Circle())
        }
        .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }

    /// Before a set: the rest that will follow it. After a set: the rest counting down on the clock, with −15 / Skip / +15.
    @ViewBuilder private func restRow(_ e: ExerciseEntry) -> some View {
        if let end = memory.restEndsAt {
            let left = Int(end.timeIntervalSince(now).rounded(.up))
            HStack(alignment: .firstTextBaseline, spacing: CySpace.s) {
                Text(left > 0 ? clock(left) : "Go").font(.system(.title, design: .rounded).weight(.heavy)).monospacedDigit().foregroundStyle(left > 0 ? theme.textPrimary : theme.success)
                    .accessibilityLabel(left > 0 ? "Rest, \(left) seconds left" : "Rest done").accessibilityIdentifier("restTimer")
                Text(left > 0 ? "rest" : "rest is over").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                Spacer(minLength: 4)
                if left > 0 {
                    restButton("−15", "15 seconds less rest", id: "restMinus") { memory.restEndsAt = max(now, end.addingTimeInterval(-15)) }
                    restButton("Skip", "Skip the rest", id: "restSkip") { memory.restEndsAt = nil }
                    restButton("+15", "15 seconds more rest", id: "restPlus") { memory.restEndsAt = end.addingTimeInterval(15) }
                }
            }
            .frame(minHeight: CyHit.min)
        } else {
            Text(plannedRest(e))
                .font(CyFont.callout).foregroundStyle(theme.textSecondary).frame(minHeight: CyHit.min, alignment: .leading)
                .accessibilityIdentifier("restPlanned")
        }
    }
    private func plannedRest(_ e: ExerciseEntry) -> String {
        guard let es = store.activeSession?.exercises, let p = NextSet.pick(es) else { return "" }
        guard let r = NextSet.restAfter(es, logged: p) else { return e.superset != nil ? "No rest inside the round — straight to the next exercise" : "No rest is prescribed for this exercise" }
        return e.superset != nil ? "Rest \(clock(r)) after this round" : "Rest \(clock(r)) after this set"
    }
    private func restButton(_ t: String, _ label: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(t).font(CyFont.label.weight(.semibold)).monospacedDigit().foregroundStyle(theme.textPrimary)
                .frame(minWidth: CyHit.min, minHeight: CyHit.min).contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(label).accessibilityIdentifier(id)
    }

    /// What was just logged, with Undo. Undo lasts until the next set is logged, the workout is saved or discarded.
    @ViewBuilder private func loggedRow(_ s: StrengthSession) -> some View {
        if let m = memory.lastLogged, m.sessionId == s.id {
            HStack(alignment: .firstTextBaseline) {
                Text(m.skippedSets.isEmpty ? "Logged" : "Skipped").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                Text(m.skippedSets.isEmpty ? "Set \(m.number) · \(m.text)" : m.text).font(CyFont.footnote.weight(.semibold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("recorderLogged")
                Spacer(minLength: 8)
                Button("Undo") { undo(m) }
                    .font(CyFont.label.weight(.semibold)).foregroundStyle(theme.accent)
                    .frame(minWidth: CyHit.min, minHeight: CyHit.min).contentShape(Rectangle()).buttonStyle(.plain)
                    .accessibilityHint(m.skippedSets.isEmpty ? "Marks that set as not done again" : "Brings the skipped sets back").accessibilityIdentifier("recorderUndo")
            }
        }
    }

    /// The next exercise is always visible; the options sit behind one ···.
    private func nextRow(_ es: [ExerciseEntry]) -> some View {
        let n = NextSet.following(es)
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("NEXT EXERCISE").font(CyFont.overline).tracking(1.2).foregroundStyle(theme.textSecondary)
                if let n {
                    let e = es[n.entry]
                    Text(e.name).font(CyFont.headline).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Text("\(n.label.map { "\($0) · superset · " } ?? "")\(e.sets.count) × \(e.sets.first.map { "\($0.reps)" } ?? "–")")
                        .font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                } else {
                    Text("This is the last exercise").font(CyFont.headline).foregroundStyle(theme.textPrimary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("recorderNext")
            Spacer(minLength: 8)
            Menu {
                if let p = NextSet.pick(es) {
                    Button { skip(p, wholeExercise: false) } label: { Label("Skip this set", systemImage: "forward.end") }
                    Button { skip(p, wholeExercise: true) } label: { Label("Skip this exercise", systemImage: "forward.end.alt") }
                    Menu {
                        Button("Ordinary reps and weight") { setKind(p, .ordinary) }
                        Button("Timed hold") { setKind(p, .timed) }
                        Button("Bodyweight plus added weight") { setKind(p, .added) }
                        Button("Assisted (band or machine)") { setKind(p, .assisted) }
                    } label: { Label("This exercise is…", systemImage: "slider.horizontal.3") }
                }
                Button { allExercises = true } label: { Label("All exercises · correct a set", systemImage: "list.bullet") }
                Button(role: .destructive) { confirmDiscard = true } label: { Label("Discard workout", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis").font(.body.weight(.bold)).foregroundStyle(theme.textPrimary)
                    .frame(width: CyHit.min, height: CyHit.min).contentShape(Rectangle())
            }
            .accessibilityLabel("Options").accessibilityIdentifier("recorderOptions")
        }
        .padding(.top, CySpace.s)
        .overlay(alignment: .top) { Rectangle().fill(theme.separator).frame(height: 1).accessibilityHidden(true) }
    }

    private func bigButton(_ title: String, id: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.headline).foregroundStyle(theme.textOnAccent)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.accent))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)        // on the button itself (Lab run 12: placed after the padding it was not found as a button)
        .padding(.horizontal, CySpace.l).padding(.vertical, CySpace.s)
    }

    // MARK: actions — every change goes through the existing Store functions

    private func change(_ p: NextSet.Pick, _ f: @escaping (inout SetEntry) -> Void) {
        store.updateActiveSession { s in
            guard var es = s.exercises, es.indices.contains(p.entry), es[p.entry].sets.indices.contains(p.set) else { return }
            f(&es[p.entry].sets[p.set]); s.exercises = es
        }
    }
    private func log(_ s: StrengthSession, _ p: NextSet.Pick, _ e: ExerciseEntry, _ st: SetEntry) {
        change(p) { $0.done = true; $0.skipped = nil }
        memory.lastLogged = .init(sessionId: s.id, entry: p.entry, set: p.set, text: NextSet.setText(st, units), number: p.set + 1)
        let rest = NextSet.restAfter(s.exercises ?? [], logged: p)
        memory.restEndsAt = rest.flatMap { $0 > 0 ? Date().addingTimeInterval(TimeInterval($0)) : nil }
    }
    /// Skips the set on screen, or every set of its exercise that is still waiting. A skipped set is never "done".
    private func skip(_ p: NextSet.Pick, wholeExercise: Bool) {
        guard let s = store.activeSession, let es = s.exercises, es.indices.contains(p.entry) else { return }
        let targets = wholeExercise ? es[p.entry].sets.indices.filter { es[p.entry].sets[$0].isOpen } : [p.set]
        store.updateActiveSession { x in
            guard var e = x.exercises, e.indices.contains(p.entry) else { return }
            for i in targets where e[p.entry].sets.indices.contains(i) { e[p.entry].sets[i].skipped = true }
            x.exercises = e
        }
        memory.restEndsAt = nil
        memory.lastLogged = .init(sessionId: s.id, entry: p.entry, set: p.set, text: wholeExercise ? "\(es[p.entry].name) · \(targets.count) set\(targets.count == 1 ? "" : "s")" : "\(es[p.entry].name) · set \(p.set + 1)",
                                  number: p.set + 1, skippedSets: targets)
    }
    /// Makes the sets of this exercise that are still waiting timed, added-weight, assisted or ordinary sets.
    private func setKind(_ p: NextSet.Pick, _ k: SetEntry.Kind) {
        store.updateActiveSession { x in
            guard var e = x.exercises, e.indices.contains(p.entry) else { return }
            for i in e[p.entry].sets.indices where e[p.entry].sets[i].isOpen { e[p.entry].sets[i] = e[p.entry].sets[i].converted(to: k, stepKg: step) }
            x.exercises = e
        }
    }
    private func undo(_ m: CyRecorderMemory.Logged) {
        if m.skippedSets.isEmpty { change(NextSet.Pick(entry: m.entry, set: m.set, label: nil)) { $0.done = false } }
        else {
            store.updateActiveSession { x in
                guard var e = x.exercises, e.indices.contains(m.entry) else { return }
                for i in m.skippedSets where e[m.entry].sets.indices.contains(i) { e[m.entry].sets[i].skipped = nil }
                x.exercises = e
            }
        }
        memory.clear()
    }
    private func clock(_ s: Int) -> String { let v = max(0, s); return v >= 3600 ? String(format: "%d:%02d:%02d", v / 3600, v / 60 % 60, v % 60) : String(format: "%02d:%02d", v / 60, v % 60) }

    // MARK: finish and save — sheets 06e / 06f. Save first; review afterwards and optional; a failed save keeps everything.

    /// The session's name as the athlete knows it from the plan ("Full body"), or its own name when it is not planned.
    private func sessionTitle(_ s: StrengthSession) -> String {
        if let w = s.workoutId.flatMap({ id in store.plan.first { $0.id == id } }) { return StrengthPrepare.title(w.displayTitle) }
        return s.customName.isEmpty ? "Strength workout" : s.customName
    }
    /// Opening Finish pauses the clock ("paused while you decide"); going back resumes it only if Finish paused it.
    private func beginFinish() {
        store.saveFailure = nil      // a failure reported on another screen is not this workout's
        pausedByFinish = store.activeSession?.pausedAt == nil
        if pausedByFinish { store.pauseActiveSession() }
        finishing = true
    }
    private func backToWorkout() {
        if pausedByFinish { store.resumeActiveSession() }
        pausedByFinish = false; confirmDiscard = false; finishing = false
    }
    private func discard() { store.discardActiveSession(); memory.clear(); confirmDiscard = false; finishing = false; dismiss() }

    private func finishRows(_ f: FinishSummary, failed: Bool) -> [CyFinishRow] {
        var rows = [CyFinishRow(label: "Time", value: f.timeText, id: "finishTime")]
        if f.state == .partial && !failed { rows.append(CyFinishRow(label: "Not done", value: f.notDone, id: "finishNotDone")) }
        else { rows.append(CyFinishRow(label: "Sets", value: f.setsText, id: "finishSets")) }
        if f.skipped > 0 && f.state != .nothing { rows.append(CyFinishRow(label: "Skipped", value: f.skippedText, id: "finishSkipped")) }
        if f.planned { rows.append(CyFinishRow(label: "Plan", value: failed ? "Not marked done yet" : f.planBefore, id: "finishPlan")) }
        return rows
    }
    private func markDoneWithoutDetails(_ s: StrengthSession) {
        guard let wid = s.workoutId else { return }
        store.discardActiveSession(); _ = store.markDone(wid); memory.clear(); finishing = false; dismiss()
    }

    @ViewBuilder private func finishPage(_ s: StrengthSession) -> some View {
        let f = FinishSummary.make(s, title: sessionTitle(s), now: now)
        let overline = "Strength · paused while you decide" + (CycliftLab.isLab ? " · DEMO DATA" : "")
        let failed = store.saveFailure != nil
        let rows = finishRows(f, failed: failed)
        let discardText = f.done == 0 ? "Nothing is logged. The planned session stays open."
                                      : "\(f.done) logged set\(f.done == 1 ? "" : "s") will be deleted. This cannot be undone."
        ZStack {
            if failed {
                // X6 — never shown as success. The session is still active; Try again writes exactly one record.
                CyFinishPage(overline: overline, title: "Not saved yet", titleID: "saveFailed",
                             message: "The workout could not be saved. Nothing is lost — it is still on this phone.",
                             rows: rows, primary: "Try again", primaryID: "saveWorkout", onPrimary: save,
                             secondary: "Back to workout", secondaryID: "finishBackToWorkout", onSecondary: backToWorkout,
                             onBack: backToWorkout, onDiscard: { confirmDiscard = true })
            } else if f.state == .nothing {
                // X3 — no Save. "Mark done" is stored as marked, not measured.
                CyFinishPage(overline: overline, title: "Nothing was logged",
                             message: "No sets were recorded, so there is no workout to save.", messageID: "finishNothing",
                             rows: rows, primary: "Back to workout", primaryID: "finishBackToWorkout", onPrimary: backToWorkout,
                             secondary: s.workoutId == nil ? nil : "Mark done without details", secondaryID: "finishMarkDone",
                             onSecondary: { markDoneWithoutDetails(s) },
                             onBack: backToWorkout, onDiscard: { confirmDiscard = true })
            } else {
                // X1 complete / X2 partial — only recorded work is saved, as recorded
                CyFinishPage(overline: overline, title: f.title, status: f.statusLine,
                             rows: rows, primary: "Save", primaryID: "saveWorkout", onPrimary: save,
                             secondary: "Back to workout", secondaryID: "finishBackToWorkout", onSecondary: backToWorkout,
                             onBack: backToWorkout, onDiscard: { confirmDiscard = true })
            }
            if confirmDiscard { CyDiscardDialog(message: discardText, onDiscard: discard, onKeep: { confirmDiscard = false }) }
        }
    }

    /// The one durable save, in five honest states: recorded (the Finish page) → pending ("Saving…") → confirmed
    /// ("Saved": the store wrote it AND the file read back holds it) · failed ("Not saved yet": the session is still
    /// active, Try again writes exactly one record) · unknown ("Save not confirmed": checked again, never assumed).
    /// The save itself is the store's existing `finishActiveSession`; nothing about it is changed here.
    private func save() {
        guard !saving, let active = store.activeSession else { return }
        store.saveFailure = nil
        savedSummary = FinishSummary.make(active, title: sessionTitle(active), now: now)
        saving = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)     // the pending state is shown, not skipped; the session stays active and safe meanwhile
            if UITestSupport.takeFailedSave() {                  // simulator only: take the failure path without touching the store
                store.saveFailure = "This save was made to fail by a test. Nothing was written."
            } else if let s = store.finishActiveSession(rpe: nil, notes: "") {
                memory.clear(); pausedByFinish = false
                let check = store.strengthSaveCheck(s.id)
                if check == .confirmed { saved = s; finishing = false } else { checks = 0; lastCheck = check; unconfirmed = s }
            }
            // otherwise the session is still active and `saveFailure` says why: the page shows "Not saved yet"
            saving = false
        }
    }
    /// "Check again" reads first. An unreadable file is inconclusive (not a failure): it is only read again. A file that
    /// could be read and does not hold the workout is written again from the store's current state — the same record,
    /// the same identifier — and read back. Neither path can create a second workout.
    private func checkAgain(_ s: StrengthSession) {
        checks += 1
        var result = store.strengthSaveCheck(s.id)
        if result == .notOnDisk, store.writeAgain() { result = store.strengthSaveCheck(s.id) }
        lastCheck = result
        if result == .confirmed { saved = s; unconfirmed = nil; finishing = false }
    }
    private func unconfirmedPage(_ s: StrengthSession) -> some View {
        let f = savedSummary
        var rows = [CyFinishRow(label: "Sets", value: (f?.setsText ?? "\((s.exercises ?? []).reduce(0) { $0 + $1.sets.count })") + " · kept", id: "unconfirmedSets")]
        if s.workoutId != nil { rows.append(CyFinishRow(label: "Plan", value: "Not confirmed", id: "unconfirmedPlan")) }
        if checks > 0 {
            let why = lastCheck == .unreadable ? "the file could not be read" : "the file does not hold it yet"
            rows.append(CyFinishRow(label: "Checked again", value: "\(checks) time\(checks == 1 ? "" : "s") · \(why)", id: "unconfirmedChecks"))
        }
        // The workout is in the app and is not lost: it stays in this app's history and is written with the next save.
        return CyFinishPage(title: "Save not confirmed", titleID: "saveUnconfirmed",
                            message: "Cyclift could not confirm that the workout was saved. It is kept here until that is known.",
                            rows: rows, primary: "Check again", primaryID: "saveCheckAgain", onPrimary: { checkAgain(s) },
                            secondary: "Close", secondaryID: "unconfirmedClose", onSecondary: { dismiss() },
                            backLabel: "Close", onBack: { dismiss() }, pageID: "unconfirmedV14")
    }

    private func savedView(_ s: StrengthSession) -> some View {
        let f = savedSummary
        let title = f?.title ?? (s.customName.isEmpty ? "Strength workout" : s.customName)
        let sets = (s.exercises ?? []).reduce(0) { $0 + $1.sets.count }
        // the plan line is read back from the plan itself: it says "Marked done" only when the plan says so
        let marked = s.workoutId.flatMap { id in store.plan.first { $0.id == id } }.map { store.status($0).isCompleted }
        let skipped = (s.exercises ?? []).reduce(0) { $0 + ($1.skippedSets ?? 0) }
        var rows = [CyFinishRow(label: "Workout", value: "Saved on this phone", id: "savedWorkout")]
        if skipped > 0 { rows.append(CyFinishRow(label: "Skipped", value: "\(skipped) set\(skipped == 1 ? "" : "s") · not counted as done", id: "saveSkipped")) }
        if let m = marked { rows.append(CyFinishRow(label: "Plan", value: m ? (f?.state == .partial ? "Marked done · partial" : "Marked done") : "Not marked done", id: "savedPlan")) }
        return CySavedPage(subtitle: f?.savedLine ?? "\(title) · \(sets) sets", rows: rows, onReview: { review = true }, onDone: { dismiss() })
    }
}
