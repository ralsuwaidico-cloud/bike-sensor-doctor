import XCTest
@testable import BikeComputer

/// 0.8.0 — routines on the calendar, the acceptance journey from the brief, equipment, insights, workout mode, the
/// adaptive centre button, migration of a build-36 store.
final class RoutinesTests: XCTestCase {
    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: Date()) }
    private var tuesday: Date { let wd = (cal.component(.weekday, from: today) + 5) % 7; return cal.date(byAdding: .day, value: 1 - wd, to: today)! }

    private func store() -> Store {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let s = Store(directory: dir, generatePlan: false)
        var p = RiderProfile(); p.trainingMode = .hybrid; p.priority = .balanced; p.hoursPerWeek = 5; p.liftingHoursPerWeek = 2; p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 3
        s.profile = p
        s.availability = WeeklyAvailability(days: [DayAvailability(activity: .rest, minutes: 0), DayAvailability(assignments: [DayAssignment(sport: .strength, strengthType: .fullBody, minutes: 30)]),
                                                   DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: nil, minutes: 60)]), DayAvailability(assignments: [DayAssignment(sport: .strength, strengthType: .upper, minutes: 40)]),
                                                   DayAvailability(activity: .rest, minutes: 0), DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: .long, minutes: 120)]), DayAvailability(assignments: [DayAssignment(sport: .strength, strengthType: .lower, minutes: 40)])])
        s.ensurePlan()
        return s
    }
    private func ex(_ id: String, _ name: String, _ pat: MovementPattern, equipment: [String] = ["dumbbell"]) -> Exercise { Exercise(id: id, name: name, equipment: equipment, pattern: pat) }
    private func shortFullBody() -> WorkoutTemplate {
        WorkoutTemplate(name: "Short Full Body Workout", focus: .fullBody, entries: [
            ExerciseEntry(exercise: ex("db-chest-press", "Dumbbell chest press", .push), sets: [SetEntry(reps: 10, weightKg: 20), SetEntry(reps: 10, weightKg: 20), SetEntry(reps: 10, weightKg: 20)], superset: "A"),
            ExerciseEntry(exercise: ex("db-row", "Dumbbell row", .pull), sets: [SetEntry(reps: 10, weightKg: 22.5), SetEntry(reps: 10, weightKg: 22.5)], superset: "A", notes: "elbow close"),
            ExerciseEntry(exercise: ex("goblet-squat", "Goblet squat", .squat), sets: [SetEntry(reps: 12, weightKg: 24), SetEntry(reps: 12, weightKg: 24)])
        ])
    }

    // MARK: the ten-step acceptance journey
    func testAcceptanceJourney() {
        let s = store()
        // the chest press is the rider's own exercise (dumbbell) so the coach knows its equipment
        s.addCustomExercise(ex("db-chest-press", "Dumbbell chest press", .push))
        // 1. create a template with several exercises — directly, no completed session appears
        let t = shortFullBody(); s.saveTemplate(t)
        XCTAssertEqual(s.templates.count, 1); XCTAssertTrue(s.strength.isEmpty, "a saved template never counts as completed training")
        // 2. assign it to Tuesday's strength session
        let tue = s.workouts(weekOf: tuesday).first { $0.kind == .strength && cal.isDate($0.date, inSameDayAs: tuesday) }
        XCTAssertNotNil(tue, "the hybrid week has a strength session on Tuesday")
        guard let tue else { return }
        let note = s.assign(template: t, to: tue)
        XCTAssertNil(note, "the routine fits the lifting budget")
        let assigned = s.plan.first { $0.id == tue.id }!
        // 3./4. the calendar shows the routine's name and the actual saved exercises, not a generic circuit
        XCTAssertEqual(assigned.templateId, t.id); XCTAssertTrue(assigned.routineManual)
        XCTAssertEqual(assigned.displayTitle(routine: s.routine(for: assigned)), "Short Full Body Workout")
        let planned = s.plannedEntries(for: assigned)
        XCTAssertEqual(planned.map { $0.name }, ["Dumbbell chest press", "Dumbbell row", "Goblet squat"], "exercise order preserved")
        XCTAssertEqual(planned[0].sets.count, 3); XCTAssertEqual(planned[1].superset, "A"); XCTAssertEqual(planned[1].notes, "elbow close"); XCTAssertEqual(planned[2].sets[0].weightKg, 24)
        // weekday default for every Tuesday
        s.setWeekdayRoutine(t, weekday: 1)
        XCTAssertEqual(s.weekdayRoutines[1], t.id)
        // 5. the centre button on a strength day says Train now and points at that workout (simulate "today" = Tuesday)
        let action = s.todayAction(now: tuesday.addingTimeInterval(9 * 3600))
        if case .train(let w) = action { XCTAssertEqual(w.id, tue.id) } else { XCTFail("Tuesday is a strength day → Train now, got \(action)") }
        // 6. start the routine and log sets
        XCTAssertTrue(s.startStrengthSession(for: assigned, template: t, entries: planned, now: tuesday.addingTimeInterval(9 * 3600)))
        XCTAssertFalse(s.startStrengthSession(for: assigned, template: t, entries: planned), "no second session while one is in progress")
        XCTAssertNotNil(s.activeSession); XCTAssertTrue(s.activeSession!.inProgress); XCTAssertTrue(s.strength.isEmpty, "in progress ≠ completed")
        s.updateActiveSession { sess in
            for i in sess.exercises!.indices { for j in sess.exercises![i].sets.indices { sess.exercises![i].sets[j].done = true } }
            sess.exercises![0].sets[0].reps = 11      /* actual reps recorded */
        }
        // 7. finish → history, planned session marked done, exactly one completed session
        let finished = s.finishActiveSession(rpe: 7, notes: "good", now: tuesday.addingTimeInterval(9 * 3600 + 35 * 60))
        XCTAssertNotNil(finished); XCTAssertNil(s.activeSession)
        XCTAssertEqual(s.strength.count, 1); XCTAssertEqual(s.strength[0].minutes, 35); XCTAssertEqual(s.strength[0].templateId, t.id); XCTAssertEqual(s.strength[0].workoutId, tue.id)
        XCTAssertTrue(s.plan.first { $0.id == tue.id }!.done)
        XCTAssertEqual(s.templates[0].entries[0].sets[0].reps, 10, "a completed session never rewrites the template")
        // 8. the coach uses the completed sets: a second session later → progression suggestion for the first exercise
        var second = StrengthSession(date: tuesday.addingTimeInterval(7 * 86_400 + 9 * 3600), minutes: 35, focus: .fullBody, rpe: 7, exercises: planned.map { e in var x = e; x.sets = x.sets.map { st in var y = st; y.done = true; y.rpe = 7; return y }; return x })
        second.templateId = t.id
        XCTAssertTrue(s.addStrength(second))
        let ins = InsightEngine.next(routine: t, planned: planned, sessions: s.strength, plan: [], equipment: s.equipment, catalogue: s.allExercises, on: tuesday.addingTimeInterval(14 * 86_400))
        XCTAssertEqual(ins.kind, .progression); XCTAssertEqual(ins.label, .suggestion); XCTAssertEqual(ins.exerciseName, "Dumbbell chest press")
        XCTAssertEqual(ins.change?.weightDeltaKg, 1, "dumbbell exercise → +1 kg per hand")
        XCTAssertTrue(ins.evidence.hasPrefix("2 sessions"))
        // 9. next week's Tuesday keeps the routine (weekday default) when the week is generated
        let nextTue = cal.date(byAdding: .day, value: 7, to: tuesday)!
        _ = s.regenerate(weekOf: nextTue, replaceEdited: true)
        let nt = s.workouts(weekOf: nextTue).first { $0.kind == .strength && cal.isDate($0.date, inSameDayAs: nextTue) }
        XCTAssertEqual(nt?.templateId, t.id, "weekday default reused for future weeks")
        // 10. a cycling day still opens the cycling dashboard
        let wed = cal.date(byAdding: .day, value: 1, to: tuesday)!
        if case .ride = s.todayAction(now: wed.addingTimeInterval(9 * 3600)) {} else { XCTFail("Wednesday is a ride day → Ride now") }
    }

    func testBothRestMissedAndDoneDays() {
        let s = store()
        // both: Tuesday gets a ride too → choose
        var ride = Workout(date: tuesday.addingTimeInterval(7 * 3600), kind: .endurance, minutes: 45); ride.sequence = 0
        s.add(ride)
        if case .choose(let items) = s.todayAction(now: tuesday.addingTimeInterval(9 * 3600)) { XCTAssertEqual(items.count, 2) } else { XCTFail("ride + lift → choose") }
        // rest day (Monday) → rest
        let mon = cal.date(byAdding: .day, value: -1, to: tuesday)!
        if case .rest = s.todayAction(now: mon.addingTimeInterval(9 * 3600)) {} else { XCTFail("rest day → optional session") }
        // all done → doneToday with the next session
        for i in s.plan.indices where cal.isDate(s.plan[i].date, inSameDayAs: tuesday) { s.plan[i].done = true }
        if case .doneToday(let next) = s.todayAction(now: tuesday.addingTimeInterval(20 * 3600)) { XCTAssertNotNil(next); XCTAssertTrue(next!.date > tuesday) } else { XCTFail("done → next action") }
        // skipped sessions do not count as open
        for i in s.plan.indices where cal.isDate(s.plan[i].date, inSameDayAs: tuesday) { s.plan[i].done = false; s.plan[i].skipped = true }
        if case .rest = s.todayAction(now: tuesday.addingTimeInterval(9 * 3600)) {} else { XCTFail("everything skipped → nothing planned") }
        // in progress wins over everything
        XCTAssertTrue(s.startStrengthSession(for: nil, template: nil, entries: [], name: "Free"))
        if case .inProgress = s.todayAction(now: tuesday.addingTimeInterval(9 * 3600)) {} else { XCTFail("in progress → resume") }
        s.discardActiveSession()
    }

    func testEquipmentAndExclusionsFilterSuggestionsButNeverEditRoutines() {
        let s = store()
        let bar = ex("barbell-back-squat", "Barbell back squat", .squat, equipment: ["barbell"])
        let gob = ex("goblet-squat", "Goblet squat", .squat, equipment: ["dumbbell"])
        let pushup = ex("push-up", "Push-up", .push, equipment: ["bodyweight"])
        s.equipment = EquipmentProfile(owned: ["dumbbell"], excluded: ["push-up"])
        XCTAssertFalse(s.equipment.canDo(bar)); XCTAssertTrue(s.equipment.canDo(gob)); XCTAssertFalse(s.equipment.canDo(pushup), "excluded even though bodyweight")
        XCTAssertTrue(EquipmentProfile().canDo(bar), "nothing set → nothing filtered")
        // a saved routine with a barbell exercise is kept as saved
        let t = WorkoutTemplate(name: "Legs", focus: .lower, entries: [ExerciseEntry(exercise: bar, sets: [SetEntry(reps: 5, weightKg: 80)])])
        s.saveTemplate(t)
        XCTAssertEqual(s.templates[0].entries[0].exerciseId, "barbell-back-squat", "never silently replaced")
        // coverage suggestion names only doable exercises
        let hinge = ex("romanian-deadlift", "Romanian deadlift", .hinge, equipment: ["barbell"]), kbSwing = ex("kb-swing", "Kettlebell swing", .hinge, equipment: ["kettlebell"]), dbRdl = ex("db-rdl", "Dumbbell RDL", .hinge, equipment: ["dumbbell"])
        var sessions: [StrengthSession] = []
        for k in 0..<3 { sessions.append(StrengthSession(date: today.addingTimeInterval(Double(-3 - k * 5) * 86_400), minutes: 40, focus: .upper, exercises: [ExerciseEntry(exercise: pushup, sets: [SetEntry(reps: 10, bodyweight: true)]), ExerciseEntry(exercise: ex("row", "Row", .pull), sets: [SetEntry(reps: 10, weightKg: 20)]), ExerciseEntry(exercise: gob, sets: [SetEntry(reps: 10, weightKg: 20)]), ExerciseEntry(exercise: ex("plank", "Plank", .core, equipment: ["bodyweight"]), sets: [SetEntry(reps: 1, bodyweight: true)]), ExerciseEntry(exercise: ex("lunge", "Lunge", .singleLeg, equipment: ["bodyweight"]), sets: [SetEntry(reps: 8, bodyweight: true)])])) }
        let ins = InsightEngine.next(routine: nil, planned: [], sessions: sessions, plan: [], equipment: s.equipment, catalogue: [hinge, kbSwing, dbRdl], on: today, now: today)
        XCTAssertEqual(ins.kind, .coverage); XCTAssertTrue(ins.text.contains("hinge")); XCTAssertTrue(ins.text.contains("Dumbbell RDL"), "only equipment the rider owns: \(ins.text)")
        XCTAssertTrue(ins.why.contains("not counted as coverage"))
    }

    func testInsufficientHistoryIsSaidNotInvented() {
        let s = store()
        let t = shortFullBody()
        let none = InsightEngine.next(routine: t, planned: t.entries, sessions: [], plan: [], equipment: s.equipment, catalogue: s.allExercises, on: today)
        XCTAssertEqual(none.kind, .insufficient); XCTAssertNil(none.change); XCTAssertEqual(none.evidence, "insufficient evidence"); XCTAssertTrue(none.text.contains("No exercise history yet"))
        // one detailed session: still not enough for a progression call
        let one = [StrengthSession(date: today.addingTimeInterval(-3 * 86_400), minutes: 30, focus: .fullBody, exercises: t.entries)]
        let o = InsightEngine.next(routine: t, planned: t.entries, sessions: one, plan: [], equipment: s.equipment, catalogue: s.allExercises, on: today)
        XCTAssertEqual(o.kind, .insufficient); XCTAssertTrue(o.text.contains("1 detailed session"))
        // hard last session → hold (finding), never a progression
        var hard = t.entries; hard = hard.map { e in var x = e; x.sets = x.sets.map { st in var y = st; y.rpe = 9; y.done = true; return y }; return x }
        let two = one + [StrengthSession(date: today.addingTimeInterval(-1 * 86_400), minutes: 30, focus: .fullBody, exercises: hard)]
        let h = InsightEngine.next(routine: t, planned: t.entries, sessions: two, plan: [], equipment: s.equipment, catalogue: s.allExercises, on: today)
        XCTAssertEqual(h.kind, .hold); XCTAssertEqual(h.label, .finding); XCTAssertNil(h.change)
        // interference beats everything when a hard ride follows a leg-loading routine
        let hardRide = Workout(date: today.addingTimeInterval(86_400 + 7 * 3600), kind: .threshold, minutes: 60)
        let i = InsightEngine.next(routine: t, planned: t.entries, sessions: two, plan: [hardRide], equipment: s.equipment, catalogue: s.allExercises, on: today)
        XCTAssertEqual(i.kind, .interference); XCTAssertNil(i.change, "the routine is not changed by the coach")
    }

    func testAcceptEditsOnlyThatSessionAndUndoRestores() {
        let s = store()
        let t = shortFullBody(); s.saveTemplate(t)
        let tue = s.workouts(weekOf: tuesday).first { $0.kind == .strength && cal.isDate($0.date, inSameDayAs: tuesday) }!
        _ = s.assign(template: t, to: tue)
        let w = s.plan.first { $0.id == tue.id }!
        let ins = WorkoutInsight(id: "prog-db-chest-press", kind: .progression, label: .suggestion, text: "x", why: "y", evidence: "z", change: .init(exerciseId: "db-chest-press", repsDelta: 0, weightDeltaKg: 1), exerciseName: "Dumbbell chest press")
        XCTAssertTrue(s.acceptInsight(ins, for: w, alsoTemplate: false))
        XCTAssertEqual(s.plannedEntries(for: s.plan.first { $0.id == tue.id }!)[0].sets[0].weightKg, 21)
        XCTAssertEqual(s.templates[0].entries[0].sets[0].weightKg, 20, "template untouched unless asked")
        XCTAssertTrue(s.undoLastProposal())
        XCTAssertEqual(s.plannedEntries(for: s.plan.first { $0.id == tue.id }!)[0].sets[0].weightKg, 20, "undo restores the session's planned sets")
        s.ignoreInsight(ins); XCTAssertTrue(s.ignoredInsights.contains(ins.id))
        // removing / replacing the assignment keeps the template
        _ = s.assign(template: nil, to: w)
        XCTAssertNil(s.plan.first { $0.id == tue.id }!.templateId); XCTAssertEqual(s.templates.count, 1)
        s.deleteTemplateEverywhere(t); XCTAssertTrue(s.templates.isEmpty); XCTAssertTrue(s.weekdayRoutines.isEmpty)
    }

    func testLiftingBudgetWarningOnAssignment() {
        let s = store()
        var big = shortFullBody(); big.minutesEstimate = 110; big.name = "Long"
        s.saveTemplate(big)
        let tue = s.workouts(weekOf: tuesday).first { $0.kind == .strength && cal.isDate($0.date, inSameDayAs: tuesday) }!
        let note = s.assign(template: big, to: tue)
        XCTAssertNotNil(note, "110 + 40 + 40 min against a 2 h lifting budget must warn")
        XCTAssertTrue(note!.contains("against your 2 h budget"))
        XCTAssertEqual(s.plan.first { $0.id == tue.id }!.minutes, 110, "the assignment is made; the rider decides")
    }

    func testPartialSessionSurvivesRestart() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let s1 = Store(directory: dir, generatePlan: false)
        let t = shortFullBody(); s1.saveTemplate(t)
        XCTAssertTrue(s1.startStrengthSession(for: nil, template: t, entries: t.entries, now: Date().addingTimeInterval(-600)))
        s1.updateActiveSession { $0.exercises![0].sets[0].done = true; $0.exercises![0].sets[0].weightKg = 22 }
        s1.pauseActiveSession(now: Date().addingTimeInterval(-300))
        let s2 = Store(directory: dir, generatePlan: false)
        XCTAssertNotNil(s2.activeSession, "an in-progress workout is reloaded after a restart")
        XCTAssertTrue(s2.activeSession!.inProgress); XCTAssertNotNil(s2.activeSession!.pausedAt)
        XCTAssertEqual(s2.activeSession!.exercises![0].sets[0].weightKg, 22); XCTAssertTrue(s2.activeSession!.exercises![0].sets[0].done)
        XCTAssertTrue(s2.strength.isEmpty, "not completed")
        s2.resumeActiveSession()
        let f = s2.finishActiveSession(rpe: nil, notes: "")
        XCTAssertEqual(f?.exercises?.count, 1, "only exercises with completed sets are kept"); XCTAssertEqual(f?.exercises?[0].sets.count, 1)
        XCTAssertGreaterThanOrEqual(f!.minutes, 4); XCTAssertLessThanOrEqual(f!.minutes, 6, "paused time excluded: ~5 min of work")
        try? FileManager.default.removeItem(at: dir)
    }

    /// A store.json as build 36 wrote it (templates, custom exercise, detailed log, edited plan, no 0.8.0 keys) loads with
    /// nothing lost and the new fields at their defaults.
    func testMigrationFromBuild36StoreKeepsEverything() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tid = UUID().uuidString, wid = UUID().uuidString
        let json = """
        {"schema":1,"profile":{"name":"Rashed","goal":"fitness","hoursPerWeek":5,"level":"intermediate","weightKg":82,"age":35,"ftpW":210,"ftpHow":"entered","birthYear":1988,"version":12,"updatedAt":"2026-10-25T10:00:00Z","trainingMode":"hybrid","priority":"balanced","cyclingDaysPerWeek":3,"liftDaysPerWeek":3,"liftingHoursPerWeek":2},
         "settings":{"units":"metric","phoneOnlyMode":false,"hrPref":"watch","keepScreenOn":true,"autoConnectBoard":true,"enabledConnections":["board","watch"]},
         "plan":[{"id":"\(wid)","date":"2026-10-27T07:00:00Z","kind":"strength","minutes":45,"done":false,"skipped":false,"note":"","edited":true,"strengthFocus":"lower","sequence":0,"fixed":true}],
         "rides":[],"tiles":["power","cadence","hr","speed","time","dist"],"onboarded":true,"guest":true,"createdAt":"2026-10-24T10:00:00Z","boardSync":[{"boardId":"8c:fd:49:9b:ef:40","ackedVersion":9,"ackedAt":"2026-10-25T09:00:00Z","confirmed":true,"boardFirmware":"0.6.0","settingsVersion":2}],
         "templates":[{"id":"\(tid)","name":"Short Full Body Workout","focus":"fullBody","entries":[{"id":"\(UUID().uuidString)","exerciseId":"db-chest-press","name":"Dumbbell chest press","pattern":"push","sets":[{"id":"\(UUID().uuidString)","reps":10,"weightKg":20,"bodyweight":false,"unilateral":false,"done":true}],"superset":"A","notes":""}],"updatedAt":"2026-10-25T11:00:00Z"}],
         "customExercises":[{"id":"custom-landmine","name":"Landmine row","aliases":[],"equipment":["barbell"],"pattern":"pull","muscles":["back"],"unilateral":false,"custom":true}],
         "strength":[{"id":"\(UUID().uuidString)","date":"2026-10-24T18:00:00Z","minutes":40,"focus":"fullBody","customName":"","rpe":7,"notes":"","source":"manual","templateId":"\(tid)","exercises":[{"id":"\(UUID().uuidString)","exerciseId":"db-chest-press","name":"Dumbbell chest press","pattern":"push","sets":[{"id":"\(UUID().uuidString)","reps":10,"weightKg":20,"bodyweight":false,"unilateral":false,"done":true}]}]}],
         "appliedProposals":[]}
        """
        try Data(json.utf8).write(to: dir.appendingPathComponent("store.json"))
        let s = Store(directory: dir, generatePlan: false)
        XCTAssertEqual(s.templates.count, 1); XCTAssertEqual(s.templates[0].name, "Short Full Body Workout"); XCTAssertEqual(s.templates[0].entries[0].superset, "A")
        XCTAssertEqual(s.customExercises.count, 1); XCTAssertEqual(s.strength.count, 1); XCTAssertTrue(s.strength[0].isDetailed)
        XCTAssertEqual(s.plan.count, 1); XCTAssertTrue(s.plan[0].edited); XCTAssertTrue(s.plan[0].fixed); XCTAssertNil(s.plan[0].templateId); XCTAssertFalse(s.plan[0].routineManual)
        XCTAssertEqual(s.boardSync.first?.ackedVersion, 9); XCTAssertNotNil(s.boardSync.first?.ackedAt, "last successful sync survives")
        XCTAssertTrue(s.weekdayRoutines.isEmpty); XCTAssertFalse(s.equipment.isSet); XCTAssertNil(s.activeSession); XCTAssertTrue(s.ignoredInsights.isEmpty)
        XCTAssertEqual(s.profile.version, 12); XCTAssertEqual(s.profile.ftpW, 210)
        // round-trips with the new keys
        s.weekdayRoutines[1] = s.templates[0].id; s.equipment.owned = ["dumbbell"]
        let s2 = Store(directory: dir, generatePlan: false)
        XCTAssertEqual(s2.weekdayRoutines[1], s.templates[0].id); XCTAssertEqual(s2.equipment.owned, ["dumbbell"]); XCTAssertEqual(s2.templates.count, 1)
        try? FileManager.default.removeItem(at: dir)
    }
}
