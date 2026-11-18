import XCTest
@testable import BikeComputer

/// Training Hub v1.4 Finish / Saved / Review wording (sheets 06e, 06f, 06a): counted from the session, nothing invented.
final class FinishReviewTests: XCTestCase {
    private func entry(_ name: String, done: Int, open: Int, skipped: Int = 0) -> ExerciseEntry {
        var sets: [SetEntry] = []
        for _ in 0..<done { var s = SetEntry(reps: 10); s.done = true; sets.append(s) }
        for _ in 0..<open { var s = SetEntry(reps: 10); s.done = false; sets.append(s) }
        for _ in 0..<skipped { var s = SetEntry(reps: 10); s.done = false; s.skipped = true; sets.append(s) }
        return ExerciseEntry(exercise: Exercise(id: "t-" + name, name: name, equipment: []), sets: sets)
    }
    private func session(_ es: [ExerciseEntry], planned: Bool = true, seconds: Int = 2100) -> (StrengthSession, Date) {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var s = StrengthSession(date: start, minutes: 0, focus: .fullBody)
        s.startedAt = start; s.exercises = es; s.workoutId = planned ? UUID() : nil
        return (s, start.addingTimeInterval(TimeInterval(seconds)))
    }

    func testCompleteSessionSaysCompleteAndThePlanWillBeMarked() {
        let (s, now) = session([entry("Goblet squat", done: 3, open: 0), entry("Row", done: 4, open: 0), entry("Press", done: 4, open: 0)])
        let f = FinishSummary.make(s, title: "Full body", now: now)
        XCTAssertEqual(f.state, .complete); XCTAssertEqual(f.statusLine, "Complete")
        XCTAssertEqual(f.setsText, "11 of 11"); XCTAssertEqual(f.timeText, "35 min"); XCTAssertEqual(f.planBefore, "Will be marked done")
        XCTAssertEqual(f.savedLine, "Full body · 11 of 11 sets"); XCTAssertTrue(f.planned)
    }

    func testPartialSessionNamesWhatWasNotDone() {
        let (s, now) = session([entry("Goblet squat", done: 3, open: 0), entry("Row", done: 3, open: 0), entry("Press", done: 3, open: 0), entry("Pallof press", done: 0, open: 2)], seconds: 1980)
        let f = FinishSummary.make(s, title: "Full body", now: now)
        XCTAssertEqual(f.state, .partial); XCTAssertEqual(f.statusLine, "Partial · 9 of 11 sets")
        XCTAssertEqual(f.notDone, "Pallof press · 2 sets"); XCTAssertEqual(f.timeText, "33 min")
        XCTAssertEqual(f.planBefore, "Will be marked done as partial")
        // a skipped set is not done, is counted as skipped, and is never counted as done
        let (t, n2) = session([entry("A", done: 2, open: 1, skipped: 1), entry("B", done: 1, open: 0), entry("C", done: 0, open: 1), entry("D", done: 0, open: 3)])
        let g = FinishSummary.make(t, title: "x", now: n2)
        XCTAssertEqual(g.done, 3); XCTAssertEqual(g.total, 9); XCTAssertEqual(g.skipped, 1); XCTAssertEqual(g.skippedText, "1 set")
        XCTAssertEqual(g.notDone, "A · 2 sets, C · 1 set +1 more")
    }

    func testNothingLoggedOffersNoSaveAndPromisesNothingAboutThePlan() {
        let (s, now) = session([entry("Goblet squat", done: 0, open: 3), entry("Row", done: 0, open: 8)], planned: false, seconds: 240)
        let f = FinishSummary.make(s, title: "Full body", now: now)
        XCTAssertEqual(f.state, .nothing); XCTAssertEqual(f.setsText, "0 of 11"); XCTAssertEqual(f.timeText, "4 min")
        XCTAssertEqual(f.planBefore, "Not marked done"); XCTAssertFalse(f.planned)
        XCTAssertTrue(Store.finishWouldSaveNothing(s), "the page's 'nothing' state is the store's own rule")
        let (u, n3) = session([entry("Row", done: 1, open: 0)], seconds: 10)
        XCTAssertEqual(FinishSummary.make(u, title: "x", now: n3).timeText, "Under 1 min")
    }

    func testReviewWordsMatchTheSheetAndAnUnansweredValueHasNoWord() {
        XCTAssertEqual(ReviewScale.intensity.word(7), "Demanding", "sheet 06a R2")
        XCTAssertEqual(ReviewScale.effort.word(8), "Hard", "sheet 06a R2")
        for s in ReviewScale.allCases {
            XCTAssertEqual(s.word(nil), "Not answered")
            for v in 1...10 { XCTAssertFalse(s.word(v).isEmpty); XCTAssertNotEqual(s.word(v), "Not answered") }
            XCTAssertEqual(s.word(0), s.word(1)); XCTAssertEqual(s.word(99), s.word(10))
        }
        XCTAssertEqual(ReviewScale.effort.word(9), "Very hard"); XCTAssertEqual(ReviewScale.effort.word(10), "Maximal")
    }

    func testFatigueAndEquipmentAreStoredUnderTheirOwnNamesAndOnlyWhenWritten() throws {
        XCTAssertTrue(ReviewNotes().isEmpty); XCTAssertTrue(ReviewNotes(fatigue: "  ", equipment: "\n", note: " ").isEmpty)
        // nothing written: nothing stored, and the review is empty
        XCTAssertTrue(SessionReview(fatigue: "  ", equipment: "").isEmpty)
        let r = SessionReview(effort: 8, note: "short on time", fatigue: " legs heavy ", equipment: "bench wobbles", at: Date(timeIntervalSince1970: 1_800_000_000))   // whole seconds: the stored date format keeps no fractions
        XCTAssertEqual(r.fatigue, "legs heavy"); XCTAssertEqual(r.equipment, "bench wobbles"); XCTAssertEqual(r.note, "short on time", "the note is not mixed with them")
        XCTAssertFalse(SessionReview(fatigue: "tired").isEmpty, "a written word alone is a review")
        // it survives storage under its own keys, and a record written before these keys existed still opens
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let data = try enc.encode(r)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["fatigue"] as? String, "legs heavy"); XCTAssertEqual(json["equipment"] as? String, "bench wobbles")
        XCTAssertEqual(try dec.decode(SessionReview.self, from: data), r)
        let plain = try enc.encode(SessionReview(effort: 6))
        let old = try XCTUnwrap(JSONSerialization.jsonObject(with: plain) as? [String: Any])
        XCTAssertNil(old["fatigue"]); XCTAssertNil(old["equipment"], "absent when nothing was written")
        let before = try dec.decode(SessionReview.self, from: Data(#"{"effort":7,"note":"","at":"2026-11-01T10:00:00Z"}"#.utf8))
        XCTAssertNil(before.fatigue); XCTAssertNil(before.equipment); XCTAssertEqual(before.effort, 7)
        // written words never become a rating or a pain report, and never make a full check-in on their own
        let words = SessionReview(fatigue: "exhausted, 9 out of 10", equipment: "knee sleeve")
        XCTAssertNil(words.effort); XCTAssertNil(words.intensity); XCTAssertNil(words.performance); XCTAssertNil(words.pain); XCTAssertNil(words.asCheckIn)
    }

    func testPainIsUnknownUntilAnsweredAndNoneOnlyWhenSaid() {
        // acceptance D9: an area with no level stores no level and no area; D6: nothing answered is an empty review
        let r = SessionReview(intensity: nil, performance: nil, effort: nil, pain: nil, painArea: .knees, note: "")
        XCTAssertNil(r.pain); XCTAssertNil(r.painArea); XCTAssertTrue(r.isEmpty)
        // three different things: unknown, explicitly none, reported
        let unknown = SessionReview(performance: 6, effort: 7)
        XCTAssertNil(unknown.pain); XCTAssertNil(unknown.asCheckIn, "ratings without a pain answer are not a full check-in: no 'no pain' is assumed")
        let none = SessionReview(performance: 6, effort: 7, pain: .noPain)
        XCTAssertEqual(none.pain, .noPain); XCTAssertEqual(none.asCheckIn?.pain, .noPain)
        let reported = SessionReview(pain: .discomfort, painArea: .knees)
        XCTAssertEqual(reported.pain, .discomfort); XCTAssertEqual(reported.painArea, .knees); XCTAssertFalse(reported.isEmpty)
        // one answer alone is a review, but not a full check-in for the Coach
        let one = SessionReview(effort: 8)
        XCTAssertFalse(one.isEmpty); XCTAssertNil(one.asCheckIn); XCTAssertNil(one.intensity); XCTAssertNil(one.performance)
    }

    // MARK: save lifecycle — Saved only when the file on the phone holds the workout; a retry never duplicates

    private func tmp(_ tag: String) -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("finish-\(tag)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d
    }
    private func start(_ store: Store) {
        var e = entry("Goblet squat", done: 2, open: 1)
        e.sets[2].done = false
        var s = StrengthSession(date: Date(), minutes: 0, focus: .fullBody)
        s.startedAt = Date().addingTimeInterval(-900); s.exercises = [e]
        store.activeSession = s
    }

    func testSavedIsConfirmedFromTheFileAndCheckingAgainWritesNothing() throws {
        let d = tmp("ok"); let store = Store(directory: d, generatePlan: false)
        start(store)
        let saved = try XCTUnwrap(store.finishActiveSession(rpe: nil, notes: ""))
        XCTAssertEqual(store.strengthSaveCheck(saved.id), .confirmed, "in the history and in the file")
        let file = d.appendingPathComponent("store.json")
        let bytes = try Data(contentsOf: file), stamp = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
        for _ in 0..<5 { XCTAssertEqual(store.strengthSaveCheck(saved.id), .confirmed) }
        XCTAssertEqual(try Data(contentsOf: file), bytes, "checking again does not write"); XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date, stamp)
        XCTAssertEqual(store.strength.filter { $0.id == saved.id }.count, 1)
        // a second Save tap has no session left to save: no duplicate, in memory or on disk
        XCTAssertNil(store.finishActiveSession(rpe: nil, notes: "")); XCTAssertEqual(store.strength.count, 1)
        XCTAssertEqual(Store(directory: d, generatePlan: false).strength.count, 1, "one record after a relaunch")
        // unknown workout, unreadable file, and a file that does not hold it are three different answers — none is "confirmed"
        XCTAssertEqual(store.strengthSaveCheck(UUID()), .notInHistory)
        try Data("not json".utf8).write(to: file); XCTAssertEqual(store.strengthSaveCheck(saved.id), .unreadable)
        try Data(#"{"strength":[]}"#.utf8).write(to: file); XCTAssertEqual(store.strengthSaveCheck(saved.id), .notOnDisk)
        try FileManager.default.removeItem(at: file); XCTAssertEqual(store.strengthSaveCheck(saved.id), .unreadable)
    }

    /// The six outcomes of the save lifecycle at the level of the store (owner directive, 18 Nov 2026).
    func testRestartRetryAndWriteAgainNeverLoseOrDuplicateTheWorkout() throws {
        let file = { (d: URL) in d.appendingPathComponent("store.json") }
        // 1. The app closes BEFORE Save (or after a failed save, which writes nothing): the session and its sets are still
        //    there after a restart, and saving then produces exactly one workout.
        let d1 = tmp("restart-before"); var a: Store? = Store(directory: d1, generatePlan: false)
        start(a!); let active = try XCTUnwrap(a!.activeSession); a = nil
        let b = Store(directory: d1, generatePlan: false)
        XCTAssertEqual(b.activeSession?.id, active.id, "the part-logged session survives the restart")
        XCTAssertEqual(b.activeSession?.exercises?.first?.doneSets.count, 2, "with its logged sets"); XCTAssertTrue(b.strength.isEmpty, "nothing was saved")
        let saved = try XCTUnwrap(b.finishActiveSession(rpe: nil, notes: ""))
        XCTAssertEqual(b.strength.count, 1); XCTAssertNil(b.activeSession); XCTAssertEqual(b.strengthSaveCheck(saved.id), .confirmed)
        // 2. The app closes AFTER the write, while the screen still said "not confirmed": a new launch finds the workout
        //    once, nothing in progress, and "Check again" locates it.
        let c = Store(directory: d1, generatePlan: false)
        XCTAssertEqual(c.strength.map(\.id), [saved.id]); XCTAssertNil(c.activeSession); XCTAssertEqual(c.strengthSaveCheck(saved.id), .confirmed)
        XCTAssertNil(c.finishActiveSession(rpe: nil, notes: ""), "there is nothing left to save again"); XCTAssertEqual(c.strength.count, 1)
        // 3. The write happened but the file read back does not hold the workout: writing again stores the SAME record
        //    (same identifier) and the check then confirms it. One workout in memory, one on disk, one after a relaunch.
        try Data(#"{"strength":[]}"#.utf8).write(to: file(d1))
        XCTAssertEqual(c.strengthSaveCheck(saved.id), .notOnDisk)
        XCTAssertTrue(c.writeAgain()); XCTAssertEqual(c.strengthSaveCheck(saved.id), .confirmed); XCTAssertEqual(c.strength.count, 1)
        XCTAssertTrue(c.writeAgain()); XCTAssertTrue(c.writeAgain(), "writing again any number of times adds nothing")
        let e = Store(directory: d1, generatePlan: false)
        XCTAssertEqual(e.strength.map(\.id), [saved.id], "exactly one record after the retries and a relaunch")
        XCTAssertEqual(e.strength.first?.exercises?.first?.sets.count, 2, "the two logged sets, and only those")
        // 4. An inconclusive read-back (the file cannot be read just now) is not a failure and not a confirmation; the
        //    workout stays in the app's history untouched.
        try Data("not json".utf8).write(to: file(d1))
        XCTAssertEqual(e.strengthSaveCheck(saved.id), .unreadable); XCTAssertEqual(e.strength.count, 1)
    }
}
