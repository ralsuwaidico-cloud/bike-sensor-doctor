import XCTest
@testable import BikeComputer

/// Coach "Review change" (sheet G1): before / after come from the planned session and the engine's own apply; the
/// evidence is the athlete's logged sessions; decisions are stored and shown as what they were, never more.
final class CoachReviewTests: XCTestCase {
    private var cal: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }
    private func at(_ day: Int, _ hour: Int) -> Date { cal.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour))! }
    private let squat = Exercise(id: "ex-003", name: "Goblet squat", equipment: ["kettlebell"], pattern: .squat)
    private func sets(_ n: Int, _ reps: Int, _ kg: Double, rpe: Int? = nil, done: Bool = true) -> [SetEntry] {
        (0..<n).map { _ in var s = SetEntry(); s.reps = reps; s.weightKg = kg; s.rpe = rpe; s.done = done; return s }
    }
    private func planned() -> (Workout, [ExerciseEntry]) {
        var w = Workout(date: at(19, 6), kind: .strength, minutes: 30)
        let e = [ExerciseEntry(exercise: squat, sets: sets(3, 10, 25, done: false))]
        w.plannedEntries = e
        return (w, e)
    }
    private func raise(_ w: Workout) -> PlanAdjustment {
        PlanAdjustment(workoutId: w.id, change: .weight(exerciseId: "ex-003", deltaKg: 2), category: .progression, summary: "Goblet squat: 25 kg → 27 kg",
                       why: "You completed every planned set of Goblet squat (3 × 10) twice.", createdAt: at(18, 9))
    }

    func testBeforeIsThePlanAndAfterIsTheEnginesOwnApply() {
        let (w, e) = planned()
        let c = CoachReview.change(raise(w), workout: w, entries: e, units: .metric)
        XCTAssertEqual(c.label, "Goblet squat")
        XCTAssertEqual(c.before, "25 kg"); XCTAssertEqual(c.beforeSub, "3 × 10")
        XCTAssertEqual(c.after, "27 kg"); XCTAssertEqual(c.afterSub, "3 × 10 · +2 kg (8 %)")
        // exactly what approval would write
        let applied = AdaptiveRules.apply([raise(w)], to: w, entries: e)
        XCTAssertEqual(applied.plannedEntries?.first?.sets.compactMap(\.weightKg), [27, 27, 27])
        XCTAssertEqual(CoachReview.plannedNow(raise(w), workout: applied, entries: applied.plannedEntries ?? [], units: .metric),
                       "In your plan now · \(AdaptationExplainer.day(w.date)): Goblet squat 3 × 10 @ 27 kg")
    }

    func testWithoutThePlannedSessionNoValuesAreMadeUp() {
        let (w, _) = planned()
        let c = CoachReview.change(raise(w), workout: nil, entries: [], units: .metric)
        XCTAssertNil(c.before); XCTAssertNil(c.after); XCTAssertEqual(c.summary, "Goblet squat: 25 kg → 27 kg")
        XCTAssertNil(CoachReview.plannedNow(raise(w), workout: nil, entries: [], units: .metric))
    }

    func testEvidenceIsTheLoggedSessionsAndAMissingEffortIsSaidSo() {
        let (w, e) = planned()
        let a = StrengthSession(date: at(10, 18), minutes: 40, focus: .fullBody, rpe: 7, exercises: [ExerciseEntry(exercise: squat, sets: sets(3, 10, 25))])
        let b = StrengthSession(date: at(14, 18), minutes: 40, focus: .fullBody, exercises: [ExerciseEntry(exercise: squat, sets: sets(3, 10, 25))])
        let old = StrengthSession(date: at(3, 18), minutes: 40, focus: .fullBody, rpe: 9, exercises: [ExerciseEntry(exercise: squat, sets: sets(3, 10, 22.5))])
        let p = AdaptiveProposal(id: "hold|\(raise(w).key)", reason: .heldIncrease, text: "Goblet squat: 25 kg → 27 kg?", why: raise(w).why, adjustments: [raise(w)])
        var i = CoachReview.Input(proposal: p)
        i.workout = w; i.entries = e; i.strength = [old, b, a]; i.now = at(18, 12)
        let m = CoachReview.model(i)
        XCTAssertEqual(m.title, "Goblet squat · \(AdaptationExplainer.day(w.date))")
        XCTAssertEqual(m.stateTag, "NEEDS YOUR APPROVAL"); XCTAssertTrue(m.canApprove)
        XCTAssertEqual(m.evidence.count, 3, "the two most recent sessions the rule read, and the pain line")
        XCTAssertEqual(m.evidence[0].label, "\(AdaptationExplainer.day(a.date)) · 3 × 10 @ 25 kg"); XCTAssertEqual(m.evidence[0].value, "effort 7")
        XCTAssertEqual(m.evidence[1].value, "effort not recorded", "an effort that was not recorded is not filled in")
        XCTAssertEqual(m.evidence[2].value, "none")
        XCTAssertNil(m.evidenceNote)

        let advice = CoachReview.model(.init(proposal: AdaptiveProposal(id: "split", reason: .split, text: "Consider an upper/lower split.", why: "Four strength days.")))
        XCTAssertFalse(advice.canApprove); XCTAssertEqual(advice.stateTag, "ADVICE ONLY"); XCTAssertTrue(advice.changes.isEmpty); XCTAssertTrue(advice.evidence.isEmpty)
        XCTAssertNotNil(advice.evidenceNote)
    }

    func testDecisionsOnTheTimeline() {
        let (w, _) = planned()
        let adj = raise(w)
        func d(_ choice: String, _ day: Int) -> CoachPageFile.Decision {
            .init(proposalId: "hold|\(adj.key)", keys: [adj.key], at: at(day, 10), choice: choice, text: "Goblet squat: 25 kg → 27 kg?", why: adj.why, change: adj.summary)
        }
        // approved and in force: one entry (the decision), with Undo; not listed a second time as a Coach change
        var e = CoachTimeline.entries(.init(summary: nil, proposals: [], applied: [adj], accepted: [], now: at(19, 12), decisions: [d(CoachPageFile.Decision.approved, 18)]))
        XCTAssertEqual(e.count, 1); XCTAssertEqual(e[0].state, "APPROVED"); XCTAssertEqual(e[0].undo, [adj.key]); XCTAssertEqual(e[0].author, .athlete)
        XCTAssertEqual(e[0].text, "Goblet squat: 25 kg → 27 kg"); XCTAssertTrue(e[0].detail?.hasPrefix("Approved by you") == true)
        // approved but not in force (not applied, or the session is finished): no Undo and it says so
        e = CoachTimeline.entries(.init(summary: nil, proposals: [], applied: [], accepted: [], now: at(19, 12), decisions: [d(CoachPageFile.Decision.approved, 18)]))
        XCTAssertEqual(e.count, 1); XCTAssertTrue(e[0].undo.isEmpty); XCTAssertTrue(e[0].detail?.contains("not in force") == true)
        // approved, then undone: both are history; nothing can be undone twice
        e = CoachTimeline.entries(.init(summary: nil, proposals: [], applied: [], accepted: [], now: at(19, 12),
                                        decisions: [d(CoachPageFile.Decision.approved, 18), d(CoachPageFile.Decision.undone, 19)]))
        XCTAssertEqual(e.map(\.state), ["APPROVED", "UNDONE"]); XCTAssertTrue(e.allSatisfy { $0.undo.isEmpty }); XCTAssertTrue(e[0].detail?.contains("undid") == true)
        // declined: plan unchanged, nothing to undo
        e = CoachTimeline.entries(.init(summary: nil, proposals: [], applied: [], accepted: [], now: at(19, 12), decisions: [d(CoachPageFile.Decision.declined, 18)]))
        XCTAssertEqual(e.map(\.state), ["DECLINED"]); XCTAssertTrue(e[0].text.hasPrefix("Declined: ")); XCTAssertTrue(e[0].undo.isEmpty)
        XCTAssertEqual(Set(e.map(\.id)).count, e.count)
        // an automatic change (no decision) still offers the engine's Undo
        e = CoachTimeline.entries(.init(summary: nil, proposals: [], applied: [adj], accepted: [], now: at(19, 12)))
        XCTAssertEqual(e.map(\.kind), [.outcome]); XCTAssertEqual(e[0].undo, [adj.key])
    }

    func testEngineStatesAreNamedOnlyWhenTheEngineProducedThem() {
        let low = AdaptationSummary(at: at(10, 7), confidence: .low, findings: [], feedbackRequest: "Not enough data yet.", painAdvice: "Knee: held.")
        var e = CoachTimeline.entries(.init(summary: low, proposals: [], applied: [], accepted: [], now: at(10, 12)))
        XCTAssertEqual(e.first { $0.id == "ask" }?.state, "NO CHANGE"); XCTAssertEqual(e.first { $0.id == "pain" }?.state, "HELD")
        let ok = AdaptationSummary(at: at(10, 7), confidence: .medium, findings: [], feedbackRequest: "How did it feel?")
        e = CoachTimeline.entries(.init(summary: ok, proposals: [], applied: [], accepted: [], now: at(10, 12)))
        XCTAssertNil(e.first { $0.id == "ask" }?.state)
    }

    func testDecisionsAreStoredAndReadBack() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("coach-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let j = CoachJournal(directory: dir)
        j.see(.init(proposalId: "hold|k", keys: ["k"], text: "Add 2 kg?", why: "Two sessions.", change: "Goblet squat: 25 kg → 27 kg"))
        XCTAssertTrue(j.postpone("hold|k", at: at(18, 9)))
        XCTAssertEqual(CoachJournal(directory: dir).file.seen?.count, 1)
        XCTAssertTrue(j.decide(.init(proposalId: "hold|k", keys: ["k"], at: at(18, 10), choice: CoachPageFile.Decision.approved, text: "Add 2 kg?", why: "Two sessions.", change: "Goblet squat: 25 kg → 27 kg")))
        let again = CoachJournal(directory: dir)
        XCTAssertEqual(again.file.decisions?.map(\.choice), ["approved"]); XCTAssertNil(again.file.seen, "a decided proposal is no longer waiting")
        XCTAssertEqual(again.file.decisions?.first?.at, at(18, 10))
        // a file written before decisions existed still opens
        let old = #"{"schema":1,"messages":[],"links":[]}"#
        try old.data(using: .utf8)!.write(to: dir.appendingPathComponent(CoachJournal.fileName))
        let o = CoachJournal(directory: dir)
        XCTAssertTrue(o.writable); XCTAssertNil(o.file.decisions); XCTAssertNil(o.file.seen)
    }
}
