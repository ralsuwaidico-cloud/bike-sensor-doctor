// Copied unchanged from the third independent review pass (3e801a0, /home/claude/coach-review/pass3): assertions encode what a
// correct coach should do; the failing ones are findings P3-01..P3-07 and are kept as regression tests.
import XCTest
@testable import BikeComputer

/// Third-pass regression / information probes (3e801a0): intensity by goal, VO2 placement (F-22), legacy typed days (N-09).
final class Pass3Probe2Tests: XCTestCase {
    let cal = Calendar.current
    var today: Date { cal.startOfDay(for: Date()) }
    var nextMonday: Date { let wd = (cal.component(.weekday, from: today) + 5) % 7; return cal.date(byAdding: .day, value: 7 - wd, to: today)! }
    func desc(_ w: [Workout]) -> String { w.filter { $0.kind != .rest }.sorted { $0.date < $1.date }.map { "\($0.date.shortDay):\($0.kind.rawValue)\($0.minutes)\($0.effectiveIntervalReps.map { "x\($0)" } ?? "")" }.joined(separator: " ") }
    func clear() -> HealthScreen { var s = HealthScreen(); s.answeredAt = Date(); return s }

    func testR1_IntensityByGoalAndBlockInfo() {
        for goal in [RiderProfile.Goal.fitness, .stronger, .event] { for level in [RiderProfile.Level.beginner, .intermediate, .advanced] {
            var p = RiderProfile(); p.trainingMode = .cycling; p.level = level; p.goal = goal; p.hoursPerWeek = 10; p.cyclingDaysPerWeek = 5; p.healthScreen = clear()
            let a = WeeklyAvailability.suggested(for: p)
            let weeks = (0..<4).map { desc(PlanEngine.week(starting: nextMonday, profile: p, availability: a, trainingWeeks: $0)) }
            print("R1 \(goal) \(level): " + weeks.enumerated().map { "w\($0.offset + 1)[\($0.element)]" }.joined(separator: " "))
            let hasVO2 = weeks.contains { $0.contains("vo2") }
            if level == .advanced && goal != .fitness { print("R1 F-22 VO2 reachable for advanced \(goal): \(hasVO2)") }
            XCTAssertFalse(weeks[3].contains("threshold") || weeks[3].contains("vo2") || weeks[3].contains("tempo"), "easy week 4 has intensity")
            if goal == .fitness || level == .beginner { XCTAssertFalse(weeks.joined().contains("threshold"), "fitness/beginner get threshold") }
        } }
    }
    func testR2_LegacyTypedNormalWeekInfo() {
        var p = RiderProfile(); p.trainingMode = .cycling; p.level = .intermediate; p.goal = .fitness; p.hoursPerWeek = 7; p.cyclingDaysPerWeek = 3; p.healthScreen = clear()
        var a = WeeklyAvailability(days: Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7))
        a.days[2] = DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: .threshold, minutes: 90)])
        a.days[5] = DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: .long, minutes: 150)])
        a.days[6] = DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: .zone2, minutes: 90)])
        print("R2 fitness goal, legacy typed threshold, block week 1:", desc(PlanEngine.week(starting: nextMonday, profile: p, availability: a, trainingWeeks: 0)))
        print("R2 same, easy week:", desc(PlanEngine.week(starting: nextMonday, profile: p, availability: a, trainingWeeks: 3)))
    }
}
