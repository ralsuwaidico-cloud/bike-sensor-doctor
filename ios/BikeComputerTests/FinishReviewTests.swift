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

    func testCoachNotesStoreOnlyWhatWasWrittenAndAnAreaAloneReportsNoPain() {
        XCTAssertEqual(ReviewNotes().composed, ""); XCTAssertEqual(ReviewNotes(fatigue: "  ", equipment: "\n", note: " ").composed, "")
        XCTAssertEqual(ReviewNotes(fatigue: "legs heavy", equipment: "", note: "short on time").composed, "Fatigue: legs heavy\nshort on time")
        XCTAssertEqual(ReviewNotes(fatigue: "", equipment: "bench wobbles", note: "").composed, "Equipment: bench wobbles")
        // acceptance D9: an area with no level stores no level and no area; D6: nothing answered is an empty review
        let r = SessionReview(intensity: nil, performance: nil, effort: nil, pain: nil, painArea: .knees, note: "")
        XCTAssertNil(r.pain); XCTAssertNil(r.painArea); XCTAssertTrue(r.isEmpty)
        // one answer alone is a review, but not a full check-in for the Coach
        let one = SessionReview(effort: 8)
        XCTAssertFalse(one.isEmpty); XCTAssertNil(one.asCheckIn); XCTAssertNil(one.intensity); XCTAssertNil(one.performance)
    }
}
