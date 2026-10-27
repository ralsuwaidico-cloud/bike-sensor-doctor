// Copied unchanged from the independent review of 02d8795 (/home/claude/coach-review): assertions encode what a correct
// coach should do; they failed on 02d8795 and are kept as regression tests for the fixes.
import XCTest
@testable import BikeComputer

/// Independent-review probes (read-only on the reviewed code). Each test PRINTS what the engine does; assertions encode
/// what a correct coach should do, so a FAILURE = a confirmed finding.
final class ReviewProbeTests: XCTestCase {
    let cal = Calendar.current
    var today: Date { cal.startOfDay(for: Date()) }
    var thisMonday: Date { let wd = (cal.component(.weekday, from: today) + 5) % 7; return cal.date(byAdding: .day, value: -wd, to: today)! }
    var nextMonday: Date { cal.date(byAdding: .day, value: 7, to: thisMonday)! }
    func at(_ base: Date, _ d: Int, _ h: Int = 7) -> Date { cal.date(byAdding: .day, value: d, to: base)!.addingTimeInterval(TimeInterval(h * 3600)) }
    func screened(_ p: inout RiderProfile) { var s = HealthScreen(); s.answeredAt = Date(timeIntervalSince1970: 1_790_000_000); p.healthScreen = s }
    func desc(_ w: [Workout]) -> String { w.filter { $0.kind != .rest }.sorted { $0.date < $1.date }.map { "\($0.date.shortDay):\($0.kind.rawValue)\($0.minutes)\($0.effectiveIntervalReps.map { "x\($0)" } ?? "")" }.joined(separator: " ") }
    func store() -> Store { let d = FileManager.default.temporaryDirectory.appendingPathComponent("rev-\(UUID().uuidString)"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return Store(directory: d, generatePlan: false) }
    func ride(_ d: Date, _ min: Int = 60) -> RideRecord { RideRecord(start: d, durationS: min * 60, distanceM: 25000, recorder: .phone, sources: []) }

    // R1: easy week ignored when the availability carries typed rides (hybrid without split: suggested(for:) types them)
    func testR1_EasyWeekWithTypedAvailability() {
        var p = RiderProfile(); p.trainingMode = .hybrid; p.priority = .balanced; p.level = .intermediate; p.goal = .stronger
        p.hoursPerWeek = 7; p.liftingHoursPerWeek = 2; p.cyclingDaysPerWeek = 4; p.liftDaysPerWeek = 2; screened(&p)
        let a = WeeklyAvailability.suggested(for: p)
        print("R1 availability types:", a.days.map { $0.assignments.map { "\($0.sport.rawValue):\($0.cyclingType?.rawValue ?? "nil"):\($0.minutes)" } })
        for k in 0..<4 { print("R1 trainingWeeks=\(k):", desc(PlanEngine.week(starting: nextMonday, profile: p, availability: a, trainingWeeks: k))) }
        let easy = PlanEngine.week(starting: nextMonday, profile: p, availability: a, trainingWeeks: 3)
        XCTAssertFalse(easy.contains { $0.kind.zone >= 4 }, "R1: the 4th (easy) week still contains an interval session")
    }
    // R2: goal-based intensity bypassed for typed rides (health goal gets threshold)
    func testR2_GoalIntensityWithTypedAvailability() {
        var p = RiderProfile(); p.trainingMode = .hybrid; p.priority = .balanced; p.level = .intermediate; p.goal = .fitness
        p.hoursPerWeek = 6; p.liftingHoursPerWeek = 2; p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 2; screened(&p)
        let w = PlanEngine.week(starting: nextMonday, profile: p, availability: WeeklyAvailability.suggested(for: p))
        print("R2 fitness goal hybrid:", desc(w))
        XCTAssertFalse(w.contains { $0.kind == .threshold }, "R2: a general-fitness goal should get tempo (M-05), got threshold")
    }
    // R3: threshold block 3 -> 4 -> 5 falls back to 3 when 5 does not fit the minutes
    func testR3_ThresholdBlockRegression() {
        var p = RiderProfile(); p.trainingMode = .cycling; p.level = .intermediate; p.goal = .stronger; p.hoursPerWeek = 7; p.cyclingDaysPerWeek = 4; screened(&p)
        let a = WeeklyAvailability.suggested(for: p)
        let reps = (0..<4).map { k in PlanEngine.week(starting: nextMonday, profile: p, availability: a, trainingWeeks: k).first { $0.kind == .threshold }.map { "\($0.minutes)min x\($0.effectiveIntervalReps ?? 0)" } ?? "none" }
        print("R3 threshold by block week:", reps)
        XCTAssertNotEqual(reps[2], reps[0], "R3: week 3 of the block drops back to week-1 reps")
    }
    // R4: the block position of NEXT week is fixed when it is first generated, i.e. before the current week is trained
    func testR4_BlockPositionDecidedAtGeneration() {
        var p = RiderProfile(); p.trainingMode = .cycling; p.level = .intermediate; p.goal = .stronger; p.hoursPerWeek = 7; p.cyclingDaysPerWeek = 4; screened(&p)
        let s = store(); s.profile = p
        // rode in each of the 2 previous weeks and will ride this week: next week = week 4 of a 3:1 block (easy)
        s.rides = [-14, -12, -10, -7, -5, -3].map { ride(at(thisMonday, $0)) }
        s.plan = []
        s.ensurePlan(now: at(thisMonday, 0, 6))      // Monday 06:00, nothing logged yet this week
        let next = s.plan.filter { $0.date >= nextMonday }
        print("R4 next week generated Monday 06:00:", desc(next), " streak=", s.consecutiveTrainingWeeks(before: nextMonday))
        s.rides.append(ride(at(thisMonday, 0, 7)))
        print("R4 streak once Monday is ridden:", s.consecutiveTrainingWeeks(before: nextMonday))
        XCTAssertFalse(next.contains { $0.kind.zone >= 4 }, "R4: next week should be the easy week (3 weeks trained) but was generated as build week 1")
    }
    // R5: an engine-adjusted ride (coachOriginal set) escapes the health-check cap
    func testR5_EngineAdjustedRideEscapesCap() {
        let s = store(); var p = RiderProfile(); p.trainingMode = .cycling; s.profile = p   // not screened
        var w = Workout(date: at(today, 2), kind: .threshold, minutes: 70); w.intervalReps = 4; w.coachOriginal = WorkoutPlanSnapshot(kind: .threshold, minutes: 70, plannedEntries: nil, intervalReps: nil, generatedEntries: false)
        s.plan = [w]; s.refreshRideSafety()
        print("R5 after refresh:", desc(s.plan))
        XCTAssertLessThanOrEqual(s.plan[0].kind.zone, 2, "R5: unscreened rider keeps an engine-adjusted threshold ride")
    }
    // R6: chest pain / supervised-only answers still get a full moderate programme incl. long rides and progressing lifts
    func testR6_ChestPainStillTrains() {
        var p = RiderProfile(); p.trainingMode = .hybrid; p.level = .intermediate; p.goal = .stronger; p.hoursPerWeek = 8; p.liftingHoursPerWeek = 2; p.cyclingDaysPerWeek = 4; p.liftDaysPerWeek = 2; p.strengthSplit = .fullBody
        var s = HealthScreen(); s.answeredAt = Date(); s.chestPain = true; s.supervisedOnly = true; p.healthScreen = s
        let w = PlanEngine.week(starting: nextMonday, profile: p, availability: WeeklyAvailability.suggested(for: p))
        print("R6 chest pain + supervised-only week:", desc(w), "status", p.readiness.screen)
        let sq = Exercise(id: "q", name: "Back squat", equipment: ["barbell"], pattern: .squat, muscles: ["quads"], unilateral: false, custom: true)
        func log(_ d: Int) -> StrengthSession { StrengthSession(date: at(today, -d, 18), minutes: 45, focus: .fullBody, rpe: 7, exercises: [ExerciseEntry(exercise: sq, sets: (0..<3).map { _ in SetEntry(reps: 6, weightKg: 100, rpe: 7, done: true) })]) }
        var prefs = StrengthPrefs(); prefs.goal = .strength
        let c = PlannerContext(profile: p, prefs: prefs, equipment: EquipmentProfile(owned: ["barbell"]), catalogue: [sq], logs: [log(3), log(6)], now: Date(), calendar: cal)
        let l = StrengthPlanner.prescribeLoad(sq, meta: ExerciseLibrary.meta(sq), reps: 4...6, sets: 3, painBlocked: false, ctx: c)
        print("R6 squat prescription:", l.weight ?? -1, l.why)
        XCTAssertTrue(w.filter { $0.kind != .rest }.isEmpty, "R6: chest pain / supervised-only -> the coach still plans \(w.filter { $0.kind != .rest }.count) sessions")
        XCTAssertFalse(l.progressed, "R6: load still progresses (100 -> \(l.weight ?? 0) kg) while clearance is pending")
    }
    // R7: return after a very long break — rides restart at 75 % whatever the length; loads may drop below the empty bar
    func testR7_ReturnScaling() {
        var p = RiderProfile(); p.trainingMode = .cycling; p.level = .intermediate; p.goal = .stronger; p.hoursPerWeek = 8; p.cyclingDaysPerWeek = 4; screened(&p)
        let a = WeeklyAvailability.suggested(for: p)
        for gap in [25, 200] {
            let r = ReturnPhase(breakDays: gap, sessionsSince: 0, ongoing: true)
            print("R7 break \(gap) d:", desc(PlanEngine.week(starting: nextMonday, profile: p, availability: a, returning: r)))
        }
        let bar = Exercise(id: "q", name: "Back squat", equipment: ["barbell"], pattern: .squat, muscles: ["quads"], unilateral: false, custom: true)
        let lg = StrengthSession(date: at(today, -60, 18), minutes: 45, focus: .fullBody, rpe: 7, exercises: [ExerciseEntry(exercise: bar, sets: (0..<3).map { _ in SetEntry(reps: 8, weightKg: 20, rpe: 7, done: true) })])
        let c = PlannerContext(profile: p, equipment: EquipmentProfile(owned: ["barbell"]), catalogue: [bar], logs: [lg], now: Date(), calendar: cal)
        let l = StrengthPlanner.prescribeLoad(bar, meta: ExerciseLibrary.meta(bar), reps: 6...10, sets: 3, painBlocked: false, ctx: c)
        print("R7 barbell 20 kg after 60 d:", l.weight ?? -1)
        XCTAssertGreaterThanOrEqual(l.weight ?? 0, 20, "R7: barbell load prescribed below the empty bar")
    }
    // R8: knee pain from lifting can only be cleared by sessions that load knees, which the planner has just removed
    func testR8_PainHoldDeadlock() {
        var p = RiderProfile(); p.trainingMode = .hybrid; screened(&p)
        let sq = Exercise(id: "q", name: "Back squat", equipment: ["barbell"], pattern: .squat, unilateral: false, custom: true)
        let rdl = Exercise(id: "h", name: "Glute bridge", equipment: ["bodyweight"], pattern: .hinge, unilateral: false, custom: true)
        let bench = Exercise(id: "b", name: "Bench press", equipment: ["barbell"], pattern: .push, unilateral: false, custom: true)
        func lg(_ d: Int, _ es: [Exercise], pain: PainLevel, area: PainArea? = nil) -> StrengthSession {
            var s = StrengthSession(date: at(today, -d, 18), minutes: 45, focus: .lower, rpe: 7, exercises: es.map { ExerciseEntry(exercise: $0, sets: [SetEntry(reps: 8, weightKg: 40, rpe: 7, done: true)]) })
            s.checkIn = CheckIn(performance: 7, effort: 6, pain: pain, painArea: area, at: s.date); return s
        }
        let logs = [lg(30, [sq, rdl], pain: .concerning, area: .knees)] + [25, 20, 15, 10, 5].map { lg($0, [rdl, bench], pain: .noPain) }
        let an = TrainingAnalyzer.analyze(AdaptationInput(profile: p, plan: [], rides: [], strength: logs, availability: WeeklyAvailability.suggested(for: p), now: Date(), calendar: cal))
        print("R8 pain areas after 5 pain-free lower sessions without squats over 25 days:", an.painAreas)
        // CHANGED after the review (owner instruction 27 Oct 11:35): concerning pain is never released automatically.
        // The reviewer's deadlock (R8) is resolved by ASKING the rider once the hold conditions are met.
        XCTAssertEqual(an.painAreas, [.knees], "concerning pain stays held until the rider confirms")
        XCTAssertEqual(an.painReviewDue, [.knees], "R8: after the hold and pain-free sessions the rider is asked")
    }
    // R9: strength deload week vs cycling easy week computed from different streaks
    func testR9_DeloadMisalignment() {
        var p = RiderProfile(); p.trainingMode = .hybrid; p.level = .intermediate; p.goal = .stronger; p.hoursPerWeek = 7; p.liftingHoursPerWeek = 2; p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 2; p.strengthSplit = .fullBody; screened(&p)
        let s = store(); s.profile = p
        s.rides = [-20, -13, -6].map { ride(at(thisMonday, $0)) }        // 3 riding weeks
        let sq = Exercise(id: "q", name: "Back squat", equipment: ["barbell"], pattern: .squat, unilateral: false, custom: true)
        s.strength = [StrengthSession(date: at(thisMonday, -4, 18), minutes: 45, focus: .fullBody, rpe: 7, exercises: [ExerciseEntry(exercise: sq, sets: [SetEntry(reps: 8, weightKg: 40, rpe: 7, done: true)])])]
        let wk = PlanEngine.week(starting: thisMonday, profile: p, availability: WeeklyAvailability.suggested(for: p), trainingWeeks: s.consecutiveTrainingWeeks(before: thisMonday))
        let lift = wk.first { $0.kind == .strength }!
        var c = s.plannerContext(); c.plan = wk
        let ctxw = StrengthPlanner.weekContext(for: lift, ctx: c)
        print("R9 cycling week:", desc(wk), "| strength deload:", ctxw.deload, "| streak(all)=", s.consecutiveTrainingWeeks(before: thisMonday))
        // with quick (non-detailed) logs the strength streak is always 0
        XCTAssertEqual(!wk.contains { $0.kind.zone >= 4 }, ctxw.deload, "R9: cycling easy week and strength deload fall in different weeks")
    }
    // R10: unscreened rider still gets tempo capped? (zone 3 > maxRideZone 2) and long rides of any length
    func testR10_UnscreenedCaps() {
        var p = RiderProfile(); p.trainingMode = .cycling; p.level = .beginner; p.goal = .fitness; p.hoursPerWeek = 10; p.cyclingDaysPerWeek = 4
        let w = PlanEngine.week(starting: nextMonday, profile: p, availability: WeeklyAvailability.suggested(for: p))
        print("R10 unscreened beginner 10 h:", desc(w))
    }
    // R11: ACWR with a perfectly steady 5-week history
    func testR11_ACWRSteady() {
        var p = RiderProfile(); p.trainingMode = .cycling; screened(&p)
        for hist in [29, 31, 35, 40] {
            var rides: [RideRecord] = []
            for d in stride(from: 1, through: hist, by: 1) where d % 2 == 0 { var r = ride(at(today, -d, 7)); r.checkIn = CheckIn(performance: 7, effort: 5, at: r.start); rides.append(r) }
            let an = TrainingAnalyzer.analyze(AdaptationInput(profile: p, plan: [], rides: rides, strength: [], availability: WeeklyAvailability.suggested(for: p), now: Date(), calendar: cal))
            print("R11 history \(hist) d every 2nd day: ACWR=", an.acwr.map { String(format: "%.2f", $0) } ?? "nil")
        }
    }
    // R12: VO2 + threshold placement for an advanced rider with 5 rides
    func testR12_AdvancedWeek() {
        var p = RiderProfile(); p.trainingMode = .cycling; p.level = .advanced; p.goal = .event; p.hoursPerWeek = 10; p.cyclingDaysPerWeek = 5; screened(&p)
        for k in 0..<4 { print("R12 advanced event 5 rides wk\(k):", desc(PlanEngine.week(starting: nextMonday, profile: p, availability: WeeklyAvailability.suggested(for: p), trainingWeeks: k))) }
        p.cyclingDaysPerWeek = 6; p.hoursPerWeek = 12
        print("R12 advanced 6 rides:", desc(PlanEngine.week(starting: nextMonday, profile: p, availability: WeeklyAvailability.suggested(for: p), trainingWeeks: 1)))
        p.age = 62
        print("R12 advanced 6 rides age 62:", desc(PlanEngine.week(starting: nextMonday, profile: p, availability: WeeklyAvailability.suggested(for: p), trainingWeeks: 1)))
    }
}
