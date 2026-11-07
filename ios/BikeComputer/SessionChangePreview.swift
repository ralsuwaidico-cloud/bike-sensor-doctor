import SwiftUI

// MARK: - Phase 1 rebuild fix: the before/after preview of a session change
// Every significant change (type, duration, supersets, a session turned into strength) — from the edit sheets, Home swap,
// the plan's budget fix and accepted coach suggestions — lands here. Nothing is saved until Apply; Cancel discards the
// proposal and leaves the session exactly as it was. A blocked change shows the conflict and the alternatives; it is never
// relabelled or swapped for a different split.

/// Presents the preview for a proposal id held by the store.
struct SessionChangeSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State var proposalId: UUID
    /// Set when the change comes from a coach suggestion (Apply records it for the coach card's Undo).
    var coach: CoachProposal? = nil
    /// Called after a successful Apply (the caller closes its own sheet).
    var onApplied: () -> Void = {}
    @State private var notice: String? = nil
    @State private var showEquipment = false

    var body: some View {
        NavigationStack {
            Group {
                if let p = store.pendingProposals[proposalId] {
                    SessionChangePreviewContent(p: p, units: store.settings.units, notice: notice) { action in handle(action, p) }
                } else {
                    VStack(spacing: DS.m) {
                        Text("This change is no longer available. Nothing was saved.").font(.body).multilineTextAlignment(.center)
                        Button("Close") { dismiss() }.buttonStyle(.bordered).controlSize(.large)
                    }.padding()
                }
            }
            .navigationTitle("Review the change").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.discardProposal(proposalId); dismiss() }.accessibilityIdentifier("changeCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    let blocked = store.pendingProposals[proposalId]?.report.outcome == .block
                    Button("Apply") { apply() }.bold().disabled(blocked || store.pendingProposals[proposalId] == nil).accessibilityIdentifier("changeApply")
                }
            }
            .sheet(isPresented: $showEquipment, onDismiss: { rebuild(note: "Rebuilt with your equipment.") { _ in } }) {
                NavigationStack { EquipmentPage().navigationTitle("Equipment").toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showEquipment = false } } } }
            }
        }
        .interactiveDismissDisabled()        // Cancel or Apply, never a half-decision by swiping
    }

    private func apply() {
        let r: CommitResult = coach.map { store.commitCoachChange($0, proposalId: proposalId) } ?? store.commit(proposalId: proposalId, confirmed: true)
        switch r {
        case .applied: onApplied(); dismiss()
        case .stale: rebuild(note: "Something this change depends on changed while you were looking (your plan, equipment or health status). Here is the updated version; nothing was saved.") { _ in }
        case .blocked(let ids): notice = ids.contains("SAFE-001") ? "Training is paused by your health check, so nothing was changed." : "This change can't be applied (\(ids.joined(separator: ", "))). Nothing was saved."
        case .needsConfirmation, .notValidated: notice = "Nothing was saved. Please review the change again."
        }
    }

    private func rebuild(note: String, _ adjust: @escaping (inout SessionChangeRequest) -> Void) {
        if let id = store.repropose(proposalId, adjust: adjust) { proposalId = id; notice = note }
        else { notice = "The session is no longer in your plan. Nothing was saved." }
    }

    private func handle(_ a: PreviewAction, _ p: SessionChangeProposal) {
        switch a {
        case .keepAsPlanned: store.discardProposal(proposalId); dismiss()
        case .allowMinutes(let m): rebuild(note: "Rebuilt for \(m) min.") { $0.minutes = m }
        case .setEquipment: showEquipment = true
        case .detachRoutine: rebuild(note: "Rebuilt without the routine for this session.") { $0.detachRoutine = true }
        case .supersets(let on): rebuild(note: on ? "Rebuilt with supersets." : "Rebuilt with straight sets.") { $0.prefersSupersets = on }
        }
    }
}

enum PreviewAction { case keepAsPlanned, allowMinutes(Int), setEquipment, detachRoutine, supersets(Bool) }

/// The preview body (separate so tests and screenshots can render it without a store sheet).
struct SessionChangePreviewContent: View {
    let p: SessionChangeProposal
    let units: AppSettings.Units
    var notice: String? = nil
    let act: (PreviewAction) -> Void

    private var blocked: Bool { p.report.outcome == .block }
    private var blockers: [ValidationIssue] { p.report.issues.filter { $0.outcome == .block } }
    private var checks: [ValidationIssue] { p.report.issues.filter { $0.outcome != .block && ($0.needsConfirmation || $0.severity != .info) } }

    var body: some View {
        List {
            if let n = notice {
                Section { Text(n).font(.footnote).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("changeNotice") }
            }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text(timeLine).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("changeTime")
                }.padding(.vertical, 4)
            }
            if blocked {
                Section {
                    ForEach(Array(blockers.enumerated()), id: \.offset) { pair in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pair.element.explanation).font(.body).foregroundStyle(BC.stale).fixedSize(horizontal: false, vertical: true)
                            Text(pair.element.remedy).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    alternatives
                } header: { Text("Can't apply this change") } footer: { Text("Nothing is changed until you pick an option. The session is never relabelled or turned into a different type to make it fit.") }
                    .accessibilityIdentifier("changeConflict")
            }
            if !checks.isEmpty {
                Section("Please check") {
                    ForEach(Array(checks.enumerated()), id: \.offset) { pair in Text(pair.element.explanation).font(.footnote).fixedSize(horizontal: false, vertical: true) }
                }
            }
            Section {
                entryList(p.afterEntries, logged: Set(p.preservedLogged.map(\.exerciseId)))
            } header: { Text(blocked ? "What the rebuild produced (not saved)" : "After") } footer: { if !p.preservedLogged.isEmpty { Text("Sets you have already done are kept exactly as logged.") } }
            Section("Before") { entryList(p.beforeEntries, logged: []) }
            if p.request.focus != nil || p.request.minutes != nil, p.after.kind == .strength, !blocked {
                Section {
                    let on = p.request.prefersSupersets == true
                    Button(on ? "Use straight sets instead" : "Use supersets to save time") { act(.supersets(!on)) }.accessibilityIdentifier("changeSupersets")
                } footer: { Text("Supersets pair two non-competing exercises back to back.") }
            }
            Section("This week") { ForEach(p.weekly, id: \.self) { Text($0).font(.footnote).fixedSize(horizontal: false, vertical: true) } }
            if let notes = p.after.rationale?.notes, !notes.isEmpty, !blocked {
                Section("Why") { ForEach(Array(notes.enumerated()), id: \.offset) { pair in Text(pair.element).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) } }
            }
        }
        .accessibilityIdentifier("changePreview")
    }

    private var title: String {
        let b = p.before, a = p.after
        if b.kind != a.kind { return "\(b.kind.title) → \(a.displayTitle)" }
        if b.strengthFocus != a.strengthFocus { return "\(b.strengthFocus?.title ?? "Strength") → \(a.strengthFocus?.title ?? "Strength")" }
        return a.displayTitle
    }
    private var timeLine: String {
        var parts: [String] = []
        if p.before.minutes != p.after.minutes { parts.append("Time limit \(p.before.minutes) → \(p.after.minutes) min") } else { parts.append("Time limit \(p.after.minutes) min") }
        let b = p.beforeEstimate.map { "\(Int($0.rounded(.up))) min" } ?? "—"
        let a = p.report.estimatedMinutes.map { "\(Int($0.rounded(.up))) min" } ?? "—"
        parts.append("estimated \(b) → \(a)")
        let sb = p.beforeEntries.reduce(0) { $0 + $1.sets.count }, sa = p.afterEntries.reduce(0) { $0 + $1.sets.count }
        parts.append("\(sb) → \(sa) sets")
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var alternatives: some View {
        Button("Keep the session as planned") { act(.keepAsPlanned) }.accessibilityIdentifier("altKeep")
        if p.report.has("TIME-001"), let e = p.report.estimatedMinutes { let m = Int(e.rounded(.up)) + 1; Button("Allow \(m) min instead") { act(.allowMinutes(m)) }.accessibilityIdentifier("altAllowTime") }
        if p.report.has("EQUIP-002") || p.report.has("EQUIP-001") { Button("Set my equipment") { act(.setEquipment) }.accessibilityIdentifier("altEquipment") }
        if p.report.has("ROUTINE-001") && !p.request.detachRoutine { Button("Rebuild without my routine (this session only)") { act(.detachRoutine) } }
    }

    @ViewBuilder private func entryList(_ es: [ExerciseEntry], logged: Set<String>) -> some View {
        if es.isEmpty { Text("No exercises").foregroundStyle(.secondary) }
        ForEach(Array(es.enumerated()), id: \.offset) { pair in
            let e = pair.element
            HStack(alignment: .firstTextBaseline, spacing: DS.s) {
                if let g = e.superset { Text(g).font(.caption.weight(.heavy)).padding(4).background(BC.accent.opacity(0.18), in: Circle()).accessibilityLabel("superset \(g)") }
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.name).font(.body.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    Text(dose(e, done: logged.contains(e.exerciseId))).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("previewEntry")
        }
    }
    private func dose(_ e: ExerciseEntry, done: Bool) -> String {
        let reps = e.sets.map(\.reps)
        let lo = reps.min() ?? 0, hi = reps.max() ?? 0
        let hold = DurationModel.isHoldName(e.name)
        var t = "\(e.sets.count) × \(lo == hi ? "\(lo)" : "\(lo)–\(hi)")\(hold ? " s" : "")\(e.sets.first?.unilateral == true ? " per side" : "")"
        if let w = e.sets.first?.weightKg { t += " · \(WeightFmt.text(w, units))" }
        if let r = e.restSeconds { t += " · rest \(RestPrescription.text(r))" }
        if done { t += " · \(e.doneSets.count) done (kept)" }
        return t
    }
}

/// Identifiable wrapper for `.sheet(item:)`.
struct PreviewRef: Identifiable, Equatable { let id: UUID }

/// The result of an edit request from a screen.
enum EditOutcome: Equatable { case saved, preview(UUID), refused(String) }

extension Store {
    /// Screens call this instead of `edit`: a significant change opens the preview (nothing saved yet); other edits are
    /// saved directly; a change that cannot be prepared is refused with a sentence to show.
    func requestEdit(_ w: Workout, prefersSupersets: Bool? = nil) -> EditOutcome {
        lastProposalId = nil
        if let old = plan.first(where: { $0.id == w.id }), old.done, Store.significantChange(from: old, to: w, prefersSupersets: prefersSupersets) != nil {
            return .refused("This session is already logged. Its logged sets stay exactly as recorded; add a new session instead.")
        }
        switch edit(w, prefersSupersets: prefersSupersets) {
        case .applied: return .saved
        case .needsConfirmation, .blocked:
            if let id = lastProposalId, pendingProposals[id] != nil { return .preview(id) }
            return .refused("This change couldn't be prepared. Nothing was saved.")
        case .stale, .notValidated: return .refused("Nothing was saved. Please try again.")
        }
    }
}

// MARK: - RC3 / ENG-J2: week-level change preview (profile, equipment, days, minutes, goals → planned sessions)
/// Shows `store.pendingPlanChanges[proposalId]`. Nothing is saved until Apply; Cancel discards it. Completed workouts and
/// history are never in scope.
struct PlanChangeSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let proposalId: UUID
    /// Called after a successful Apply.
    var onApplied: () -> Void = {}
    @State private var stale = false
    @State private var emptyStrength: [String] = []
    private func recalc(_ p: PlanChangeProposal) {
        emptyStrength = EmptyStrengthCheck.warnings(for: p.after, ctx: store.plannerContext()).map { "\($0.workout.date.dayAndDate): \($0.finding.text)" }
    }
    var body: some View {
        NavigationStack {
            Group {
                if let p = store.pendingPlanChanges[proposalId] {
                    // APP-035: recalculated on the exact sessions Apply would save (on open and whenever the proposal changes)
                    PlanChangeContent(p: p, stale: stale, emptyStrength: emptyStrength)
                        .onAppear { recalc(p) }
                        .onChange(of: p.after) { _, _ in recalc(p) }
                } else {
                    VStack(spacing: DS.m) {
                        Text("This change is no longer available. Nothing was saved.").font(.body).multilineTextAlignment(.center)
                        Button("Close") { dismiss() }.buttonStyle(.bordered).controlSize(.large)
                    }.padding()
                }
            }
            .navigationTitle("Review the change").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { store.discardPlanChange(proposalId); dismiss() }.accessibilityIdentifier("planChangeCancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        if store.applyPlanChange(proposalId) { onApplied(); dismiss() } else { stale = true }
                    }
                    .bold().disabled(store.pendingPlanChanges[proposalId] == nil).accessibilityIdentifier("planChangeApply")
                }
            }
        }
        .interactiveDismissDisabled()
    }
}

/// The preview body (separate so tests and screenshots can render it without a store sheet).
struct PlanChangeContent: View {
    let p: PlanChangeProposal
    var stale = false
    /// APP-035: strength sessions in `after` that the coach cannot fill, with the reason (empty = none).
    var emptyStrength: [String] = []
    var body: some View {
        List {
            if stale {
                Section { Text("Your plan changed while you were looking, so nothing was saved. Close and try again.").font(.footnote).fixedSize(horizontal: false, vertical: true) }
            }
            if !emptyStrength.isEmpty {
                Section {
                    ForEach(emptyStrength, id: \.self) { Text($0).font(.footnote).fixedSize(horizontal: false, vertical: true) }
                } header: { Text("Strength sessions without exercises") } footer: { Text("You can still apply; these sessions count as planned strength time. Equipment and Avoided exercises are in Profile.") }
                .accessibilityIdentifier("planChangeEmptyStrength")
            }
            if !p.changesSessions {
                Section { Text("No planned sessions change. Apply saves your settings.").font(.body).fixedSize(horizontal: false, vertical: true) }
            }
            if !p.summary.isEmpty {
                Section("What changes") { ForEach(p.summary, id: \.self) { Text($0).font(.footnote).fixedSize(horizontal: false, vertical: true) } }
            }
            if !p.after.isEmpty {
                Section("After") { ForEach(p.after.sorted { $0.date < $1.date }) { w in PlanChangeRow(w: w) } }
            }
            if !p.before.isEmpty {
                Section("Before") { ForEach(p.before.sorted { $0.date < $1.date }) { w in PlanChangeRow(w: w) } }
            }
            if !p.kept.isEmpty {
                Section {
                    ForEach(p.kept.sorted { $0.date < $1.date }) { w in PlanChangeRow(w: w) }
                } header: { Text("Kept as they are") } footer: { Text("Sessions you changed by hand, fixed or started stay as they are.") }
            }
            Section { Text("Completed workouts and your history are never changed.").font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .accessibilityIdentifier("planChangePreview")
    }
}

struct PlanChangeRow: View {
    let w: Workout
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.s) {
            Text(w.date.formatted(.dateTime.weekday(.abbreviated).day())).font(.footnote.weight(.semibold)).monospacedDigit().frame(minWidth: 52, alignment: .leading)
            Text(w.displayTitle).font(.body).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DS.s)
            if w.kind != .rest { Text("\(w.minutes) min").font(.footnote).foregroundStyle(.secondary).monospacedDigit() }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - RC3 / ENG-J3: plan versions (read-only history) with Undo as a new, previewed change
struct PlanVersionsView: View {
    @EnvironmentObject private var store: Store
    @State private var preview: PreviewRef? = nil
    var body: some View {
        List {
            if store.planVersions.isEmpty {
                Text("No plan changes yet.").foregroundStyle(.secondary)
            }
            ForEach(Array(store.planVersions.reversed())) { v in
                NavigationLink {
                    PlanVersionDetail(v: v, blocked: store.undoBlockedReason(version: v.id)) { if let id = store.proposeUndo(version: v.id) { preview = PreviewRef(id: id) } }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(v.cause.title).font(.body.weight(.semibold))
                        Text("\(v.createdAt.formatted(date: .abbreviated, time: .shortened)) · from \(v.effectiveDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("planVersionRow")
            }
        }
        .navigationTitle("Plan changes")
        .sheet(item: $preview) { r in PlanChangeSheet(proposalId: r.id) }
    }
}

struct PlanVersionDetail: View {
    let v: PlanVersion
    /// Why Undo is not offered (a later change would be overwritten); nil = Undo available. Both Undo buttons share it.
    var blocked: String? = nil
    var undo: () -> Void
    var body: some View {
        List {
            if !v.summary.isEmpty { Section("What changed") { ForEach(v.summary, id: \.self) { Text($0).font(.footnote).fixedSize(horizontal: false, vertical: true) } } }
            Section("After") { ForEach(v.after.sorted { $0.date < $1.date }) { w in PlanChangeRow(w: w) } }
            Section("Before") { ForEach(v.before.sorted { $0.date < $1.date }) { w in PlanChangeRow(w: w) } }
            Section {
                Button("Undo this change") { undo() }.frame(minHeight: DS.minTap).disabled(blocked != nil).accessibilityIdentifier("planVersionUndoBottom")
            } footer: { Text(blocked ?? "Undo shows a preview first. Sessions already done stay as they are.").accessibilityIdentifier(blocked == nil ? "planVersionUndoNote" : "planVersionUndoBlocked") }
        }
        .navigationTitle(v.cause.title).navigationBarTitleDisplayMode(.inline)
        // run 137: at large text the Undo row sat below a long before/after list — the main action is always in the bar
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Undo") { undo() }.disabled(blocked != nil).accessibilityLabel("Undo this change").accessibilityHint(blocked ?? "Shows a preview first").accessibilityIdentifier("planVersionUndo") } }
    }
}
