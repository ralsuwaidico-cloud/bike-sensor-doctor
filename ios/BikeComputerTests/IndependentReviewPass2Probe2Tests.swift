// Copied unchanged from the second independent review pass (29916e7, /home/claude/coach-review): assertions encode what a
// correct coach should do; they failed on 29916e7 and are kept as regression tests.
import XCTest
@testable import BikeComputer

final class Pass2Probe2Tests: XCTestCase {
    let cal = Calendar.current
    var today: Date { cal.startOfDay(for: Date()) }
    func at(_ d: Int, _ h: Int = 18) -> Date { cal.date(byAdding: .day, value: d, to: today)!.addingTimeInterval(TimeInterval(h * 3600)) }
    // Q11: routine after a break: the displayed (return-reduced) entries are written back by Save / swap / insight -> the reduction compounds
    func testQ11_ReturnReductionCompounds() {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("p2b-\(UUID().uuidString)"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let s = Store(directory: d, generatePlan: false)
        var p = RiderProfile(); p.trainingMode = .strength; var h = HealthScreen(); h.answeredAt = Date(); p.healthScreen = h; s.profile = p
        let sq = Exercise(id: "rq", name: "Back squat", equipment: ["barbell"], pattern: .squat, unilateral: false, custom: true)
        let row = Exercise(id: "rr", name: "Barbell row", equipment: ["barbell"], pattern: .pull, unilateral: false, custom: true)
        s.customExercises = [sq, row]; s.equipment = EquipmentProfile(owned: ["barbell"])
        let t = WorkoutTemplate(name: "Legs", focus: .lower, entries: [ExerciseEntry(exercise: sq, sets: (0..<3).map { _ in SetEntry(reps: 5, weightKg: 100) })], updatedAt: Date(timeIntervalSince1970: 0))
        s.templates = [t]
        s.strength = [-60, -62, -64].map { dd in var l = StrengthSession(date: at(dd), minutes: 45, focus: .lower, rpe: 7, exercises: [ExerciseEntry(exercise: sq, sets: (0..<3).map { _ in SetEntry(reps: 5, weightKg: 100, rpe: 7, done: true) })]); l.templateId = t.id; return l }
        var w = Workout(date: at(1), kind: .strength, minutes: 45, strengthFocus: .lower); w.templateId = t.id
        s.plan = [w]
        let first = s.plannedEntries(for: s.plan[0])
        print("Q11 shown:", first.map { "\($0.sets.first?.weightKg ?? 0) | \($0.notes)" })
        // the session editor's Save (StrengthWorkout.swift:417) writes what it showed
        s.plan[0].plannedEntries = first; s.plan[0].generatedEntries = false; s.plan[0].edited = true
        let second = s.plannedEntries(for: s.plan[0])
        print("Q11 shown after Save:", second.map { "\($0.sets.first?.weightKg ?? 0) | \($0.notes)" })
        XCTAssertEqual(second.first?.sets.first?.weightKg, first.first?.sets.first?.weightKg, "Q11: the break reduction is applied again to the saved, already reduced weight")
    }
}
