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
    @FocusState private var typing: Bool

    private var entries: [CyCoachEntry] {
        CoachTimeline.entries(.init(summary: store.lastAdaptation, proposals: store.adaptiveProposals, applied: store.activeAdaptations,
                                    accepted: store.appliedProposals, now: Date(), checks: center.checks, closed: center.closed, chat: center.messages))
    }

    var body: some View {
        let all = entries
        return VStack(spacing: 0) {
            bar
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: CySpace.m) {
                        Text(center.state == .historyUnreadable ? center.state.text : "The Coach follows written rules and works only from what you have recorded. AI chat is not connected.")
                            .font(.caption2).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("coachRulesNote")
                        if all.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("No coach notes yet").font(CyFont.headline).foregroundStyle(theme.textPrimary)
                                Text("Complete a session and its short check-in. The Coach starts from what you actually do.")
                                    .font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(CySpace.l).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).fill(theme.surface))
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier("coachEmpty")
                        }
                        ForEach(CoachTimeline.days(all, now: Date()), id: \.day) { group in
                            Text(group.day.uppercased()).font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary)
                                .frame(maxWidth: .infinity).padding(.top, CySpace.s)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.entries) { e in bubble(e).id(e.id) }
                        }
                        if center.thinking { ProgressView().frame(maxWidth: .infinity, alignment: .leading).accessibilityLabel("The Coach is answering") }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, CySpace.l)
                    .padding(.vertical, CySpace.m)
                }
                .accessibilityIdentifier("coachTimeline")
                .scrollDismissesKeyboard(.interactively)
                .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo("end", anchor: .bottom) } }
                .onChange(of: center.revision) { _, _ in DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { withAnimation { proxy.scrollTo("end", anchor: .bottom) } } }
            }
            composer
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

    private var bar: some View {
        HStack(spacing: CySpace.s) {
            Button(action: onClose) {
                Image(systemName: "chevron.down").font(.system(size: 15, weight: .bold)).foregroundStyle(theme.textPrimary)
                    .frame(width: 34, height: 34).background(Circle().fill(theme.surface2))
                    .frame(width: CyHit.min, height: CyHit.min).contentShape(Rectangle())
            }
            .accessibilityLabel("Close coach").accessibilityIdentifier("coachClose")
            Text("Coach").font(CyFont.title).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("coachTitle")
            tag("rules-based", theme.textSecondary)
            if CycliftLab.isLab { tag("DEMO DATA", theme.warning) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CySpace.s)
        .padding(.vertical, CySpace.s)
    }
    private func tag(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption2.weight(.semibold)).foregroundStyle(c).lineLimit(1).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(c.opacity(0.7), lineWidth: 1))
    }

    private static let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm"; return f }()

    @ViewBuilder private func bubble(_ e: CyCoachEntry) -> some View {
        let mine = e.author == .athlete
        let shape = RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous)
        let time = Self.clock.string(from: e.at)
        let chip = e.chip ?? (mine ? CoachSource.athlete.chip : CoachSource.rules.chip)
        HStack(alignment: .top, spacing: 0) {
            if mine { Spacer(minLength: typeSize.isAccessibilitySize ? 16 : 48) }
            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: e.kind.icon).font(.caption2).foregroundStyle(mine ? theme.accent : theme.textSecondary).accessibilityHidden(true)
                        Text(e.kind.label).font(.caption2.weight(.semibold)).foregroundStyle(mine ? theme.accent : theme.textSecondary)
                        Text(time).font(.caption2).monospacedDigit().foregroundStyle(theme.textTertiary)
                        Spacer(minLength: 4)
                        tag(chip, chip == CoachSource.notConnected.chip ? theme.warning : theme.textSecondary)
                    }
                    Text(e.text).font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                    if let d = e.detail {
                        Text(d).font(CyFont.footnote).foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let c = e.check {
                        Label { Text(c).fixedSize(horizontal: false, vertical: true) } icon: { Image(systemName: "checkmark.shield") }
                            .font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                    }
                    if !e.basedOn.isEmpty {
                        Text("Based on: " + e.basedOn.joined(separator: " · ")).font(.caption2).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(mine ? "You" : "Coach"), \(e.kind.label), \(chip), \(time). \(e.text) \(e.detail ?? "") \(e.check ?? "") \(e.basedOn.isEmpty ? "" : "Based on " + e.basedOn.joined(separator: ", "))")
                .accessibilityIdentifier("coachEntry-\(e.id)")
                if let o = e.opens {
                    Button { open(o) } label: {
                        HStack(spacing: 6) {
                            Text(openLabel(e)).font(CyFont.caption.weight(.semibold))
                            Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(theme.accent)
                        .frame(maxWidth: .infinity, minHeight: CyHit.min, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(e.kind == .proposal ? "Nothing changes in your plan unless you approve it" : "")
                    .accessibilityIdentifier("coachOpen-\(e.id)")
                }
            }
            .padding(CySpace.m)
            .background(shape.fill(mine ? theme.accentSubtle : theme.surface))
            .overlay(shape.strokeBorder(theme.id == .highContrast ? theme.border : Color.clear, lineWidth: theme.borderWidth))
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
            if !mine { Spacer(minLength: typeSize.isAccessibilitySize ? 16 : 48) }
        }
    }

    private func openLabel(_ e: CyCoachEntry) -> String {
        switch e.opens {
        case .proposal: return e.kind == .proposal ? "Review and decide" : "Details"
        case .adjustments: return e.kind == .outcome ? "See the change · Undo" : "Open adjustments"
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
                TextField("Ask the Coach", text: $draft, axis: .vertical)
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
            Text("Answers come from your records by written rules. AI chat is not connected.")
                .font(.caption2).foregroundStyle(theme.textTertiary).padding(.horizontal, CySpace.l)
                .accessibilityIdentifier("coachComposerNote")
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
