// Copied unchanged from the independent review of 02d8795 (/home/claude/coach-review): assertions encode what a correct
// coach should do; they failed on 02d8795 and are kept as regression tests for the fixes.
import XCTest
@testable import BikeComputer

final class ReviewProbe2Tests: XCTestCase {
    let cal = Calendar.current
    var today: Date { cal.startOfDay(for: Date()) }
    func at(_ d: Int, _ h: Int = 7) -> Date { cal.date(byAdding: .day, value: d, to: today)!.addingTimeInterval(TimeInterval(h * 3600)) }
    func store() -> Store { let d = FileManager.default.temporaryDirectory.appendingPathComponent("rev2-\(UUID().uuidString)"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return Store(directory: d, generatePlan: false) }
    func screened(_ p: inout RiderProfile) { var s = HealthScreen(); s.answeredAt = Date(timeIntervalSince1970: 1_790_000_000); p.healthScreen = s }

    // R13: a rider's own routine after a 8-week lifting break: what does the next session prescribe?
    func testR13_RoutineAfterBreak() {
        let s = store(); var p = RiderProfile(); p.trainingMode = .strength; p.liftDaysPerWeek = 3; p.liftingHoursPerWeek = 3; screened(&p); s.profile = p
        let sq = Exercise(id: "rq", name: "Back squat", equipment: ["barbell"], pattern: .squat, unilateral: false, custom: true)
        s.customExercises = [sq]; s.equipment = EquipmentProfile(owned: ["barbell"])
        let t = WorkoutTemplate(name: "Legs", focus: .lower, entries: [ExerciseEntry(exercise: sq, sets: (0..<3).map { _ in SetEntry(reps: 5, weightKg: 100) })], updatedAt: Date(timeIntervalSince1970: 0))
        s.templates = [t]
        s.strength = [-60, -62, -64].map { d in var l = StrengthSession(date: at(d, 18), minutes: 45, focus: .lower, rpe: 7, exercises: [ExerciseEntry(exercise: sq, sets: (0..<3).map { _ in SetEntry(reps: 5, weightKg: 100, rpe: 7, done: true) })]); l.templateId = t.id; return l }
        var w = Workout(date: at(1, 18), kind: .strength, minutes: 45, strengthFocus: .lower); w.templateId = t.id
        s.plan = [w]
        s.refreshGeneratedSessions(); _ = s.runAdaptation()
        let e = s.plannedEntries(for: s.plan[0])
        print("R13 routine session after 8 weeks off:", e.map { "\($0.name) \($0.sets.map { "\($0.reps)x\($0.weightKg ?? 0)" })" }, "returnPhase:", String(describing: s.liftingReturnPhase()))
        XCTAssertLessThan(e.first?.sets.first?.weightKg ?? 999, 100, "R13: own routine prescribes the pre-break load after 8 weeks off")
    }
    // R14: duration progression during the ride return phase
    func testR14_DurationProgressionDuringReturn() {
        var p = RiderProfile(); p.trainingMode = .cycling; p.hoursPerWeek = 10; screened(&p)
        var rides: [RideRecord] = [-60, -62, -64].map { RideRecord(start: at($0), durationS: 3600, distanceM: 25000, recorder: .phone, sources: []) }
        for d in [-1, -3] { var r = RideRecord(start: at(d), durationS: 3600, distanceM: 25000, recorder: .phone, sources: []); r.checkIn = CheckIn(performance: 9, effort: 4, at: r.start); rides.append(r) }
        let w = Workout(date: at(2), kind: .endurance, minutes: 60)
        let res = AdaptationEngine.run(AdaptationInput(profile: p, plan: [w], rides: rides, strength: [], availability: WeeklyAvailability.suggested(for: p), now: Date(), calendar: cal))
        print("R14 return phase:", String(describing: ReturnPhase.detect(dates: rides.map { $0.start }, now: Date())), "adjustments:", res.adjustments.map { $0.summary })
    }
    // R15: daily steady load ACWR, short history
    func testR15_ACWRDaily() {
        var p = RiderProfile(); p.trainingMode = .cycling; screened(&p)
        for hist in [28, 29, 35] {
            let rides: [RideRecord] = (1...hist).map { d in var r = RideRecord(start: at(-d), durationS: 3600, distanceM: 25000, recorder: .phone, sources: []); r.checkIn = CheckIn(performance: 7, effort: 5, at: r.start); return r }
            let an = TrainingAnalyzer.analyze(AdaptationInput(profile: p, plan: [], rides: rides, strength: [], availability: WeeklyAvailability.suggested(for: p), now: Date(), calendar: cal))
            print("R15 daily \(hist) d: ACWR=", an.acwr.map { String(format: "%.2f", $0) } ?? "nil")
        }
    }
    // R16: 2-day riders and 7-day riders: what does the default week give?
    func testR16_FrequencyExtremes() {
        for (mode, rides, lifts, h, lh) in [(TrainingMode.cycling, 2, 0, 3, 0), (.cycling, 7, 0, 12, 0), (.hybrid, 2, 2, 3, 2), (.hybrid, 6, 3, 10, 3), (.strength, 0, 2, 0, 2), (.strength, 0, 6, 0, 6)] {
            var p = RiderProfile(); p.trainingMode = mode; p.cyclingDaysPerWeek = rides; p.liftDaysPerWeek = lifts; p.hoursPerWeek = h; p.liftingHoursPerWeek = lh; p.level = .intermediate; p.goal = .stronger; screened(&p)
            let w = PlanEngine.week(starting: today, profile: p, availability: WeeklyAvailability.suggested(for: p))
            print("R16 \(mode) rides \(rides) lifts \(lifts):", w.filter { $0.kind != .rest }.sorted { $0.date < $1.date }.map { "\($0.date.shortDay):\($0.kind.rawValue)\($0.strengthFocus.map { "/\($0.rawValue)" } ?? "")\($0.minutes)" }.joined(separator: " "))
        }
    }
}
