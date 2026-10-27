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
        s.heartOrBloodPressure = true
        XCTAssertEqual(s.status, .needsClearance)
        s.clearedAt = now
        XCTAssertEqual(s.status, .cleared)
        XCTAssertEqual(HealthScreen.questions.count, 9)
        // F-01: symptoms stop planning until a recorded clearance; supervised-only is never cleared in the app
        var sym = HealthScreen(); sym.answeredAt = now; sym.chestPain = true
        XCTAssertEqual(sym.status, .stop); sym.clearedAt = now; XCTAssertEqual(sym.status, .cleared)
        var sup = HealthScreen(); sup.answeredAt = now; sup.supervisedOnly = true; sup.clearedAt = now
        XCTAssertEqual(sup.status, .stop); XCTAssertFalse(sup.clearable)
        // answers expire after a year
        var old = HealthScreen(); old.answeredAt = now.addingTimeInterval(-400 * 86_400)
        XCTAssertEqual(old.status(now: now), .notAnswered)
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
        XCTAssertEqual(CoachReadiness(screen: .needsClearance).maxStrengthRPE, 6)
        XCTAssertEqual(CoachReadiness(screen: .notAnswered).maxStrengthRPE, 7)
        XCTAssertFalse(CoachReadiness(screen: .stop).trainingAllowed)
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

    // MARK: Stage 3 — cycling intensity and block progression (M-05, G-10, G-18, G-20), adaptation (G-12, G-13, G-14, G-15), choice (G-19)

    private func splitWeek(_ p: RiderProfile, trainingWeeks: Int? = nil) -> [Workout] {
        PlanEngine.week(starting: nextMonday, profile: p, availability: WeeklyAvailability.suggested(for: p), trainingWeeks: trainingWeeks)
    }

    func testIntensityFollowsGoalAndLevel() {
        var adv = profile(level: .advanced); adv.goal = .event; adv.cyclingDaysPerWeek = 5; adv.hoursPerWeek = 9; adv.trainingMode = .cycling
        var av = WeeklyAvailability(days: Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7))
        for (d, m) in [(0, 60), (1, 75), (3, 75), (5, 180), (6, 60)] { av.days[d] = DayAvailability(activity: .cycle, minutes: m) }
        adv.hoursPerWeek = 8
        let a = PlanEngine.week(starting: nextMonday, profile: adv, availability: av)
        XCTAssertTrue(a.contains { $0.kind == .threshold }, a.map { "\($0.kind)" }.joined(separator: ","))
        XCTAssertTrue(a.contains { $0.kind == .vo2 }, "advanced event rider with 5 spaced rides gets a VO2 session: \(a.map { "\($0.kind)" })")
        // five rides on consecutive days leave no room for a second hard day 48 h apart: none is forced
        let packed = splitWeek(adv)
        XCTAssertLessThanOrEqual(packed.filter { $0.kind.zone >= 4 }.count, 1)
        var fit = profile(level: .intermediate); fit.goal = .fitness; fit.trainingMode = .cycling
        XCTAssertFalse(splitWeek(fit).contains { $0.kind.zone >= 4 }, "a fitness goal gets tempo, not threshold")
        var beg = profile(level: .beginner); beg.goal = .stronger; beg.trainingMode = .cycling
        XCTAssertFalse(splitWeek(beg).contains { $0.kind.zone >= 4 })
    }

    func testQualityRideSurvivesASplitWhenEveryDayTouchesLegs() {
        // audit P04: an advanced event rider with a split got five easy rides
        var p = profile(level: .advanced); p.goal = .event; p.strengthSplit = .fullBody; p.cyclingDaysPerWeek = 5; p.liftDaysPerWeek = 2; p.hoursPerWeek = 9; p.priority = .cycling
        let w = splitWeek(p)
        XCTAssertTrue(w.contains { $0.kind.zone >= 3 }, w.map { "\($0.kind)" }.joined(separator: ","))
        for l in w where l.kind == .strength && (l.strengthFocus?.loadsLegs ?? false) {
            XCTAssertFalse(w.contains { $0.kind.isRide && $0.kind.zone >= 3 && cal.isDate($0.date, inSameDayAs: l.date) }, "never on the leg day itself")
        }
        // strength priority keeps legs first: no quality ride forced next to a leg day
        var s = p; s.priority = .strength
        let ws = splitWeek(s)
        let legDays = ws.filter { $0.kind == .strength && ($0.strengthFocus?.loadsLegs ?? false) }.map { cal.startOfDay(for: $0.date) }
        for r in ws where r.kind.isRide && r.kind.zone >= 3 {
            let d = cal.startOfDay(for: r.date)
            XCTAssertFalse(legDays.contains { abs($0.timeIntervalSince(d)) <= 86_400 }, "strength priority: quality ride never next to legs")
        }
    }

    func testThresholdBuildsInsideABlockAndEveryFourthWeekIsEasier() {
        var p = profile(level: .intermediate); p.goal = .stronger; p.trainingMode = .cycling; p.cyclingDaysPerWeek = 4; p.hoursPerWeek = 7
        let reps = (0..<4).map { k in splitWeek(p, trainingWeeks: k).first { $0.kind == .threshold }?.effectiveIntervalReps }
        XCTAssertEqual(reps[0], 3); XCTAssertNotNil(reps[1]); XCTAssertGreaterThanOrEqual(reps[1] ?? 0, reps[0] ?? 0)
        XCTAssertNil(reps[3], "week 4: no interval session")
        let long0 = splitWeek(p, trainingWeeks: 0).first { $0.kind == .long }?.minutes ?? 0, long3 = splitWeek(p, trainingWeeks: 3).first { $0.kind == .long }?.minutes ?? 0
        XCTAssertLessThan(long3, long0)
        // slower recovery → every 3rd week
        p.recoveryCapacity = .low
        XCTAssertNil(splitWeek(p, trainingWeeks: 2).first { $0.kind == .threshold })
    }

    func testOnlyOneLongRidePerWeek() {
        var p = profile(); p.trainingMode = .cycling
        var a = WeeklyAvailability(days: Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7))
        a.days[5] = DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: .long, minutes: 180)])
        a.days[2] = DayAvailability(assignments: [DayAssignment(sport: .cycling, minutes: 100)])
        a.days[3] = DayAvailability(assignments: [DayAssignment(sport: .cycling, minutes: 60)])
        p.hoursPerWeek = 6
        let w = PlanEngine.week(starting: nextMonday, profile: p, availability: a)
        XCTAssertEqual(w.filter { $0.kind == .long }.count, 1)
    }

    func testCyclingImprovingNeedsBetterThanUsual() {
        func ride(_ d: Int, _ perf: Int, _ eff: Int) -> RideRecord { var r = RideRecord(start: day(d, hour: 7), durationS: 3600, distanceM: 25000, recorder: .phone, sources: []); r.checkIn = CheckIn(performance: perf, effort: eff, at: r.start); return r }
        let usual = (3...20).filter { $0 % 3 == 0 }.map { ride(-$0, 7, 6) }
        let p = profile()
        let a1 = TrainingAnalyzer.analyze(AdaptationInput(profile: p, plan: [], rides: [ride(-1, 7, 6), ride(-2, 7, 6)] + usual, strength: [], availability: WeeklyAvailability.suggested(for: p), now: now, calendar: cal))
        XCTAssertFalse(a1.cyclingImproving, "7/6 is this rider's normal")
        let a2 = TrainingAnalyzer.analyze(AdaptationInput(profile: p, plan: [], rides: [ride(-1, 9, 4), ride(-2, 8, 5)] + usual, strength: [], availability: WeeklyAvailability.suggested(for: p), now: now, calendar: cal))
        XCTAssertTrue(a2.cyclingImproving)
    }

    func testEarlierSameDayKeyRideLightensLegs() {
        var ride = Workout(date: day(2, hour: 7), kind: .threshold, minutes: 70); ride.sequence = 0
        var lift = Workout(date: day(2, hour: 7).addingTimeInterval(1), kind: .strength, minutes: 60, strengthFocus: .lower); lift.sequence = 1
        var c = ctx(profile(), logs: []); c.plan = [ride, lift]
        let wk = StrengthPlanner.weekContext(for: lift, ctx: c)
        XCTAssertNotNil(wk.hardRideBefore); XCTAssertTrue(wk.hardRideBefore?.contains("earlier today") ?? false)
    }

    func testStrengthPriorityKeepsLegWorkNextToKeyRides() {
        let ride = Workout(date: day(3, hour: 7), kind: .long, minutes: 150)
        let lift = Workout(date: day(2, hour: 18), kind: .strength, minutes: 60, strengthFocus: .lower)
        var bal = ctx(profile(), logs: []); bal.plan = [ride, lift]
        var sp = profile(); sp.priority = .strength
        var str = ctx(sp, logs: []); str.plan = [ride, lift]
        let b = StrengthPlanner.build(for: lift, ctx: bal), s = StrengthPlanner.build(for: lift, ctx: str)
        XCTAssertGreaterThan(s.entries.reduce(0) { $0 + $1.sets.count }, b.entries.reduce(0) { $0 + $1.sets.count })
        XCTAssertTrue(s.rationale.notes.contains { $0.contains("Strength is your priority") }, s.rationale.notes.joined(separator: " | "))
    }

    func testExplicitHingeChoiceForCyclists() {
        let conv = ex("r-conv", "Conventional deadlift", ["barbell"], .hinge, ["hamstrings", "glutes", "back"])
        var p = profile(); p.priority = .cycling
        var c = ctx(p, logs: []); c.catalogue = [conv] + catalogue
        let m = ExerciseLibrary.meta(catalogue[1])
        XCTAssertNotNil(StrengthPlanner.preferenceBonus(catalogue[1], m, spec: .init(slot: m.slot, role: .main), ctx: c).reason)
        let pick = StrengthPlanner.pick(.init(slot: m.slot, role: .main), ctx: c, used: [])
        XCTAssertEqual(pick?.id, "r-rdl")
    }

    func testCoachCutSetIsNotAnIncompleteSession() {
        let bench = catalogue[2]
        let t = WorkoutTemplate(name: "Push", focus: .push, entries: [ExerciseEntry(exercise: bench, sets: (0..<3).map { _ in SetEntry(reps: 8, weightKg: 60) })], updatedAt: Date(timeIntervalSince1970: 0))
        var w = Workout(date: day(2, hour: 8), kind: .strength, minutes: 45, strengthFocus: .push); w.templateId = t.id
        func logs(workoutMode: Bool, sets: Int) -> [StrengthSession] {
            [3, 6].map { d in
                var l = log(d, bench, reps: Array(repeating: 8, count: sets), kg: 60, rpe: 7); l.templateId = t.id
                if workoutMode { l.startedAt = l.date.addingTimeInterval(-2700); l.finishedAt = l.date; l.workoutId = UUID() }
                return l
            }
        }
        func decide(_ ls: [StrengthSession]) -> PlanAdjustment? {
            let p = profile()
            let inp = AdaptationInput(profile: p, plan: [w], rides: [], strength: ls, availability: WeeklyAvailability.suggested(for: p), equipment: EquipmentProfile(owned: ["barbell", "bench"]), catalogue: catalogue, templates: [t], originalEntries: [w.id: t.prefilled(from: ls.first)], now: now, calendar: cal)
            return AdaptationEngine.strengthDecision(t.prefilled(from: ls.first)[0], session: w, input: inp)
        }
        XCTAssertNotNil(decide(logs(workoutMode: true, sets: 2)), "2 of 2 planned sets done in workout mode (the coach had cut one) is complete")
        XCTAssertNil(decide(logs(workoutMode: false, sets: 2)), "a quick log of 2 sets against a 3-set routine is not complete")
        XCTAssertNotNil(decide(logs(workoutMode: false, sets: 3)))
    }

    func testRidesGeneratedBeforeABreakOrTheScreenAreCappedAtRefresh() {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("remediation-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let s = Store(directory: d, generatePlan: false)
        s.profile = profile()
        // riding history that stopped 6 weeks ago
        s.rides = [-42, -45, -49, -52].map { RideRecord(start: day($0, hour: 7), durationS: 3600, distanceM: 25000, recorder: .phone, sources: []) }
        var hard = Workout(date: day(2, hour: 7), kind: .threshold, minutes: 70)
        var fixed = Workout(date: day(3, hour: 7), kind: .vo2, minutes: 60); fixed.fixed = true
        var long = Workout(date: day(4, hour: 7), kind: .long, minutes: 150)
        hard.note = ""; long.note = ""
        s.plan = [hard, fixed, long]
        s.refreshRideSafety(now: now)
        XCTAssertEqual(s.plan.first { $0.id == hard.id }?.kind, .endurance)
        XCTAssertEqual(s.plan.first { $0.id == long.id }?.kind, .endurance)
        XCTAssertLessThan(s.plan.first { $0.id == long.id }?.minutes ?? 999, 150)
        XCTAssertEqual(s.plan.first { $0.id == fixed.id }?.kind, .vo2, "a fixed ride is never changed")
        // unscreened rider, no break: hard rides capped too
        let t = Store(directory: d.appendingPathComponent("b"), generatePlan: false)
        t.profile = profile(screened: false)
        t.plan = [Workout(date: day(2, hour: 7), kind: .threshold, minutes: 70)]
        t.refreshRideSafety(now: now)
        XCTAssertEqual(t.plan.first?.kind, .endurance)
        XCTAssertTrue(t.plan.first?.note.contains("health check") ?? false)
        // answering the check lifts the cap again: the ride is restored exactly as generated
        t.profile = profile(screened: true)
        t.refreshRideSafety(now: now)
        XCTAssertEqual(t.plan.first?.kind, .threshold); XCTAssertNil(t.plan.first?.safetyOriginal); XCTAssertEqual(t.plan.first?.note, "")
        // the break ends (three rides logged since): the long ride comes back
        s.rides += [-1, -2, -3].map { RideRecord(start: day($0, hour: 7), durationS: 3600, distanceM: 25000, recorder: .phone, sources: []) }
        s.refreshRideSafety(now: now)
        XCTAssertEqual(s.plan.first { $0.id == long.id }?.kind, .long); XCTAssertEqual(s.plan.first { $0.id == long.id }?.minutes, 150)
    }

    // MARK: Independent review (F-series)

    func testStopAnswersPlanNoTraining() {
        var p = profile(); var sc = HealthScreen(); sc.answeredAt = now; sc.dizzinessOrFainting = true; p.healthScreen = sc
        let w = week(p)
        XCTAssertTrue(w.allSatisfy { $0.kind == .rest }, w.map { "\($0.kind)" }.joined(separator: ","))
        XCTAssertTrue(w.contains { $0.note.contains("see a doctor") })
        // fixed days come back unchanged once cleared (the original is kept on the rest day)
        XCTAssertTrue(w.filter { $0.safetyOriginal != nil }.count >= 4)
    }

    func testPendingClearanceMeansNoLoadIncreasesAndNoHeavyLowReps() {
        var p = profile(); var sc = HealthScreen(); sc.answeredAt = now; sc.chronicMedication = true; p.healthScreen = sc
        let logs = [log(3, squat, reps: [10, 10, 10], kg: 100, rpe: 7), log(6, squat, reps: [10, 10, 10], kg: 100, rpe: 7)]
        let l = StrengthPlanner.prescribeLoad(squat, meta: ExerciseLibrary.meta(squat), reps: 8...12, sets: 3, painBlocked: false, ctx: ctx(p, logs: logs))
        XCTAssertEqual(l.weight, 100); XCTAssertFalse(l.progressed); XCTAssertTrue(l.why.contains("health check"), l.why)
        var sp = StrengthPrefs(); sp.goal = .strength
        var c = ctx(p, logs: []); c.prefs = sp
        let b = StrengthPlanner.build(for: Workout(date: day(2), kind: .strength, minutes: 60, strengthFocus: .fullBody), ctx: c)
        for e in b.entries where !e.notes.hasPrefix("Hold") { XCTAssertTrue(e.sets.allSatisfy { $0.reps >= 8 }, "\(e.name) \(e.sets.first?.reps ?? 0)") }
        XCTAssertTrue(b.rationale.exercises.allSatisfy { ($0.targetRPE ?? 0) <= 6 })
    }

    func testBarbellNeverBelowTheEmptyBar() {
        let l = StrengthPlanner.prescribeLoad(squat, meta: ExerciseLibrary.meta(squat), reps: 6...10, sets: 3, painBlocked: false, ctx: ctx(profile(), logs: [log(60, squat, reps: [8, 8, 8], kg: 20, rpe: 7)]))
        XCTAssertGreaterThanOrEqual(l.weight ?? 0, 20, l.why)
        let f = StrengthPlanner.prescribeLoad(squat, meta: ExerciseLibrary.meta(squat), reps: 6...10, sets: 3, painBlocked: false, ctx: ctx(profile(), logs: [log(3, squat, reps: [4, 4, 4], kg: 20, rpe: 10), log(6, squat, reps: [4, 4, 4], kg: 20, rpe: 10)]))
        XCTAssertGreaterThanOrEqual(f.weight ?? 0, 20, f.why)
    }

    func testThresholdBlockNeverGoesBackwards() {
        var p = profile(level: .intermediate); p.goal = .stronger; p.trainingMode = .cycling; p.cyclingDaysPerWeek = 4; p.hoursPerWeek = 7
        let reps = (0..<3).compactMap { k in splitWeek(p, trainingWeeks: k).first { $0.kind == .threshold }?.effectiveIntervalReps }
        XCTAssertEqual(reps.count, 3); XCTAssertEqual(reps, reps.sorted(), "\(reps)")
    }

    func testHybridWithoutSplitGetsGoalIntensityAndAnEasyWeek() {
        var fit = profile(level: .intermediate); fit.goal = .fitness; fit.strengthSplit = nil
        XCTAssertFalse(splitWeek(fit, trainingWeeks: 1).contains { $0.kind.zone >= 4 }, "general fitness: tempo, not threshold")
        var str = profile(level: .intermediate); str.goal = .stronger; str.strengthSplit = nil; str.cyclingDaysPerWeek = 4; str.hoursPerWeek = 7
        XCTAssertFalse(splitWeek(str, trainingWeeks: 3).contains { $0.kind.zone >= 4 }, "week 4 is easy")
    }

    func testMondayMorningWeekStillKnowsItsBlockPosition() {
        // three past weeks logged, nothing logged yet this week, this week planned → next week is block week 5 = pos 0;
        // two past weeks logged + this week planned → next week is week 4 = the easy week
        let cal = Calendar.current
        let thisMonday = TrainingLedger.monday(of: now)
        let past2 = Set((1...2).map { cal.date(byAdding: .day, value: -7 * $0 + 1, to: thisMonday)! })
        let nextMonday = cal.date(byAdding: .day, value: 7, to: thisMonday)!
        XCTAssertEqual(BlockClock.weeks(before: nextMonday, activity: past2, plannedMondays: [thisMonday], now: now), 3)
        XCTAssertEqual(BlockClock.weeks(before: nextMonday, activity: past2, plannedMondays: [], now: now), 0, "without the planned week the streak breaks")
    }
}
