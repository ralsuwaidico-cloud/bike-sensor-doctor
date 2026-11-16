import Foundation

// Coach foundation — SHADOW MODE (owner authorization of 16 Nov 2026).
//
// What this file is: the structured vocabulary of the future Coach (observation → proposal → policy decision →
// athlete decision), an independent deterministic policy evaluation, and an append-only decision history with
// provenance and duplicate protection.
//
// What this file cannot do, by construction:
//   • it has no reference to `Store`'s setters, the plan, rides or strength logs, and no function that applies a
//     proposal. A proposal is a description; nothing here turns it into a change.
//   • it writes only its own file (`coach-shadow.json`) in a directory it is given, never `store.json`.
//   • it contacts no network service and no AI model. `ShadowOrigin.model` exists only so the policy can already say
//     how such a proposal would be treated.
//
// Not approved and therefore not built in: any limit for an "automatic small step", any protective-action allowlist.
// Both are parameters that default to "nothing is automatic".

// MARK: evidence and observations

/// How a value came to exist. Mirrors Master Instructions §9; a proposal may not present an estimate as a measurement.
enum ShadowEvidenceKind: String, Codable, CaseIterable { case measured, userEntered, calculated, estimate, sample, missing }

struct ShadowEvidence: Codable, Equatable {
    var kind: ShadowEvidenceKind
    /// Where it came from, in words an athlete can read ("Strength log, 14 Nov", "Entered in Profile").
    var source: String
    var label: String
    /// The value as shown, with its unit. nil when `kind` is `.missing`.
    var value: String?
}

struct ShadowObservation: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var at: Date
    var topic: String
    var summary: String
    var evidence: [ShadowEvidence]
}

// MARK: proposals

enum ShadowOrigin: String, Codable { case rules, model }

/// What the Coach would like to happen. Descriptions only.
enum ShadowAction: Codable, Equatable {
    case increaseLoad(exercise: String, fromKg: Double, toKg: Double)
    case increaseReps(exercise: String, from: Int, to: Int)
    case reduceLoad(exercise: String, fromKg: Double, toKg: Double)
    case shortenSession(sessionId: String, fromMinutes: Int, toMinutes: Int)
    case addRestDay(day: String)
    case moveSession(sessionId: String, fromDay: String, toDay: String)
    case fuelingNote(text: String)

    enum Category: String, Codable { case increase, protective, schedule, advice }
    var category: Category {
        switch self {
        case .increaseLoad, .increaseReps: return .increase
        case .reduceLoad, .shortenSession, .addRestDay: return .protective
        case .moveSession: return .schedule
        case .fuelingNote: return .advice
        }
    }
    /// A stable name for allowlists and history ("reduceLoad"), without the values.
    var name: String {
        switch self {
        case .increaseLoad: return "increaseLoad"
        case .increaseReps: return "increaseReps"
        case .reduceLoad: return "reduceLoad"
        case .shortenSession: return "shortenSession"
        case .addRestDay: return "addRestDay"
        case .moveSession: return "moveSession"
        case .fuelingNote: return "fuelingNote"
        }
    }
    /// The proposal describes a real change in the stated direction. A malformed one is rejected, never "fixed".
    var isWellFormed: Bool {
        switch self {
        case let .increaseLoad(e, f, t): return !e.isEmpty && f >= 0 && t > f && t.isFinite
        case let .increaseReps(e, f, t): return !e.isEmpty && f >= 0 && t > f
        case let .reduceLoad(e, f, t): return !e.isEmpty && t >= 0 && t < f && f.isFinite
        case let .shortenSession(s, f, t): return !s.isEmpty && t > 0 && t < f
        case let .addRestDay(d): return !d.isEmpty
        case let .moveSession(s, f, t): return !s.isEmpty && !f.isEmpty && !t.isEmpty && f != t
        case let .fuelingNote(text): return !text.isEmpty
        }
    }
}

struct ShadowProposal: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    /// The same intended change must carry the same key however often it is generated (retries, relaunch, two devices).
    var idempotencyKey: String
    var at: Date
    var origin: ShadowOrigin
    var action: ShadowAction
    var rationale: String
    var observationIds: [UUID]
    var evidence: [ShadowEvidence]

    /// The key the generator should use: what would change and for which training week, not when it was computed.
    static func key(action: ShadowAction, scope: String) -> String { "\(action.name)|\(scope)|\(action)" }
}

// MARK: the athlete facts the policy may read

enum ShadowTrainingStatus: String, Codable { case allowed, onHold, unavailable }

/// A read-only copy of the few athlete facts the policy needs. Built by the caller; the policy never sees the Store.
struct ShadowAthleteSnapshot: Codable, Equatable {
    var training: ShadowTrainingStatus
    /// The athlete reported pain that has not been cleared. nil = not known.
    var unclearedPain: Bool?
    var at: Date
}

// MARK: policy

/// Limits for a step small enough to be applied without asking. NOT APPROVED: no value of this type exists in the app.
/// Tests construct one with obviously synthetic numbers to exercise the mechanism.
struct ShadowAutomaticLimits: Codable, Equatable {
    var maxLoadIncreaseFraction: Double
    var maxRepIncrease: Int
}

struct ShadowPolicyConfig: Codable, Equatable {
    /// Master switch. false in every configuration the app can build today.
    var automaticProgressionEnabled: Bool
    var automaticLimits: ShadowAutomaticLimits?
    /// Names of protective actions that may be applied without asking. Empty until the owner approves a list.
    var protectiveAllowlist: [String]

    /// The only configuration available outside tests: nothing is automatic.
    static let shadowDefault = ShadowPolicyConfig(automaticProgressionEnabled: false, automaticLimits: nil, protectiveAllowlist: [])
}

enum ShadowReason: String, Codable, CaseIterable {
    // rejections
    case malformedProposal, missingRationale, noEvidence, evidenceMissing, healthHold, trainingStatusUnknown, unclearedPain, painStatusUnknown
    // approval requirements
    case automaticProgressionDisabled, automaticLimitsNotApproved, exceedsAutomaticLimits, evidenceNotMeasuredOrEntered
    case modelOriginNeedsApproval, notOnProtectiveAllowlist, scheduleChangeNeedsApproval
    // informational
    case adviceOnly

    var text: String {
        switch self {
        case .malformedProposal: return "The proposal does not describe a valid change."
        case .missingRationale: return "The proposal gives no reason."
        case .noEvidence: return "The proposal cites no evidence."
        case .evidenceMissing: return "The proposal relies on information that is missing."
        case .healthHold: return "Training is paused by the health check, so nothing may be increased."
        case .trainingStatusUnknown: return "The training status could not be read, so nothing may be increased."
        case .unclearedPain: return "Pain was reported and has not been cleared, so nothing may be increased."
        case .painStatusUnknown: return "It is not known whether pain was reported, so an increase needs the athlete's decision."
        case .automaticProgressionDisabled: return "Automatic progression is switched off."
        case .automaticLimitsNotApproved: return "No limits for automatic steps have been approved."
        case .exceedsAutomaticLimits: return "The step is larger than the approved automatic limit."
        case .evidenceNotMeasuredOrEntered: return "The evidence includes an estimate, a calculation or sample data."
        case .modelOriginNeedsApproval: return "The proposal was written by an AI model."
        case .notOnProtectiveAllowlist: return "This protective action is not on the approved list."
        case .scheduleChangeNeedsApproval: return "Changes to the schedule are the athlete's decision."
        case .adviceOnly: return "General advice; it changes nothing."
        }
    }
}

enum ShadowVerdict: String, Codable { case rejected, needsAthleteApproval, eligibleAutomatic, adviceOnly, duplicate }

struct ShadowDecision: Codable, Equatable {
    var verdict: ShadowVerdict
    var reasons: [ShadowReason]
    /// For `.duplicate`: the proposal already recorded under the same idempotency key.
    var duplicateOf: UUID?
    /// Always false in this file: shadow mode never applies anything. Present so history can never be misread.
    var applied: Bool = false
}

/// Deterministic: the same proposal, snapshot and configuration always give the same decision. No clock, no randomness,
/// no stored state. Independent of whatever produced the proposal.
enum ShadowPolicy {
    static func evaluate(_ p: ShadowProposal, athlete: ShadowAthleteSnapshot, config: ShadowPolicyConfig) -> ShadowDecision {
        // 1. Things that make a proposal unacceptable whoever approves it.
        var reject: [ShadowReason] = []
        if !p.action.isWellFormed { reject.append(.malformedProposal) }
        if p.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { reject.append(.missingRationale) }
        if p.evidence.isEmpty { reject.append(.noEvidence) }
        if p.evidence.contains(where: { $0.kind == .missing }) { reject.append(.evidenceMissing) }
        if p.action.category == .increase {
            switch athlete.training {
            case .onHold: reject.append(.healthHold)
            case .unavailable: reject.append(.trainingStatusUnknown)
            case .allowed: break
            }
            if athlete.unclearedPain == true { reject.append(.unclearedPain) }
        }
        if !reject.isEmpty { return ShadowDecision(verdict: .rejected, reasons: reject, duplicateOf: nil) }

        // 2. Advice changes nothing.
        if p.action.category == .advice { return ShadowDecision(verdict: .adviceOnly, reasons: [.adviceOnly], duplicateOf: nil) }

        // 3. Everything that requires the athlete's decision.
        var ask: [ShadowReason] = []
        if p.origin == .model { ask.append(.modelOriginNeedsApproval) }
        if p.evidence.contains(where: { $0.kind != .measured && $0.kind != .userEntered }) { ask.append(.evidenceNotMeasuredOrEntered) }
        switch p.action.category {
        case .schedule:
            ask.append(.scheduleChangeNeedsApproval)
        case .protective:
            if !config.protectiveAllowlist.contains(p.action.name) { ask.append(.notOnProtectiveAllowlist) }
        case .increase:
            if athlete.unclearedPain == nil { ask.append(.painStatusUnknown) }
            if !config.automaticProgressionEnabled { ask.append(.automaticProgressionDisabled) }
            if let lim = config.automaticLimits {
                if !within(lim, p.action) { ask.append(.exceedsAutomaticLimits) }
            } else { ask.append(.automaticLimitsNotApproved) }
        case .advice:
            break
        }
        if !ask.isEmpty { return ShadowDecision(verdict: .needsAthleteApproval, reasons: ask, duplicateOf: nil) }
        return ShadowDecision(verdict: .eligibleAutomatic, reasons: [], duplicateOf: nil)
    }

    private static func within(_ lim: ShadowAutomaticLimits, _ a: ShadowAction) -> Bool {
        switch a {
        case let .increaseLoad(_, f, t):
            guard f > 0 else { return false }                       // a first load is never an automatic step
            return (t - f) / f <= lim.maxLoadIncreaseFraction + 1e-9
        case let .increaseReps(_, f, t):
            return t - f <= lim.maxRepIncrease
        default:
            return false
        }
    }
}

// MARK: decision history

enum ShadowAthleteChoice: String, Codable { case approved, declined }

struct ShadowEvent: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case evaluated, duplicateIgnored, athleteChoice }
    var id: UUID = UUID()
    var at: Date
    var kind: Kind
    var proposalId: UUID
    var decision: ShadowDecision?
    var choice: ShadowAthleteChoice?
    /// Which rules produced the decision, so an old entry can still be explained after the rules change.
    var policyVersion: Int
    var config: ShadowPolicyConfig?
}

/// What the Coach can currently offer. A missing model is a normal state with a plain description, not an error.
enum ShadowCoachState: String, Codable {
    case rulesOnly, modelUnavailable, historyUnreadable
    var text: String {
        switch self {
        case .rulesOnly: return "Coach guidance comes from Cyclift's built-in rules."
        case .modelUnavailable: return "The AI Coach is not available right now. Cyclift's built-in rules still apply."
        case .historyUnreadable: return "The Coach history could not be read. Nothing was changed; new entries are not being recorded."
        }
    }
}

/// Append-only history of proposals, decisions and athlete choices, in its own file. Entries are never edited or removed
/// by this type. Recording an athlete's "approved" here changes nothing else: there is no code path from this file to
/// the plan.
final class ShadowLedger {
    static let fileName = "coach-shadow.json"
    static let policyVersion = 1

    struct File: Codable, Equatable {
        var schema: Int = 1
        var proposals: [ShadowProposal] = []
        var events: [ShadowEvent] = []
    }

    private(set) var file = File()
    private(set) var state: ShadowCoachState = .rulesOnly
    let url: URL

    init(directory: URL) {
        url = directory.appendingPathComponent(ShadowLedger.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        if let d = try? Data(contentsOf: url), let f = try? dec.decode(File.self, from: d) { file = f }
        else { state = .historyUnreadable }          // keep the unreadable file exactly as it is; never overwrite it
    }

    func proposal(_ id: UUID) -> ShadowProposal? { file.proposals.first { $0.id == id } }
    func events(for id: UUID) -> [ShadowEvent] { file.events.filter { $0.proposalId == id } }

    /// Evaluates and records a proposal. A proposal whose idempotency key is already recorded is not evaluated again:
    /// the answer is `.duplicate` and points at the first one.
    @discardableResult
    func submit(_ p: ShadowProposal, athlete: ShadowAthleteSnapshot, config: ShadowPolicyConfig = .shadowDefault, now: Date) -> ShadowDecision {
        if let first = file.proposals.first(where: { $0.idempotencyKey == p.idempotencyKey }) {
            let d = ShadowDecision(verdict: .duplicate, reasons: [], duplicateOf: first.id)
            append(ShadowEvent(at: now, kind: .duplicateIgnored, proposalId: first.id, decision: d, choice: nil, policyVersion: ShadowLedger.policyVersion, config: nil))
            return d
        }
        let d = ShadowPolicy.evaluate(p, athlete: athlete, config: config)
        file.proposals.append(p)
        append(ShadowEvent(at: now, kind: .evaluated, proposalId: p.id, decision: d, choice: nil, policyVersion: ShadowLedger.policyVersion, config: config))
        return d
    }

    /// Records the athlete's answer to a proposal that was waiting for one. Returns false (and records nothing) when the
    /// proposal is unknown, was not waiting for an answer, or has already been answered.
    @discardableResult
    func recordChoice(_ choice: ShadowAthleteChoice, for id: UUID, now: Date) -> Bool {
        let evs = events(for: id)
        guard let evaluated = evs.first(where: { $0.kind == .evaluated }), evaluated.decision?.verdict == .needsAthleteApproval else { return false }
        guard !evs.contains(where: { $0.kind == .athleteChoice }) else { return false }
        append(ShadowEvent(at: now, kind: .athleteChoice, proposalId: id, decision: nil, choice: choice, policyVersion: ShadowLedger.policyVersion, config: nil))
        return true
    }

    private func append(_ e: ShadowEvent) {
        file.events.append(e)
        guard state != .historyUnreadable else { return }
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601; enc.outputFormatting = [.sortedKeys]
        if let d = try? enc.encode(file) { try? d.write(to: url, options: .atomic) }
    }
}

// MARK: interface to the existing athlete record (read-only)

extension ShadowAthleteSnapshot {
    /// Reads the one fact the policy needs today from the athlete record. It reads; it assigns nothing on `store`.
    /// Pain status is not derived here yet (nil = not known), so in shadow mode every increase still asks the athlete.
    init(reading store: Store, now: Date) {
        let t: ShadowTrainingStatus
        switch store.trainingAuthority {
        case .allowed: t = .allowed
        case .onHold: t = .onHold
        case .unavailable: t = .unavailable
        }
        self.init(training: t, unclearedPain: nil, at: now)
    }
}
