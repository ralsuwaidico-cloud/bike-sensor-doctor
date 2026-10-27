import XCTest
@testable import BikeComputer

/// Coach remediation round 2 (third independent review, P3-01 … P3-17): one test per fix, beside QA's own pass-3 probes
/// (IndependentReviewPass3ProbeTests / IndependentReviewPass3Probe2Tests, copied unchanged).
final class CoachRemediationPass3Tests: XCTestCase {
    let cal = Calendar.current
    func at(_ d: Int, _ h: Int = 7) -> Date { cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: Date()))!.addingTimeInterval(TimeInterval(h * 3600)) }
    func store() -> Store { let d = FileManager.default.temporaryDirectory.appendingPathComponent("p3fix-\(UUID().uuidString)"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return Store(directory: d, generatePlan: false) }
    func screen(_ f: (inout HealthScreen) -> Void = { _ in }, answered: Date = Date()) -> HealthScreen { var s = HealthScreen(); s.answeredAt = answered; f(&s); return s }
    var nextMonday: Date { let t = cal.startOfDay(for: Date()); let wd = (cal.component(.weekday, from: t) + 5) % 7; return cal.date(byAdding: .day, value: 7 - wd, to: t)! }

    // P3-01: an edit drops the safety original; the stop path stores the edit, and the edit comes back
    func testEditDropsSafetyOriginalAndPauseRestoresTheEdit() {
        let s = store(); var p = RiderProfile(); p.trainingMode = .cycling; s.profile = p
        s.plan = [Workout(date: at(2), kind: .threshold, minutes: 70)]
        s.refreshRideSafety()
        XCTAssertNotNil(s.plan[0].safetyOriginal)
        var e = s.plan[0]; e.kind = .recovery; e.minutes = 30; s.edit(e)
        XCTAssertNil(s.plan[0].safetyOriginal, "an edit replaces the safety original")
        // even with a stale original (e.g. a snapshot restored by Undo), the stop path keeps the edit
        s.plan[0].safetyOriginal = SafetyOriginal(kind: .threshold, minutes: 70, intervalReps: 3, note: "")
        s.profile.healthScreen = screen { $0.chestPain = true }
        s.refreshRideSafety()
        XCTAssertEqual(s.plan[0].kind, .rest)
        XCTAssertEqual(s.plan[0].safetyOriginal?.kind, .recovery)
        s.profile.healthScreen = screen { $0.heartOrBloodPressure = true }
        s.refreshRideSafety()
        XCTAssertEqual(s.plan[0].kind, .recovery); XCTAssertEqual(s.plan[0].minutes, 30)
    }

    // P3-02: a clearance covers only the answers it was confirmed for; symptoms need a clearance dated on/after them
    func testClearanceDoesNotCarryOverToNewAnswers() {
        var h = screen({ $0.heartOrBloodPressure = true; $0.clearedAt = self.at(-30) }, answered: at(-10))
        XCTAssertEqual(h.status, .cleared, "a known condition cleared by a doctor before the answers")
        // the rider re-answers with new chest pain; the form keeps the old clearance (worst case): not cleared
        h.chestPain = true; h.answeredAt = Date(); h.conditionsChangedAt = Date()
        XCTAssertEqual(h.status, .stop)
        // confirmed again, but the clearance predates the symptom → still stop
        h.clearanceConfirmedAt = Date()
        XCTAssertEqual(h.status, .stop)
        // a clearance from a check on/after the symptom day counts
        h.clearedAt = Date()
        XCTAssertEqual(h.status, .cleared)
        // a clearance confirmed BEFORE the answers last changed never counts
        var k = screen({ $0.boneJointProblem = true; $0.clearedAt = self.at(-5) })
        k.clearanceConfirmedAt = at(-5); k.conditionsChangedAt = at(-1)
        XCTAssertEqual(k.status, .needsClearance)
        XCTAssertEqual(screen { $0.boneJointProblem = true; $0.chestPain = false }.conditionKeys, ["bone"])
    }

    // P3-17: a clearance dated after the answers is not accepted
    func testFutureClearanceIsNotAccepted() {
        XCTAssertEqual(screen { $0.heartOrBloodPressure = true; $0.clearedAt = self.at(30) }.status, .needsClearance)
        XCTAssertEqual(screen { $0.chestPain = true; $0.clearedAt = self.at(30) }.status, .stop)
    }

    // P3-09: an operation needs a clearance (not an illness pause); an illness pause never expires into training
    func testOperationNeedsClearanceAndIllnessPauseDoesNotExpire() {
        let op = screen { $0.recentOperation = true }
        XCTAssertEqual(op.status, .needsClearance)
        XCTAssertTrue(op.clearable)
        XCTAssertFalse(CoachReadiness(screen: op.status).vigorousAllowed)
        XCTAssertEqual(screen({ $0.currentIllness = true }, answered: at(-400)).status, .paused)
        XCTAssertEqual(HealthScreen.currentQuestionSet, 3)
        var old = screen(); old.questionSet = 2
        XCTAssertEqual(old.status, .notAnswered, "answers to the older question set are asked again")
    }

    // P3-05: stop / pause covers other activities and mobility; they come back afterwards
    func testStopPausesEverySessionKindAndRestores() {
        let s = store(); var p = RiderProfile(); p.trainingMode = .hybrid; p.healthScreen = screen(); s.profile = p
        s.plan = [Workout(date: at(2), kind: .other, minutes: 60), Workout(date: at(3), kind: .mobility, minutes: 30)]
        s.profile.healthScreen = screen { $0.currentIllness = true }
        s.refreshRideSafety()
        XCTAssertEqual(s.plan.map { $0.kind }, [.rest, .rest])
        s.profile.healthScreen = screen()
        s.refreshRideSafety()
        XCTAssertEqual(s.plan.map { $0.kind }, [.other, .mobility]); XCTAssertEqual(s.plan.map { $0.minutes }, [60, 30])
    }

    // P3-08: an edited hard ride keeps the rider's version but carries the caution while clearance is pending
    func testEditedHardRideGetsCautionAndLosesItWhenCleared() {
        let s = store(); var p = RiderProfile(); p.trainingMode = .cycling; p.healthScreen = screen(); s.profile = p
        var r = Workout(date: at(2), kind: .vo2, minutes: 60); r.edited = true; r.note = "with Sam"; s.plan = [r]
        s.profile.healthScreen = screen { $0.heartOrBloodPressure = true }
        s.refreshRideSafety()
        XCTAssertEqual(s.plan[0].kind, .vo2)
        XCTAssertTrue(s.plan[0].note.hasPrefix("Caution: "), s.plan[0].note)
        XCTAssertTrue(s.plan[0].note.hasSuffix("with Sam"))
        s.refreshRideSafety()
        XCTAssertEqual(s.plan[0].note.components(separatedBy: "Caution:").count, 2, "the caution is not repeated")
        s.profile.healthScreen = screen()
        s.refreshRideSafety()
        XCTAssertEqual(s.plan[0].note, "with Sam")
    }

    // P3-10: an old report with nothing logged since is not called "lasted / come back"; an ongoing one is
    func testPersistentOnlyWhenOngoingOrRecurring() {
        var p = RiderProfile(); p.trainingMode = .cycling; p.healthScreen = screen()
        func ride(_ d: Int, _ pain: PainLevel) -> RideRecord { var r = RideRecord(start: at(d), durationS: 3600, distanceM: 25000, recorder: .phone, sources: []); r.checkIn = CheckIn(performance: 6, effort: 6, pain: pain, painArea: pain.needsArea ? .knees : nil, at: r.start); return r }
        func analyze(_ rides: [RideRecord]) -> TrainingAnalysis { TrainingAnalyzer.analyze(AdaptationInput(profile: p, plan: [], rides: rides, strength: [], availability: WeeklyAvailability.suggested(for: p), now: Date(), calendar: cal)) }
        let alone = analyze([ride(-60, .concerning)])
        XCTAssertEqual(alone.painAreas, [.knees]); XCTAssertTrue(alone.painPersistent.isEmpty)
        let ongoing = analyze([ride(-30, .concerning), ride(-20, .discomfort), ride(-10, .noPain)])
        XCTAssertEqual(ongoing.painPersistent, [.knees])
    }

    // P3-13: concerning knee pain also trims the long ride (bounded, automatic, fixed/edited untouched)
    func testConcerningLegPainTrimsTheLongRide() {
        var p = RiderProfile(); p.trainingMode = .cycling; p.healthScreen = screen()
        var rides = (1...4).map { k -> RideRecord in var r = RideRecord(start: at(-k * 2), durationS: 3600, distanceM: 25000, recorder: .phone, sources: []); r.checkIn = CheckIn(performance: 7, effort: 6, at: r.start); return r }
        rides[0].checkIn = CheckIn(performance: 5, effort: 6, pain: .concerning, painArea: .knees, at: rides[0].start)
        let long = Workout(date: at(3), kind: .long, minutes: 180)
        var fixedLong = Workout(date: at(4), kind: .long, minutes: 150); fixedLong.fixed = true
        let r = AdaptationEngine.run(AdaptationInput(profile: p, plan: [long, fixedLong], rides: rides, strength: [], availability: WeeklyAvailability.suggested(for: p), now: Date(), calendar: cal))
        XCTAssertTrue(r.adjustments.contains { $0.workoutId == long.id && $0.change == .minutes(delta: -20) }, r.adjustments.map { $0.summary }.joined(separator: "; "))
        XCTAssertFalse(r.adjustments.contains { $0.workoutId == fixedLong.id })
    }

    // P3-14: a flexible typed threshold day follows a fitness goal (tempo, with a note); a fixed one is kept
    func testLegacyTypedDaysFollowTheGoal() {
        var p = RiderProfile(); p.trainingMode = .cycling; p.level = .intermediate; p.goal = .fitness; p.hoursPerWeek = 7; p.cyclingDaysPerWeek = 3; p.healthScreen = screen()
        var a = WeeklyAvailability(days: Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7))
        a.days[2] = DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: .threshold, minutes: 90)])
        a.days[4] = DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: .intervals, minutes: 60, fixed: true)])
        a.days[6] = DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: .long, minutes: 150)])
        let w = PlanEngine.week(starting: nextMonday, profile: p, availability: a, trainingWeeks: 0)
        let wed = w.first { cal.isDate($0.date, inSameDayAs: cal.date(byAdding: .day, value: 2, to: nextMonday)!) }
        let fri = w.first { cal.isDate($0.date, inSameDayAs: cal.date(byAdding: .day, value: 4, to: nextMonday)!) }
        XCTAssertEqual(wed?.kind, .tempo); XCTAssertTrue(wed?.note.contains("mark it as fixed") ?? false, wed?.note ?? "")
        XCTAssertEqual(fri?.kind, .vo2, "a fixed day is never changed")
        p.goal = .stronger
        let w2 = PlanEngine.week(starting: nextMonday, profile: p, availability: a, trainingWeeks: 0)
        XCTAssertEqual(w2.first { cal.isDate($0.date, inSameDayAs: cal.date(byAdding: .day, value: 2, to: nextMonday)!) }?.kind, .threshold)
    }

    // P3-07: the routine break reduction keys on a structured marker, not on note text; it is dropped once logged again
    func testReturnMarkerInsteadOfNoteText() {
        let s = store(); var p = RiderProfile(); p.trainingMode = .strength; p.healthScreen = screen(); s.profile = p
        let sq = Exercise(id: "q3", name: "Back squat", equipment: ["barbell"], pattern: .squat, unilateral: false, custom: true)
        s.customExercises = [sq]; s.equipment = EquipmentProfile(owned: ["barbell"])
        s.strength = [StrengthSession(date: at(-40, 18), minutes: 45, focus: .lower, rpe: 7, exercises: [ExerciseEntry(exercise: sq, sets: (0..<3).map { _ in SetEntry(reps: 5, weightKg: 100, rpe: 7, done: true) })])]
        var e = ExerciseEntry(exercise: sq, sets: (0..<3).map { _ in SetEntry(reps: 5, weightKg: 100) }); e.notes = "Back after warm-up: knees out"
        var w = Workout(date: at(1), kind: .strength, minutes: 45, strengthFocus: .lower); w.plannedEntries = [e]; w.generatedEntries = false
        let shown = s.returnAdjusted([e], for: w)
        XCTAssertLessThan(shown[0].sets[0].weightKg ?? 100, 100)
        XCTAssertNotNil(shown[0].returnMark)
        XCTAssertEqual(s.returnAdjusted(shown, for: w)[0].sets[0].weightKg, shown[0].sets[0].weightKg, "not reduced twice")
        // logged again after the mark: the marker and its note are dropped, no new reduction (no break)
        s.strength.append(StrengthSession(date: Date().addingTimeInterval(60), minutes: 45, focus: .lower, rpe: 7, exercises: [ExerciseEntry(exercise: sq, sets: (0..<3).map { _ in SetEntry(reps: 5, weightKg: 90, rpe: 7, done: true) })]))
        let later = s.returnAdjusted(shown, for: w, now: Date().addingTimeInterval(120))
        XCTAssertNil(later[0].returnMark); XCTAssertEqual(later[0].notes, "Back after warm-up: knees out")
    }

    // P3-12: the definitions no longer overlap ("next day" is about joint pain only)
    func testPainDefinitionsDoNotOverlap() {
        XCTAssertTrue(painDefinition(.soreness).contains("not in a joint"))
        XCTAssertTrue(painDefinition(.concerning).contains("joint pain still there the next day"))
    }
}
