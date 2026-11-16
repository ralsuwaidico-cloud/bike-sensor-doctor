import XCTest
@testable import BikeComputer

/// Coach foundation in shadow mode (owner authorization of 16 Nov 2026). Synthetic fixtures only; Foundation only, so
/// the file runs in the Linux logic tests and in the iOS unit tests. Every test checks data: decisions, the history
/// file, and that the athlete's own file is untouched. The numbers used for "automatic limits" are test values chosen
/// to exercise the mechanism. They are NOT approved limits and exist nowhere in the app.
final class CoachShadowTests: XCTestCase {
    private func tmp(_ tag: String) -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("coach-\(tag)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private var measured: [ShadowEvidence] { [ShadowEvidence(kind: .measured, source: "Synthetic strength log", label: "Squat, last 3 sessions", value: "3 × 8 at 60 kg, all sets completed")] }
    private func athlete(_ s: ShadowTrainingStatus = .allowed, pain: Bool? = false) -> ShadowAthleteSnapshot { ShadowAthleteSnapshot(training: s, unclearedPain: pain, at: t0) }
    private func proposal(_ a: ShadowAction, origin: ShadowOrigin = .rules, evidence: [ShadowEvidence]? = nil, rationale: String = "All sets completed three sessions in a row.", scope: String = "2026-W47") -> ShadowProposal {
        ShadowProposal(idempotencyKey: ShadowProposal.key(action: a, scope: scope), at: t0, origin: origin, action: a, rationale: rationale, observationIds: [], evidence: evidence ?? measured)
    }
    private let smallLoad = ShadowAction.increaseLoad(exercise: "squat", fromKg: 60, toKg: 62.5)
    /// TEST VALUES ONLY — not approved limits.
    private let testLimits = ShadowAutomaticLimits(maxLoadIncreaseFraction: 0.05, maxRepIncrease: 1)

    // MARK: automatic progression stays off

    func testDefaultConfigurationMakesNothingAutomatic() {
        XCTAssertFalse(ShadowPolicyConfig.shadowDefault.automaticProgressionEnabled)
        XCTAssertNil(ShadowPolicyConfig.shadowDefault.automaticLimits)
        XCTAssertTrue(ShadowPolicyConfig.shadowDefault.protectiveAllowlist.isEmpty)
        let actions: [ShadowAction] = [smallLoad, .increaseReps(exercise: "squat", from: 8, to: 9), .reduceLoad(exercise: "squat", fromKg: 60, toKg: 55),
                                       .shortenSession(sessionId: "s1", fromMinutes: 60, toMinutes: 45), .addRestDay(day: "2026-11-18"), .moveSession(sessionId: "s1", fromDay: "2026-11-17", toDay: "2026-11-19")]
        for a in actions {
            let d = ShadowPolicy.evaluate(proposal(a), athlete: athlete(), config: .shadowDefault)
            XCTAssertEqual(d.verdict, .needsAthleteApproval, "\(a.name) must wait for the athlete")
            XCTAssertFalse(d.applied)
        }
    }

    func testSmallIncreaseWithDefaultConfigurationNamesBothMissingApprovals() {
        let d = ShadowPolicy.evaluate(proposal(smallLoad), athlete: athlete(), config: .shadowDefault)
        XCTAssertEqual(d.reasons, [.automaticProgressionDisabled, .automaticLimitsNotApproved])
    }

    func testLimitsAloneDoNotEnableAutomaticProgression() {
        let cfg = ShadowPolicyConfig(automaticProgressionEnabled: false, automaticLimits: testLimits, protectiveAllowlist: [])
        let d = ShadowPolicy.evaluate(proposal(smallLoad), athlete: athlete(), config: cfg)
        XCTAssertEqual(d.verdict, .needsAthleteApproval); XCTAssertEqual(d.reasons, [.automaticProgressionDisabled])
    }

    // MARK: the mechanism, exercised with test limits

    func testWithTestLimitsASmallMeasuredRulesStepIsEligibleAndALargerOneIsNot() {
        let cfg = ShadowPolicyConfig(automaticProgressionEnabled: true, automaticLimits: testLimits, protectiveAllowlist: [])
        XCTAssertEqual(ShadowPolicy.evaluate(proposal(smallLoad), athlete: athlete(), config: cfg).verdict, .eligibleAutomatic)   // 2.5 / 60 = 4.2 %
        XCTAssertEqual(ShadowPolicy.evaluate(proposal(.increaseLoad(exercise: "squat", fromKg: 60, toKg: 63)), athlete: athlete(), config: cfg).verdict, .eligibleAutomatic, "exactly 5 % is within a 5 % limit")
        let big = ShadowPolicy.evaluate(proposal(.increaseLoad(exercise: "squat", fromKg: 60, toKg: 65)), athlete: athlete(), config: cfg)
        XCTAssertEqual(big.verdict, .needsAthleteApproval); XCTAssertEqual(big.reasons, [.exceedsAutomaticLimits])
        XCTAssertEqual(ShadowPolicy.evaluate(proposal(.increaseReps(exercise: "squat", from: 8, to: 9)), athlete: athlete(), config: cfg).verdict, .eligibleAutomatic)
        XCTAssertEqual(ShadowPolicy.evaluate(proposal(.increaseReps(exercise: "squat", from: 8, to: 10)), athlete: athlete(), config: cfg).reasons, [.exceedsAutomaticLimits])
        let first = ShadowPolicy.evaluate(proposal(.increaseLoad(exercise: "squat", fromKg: 0, toKg: 20)), athlete: athlete(), config: cfg)
        XCTAssertEqual(first.reasons, [.exceedsAutomaticLimits], "a first load is never an automatic step")
    }

    func testEvenWithTestLimitsModelOriginEstimatesAndUnknownPainStillNeedTheAthlete() {
        let cfg = ShadowPolicyConfig(automaticProgressionEnabled: true, automaticLimits: testLimits, protectiveAllowlist: [])
        XCTAssertEqual(ShadowPolicy.evaluate(proposal(smallLoad, origin: .model), athlete: athlete(), config: cfg).reasons, [.modelOriginNeedsApproval])
        for k in [ShadowEvidenceKind.calculated, .estimate, .sample] {
            let ev = measured + [ShadowEvidence(kind: k, source: "Synthetic", label: "Estimated 1RM", value: "80 kg")]
            XCTAssertEqual(ShadowPolicy.evaluate(proposal(smallLoad, evidence: ev), athlete: athlete(), config: cfg).reasons, [.evidenceNotMeasuredOrEntered], "\(k)")
        }
        XCTAssertEqual(ShadowPolicy.evaluate(proposal(smallLoad), athlete: athlete(pain: nil), config: cfg).reasons, [.painStatusUnknown])
    }

    // MARK: rejections

    func testIncreasesAreRejectedDuringAHoldUnknownStatusOrUnclearedPain() {
        let cfg = ShadowPolicyConfig(automaticProgressionEnabled: true, automaticLimits: testLimits, protectiveAllowlist: [])
        XCTAssertEqual(ShadowPolicy.evaluate(proposal(smallLoad), athlete: athlete(.onHold), config: cfg), ShadowDecision(verdict: .rejected, reasons: [.healthHold], duplicateOf: nil))
        XCTAssertEqual(ShadowPolicy.evaluate(proposal(smallLoad), athlete: athlete(.unavailable), config: cfg).reasons, [.trainingStatusUnknown])
        XCTAssertEqual(ShadowPolicy.evaluate(proposal(smallLoad), athlete: athlete(pain: true), config: cfg).reasons, [.unclearedPain])
        // a protective proposal is not blocked by a hold: it goes to the athlete
        XCTAssertEqual(ShadowPolicy.evaluate(proposal(.addRestDay(day: "2026-11-18")), athlete: athlete(.onHold), config: cfg).verdict, .needsAthleteApproval)
    }

    func testMalformedUnexplainedOrUnevidencedProposalsAreRejectedWithEveryReason() {
        let bad: [ShadowAction] = [.increaseLoad(exercise: "squat", fromKg: 60, toKg: 60), .increaseLoad(exercise: "", fromKg: 60, toKg: 62.5), .increaseReps(exercise: "squat", from: 8, to: 7),
                                   .reduceLoad(exercise: "squat", fromKg: 60, toKg: 65), .shortenSession(sessionId: "s1", fromMinutes: 45, toMinutes: 60), .moveSession(sessionId: "s1", fromDay: "a", toDay: "a"), .fuelingNote(text: "")]
        for a in bad { XCTAssertEqual(ShadowPolicy.evaluate(proposal(a), athlete: athlete(), config: .shadowDefault).reasons, [.malformedProposal], "\(a)") }
        let d = ShadowPolicy.evaluate(proposal(smallLoad, evidence: [], rationale: "  "), athlete: athlete(), config: .shadowDefault)
        XCTAssertEqual(d.verdict, .rejected); XCTAssertEqual(d.reasons, [.missingRationale, .noEvidence])
        let missing = [ShadowEvidence(kind: .missing, source: "Synthetic", label: "Sleep", value: nil)]
        XCTAssertEqual(ShadowPolicy.evaluate(proposal(smallLoad, evidence: measured + missing), athlete: athlete(), config: .shadowDefault).reasons, [.evidenceMissing])
    }

    func testEveryReasonHasPlainWords() {
        for r in ShadowReason.allCases { XCTAssertFalse(r.text.isEmpty, r.rawValue) }
    }

    // MARK: protective allowlist and advice

    func testProtectiveActionsNeedTheAllowlistAndAdviceChangesNothing() {
        let reduce = ShadowAction.reduceLoad(exercise: "squat", fromKg: 60, toKg: 55)
        XCTAssertEqual(ShadowPolicy.evaluate(proposal(reduce), athlete: athlete(), config: .shadowDefault).reasons, [.notOnProtectiveAllowlist])
        let cfg = ShadowPolicyConfig(automaticProgressionEnabled: false, automaticLimits: nil, protectiveAllowlist: ["reduceLoad"])   // test list, not approved
        XCTAssertEqual(ShadowPolicy.evaluate(proposal(reduce), athlete: athlete(), config: cfg).verdict, .eligibleAutomatic)
        XCTAssertEqual(ShadowPolicy.evaluate(proposal(.addRestDay(day: "2026-11-18")), athlete: athlete(), config: cfg).reasons, [.notOnProtectiveAllowlist], "only the named action")
        XCTAssertEqual(ShadowPolicy.evaluate(proposal(reduce, origin: .model), athlete: athlete(), config: cfg).reasons, [.modelOriginNeedsApproval])
        let advice = ShadowPolicy.evaluate(proposal(.fuelingNote(text: "Synthetic general note")), athlete: athlete(.onHold), config: cfg)
        XCTAssertEqual(advice.verdict, .adviceOnly)
    }

    func testThePolicyIsDeterministic() {
        let p = proposal(smallLoad, origin: .model)
        let first = ShadowPolicy.evaluate(p, athlete: athlete(), config: .shadowDefault)
        for _ in 0..<50 { XCTAssertEqual(ShadowPolicy.evaluate(p, athlete: athlete(), config: .shadowDefault), first) }
    }

    // MARK: history, duplicates, athlete choices

    func testTheSameIntendedChangeIsRecordedOnceHoweverOftenItIsSubmitted() {
        let l = ShadowLedger(directory: tmp("dup"))
        let a = proposal(smallLoad); let again = proposal(smallLoad)          // a different id, the same idempotency key
        XCTAssertNotEqual(a.id, again.id); XCTAssertEqual(a.idempotencyKey, again.idempotencyKey)
        XCTAssertEqual(l.submit(a, athlete: athlete(), now: t0).verdict, .needsAthleteApproval)
        let d = l.submit(again, athlete: athlete(), now: t0.addingTimeInterval(60))
        XCTAssertEqual(d.verdict, .duplicate); XCTAssertEqual(d.duplicateOf, a.id)
        XCTAssertEqual(l.file.proposals.count, 1)
        XCTAssertEqual(l.file.events.map { $0.kind }, [.evaluated, .duplicateIgnored])
        // the same change in another week is a different proposal
        XCTAssertEqual(l.submit(proposal(smallLoad, scope: "2026-W48"), athlete: athlete(), now: t0).verdict, .needsAthleteApproval)
        XCTAssertEqual(l.file.proposals.count, 2)
    }

    func testAnAthleteChoiceIsRecordedOnceAndOnlyForAProposalThatWasWaiting() {
        let l = ShadowLedger(directory: tmp("choice"))
        let waiting = proposal(smallLoad); l.submit(waiting, athlete: athlete(), now: t0)
        let rejected = proposal(.increaseReps(exercise: "row", from: 8, to: 9)); l.submit(rejected, athlete: athlete(.onHold), now: t0)
        XCTAssertTrue(l.recordChoice(.approved, for: waiting.id, now: t0.addingTimeInterval(10)))
        XCTAssertFalse(l.recordChoice(.declined, for: waiting.id, now: t0.addingTimeInterval(20)), "a second answer is ignored")
        XCTAssertFalse(l.recordChoice(.approved, for: rejected.id, now: t0), "a rejected proposal cannot be approved")
        XCTAssertFalse(l.recordChoice(.approved, for: UUID(), now: t0), "an unknown proposal cannot be approved")
        let evs = l.events(for: waiting.id)
        XCTAssertEqual(evs.map { $0.kind }, [.evaluated, .athleteChoice]); XCTAssertEqual(evs.last?.choice, .approved)
        XCTAssertEqual(evs.first?.decision?.applied, false, "an approved proposal is still not applied in shadow mode")
    }

    func testHistorySurvivesRelaunchWithProvenanceAndKeepsRejectingDuplicates() throws {
        let d = tmp("relaunch")
        let p = proposal(smallLoad, origin: .model)
        do { let l = ShadowLedger(directory: d); l.submit(p, athlete: athlete(), now: t0); l.recordChoice(.declined, for: p.id, now: t0.addingTimeInterval(5)) }
        let l2 = ShadowLedger(directory: d)
        XCTAssertEqual(l2.state, .rulesOnly)
        let saved = try XCTUnwrap(l2.proposal(p.id))
        XCTAssertEqual(saved.origin, .model); XCTAssertEqual(saved.evidence, measured); XCTAssertEqual(saved.rationale, p.rationale)
        let ev = try XCTUnwrap(l2.events(for: p.id).first)
        XCTAssertEqual(ev.policyVersion, ShadowLedger.policyVersion); XCTAssertEqual(ev.config, .shadowDefault)
        XCTAssertEqual(ev.decision?.reasons, [.modelOriginNeedsApproval, .automaticProgressionDisabled, .automaticLimitsNotApproved])
        XCTAssertEqual(l2.events(for: p.id).last?.choice, .declined)
        XCTAssertEqual(l2.submit(proposal(smallLoad, origin: .model), athlete: athlete(), now: t0).verdict, .duplicate)
    }

    func testAnUnreadableHistoryIsReportedAndNeverOverwritten() throws {
        let d = tmp("corrupt"); let url = d.appendingPathComponent(ShadowLedger.fileName)
        let garbage = Data("not json".utf8); try garbage.write(to: url)
        let l = ShadowLedger(directory: d)
        XCTAssertEqual(l.state, .historyUnreadable); XCTAssertFalse(l.state.text.isEmpty)
        XCTAssertEqual(l.submit(proposal(smallLoad), athlete: athlete(), now: t0).verdict, .needsAthleteApproval, "the policy still answers")
        XCTAssertEqual(try Data(contentsOf: url), garbage, "the unreadable file is left exactly as it was")
    }

    // MARK: non-mutating, proven against the athlete's own file

    func testTheWholePipelineLeavesTheAthleteRecordAndItsFileUnchanged() throws {
        let d = tmp("store"); let s = Store(directory: d, generatePlan: false)
        let today = Calendar.current.startOfDay(for: Date())
        s.plan = [Workout(date: today.addingTimeInterval(7 * 3600), kind: .endurance, minutes: 60)]
        let storeURL = d.appendingPathComponent("store.json")
        let before = try Data(contentsOf: storeURL); let planBefore = s.plan; let ridesBefore = s.rides; let strengthBefore = s.strength.count

        let snap = ShadowAthleteSnapshot(reading: s, now: t0)
        XCTAssertEqual(snap.training, .allowed); XCTAssertNil(snap.unclearedPain)
        let l = ShadowLedger(directory: d)
        let move = proposal(.moveSession(sessionId: s.plan[0].id.uuidString, fromDay: "2026-11-16", toDay: "2026-11-17"))
        let all = [proposal(smallLoad), proposal(.shortenSession(sessionId: s.plan[0].id.uuidString, fromMinutes: 60, toMinutes: 45)), move, proposal(.addRestDay(day: "2026-11-18"))]
        for p in all { l.submit(p, athlete: snap, now: t0); l.recordChoice(.approved, for: p.id, now: t0.addingTimeInterval(1)) }

        XCTAssertEqual(s.plan, planBefore, "the plan is unchanged"); XCTAssertEqual(s.rides, ridesBefore); XCTAssertEqual(s.strength.count, strengthBefore)
        XCTAssertEqual(try Data(contentsOf: storeURL), before, "store.json is byte-for-byte unchanged")
        XCTAssertTrue(FileManager.default.fileExists(atPath: d.appendingPathComponent(ShadowLedger.fileName).path), "the Coach wrote only its own file")
        XCTAssertEqual(l.file.events.filter { $0.kind == .athleteChoice }.count, 4)
        XCTAssertTrue(l.file.events.allSatisfy { $0.decision?.applied != true }, "nothing is ever marked applied")
    }
}
