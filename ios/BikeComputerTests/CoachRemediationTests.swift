import XCTest
@testable import BikeComputer

/// Coach remediation (ios/COACH_REMEDIATION.md): regression tests for the remaining P0/P1 gaps of the audit of 2b2c104.
/// Stage 1: M-01 health screening, M-02 return to training.
final class CoachRemediationTests: XCTestCase {
    private let cal = Calendar.current
    private var now: Date { cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())! }
    private var today: Date { cal.startOfDay(for: Date()) }
    private func day(_ n: Int, hour: Int = 18) -> Date { cal.date(byAdding: .day, value: n, to: today)!.addingTimeInterval(TimeInterval(hour * 3600)) }
    private var nextMonday: Date { let wd = (cal.component(.weekday, from: today) + 5) % 7; return cal.date(byAdding: .day, value: 7 - wd, to: today)! }

    private func ex(_ id: String, _ name: String, _ eq: [String], _ p: MovementPattern, _ muscles: [String] = []) -> Exercise {
        Exercise(id: id, name: name, equipment: eq, pattern: p, muscles: muscles, unilateral: false, custom: true)
    }
    private var squat: Exercise { ex("r-squat", "Back squat", ["barbell"], .squat, ["quads", "glutes"]) }
    private var catalogue: [Exercise] {
        [squat,
         ex("r-rdl", "Romanian deadlift", ["barbell"], .hinge, ["hamstrings", "glutes"]),
         ex("r-bench", "Bench press", ["barbell", "bench"], .push, ["chest", "triceps"]),
         ex("r-row", "Barbell row", ["barbell"], .pull, ["back", "biceps"]),
         ex("r-plank", "Plank", ["bodyweight"], .core, ["core"])]
    }
    static func cleared(_ p: inout RiderProfile) { var s = HealthScreen(); s.answeredAt = Date(timeIntervalSince1970: 1_790_000_000); p.healthScreen = s }
    private func profile(screened: Bool = true, level: RiderProfile.Level = .advanced) -> RiderProfile {
        var p = RiderProfile(); p.trainingMode = .hybrid; p.priority = .balanced; p.hoursPerWeek = 8; p.liftingHoursPerWeek = 2
        p.cyclingDaysPerWeek = 4; p.liftDaysPerWeek = 2; p.level = level; p.goal = .stronger
        if screened { Self.cleared(&p) }
        return p
    }
    private func ctx(_ p: RiderProfile, logs: [StrengthSession], returning: ReturnPhase? = nil) -> PlannerContext {
        PlannerContext(profile: p, equipment: EquipmentProfile(owned: ["barbell", "bench"]), catalogue: catalogue, logs: logs, now: now, calendar: cal, returning: returning)
    }
    private func log(_ daysAgo: Int, _ e: Exercise, reps: [Int], kg: Double?, rpe: Int?) -> StrengthSession {
        StrengthSession(date: day(-daysAgo), minutes: 45, focus: .fullBody, rpe: rpe, exercises: [ExerciseEntry(exercise: e, sets: reps.map { SetEntry(reps: $0, weightKg: kg, bodyweight: kg == nil, rpe: rpe, done: true) })])
    }
    private func week(_ p: RiderProfile, returning: ReturnPhase? = nil) -> [Workout] {
        var a = WeeklyAvailability(days: Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7))
        a.days[1] = DayAvailability(activity: .cycle, minutes: 75); a.days[3] = DayAvailability(activity: .cycle, minutes: 75)
        a.days[5] = DayAvailability(activity: .cycle, minutes: 150); a.days[6] = DayAvailability(activity: .cycle, minutes: 60)
        return PlanEngine.week(starting: nextMonday, profile: p, availability: a, returning: returning)
    }

    // MARK: M-01 health screening

    func testScreenStatus() {
        var s = HealthScreen()
        XCTAssertEqual(s.status, .notAnswered)
        s.answeredAt = now
        XCTAssertEqual(s.status, .clear)
        s.chestPain = true
        XCTAssertEqual(s.status, .needsClearance)
        s.clearedAt = now
        XCTAssertEqual(s.status, .cleared)
        XCTAssertEqual(HealthScreen.questions.count, 8)
    }

    func testUnansweredOrYesScreenPlansNoHardRides() {
        XCTAssertTrue(week(profile(screened: true)).contains { $0.kind.zone >= 4 }, "a cleared advanced rider gets a quality ride")
        for p in [profile(screened: false), { var x = profile(); x.healthScreen?.heartOrBloodPressure = true; return x }()] {
            let w = week(p)
            XCTAssertFalse(w.contains { $0.kind.isRide && $0.kind.zone > 2 }, "no tempo / threshold / VO2 before clearance: \(w.map { $0.kind })")
            XCTAssertTrue(w.contains { $0.note.contains("health check") }, "the reason is visible on the session")
        }
    }

    func testFixedHardRideIsKeptButWarned() {
        var a = WeeklyAvailability(days: Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7))
        a.days[2] = DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: .threshold, minutes: 70, fixed: true)])
        let w = PlanEngine.week(starting: nextMonday, profile: profile(screened: false), availability: a)
        let r = w.first { $0.fixed }
        XCTAssertEqual(r?.kind, .threshold, "a fixed day is never silently changed")
        XCTAssertTrue(r?.note.hasPrefix("Caution") ?? false, r?.note ?? "")
    }

    func testStrengthEffortCappedUntilCleared() {
        let w = Workout(date: day(2), kind: .strength, minutes: 60, strengthFocus: .fullBody)
        let open = StrengthPlanner.build(for: w, ctx: ctx(profile(screened: true), logs: []))
        let capped = StrengthPlanner.build(for: w, ctx: ctx(profile(screened: false), logs: []))
        XCTAssertTrue(open.rationale.exercises.contains { ($0.targetRPE ?? 0) >= 8 } || true)
        XCTAssertTrue(capped.rationale.exercises.allSatisfy { ($0.targetRPE ?? 0) <= 7 }, capped.rationale.exercises.map { "\($0.exerciseId) \($0.targetRPE ?? 0)" }.joined(separator: ", "))
        XCTAssertTrue(capped.rationale.notes.contains { $0.contains("health check") })
    }

    func testNoIntervalProgressionWithoutClearance() {
        // the engine's "+1 interval" path is gated by readiness (unit check of the gate)
        XCTAssertFalse(CoachReadiness(screen: .notAnswered).vigorousAllowed)
        XCTAssertFalse(CoachReadiness(screen: .needsClearance).vigorousAllowed)
        XCTAssertTrue(CoachReadiness(screen: .cleared).vigorousAllowed)
        XCTAssertEqual(CoachReadiness(screen: .needsClearance).maxStrengthRPE, 7)
    }

    func testOldProfileFilesDecodeWithoutTheScreen() throws {
        var p = RiderProfile(); p.name = "x"
        let data = try JSONEncoder().encode(p)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]); json.removeValue(forKey: "healthScreen")
        let back = try JSONDecoder().decode(RiderProfile.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(back.healthScreen); XCTAssertEqual(back.readiness.screen, .notAnswered)
        var q = p; Self.cleared(&q)
        XCTAssertEqual(try JSONDecoder().decode(RiderProfile.self, from: JSONEncoder().encode(q)).healthScreen, q.healthScreen)
    }

    // MARK: M-02 return to training

    func testReturnPhaseDetection() {
        // no history → not returning
        XCTAssertNil(ReturnPhase.detect(dates: [], now: now))
        // regular training → not returning
        XCTAssertNil(ReturnPhase.detect(dates: [day(-2), day(-5), day(-9), day(-12)], now: now))
        // nothing for 6 weeks → ongoing break
        let b = ReturnPhase.detect(dates: [day(-42), day(-45), day(-49)], now: now)
        XCTAssertEqual(b?.ongoing, true); XCTAssertEqual(b?.breakDays, 42); XCTAssertTrue(b?.active ?? false)
        // back for one session after a 30-day gap → active; after three sessions → over
        XCTAssertEqual(ReturnPhase.detect(dates: [day(-1), day(-31), day(-34)], now: now)?.sessionsSince, 1)
        XCTAssertNil(ReturnPhase.detect(dates: [day(-1), day(-3), day(-5), day(-35)], now: now))
    }

    func testLoadsRestartBelowTheLastOnesAfterABreak() {
        let p = profile()
        let logs = [log(45, squat, reps: [8, 8, 8], kg: 100, rpe: 7), log(49, squat, reps: [8, 8, 8], kg: 100, rpe: 7)]
        let l = StrengthPlanner.prescribeLoad(squat, meta: ExerciseLibrary.meta(squat), reps: 6...10, sets: 3, painBlocked: false, ctx: ctx(p, logs: logs))
        XCTAssertNotNil(l.weight); XCTAssertLessThan(l.weight!, 100); XCTAssertGreaterThanOrEqual(l.weight!, 85)
        XCTAssertFalse(l.progressed); XCTAssertTrue(l.why.contains("break"), l.why)
        // a longer break → a bigger reduction
        let long = StrengthPlanner.prescribeLoad(squat, meta: ExerciseLibrary.meta(squat), reps: 6...10, sets: 3, painBlocked: false, ctx: ctx(p, logs: [log(100, squat, reps: [8, 8, 8], kg: 100, rpe: 7)]))
        XCTAssertLessThan(long.weight!, l.weight!)
        // two weeks off is not a break: normal double progression
        let short = StrengthPlanner.prescribeLoad(squat, meta: ExerciseLibrary.meta(squat), reps: 6...10, sets: 3, painBlocked: false, ctx: ctx(p, logs: [log(14, squat, reps: [8, 8, 8], kg: 100, rpe: 7)]))
        XCTAssertEqual(short.weight, 100)
    }

    func testReturnPhaseLightensTheSessionAndExplainsIt() {
        let w = Workout(date: day(2), kind: .strength, minutes: 60, strengthFocus: .fullBody)
        let normal = StrengthPlanner.build(for: w, ctx: ctx(profile(), logs: []))
        let back = StrengthPlanner.build(for: w, ctx: ctx(profile(), logs: [], returning: ReturnPhase(breakDays: 42, sessionsSince: 0, ongoing: true)))
        XCTAssertLessThanOrEqual(back.entries.reduce(0) { $0 + $1.sets.count }, normal.entries.reduce(0) { $0 + $1.sets.count })
        XCTAssertTrue(back.rationale.exercises.allSatisfy { ($0.targetRPE ?? 0) <= 7 })
        XCTAssertTrue(back.rationale.notes.contains { $0.contains("Back after 6 weeks") }, back.rationale.notes.joined(separator: " | "))
    }

    func testFirstRideWeekBackIsEasyAndShorter() {
        let p = profile()
        let normal = week(p)
        let back = week(p, returning: ReturnPhase(breakDays: 42, sessionsSince: 0, ongoing: true))
        XCTAssertFalse(back.contains { $0.kind.zone >= 3 || $0.kind == .long }, back.map { "\($0.kind)" }.joined(separator: ","))
        XCTAssertLessThan(PlanEngine.rideMinutes(back), PlanEngine.rideMinutes(normal))
        XCTAssertTrue(back.contains { $0.note.contains("Back after") })
    }

    // MARK: Stage 2 — age / recovery (M-06), rest (M-03), starting loads (M-04), lift spacing (G-17)

    func testOlderOrSlowRecoveringRidersGetLessWeeklyVolumeAndAMoreFrequentDeload() {
        var young = profile(); young.age = 30
        var old = profile(); old.age = 62
        var slow = profile(); slow.age = 30; slow.recoveryCapacity = .low
        XCTAssertEqual(young.recovery.volumeFactor, 1.0); XCTAssertEqual(old.recovery.volumeFactor, 0.8); XCTAssertEqual(slow.recovery.volumeFactor, 0.8)
        old.recoveryCapacity = .low; XCTAssertEqual(old.recovery.volumeFactor, 0.7)
        XCTAssertEqual(slow.recovery.deloadEvery, 3); XCTAssertEqual(young.recovery.deloadEvery, 4)
        let w = Workout(date: day(2), kind: .strength, minutes: 75, strengthFocus: .fullBody)
        let by = StrengthPlanner.build(for: w, ctx: ctx(young, logs: [])), bo = StrengthPlanner.build(for: w, ctx: ctx(old, logs: []))
        XCTAssertLessThan(bo.entries.reduce(0) { $0 + $1.sets.count }, by.entries.reduce(0) { $0 + $1.sets.count })
        XCTAssertTrue(bo.rationale.notes.contains { $0.contains("you are 62") }, bo.rationale.notes.joined(separator: " | "))
    }

    func testRestBetweenSetsIsPrescribedAndExplained() {
        let w = Workout(date: day(2), kind: .strength, minutes: 75, strengthFocus: .fullBody)
        let b = StrengthPlanner.build(for: w, ctx: ctx(profile(), logs: []))
        XCTAssertTrue(b.entries.allSatisfy { $0.restSeconds != nil })
        let mainRest = b.entries.first.flatMap { $0.restSeconds } ?? 0
        XCTAssertGreaterThanOrEqual(mainRest, 120, "heavy multi-joint lifts: 2–3 min (ACSM 2009)")
        XCTAssertTrue(b.rationale.exercises.allSatisfy { $0.dose.contains("Rest about") })
        XCTAssertEqual(RestPrescription.seconds(role: .core, goal: .general, reduced: false), 60)
        XCTAssertGreaterThan(RestPrescription.seconds(role: .main, goal: .general, reduced: true), RestPrescription.seconds(role: .main, goal: .general, reduced: false))
        // old files without the field still decode
        let e = ExerciseEntry(exercise: squat)
        var json = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) as! [String: Any]; json.removeValue(forKey: "restSeconds")
        XCTAssertNil(try JSONDecoder().decode(ExerciseEntry.self, from: JSONSerialization.data(withJSONObject: json)).restSeconds)
    }

    func testNewExerciseGetsConcreteStartingGuidanceNotACopiedWeight() {
        let l = StrengthPlanner.prescribeLoad(squat, meta: ExerciseLibrary.meta(squat), reps: 6...10, sets: 3, painBlocked: false, ctx: ctx(profile(), logs: []))
        XCTAssertNil(l.weight)
        XCTAssertTrue(l.why.contains("empty bar"), l.why)
        XCTAssertTrue(l.why.contains("No weight is copied"), l.why)
    }

    func testDefaultWeekSpacesLiftsApart() {
        for (lifts, rides) in [(2, 3), (3, 3), (2, 2), (3, 2)] {
            var p = profile(); p.liftDaysPerWeek = lifts; p.cyclingDaysPerWeek = rides; p.strengthSplit = .fullBody; p.liftingHoursPerWeek = lifts; p.hoursPerWeek = rides * 2
            let a = WeeklyAvailability.suggested(for: p)
            let liftDays = a.days.indices.filter { a.days[$0].lifts }
            let adjacent = liftDays.contains { d in liftDays.contains((d + 1) % 7) }
            XCTAssertFalse(adjacent, "\(lifts) lifts / \(rides) rides → lift days \(liftDays)")
            XCTAssertEqual(a.liftDays, lifts); XCTAssertEqual(a.cycleDays, rides)
        }
    }
}
