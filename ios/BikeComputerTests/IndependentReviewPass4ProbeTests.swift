// Copied unchanged from the fourth independent review pass (0d9fc24, /home/claude/coach-review/pass4): assertions encode what a
// correct coach should do; U1 (P4-01) and U2 (P4-02) were the failing findings and are kept as regression tests.
// One change: U2 mirrors HomeView's alternative pick, which now calls store.edit instead of store.update (the P4-02 fix).
import XCTest
@testable import BikeComputer

/// Fourth-pass independent review probes (0d9fc24). Assertions encode what a correct coach should do: FAIL = finding.
/// Tests named ...Info only print behaviour for the report.
final class Pass4ProbeTests: XCTestCase {
    let cal = Calendar.current
    var today: Date { cal.startOfDay(for: Date()) }
    var nextMonday: Date { let wd = (cal.component(.weekday, from: today) + 5) % 7; return cal.date(byAdding: .day, value: 7 - wd, to: today)! }
    func at(_ d: Int, _ h: Int = 7) -> Date { cal.date(byAdding: .day, value: d, to: today)!.addingTimeInterval(TimeInterval(h * 3600)) }
    func store() -> Store { let d = FileManager.default.temporaryDirectory.appendingPathComponent("p4-\(UUID().uuidString)"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return Store(directory: d, generatePlan: false) }
    func screen(_ f: (inout HealthScreen) -> Void = { _ in }, answered: Date = Date()) -> HealthScreen { var s = HealthScreen(); s.answeredAt = answered; f(&s); return s }
    func desc(_ w: [Workout]) -> String { w.sorted { $0.date < $1.date }.map { "\($0.kind.rawValue)\($0.minutes)\($0.effectiveIntervalReps.map { "x\($0)" } ?? "")" }.joined(separator: " ") }
    let squat = Exercise(id: "q", name: "Back squat", equipment: ["barbell"], pattern: .squat, muscles: ["quads", "glutes"], unilateral: false, custom: true)
    let db = Exercise(id: "d", name: "DB press", equipment: ["dumbbell"], pattern: .push, muscles: ["chest"], unilateral: false, custom: true)
    func log(_ ex: Exercise, _ date: Date, kg: Double, reps: Int, rpe: Int) -> StrengthSession { StrengthSession(date: date, minutes: 45, focus: .fullBody, rpe: rpe, exercises: [ExerciseEntry(exercise: ex, sets: (0..<3).map { _ in SetEntry(reps: reps, weightKg: kg, rpe: rpe, done: true) })]) }

    // U1: the rider edits a capped ride to REST. markRiderEdited keeps safetyOriginal for kind == .rest, so the refresh
    // cannot tell the rider's rest from a health-check pause and restores the stale uncapped ride over the edit.
    func testU1_EditCappedRideToRestIsOverwritten() {
        let s = store(); var p = RiderProfile(); p.trainingMode = .cycling; s.profile = p              // not answered
        s.plan = [Workout(date: at(2), kind: .threshold, minutes: 70)]
        s.refreshRideSafety()
        print("U1 capped:", desc(s.plan), "SO:", s.plan[0].safetyOriginal?.kind.rawValue ?? "nil")
        var e = s.plan[0]; e.kind = .rest; e.minutes = 0; s.edit(e)                                     // PlanView editor: Type = Rest, Save
        print("U1 after edit:", desc(s.plan), "SO:", s.plan[0].safetyOriginal?.kind.rawValue ?? "nil")
        s.refreshRideSafety()
        print("U1 after refresh:", desc(s.plan), "edited:", s.plan[0].edited)
        XCTAssertEqual(s.plan[0].kind, .rest, "U1: the rider's Rest edit is replaced by \(desc(s.plan)) (uncapped, not-cleared rider)")
    }
    // U2: Home 'alternatives' uses store.update (no edited flag, safetyOriginal kept): the rider's pick is overwritten
    func testU2_HomeAlternativeOnCappedRide() {
        let s = store(); var p = RiderProfile(); p.trainingMode = .cycling; s.profile = p
        s.plan = [Workout(date: at(0, 23), kind: .threshold, minutes: 70)]
        s.refreshRideSafety()
        var w = s.plan[0]; w.kind = .recovery; w.minutes = 30; s.edit(w)                                // HomeView now calls store.edit (P4-02 fix); QA's original called s.update here
        s.refreshRideSafety()
        print("U2 Home alternative recovery30 on a capped ride -> after refresh:", desc(s.plan))
        XCTAssertEqual(s.plan[0].kind, .recovery, "U2: the alternative the rider picked on Home is replaced by \(desc(s.plan))")
    }

    // U3: clearance sequences (model level; the form's save logic sets conditionsChangedAt / clearanceConfirmedAt)
    func testU3_ClearanceSequences() {
        let now = Date()
        // a) new chest pain, the rider re-ticks the toggle but the date stays at an old clearance
        let a = screen { $0.heartOrBloodPressure = true; $0.chestPain = true; $0.clearedAt = self.at(-60); $0.conditionsChangedAt = now; $0.clearanceConfirmedAt = now }
        XCTAssertEqual(a.status, .stop, "U3a: a clearance dated before new chest pain covers it")
        // b) conditions changed after the clearance was confirmed
        let b = screen { $0.heartOrBloodPressure = true; $0.boneJointProblem = true; $0.clearedAt = self.at(-60); $0.conditionsChangedAt = now; $0.clearanceConfirmedAt = self.at(-60) }
        XCTAssertEqual(b.status, .needsClearance, "U3b: an older confirmation carries over to a changed answer")
        // c) clearance in the future
        let c = screen { $0.chestPain = true; $0.clearedAt = self.at(30); $0.conditionsChangedAt = now; $0.clearanceConfirmedAt = now }
        XCTAssertNotEqual(c.status, .cleared, "U3c: future-dated clearance accepted")
        // d) supervised only with every kind of clearance
        let d = screen { $0.supervisedOnly = true; $0.clearedAt = now; $0.conditionsChangedAt = self.at(-1); $0.clearanceConfirmedAt = now }
        XCTAssertEqual(d.status, .stop)
        // e) operation (new question) without clearance, and an old pause
        XCTAssertEqual(screen { $0.recentOperation = true }.status, .needsClearance)
        XCTAssertEqual(screen({ $0.currentIllness = true }, answered: at(-400)).status, .paused, "U3e: an illness pause expires into training")
        // info: non-symptom condition added, rider re-ticked, clearance 300 d old; legacy (no new fields) cases
        let f = screen { $0.heartOrBloodPressure = true; $0.pregnancy = true; $0.clearedAt = self.at(-300); $0.conditionsChangedAt = now; $0.clearanceConfirmedAt = now }
        var g = screen { $0.chestPain = true; $0.clearedAt = self.at(1, 0) }; g.questionSet = 2
        var h = screen { $0.chestPain = true; $0.clearedAt = Date() }; h.questionSet = 2
        print("U3 info: pregnancy added + heart, re-ticked, clearance 300 d old -> \(f.status); legacy set-2 chest pain + clearance after -> \(g.status); legacy set-2 chest pain + clearance same time -> \(h.status)")
    }

    // U4: see-a-doctor / supervised / illness pause every session kind, fixed and edited included, and restore them exactly
    func testU4_PauseEverySessionKindAndRestore() {
        for (name, sc) in [("stop", screen { $0.chestPain = true }), ("supervised", screen { $0.supervisedOnly = true }), ("ill", screen { $0.currentIllness = true }), ("ill, 400 d old", screen({ $0.currentIllness = true }, answered: at(-400)))] {
            let s = store(); var p = RiderProfile(); p.trainingMode = .hybrid; p.healthScreen = screen(); s.profile = p
            var lift = Workout(date: at(1, 18), kind: .strength, minutes: 45, strengthFocus: .lower); lift.plannedEntries = [ExerciseEntry(exercise: squat, sets: [SetEntry(reps: 5, weightKg: 100)])]; lift.fixed = true
            var ed = Workout(date: at(2), kind: .vo2, minutes: 60, note: "my intervals"); ed.edited = true
            let kinds: [WorkoutKind] = [.other, .mobility, .recoveryDay, .ftpTest, .long, .tempo]
            s.plan = [lift, ed] + kinds.enumerated().map { Workout(date: at(3 + $0.offset), kind: $0.element, minutes: 60) }
            let before = s.plan.map { "\($0.kind.rawValue)\($0.minutes)|\($0.note)|\($0.plannedEntries?.count ?? 0)" }
            s.profile.healthScreen = sc; s.refreshRideSafety()
            let paused = s.plan.filter { $0.kind != .rest }
            XCTAssertTrue(paused.isEmpty, "U4 \(name): still planned \(paused.map { $0.kind.rawValue })")
            s.profile.healthScreen = screen(); s.refreshRideSafety()
            let after = s.plan.map { "\($0.kind.rawValue)\($0.minutes)|\($0.note)|\($0.plannedEntries?.count ?? 0)" }
            print("U4 \(name) restored:", after)
            XCTAssertEqual(after, before, "U4 \(name): restore differs")
        }
    }

    // U5: pain release timing
    func testU5_PainReleaseTiming() {
        var p = RiderProfile(); p.trainingMode = .cycling; p.healthScreen = screen()
        let now = Date()
        func ride(_ start: Date, at: Date?) throws -> RideRecord {
            var r = RideRecord(start: start, durationS: 3600, distanceM: 25000, recorder: .phone, sources: [])
            r.checkIn = CheckIn(performance: 5, effort: 6, pain: .concerning, painArea: .knees, at: at ?? start)
            if at == nil {      // legacy check-in without 'at': re-decode from JSON without the key
                var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(r.checkIn!)) as! [String: Any]; obj["at"] = nil
                r.checkIn = try JSONDecoder().decode(CheckIn.self, from: JSONSerialization.data(withJSONObject: obj))
            }
            return r
        }
        func held(_ rides: [RideRecord], clear: Date) -> [PainArea] {
            TrainingAnalyzer.analyze(AdaptationInput(profile: p, plan: [], rides: rides, strength: [], availability: WeeklyAvailability.suggested(for: p), now: now, calendar: cal, painClearances: [PainClearance(area: .knees, at: clear)])).painAreas
        }
        // a) S4 scenario
        XCTAssertEqual(held([try! ride(now.addingTimeInterval(-7200), at: now)], clear: now.addingTimeInterval(-3600)), [.knees], "U5a")
        // b) report made before the confirmation is released by it
        XCTAssertEqual(held([try! ride(now.addingTimeInterval(-7200), at: now.addingTimeInterval(-5000))], clear: now.addingTimeInterval(-3600)), [], "U5b")
        // c) legacy check-in without 'at' (decoded as 1970): released by a later confirmation and stays released after re-decode
        XCTAssertEqual(held([try! ride(at(-5), at: nil)], clear: now.addingTimeInterval(-60)), [], "U5c: legacy report not releasable")
        // d) confirmation dated before the report day but a check-in clock earlier than the session start (clamped to start)
        XCTAssertEqual(held([try! ride(now.addingTimeInterval(-600), at: now.addingTimeInterval(-86_400))], clear: now.addingTimeInterval(-1200)), [.knees], "U5d")
    }

    // U6: return after a break vs not cleared, across loads, reps, RPE and break lengths: never heavier than without the
    // break, never heavier than the last weight
    func testU6_ReturnVsNotCleared() {
        var bad: [String] = []
        for (ex, kg) in [(squat, 100.0), (squat, 22.5), (db, 20.0)] {
            for cleared in [false, true] { for reps in [3, 5, 6, 8] { for rpe in [6, 8, 10] { for gap in [21, 30, 60, 120] {
                var p = RiderProfile(); p.trainingMode = .strength; p.level = .intermediate
                if cleared { p.healthScreen = screen() }
                var prefs = StrengthPrefs(); prefs.goal = .strength
                func presc(_ days: [Int]) -> StrengthPlanner.Load {
                    let c = PlannerContext(profile: p, prefs: prefs, equipment: EquipmentProfile(owned: ["barbell", "dumbbell"]), catalogue: [ex], logs: days.map { log(ex, at($0, 18), kg: kg, reps: reps, rpe: rpe) }, now: Date(), calendar: cal)
                    var r = StrengthPlanner.dose(role: .main, goal: .strength, experience: .intermediate).reps
                    if let lo = c.readiness.minStrengthReps, r.lowerBound < lo { r = lo...max(lo + 4, r.upperBound) }
                    return StrengthPlanner.prescribeLoad(ex, meta: ExerciseLibrary.meta(ex), reps: r, sets: 3, painBlocked: false, ctx: c)
                }
                let a = presc([-gap, -gap - 3]), n = presc([-3, -6])
                let wa = a.weight ?? 0, wn = n.weight ?? 0
                if wa > wn + 0.001 || wa > kg + 0.001 { bad.append("\(ex.name) \(kg)x\(reps)@\(rpe) cleared=\(cleared) gap \(gap): break \(wa)x\(a.reps) vs no break \(wn)x\(n.reps)") }
            } } } }
        }
        print("U6 violations (\(bad.count)):", bad.prefix(12))
        XCTAssertTrue(bad.isEmpty, "U6: \(bad.count) combinations heavier after a break")
    }

    // U7: legacy decode (02d8795 / 3e801a0 data)
    func testU7_LegacyDecode() throws {
        func dec(_ hs: String) throws -> RiderProfile { try JSONDecoder().decode(RiderProfile.self, from: Data(#"{"name":"x","healthScreen":\#(hs)}"#.utf8)) }
        let t = Date().timeIntervalSinceReferenceDate - 86_400
        let ill = try dec(#"{"answeredAt":\#(t),"currentIllness":true,"questionSet":2}"#)
        let stop = try dec(#"{"answeredAt":\#(t),"dizzinessOrFainting":true}"#)
        let bad = try dec(#"{"answeredAt":\#(t),"conditionsChangedAt":"x","clearanceConfirmedAt":[],"questionSet":"3"}"#)
        print("U7 set-2 ill -> \(ill.readiness.screen); 02d8795 dizziness -> \(stop.readiness.screen); malformed new fields -> \(bad.readiness.screen)")
        XCTAssertEqual(ill.readiness.screen, .paused); XCTAssertEqual(stop.readiness.screen, .stop); XCTAssertEqual(bad.readiness.screen, .notAnswered)
        // returnMark missing / malformed in stored entries
        let e = try JSONDecoder().decode(ExerciseEntry.self, from: JSONEncoder().encode(ExerciseEntry(exercise: squat, sets: [SetEntry(reps: 5, weightKg: 100)])))
        XCTAssertNil(e.returnMark)
    }

    // U8: caution on an edited hard ride appears while not cleared and disappears afterwards, the rider's note kept
    func testU8_EditedRideCaution() {
        let s = store(); var p = RiderProfile(); p.trainingMode = .cycling; p.healthScreen = screen(); s.profile = p
        var r = Workout(date: at(2), kind: .vo2, minutes: 60, note: "club ride"); r.edited = true; s.plan = [r]
        s.profile.healthScreen = screen { $0.heartOrBloodPressure = true }; s.refreshRideSafety()
        let n1 = s.plan[0].note
        s.profile.healthScreen = screen(); s.refreshRideSafety()
        let n2 = s.plan[0].note
        print("U8 needs clearance: '\(n1)' | cleared: '\(n2)'")
        XCTAssertTrue(n1.hasPrefix("Caution") && n1.contains("club ride")); XCTAssertEqual(n2, "club ride"); XCTAssertEqual(s.plan[0].kind, .vo2)
    }

    // U9: P3-14 — typed days follow the goal (rider-typed non-fixed day too); fixed untouched
    func testU9_TypedDaysFollowGoalInfo() {
        var p = RiderProfile(); p.trainingMode = .cycling; p.level = .intermediate; p.goal = .fitness; p.hoursPerWeek = 7; p.cyclingDaysPerWeek = 3; p.healthScreen = screen()
        var a = WeeklyAvailability(days: Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7))
        a.days[1] = DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: .intervals, minutes: 60)])
        a.days[3] = DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: .threshold, minutes: 90)])
        var fixed = DayAssignment(sport: .cycling, cyclingType: .threshold, minutes: 70); fixed.fixed = true
        a.days[5] = DayAvailability(assignments: [fixed])
        let w = PlanEngine.week(starting: nextMonday, profile: p, availability: a, trainingWeeks: 0)
        print("U9 fitness goal, typed vo2/threshold + fixed threshold:", w.filter { $0.kind != .rest }.map { "\($0.date.shortDay):\($0.kind.rawValue)\($0.minutes) '\($0.note.prefix(60))'" })
        XCTAssertEqual(w.filter { $0.fixed }.first?.kind, .threshold)
        XCTAssertEqual(w.filter { $0.kind == .tempo || $0.kind == .threshold || $0.kind == .vo2 }.count, 3, "two consecutive-ish hard days kept? info")
    }

    // U10: f725cc4 — the rider lifts MORE than the routine prescribes twice: progression; less weight with more reps: none
    func testU10_RoutineAtCurrentInfo() {
        var p = RiderProfile(); p.trainingMode = .strength; p.healthScreen = screen()
        let t = WorkoutTemplate(name: "Legs", focus: .lower, entries: [ExerciseEntry(exercise: squat, sets: (0..<3).map { _ in SetEntry(reps: 8, weightKg: 60) })], updatedAt: Date(timeIntervalSince1970: 0))
        func decide(_ kg: Double, _ reps: Int) -> String {
            var w = Workout(date: at(2, 18), kind: .strength, minutes: 45, strengthFocus: .lower); w.templateId = t.id
            var logs = [log(squat, at(-3, 18), kg: kg, reps: reps, rpe: 7), log(squat, at(-6, 18), kg: kg, reps: reps, rpe: 7)]
            for i in logs.indices { logs[i].templateId = t.id; logs[i].checkIn = CheckIn(performance: 7, effort: 6, at: logs[i].date) }
            let inp = AdaptationInput(profile: p, plan: [w], rides: [], strength: logs, availability: WeeklyAvailability.suggested(for: p), equipment: EquipmentProfile(owned: ["barbell"]), catalogue: [squat], templates: [t], originalEntries: [w.id: t.prefilled(from: logs.first)], now: Date(), calendar: cal)
            return AdaptationEngine.strengthDecision(t.prefilled(from: logs.first)[0], session: w, input: inp).map { $0.summary } ?? "no change"
        }
        print("U10 routine 3x8@60: logged 62.5x8 twice -> \(decide(62.5, 8)); 57.5x10 twice -> \(decide(57.5, 10)); 60x8 twice -> \(decide(60, 8))")
    }
}
