import XCTest
@testable import BikeComputer

/// Training Hub v1.4: the recorder's "Next exercise" line follows the same order rule the logger uses.
final class NextExerciseTests: XCTestCase {
    private func ex(_ id: String) -> Exercise { Exercise(id: id, name: id, equipment: [], pattern: .other, muscles: [], unilateral: false, custom: true) }
    private func entry(_ id: String, sets: Int, done: Int = 0, group: String? = nil) -> ExerciseEntry {
        ExerciseEntry(exercise: ex(id), sets: (0..<sets).map { SetEntry(reps: 10, weightKg: 20, done: $0 < done) }, superset: group)
    }

    func testOrdinaryExercisesGoInListOrder() {
        let es = [entry("squat", sets: 3), entry("press", sets: 2)]
        XCTAssertEqual(NextSet.pick(es)?.entry, 0)
        XCTAssertEqual(NextSet.following(es)?.entry, 1, "after the squat comes the press")
        XCTAssertNil(NextSet.following([entry("squat", sets: 3, done: 3), entry("press", sets: 2)]), "the last exercise has nothing after it")
    }

    func testInsideASupersetThePartnerIsNext() {
        let es = [entry("bench", sets: 3, group: "A"), entry("row", sets: 3, group: "A"), entry("pallof", sets: 2)]
        XCTAssertEqual(NextSet.pick(es)?.label, "A1")
        XCTAssertEqual(NextSet.following(es)?.label, "A2", "A1 is followed by A2")
        let afterA1 = [entry("bench", sets: 3, done: 1, group: "A"), entry("row", sets: 3, group: "A"), entry("pallof", sets: 2)]
        XCTAssertEqual(NextSet.pick(afterA1)?.label, "A2"); XCTAssertEqual(NextSet.following(afterA1)?.label, "A1", "then back to A1 for the next round")
        let lastRound = [entry("bench", sets: 3, done: 3, group: "A"), entry("row", sets: 3, done: 2, group: "A"), entry("pallof", sets: 2)]
        XCTAssertEqual(NextSet.following(lastRound)?.entry, 2, "after the last round comes the next exercise")
    }

    func testNothingOpenMeansNothingNext() {
        XCTAssertNil(NextSet.following([entry("squat", sets: 2, done: 2)]))
    }
}
