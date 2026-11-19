import SwiftUI

// Plan › Add a goal in the redesign: sheet B3 (selection), sheet B4 step 1 (set-up) and step 2 (program preview),
// visual direction B. Reached only from the redesigned Plan (PlanV2Host); production keeps the existing Goals page.
//
// One goal model, one planner, one approval path:
//   • the goals are the athlete record's own list and main goal (PlanGoalV2 reads them as the Goals page does);
//   • the preview is the planner's own proposal — `Store.proposePlanChange(cause: .goal, inputs:)`, the function behind
//     `changeTraining` — so "now → after approval" is exactly what Approve would save;
//   • Approve calls `Store.applyPlanChange`, the same call the existing "Review the change" sheet makes.
// Nothing is saved before Approve. Adjust, Not now, the back button and swiping the sheet away all discard the proposal.
// Sheet B5 (Coach planning proposal) is not drawn here: the planner's goal proposal is not a Coach item and has no
// postponed state, so its before/after lives in step 2 of this flow.

struct PlanGoalFlow: View {
    @EnvironmentObject private var store: Store
    @Environment(\.cyTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Binding var detent: PresentationDetent
    static let listDetent = PresentationDetent.fraction(0.64)

    private enum Step { case list, setup, preview }
    @State private var step: Step = .list
    @State private var category: PlanGoalV2.Category? = nil
    @State private var goal: GoalID? = nil
    @State private var priority: PlanGoalV2.Priority = .secondary
    @State private var removing = false
    @State private var proposal: UUID? = nil
    @State private var stale = false
    @State private var emptyStrength: [String] = []

    private var held: [GoalID] { PlanGoalV2.held(store.profile) }
    private var heldPrimary: GoalID? { PlanGoalV2.heldPrimary(store.profile) }

    var body: some View {
        ZStack(alignment: .top) {
            theme.background.ignoresSafeArea()
            switch step {
            case .list: list
            case .setup: setup
            case .preview: preview
            }
        }
        .onDisappear { discard() }
    }

    private func discard() {
        if let id = proposal { store.discardPlanChange(id) }
        proposal = nil
    }

    // MARK: B3 — selection

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: CySpace.s) {
                    Text("Add a goal").font(CyDyn.f(20, .bold)).foregroundStyle(theme.textPrimary)
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("planGoalSheetTitle")
                    Spacer(minLength: CySpace.s)
                    Text(PlanGoalV2.subtitle(store.profile)).font(CyDyn.f(13)).foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("planGoalSubtitle")
                }
                .padding(.top, 28).padding(.bottom, CySpace.s)
                let cats = PlanGoalV2.categories(for: store.profile.trainingMode)
                ForEach(cats) { c in
                    categoryRow(c)
                    Rectangle().fill(theme.separator).frame(height: 1).padding(.leading, 50)
                }
                Text("Event programmes with a date, health targets, custom goals and adding a sport are not in the app yet, so they are not offered here.")
                    .font(CyDyn.f(12)).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, CySpace.m)
                    .accessibilityIdentifier("planGoalNotOffered")
            }
            .padding(.horizontal, CySpace.l).padding(.bottom, CySpace.xl)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planGoalSheet")
    }

    private func categoryRow(_ c: PlanGoalV2.Category) -> some View {
        Button(action: { open(c) }) {
            HStack(spacing: CySpace.m) {
                Image(systemName: c.icon).font(CyDyn.f(15, .semibold))
                    .foregroundStyle(theme.isDark ? theme.background : theme.surface)
                    .frame(width: 38, height: 38).background(Circle().fill(tint(c.sport)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.title).font(CyDyn.f(15, .bold)).foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(c.detail).font(CyDyn.f(13)).foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: CySpace.xs)
                Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(theme.textSecondary).accessibilityHidden(true)
            }
            .padding(.vertical, 7).frame(minHeight: 54).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("planGoalCategory-\(c.id)")
    }

    private func tint(_ s: GoalID.Sport) -> Color {
        switch s {
        case .cycling: return theme.endurance
        case .strength: return theme.strength
        case .general: return theme.recovery
        }
    }

    private func open(_ c: PlanGoalV2.Category) {
        category = c
        // start on a type the athlete does not hold yet, when the group has one
        let first = c.goals.first { !held.contains($0) } ?? c.goals.first
        select(first)
        removing = false
        stale = false
        detent = .large
        step = .setup
    }

    private func select(_ g: GoalID?) {
        goal = g
        guard let g else { return }
        if held.isEmpty || !PlanGoalV2.canBeSecondary(held: held, goal: g) { priority = .primary }
        else if held.contains(g) { priority = heldPrimary == g ? .primary : .secondary }
        else { priority = .secondary }
    }

    // MARK: B4 step 1 — set-up

    private var setup: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                stepBar(back: "Goals", step: "Step 1 of 2") { step = .list; detent = PlanGoalFlow.listDetent }
                Text(category?.title ?? "Goal").font(CyDyn.f(22, .bold)).foregroundStyle(theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("planGoalSetupTitle")
                    .padding(.top, CySpace.m).padding(.bottom, CySpace.m)
                typeCard
                if let g = goal {
                    Text(GoalInfo.effect(g)).font(CyDyn.f(12)).foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, CySpace.s).padding(.horizontal, 2)
                        .accessibilityIdentifier("planGoalEffect")
                    if g == .event {
                        Text("The app has no event date or phased event programme yet. This sets the planner's event emphasis only.")
                            .font(CyDyn.f(12)).foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, 4).padding(.horizontal, 2)
                            .accessibilityIdentifier("planGoalEventNote")
                    }
                }
                caption("PRIORITY")
                priorityCells
                caption("WHAT THE PLAN WILL USE")
                usesCard
                Text("Missing values are not guessed.").font(CyDyn.f(12)).foregroundStyle(theme.textSecondary)
                    .padding(.top, CySpace.s).padding(.horizontal, 2)
                setupActions.padding(.top, CySpace.l)
            }
            .padding(.horizontal, CySpace.l).padding(.bottom, CySpace.xl)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planGoalSetup")
    }

    private var typeCard: some View {
        let goals = category?.goals ?? []
        return VStack(spacing: 0) {
            ForEach(Array(goals.enumerated()), id: \.offset) { i, g in
                if i > 0 { Rectangle().fill(theme.separator).frame(height: 1).padding(.horizontal, 14) }
                typeRow(g)
            }
        }
        .background(card)
    }

    private func typeRow(_ g: GoalID) -> some View {
        let on = goal == g
        let has = held.contains(g)
        return Button(action: { select(g) }) {
            HStack(spacing: CySpace.s) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(g.title + (has ? (heldPrimary == g ? " · your main goal" : " · already a goal") : ""))
                        .font(CyDyn.f(14, .semibold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Text(GoalInfo.line(g)).font(CyDyn.f(12.5)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: CySpace.xs)
                Image(systemName: on ? "checkmark.circle.fill" : "circle").font(CyDyn.f(17))
                    .foregroundStyle(on ? theme.accent : theme.textTertiary).accessibilityHidden(true)
            }
            .padding(.horizontal, 14).padding(.vertical, 6).frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("planGoalType-\(g.rawValue)")
    }

    private var priorityCells: some View {
        let g = goal
        let secondaryPossible = g.map { PlanGoalV2.canBeSecondary(held: held, goal: $0) } ?? false
        // who stays (or becomes) the main goal when this one is secondary
        let other = heldPrimary.flatMap { $0 == g ? nil : $0 } ?? held.first { $0 != g }
        return HStack(spacing: CySpace.s) {
            priorityCell(.primary, title: "Primary", detail: g.map { "\($0.title) leads the plan" } ?? "", enabled: true)
            priorityCell(.secondary, title: "Secondary",
                         detail: secondaryPossible ? (other.map { "\($0.title) stays the main goal" } ?? "") : "Needs another goal to lead",
                         enabled: secondaryPossible)
        }
    }

    private func priorityCell(_ p: PlanGoalV2.Priority, title: String, detail: String, enabled: Bool) -> some View {
        let on = priority == p
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button(action: { priority = p }) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(CyDyn.f(14, .bold)).foregroundStyle(enabled ? theme.textPrimary : theme.disabledText)
                Text(detail).font(CyDyn.f(12)).foregroundStyle(enabled ? theme.textSecondary : theme.disabledText)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(shape.fill(on ? theme.selectedFill : theme.surface))
            .overlay(shape.strokeBorder(on ? theme.selectedBorder : theme.cardStroke, lineWidth: on ? 2 : theme.borderWidth))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? [.isSelected] : [])
        .accessibilityIdentifier("planGoalPriority-\(p.rawValue)")
    }

    private var usesCard: some View {
        let p = store.profile
        let a = store.effectiveAvailability
        let days = a.days.filter { $0.activity != .rest }.count
        let since = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let recorded = store.rides.filter { $0.start >= since }.count + store.strength.filter { $0.date >= since }.count
        return VStack(spacing: 0) {
            valueRow("Training type", ProfileText.mode(p.trainingMode), id: "planGoalUsesType")
            line
            valueRow("Time available", "\(Fmt.duration(minutes: a.totalMinutes)) a week · \(days) day\(days == 1 ? "" : "s")", id: "planGoalUsesTime")
            line
            valueRow("Recorded, last 4 weeks", "\(recorded) session\(recorded == 1 ? "" : "s")", id: "planGoalUsesRecent")
            if category?.sport == .cycling {
                line
                valueRow("Threshold power", p.ftpKnown ? "\(p.ftpW) W · \(p.ftpHow.label)" : "Not entered", id: "planGoalUsesFTP")
            }
        }
        .background(card)
    }

    private var setupActions: some View {
        let g = goal
        let req = g.map { PlanGoalV2.Request(goal: $0, priority: priority) }
        let nothing = req.map { PlanGoalV2.changesNothing(held: held, primary: heldPrimary, request: $0) } ?? true
        let canRemove = g.map { held.contains($0) && held.count > 1 } ?? false
        return VStack(spacing: CySpace.s) {
            if nothing, g != nil {
                Text("This is how your goals already are. Choose another type or priority to see a change.")
                    .font(CyDyn.f(12.5)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("planGoalNoChange")
            }
            primaryButton("Preview plan changes", id: "planGoalContinue", enabled: !nothing) { makeProposal(remove: false) }
            if canRemove, let g {
                Button(action: { makeProposal(remove: true) }) {
                    Text("Remove \(g.title) from my goals").font(CyDyn.f(14, .semibold)).foregroundStyle(theme.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("planGoalRemove")
            }
        }
    }

    /// Asks the existing planner what the change would do. Nothing is saved: the proposal waits in `pendingPlanChanges`.
    private func makeProposal(remove: Bool) {
        guard let g = goal else { return }
        let req = PlanGoalV2.Request(goal: g, priority: priority, remove: remove)
        guard let out = PlanGoalV2.result(held: held, primary: heldPrimary, request: req) else { return }
        var inputs = store.planInputs
        PlanGoalV2.answers(goals: out.goals, primary: out.primary).apply(to: &inputs)
        discard()
        let id: UUID = store.proposePlanChange(cause: .goal, inputs: inputs)
        proposal = id
        removing = remove
        stale = false
        if let p = store.pendingPlanChanges[id] {
            emptyStrength = EmptyStrengthCheck.warnings(for: p.after, ctx: store.plannerContext()).map { "\($0.workout.date.dayAndDate): \($0.finding.text)" }
        } else { emptyStrength = [] }
        step = .preview
    }

    // MARK: B4 step 2 — program preview

    private var preview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                stepBar(back: "Set-up", step: "Step 2 of 2") { discard(); step = .setup }
                Text("Program preview").font(CyDyn.f(22, .bold)).foregroundStyle(theme.textPrimary)
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("planGoalPreviewTitle")
                    .padding(.top, CySpace.m).padding(.bottom, CySpace.m)
                if let id = proposal, let p = store.pendingPlanChanges[id] {
                    previewBody(p)
                } else {
                    Text(stale ? "Your plan changed while you were looking, so nothing was saved. Go back and preview again."
                               : "This change is no longer available. Nothing was saved.")
                        .font(CyDyn.f(14)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                        .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(card)
                        .accessibilityIdentifier("planGoalStale")
                    secondaryButton("Back to set-up", id: "planGoalAdjust") { discard(); step = .setup }.padding(.top, CySpace.m)
                }
            }
            .padding(.horizontal, CySpace.l).padding(.bottom, CySpace.xl)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planGoalProgramPreview")
    }

    @ViewBuilder private func previewBody(_ p: PlanChangeProposal) -> some View {
        let rows = PlanGoalV2.rows(before: p.before, after: p.after)
        headlineCard(p, changedDays: rows.count)
        caption("GOALS")
        goalsCard(p)
        caption(p.changesSessions ? "PLANNED SESSIONS WOULD CHANGE" : "PLANNED SESSIONS")
        sessionsCard(p, rows: rows)
        if !emptyStrength.isEmpty {
            caption("STRENGTH SESSIONS WITHOUT EXERCISES")
            VStack(alignment: .leading, spacing: 6) {
                ForEach(emptyStrength, id: \.self) { t in
                    Text(t).font(CyDyn.f(12.5)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading).background(card)
            .accessibilityIdentifier("planGoalEmptyStrength")
        }
        Text("Nothing changes until you approve. Completed sessions are never changed.")
            .font(CyDyn.f(12)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            .padding(.top, CySpace.m).padding(.horizontal, 2)
            .accessibilityIdentifier("planGoalPreviewNote")
        primaryButton("Approve these changes", id: "planGoalApprove", enabled: true) { approve(p.id) }
            .padding(.top, CySpace.m)
        HStack(spacing: CySpace.s) {
            secondaryButton("Adjust", id: "planGoalAdjust") { discard(); step = .setup }
            secondaryButton("Not now", id: "planGoalNotNow") { discard(); dismiss() }
        }
        .padding(.top, CySpace.s)
    }

    private func headlineCard(_ p: PlanChangeProposal, changedDays: Int) -> some View {
        let main = p.inputs.profile.effectivePrimaryGoal
        return VStack(alignment: .leading, spacing: 4) {
            Text(PlanGoalV2.headline(changedDays: changedDays, changesSessions: p.changesSessions))
                .font(CyDyn.f(16, .bold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("planGoalHeadline")
            Text(GoalInfo.effect(main) + " This is what the planner would schedule — not a performance prediction.")
                .font(CyDyn.f(13)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.highlightSurface))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
    }

    private func goalsCard(_ p: PlanChangeProposal) -> some View {
        let now = PlanGoalV2.list(PlanGoalV2.held(p.inputsBefore.profile), primary: PlanGoalV2.heldPrimary(p.inputsBefore.profile))
        let after = PlanGoalV2.list(PlanGoalV2.held(p.inputs.profile), primary: PlanGoalV2.heldPrimary(p.inputs.profile))
        return VStack(spacing: 0) {
            valueRow("Now", now, id: "planGoalBefore")
            line
            valueRow("After approval", after, id: "planGoalAfter")
        }
        .background(card)
    }

    private func sessionsCard(_ p: PlanChangeProposal, rows: [PlanGoalV2.ChangeRow]) -> some View {
        let shown = Array(rows.prefix(8))
        return VStack(alignment: .leading, spacing: 0) {
            if !p.changesSessions {
                Text("No planned session changes. Approving saves your goals.")
                    .font(CyDyn.f(13.5)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("planGoalNoSessionChange")
            }
            ForEach(Array(p.summary.enumerated()), id: \.offset) { i, s in
                if i > 0 { line }
                summaryRow(s)
            }
            ForEach(Array(shown.enumerated()), id: \.offset) { i, r in
                if i > 0 || !p.summary.isEmpty || !p.changesSessions { line }
                changeRow(r)
            }
            if rows.count > shown.count {
                line
                Text("+ \(rows.count - shown.count) more day\(rows.count - shown.count == 1 ? "" : "s") in the same pattern")
                    .font(CyDyn.f(12.5)).foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 14).frame(minHeight: 40)
            }
            if !p.kept.isEmpty {
                line
                valueRow("Kept as you set it", "\(p.kept.count) session\(p.kept.count == 1 ? "" : "s") edited or fixed by you", id: "planGoalKept")
            }
        }
        .background(card)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("planGoalSessions")
    }

    private func summaryRow(_ s: String) -> some View {
        let lower = s.lowercased()
        let color: Color = lower.hasPrefix("riding") || lower.hasSuffix("rides") ? theme.endurance
            : (lower.hasPrefix("lifting") || lower.hasSuffix("lifts") ? theme.strength : theme.textTertiary)
        return HStack(spacing: CySpace.s) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 20).accessibilityHidden(true)
            Text(s).font(CyDyn.f(13.5, .semibold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 6).frame(minHeight: 44)
    }

    private func changeRow(_ r: PlanGoalV2.ChangeRow) -> some View {
        let color: Color = r.sport == "strength" ? theme.strength : (r.sport == "cycling" ? theme.endurance : theme.textTertiary)
        return HStack(alignment: .top, spacing: CySpace.s) {
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 3, height: 20).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(r.day).font(CyDyn.f(13.5, .semibold)).foregroundStyle(theme.textPrimary)
                Text("\(r.before) → \(r.after)").font(CyDyn.f(12.5)).foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(r.day): now \(r.before), after approval \(r.after)")
    }

    /// The same call the existing "Review the change" sheet makes. false = the plan changed meanwhile; nothing is saved.
    private func approve(_ id: UUID) {
        if store.applyPlanChange(id) {
            proposal = nil
            dismiss()
        } else {
            proposal = nil
            stale = true
        }
    }

    // MARK: Pieces

    private var card: some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return shape.fill(theme.surface).overlay(shape.strokeBorder(theme.cardStroke, lineWidth: theme.borderWidth))
    }
    private var line: some View { Rectangle().fill(theme.separator).frame(height: 1).padding(.horizontal, 14) }

    private func caption(_ text: String) -> some View {
        Text(text).font(CyDyn.f(10.5, .semibold)).tracking(0.6).foregroundStyle(theme.textSecondary)
            .padding(.top, CySpace.l).padding(.bottom, CySpace.s).padding(.horizontal, 2)
            .accessibilityAddTraits(.isHeader)
    }

    private func valueRow(_ label: String, _ value: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CySpace.m) {
            Text(label).font(CyDyn.f(13.5)).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: CySpace.s)
            Text(value).font(CyDyn.f(13.5, .semibold)).foregroundStyle(theme.textPrimary)
                .multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.vertical, 6).frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
        .accessibilityIdentifier(id)
    }

    private func stepBar(back: String, step: String, action: @escaping () -> Void) -> some View {
        HStack {
            Button(action: action) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(CyDyn.f(12, .bold)).accessibilityHidden(true)
                    Text(back).font(CyDyn.f(14, .semibold))
                }
                .foregroundStyle(theme.accent).frame(minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to \(back)")
            .accessibilityIdentifier("planGoalBack")
            Spacer()
            Text(step).font(CyDyn.f(13)).foregroundStyle(theme.textSecondary).accessibilityIdentifier("planGoalStep")
        }
        .padding(.top, CySpace.l)
    }

    private func primaryButton(_ title: String, id: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Button(action: action) {
            Text(title).font(CyDyn.f(15, .bold)).foregroundStyle(enabled ? theme.textOnAccent : theme.disabledText)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(primaryFill(shape, enabled: enabled))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(id)
    }
    @ViewBuilder private func primaryFill(_ shape: RoundedRectangle, enabled: Bool) -> some View {
        if !enabled {
            shape.fill(theme.disabledFill)
        } else if theme.usesGradients {
            shape.fill(LinearGradient(colors: [theme.endurance, theme.accent], startPoint: .leading, endPoint: .trailing))
        } else {
            shape.fill(theme.accent)
        }
    }

    private func secondaryButton(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button(action: action) {
            Text(title).font(CyDyn.f(14, .bold)).foregroundStyle(theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(shape.fill(theme.surface.opacity(theme.id == .highContrast ? 1 : 0.6)))
                .overlay(shape.strokeBorder(theme.border, lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
