import XCTest
@testable import BikeComputer

/// Training Hub v1.4 record extensions (owner approval of 16 Nov 2026): optional fields that leave every older record
/// and every older reader's meaning untouched.
final class TrainingHubV14RecordTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_794_000_000)
    private func ex(_ id: String) -> Exercise { Exercise(id: id, name: id, equipment: [], pattern: .other, muscles: [], unilateral: false, custom: true) }
    private func entry(_ id: String, sets: Int, done: Int = 0, group: String? = nil, rest: Int? = nil) -> ExerciseEntry {
        var e = ExerciseEntry(exercise: ex(id), sets: (0..<sets).map { SetEntry(reps: 10, weightKg: 20, done: $0 < done) }, superset: group); e.restSeconds = rest; return e
    }
    private func store() -> Store {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("v14-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return Store(directory: d, generatePlan: false)
    }
    private func json<T: Encodable>(_ v: T) -> String { String(data: try! JSONEncoder().encode(v), encoding: .utf8)! }
    private func decode<T: Decodable>(_ t: T.Type, _ s: String) -> T { try! JSONDecoder().decode(t, from: Data(s.utf8)) }

    // MARK: older records

    func testAnOrdinarySetWritesNoneOfTheNewKeysAndAnOlderSetDecodesUnchanged() {
        let j = json(SetEntry(reps: 8, weightKg: 40, done: true))
        for k in ["skipped", "seconds", "addedKg", "assistKg"] { XCTAssertFalse(j.contains("\"\(k)\""), "an ordinary set must not write \(k)") }
        let old = decode(SetEntry.self, #"{"reps":8,"weightKg":40,"bodyweight":false,"unilateral":false,"done":true}"#)
        XCTAssertEqual(old.kind, .ordinary); XCTAssertNil(old.skipped); XCTAssertNil(old.seconds); XCTAssertNil(old.addedKg); XCTAssertNil(old.assistKg)
        XCTAssertTrue(old.done); XCTAssertEqual(old.weightKg, 40); XCTAssertEqual(old.reps, 8)
        XCTAssertEqual(NextSet.setText(old, .metric), "40 kg × 8", "an older set reads exactly as before")
    }

    func testAnOlderSessionHasNoReviewAndNoSkips() {
        let s = decode(StrengthSession.self, #"{"date":0,"minutes":30,"focus":"fullBody"}"#)
        XCTAssertNil(s.review); XCTAssertNil(s.skippedExercises); XCTAssertNil(s.checkIn)
        XCTAssertFalse(json(StrengthSession(date: t0, minutes: 30, focus: .fullBody)).contains("\"review\""), "no review is written when there is none")
    }

    // MARK: new kinds never look like loaded sets to an older reader

    func testTimedAddedAndAssistedSetsKeepTheOlderFieldsTrue() {
        let base = SetEntry(reps: 8, weightKg: 20, done: false)
        let timed = base.converted(to: .timed), added = base.converted(to: .added, stepKg: 5), assisted = base.converted(to: .assisted, stepKg: 10)
        for s in [timed, added, assisted] {
            XCTAssertTrue(s.bodyweight); XCTAssertNil(s.weightKg, "the older weight field never carries the new meaning")
            XCTAssertNil(s.tonnageKg, "no load × reps is made up for these sets")
        }
        XCTAssertEqual(timed.reps, 0); XCTAssertEqual(timed.seconds, 30); XCTAssertEqual(NextSet.setText(timed, .metric), "30 s hold")
        XCTAssertEqual(NextSet.setText(added, .metric), "BW + 5 kg × 8"); XCTAssertEqual(NextSet.setText(assisted, .metric), "BW − 10 kg assist × 8")
        // what an older reader sees: the same JSON without the new keys is a plain bodyweight set
        let asOld = decode(SetEntry.self, #"{"reps":8,"bodyweight":true,"unilateral":false,"done":true}"#)
        XCTAssertEqual(NextSet.setText(asOld, .metric), "BW × 8")
        // round trip
        XCTAssertEqual(decode(SetEntry.self, json(added)).addedKg, 5); XCTAssertEqual(decode(SetEntry.self, json(timed)).seconds, 30)
        XCTAssertEqual(base.converted(to: .timed).converted(to: .ordinary).kind, .ordinary)
        XCTAssertGreaterThan(base.converted(to: .timed).converted(to: .ordinary).reps, 0)
    }

    // MARK: skipping

    func testASkippedSetIsNotWaitingAndNotDone() {
        var es = [entry("squat", sets: 3), entry("press", sets: 2)]
        es[0].sets[0].skipped = true
        XCTAssertEqual(NextSet.pick(es), NextSet.Pick(entry: 0, set: 1, label: nil), "the skipped set is passed over")
        XCTAssertEqual(es[0].doneSets.count, 0, "a skipped set is never done")
        for i in es[0].sets.indices { es[0].sets[i].skipped = true }
        XCTAssertEqual(NextSet.pick(es)?.entry, 1, "a fully skipped exercise is passed over")
    }

    func testSavingKeepsDoneSetsRemembersSkipsAndWritesOneWorkout() {
        let s = store()
        var a = entry("squat", sets: 3), b = entry("press", sets: 2), c = entry("row", sets: 2)
        a.sets[2].skipped = true
        XCTAssertTrue(s.startStrengthSession(for: nil, template: nil, entries: [a, b, c], name: "Test", now: t0))
        s.updateActiveSession { x in
            x.exercises![0].sets[0].done = true; x.exercises![0].sets[1].done = true; x.exercises![0].sets[2].skipped = true
            x.exercises![1].sets[0].skipped = true; x.exercises![1].sets[1].skipped = true          // press skipped entirely
            x.exercises![2].sets[0].done = true                                                     // row: one done, one left open
        }
        let saved = s.finishActiveSession(rpe: nil, notes: "", now: t0.addingTimeInterval(1800))
        XCTAssertNotNil(saved); XCTAssertNil(s.activeSession)
        XCTAssertEqual(s.strength.filter { $0.id == saved?.id }.count, 1, "exactly one workout in the history")
        let x = s.strength.first { $0.id == saved?.id }!
        XCTAssertEqual(x.exercises?.map(\.name), ["squat", "row"], "order and identity of the exercises that have sets are kept")
        XCTAssertEqual(x.exercises?[0].sets.count, 2); XCTAssertEqual(x.exercises?[0].skippedSets, 1)
        XCTAssertNil(x.exercises?[1].skippedSets, "an open set that was simply not done is not called skipped")
        XCTAssertEqual(x.skippedExercises, ["press"])
        XCTAssertTrue(x.exercises!.allSatisfy { $0.sets.allSatisfy { $0.done && $0.skipped == nil } }, "every saved set is a done set")
        XCTAssertNil(s.finishActiveSession(rpe: nil, notes: ""), "a second Save has nothing to save: no duplicate")
        XCTAssertEqual(s.strength.count, 1)
        // relaunch
        let again = Store(directory: s.dir, generatePlan: false)
        XCTAssertEqual(again.strength.first?.skippedExercises, ["press"]); XCTAssertEqual(again.strength.first?.exercises?[0].skippedSets, 1)
    }

    func testOnlySkippedSetsIsNothingToSave() {
        let s = store()
        XCTAssertTrue(s.startStrengthSession(for: nil, template: nil, entries: [entry("squat", sets: 2)], now: t0))
        s.updateActiveSession { $0.exercises![0].sets[0].skipped = true; $0.exercises![0].sets[1].skipped = true }
        XCTAssertNil(s.finishActiveSession(rpe: nil, notes: "")); XCTAssertNotNil(s.activeSession, "nothing done: the session stays open, nothing is written")
    }

    // MARK: superset rest

    func testSupersetRestComesAfterTheRoundNotBetweenItsMembers() {
        let es = [entry("bench", sets: 3, group: "A", rest: 60), entry("row", sets: 3, group: "A", rest: 90), entry("squat", sets: 2, rest: 120)]
        let a1 = NextSet.pick(es)!
        XCTAssertNil(NextSet.restAfter(es, logged: a1), "A1 → A2 without rest")
        var after = es; after[0].sets[0].done = true
        let a2 = NextSet.pick(after)!; XCTAssertEqual(a2.label, "A2")
        XCTAssertEqual(NextSet.restAfter(after, logged: a2), 90, "after the round: the longest rest of the members")
        XCTAssertEqual(NextSet.restAfter([entry("squat", sets: 2, rest: 120)], logged: NextSet.Pick(entry: 0, set: 0, label: nil)), 120, "an ordinary exercise keeps its own rest")
        // a skipped partner does not hold the round open
        var skipped = es; skipped[1].sets[0].skipped = true
        XCTAssertEqual(NextSet.restAfter(skipped, logged: NextSet.pick(skipped)!), 90)
    }

    // MARK: review

    func testEveryPartOfTheReviewIsOptionalAndUnknownPainIsNotNoPain() {
        XCTAssertTrue(SessionReview().isEmpty)
        let one = SessionReview(effort: 7, at: t0)
        XCTAssertFalse(one.isEmpty); XCTAssertNil(one.pain, "not answered stays unknown"); XCTAssertNil(one.asCheckIn, "one answer is not a complete assessment")
        XCTAssertFalse(json(one).contains("\"pain\""), "an unanswered pain question writes nothing")
        XCTAssertFalse(json(one).contains("\"performance\""))
        let full = SessionReview(intensity: 6, performance: 7, effort: 8, pain: .noPain, at: t0)
        XCTAssertEqual(full.asCheckIn?.effort, 8); XCTAssertEqual(full.asCheckIn?.pain, .noPain)
        XCTAssertEqual(decode(SessionReview.self, json(full)), full)
        XCTAssertNil(decode(SessionReview.self, #"{"effort":0,"performance":11}"#).effort, "values outside 1–10 are not answers")
        XCTAssertEqual(SessionReview(pain: .discomfort).painArea, .other); XCTAssertNil(SessionReview(pain: .noPain, painArea: .knees).painArea)
    }

    func testAPartialReviewIsStoredWithoutACheckInAndACompleteOneIsAlsoACheckIn() {
        let s = store()
        let a = StrengthSession(date: t0, minutes: 30, focus: .fullBody), b = StrengthSession(date: t0.addingTimeInterval(86_400), minutes: 30, focus: .fullBody)
        s.strength = [a, b]
        XCTAssertFalse(s.recordReview(SessionReview(), strengthId: a.id), "an empty review stores nothing"); XCTAssertNil(s.strength[0].review)
        XCTAssertTrue(s.recordReview(SessionReview(intensity: 5, at: t0), strengthId: a.id, now: t0))
        XCTAssertEqual(s.strength.first { $0.id == a.id }?.review?.intensity, 5); XCTAssertNil(s.strength.first { $0.id == a.id }?.checkIn, "a partial review is not a check-in")
        XCTAssertTrue(s.recordReview(SessionReview(performance: 7, effort: 6, pain: .noPain, at: t0), strengthId: b.id, now: t0))
        XCTAssertEqual(s.strength.first { $0.id == b.id }?.checkIn?.performance, 7, "a complete review is also the check-in the Coach already understands")
        let again = Store(directory: s.dir, generatePlan: false)
        XCTAssertEqual(again.strength.first { $0.id == a.id }?.review?.intensity, 5, "the review survives a relaunch")
    }
}
