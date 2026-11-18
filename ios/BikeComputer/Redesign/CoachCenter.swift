import SwiftUI

// Coach page — the one object that connects the page to the athlete record, the shadow policy and the conversation.
//
// SHADOW MODE, NON-MUTATING. This file reads the athlete record. It assigns nothing on `Store`: no plan, proposal or
// setting is changed here. It writes only the Coach's own two files (the shadow decision history and the conversation).
// Approving or declining a proposal still happens in the app's existing approval sheet; afterwards this object reads
// what the athlete decided and records it in the decision history.

@MainActor
final class CoachCenter: ObservableObject {
    @Published private(set) var revision = 0
    @Published private(set) var thinking = false
    private var ledger: ShadowLedger?
    private var journal: CoachJournal?
    /// The responder is the only thing that changes when an AI model is connected. Today: rules only.
    var responder: CoachResponder = RulesCoachResponder()

    func attach(directory: URL) {
        guard ledger == nil else { return }
        ledger = ShadowLedger(directory: directory); journal = CoachJournal(directory: directory)
        revision += 1
    }

    var state: ShadowCoachState { ledger?.state ?? .rulesOnly }
    var messages: [CoachChatMessage] { journal?.file.messages ?? [] }

    /// Describes every open proposal to the independent policy (once each) and records decisions the athlete has made
    /// since the last look. Reads the store; changes nothing in it.
    func sync(_ store: Store, now: Date = Date()) {
        guard let ledger, let journal else { return }
        let athlete = ShadowAthleteSnapshot(reading: store, now: now)
        for p in store.adaptiveProposals {
            for adj in p.adjustments {
                guard !journal.file.links.contains(where: { $0.proposalId == p.id && $0.adjustmentKey == adj.key }),
                      let sp = CoachShadowMap.proposal(for: adj, workout: store.plan.first(where: { $0.id == adj.workoutId }), now: now) else { continue }
                let d = ledger.submit(sp, athlete: athlete, now: now)
                journal.link(.init(shadowId: d.duplicateOf ?? sp.id, proposalId: p.id, adjustmentKey: adj.key, text: p.text, why: p.why))
            }
        }
        let open = Set(store.adaptiveProposals.map(\.id))
        journal.prunePostponed(open: open)
        for l in journal.file.links where !open.contains(l.proposalId) {
            if store.approvedAdaptations.contains(l.adjustmentKey) { ledger.recordChoice(.approved, for: l.shadowId, now: now) }
            else if store.dismissedAdaptations.contains(l.proposalId) { ledger.recordChoice(.declined, for: l.shadowId, now: now) }
        }
        revision += 1
    }

    /// AdaptiveProposal.id → what the independent check concluded (first checked adjustment of the proposal).
    var checks: [String: String] {
        guard let ledger, let journal else { return [:] }
        var out: [String: String] = [:]
        for l in journal.file.links where out[l.proposalId] == nil {
            if let d = ledger.events(for: l.shadowId).first(where: { $0.kind == .evaluated })?.decision { out[l.proposalId] = CoachShadowMap.line(d) }
        }
        return out
    }

    /// "Not now": the athlete postponed deciding. Stored in the Coach's own file; the athlete record and the plan are
    /// not touched, and the proposal stays open.
    func postpone(proposalId: String, now: Date = Date()) { if journal?.postpone(proposalId, at: now) == true { revision += 1 } }
    func postponedAt(_ proposalId: String) -> Date? { journal?.postponedAt(proposalId) }

    /// Answered proposals from the durable history, one per proposal.
    var closed: [CoachTimeline.Closed] {
        guard let ledger, let journal else { return [] }
        var seen = Set<String>(), out: [CoachTimeline.Closed] = []
        for l in journal.file.links where !seen.contains(l.proposalId) {
            let evs = ledger.events(for: l.shadowId)
            guard let c = evs.first(where: { $0.kind == .athleteChoice }), let choice = c.choice else { continue }
            seen.insert(l.proposalId)
            out.append(.init(id: l.proposalId, at: c.at, text: l.text, why: l.why, approved: choice == .approved,
                             check: evs.first(where: { $0.kind == .evaluated })?.decision.map(CoachShadowMap.line)))
        }
        return out
    }

    static func facts(_ store: Store, recorderActive: Bool) -> CoachFacts {
        let h = store.homeToday(recorderActive: recorderActive), w = store.homeWeek(), p = store.profile
        var f = CoachFacts()
        func line(_ s: HomeSession) -> String { "\(s.title), \(s.subtitle) — \(s.status.chip?.lowercased() ?? "planned")" }
        switch h.layout {
        case .single(let s): f.todayLine = "Today: \(line(s))."
        case .multi(let rows): f.todayLine = "Today: " + rows.map(line).joined(separator: "; ") + "."
        case .rest: f.todayLine = "Today is a rest day."
        case .hold: f.onHold = true
        case .freeSession: f.todayLine = "A strength session is in progress."
        case .first: f.todayLine = nil
        }
        f.nextLine = w.upNext
        if w.total.planned > 0 { f.weekLine = w.line; f.weekSplit = w.split }
        f.changes = store.activeAdaptations.map { "\($0.summary) — \($0.why)" }
        f.pending = store.adaptiveProposals.map(\.text)
        f.cycles = p.trainingMode.includesCycling
        if let v = p.ftpValue { f.ftpLine = "\(v) W — \(p.ftpSourceText)" }
        return f
    }

    /// Stores the question, asks the responder, stores the answer.
    func ask(_ question: String, store: Store, recorderActive: Bool) async {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let journal, !thinking else { return }
        journal.append(CoachChatMessage(at: Date(), source: .athlete, text: q)); revision += 1
        thinking = true
        let r = await responder.reply(to: q, facts: Self.facts(store, recorderActive: recorderActive))
        journal.append(CoachChatMessage(at: Date(), source: r.source, text: r.text, basedOn: r.basedOn))
        thinking = false; revision += 1
    }
}
