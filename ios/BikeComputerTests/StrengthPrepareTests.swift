import XCTest
@testable import BikeComputer

/// Training Hub v1.4 preparation screen (sheet 01a "J2"): the rows are the session's own planned entries, in order.
final class StrengthPrepareTests: XCTestCase {
    private func ex(_ id: String, _ name: String, _ equipment: [String]) -> Exercise {
        Exercise(id: id, name: name, equipment: equipment)
    }
    private func entry(_ e: Exercise, sets: Int, reps: Int, superset: String? = nil) -> ExerciseEntry {
        ExerciseEntry(exercise: e, sets: (0..<sets).map { _ in SetEntry(reps: reps) }, superset: superset)
    }

    func testRowsFollowThePlanAndASupersetIsOneGroupWithItsRounds() {
        let squat = ex("t-squat", "Goblet squat", ["dumbbell"]), press = ex("t-press", "Dumbbell bench press", ["dumbbell", "bench"])
        let row = ex("t-row", "Chest-supported row", ["dumbbell", "bench"]), pallof = ex("t-pallof", "Pallof press", ["band"])
        let entries = [entry(squat, sets: 3, reps: 10), entry(press, sets: 3, reps: 10, superset: "A"), entry(row, sets: 3, reps: 10, superset: "A"), entry(pallof, sets: 2, reps: 12)]
        let g = StrengthPrepare.groups(entries)
        XCTAssertEqual(g.count, 3)
        XCTAssertNil(g[0].heading); XCTAssertEqual(g[0].rows.map(\.name), ["Goblet squat"]); XCTAssertEqual(g[0].rows[0].target, "3 × 10")
        XCTAssertEqual(g[1].heading, "Superset A · 3 rounds"); XCTAssertEqual(g[1].rows.map(\.name), ["Dumbbell bench press", "Chest-supported row"])
        XCTAssertEqual(g[1].rows.map(\.target), ["10", "10"], "inside a superset only the repetitions; the rounds are in the heading")
        XCTAssertEqual(g[2].rows[0].target, "2 × 12")
        XCTAssertEqual(StrengthPrepare.equipment(entries, library: [squat, press, row, pallof]), ["dumbbell", "bench", "band"], "in the order first needed, each once")
        XCTAssertEqual(StrengthPrepare.summary(minutes: 35, equipment: ["dumbbell", "bench", "band"], known: true), "About 35 min · dumbbells, bench, band", "as sheet 01a words it")
        XCTAssertEqual(StrengthPrepare.equipmentWord("kettlebell"), "kettlebells"); XCTAssertEqual(StrengthPrepare.equipmentWord("barbell"), "barbell")
    }

    func testNothingIsInventedForUnusualSets() {
        let plank = ex("t-plank", "Plank", ["bodyweight"]), lunge = ex("t-lunge", "Split squat", [])
        var timed = entry(plank, sets: 3, reps: 0); for i in timed.sets.indices { timed.sets[i].seconds = 30 }
        XCTAssertEqual(StrengthPrepare.target(timed, inSuperset: false), "3 × 30 s")
        var side = entry(lunge, sets: 2, reps: 8); for i in side.sets.indices { side.sets[i].unilateral = true }
        XCTAssertEqual(StrengthPrepare.target(side, inSuperset: false), "2 × 8 / side")
        var mixed = entry(lunge, sets: 3, reps: 8); mixed.sets[2].reps = 6
        XCTAssertEqual(StrengthPrepare.target(mixed, inSuperset: false), "3 sets", "different sets are not summarised as one number")
        // a lone entry carrying a superset letter is not a superset
        let alone = entry(lunge, sets: 2, reps: 8, superset: "B")
        XCTAssertNil(StrengthPrepare.groups([alone])[0].heading)
        XCTAssertEqual(StrengthPrepare.equipment([timed], library: [plank]), [], "bodyweight is not equipment")
        XCTAssertEqual(StrengthPrepare.summary(minutes: 20, equipment: [], known: true), "About 20 min · bodyweight")
        XCTAssertEqual(StrengthPrepare.summary(minutes: 0, equipment: [], known: false), "")
        XCTAssertEqual(StrengthPrepare.target(ExerciseEntry(exercise: lunge, sets: []), inSuperset: false), "")
    }

    func testTheTitleDoesNotRepeatStrength() {
        XCTAssertEqual(StrengthPrepare.title("Strength · Full body"), "Full body")
        XCTAssertEqual(StrengthPrepare.title("Strength"), "Strength")
        XCTAssertEqual(StrengthPrepare.title("Strength · "), "Strength · ")
        XCTAssertEqual(StrengthPrepare.title("My Tuesday routine"), "My Tuesday routine")
    }

    func testTheOverlineSaysTodayOnlyForToday() {
        let cal = Calendar.current, now = Date()
        XCTAssertEqual(StrengthPrepare.overline(date: now, now: now, calendar: cal), "Strength · planned today")
        let later = cal.date(byAdding: .day, value: 2, to: now)!
        XCTAssertTrue(StrengthPrepare.overline(date: later, now: now, calendar: cal).hasPrefix("Strength · planned "))
        XCTAssertFalse(StrengthPrepare.overline(date: later, now: now, calendar: cal).contains("today"))
    }
}
