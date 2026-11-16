import XCTest
@testable import BikeComputer

/// Coach conversation: supported questions are answered from the athlete's records by rules and say so; anything else
/// says that AI chat is not connected. The shadow-policy link describes proposals and can change nothing.
final class CoachChatTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_794_000_000)
    private let squat = Exercise(id: "squat", name: "Goblet squat", equipment: ["dumbbell"], pattern: .squat, muscles: [], unilateral: false, custom: true)
    private func dir() -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("coach-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }

    func testEverySuggestedQuestionIsRecognisedAsItsOwnIntent() {
        for s in CoachRules.suggested { XCTAssertEqual(CoachRules.classify(s.question), s.intent, s.question) }
    }

    func testUnsupportedQuestionSaysAIChatIsNotConnectedAndInventsNothing() {
        let r = CoachRules.reply(to: "Should I change my saddle height?", facts: CoachFacts(weekLine: "2 of 5 sessions done", ftpLine: "210 W"))
        XCTAssertEqual(r.source, .notConnected)
        XCTAssertTrue(r.text.hasPrefix("AI chat is not connected yet"))
        XCTAssertFalse(r.text.contains("210") || r.text.contains("2 of 5"), "no athlete figure appears in an answer that was not asked for")
    }

    func testAnswersUseOnlyTheSuppliedFacts() {
        var f = CoachFacts(todayLine: "Today: Full body, 40 min — planned.", nextLine: "Thu · Endurance 60 min", weekLine: "2 of 5 sessions done", weekSplit: "Rides 1 of 3 · Lifts 1 of 2")
        XCTAssertEqual(CoachRules.reply(to: "What should I do today?", facts: f).text, "Today: Full body, 40 min — planned. Next: Thu · Endurance 60 min.")
        XCTAssertEqual(CoachRules.reply(to: "How is my week going?", facts: f).text, "2 of 5 sessions done · Rides 1 of 3 · Lifts 1 of 2.")
        XCTAssertEqual(CoachRules.reply(to: "Why did my plan change?", facts: f).text, "The Coach has not changed any upcoming session.")
        f.changes = ["Thu ride: 60 → 50 min — two hard sessions in three days."]
        XCTAssertEqual(CoachRules.reply(to: "why was my plan changed", facts: f).text, "Thu ride: 60 → 50 min — two hard sessions in three days.")
        XCTAssertEqual(CoachRules.reply(to: "What needs my decision?", facts: f).text, "Nothing is waiting for your decision.")
        XCTAssertTrue(CoachRules.suggested.dropLast().allSatisfy { CoachRules.reply(to: $0.question, facts: f).source == .rules })
    }

    func testUnknownFTPIsSaidPlainlyAndNeverGuessed() {
        let r = CoachRules.reply(to: "What is my FTP?", facts: CoachFacts())
        XCTAssertTrue(r.text.hasPrefix("Your FTP is unknown")); XCTAssertNil(r.text.range(of: "[0-9]", options: .regularExpression), "no number in the answer")
        XCTAssertEqual(CoachRules.reply(to: "ftp?", facts: CoachFacts(ftpLine: "210 W — entered by you")).text, "210 W — entered by you")
    }

    func testHealthHoldComesFirstForToday() {
        XCTAssertTrue(CoachRules.reply(to: "What should I do today?", facts: CoachFacts(todayLine: "Today: Intervals", onHold: true)).text.hasPrefix("Training is paused"))
    }

    func testFuelingIsNotAvailableAndGivesNoAdvice() {
        let r = CoachRules.reply(to: "What should I eat before my ride?", facts: CoachFacts())
        XCTAssertTrue(r.text.hasPrefix("Fueling guidance is not available yet"))
        XCTAssertNil(r.text.range(of: "[0-9]", options: .regularExpression))
    }

    func testShadowMappingDescribesWhatItCanAndRefusesTheRest() {
        var w = Workout(date: t0, kind: .strength, minutes: 40)
        let e = ExerciseEntry(exercise: squat, sets: [SetEntry(reps: 10, weightKg: 20), SetEntry(reps: 10, weightKg: 20)])
        w.plannedEntries = [e]
        func adj(_ c: PlanAdjustment.Change) -> PlanAdjustment { PlanAdjustment(workoutId: w.id, change: c, category: .progression, summary: "s", why: "because", createdAt: t0) }
        XCTAssertEqual(CoachShadowMap.action(for: adj(.weight(exerciseId: "squat", deltaKg: 1)), workout: w), .increaseLoad(exercise: "Goblet squat", fromKg: 20, toKg: 21))
        XCTAssertEqual(CoachShadowMap.action(for: adj(.reps(exerciseId: "squat", delta: 1)), workout: w), .increaseReps(exercise: "Goblet squat", from: 10, to: 11))
        XCTAssertEqual(CoachShadowMap.action(for: adj(.minutes(delta: -10)), workout: w), .shortenSession(sessionId: w.id.uuidString, fromMinutes: 40, toMinutes: 30))
        XCTAssertNil(CoachShadowMap.action(for: adj(.sets(exerciseId: "squat", delta: 1)), workout: w), "no word for it yet: no check is claimed")
        XCTAssertNil(CoachShadowMap.action(for: adj(.weight(exerciseId: "other", deltaKg: 1)), workout: w), "an unknown starting weight is never assumed")
        XCTAssertNil(CoachShadowMap.action(for: adj(.minutes(delta: 10)), workout: w))
    }

    func testAnIncreaseAlwaysNeedsTheAthleteInShadowMode() {
        var w = Workout(date: t0, kind: .strength, minutes: 40)
        w.plannedEntries = [ExerciseEntry(exercise: squat, sets: [SetEntry(reps: 10, weightKg: 20)])]
        let a = PlanAdjustment(workoutId: w.id, change: .weight(exerciseId: "squat", deltaKg: 1), category: .progression, summary: "20 → 21 kg", why: "All reps done twice.", createdAt: t0)
        let p = CoachShadowMap.proposal(for: a, workout: w, now: t0)!
        let ledger = ShadowLedger(directory: dir())
        let d = ledger.submit(p, athlete: ShadowAthleteSnapshot(training: .allowed, pain: .unavailable, at: t0), now: t0)
        XCTAssertEqual(d.verdict, .needsAthleteApproval); XCTAssertFalse(d.applied)
        XCTAssertTrue(d.reasons.contains(.automaticProgressionDisabled))
        XCTAssertTrue(CoachShadowMap.line(d).hasPrefix("Independent policy check: needs your decision."))
        // the same adjustment generated again is one proposal, not two
        let again = CoachShadowMap.proposal(for: a, workout: w, now: t0.addingTimeInterval(60))!
        XCTAssertEqual(ledger.submit(again, athlete: ShadowAthleteSnapshot(training: .allowed, pain: .unavailable, at: t0), now: t0).verdict, .duplicate)
        XCTAssertEqual(ledger.file.proposals.count, 1)
    }

    func testConversationAndLinksSurviveARelaunchAndDeleteRemovesThem() {
        let d = dir()
        let j = CoachJournal(directory: d)
        j.append(CoachChatMessage(at: t0, source: .athlete, text: "What is my FTP?"))
        j.append(CoachChatMessage(at: t0, source: .rules, text: "Your FTP is unknown.", basedOn: ["Your FTP and its source"]))
        let id = UUID()
        j.link(.init(shadowId: id, proposalId: "hold|x", adjustmentKey: "k", text: "Add a set?", why: "w")); j.link(.init(shadowId: id, proposalId: "hold|x", adjustmentKey: "k", text: "Add a set?", why: "w"))
        let again = CoachJournal(directory: d)
        XCTAssertEqual(again.file.messages.map(\.text), ["What is my FTP?", "Your FTP is unknown."]); XCTAssertEqual(again.file.links.count, 1)
        CoachJournal.removeFiles(in: d)
        XCTAssertTrue(CoachJournal(directory: d).file.messages.isEmpty)
    }

    func testAnUnreadableConversationFileIsLeftAsItIs() {
        let d = dir(); let u = d.appendingPathComponent(CoachJournal.fileName)
        try? Data("not json".utf8).write(to: u)
        let j = CoachJournal(directory: d); XCTAssertFalse(j.writable)
        j.append(CoachChatMessage(at: t0, source: .athlete, text: "x"))
        XCTAssertEqual(try? String(contentsOf: u, encoding: .utf8), "not json")
    }

    func testTimelineCarriesChecksClosedDecisionsAndChatInTimeOrder() {
        let p = AdaptiveProposal(id: "hold|x", reason: .heldIncrease, text: "Add 1 kg?", why: "w",
                                 adjustments: [PlanAdjustment(workoutId: UUID(), change: .minutes(delta: -5), category: .reduction, summary: "s", why: "w", createdAt: t0)])
        let e = CoachTimeline.entries(.init(summary: nil, proposals: [p], applied: [], accepted: [], now: t0.addingTimeInterval(300), checks: ["hold|x": "Independent policy check: needs your decision."],
                                            closed: [.init(id: "c", at: t0, text: "Ease Thursday?", why: "w", approved: false, check: nil)],
                                            chat: [CoachChatMessage(at: t0.addingTimeInterval(100), source: .athlete, text: "q"), CoachChatMessage(at: t0.addingTimeInterval(101), source: .notConnected, text: "a")]))
        XCTAssertEqual(e.map(\.kind), [.decision, .question, .answer, .proposal])
        XCTAssertEqual(e[0].text, "Declined: Ease Thursday?"); XCTAssertEqual(e[2].chip, "AI not connected"); XCTAssertEqual(e[3].check, "Independent policy check: needs your decision.")
    }
}
