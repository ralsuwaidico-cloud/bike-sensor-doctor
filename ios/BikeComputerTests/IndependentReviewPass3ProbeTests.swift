// Copied unchanged from the third independent review pass (3e801a0, /home/claude/coach-review/pass3): assertions encode what a
// correct coach should do; the failing ones are findings P3-01..P3-07 and are kept as regression tests.
import XCTest
@testable import BikeComputer

/// Third-pass independent review probes (3e801a0). Assertions encode what a correct coach should do: FAIL = finding.
/// Tests named ...Info only print behaviour (no assertion) for the report.
final class Pass3ProbeTests: XCTestCase {
    let cal = Calendar.current
    var today: Date { cal.startOfDay(for: Date()) }
    var thisMonday: Date { let wd = (cal.component(.weekday, from: today) + 5) % 7; return cal.date(byAdding: .day, value: -wd, to: today)! }
    var nextMonday: Date { cal.date(byAdding: .day, value: 7, to: thisMonday)! }
    func at(_ d: Int, _ h: Int = 7, from base: Date? = nil) -> Date { cal.date(byAdding: .day, value: d, to: cal.startOfDay(for: base ?? Date()))!.addingTimeInterval(TimeInterval(h * 3600)) }
    func store() -> Store { let d = FileManager.default.temporaryDirectory.appendingPathComponent("p3-\(UUID().uuidString)"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return Store(directory: d, generatePlan: false) }
    func screen(_ f: (inout HealthScreen) -> Void = { _ in }, answered: Date = Date()) -> HealthScreen { var s = HealthScreen(); s.answeredAt = answered; f(&s); return s }
    func desc(_ w: [Workout]) -> String { w.filter { $0.kind != .rest }.sorted { $0.date < $1.date }.map { "\($0.date.shortDay):\($0.kind.rawValue)\($0.minutes)\($0.effectiveIntervalReps.map { "x\($0)" } ?? "")" }.joined(separator: " ") }
    let squat = Exercise(id: "q", name: "Back squat", equipment: ["barbell"], pattern: .squat, muscles: ["quads", "glutes"], unilateral: false, custom: true)
    func log(_ date: Date, kg: Double, reps: Int, rpe: Int = 8) -> StrengthSession { StrengthSession(date: date, minutes: 45, focus: .fullBody, rpe: rpe, exercises: [ExerciseEntry(exercise: squat, sets: (0..<3).map { _ in SetEntry(reps: reps, weightKg: kg, rpe: rpe, done: true) })]) }

    // S1: a clearance recorded earlier (for a heart condition) is carried over by the health-check form when the rider
    // re-answers with NEW chest pain (HealthCheckView.onAppear keeps clearanceConfirmed/clearedOn; draft keeps clearedAt).
    func testS1_PriorClearanceCoversNewChestPain() {
        let before = screen({ $0.heartOrBloodPressure = true; $0.clearedAt = self.at(-60) }, answered: at(-60))
        XCTAssertEqual(before.status, .cleared)
        // what HealthCheckView saves when the rider only flips "chest pain" to Yes (toggle and date pre-filled from before)
        var draft = HealthScreen(); draft.heartOrBloodPressure = true; draft.chestPain = true
        draft.clearedAt = (before.clearedAt != nil && draft.clearable) ? before.clearedAt : nil
        draft.answeredAt = Date()
        let r = CoachReadiness(screen: draft.status)
        print("S1 new chest pain, clearance dated 60 d earlier carried over -> \(draft.status) vigorous=\(r.vigorousAllowed)")
        XCTAssertEqual(draft.status, .stop, "S1: new chest pain is 'cleared' by a clearance that predates it -> vigorous training")
    }
    // S1b: clearance window (N-08 fix): any clearance up to 12 months BEFORE the answers counts for current chest pain
    func testS1b_ClearanceWindowInfo() {
        for d in [-1, -30, -200, -364, -366] {
            let s = screen({ $0.chestPain = true; $0.clearedAt = self.at(d) })
            print("S1b chest pain today, clearance dated \(d) d -> \(s.status)")
        }
    }

    // S2: N-01 via the stop/pause path. Capped ride, rider edits it (no refresh in between: Store.edit does not clear
    // safetyOriginal), then the health check pauses training and later allows it again (needs clearance).
    func testS2_StaleSafetyOriginalRestoredOverEditViaPause() {
        let s = store(); var p = RiderProfile(); p.trainingMode = .cycling; s.profile = p           // not answered
        s.plan = [Workout(date: at(2), kind: .threshold, minutes: 70)]
        s.refreshRideSafety()
        print("S2 capped:", desc(s.plan), "SO:", s.plan[0].safetyOriginal?.kind.rawValue ?? "nil")
        var e = s.plan[0]; e.kind = .recovery; e.minutes = 30; s.edit(e)                          // rider edits it
        s.profile.healthScreen = screen { $0.currentIllness = true }                                  // ill -> paused
        s.refreshRideSafety()
        print("S2 paused:", s.plan.map { "\($0.kind.rawValue)\($0.minutes) SO:\($0.safetyOriginal.map { "\($0.kind.rawValue)\($0.minutes)" } ?? "nil")" })
        s.profile.healthScreen = screen { $0.heartOrBloodPressure = true }                           // well again, needs clearance
        s.refreshRideSafety()
        print("S2 after pause, needsClearance:", desc(s.plan), "edited:", s.plan[0].edited)
        XCTAssertEqual(s.plan[0].kind, .recovery, "S2: the rider's edit is replaced by the stale uncapped original (\(desc(s.plan))) for a rider who needs clearance")
        XCTAssertEqual(s.plan[0].minutes, 30)
    }

    // S3: N-02 on the return-after-break path: the rep floor (>= 8 until cleared) is applied with only the break factor
    func testS3_BreakPathRepFloorHarderThanNoBreak() {
        var p = RiderProfile(); p.trainingMode = .strength; p.level = .intermediate               // health check not answered
        var prefs = StrengthPrefs(); prefs.goal = .strength
        func prescribe(_ days: [Int]) -> StrengthPlanner.Load {
            let c = PlannerContext(profile: p, prefs: prefs, equipment: EquipmentProfile(owned: ["barbell"]), catalogue: [squat], logs: days.map { log(at($0, 18), kg: 100, reps: 5, rpe: 8) }, now: Date(), calendar: cal)
            var reps = StrengthPlanner.dose(role: .main, goal: .strength, experience: .intermediate).reps
            if let lo = c.readiness.minStrengthReps, reps.lowerBound < lo { reps = lo...max(lo + 4, reps.upperBound) }
            return StrengthPlanner.prescribeLoad(squat, meta: ExerciseLibrary.meta(squat), reps: reps, sets: 3, painBlocked: false, ctx: c)
        }
        let recent = prescribe([-3, -6]), afterBreak = prescribe([-22, -25])
        print("S3 last 3x5 @100 kg RPE 8. No break: \(recent.weight ?? -1) kg x \(recent.reps). After 22 d off: \(afterBreak.weight ?? -1) kg x \(afterBreak.reps) | \(afterBreak.why)")
        // Epley: 100 kg x5 @ RPE 8 (2 in reserve) ~ 123 kg e1RM; 95 kg x 8 ~ 120 kg e1RM -> ~RPE 9-10, above the RPE 7 cap
        XCTAssertLessThanOrEqual(afterBreak.weight ?? 0, recent.weight ?? 0, "S3: after a break the not-cleared lifter gets a HEAVIER set (\(afterBreak.weight ?? 0) kg x \(afterBreak.reps)) than without a break (\(recent.weight ?? 0) kg x \(recent.reps))")
    }

    // S4: a "pain is gone" confirmation made earlier the same day swallows a NEW concerning report from a session that
    // started before the confirmation (comparison is clearance.at > session START date)
    func testS4_ClearanceSwallowsLaterReportOfEarlierStartedSession() {
        var p = RiderProfile(); p.trainingMode = .cycling; p.healthScreen = screen()
        let now = Date()
        var old = RideRecord(start: now.addingTimeInterval(-10 * 86_400), durationS: 3600, distanceM: 25000, recorder: .phone, sources: [])
        old.checkIn = CheckIn(performance: 5, effort: 6, pain: .concerning, painArea: .knees, at: old.start)
        var ride = RideRecord(start: now.addingTimeInterval(-2 * 3600), durationS: 5400, distanceM: 40000, recorder: .phone, sources: [])
        ride.checkIn = CheckIn(performance: 4, effort: 7, pain: .concerning, painArea: .knees, at: now)   // new pain, reported after the ride
        let input = AdaptationInput(profile: p, plan: [], rides: [old, ride], strength: [], availability: WeeklyAvailability.suggested(for: p), now: now, calendar: cal,
                                    painClearances: [PainClearance(area: .knees, at: now.addingTimeInterval(-3600))])   // "it's fine now" before the ride ended
        let a = TrainingAnalyzer.analyze(input)
        print("S4 knee cleared 1 h ago, ride started 2 h ago with NEW concerning knee pain -> held \(a.painAreas)")
        XCTAssertTrue(a.painAreas.contains(.knees), "S4: a new concerning report is silently released by an earlier confirmation")
    }

    // S5: sessions already generated, health check then says "see a doctor": other activities and mobility stay planned
    func testS5_OtherSessionsStayPlannedDuringStop() {
        let s = store(); var p = RiderProfile(); p.trainingMode = .hybrid; p.healthScreen = screen { $0.chestPain = true }; s.profile = p
        s.plan = [Workout(date: at(2), kind: .other, minutes: 60), Workout(date: at(3), kind: .mobility, minutes: 30), Workout(date: at(4), kind: .endurance, minutes: 60)]
        s.refreshRideSafety()
        print("S5 stop, already generated:", s.plan.map { "\($0.kind.rawValue)\($0.minutes)" })
        XCTAssertTrue(s.plan.allSatisfy { $0.kind == .rest || $0.kind == .mobility }, "S5: a generated 'other activity' (run/swim/hike, 60 min) stays planned while the check says see a doctor")
        let w = PlanEngine.week(starting: nextMonday, profile: p, availability: WeeklyAvailability.suggested(for: p))
        print("S5 stop, new week:", desc(w))
    }

    // S6: illness pause: week builder, refresh of already generated sessions, restore afterwards
    func testS6_IllnessPause() {
        let s = store(); var p = RiderProfile(); p.trainingMode = .hybrid; p.level = .intermediate; p.goal = .stronger; p.hoursPerWeek = 8; p.liftingHoursPerWeek = 2; p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 2
        p.healthScreen = screen(); s.profile = p
        var lift = Workout(date: at(2, 18), kind: .strength, minutes: 45, strengthFocus: .lower); lift.plannedEntries = [ExerciseEntry(exercise: squat, sets: [SetEntry(reps: 5, weightKg: 100)])]; lift.generatedEntries = true
        var editedRide = Workout(date: at(3), kind: .tempo, minutes: 50); editedRide.edited = true
        s.plan = [lift, editedRide, Workout(date: at(4), kind: .threshold, minutes: 70)]
        s.profile.healthScreen = screen { $0.currentIllness = true }
        XCTAssertEqual(s.profile.readiness.screen, .paused)
        s.refreshRideSafety()
        print("S6 paused:", s.plan.map { "\($0.kind.rawValue)\($0.minutes)" })
        XCTAssertTrue(s.plan.allSatisfy { $0.kind == .rest })
        let w = PlanEngine.week(starting: nextMonday, profile: s.profile, availability: WeeklyAvailability.suggested(for: s.profile))
        XCTAssertEqual(desc(w), "", "S6: the week builder plans sessions during an illness pause")
        s.profile.healthScreen = screen()
        s.refreshRideSafety()
        print("S6 recovered:", s.plan.map { "\($0.kind.rawValue)\($0.minutes) entries:\($0.plannedEntries?.count ?? 0)" })
        XCTAssertEqual(s.plan.map { $0.kind }, [.strength, .tempo, .threshold]); XCTAssertEqual(s.plan[1].minutes, 50); XCTAssertEqual(s.plan[0].plannedEntries?.first?.sets.first?.weightKg, 100)
        // an old pause
        let oldPause = screen({ $0.currentIllness = true }, answered: at(-370))
        print("S6 illness answer 370 d old ->", oldPause.status)
    }

    // S7: status table for expired / old-set answers (informational)
    func testS7_ExpiryTableInfo() {
        let old = at(-400)
        let cases: [(String, HealthScreen)] = [
            ("chest pain, no clearance, 400 d", screen({ $0.chestPain = true }, answered: old)),
            ("chest pain + clearance at answer, 400 d", screen({ $0.chestPain = true; $0.clearedAt = old }, answered: old)),
            ("supervised only, 400 d", screen({ $0.supervisedOnly = true }, answered: old)),
            ("heart condition + clearance, 400 d", screen({ $0.heartOrBloodPressure = true; $0.clearedAt = old }, answered: old)),
            ("dizziness, question set 1, today", screen({ $0.dizzinessOrFainting = true; $0.questionSet = 1 })),
            ("bone/joint only, today", screen({ $0.boneJointProblem = true })),
            ("pregnancy only, today", screen({ $0.pregnancy = true })),
            ("clearance in the future (+30 d)", screen({ $0.chestPain = true; $0.clearedAt = self.at(30) })),
        ]
        for (n, s) in cases { print("S7 \(n) -> \(s.status)") }
    }

    // S8: the N-03 fix keys on the text "Back after" in the entry note: a rider's own note containing it disables the
    // break reduction for that exercise
    func testS8_RiderNoteDisablesBreakReduction() {
        let s = store(); var p = RiderProfile(); p.trainingMode = .strength; p.healthScreen = screen(); s.profile = p
        s.customExercises = [squat]; s.equipment = EquipmentProfile(owned: ["barbell"])
        var entry = ExerciseEntry(exercise: squat, sets: (0..<3).map { _ in SetEntry(reps: 5, weightKg: 100) }); entry.notes = "Back after warm-up: check knee tracking"
        let t = WorkoutTemplate(name: "Legs", focus: .lower, entries: [entry], updatedAt: Date(timeIntervalSince1970: 0))
        s.templates = [t]
        s.strength = [-60, -62, -64].map { d in var l = log(at(d, 18), kg: 100, reps: 5, rpe: 7); l.templateId = t.id; return l }
        var w = Workout(date: at(1), kind: .strength, minutes: 45, strengthFocus: .lower); w.templateId = t.id; w.plannedEntries = [entry]; w.generatedEntries = false
        s.plan = [w]
        let shown = s.plannedEntries(for: s.plan[0])
        print("S8 60 d off, routine note contains 'Back after':", shown.map { "\($0.sets.first?.weightKg ?? 0) | \($0.notes)" })
        XCTAssertLessThan(shown.first?.sets.first?.weightKg ?? 100, 100, "S8: no break reduction because the rider's note contains 'Back after'")
    }

    // S9: the engine's readiness gate (N-04 fix) reads the device clock, not input.now
    func testS9_EngineReadinessUsesDeviceClock() {
        let later = Date().addingTimeInterval(400 * 86_400)                                         // answers expired at input.now
        var p = RiderProfile(); p.trainingMode = .strength; p.healthScreen = screen()               // clear by device clock
        let t = WorkoutTemplate(name: "Legs", focus: .lower, entries: [ExerciseEntry(exercise: squat, sets: (0..<3).map { _ in SetEntry(reps: 8, weightKg: 60) })], updatedAt: Date(timeIntervalSince1970: 0))
        var w = Workout(date: at(2, 18, from: later), kind: .strength, minutes: 45, strengthFocus: .lower); w.templateId = t.id
        var logs = [log(at(-3, 18, from: later), kg: 60, reps: 8, rpe: 7), log(at(-6, 18, from: later), kg: 60, reps: 8, rpe: 7)]
        for i in logs.indices { logs[i].templateId = t.id; logs[i].checkIn = CheckIn(performance: 7, effort: 6, at: logs[i].date) }
        let r = AdaptationEngine.run(AdaptationInput(profile: p, plan: [w], rides: [], strength: logs, availability: WeeklyAvailability.suggested(for: p), equipment: EquipmentProfile(owned: ["barbell"]), catalogue: [squat], templates: [t], originalEntries: [w.id: t.prefilled(from: logs.first)], now: later, calendar: cal))
        print("S9 status at input.now:", CoachReadiness(profile: p, now: later).screen, "adjustments:", r.adjustments.map { $0.summary })
        XCTAssertFalse(r.adjustments.contains { $0.category == .progression }, "S9: engine progresses although the health check has expired at input.now")
    }

    // S10: answers saved by 02d8795 with a stop answer decode and stay 'stop'
    func testS10_OldStopAnswersDecode() throws {
        let json = #"{"name":"x","healthScreen":{"answeredAt":800000000,"heartOrBloodPressure":false,"chestPain":true,"dizzinessOrFainting":false,"otherChronicCondition":false,"chronicMedication":false,"boneJointProblem":false,"supervisedOnly":false,"pregnancy":false}}"#
        let p = try JSONDecoder().decode(RiderProfile.self, from: Data(json.utf8))
        print("S10 old chest-pain answers ->", p.readiness.screen)
        XCTAssertEqual(p.readiness.screen, .stop)
        let garbage = #"{"name":"x","healthScreen":{"answeredAt":"not a date","chestPain":"yes"}}"#
        let g = try? JSONDecoder().decode(RiderProfile.self, from: Data(garbage.utf8))
        print("S10 malformed answers ->", g.map { "\($0.readiness.screen)" } ?? "profile failed to decode")
    }

    // S11: a ride the rider edited to threshold stays threshold (no cap, no caution note) once clearance is needed
    func testS11_EditedHardRideNotCautionedInfo() {
        let s = store(); var p = RiderProfile(); p.trainingMode = .cycling; p.healthScreen = screen(); s.profile = p
        var r = Workout(date: at(2), kind: .vo2, minutes: 60); r.edited = true; s.plan = [r]
        s.profile.healthScreen = screen { $0.heartOrBloodPressure = true }
        s.refreshRideSafety()
        print("S11 edited VO2 ride, needs clearance ->", s.plan.map { "\($0.kind.rawValue)\($0.minutes) note:'\($0.note)'" })
    }

    // S12: N-11: generation-time return cap stores the block's threshold reps
    func testS12_ReturnCapKeepsBlockRepsInfo() {
        var p = RiderProfile(); p.trainingMode = .cycling; p.level = .intermediate; p.goal = .stronger; p.hoursPerWeek = 9; p.cyclingDaysPerWeek = 4; p.healthScreen = screen()
        let w = PlanEngine.week(starting: nextMonday, profile: p, availability: WeeklyAvailability.suggested(for: p), returning: ReturnPhase(breakDays: 30, sessionsSince: 0, ongoing: true), trainingWeeks: 2)
        print("S12 return week, block pos 2:", desc(w), "| SO:", w.compactMap { $0.safetyOriginal.map { "\($0.kind.rawValue)\($0.minutes)x\($0.intervalReps ?? -1)" } })
    }

    // S13: discomfort vs concerning (regression of the three levels)
    func testS13_ThreeLevels() {
        var p = RiderProfile(); p.trainingMode = .hybrid; p.healthScreen = screen()
        func analyze(_ level: PainLevel, daysAgo: Int, later: [PainLevel]) -> TrainingAnalysis {
            var first = log(at(-daysAgo, 18), kg: 60, reps: 8); first.checkIn = CheckIn(performance: 6, effort: 7, pain: level, painArea: .knees, at: first.date)
            var xs = [first]
            for (i, l) in later.enumerated() { var x = log(at(-daysAgo + 2 * (i + 1), 18), kg: 60, reps: 8); x.checkIn = CheckIn(performance: 7, effort: 6, pain: l, painArea: l.needsArea ? .knees : nil, at: x.date); xs.append(x) }
            return TrainingAnalyzer.analyze(AdaptationInput(profile: p, plan: [], rides: [], strength: xs, availability: WeeklyAvailability.suggested(for: p), now: Date(), calendar: cal))
        }
        let sore = analyze(.soreness, daysAgo: 1, later: [])
        let disc = analyze(.discomfort, daysAgo: 3, later: [])
        let discGone = analyze(.discomfort, daysAgo: 5, later: [.noPain])
        let conc90 = analyze(.concerning, daysAgo: 90, later: [])
        let conc30Free = analyze(.concerning, daysAgo: 30, later: [.noPain, .soreness, .noPain])
        print("S13 soreness: held \(sore.painAreas) disc \(sore.discomfortAreas)")
        print("S13 discomfort: disc \(disc.discomfortAreas); after a pain-free session: \(discGone.discomfortAreas)")
        print("S13 concerning 90 d ago, nothing since: held \(conc90.painAreas) persistent \(conc90.painPersistent)")
        print("S13 concerning 30 d ago + 3 pain-free: held \(conc30Free.painAreas) reviewDue \(conc30Free.painReviewDue) persistent \(conc30Free.painPersistent)")
        XCTAssertTrue(sore.painAreas.isEmpty && sore.discomfortAreas.isEmpty)
        XCTAssertEqual(disc.discomfortAreas, [.knees]); XCTAssertTrue(discGone.discomfortAreas.isEmpty)
        XCTAssertEqual(conc90.painAreas, [.knees]); XCTAssertEqual(conc30Free.painAreas, [.knees], "concerning pain is never auto-released")
        XCTAssertEqual(conc30Free.painReviewDue, [.knees])
    }
}
