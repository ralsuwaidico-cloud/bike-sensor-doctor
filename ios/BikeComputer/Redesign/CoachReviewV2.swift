import SwiftUI

// Coach — "Review change" (design sheet G1, screen 2: "Proposal: before and after").
// Opened from Review on an open suggestion of the Coach page. Shown where CyProduct.redesign is on; the existing app
// keeps its own sheet (HomeProposalSheet), and so do the hybrid coach's proposals, which have their own preview.
//
// WHAT IS REAL HERE
// • The values under NOW are read from the planned session as it is. The values under PROPOSED are that session passed
//   through the engine's own `AdaptiveRules.apply` — the function that changes the plan on approval. Nothing is typed in.
// • Evidence rows are the athlete's own logged sessions the progression rule read (CoachReview.strengthEvidence).
//   A value that was not recorded is said to be not recorded.
// • The Coach here is the rules-based engine. No AI model is involved and the page says so.
// • Approve calls `Store.acceptAdaptiveProposal`, Decline calls `Store.dismissAdaptiveProposal` — exactly what the
//   existing sheet calls. Not now postpones through the Coach's own file (CoachPostpone): the suggestion stays open
//   and the plan is not touched. This page has no apply logic of its own.
// • An approval that did not reach storage is not presented as approved: the page stays and says so.

/// Reads for the review page and the timeline. Nothing here writes.
enum CoachReviewData {
    /// The planned exercises of a session as the engine sees them now: its own planned sets when it has them, else
    /// the assigned routine as originally planned (the same source `Store.applyAdaptation` applies changes to).
    static func entries(_ store: Store, _ w: Workout) -> [ExerciseEntry] {
        if let e = w.plannedEntries, !e.isEmpty { return e }
        return store.originalEntries(for: w)
    }
    static func model(_ store: Store, _ p: AdaptiveProposal, now: Date = Date()) -> CoachReviewModel {
        let w = p.adjustments.first.flatMap { a in store.plan.first { $0.id == a.workoutId } }
        var input = CoachReview.Input(proposal: p)
        input.workout = w
        input.sessionTitle = w.map { $0.displayTitle(routine: store.routine(for: $0)) }
        input.entries = w.map { entries(store, $0) } ?? []
        input.strength = store.strength
        input.units = store.settings.units
        input.painAreas = store.activePainAreas(now: now).map { $0.title }
        input.now = now
        return CoachReview.model(input)
    }
}

struct CoachReviewScreen: View {
    @EnvironmentObject private var store: Store
    @Environment(\.cyTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let proposalId: String
    /// "Not now": the Coach page's own postponement (CoachCenter.postpone → CoachPostpone). Never an approval or a rejection.
    let onPostpone: (String) -> Void
    /// The page as it was when it opened, so it does not empty itself in the moment a decision removes the proposal.
    @State private var shown: CoachReviewModel? = nil
    /// The approval was made but the athlete record could not be written.
    @State private var notSaved = false

    private var proposal: AdaptiveProposal? { store.adaptiveProposals.first { $0.id == proposalId } }

    var body: some View {
        VStack(spacing: 0) {
            bar
            if let m = shown { page(m) } else { gone }
        }
        .background(theme.background.ignoresSafeArea())
        .onAppear { if shown == nil, let p = proposal { shown = CoachReviewData.model(store, p) } }
        .presentationDetents([.large])
        .interactiveDismissDisabled(notSaved)
    }

    // MARK: bar — "Cancel" on the left, "Review change" centred (G1)

    private var bar: some View {
        ZStack {
            Text("Review change").font(CyDyn.f(17, .semibold)).foregroundStyle(theme.textPrimary)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("coachReviewTitle")
            HStack {
                Button { dismiss() } label: {
                    Text(notSaved ? "Close" : "Cancel").font(CyDyn.f(16)).foregroundStyle(theme.accent)
                        .frame(minWidth: CyHit.min, minHeight: CyHit.min, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Closes the review. Nothing changes")
                .accessibilityIdentifier("coachReviewCancel")
                Spacer(minLength: 0)
                if CycliftLab.isLab { tag("DEMO DATA", theme.warning) }
            }
        }
        .padding(.horizontal, CySpace.l).padding(.top, CySpace.s)
    }

    private var gone: some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            Text("This suggestion no longer applies.").font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textPrimary)
            Text("The Coach withdrew it or it was already decided. Nothing changed.").font(CyDyn.f(13)).foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(CySpace.l).frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("coachReviewGone")
    }

    private func page(_ m: CoachReviewModel) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: CySpace.m) {
                    changeCard(m)
                    evidenceCard(m)
                    elseCard(m)
                    needsYou(m)
                    if notSaved { notSavedCard } else { actionsNote(m) }
                }
                .padding(.horizontal, CySpace.l).padding(.top, CySpace.s).padding(.bottom, CySpace.l)
            }
            .accessibilityIdentifier("coachReview")
            // the three decisions stay on screen whatever the text size (they are never below the fold)
            if !notSaved {
                actions(m).padding(.horizontal, CySpace.l).padding(.top, CySpace.s).padding(.bottom, CySpace.s)
                    .background(theme.background)
            }
        }
    }

    // MARK: pieces

    private func tag(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(c).lineLimit(1).fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(c.opacity(0.8), lineWidth: 1))
    }
    private func card<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        let shape = RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous)
        return VStack(alignment: .leading, spacing: CySpace.s) { content() }
            .padding(CySpace.m).frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(theme.surface))
            .overlay(shape.strokeBorder(theme.border.opacity(theme.id == .highContrast ? 1 : 0.5), lineWidth: 1))
    }

    /// Who produced it, its state, what it is about, NOW and PROPOSED, and the rule's reason in its own words.
    private func changeCard(_ m: CoachReviewModel) -> some View {
        card {
            HStack(spacing: 6) {
                tag("RULES", theme.success)
                    .accessibilityLabel("Rules-based, not AI").accessibilityIdentifier("coachReviewRules")
                Text(m.stateTag).font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier("coachReviewState")
                Spacer(minLength: 0)
            }
            Text(m.title).font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("coachReviewSubject")
            ForEach(Array(m.changes.enumerated()), id: \.element.id) { n, c in changeRow(c, index: n, labelled: m.changes.count > 1) }
            if m.changes.isEmpty {
                Text(m.text).font(CyDyn.f(14, .semibold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("coachReviewAdvice")
            }
            Text("Why: \(m.why)").font(CyDyn.f(13)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("coachReviewWhy")
        }
    }

    @ViewBuilder private func changeRow(_ c: CoachReviewModel.Change, index: Int, labelled: Bool) -> some View {
        let suffix = index == 0 ? "" : "-\(index)"
        if labelled { Text(c.label).font(CyDyn.f(13, .semibold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true) }
        if let b = c.before, let a = c.after {
            HStack(alignment: .top, spacing: CySpace.s) {
                valueBox("NOW", b, c.beforeSub, strong: false, id: "coachReviewBefore" + suffix)
                valueBox("PROPOSED", a, c.afterSub, strong: true, id: "coachReviewAfter" + suffix)
            }
        } else {
            // the planned session could not be read: the engine's own sentence, never made-up values
            Text(c.summary).font(CyDyn.f(14, .semibold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("coachReviewSummary" + suffix)
        }
    }

    private func valueBox(_ label: String, _ value: String, _ sub: String?, strong: Bool, id: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(theme.textSecondary)
            Text(value).font(CyDyn.f(20, .bold)).monospacedDigit().foregroundStyle(theme.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
            if let sub { Text(sub).font(CyDyn.f(12)).monospacedDigit().foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(CySpace.m).frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(theme.background))
        .overlay(shape.strokeBorder(strong ? theme.accent.opacity(0.7) : theme.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label == "NOW" ? "Now" : "Proposed"): \(value)\(sub.map { ", \($0)" } ?? "")")
        .accessibilityIdentifier(id)
    }

    /// The athlete's own records the rule read. No row is ever a placeholder.
    private func evidenceCard(_ m: CoachReviewModel) -> some View {
        card {
            Text("Evidence").font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
            ForEach(m.evidence) { e in
                VStack(spacing: CySpace.s) {
                    Rectangle().fill(theme.border.opacity(0.5)).frame(height: 1).accessibilityHidden(true)
                    HStack(alignment: .firstTextBaseline, spacing: CySpace.s) {
                        Text(e.label).font(CyDyn.f(13)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: CySpace.s)
                        Text(e.value).font(CyDyn.f(13, .semibold)).monospacedDigit().foregroundStyle(theme.textPrimary).multilineTextAlignment(.trailing)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(e.label): \(e.value)")
                .accessibilityIdentifier("coachReviewEvidence-\(e.id)")
            }
            if let n = m.evidenceNote {
                Text(n).font(CyDyn.f(13)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("coachReviewEvidenceNote")
            }
            Text("From your own logged sessions. Checked by written rules — no AI model is used.")
                .font(CyDyn.f(11)).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("coachReviewRulesNote")
        }
    }

    private func elseCard(_ m: CoachReviewModel) -> some View {
        card {
            Text("What else changes").font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
            Text(m.elseChanges).font(CyDyn.f(13)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("coachReviewElse")
        }
    }

    private func needsYou(_ m: CoachReviewModel) -> some View {
        Text(m.needsYou).font(CyDyn.f(13)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            .padding(CySpace.m).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .accessibilityIdentifier("coachReviewNeedsYou")
    }

    // MARK: actions — Decline · Approve (G1), and Not now beneath (owner decision of 19 Nov 2026: Not now postpones).
    // Pinned under the page so all three are always reachable.

    private func outline(_ title: String) -> some View {
        Text(title).font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textSecondary)
            .frame(maxWidth: .infinity, minHeight: CyHit.min)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.border, lineWidth: 1.2))
            .contentShape(Rectangle())
    }
    private func filled(_ title: String) -> some View {
        Text(title).font(CyDyn.f(15, .bold)).foregroundStyle(theme.textOnAccent)
            .frame(maxWidth: .infinity, minHeight: CyHit.min)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.accent))
            .contentShape(Rectangle())
    }

    private func actions(_ m: CoachReviewModel) -> some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            HStack(spacing: CySpace.m) {
                Button { decline() } label: { outline(m.canApprove ? "Decline" : "Dismiss") }
                    .buttonStyle(.plain)
                    .accessibilityHint("Rejects the suggestion. Your plan stays as it is")
                    .accessibilityIdentifier("proposalDecline")
                if m.canApprove {
                    Button { approve() } label: { filled("Approve") }
                        .buttonStyle(.plain)
                        .accessibilityHint("Saves this change to your plan")
                        .accessibilityIdentifier("proposalAccept")
                }
            }
            Button { postpone() } label: { outline("Not now") }
                .buttonStyle(.plain)
                .accessibilityHint("Postpones the decision. The suggestion stays open")
                .accessibilityIdentifier("proposalNotNow")
        }
    }
    private func actionsNote(_ m: CoachReviewModel) -> some View {
        Text(m.canApprove
                 ? "Approve saves the change and adds it to the timeline with Undo. Not now keeps the suggestion open and changes nothing. Decline is remembered: it is not offered again for the same session."
                 : "Not now keeps this note open. Dismiss removes it. Neither changes your plan.")
                .font(CyDyn.f(11)).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("coachReviewActionsNote")
    }

    /// The approval is in the app's memory but the athlete record could not be written. Said plainly; never "Approved".
    private var notSavedCard: some View {
        card {
            tag("NOT SAVED", theme.danger).accessibilityIdentifier("coachReviewNotSaved")
            Text("Your approval could not be saved").font(CyDyn.f(15, .semibold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            Text("The app could not write to storage, so this change is not confirmed. Free some space and try again.")
                .font(CyDyn.f(13)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            Button { retry() } label: { filled("Try again") }
                .buttonStyle(.plain).accessibilityIdentifier("coachReviewRetry")
        }
    }

    // The same calls as the existing sheet (HomeProposalSheet): accept / dismiss on the Store, postpone via the Coach file.
    private func approve() {
        guard let p = proposal else { dismiss(); return }
        let ok = store.acceptAdaptiveProposal(p)
        if ok && store.lastSaveError == nil { dismiss() } else if ok { notSaved = true }
    }
    private func decline() {
        if let p = proposal { store.dismissAdaptiveProposal(p) }
        dismiss()
    }
    private func postpone() {
        if let p = proposal { onPostpone(p.id) }
        dismiss()
    }
    private func retry() {
        if store.writeAgain() { notSaved = false; dismiss() }
    }
}
