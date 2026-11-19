import Foundation

// Coach page — the conversation and the shadow policy link. Foundation only (tested on Linux).
//
// THE CONVERSATION ARCHITECTURE (kept for the day a real AI model is connected)
//   question → CoachResponder → CoachReply (text + who produced it + what it is based on) → stored CoachChatMessage.
// Today the only responder is `RulesCoachResponder`: fixed questions answered from the athlete's own records by the
// app's existing logic. A question it cannot answer gets the plain statement that AI chat is not connected.
// No model is called, nothing leaves the phone, and no answer is invented: every sentence is built from `CoachFacts`,
// which the caller fills from the athlete record.

/// Who produced a line. Shown as a chip on every message.
enum CoachSource: String, Codable { case athlete, rules, notConnected
    var chip: String { switch self { case .athlete: return "You"; case .rules: return "Rules"; case .notConnected: return "AI not connected" } }
}

struct CoachReply: Equatable {
    var text: String
    var source: CoachSource
    /// The records the answer was built from ("This week's sessions", "Your FTP and its source").
    var basedOn: [String] = []
}

struct CoachChatMessage: Codable, Equatable, Identifiable {
    var id = UUID()
    var at: Date
    var source: CoachSource
    var text: String
    var basedOn: [String] = []
}

/// The athlete's own records, as plain sentences the existing logic already produces. nil = not known; an answer then
/// says so instead of guessing.
struct CoachFacts: Equatable {
    var todayLine: String? = nil            // "Today: Full body strength, 40 min — planned"
    var nextLine: String? = nil             // "Thu · Strength · Full body 40 min"
    var weekLine: String? = nil             // "2 of 5 sessions done"
    var weekSplit: String? = nil            // "Rides 1 of 3 · Lifts 0 of 2"
    var changes: [String] = []              // applied Coach changes, each "summary — why"
    var pending: [String] = []              // proposals waiting for the athlete
    var ftpLine: String? = nil              // "210 W — entered by you" / nil when unknown
    var cycles: Bool = true
    var onHold: Bool = false
}

enum CoachIntent: String, CaseIterable { case today, week, changes, decisions, ftp, fueling, capabilities }

protocol CoachResponder {
    /// Asynchronous so that a network-backed responder can replace the rules without changing any caller.
    func reply(to question: String, facts: CoachFacts) async -> CoachReply
}

struct RulesCoachResponder: CoachResponder {
    func reply(to question: String, facts: CoachFacts) async -> CoachReply { CoachRules.reply(to: question, facts: facts) }
}

enum CoachRules {
    /// The questions offered as buttons. Each is answered from records by rules.
    static let suggested: [(intent: CoachIntent, question: String)] = [
        (.today, "What should I do today?"),
        (.week, "How is my week going?"),
        (.changes, "Why did my plan change?"),
        (.decisions, "What needs my decision?"),
        (.ftp, "What is my FTP?"),
        (.capabilities, "What can you answer?"),
    ]

    /// Recognises a supported question by its words. Deliberately narrow: anything else is not answered by rules.
    static func classify(_ q: String) -> CoachIntent? {
        let s = " " + q.lowercased().replacingOccurrences(of: "?", with: " ").replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "") + " "
        func has(_ words: String...) -> Bool { words.contains { s.contains($0) } }
        if has("what can you", "what do you", "help") { return .capabilities }
        if has("fuel", " eat", " food", "nutrition", " drink", "hydrat") { return .fueling }
        if has("ftp") { return .ftp }
        if has("decision", "approve", "approval", "pending", "waiting for me") { return .decisions }
        if has("why") && has("change", "adjust", "different", "eased", "moved") { return .changes }
        if has("plan change", "what changed", "adjustments") { return .changes }
        if has("week") { return .week }
        if has("today", "next session", "next workout", "what should i do", "whats next", "what is next") { return .today }
        return nil
    }

    static func reply(to q: String, facts f: CoachFacts) -> CoachReply {
        guard let intent = classify(q) else {
            return CoachReply(text: "AI chat is not connected yet, so I can't answer that. From your records I can answer: "
                                + suggested.dropLast().map(\.question).joined(separator: " · "), source: .notConnected)
        }
        switch intent {
        case .today:
            if f.onHold { return CoachReply(text: "Training is paused by your health check. Review it before the next session.", source: .rules, basedOn: ["Your health check"]) }
            var parts: [String] = []
            if let t = f.todayLine { parts.append(t) }
            if let n = f.nextLine { parts.append("Next: \(n).") }
            return CoachReply(text: parts.isEmpty ? "Nothing is planned today, and nothing else is planned this week." : parts.joined(separator: " "),
                              source: .rules, basedOn: ["Your approved plan"])
        case .week:
            guard let w = f.weekLine else { return CoachReply(text: "There is no plan for this week yet, so there is nothing to count.", source: .rules, basedOn: ["Your approved plan"]) }
            return CoachReply(text: [w, f.weekSplit].compactMap { $0 }.joined(separator: " · ") + ".", source: .rules, basedOn: ["This week's planned and completed sessions"])
        case .changes:
            if f.changes.isEmpty { return CoachReply(text: "The Coach has not changed any upcoming session.", source: .rules, basedOn: ["The Coach's applied changes"]) }
            return CoachReply(text: f.changes.joined(separator: "\n"), source: .rules, basedOn: ["The Coach's applied changes and their reasons"])
        case .decisions:
            if f.pending.isEmpty { return CoachReply(text: "Nothing is waiting for your decision.", source: .rules, basedOn: ["Open Coach proposals"]) }
            return CoachReply(text: "Waiting for you:\n" + f.pending.joined(separator: "\n") + "\nNothing changes unless you approve it.", source: .rules, basedOn: ["Open Coach proposals"])
        case .ftp:
            if !f.cycles { return CoachReply(text: "Your roster has no cycling, so no FTP is kept.", source: .rules, basedOn: ["Your athlete profile"]) }
            return CoachReply(text: f.ftpLine ?? "Your FTP is unknown. Rides use heart rate and effort until you enter it or do an FTP test; no value is guessed.",
                              source: .rules, basedOn: ["Your FTP and its source"])
        case .fueling:
            return CoachReply(text: "Fueling guidance is not available yet. Its wording has to be reviewed by a qualified sports dietitian before Cyclift shows any, and Cyclift does not know what you eat or drink.",
                              source: .rules)
        case .capabilities:
            return CoachReply(text: "I answer from your own records using Cyclift's written rules: " + suggested.dropLast().map(\.question).joined(separator: " · ")
                                + " AI chat is not connected, so I cannot discuss anything else yet.", source: .rules)
        }
    }
}

// MARK: - link to the shadow policy (descriptions only; nothing here can change a plan)

enum CoachShadowMap {
    /// Describes one engine adjustment in the policy's vocabulary, when it has a word for it. nil = the policy has no
    /// description for this kind of change yet, and the page says so instead of showing a check that did not happen.
    static func action(for adj: PlanAdjustment, workout: Workout?) -> ShadowAction? {
        let entry: (String) -> ExerciseEntry? = { id in workout?.plannedEntries?.first { $0.exerciseId == id } }
        switch adj.change {
        case let .weight(e, d):
            guard let x = entry(e), let from = x.sets.compactMap(\.weightKg).max() else { return nil }
            return d > 0 ? .increaseLoad(exercise: x.name, fromKg: from, toKg: from + d) : d < 0 ? .reduceLoad(exercise: x.name, fromKg: from, toKg: max(0, from + d)) : nil
        case let .reps(e, d):
            guard d > 0, let x = entry(e), let from = x.sets.map(\.reps).max() else { return nil }
            return .increaseReps(exercise: x.name, from: from, to: from + d)
        case let .minutes(d):
            guard d < 0, let w = workout, w.minutes + d > 0 else { return nil }
            return .shortenSession(sessionId: w.id.uuidString, fromMinutes: w.minutes, toMinutes: w.minutes + d)
        case .sets, .kind, .intervalReps, .replace:
            return nil
        }
    }

    static func proposal(for adj: PlanAdjustment, workout: Workout?, now: Date) -> ShadowProposal? {
        guard let a = action(for: adj, workout: workout) else { return nil }
        return ShadowProposal(idempotencyKey: ShadowProposal.key(action: a, scope: adj.key), at: now, origin: .rules, action: a, rationale: adj.why, observationIds: [],
                              evidence: [ShadowEvidence(kind: .calculated, source: "Cyclift adaptation rules", label: adj.summary, value: nil)])
    }

    /// One sentence for the timeline: what the independent check concluded.
    static func line(_ d: ShadowDecision) -> String {
        let why = d.reasons.map(\.text).joined(separator: " ")
        switch d.verdict {
        case .rejected: return "Independent policy check: not acceptable. \(why)"
        case .needsAthleteApproval: return "Independent policy check: needs your decision. \(why)"
        case .eligibleAutomatic: return "Independent policy check: within automatic limits. It is still shown to you; nothing is applied automatically."
        case .adviceOnly: return "Independent policy check: advice only; it changes nothing."
        case .duplicate: return "Independent policy check: already checked."
        }
    }
}

// MARK: - what the page stores (its own file; never the athlete record)

/// The Coach page's own small file: the conversation, and which shadow-ledger proposal belongs to which Coach proposal.
struct CoachPageFile: Codable, Equatable {
    struct Link: Codable, Equatable {
        var shadowId: UUID
        var proposalId: String          // AdaptiveProposal.id
        var adjustmentKey: String       // PlanAdjustment.key
        var text: String                // the proposal as the athlete saw it
        var why: String
    }
    /// "Not now" on an open proposal (sheet G1): the athlete deliberately postponed the decision. It is neither an
    /// approval nor a rejection, changes nothing in the plan, and the proposal stays open and reviewable.
    struct Postponed: Codable, Equatable {
        var proposalId: String          // AdaptiveProposal.id
        var at: Date
    }
    var schema = 1
    var messages: [CoachChatMessage] = []
    var links: [Link] = []
    /// Optional so that a file written before postponement existed still opens (nil = none).
    var postponed: [Postponed]? = nil
    /// An open proposal as the athlete saw it, kept so that a later decision can be shown with what it was about.
    struct Seen: Codable, Equatable {
        var proposalId: String          // AdaptiveProposal.id
        var keys: [String]              // PlanAdjustment.key of each change it would make (empty = advice only)
        var text: String
        var why: String
        var change: String?             // the engine's own "Goblet squat: 25 kg → 27 kg" line(s)
    }
    /// What the athlete decided, with its time. Read back from the athlete record (approved / dismissed keys), never
    /// assumed: see CoachCenter.sync.
    struct Decision: Codable, Equatable {
        static let approved = "approved", declined = "declined", dismissed = "dismissed", undone = "undone"
        var proposalId: String
        var keys: [String]
        var at: Date
        var choice: String
        var text: String
        var why: String
        var change: String?
    }
    /// Optional and additive, like `postponed` (nil = none; a file written before they existed still opens).
    var seen: [Seen]? = nil
    var decisions: [Decision]? = nil
}

/// "Not now" means one thing everywhere (owner decision, 19 Nov 2026): the decision is postponed. The suggestion stays
/// open and reviewable, the plan is untouched, and it is neither an approval nor a rejection. Every screen that offers
/// Not now records it here, in the Coach's own file, and reads it from here.
enum CoachPostpone {
    private static var cache: (path: String, stamp: Date?, ids: Set<String>)?
    /// Open suggestions the athlete has postponed. Re-reads the file only when it has changed.
    static func ids(_ directory: URL) -> Set<String> {
        let url = directory.appendingPathComponent(CoachJournal.fileName)
        let stamp = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        if let c = cache, c.path == url.path, c.stamp == stamp { return c.ids }
        let ids = Set((CoachJournal(directory: directory).file.postponed ?? []).map(\.proposalId))
        cache = (url.path, stamp, ids)
        return ids
    }
    /// Records the postponement (once). false = it could not be stored, so nothing may be shown as postponed.
    @discardableResult
    static func record(_ proposalId: String, directory: URL, at: Date = Date()) -> Bool {
        let ok = CoachJournal(directory: directory).postpone(proposalId, at: at)
        cache = nil
        return ok
    }
}

final class CoachJournal {
    static let fileName = "coach-page.json"
    private(set) var file = CoachPageFile()
    /// false when an existing file could not be read: it is left exactly as it is and nothing new is written.
    private(set) var writable = true
    let url: URL

    init(directory: URL) {
        url = directory.appendingPathComponent(CoachJournal.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let d = try? Data(contentsOf: url), let f = try? dec.decode(CoachPageFile.self, from: d) { file = f } else { writable = false }
    }
    func append(_ m: CoachChatMessage) { file.messages.append(m); if file.messages.count > 400 { file.messages.removeFirst(file.messages.count - 400) }; save() }
    func link(_ l: CoachPageFile.Link) { guard !file.links.contains(where: { $0.shadowId == l.shadowId }) else { return }; file.links.append(l); save() }
    /// Records "Not now" for an open proposal (once; the first time is kept). Returns false when nothing could be stored.
    @discardableResult
    func postpone(_ proposalId: String, at: Date) -> Bool {
        guard writable else { return false }
        var list = file.postponed ?? []
        guard !list.contains(where: { $0.proposalId == proposalId }) else { return true }
        list.append(.init(proposalId: proposalId, at: at)); file.postponed = list; save()
        return true
    }
    /// Postponements of proposals that are no longer open are dropped (they were decided, or the Coach withdrew them).
    func prunePostponed(open: Set<String>) {
        guard let list = file.postponed, list.contains(where: { !open.contains($0.proposalId) }) else { return }
        let kept = list.filter { open.contains($0.proposalId) }
        file.postponed = kept.isEmpty ? nil : kept; save()
    }
    func postponedAt(_ proposalId: String) -> Date? { file.postponed?.first { $0.proposalId == proposalId }?.at }
    /// Remembers an open proposal as shown (replaced when its wording changed).
    func see(_ s: CoachPageFile.Seen) {
        var list = file.seen ?? []
        if let i = list.firstIndex(where: { $0.proposalId == s.proposalId }) { guard list[i] != s else { return }; list[i] = s } else { list.append(s) }
        file.seen = list; save()
    }
    /// A proposal that is no longer open without a decision (the Coach withdrew it) is forgotten.
    func unsee(_ proposalId: String) {
        guard let list = file.seen, list.contains(where: { $0.proposalId == proposalId }) else { return }
        let kept = list.filter { $0.proposalId != proposalId }
        file.seen = kept.isEmpty ? nil : kept; save()
    }
    /// Stores a decision (the last 200 are kept). false = it could not be written, so it may not be shown as decided.
    @discardableResult
    func decide(_ d: CoachPageFile.Decision) -> Bool {
        guard writable else { return false }
        let before = file
        var list = file.decisions ?? []
        list.append(d); if list.count > 200 { list.removeFirst(list.count - 200) }
        file.decisions = list
        if let s = file.seen { let kept = s.filter { $0.proposalId != d.proposalId }; file.seen = kept.isEmpty ? nil : kept }
        if save() { return true }
        file = before
        return false
    }
    @discardableResult
    private func save() -> Bool {
        guard writable else { return false }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.sortedKeys]
        guard let d = try? enc.encode(file) else { return false }
        do { try d.write(to: url, options: .atomic); return true } catch { return false }
    }
    static func removeFiles(in directory: URL) {
        for n in [CoachJournal.fileName, ShadowLedger.fileName] { try? FileManager.default.removeItem(at: directory.appendingPathComponent(n)) }
    }
}
