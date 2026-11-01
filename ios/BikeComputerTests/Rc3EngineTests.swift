import XCTest
@testable import BikeComputer

/// RC3 engine acceptance tests (blueprint/engine/WP2_APPROVAL.md AT-* ids; level HOST = Linux coach harness).
final class Rc3EngineTests: XCTestCase {
    let cal: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; c.firstWeekday = 2; return c }()
    var nextMonday: Date { let c = Calendar.current; let t = c.startOfDay(for: Date()); let wd = (c.component(.weekday, from: t) + 5) % 7; return c.date(byAdding: .day, value: 7 - wd, to: t)! }

    private func store() -> Store {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("rc3-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return Store(directory: d, generatePlan: false)
    }
    private func day(_ sport: DayAssignment.Sport?, _ minutes: Int = 0) -> DayAvailability {
        guard let s = sport else { return DayAvailability(activity: .rest, minutes: 0) }
        return DayAvailability(assignments: [DayAssignment(sport: s, minutes: minutes)])
    }
    /// The owner-like hybrid: strength Mon/Wed/Fri 30 min, rides Tue/Sat 60 min, explicit week.
    private func hybridPersona(_ s: Store, equipment: EquipmentProfile = EquipmentProfile(owned: ["dumbbell", "bench"])) {
        var p = RiderProfile.screened(); p.trainingMode = .hybrid; p.priority = .balanced; p.hoursPerWeek = 2; p.liftingHoursPerWeek = 1
        p.cyclingDaysPerWeek = 2; p.liftDaysPerWeek = 3; p.weekIsExplicit = true; p.goal = .endurance
        s.profile = p
        s.strengthPrefs.experience = .intermediate; s.strengthPrefs.prefersSupersets = true
        s.equipment = equipment
        s.availability = WeeklyAvailability(days: [day(.strength, 30), day(.cycling, 60), day(.strength, 30), day(nil), day(.strength, 30), day(.cycling, 60), day(nil)])
    }

    // MARK: ENG-E5 — ride steps add up
    func testAT_E5_1_TempoStepsFit() {
        func mins(_ m: Int) -> [Int] { Workout(date: Date(), kind: .tempo, minutes: m).rideSteps.map(\.minutes) }
        XCTAssertEqual(mins(45), [10, 15, 15, 5])
        XCTAssertEqual(mins(60), [15, 15, 5, 15, 10])
        XCTAssertEqual(mins(90), [15, 15, 5, 15, 5, 15, 10, 10])
    }
    func testAT_E5_2_EveryKindEveryLengthSumsExactly() {
        for k in WorkoutKind.allCases where k.isRide {
            for m in stride(from: 20, through: 240, by: 5) {
                let w = Workout(date: Date(), kind: k, minutes: m)
                XCTAssertEqual(w.rideSteps.reduce(0) { $0 + $1.minutes }, m, "\(k) \(m)")
                XCTAssertTrue(w.rideSteps.allSatisfy { $0.minutes > 0 }, "\(k) \(m)")
                XCTAssertEqual(WorkoutValidator.rideStepsMinutes(w), m)
            }
        }
    }
    func testAT_E5_3_ThresholdRepsThatFit() {
        let w = Workout(date: Date(), kind: .threshold, minutes: 60)
        XCTAssertEqual(w.fittedIntervalReps, 3)
        XCTAssertEqual(w.rideSteps.filter { $0.role == .work }.count, 3)
        XCTAssertEqual(w.rideSteps.last(where: { $0.role == .easy })?.minutes, 2, "15 + 3 × 11 + 10 = 58 → 2 min easy")
        XCTAssertEqual(w.liveIntervalPlan?.repeats, 3, "the live coach runs the same reps")
    }

    // MARK: ENG-E1 / E3 — FTP state and effort targets
    func testAT_E1_1_UnknownFTPHasNoWatts() {
        let p = RiderProfile()                      // ftpHow = .assumed → Unknown
        XCTAssertFalse(p.ftpKnown); XCTAssertNil(p.targetFTP); XCTAssertEqual(p.ftpSource, .unknown); XCTAssertEqual(p.ftpDisplay, "Unknown")
        for k in WorkoutKind.allCases where k.isRide {
            let steps = Workout(date: Date(), kind: k, minutes: 60).steps(ftp: p.targetFTP ?? 0)
            XCTAssertFalse(steps.contains { $0.target.contains(" W") }, "\(k): \(steps.map(\.target))")
            XCTAssertTrue(Workout(date: Date(), kind: k, minutes: 60).rideSteps.allSatisfy { $0.watts(ftp: p.targetFTP) == nil })
        }
        XCTAssertEqual(p.linkMessage(units: .metric).ftpW, 0, "the board never receives an invented FTP")
    }
    func testAT_E1_3_EnteredFTPGivesTaggedWatts() {
        var p = RiderProfile(); p.setFTP(250, source: .entered)
        XCTAssertEqual(p.ftpSource, .entered); XCTAssertNotNil(p.targetFTP)
        let steps = Workout(date: Date(), kind: .tempo, minutes: 60).steps(ftp: p.targetFTP!)
        XCTAssertTrue(steps.contains { $0.target.contains(" W") })
        XCTAssertEqual(p.ftpBadge, "entered")
    }
    func testAT_E3_1_UnknownFTPTempoTargetsEffortAndHR() {
        let p = RiderProfile()
        let w = Workout(date: Date(), kind: .tempo, minutes: 60)
        let work = w.rideSteps.filter { $0.role == .work }
        XCTAssertTrue(work.allSatisfy { $0.rpe == 5...6 && $0.hrZone == 3 })
        XCTAssertTrue(w.rideSteps.filter { $0.role == .warmUp || $0.role == .coolDown }.allSatisfy { $0.rpe == 2...3 })
        XCTAssertTrue(work[0].targetText(ftp: nil, hrZones: p.hrZones).contains("HR Z3"))
        XCTAssertEqual(work[0].targetText(ftp: nil, hrZones: nil), "RPE 5–6", "no HR source → effort only (AT-E3-2)")
    }

    // MARK: ENG-D1 / C2 / C1 / A1 / H1 — the week
    func testAT_D1_1_C2_1_ThreeShortLiftsAreFullBodyAndFit() {
        let s = store(); hybridPersona(s)
        let w = PlanEngine.week(starting: nextMonday, profile: s.profile, availability: s.availability!)
        let lifts = w.filter { $0.kind == .strength }, rides = w.filter { $0.kind.isRide }
        XCTAssertEqual(lifts.map(\.strengthFocus), [.fullBody, .fullBody, .fullBody])
        XCTAssertEqual(lifts.map(\.minutes), [30, 30, 30], "session length is the stated maximum, not hours ÷ sessions")
        XCTAssertEqual(rides.map(\.minutes), [60, 60])
        s.plan = w
        s.refreshGeneratedSessions(now: nextMonday.addingTimeInterval(-86_400))
        for l in s.plan.filter({ $0.kind == .strength }) {
            let es = s.plannedEntries(for: l)
            XCTAssertFalse(es.isEmpty)
            let est = DurationModel().minutes(es, catalogue: s.allExercises)
            XCTAssertLessThanOrEqual(est, 29.0 + 0.001, "DurationModel estimate ≤ 29 min (TIME-001)")
            let cov = WorkoutValidator.coverage(es, catalogue: s.allExercises)
            XCTAssertGreaterThanOrEqual([cov.knee > 0, cov.hip > 0, cov.push > 0, cov.pull > 0].filter { $0 }.count, 3, "full body: at least three of knee / hip / push / pull in 30 min")
        }
    }
    func testAT_D1_2_FourLongLiftsAlternateUpperLower() {
        var p = RiderProfile.screened(); p.trainingMode = .strength; p.liftDaysPerWeek = 4; p.weekIsExplicit = true
        let a = WeeklyAvailability(days: [day(.strength, 60), day(nil), day(.strength, 60), day(nil), day(.strength, 60), day(nil), day(.strength, 60)])
        XCTAssertEqual(PlanEngine.week(starting: nextMonday, profile: p, availability: a).filter { $0.kind == .strength }.map(\.strengthFocus), [.upper, .lower, .upper, .lower])
    }
    func testAT_D1_4_TwoShortLiftsAreFullBody() {
        var p = RiderProfile.screened(); p.trainingMode = .strength; p.liftDaysPerWeek = 2; p.weekIsExplicit = true
        let a = WeeklyAvailability(days: [day(.strength, 30), day(nil), day(nil), day(.strength, 30), day(nil), day(nil), day(nil)])
        XCTAssertEqual(PlanEngine.week(starting: nextMonday, profile: p, availability: a).filter { $0.kind == .strength }.map(\.strengthFocus), [.fullBody, .fullBody])
    }
    func testAT_C2_2_PerDayOverrideKept() {
        let s = store(); hybridPersona(s)
        s.availability!.days[2] = day(.strength, 45)
        let lifts = PlanEngine.week(starting: nextMonday, profile: s.profile, availability: s.availability!).filter { $0.kind == .strength }
        XCTAssertEqual(lifts.map(\.minutes), [30, 45, 30])
    }
    func testAT_C1_1_CyclingOnlyUsesMarkedDays() {
        var p = RiderProfile.screened(); p.trainingMode = .cycling; p.cyclingDaysPerWeek = 3; p.preferredDays = [0, 3, 6]; p.cyclingSessionMinutes = 60; p.hoursPerWeek = 3
        let w = PlanEngine.week(starting: nextMonday, profile: p, availability: WeeklyAvailability.suggested(for: p))
        let rideDays = w.filter { $0.kind.isRide }.map { Store.weekdayIndex($0.date) }.sorted()
        XCTAssertEqual(rideDays, [0, 3, 6])
    }
    func testAT_C1_2_NoSessionOnARestDay() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            var p = RiderProfile.screened(); p.trainingMode = [.cycling, .hybrid, .strength].randomElement(using: &rng)!; p.weekIsExplicit = Bool.random(using: &rng)
            p.hoursPerWeek = Int.random(in: 2...10, using: &rng); p.liftingHoursPerWeek = Int.random(in: 1...4, using: &rng)
            var days: [DayAvailability] = []
            for _ in 0..<7 {
                switch Int.random(in: 0...2, using: &rng) {
                case 0: days.append(day(nil))
                case 1: days.append(day(.cycling, [30, 45, 60, 90].randomElement(using: &rng)!))
                default: days.append(day(.strength, [20, 30, 45, 60].randomElement(using: &rng)!))
                }
            }
            let a = WeeklyAvailability(days: days)
            let w = PlanEngine.week(starting: nextMonday, profile: p, availability: a)
            for (i, d) in days.enumerated() where d.isRest {
                let date = Calendar.current.date(byAdding: .day, value: i, to: nextMonday)!
                XCTAssertFalse(w.contains { Calendar.current.isDate($0.date, inSameDayAs: date) && $0.kind != .rest }, "rest day \(i)")
            }
        }
    }
    func testAT_A1_1_StrengthLevelIsItsOwnAnswer() {
        var p = RiderProfile.screened(); p.level = .advanced; p.trainingMode = .hybrid
        XCTAssertEqual(PlannerContext(profile: p).experience, .beginner, "never copied from the cycling level")
        var prefs = StrengthPrefs(); prefs.experience = .advanced
        XCTAssertEqual(PlannerContext(profile: p, prefs: prefs).experience, .advanced)
    }
    func testAT_H1_1_UnknownEquipmentPlansBodyweightOnly() {
        let s = store(); hybridPersona(s, equipment: EquipmentProfile())
        XCTAssertTrue(s.equipment.isProvisional)
        s.plan = PlanEngine.week(starting: nextMonday, profile: s.profile, availability: s.availability!)
        s.refreshGeneratedSessions(now: nextMonday.addingTimeInterval(-86_400))
        for l in s.plan.filter({ $0.kind == .strength }) {
            let es = s.plannedEntries(for: l)
            XCTAssertFalse(es.isEmpty)
            for e in es { let ex = s.allExercises.first { $0.id == e.exerciseId }!; XCTAssertTrue(EquipmentProfile.needsNothing(ex), "\(ex.name) needs \(ex.equipment)") }
            XCTAssertTrue(l.rationale?.notes.contains { $0.hasPrefix("Provisional") } ?? s.plan.first { $0.id == l.id }!.rationale!.notes.contains { $0.hasPrefix("Provisional") })
        }
    }

    // MARK: ENG-J2 / J3 — changes reach planned weeks only after preview; history is append-only
    func testAT_H1_2_J2_1_EquipmentChangeIsAPreviewedProposal() {
        let s = store(); hybridPersona(s, equipment: EquipmentProfile())
        s.plan = PlanEngine.week(starting: nextMonday, profile: s.profile, availability: s.availability!)
        s.refreshGeneratedSessions(now: nextMonday.addingTimeInterval(-86_400))
        let before = s.snapshot
        let id = s.proposePlanChange(cause: .equipment, now: nextMonday.addingTimeInterval(-86_400)) { $0.equipment = EquipmentProfile(owned: ["dumbbell", "bench"]) }
        XCTAssertNotNil(id)
        XCTAssertEqual(s.snapshot, before, "nothing saved before Apply")
        let p = s.pendingPlanChanges[id!]!
        XCTAssertFalse(p.after.isEmpty); XCTAssertTrue(p.after.allSatisfy { $0.kind == .strength || $0.kind.isRide || $0.kind == .rest })
        s.discardPlanChange(id!)
        XCTAssertEqual(s.snapshot, before, "Cancel leaves the plan byte-identical")
        let id2 = s.proposePlanChange(cause: .equipment, now: nextMonday.addingTimeInterval(-86_400)) { $0.equipment = EquipmentProfile(owned: ["dumbbell", "bench"]) }!
        XCTAssertTrue(s.applyPlanChange(id2, now: nextMonday.addingTimeInterval(-86_400)))
        XCTAssertEqual(s.equipment.owned, ["dumbbell", "bench"])
        XCTAssertEqual(s.planVersions.count, 1); XCTAssertEqual(s.planVersions[0].cause, .equipment)
    }
    func testAT_J2_1_DaysMoveTuesdayToThursday() {
        let s = store(); hybridPersona(s)
        s.plan = PlanEngine.week(starting: nextMonday, profile: s.profile, availability: s.availability!)
        let id = s.proposePlanChange(cause: .days, now: nextMonday.addingTimeInterval(-86_400)) { x in
            x.availability!.days[1] = DayAvailability(activity: .rest, minutes: 0)
            x.availability!.days[3] = DayAvailability(assignments: [DayAssignment(sport: .cycling, minutes: 60)])
        }!
        let p = s.pendingPlanChanges[id]!
        XCTAssertTrue(p.before.contains { Store.weekdayIndex($0.date) == 1 && $0.kind.isRide })
        XCTAssertTrue(p.after.contains { Store.weekdayIndex($0.date) == 3 && $0.kind.isRide })
        XCTAssertTrue(s.plan.contains { Store.weekdayIndex($0.date) == 1 && $0.kind.isRide }, "unchanged until Apply")
        XCTAssertTrue(s.applyPlanChange(id, now: nextMonday.addingTimeInterval(-86_400)))
        XCTAssertFalse(s.plan.contains { Store.weekdayIndex($0.date) == 1 && $0.kind.isRide && $0.date >= self.nextMonday })
        XCTAssertTrue(s.plan.contains { Store.weekdayIndex($0.date) == 3 && $0.kind.isRide && $0.date >= self.nextMonday })
    }
    func testAT_J2_2_J3_2_CompletedSessionsAndLogsUntouched() {
        let s = store(); hybridPersona(s)
        s.plan = PlanEngine.week(starting: nextMonday, profile: s.profile, availability: s.availability!)
        // Monday's lift done with a log; "now" is Wednesday
        let mon = s.plan.first { $0.kind == .strength && Store.weekdayIndex($0.date) == 0 }!
        if let i = s.plan.firstIndex(where: { $0.id == mon.id }) { s.plan[i].done = true; s.plan[i].completion = .recorded }
        s.strength = [StrengthSession(date: mon.date, minutes: 30, focus: .fullBody, rpe: 7, workoutId: mon.id)]
        let wed = Calendar.current.date(byAdding: .day, value: 2, to: nextMonday)!
        let logsBefore = s.strength, monBefore = s.plan.first { $0.id == mon.id }!
        for cause in [PlanChangeCause.equipment, .minutes, .strengthLevel] {
            let id = s.proposePlanChange(cause: cause, now: wed) { x in
                switch cause {
                case .equipment: x.equipment = EquipmentProfile(owned: ["barbell", "bench", "dumbbell"])
                case .minutes: x.availability!.days[4] = DayAvailability(assignments: [DayAssignment(sport: .strength, minutes: 45)])
                default: x.strengthPrefs.experience = .advanced
                }
            }
            if let id { XCTAssertFalse(s.pendingPlanChanges[id]!.before.contains { $0.id == mon.id }); _ = s.applyPlanChange(id, now: wed) }
            XCTAssertEqual(s.strength, logsBefore, "logs identical after \(cause)")
            XCTAssertEqual(s.plan.first { $0.id == mon.id }, monBefore, "completed session identical after \(cause)")
        }
    }
    func testAT_J2_4_HandEditedSessionKept() {
        let s = store(); hybridPersona(s)
        s.plan = PlanEngine.week(starting: nextMonday, profile: s.profile, availability: s.availability!)
        let fri = s.plan.first { $0.kind == .strength && Store.weekdayIndex($0.date) == 4 }!
        if let i = s.plan.firstIndex(where: { $0.id == fri.id }) { s.plan[i].edited = true }
        let id = s.proposePlanChange(cause: .equipment, now: nextMonday.addingTimeInterval(-86_400)) { $0.equipment = EquipmentProfile(owned: ["barbell", "bench"]) }!
        let p = s.pendingPlanChanges[id]!
        XCTAssertTrue(p.kept.contains { $0.id == fri.id }); XCTAssertFalse(p.before.contains { $0.id == fri.id })
    }
    func testAT_J3_3_UndoIsANewProposalAndTheLogGrows() {
        let s = store(); hybridPersona(s)
        s.plan = PlanEngine.week(starting: nextMonday, profile: s.profile, availability: s.availability!)
        let now = nextMonday.addingTimeInterval(-86_400)
        let id = s.proposePlanChange(cause: .days, now: now) { x in x.availability!.days[6] = DayAvailability(assignments: [DayAssignment(sport: .cycling, minutes: 45)]) }!
        XCTAssertTrue(s.applyPlanChange(id, now: now))
        XCTAssertEqual(s.planVersions.count, 1)
        let u = s.proposeUndo(version: s.planVersions[0].id, now: now)!
        XCTAssertTrue(s.applyPlanChange(u, now: now))
        XCTAssertEqual(s.planVersions.count, 2, "Undo adds a version; nothing is deleted")
        XCTAssertEqual(s.planVersions[1].cause, .undo)
        XCTAssertFalse(s.plan.contains { Store.weekdayIndex($0.date) == 6 && $0.kind.isRide && $0.date >= self.nextMonday })
    }
    func testStaleProposalIsRefused() {
        let s = store(); hybridPersona(s)
        s.plan = PlanEngine.week(starting: nextMonday, profile: s.profile, availability: s.availability!)
        let now = nextMonday.addingTimeInterval(-86_400)
        let id = s.proposePlanChange(cause: .equipment, now: now) { $0.equipment = EquipmentProfile(owned: ["barbell", "bench"]) }!
        guard let target = s.pendingPlanChanges[id]?.before.first, let i = s.plan.firstIndex(where: { $0.id == target.id }) else { return XCTFail("nothing in scope") }
        s.plan[i].done = true
        let snap = s.snapshot
        XCTAssertFalse(s.applyPlanChange(id, now: now)); XCTAssertEqual(s.snapshot, snap)
    }

    // MARK: ENG-D6 — top set and e1RM
    func testAT_D6_TopSetAndE1RM() {
        let squat = Exercise(id: "bb-squat", name: "Back squat", equipment: ["barbell"], pattern: .squat)
        let e = ExerciseEntry(exercise: squat, sets: [SetEntry(reps: 8, weightKg: 60), SetEntry(reps: 6, weightKg: 70), SetEntry(reps: 5, weightKg: 70)])
        let t = StrengthPerformance.topSet(e, date: Date())!
        XCTAssertEqual(t.weightKg, 70); XCTAssertEqual(t.reps, 6)
        XCTAssertEqual(StrengthPerformance.e1RM(weightKg: 80, reps: 5, rpe: 9)!, 80 * 36 / 31, accuracy: 0.01)          // AT-D6-2: 92.9 kg
        XCTAssertNil(StrengthPerformance.e1RM(weightKg: 20, reps: 12, rpe: 8), "r_eff 14 > 10")
        XCTAssertNil(StrengthPerformance.e1RM(weightKg: 80, reps: 5, rpe: nil), "no RPE → no estimate")
        XCTAssertNil(StrengthPerformance.e1RM(weightKg: 80, reps: 5, rpe: 7), "RPE below 8 → no estimate")
        let plank = ExerciseEntry(exercise: Exercise(id: "plank", name: "Plank hold", equipment: ["bodyweight"], pattern: .core), sets: [SetEntry(reps: 40, weightKg: nil, bodyweight: true, rpe: 9)])
        XCTAssertNil(StrengthPerformance.topSet(plank, date: Date()), "bodyweight hold has no loaded top set")
        // AT-D6-4: two qualifying sessions → not enough for a trend
        let logs = [-10, -5].map { d in StrengthSession(date: Date().addingTimeInterval(Double(d) * 86_400), minutes: 40, focus: .lower, rpe: 8, exercises: [ExerciseEntry(exercise: squat, sets: [SetEntry(reps: 5, weightKg: 80, rpe: 9)])]) }
        let l = StrengthPerformance.lifts(logs: logs)[0]
        XCTAssertEqual(l.qualifyingSessions, 2); XCTAssertFalse(l.e1RMTrendAvailable)
    }

    // MARK: ENG-K1 — checkpoints
    func testAT_K1_CheckpointsNeedTimeAndSessions() {
        let first = cal.date(from: DateComponents(year: 2026, month: 11, day: 10))!
        let now1 = cal.date(from: DateComponents(year: 2026, month: 12, day: 7))!
        var c = Checkpoints.compute(sport: .cycling, completed: (0..<6).map { first.addingTimeInterval(Double($0) * 4 * 86_400) }, pausedWeeks: [], performance: .notEnoughData, now: now1, calendar: cal)
        XCTAssertFalse(c[0].reached, "not before 8 Dec"); XCTAssertEqual(cal.component(.day, from: c[0].earliestDate!), 8)
        // AT-K1-2: 5 counted weeks, 3 rides → 1 more ride
        let now2 = first.addingTimeInterval(35 * 86_400)
        c = Checkpoints.compute(sport: .cycling, completed: [0, 10, 20].map { first.addingTimeInterval(Double($0) * 86_400) }, pausedWeeks: [], performance: .improved, now: now2, calendar: cal)
        XCTAssertFalse(c[0].reached); XCTAssertEqual(c[0].missing, "1 more ride"); XCTAssertEqual(c[0].performance, .notEnoughData)
        // AT-K1-3: paused weeks are not counted
        let paused: Set<Date> = [TrainingLedger.monday(of: first.addingTimeInterval(14 * 86_400), calendar: cal), TrainingLedger.monday(of: first.addingTimeInterval(21 * 86_400), calendar: cal)]
        c = Checkpoints.compute(sport: .cycling, completed: (0..<10).map { first.addingTimeInterval(Double($0) * 5 * 86_400) }, pausedWeeks: paused, performance: .flat, now: first.addingTimeInterval(56 * 86_400), calendar: cal)
        XCTAssertEqual(c[0].countedWeeks, 6)
        // AT-K1-5 / K1-6: no FTP evidence → not enough data, never "improved"
        XCTAssertEqual(Checkpoints.cyclingPerformance(ftpEvidence: []), .notEnoughData)
        XCTAssertEqual(Checkpoints.cyclingPerformance(ftpEvidence: [(first, 230)]), .notEnoughData)
        // no completed session yet → the clock hasn't started
        XCTAssertEqual(Checkpoints.compute(sport: .strength, completed: [], pausedWeeks: [], performance: .improved, now: now1, calendar: cal)[0].missing, "Starts with your first completed strength session")
    }

    // MARK: health rework and pause
    func testUnansweredCheckNoLongerCapsAndPauseStopsPlanning() {
        var p = RiderProfile(); p.trainingMode = .cycling; p.level = .advanced; p.goal = .stronger; p.healthScreen = nil
        var a = WeeklyAvailability(days: Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7))
        a.days[1] = DayAvailability(activity: .cycle, minutes: 75); a.days[3] = DayAvailability(activity: .cycle, minutes: 75); a.days[5] = DayAvailability(activity: .cycle, minutes: 150)
        XCTAssertTrue(PlanEngine.week(starting: nextMonday, profile: p, availability: a).contains { $0.kind.zone >= 3 }, "a quality ride without answering the questionnaire")
        p.trainingPause = TrainingPause(since: Date(), reason: .unwell)
        XCTAssertTrue(PlanEngine.week(starting: nextMonday, profile: p, availability: a).allSatisfy { $0.kind == .rest }, "paused → no sessions")
        // saved answers that need a doctor still cap (unchanged rule)
        p.trainingPause = nil; var hs = HealthScreen(); hs.answeredAt = Date(); hs.heartOrBloodPressure = true; p.healthScreen = hs
        XCTAssertFalse(PlanEngine.week(starting: nextMonday, profile: p, availability: a).contains { $0.kind.zone >= 3 })
    }

    // MARK: migration (schema 3) on a build-121-shaped file
    func testMigrationV3KeepsEverythingAndMapsFields() throws {
        let json = """
        {"schema":2,"profile":{"name":"Rider A","goal":"endurance","level":"advanced","ftpW":225,"ftpHow":"assumed","weightKg":75,"trainingMode":"hybrid","liftDaysPerWeek":3,"liftingHoursPerWeek":2,"hoursPerWeek":2,"goals":["aerobicFitness"]},
         "plan":[],"rides":[],"strength":[],"equipment":{"owned":[],"excluded":[]},"strengthPrefs":{}}
        """
        let f0 = try JSONDecoder().decode(StoreFile.self, from: Data(json.utf8))
        XCTAssertEqual(f0.profile.goals, [.endurance]); XCTAssertEqual(f0.profile.legacyGoal, "aerobicFitness", "the merged value is kept")
        let f = StoreFile.migrate(f0)
        XCTAssertEqual(f.schema, 3)
        XCTAssertEqual(f.profile.ftpSource, .unknown); XCTAssertNil(f.profile.ftpValue); XCTAssertEqual(f.profile.ftpW, 225, "value kept as history")
        XCTAssertEqual(f.profile.strengthSessionMinutes, 40, "AT-C2-3: the length the athlete was getting"); XCTAssertEqual(f.profile.confirmSessionLength, true)
        XCTAssertEqual(f.profile.confirmStrengthLevel, true); XCTAssertNil(f.strengthPrefs.experience); XCTAssertEqual(f.profile.level, .advanced)
        XCTAssertTrue(f.equipment.isProvisional)
        XCTAssertEqual(f.profile.name, "Rider A")
        // round trip: nothing lost
        let again = try JSONDecoder().decode(StoreFile.self, from: try JSONEncoder().encode(f))
        XCTAssertEqual(again, f)
        XCTAssertEqual(StoreFile.migrate(f), f, "idempotent")
        // a profile with an entered FTP keeps value and source
        var g = f0; g.profile.ftpHow = .entered; g.profile.ftpW = 260
        XCTAssertEqual(StoreFile.migrate(g).profile.ftpValue, 260)
    }

    func testGoalsKeepLegacyFieldsInStep() {
        let s = store(); s.profile.trainingMode = .hybrid
        let x = s.setGoals([.muscle, .endurance], primary: .muscle)
        XCTAssertEqual(x.profile.primaryGoal, .muscle); XCTAssertEqual(x.strengthPrefs.goal, .hypertrophy); XCTAssertEqual(x.profile.goal, .endurance)
        XCTAssertEqual(GoalID(legacy: "Aerobic fitness"), .endurance)
    }

    // MARK: WP1 — editing changes the real workout; Cancel leaves it identical
    func testPhase1EditRebuildsTheSessionAndCancelLeavesItIdentical() {
        let s = store(); hybridPersona(s)
        s.plan = PlanEngine.week(starting: nextMonday, profile: s.profile, availability: s.availability!)
        s.refreshGeneratedSessions(now: nextMonday.addingTimeInterval(-86_400))
        let mon = s.plan.first { $0.kind == .strength && Store.weekdayIndex($0.date) == 0 }!
        let snap = s.snapshot
        var e = mon; e.strengthFocus = .upper
        XCTAssertEqual(s.edit(e), .needsConfirmation, "a focus change is previewed (requestEdit → .preview)")
        guard let pid = s.lastProposalId else { return XCTFail("no proposal") }
        XCTAssertEqual(s.snapshot, snap, "nothing saved before Apply")
        s.discardProposal(pid)
        XCTAssertEqual(s.snapshot, snap, "Cancel leaves the session identical")
        XCTAssertEqual(s.edit(e), .needsConfirmation)
        guard let pid2 = s.lastProposalId else { return XCTFail("no proposal") }
        XCTAssertEqual(s.commit(proposalId: pid2, confirmed: true), .applied)
        let after = s.plan.first { $0.id == mon.id }!
        XCTAssertEqual(after.strengthFocus, .upper)
        XCTAssertNotEqual(s.plannedEntries(for: after).map(\.exerciseId), s.plannedEntries(for: mon).map(\.exerciseId), "the exercises change, not only the label")
        let lower = s.plannedEntries(for: after).compactMap { e in s.allExercises.first { $0.id == e.exerciseId } }.filter { ExerciseLibrary.meta($0).slot.isLower && ExerciseLibrary.meta($0).compound }
        XCTAssertTrue(lower.isEmpty, "an upper-body session has no compound lower-body lift")
    }

    // MARK: RC3 screens contract (Profile / Plan / Progress use these)
    func testProposeOrApply_NonPlanningChangeSavesDirectly() {
        let s = store(); hybridPersona(s)
        s.plan = PlanEngine.week(starting: nextMonday, profile: s.profile, availability: s.availability!)
        let id = s.proposeOrApplyPlanChange(cause: .profile, now: nextMonday.addingTimeInterval(-86_400)) { $0.profile.name = "Rider B" }
        XCTAssertNil(id, "a name is not a planning input: saved directly, no preview")
        XCTAssertEqual(s.profile.name, "Rider B")
        XCTAssertTrue(s.planVersions.isEmpty)
    }
    func testProposeOrApply_SessionChangeNeedsPreview() {
        let s = store(); hybridPersona(s)
        s.plan = PlanEngine.week(starting: nextMonday, profile: s.profile, availability: s.availability!)
        let before = s.plan
        let id = s.proposeOrApplyPlanChange(cause: .days, now: nextMonday.addingTimeInterval(-86_400)) { x in
            x.availability!.days[1] = DayAvailability(activity: .rest, minutes: 0)
            x.availability!.days[3] = DayAvailability(assignments: [DayAssignment(sport: .cycling, minutes: 60)])
        }
        XCTAssertNotNil(id, "sessions change → preview first")
        XCTAssertEqual(s.plan, before, "nothing changes until Apply")
    }
    func testGlanceShowsUnknownFTP() {
        let g = ProgressGlance.make(.init(riding: [], lifting: [], showRiding: true, showLifting: false, setsThisWeek: 0, ridingTargetMinutes: 120,
                                          ftpW: 0, ftpBadge: "assumed", best20Recent: nil, best20Before: nil))
        let c = g.cards.first { $0.id == "glanceFTP" }
        XCTAssertEqual(c?.value, "Unknown")
        XCTAssertFalse(c?.detail.contains("assumed") ?? true)
    }
}
