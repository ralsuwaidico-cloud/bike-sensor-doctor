import SwiftUI

// Coach page — the approved direction (Master instructions §7; Home v2.3 Coach conversation; Coach design review §G):
// the Home Coach card opens one conversation-style page: what the Coach saw, what it advises, what needs your
// decision, what you decided, what changed, and your questions with their answers — in time order.
// Shown where CyProduct.redesign is on.
//
// WHAT IS REAL HERE
// • Every Coach line is one of the app's own records (the rules-based adaptation engine) or an answer built from the
//   athlete's records by written rules. Every line carries a chip saying who produced it. Nothing is sample text.
// • No AI model is connected and none is called. A question the rules cannot answer gets exactly that statement.
//   The conversation runs through `CoachResponder`, so a model can be connected later without rebuilding this page.
// • Each open proposal is also described to the independent policy (shadow mode). Its verdict is shown; it changes
//   nothing. Approval uses the app's existing, validated sheets — this page adds no new way to change a plan.
// • Decisions made from now on are kept in the Coach's own decision history (approved and declined, with the policy
//   version). Decisions made before this history existed are not reconstructed.

// The records and their ordering are in CoachTimeline.swift (Foundation only, tested on Linux).

struct CoachTimelineScreen: View {
    @EnvironmentObject private var store: Store
    let onClose: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @EnvironmentObject private var recorder: RideRecorder
    @StateObject private var center = CoachCenter()
    @State private var proposal: PreviewRefString?
    @State private var showAdjustments = false
    @State private var draft = ""
    @State private var tab = 0
    @FocusState private var typing: Bool

    private var entries: [CyCoachEntry] {
        CoachTimeline.entries(.init(summary: store.lastAdaptation, proposals: store.adaptiveProposals, applied: store.activeAdaptations,
                                    accepted: store.appliedProposals, now: Date(), checks: center.checks, closed: center.closed, chat: center.messages))
    }

    var body: some View {
        let all = entries
        let chat = all.filter { $0.kind == .question || $0.kind == .answer }
        let timeline = all.filter { $0.kind != .question && $0.kind != .answer }
        return VStack(spacing: 0) {
            bar
            tabs
            if tab == 0 { timelinePage(timeline) } else { askPage(chat) }
        }
        .background(theme.background.ignoresSafeArea())
        .onAppear { center.attach(directory: store.dir); center.sync(store) }
        // the athlete's decision is made in the existing sheet; when it closes, read what was decided and record it
        .sheet(item: $proposal, onDismiss: { center.sync(store) }) { p in HomeProposalSheet(adaptiveId: p.id, hybridId: nil).cyThemeRoot() }
        .sheet(isPresented: $showAdjustments, onDismiss: { center.sync(store) }) {
            NavigationStack {
                AdjustmentsView()
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showAdjustments = false } } }
            }
            .cyThemeRoot()
        }
    }

    // MARK: G1 — bar and the Timeline | Ask selector

    /// "‹ Home" on the left, "Coach" centred (sheet G1). Lab adds its DEMO DATA tag on the right.
    private var bar: some View {
        ZStack {
            Text("Coach").font(.system(.headline, design: .rounded)).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("coachTitle")
            HStack(spacing: CySpace.s) {
                Button(action: onClose) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
                        Text("Home").font(.system(.body))
                    }
                    .foregroundStyle(theme.accent)
                    .frame(minWidth: CyHit.min, minHeight: CyHit.min, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Back to Home").accessibilityIdentifier("coachClose")
                Spacer(minLength: 0)
                if CycliftLab.isLab { tag("DEMO DATA", theme.warning) }
            }
        }
        .padding(.horizontal, CySpace.l)
        .padding(.top, CySpace.xs)
    }
    private var tabs: some View {
        HStack(spacing: 0) {
            tabButton("Timeline", 0, id: "coachTabTimeline")
            tabButton("Ask", 1, id: "coachTabAsk")
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.id == .highContrast ? theme.border : Color.clear, lineWidth: theme.borderWidth))
        .padding(.horizontal, CySpace.l).padding(.top, CySpace.xs).padding(.bottom, CySpace.s)
    }
    private func tabButton(_ title: String, _ i: Int, id: String) -> some View {
        Button { typing = false; tab = i } label: {
            Text(title).font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(tab == i ? theme.textPrimary : theme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tab == i ? theme.surface2 : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityAddTraits(tab == i ? .isSelected : []).accessibilityIdentifier(id)
    }
    private func tag(_ t: String, _ c: Color) -> some View {
        Text(t).font(.system(size: 10, weight: .bold)).tracking(0.6).foregroundStyle(c).lineLimit(1).fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(c.opacity(0.8), lineWidth: 1))
    }
    private func note(_ text: String, id: String) -> some View {
        Text(text).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            .padding(CySpace.m).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.border, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
            .accessibilityIdentifier(id)
    }

    // MARK: G1 — Timeline: one history for everything the Coach saw, suggested and changed

    private func timelinePage(_ all: [CyCoachEntry]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CySpace.m) {
                if center.state == .historyUnreadable { note(center.state.text, id: "coachHistoryNote") }
                if all.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No coach notes yet").font(CyFont.headline).foregroundStyle(theme.textPrimary)
                        Text("Complete a session and its short review. The Coach starts from what you actually do.")
                            .font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(CySpace.l).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("coachEmpty")
                }
                ForEach(CoachTimeline.days(all, now: Date()), id: \.day) { group in
                    Text(group.day.uppercased()).font(CyFont.overline).tracking(1.2).foregroundStyle(theme.textSecondary)
                        .padding(.top, CySpace.xs).accessibilityAddTraits(.isHeader)
                    ForEach(group.entries) { e in entryRow(e) }
                }
                Text("The Coach follows written rules and works only from what you have recorded.")
                    .font(.caption2).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("coachRulesNote")
            }
            .padding(.horizontal, CySpace.l).padding(.bottom, CySpace.xl)
        }
        .accessibilityIdentifier("coachTimeline")
    }

    private func postponed(_ e: CyCoachEntry) -> Date? {
        guard e.kind == .proposal, case .proposal(let id)? = e.opens else { return nil }
        return center.postponedAt(id)
    }
    private static let dayTime: DateFormatter = { let f = DateFormatter(); f.dateFormat = "d MMM HH:mm"; return f }()
    private func stateTag(_ e: CyCoachEntry) -> String? {
        switch e.kind {
        case .proposal: return postponed(e) == nil ? "NEEDS YOU" : "POSTPONED"
        case .outcome: return "APPLIED"
        case .decision: return e.text.hasPrefix("Declined") ? "REJECTED" : "APPROVED"
        default: return nil
        }
    }
    private func dot(_ e: CyCoachEntry) -> Color {
        switch e.kind {
        case .proposal: return postponed(e) == nil ? theme.accent : theme.textTertiary
        case .outcome: return theme.success
        case .decision: return e.text.hasPrefix("Declined") ? theme.textTertiary : theme.success
        case .recovery: return theme.warning
        default: return theme.textTertiary
        }
    }
    private func sourceTag(_ e: CyCoachEntry) -> some View {
        let chip = e.chip ?? (e.author == .athlete ? CoachSource.athlete.chip : CoachSource.rules.chip)
        let c: Color = chip == CoachSource.notConnected.chip ? theme.warning : (e.author == .athlete ? theme.accent : theme.success)
        return tag(chip.uppercased(), c)
    }

    /// A dot on the rail and a card: who produced it, its state, what it says, and the way to act on it.
    private func entryRow(_ e: CyCoachEntry) -> some View {
        let shape = RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous)
        let chip = e.chip ?? (e.author == .athlete ? CoachSource.athlete.chip : CoachSource.rules.chip)
        let time = Self.clock.string(from: e.at)
        return HStack(alignment: .top, spacing: CySpace.m) {
            Circle().fill(dot(e)).frame(width: 9, height: 9).padding(.top, CySpace.l).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CySpace.s) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        sourceTag(e)
                        if let s = stateTag(e) { tag(s, theme.textSecondary) }
                        Spacer(minLength: 4)
                        Text(time).font(.caption2).monospacedDigit().foregroundStyle(theme.textTertiary)
                    }
                    Text(e.text).font(.system(.callout, design: .rounded).weight(.semibold)).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    if let d = e.detail {
                        Text(d).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let c = e.check {
                        Text(c).font(.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                    }
                    if !e.basedOn.isEmpty {
                        Text("Based on: " + e.basedOn.joined(separator: " · ")).font(.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(e.author == .athlete ? "You" : "Coach"), \(e.kind.label), \(chip), \(time). \(e.text) \(e.detail ?? "") \(e.check ?? "") \(e.basedOn.isEmpty ? "" : "Based on " + e.basedOn.joined(separator: ", "))")
                .accessibilityIdentifier("coachEntry-\(e.id)")
                if let o = e.opens {
                    if e.kind == .proposal, let when = postponed(e) {
                        // postponed by the athlete: said plainly, still open, still reviewable
                        Text("You chose Not now on \(Self.dayTime.string(from: when)). It stays open and nothing changes until you decide.")
                            .font(.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("coachPostponed-\(e.id)")
                        Button { open(o) } label: {
                            Text("Review").font(.system(.footnote).weight(.semibold)).foregroundStyle(theme.accent)
                                .frame(minHeight: CyHit.min, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Nothing changes in your plan unless you approve it")
                        .accessibilityIdentifier("coachOpen-\(e.id)")
                    } else if e.kind == .proposal, case .proposal(let pid) = o {
                        // G1: Not now · Review. "Not now" records a deliberate postponement in the Coach's own file; it is
                        // neither an approval nor a rejection and changes nothing in the plan.
                        HStack(spacing: CySpace.m) {
                            Button { center.postpone(proposalId: pid) } label: {
                                Text("Not now").font(.system(.subheadline, design: .rounded).weight(.semibold)).foregroundStyle(theme.textSecondary)
                                    .frame(maxWidth: .infinity, minHeight: 40)
                                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(theme.border, lineWidth: 1.2))
                                    .frame(minHeight: CyHit.min).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Postpones the decision. The suggestion stays open")
                            .accessibilityIdentifier("coachNotNow-\(e.id)")
                            Button { open(o) } label: {
                                Text("Review").font(.system(.subheadline, design: .rounded).weight(.bold)).foregroundStyle(theme.textOnAccent)
                                    .frame(maxWidth: .infinity, minHeight: 40).background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.accent))
                                    .frame(minHeight: CyHit.min).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Nothing changes in your plan unless you approve it")
                            .accessibilityIdentifier("coachOpen-\(e.id)")
                        }
                    } else {
                        Button { open(o) } label: {
                            Text(openLabel(e)).font(.system(.footnote).weight(.semibold)).foregroundStyle(theme.accent)
                                .frame(minHeight: CyHit.min, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("coachOpen-\(e.id)")
                    }
                }
            }
            .padding(CySpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(theme.surface))
            .overlay(shape.strokeBorder(theme.border.opacity(theme.id == .highContrast ? 1 : 0.5), lineWidth: 1))
        }
    }

    // MARK: G2 screen 6 — Ask: fixed questions answered by rules, from the athlete's records

    private func askPage(_ chat: [CyCoachEntry]) -> some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: CySpace.m) {
                        note("Answers come from your records using fixed rules. No AI model is installed in this version.", id: "coachAskNote")
                        ForEach(chat) { e in bubble(e).id(e.id) }
                        if center.thinking { ProgressView().frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel("The Coach is answering") }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, CySpace.l).padding(.bottom, CySpace.m)
                }
                .accessibilityIdentifier("coachAsk")
                .scrollDismissesKeyboard(.interactively)
                .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: center.revision) { _, _ in DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } } }
            }
            composer
        }
    }

    private static let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    /// The athlete's question on the right; the answer on the left with who produced it and what it is based on.
    @ViewBuilder private func bubble(_ e: CyCoachEntry) -> some View {
        let mine = e.author == .athlete
        let shape = RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous)
        let time = Self.clock.string(from: e.at)
        let chip = e.chip ?? (mine ? CoachSource.athlete.chip : CoachSource.rules.chip)
        HStack(alignment: .top, spacing: 0) {
            if mine { Spacer(minLength: typeSize.isAccessibilitySize ? 16 : 56) }
            VStack(alignment: .leading, spacing: 6) {
                if !mine { sourceTag(e) }
                Text(e.text).font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                if let d = e.detail {
                    Text(d).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                if !e.basedOn.isEmpty {
                    Text("Based on: " + e.basedOn.joined(separator: " · ")).font(.caption).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, CySpace.m).padding(.vertical, mine ? CySpace.s + 2 : CySpace.m)
            .background(shape.fill(mine ? theme.accentSubtle : theme.surface))
            .overlay(shape.strokeBorder(mine ? Color.clear : theme.border.opacity(theme.id == .highContrast ? 1 : 0.5), lineWidth: 1))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(mine ? "You" : "Coach"), \(e.kind.label), \(chip), \(time). \(e.text) \(e.detail ?? "") \(e.basedOn.isEmpty ? "" : "Based on " + e.basedOn.joined(separator: ", "))")
            .accessibilityIdentifier("coachEntry-\(e.id)")
            if !mine { Spacer(minLength: typeSize.isAccessibilitySize ? 16 : 56) }
        }
    }

    private func openLabel(_ e: CyCoachEntry) -> String {
        switch e.opens {
        case .proposal: return e.kind == .proposal ? "Review and decide" : "Details"
        case .adjustments: return e.kind == .outcome ? "Undo · See the change" : "Open adjustments"
        case nil: return ""
        }
    }
    private func open(_ o: CyCoachEntry.Opens) {
        switch o {
        case .proposal(let id): if store.adaptiveProposals.contains(where: { $0.id == id }) { proposal = PreviewRefString(id: id) }
        case .adjustments: showAdjustments = true
        }
    }

    /// The conversation's input: questions the rules can answer as buttons, and a field for anything else. A typed
    /// question the rules cannot answer is stored with the plain reply that AI chat is not connected.
    private var composer: some View {
        VStack(alignment: .leading, spacing: CySpace.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CySpace.s) {
                    ForEach(CoachRules.suggested, id: \.question) { s in
                        Button { send(s.question) } label: {
                            Text(s.question).font(CyFont.caption).foregroundStyle(theme.textPrimary).lineLimit(1)
                                .padding(.horizontal, CySpace.m).frame(minHeight: 36)
                                .background(Capsule().fill(theme.surface2))
                                .overlay(Capsule().strokeBorder(theme.id == .highContrast ? theme.border : Color.clear, lineWidth: theme.borderWidth))
                                .frame(minHeight: CyHit.min).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("coachAsk-\(s.intent.rawValue)")
                    }
                }
                .padding(.horizontal, CySpace.l)
            }
            HStack(spacing: CySpace.s) {
                TextField("Ask about your training…", text: $draft, axis: .vertical)
                    .lineLimit(1...3).focused($typing).submitLabel(.send).onSubmit { send(draft) }
                    .font(CyFont.callout).foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, CySpace.m).frame(minHeight: CyHit.min)
                    .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface))
                    .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.border.opacity(0.6), lineWidth: 1))
                    .accessibilityIdentifier("coachField")
                Button { send(draft) } label: {
                    Image(systemName: "arrow.up").font(.body.weight(.bold)).foregroundStyle(theme.textOnAccent)
                        .frame(width: 36, height: 36).background(Circle().fill(sendable ? theme.accent : theme.disabledFill))
                        .frame(width: CyHit.min, height: CyHit.min).contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(!sendable)
                .accessibilityLabel("Send question").accessibilityIdentifier("coachSend")
            }
            .padding(.horizontal, CySpace.l)
            }
        .padding(.vertical, CySpace.s)
        .background(theme.background)
    }
    private var sendable: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !center.thinking }
    private func send(_ q: String) {
        let text = q; draft = ""; typing = false
        Task { await center.ask(text, store: store, recorderActive: recorder.isActive) }
    }
}

/// Sheet item for a proposal id.
struct PreviewRefString: Identifiable, Equatable { let id: String }
