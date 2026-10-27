// Copied unchanged from the second independent review pass (29916e7, /home/claude/coach-review): assertions encode what a
// correct coach should do; they failed on 29916e7 and are kept as regression tests.
import XCTest
@testable import BikeComputer

/// Second-pass independent review probes (29916e7). Assertions encode what a correct coach should do: FAIL = finding.
final class Pass2ProbeTests: XCTestCase {
    let cal = Calendar.current
    var today: Date { cal.startOfDay(for: Date()) }
    var thisMonday: Date { let wd = (cal.component(.weekday, from: today) + 5) % 7; return cal.date(byAdding: .day, value: -wd, to: today)! }
    var nextMonday: Date { cal.date(byAdding: .day, value: 7, to: thisMonday)! }
    func at(_ d: Int, _ h: Int = 7) -> Date { cal.date(byAdding: .day, value: d, to: today)!.addingTimeInterval(TimeInterval(h * 3600)) }
    func store() -> Store { let d = FileManager.default.temporaryDirectory.appendingPathComponent("p2-\(UUID().uuidString)"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return Store(directory: d, generatePlan: false) }
    func screen(_ f: (inout HealthScreen) -> Void = { _ in }, answered: Date = Date()) -> HealthScreen { var s = HealthScreen(); s.answeredAt = answered; f(&s); return s }
    func desc(_ w: [Workout]) -> String { w.filter { $0.kind != .rest }.sorted { $0.date < $1.date }.map { "\($0.date.shortDay):\($0.kind.rawValue)\($0.minutes)\($0.effectiveIntervalReps.map { "x\($0)" } ?? "")" }.joined(separator: " ") }
    let squat = Exercise(id: "q", name: "Back squat", equipment: ["barbell"], pattern: .squat, muscles: ["quads", "glutes"], unilateral: false, custom: true)
    func log(_ d: Int, kg: Double, reps: Int, rpe: Int = 7) -> StrengthSession { StrengthSession(date: at(d, 18), minutes: 45, focus: .fullBody, rpe: rpe, exercises: [ExerciseEntry(exercise: squat, sets: (0..<3).map { _ in SetEntry(reps: reps, weightKg: kg, rpe: rpe, done: true) })]) }

    // Q1: an existing strength-goal lifter whose check is unanswered/expired: is the held load re-prescribed at MORE reps?
    func testQ1_RepFloorMakesHeldLoadHarder() {
        var p = RiderProfile(); p.trainingMode = .strength; p.level = .intermediate
        p.healthScreen = screen(answered: cal.date(byAdding: .day, value: -400, to: Date())!)   // expired
        var prefs = StrengthPrefs(); prefs.goal = .strength
        let c = PlannerContext(profile: p, prefs: prefs, equipment: EquipmentProfile(owned: ["barbell"]), catalogue: [squat], logs: [log(-3, kg: 100, reps: 5), log(-6, kg: 100, reps: 5)], now: Date(), calendar: cal)
        let d = StrengthPlanner.dose(role: .main, goal: .strength, experience: .intermediate)
        var reps = d.reps; if let lo = c.readiness.minStrengthReps, reps.lowerBound < lo { reps = lo...max(lo + 4, reps.upperBound) }
        let l = StrengthPlanner.prescribeLoad(squat, meta: ExerciseLibrary.meta(squat), reps: reps, sets: 3, painBlocked: false, ctx: c)
        print("Q1 status \(c.readiness.screen) range \(reps): \(l.weight ?? -1) kg x \(l.reps) | \(l.why)")
        XCTAssertFalse((l.weight ?? 0) >= 100 && l.reps > 5, "Q1: last 3x5 @100 kg; now prescribed \(l.weight ?? 0) kg x \(l.reps) - harder than before, while 'not cleared'")
    }
    // Q2: a user who edits a capped ride: does the refresh overwrite the edit with the uncapped original?
    func testQ2_EditedCappedRideIsOverwritten() {
        let s = store(); var p = RiderProfile(); p.trainingMode = .cycling; s.profile = p      // not answered
        s.plan = [Workout(date: at(2), kind: .threshold, minutes: 70)]
        s.refreshRideSafety()
        print("Q2 capped:", desc(s.plan), "orig:", s.plan[0].safetyOriginal?.kind.rawValue ?? "nil")
        var e = s.plan[0]; e.kind = .recovery; e.minutes = 30; s.edit(e)                      // the rider edits it
        s.refreshRideSafety()
        print("Q2 after edit + refresh:", desc(s.plan), "edited:", s.plan[0].edited)
        XCTAssertEqual(s.plan[0].kind, .recovery, "Q2: the rider's edit was replaced by the generated (uncapped) ride")
    }
    // Q3: "ill right now" keeps a moderate plan (rides up to 120 min) and requires a doctor's clearance to lift
    func testQ3_CurrentIllness() {
        var p = RiderProfile(); p.trainingMode = .cycling; p.level = .intermediate; p.goal = .stronger; p.hoursPerWeek = 8; p.cyclingDaysPerWeek = 4
        p.healthScreen = screen { $0.currentIllness = true }
        let w = PlanEngine.week(starting: nextMonday, profile: p, availability: WeeklyAvailability.suggested(for: p))
        print("Q3 ill now (\(p.readiness.screen)):", desc(w))
        XCTAssertTrue(w.allSatisfy { $0.kind == .rest || $0.kind == .recovery }, "Q3: a rider who is ill right now still gets \(desc(w))")
    }
    // Q4: clearance dated years before the answers (before the symptoms) is accepted
    func testQ4_StaleClearanceDate() {
        var s = screen { $0.chestPain = true }
        s.clearedAt = cal.date(byAdding: .year, value: -3, to: Date())
        print("Q4 chest pain + clearance dated 3 years ago:", s.status)
        XCTAssertNotEqual(s.status, .cleared, "Q4: a 3-year-old clearance unlocks vigorous training for current chest pain")
    }
    // Q5: old concerning pain reports (released under the old automatic rule) come back after the update, flagged 'persistent'
    func testQ5_OldPainReportsReheld() {
        var p = RiderProfile(); p.trainingMode = .hybrid; p.healthScreen = screen()
        var old = log(-200, kg: 60, reps: 8); old.checkIn = CheckIn(performance: 6, effort: 7, pain: .concerning, painArea: .knees, at: old.date)
        var recent = (1...6).map { log(-$0 * 5, kg: 60, reps: 8) }
        for i in recent.indices { recent[i].checkIn = CheckIn(performance: 7, effort: 6, at: recent[i].date) }
        let a = TrainingAnalyzer.analyze(AdaptationInput(profile: p, plan: [], rides: [], strength: [old] + recent, availability: WeeklyAvailability.suggested(for: p), now: Date(), calendar: cal))
        print("Q5 200-day-old knee report + 6 pain-free squat sessions: held \(a.painAreas) reviewDue \(a.painReviewDue) persistent \(a.painPersistent)")
        print("Q5 advice:", AdaptationExplainer.painAdvice(a.painAreas, persistent: a.painPersistent) ?? "-")
        XCTAssertFalse(a.painPersistent.contains(.knees), "Q5: a report from 200 days ago, followed by 6 pain-free sessions, is called 'lasted more than two weeks or come back'")
    }
    // Q6: engine progression of the rider's OWN routine while clearance is pending (planner holds loads, engine?)
    func testQ6_RoutineProgressionWhileNotCleared() {
        var p = RiderProfile(); p.trainingMode = .strength; p.healthScreen = screen { $0.heartOrBloodPressure = true }
        let t = WorkoutTemplate(name: "Legs", focus: .lower, entries: [ExerciseEntry(exercise: squat, sets: (0..<3).map { _ in SetEntry(reps: 8, weightKg: 60) })], updatedAt: Date(timeIntervalSince1970: 0))
        var w = Workout(date: at(2, 18), kind: .strength, minutes: 45, strengthFocus: .lower); w.templateId = t.id
        var logs = [log(-3, kg: 60, reps: 8), log(-6, kg: 60, reps: 8)]; for i in logs.indices { logs[i].templateId = t.id; logs[i].checkIn = CheckIn(performance: 7, effort: 6, at: logs[i].date) }
        let r = AdaptationEngine.run(AdaptationInput(profile: p, plan: [w], rides: [], strength: logs, availability: WeeklyAvailability.suggested(for: p), equipment: EquipmentProfile(owned: ["barbell"]), catalogue: [squat], templates: [t], originalEntries: [w.id: t.prefilled(from: logs.first)], now: Date(), calendar: cal))
        print("Q6 needsClearance routine adjustments:", r.adjustments.map { $0.summary })
        XCTAssertFalse(r.adjustments.contains { $0.category == .progression }, "Q6: the engine still raises a routine load while clearance is pending")
    }
    // Q7: availability typed by an OLDER version (threshold + long typed): easy week and goal intensity?
    func testQ7_LegacyTypedAvailability() {
        var p = RiderProfile(); p.trainingMode = .hybrid; p.level = .intermediate; p.goal = .fitness; p.hoursPerWeek = 7; p.liftingHoursPerWeek = 2; p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 2
        p.healthScreen = screen()
        var a = WeeklyAvailability(days: Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7))
        a.days[1] = DayAvailability(assignments: [DayAssignment(sport: .strength, minutes: 60)])
        a.days[2] = DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: .threshold, minutes: 90)])
        a.days[3] = DayAvailability(assignments: [DayAssignment(sport: .strength, minutes: 60)])
        a.days[5] = DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: .long, minutes: 150)])
        a.days[6] = DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: .zone2, minutes: 90)])
        let easy = PlanEngine.week(starting: nextMonday, profile: p, availability: a, trainingWeeks: 3)
        print("Q7 legacy typed, easy week:", desc(easy))
        XCTAssertFalse(easy.contains { $0.kind.zone >= 4 }, "Q7: stored (older-version) typed threshold survives the easy week")
    }
    // Q8: stop -> all sessions rest (fixed included) -> answers change to clear -> everything restored, plannedEntries intact
    func testQ8_StopAndRestore() {
        let s = store(); var p = RiderProfile(); p.trainingMode = .hybrid; p.healthScreen = screen { $0.chestPain = true }; s.profile = p
        var lift = Workout(date: at(2, 18), kind: .strength, minutes: 45, strengthFocus: .lower); lift.plannedEntries = [ExerciseEntry(exercise: squat, sets: [SetEntry(reps: 8, weightKg: 60)])]; lift.edited = true
        var fixed = Workout(date: at(3), kind: .threshold, minutes: 70); fixed.fixed = true
        s.plan = [lift, fixed, Workout(date: at(4), kind: .long, minutes: 150)]
        s.refreshRideSafety()
        print("Q8 stop:", s.plan.map { "\($0.kind.rawValue)\($0.minutes)" })
        XCTAssertTrue(s.plan.allSatisfy { $0.kind == .rest })
        s.profile.healthScreen = screen()
        s.refreshRideSafety()
        print("Q8 restored:", s.plan.map { "\($0.kind.rawValue)\($0.minutes) entries:\($0.plannedEntries?.count ?? 0)" })
        XCTAssertEqual(s.plan.map { $0.kind }, [.strength, .threshold, .long]); XCTAssertEqual(s.plan[0].plannedEntries?.count, 1)
    }
    // Q9: return-phase ride ramp and restore of a generation-capped ride (threshold block reps kept?)
    func testQ9_ReturnRamp() {
        var p = RiderProfile(); p.trainingMode = .cycling; p.level = .intermediate; p.goal = .stronger; p.hoursPerWeek = 8; p.cyclingDaysPerWeek = 4; p.healthScreen = screen()
        let a = WeeklyAvailability.suggested(for: p)
        for (gap, since) in [(25, 0), (200, 0), (200, 2)] { print("Q9 break \(gap) d, \(since) rides back:", desc(PlanEngine.week(starting: nextMonday, profile: p, availability: a, returning: ReturnPhase(breakDays: gap, sessionsSince: since, ongoing: since == 0), trainingWeeks: 1))) }
        print("Q9 no break, block week 2:", desc(PlanEngine.week(starting: nextMonday, profile: p, availability: a, trainingWeeks: 1)))
    }
    // Q10: health check not answered -> strength session dose and ride caps
    func testQ10_UnansweredWeek() {
        var p = RiderProfile(); p.trainingMode = .hybrid; p.level = .advanced; p.goal = .event; p.hoursPerWeek = 10; p.liftingHoursPerWeek = 2; p.cyclingDaysPerWeek = 4; p.liftDaysPerWeek = 2
        print("Q10 unanswered advanced:", desc(PlanEngine.week(starting: nextMonday, profile: p, availability: WeeklyAvailability.suggested(for: p))))
    }
}
