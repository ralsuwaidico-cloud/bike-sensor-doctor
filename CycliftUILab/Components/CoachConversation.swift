import SwiftUI

// Home v2.3 — Coach preview and Coach conversation timeline (UI Lab prototype, SAMPLE history only).
// There is no live AI conversation, no stored chat history and no automatic coaching intelligence here.
// The timeline is a view over coach EVENTS (observations, advice, proposals, decisions, outcomes). The existing
// rule-based coach is not replaced; docs/INTEGRATION_MAP.md lists what must be connected for real data.

// MARK: model

enum CyCoachAuthor: Equatable { case coach, athlete }

/// The six message categories asked for by the owner, plus "outcome" (what happened after a decision).
enum CyCoachEntryKind: String, Equatable {
    case observation, recommendation, recovery, question, answer, proposal, decision, outcome
    var label: String {
        switch self {
        case .observation: return "Observation"
        case .recommendation: return "Recommendation"
        case .recovery: return "Recovery"
        case .question: return "Your question"
        case .answer: return "Answer"
        case .proposal: return "Proposed change"
        case .decision: return "Your decision"
        case .outcome: return "Outcome"
        }
    }
    var icon: String {
        switch self {
        case .observation: return "eye"
        case .recommendation: return "lightbulb"
        case .recovery: return "moon.stars"
        case .question: return "questionmark.bubble"
        case .answer: return "text.bubble"
        case .proposal: return "arrow.triangle.2.circlepath"
        case .decision: return "hand.tap"
        case .outcome: return "checkmark.seal"
        }
    }
}

enum CyProposalStatus: String, Equatable {
    case pending, postponed, accepted, declined
    var label: String {
        switch self {
        case .pending: return "Needs your decision"
        case .postponed: return "Postponed — still open"
        case .accepted: return "Accepted"
        case .declined: return "Declined"
        }
    }
    var icon: String {
        switch self {
        case .pending: return "circle.dashed"
        case .postponed: return "clock"
        case .accepted: return "checkmark.circle.fill"
        case .declined: return "xmark.circle"
        }
    }
    var isOpen: Bool { self == .pending || self == .postponed }
}

struct CyCoachProposal: Identifiable, Equatable {
    let id: String
    let title: String
    let summary: String              // one line, used on Home while a decision is needed
    let changes: [CyChange]          // what will change
    let reason: String               // why the coach recommends it
    let benefit: String              // expected benefit
    let impact: String               // potential impact
    var status: CyProposalStatus
}

struct CyCoachEntry: Identifiable, Equatable {
    let id: String
    let day: String                  // group header: "Today · Wed 11 Nov", "Tue 10 Nov"
    let time: String                 // "06:50"
    let author: CyCoachAuthor
    let kind: CyCoachEntryKind
    let text: String
    var proposalId: String? = nil    // links advice, proposal, decision and outcome into one thread
}

struct CyCoachPreviewModel: Equatable {
    let text: String
    let needsDecision: Bool
}

struct CyCoachConversation: Equatable {
    var entries: [CyCoachEntry]      // oldest first
    var proposals: [CyCoachProposal]

    func proposal(_ id: String?) -> CyCoachProposal? { proposals.first { $0.id == id } }

    /// Home shows the latest RELEVANT insight, not simply the last message:
    /// 1. the newest proposal that still needs a decision; otherwise
    /// 2. the newest coach recommendation or recovery advice; otherwise
    /// 3. the newest coach observation.
    /// Decisions, outcomes, questions and answers are never shown as the Home insight.
    var preview: CyCoachPreviewModel? {
        if let e = entries.last(where: { $0.kind == .proposal && (proposal($0.proposalId)?.status.isOpen ?? false) }),
           let p = proposal(e.proposalId) {
            return CyCoachPreviewModel(text: p.summary, needsDecision: true)
        }
        if let e = entries.last(where: { $0.author == .coach && ($0.kind == .recommendation || $0.kind == .recovery) }) {
            return CyCoachPreviewModel(text: e.text, needsDecision: false)
        }
        if let e = entries.last(where: { $0.author == .coach && $0.kind == .observation }) {
            return CyCoachPreviewModel(text: e.text, needsDecision: false)
        }
        return nil
    }

    /// Entries grouped by day, keeping chronological order.
    var days: [(day: String, entries: [CyCoachEntry])] {
        var out: [(day: String, entries: [CyCoachEntry])] = []
        for e in entries {
            if let i = out.indices.last, out[i].day == e.day { out[i].entries.append(e) } else { out.append((day: e.day, entries: [e])) }
        }
        return out
    }

    func history(of proposalId: String) -> [CyCoachEntry] { entries.filter { $0.proposalId == proposalId } }

    /// Prototype only: records the athlete's decision and the coach's acknowledgement in the timeline.
    /// Nothing outside this in-memory sample changes.
    mutating func decide(_ proposalId: String, _ status: CyProposalStatus, day: String, time: String) {
        guard let i = proposals.firstIndex(where: { $0.id == proposalId }), proposals[i].status.isOpen else { return }
        proposals[i].status = status
        let n = entries.count
        let mine: String, reply: String
        switch status {
        case .accepted:
            mine = "Approved: \(proposals[i].title)."
            reply = "Applied to the sample plan. Nothing real was changed in this prototype."
        case .postponed:
            mine = "Not now."
            reply = "Kept open. Nothing changes until you decide."
        case .declined:
            mine = "Declined: \(proposals[i].title)."
            reply = "Understood. Your plan stays as it is and this suggestion will not be repeated."
        case .pending:
            return
        }
        entries.append(CyCoachEntry(id: "d\(n)", day: day, time: time, author: .athlete, kind: .decision, text: mine, proposalId: proposalId))
        entries.append(CyCoachEntry(id: "o\(n)", day: day, time: time, author: .coach, kind: .outcome, text: reply, proposalId: proposalId))
    }
}

// MARK: Home preview

/// Compact, text-only, tappable. No Review / Approve / Not now / Decline here — decisions live in the conversation's
/// proposal detail. About two lines of text; longer text is truncated.
struct CyCoachPreview: View {
    let model: CyCoachPreviewModel?  // nil while loading or when there is nothing to say
    var emptyText: String? = nil
    var isLoading: Bool = false
    let onOpen: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous)
        Button(action: onOpen) {
            HStack(alignment: .top, spacing: CySpace.m) {
                Image(systemName: "sparkles").font(.footnote.weight(.semibold)).foregroundStyle(theme.accent)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Coach").font(CyFont.caption.weight(.semibold)).foregroundStyle(theme.textSecondary)
                        if model?.needsDecision == true && !isLoading {
                            Circle().fill(theme.accent).frame(width: 6, height: 6)
                            Text("Needs your decision").font(.caption2).foregroundStyle(theme.textSecondary).lineLimit(1)
                        }
                    }
                    if isLoading {
                        CySkeleton(); CySkeleton(width: 200)
                    } else {
                        Text(model?.text ?? emptyText ?? "Nothing to report yet.")
                            .font(CyFont.callout).foregroundStyle(model == nil ? theme.textSecondary : theme.textPrimary)
                            .lineLimit(typeSize.isAccessibilitySize ? 4 : 2).truncationMode(.tail)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(theme.textTertiary)
                    .padding(.top, 5)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, CySpace.m)
            .padding(.horizontal, CySpace.m)
            .frame(maxWidth: .infinity, minHeight: CyHit.min, alignment: .leading)
            .background(shape.fill(theme.highlightSurface))
            .overlay(shape.strokeBorder(theme.id == .highContrast ? theme.border : Color.clear, lineWidth: theme.borderWidth))
            .contentShape(shape)
        }
        .buttonStyle(CyRingButtonStyle())
        .disabled(isLoading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Coach")
        .accessibilityValue(isLoading ? "Loading" : ((model?.needsDecision == true ? "Needs your decision. " : "") + (model?.text ?? emptyText ?? "Nothing to report yet.")))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the coach conversation")
        .accessibilityIdentifier("coachPreview")
    }
}

// MARK: Conversation page

struct CoachConversationScreen: View {
    @Binding var conversation: CyCoachConversation
    var today: String = "Today · Wed 11 Nov"
    var now: String = "12:30"
    var initialProposal: String? = nil       // prototype screenshots only
    var startAtTop: Bool = false             // prototype screenshots only
    let onClose: () -> Void
    @Environment(\.cyTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @StateObject private var sheets = SheetPresenter<CyCoachProposal>(name: "coach")
    // A decision is saved to `conversation` at once. While the proposal sheet is still leaving the screen the
    // timeline keeps showing this snapshot, and switches to the saved state when the presenter reports the sheet gone.
    @State private var held: CyCoachConversation?
    private var shown: CyCoachConversation { held ?? conversation }
    @State private var didInit = false

    var body: some View {
        VStack(spacing: 0) {
            bar
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: CySpace.m) {
                        Text("Sample history for design review. The coach follows written rules; this is not a live AI chat and nothing here is stored.")
                            .font(.caption2).foregroundStyle(theme.textTertiary).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("coachSampleNote")
                        if shown.entries.isEmpty {
                            CyEmptyStateCard(icon: "sparkles", title: "No coach notes yet", message: "Complete a session and the short check-in. The coach starts from what you actually do.")
                        }
                        ForEach(shown.days, id: \.day) { group in
                            Text(group.day.uppercased()).font(CyFont.overline).tracking(0.8).foregroundStyle(theme.textSecondary)
                                .frame(maxWidth: .infinity).padding(.top, CySpace.s)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(group.entries) { e in bubble(e).id(e.id) }
                        }
                        composer
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding(.horizontal, CySpace.l)
                    .padding(.vertical, CySpace.m)
                }
                .accessibilityIdentifier("coachTimeline")
                .onAppear { if !startAtTop { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo("end", anchor: .bottom) } } }
                .onChange(of: shown.entries.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            }
        }
        .background(theme.background.ignoresSafeArea())
        .environment(\.cyTheme, theme)
        .preferredColorScheme(theme.scheme)
        .background(sheets.anchorView())
        .sheet(item: sheets.binding, onDismiss: { sheets.swiftUIDismissed() }) { p in
            CoachProposalSheet(proposal: conversation.proposal(p.id) ?? p, history: conversation.history(of: p.id),
                               onClose: { sheets.dismiss("close button") },
                               onDecide: { status in
                                   if held == nil { held = conversation }                    // what the timeline shows meanwhile
                                   conversation.decide(p.id, status, day: today, time: now)    // saved now, not after the animation
                                   SheetLog.note("coach decision on \(p.id) saved; timeline update waits for the sheet to leave")
                                   sheets.onNextIdle { held = nil }
                                   sheets.dismiss("decision")
                               })
                .background(sheets.probeView(for: p.id))
                .onAppear { sheets.contentEvent(p.id, appeared: true) }
                .onDisappear { sheets.contentEvent(p.id, appeared: false) }
                .environment(\.cyTheme, theme)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: sheets.phase) { _, new in if new == .idle && held != nil { held = nil } }
        .onDisappear { held = nil }
        .onAppear {
            guard !didInit else { return }
            didInit = true
            if let id = initialProposal, let p = conversation.proposal(id) {
                present(p)        // the presenter waits until this screen has finished appearing
            }
        }
    }

    private func present(_ p: CyCoachProposal) { sheets.request(p) }

    private var bar: some View {
        HStack(spacing: CySpace.s) {
            CyIconButton(systemName: "chevron.down", label: "Close coach", action: onClose).accessibilityIdentifier("coachClose")
            Text("Coach").font(CyFont.title).foregroundStyle(theme.textPrimary).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("coachTitle")
            tag("rules-based", theme.textSecondary)
            tag("SAMPLE", theme.warning)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CySpace.l)
        .padding(.vertical, CySpace.s)
    }
    private func tag(_ t: String, _ c: Color) -> some View {
        Text(t).font(.caption2.weight(.semibold)).foregroundStyle(c).lineLimit(1).fixedSize()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(c.opacity(0.7), lineWidth: 1))
    }

    @ViewBuilder private func bubble(_ e: CyCoachEntry) -> some View {
        let p = e.kind == .proposal ? shown.proposal(e.proposalId) : nil
        if p == nil {
            // a plain message is one accessible element; a proposal message keeps its button reachable
            bubbleBody(e, nil)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(e.author == .athlete ? "You" : "Coach"), \(e.kind.label), \(e.time). \(e.text)")
                .accessibilityIdentifier("coachEntry-\(e.id)")
        } else {
            bubbleBody(e, p)
        }
    }

    private func bubbleBody(_ e: CyCoachEntry, _ p: CyCoachProposal?) -> some View {
        let mine = e.author == .athlete
        let shape = RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous)
        return HStack(alignment: .top, spacing: 0) {
            if mine { Spacer(minLength: typeSize.isAccessibilitySize ? 16 : 48) }
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: e.kind.icon).font(.caption2).foregroundStyle(mine ? theme.accent : theme.textSecondary).accessibilityHidden(true)
                    Text(e.kind.label).font(.caption2.weight(.semibold)).foregroundStyle(mine ? theme.accent : theme.textSecondary)
                    Text(e.time).font(.caption2).monospacedDigit().foregroundStyle(theme.textTertiary)
                }
                Text(e.text).font(CyFont.callout).foregroundStyle(theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                if let p {
                    Button(action: { present(p) }) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(p.title).font(CyFont.label).foregroundStyle(theme.textPrimary).multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 6) {
                                Image(systemName: p.status.icon).font(.caption).foregroundStyle(p.status.isOpen ? theme.accent : theme.textSecondary)
                                Text(p.status.label).font(CyFont.caption).foregroundStyle(theme.textSecondary)
                                Spacer(minLength: CySpace.s)
                                Text(p.status.isOpen ? "Review" : "View").font(CyFont.caption.weight(.semibold)).foregroundStyle(theme.accent)
                                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(theme.accent)
                            }
                        }
                        .padding(CySpace.m)
                        .frame(maxWidth: .infinity, minHeight: CyHit.min, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).fill(theme.background.opacity(theme.isDark ? 0.55 : 0.7)))
                        .overlay(RoundedRectangle(cornerRadius: CyRadius.s, style: .continuous).strokeBorder(theme.id == .highContrast ? theme.border : theme.border.opacity(0.5), lineWidth: theme.borderWidth))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CyRingButtonStyle())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Proposal: \(p.title)")
                    .accessibilityValue(p.status.label)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Opens the proposal details")
                    .accessibilityIdentifier("coachProposal-\(p.id)")
                }
            }
            .padding(CySpace.m)
            .background(shape.fill(mine ? theme.accentSubtle : theme.surface))
            .overlay(shape.strokeBorder(theme.id == .highContrast ? theme.border : Color.clear, lineWidth: theme.borderWidth))
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
            if !mine { Spacer(minLength: typeSize.isAccessibilitySize ? 16 : 48) }
        }
    }

    /// Shown so the page layout can be judged with a message field. It is deliberately not functional.
    private var composer: some View {
        HStack(spacing: CySpace.s) {
            Image(systemName: "text.bubble").font(.footnote).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
            Text("Ask the coach — not available in this prototype").font(CyFont.footnote).foregroundStyle(theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, CySpace.m)
        .frame(maxWidth: .infinity, minHeight: CyHit.min, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: CyRadius.m, style: .continuous).strokeBorder(theme.border.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
        .padding(.top, CySpace.s)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("coachComposerDisabled")
    }
}

// MARK: Proposal detail

/// What will change · why · expected benefit · potential impact · this proposal's history · Approve / Not now / Decline.
/// Nothing changes without the athlete's approval; a decided proposal is read-only.
struct CoachProposalSheet: View {
    let proposal: CyCoachProposal
    let history: [CyCoachEntry]
    let onClose: () -> Void
    let onDecide: (CyProposalStatus) -> Void
    @Environment(\.cyTheme) private var theme

    var body: some View {
        CySheet(title: proposal.title, onClose: onClose) {
            HStack(spacing: 6) {
                Image(systemName: proposal.status.icon).font(.footnote).foregroundStyle(proposal.status.isOpen ? theme.accent : theme.textSecondary)
                Text(proposal.status.label).font(CyFont.footnote.weight(.semibold)).foregroundStyle(theme.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("proposalStatus")
            CyCard(padding: CySpace.m) {
                VStack(alignment: .leading, spacing: CySpace.m) {
                    CyOverline(text: "What would change")
                    if proposal.changes.isEmpty { Text("No changes to review.").font(CyFont.callout).foregroundStyle(theme.textSecondary) }
                    ForEach(proposal.changes) { c in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(c.label).font(CyFont.caption).foregroundStyle(theme.textSecondary)
                            HStack(spacing: CySpace.s) {
                                Text(c.before).font(CyFont.callout).foregroundStyle(theme.textTertiary).strikethrough()
                                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(theme.textTertiary).accessibilityHidden(true)
                                Text(c.after).font(CyFont.callout.weight(.semibold)).foregroundStyle(theme.textPrimary)
                            }
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(c.label): from \(c.before) to \(c.after)")
                    }
                }
            }
            InfoBlock(head: "Why", text: proposal.reason)
            InfoBlock(head: "Expected benefit", text: proposal.benefit)
            InfoBlock(head: "Possible impact", text: proposal.impact)
            if !history.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    CyOverline(text: "History").accessibilityAddTraits(.isHeader)
                    ForEach(history) { e in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(e.day.replacingOccurrences(of: "Today · ", with: "")) \(e.time)").font(.caption2).monospacedDigit().foregroundStyle(theme.textTertiary)
                            Text("\(e.author == .athlete ? "You" : "Coach") · \(e.kind.label)").font(.caption2.weight(.semibold)).foregroundStyle(theme.textSecondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("proposalHistory")     // one element per history record; the heading is not one
                    }
                }
            }
            if proposal.status.isOpen {
                Text("Nothing changes in your plan unless you approve it.").font(CyFont.footnote).foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: CySpace.s) {
                    CyButton(title: "Approve", icon: "checkmark", kind: .primary) { onDecide(.accepted) }.accessibilityIdentifier("reviewApprove")
                    if proposal.status == .pending {
                        CyButton(title: "Not now", kind: .secondary) { onDecide(.postponed) }.accessibilityIdentifier("reviewPostpone")
                    }
                    CyButton(title: "Decline", kind: .destructive) { onDecide(.declined) }.accessibilityIdentifier("reviewDecline")
                }
            } else {
                Text("This proposal is closed. It is kept here so you can look back at the advice and your decision.").font(CyFont.footnote)
                    .foregroundStyle(theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("proposalClosedNote")
            }
            Text("Sample proposal. The coach follows written rules; no generative AI model is used.").font(.caption2).foregroundStyle(theme.textTertiary)
        }
    }
}
