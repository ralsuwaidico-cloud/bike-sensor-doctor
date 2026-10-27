import XCTest
@testable import BikeComputer

/// Cyclift A5 hardening pass (26 Oct 2026, ios/STRENGTH_AUDIT.md): one test per fix of the strength / schedule audit.
final class StrengthAuditTests: XCTestCase {
    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: Date()) }
    private var monday: Date { let wd = (cal.component(.weekday, from: today) + 5) % 7; return cal.date(byAdding: .day, value: -wd, to: today)! }
    private var tuesday: Date { cal.date(byAdding: .day, value: 1, to: monday)! }
    private var nextTuesday: Date { cal.date(byAdding: .day, value: 8, to: monday)! }
    private var nextMonday: Date { cal.date(byAdding: .day, value: 7, to: monday)! }

    /// Same hybrid week as RoutinesTests: Tue strength, Wed ride, Thu strength, Sat long ride, Sun strength.
    private func store() -> Store {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let s = Store(directory: dir, generatePlan: false)
        var p = RiderProfile.screened(); p.trainingMode = .hybrid; p.priority = .balanced; p.hoursPerWeek = 5; p.liftingHoursPerWeek = 2; p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 3
        s.profile = p
        s.availability = WeeklyAvailability(days: [DayAvailability(activity: .rest, minutes: 0), DayAvailability(assignments: [DayAssignment(sport: .strength, strengthType: .fullBody, minutes: 30)]),
                                                   DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: nil, minutes: 60)]), DayAvailability(assignments: [DayAssignment(sport: .strength, strengthType: .upper, minutes: 40)]),
                                                   DayAvailability(activity: .rest, minutes: 0), DayAvailability(assignments: [DayAssignment(sport: .cycling, cyclingType: .long, minutes: 120)]), DayAvailability(assignments: [DayAssignment(sport: .strength, strengthType: .lower, minutes: 40)])])
        s.ensurePlan()
        return s
    }
    private func ex(_ id: String, _ name: String, _ pat: MovementPattern, equipment: [String] = ["dumbbell"]) -> Exercise { Exercise(id: id, name: name, equipment: equipment, pattern: pat) }
    private var press: Exercise { ex("db-press", "Dumbbell press", .push) }
    private func sets(_ reps: [Int], kg: Double? = 20, done: [Bool]? = nil, rpe: Int? = nil) -> [SetEntry] {
        reps.enumerated().map { i, r in SetEntry(reps: r, weightKg: kg, bodyweight: kg == nil, rpe: rpe, done: done?[i] ?? true) }
    }
    private func routine(_ e: Exercise, _ reps: [Int] = [10, 10, 10], kg: Double? = 20, updatedAt: Date = .distantPast) -> WorkoutTemplate {
        WorkoutTemplate(name: "Short Full Body Workout", focus: .fullBody, entries: [ExerciseEntry(exercise: e, sets: sets(reps, kg: kg))], updatedAt: updatedAt)
    }
    private func session(daysAgo: Double, _ entries: [ExerciseEntry], rpe: Int? = nil) -> StrengthSession {
        StrengthSession(date: today.addingTimeInterval(-daysAgo * 86_400 + 9 * 3600), minutes: 40, focus: .fullBody, rpe: rpe, exercises: entries)
    }
    private func strengthOn(_ s: Store, _ day: Date) -> Workout? { s.plan.first { $0.kind == .strength && cal.isDate($0.date, inSameDayAs: day) } }

    // MARK: weekday defaults survive a rebuild and a training-mode change
    func testWeekdayDefaultSurvivesRebuildAndTrainingModeChange() {
        let s = store()
        let t = routine(press); s.saveTemplate(t)
        s.setWeekdayRoutine(t, weekday: 1)
        _ = s.regenerate(weekOf: nextTuesday, replaceEdited: true)
        XCTAssertEqual(strengthOn(s, nextTuesday)?.templateId, t.id, "rebuild keeps the Tuesday default")
        // mode change with the suggested availability (the Profile page rebuilds the weeks then)
        s.availability = nil
        for wd in 0..<7 { s.setWeekdayRoutine(t, weekday: wd) }
        s.updateProfile { $0.trainingMode = .cycling; $0.liftDaysPerWeek = 0; $0.liftingHoursPerWeek = 0 }
        _ = s.regenerate(weekOf: nextTuesday, replaceEdited: false)
        XCTAssertTrue(s.workouts(weekOf: nextTuesday).filter { $0.kind == .strength }.allSatisfy { $0.templateId == t.id }, "any lift the cycling week keeps has its default")
        XCTAssertEqual(s.weekdayRoutines.count, 7, "the defaults themselves are kept through the mode change")
        s.updateProfile { $0.trainingMode = .hybrid; $0.liftDaysPerWeek = 2; $0.liftingHoursPerWeek = 2 }
        _ = s.regenerate(weekOf: nextTuesday, replaceEdited: false)
        let lifts = s.workouts(weekOf: nextTuesday).filter { $0.kind == .strength }
        XCTAssertFalse(lifts.isEmpty)
        XCTAssertTrue(lifts.allSatisfy { $0.templateId == t.id }, "every regenerated lift takes its weekday default again")
    }

    // MARK: ensurePlan never rebuilds an existing week (it used to when today's entry was removed)
    func testEnsurePlanNeverRebuildsAnExistingWeek() {
        let s = store()
        let t = routine(press); s.saveTemplate(t)
        let nt = strengthOn(s, nextTuesday)!
        _ = s.assign(template: t, to: nt)
        if let i = s.plan.firstIndex(where: { $0.date >= monday && $0.date < today && $0.kind != .rest }) { s.plan[i].done = true }
        for w in s.plan where cal.isDate(w.date, inSameDayAs: today) { s.remove(w) }
        let before = s.plan
        s.ensurePlan()
        XCTAssertEqual(s.plan, before, "hand edits, the assigned routine and done flags survive; nothing is regenerated")
        XCTAssertTrue(s.plan.first { $0.id == nt.id }!.routineManual)
        // a missing week (e.g. the app stayed open across the weekend) is generated with the weekday defaults
        s.setWeekdayRoutine(t, weekday: 3)
        s.plan.removeAll { $0.date >= nextMonday }
        s.ensurePlan()
        XCTAssertFalse(s.workouts(weekOf: nextTuesday).isEmpty)
        XCTAssertEqual(strengthOn(s, cal.date(byAdding: .day, value: 2, to: nextTuesday)!)?.templateId, t.id)
    }

    // MARK: template edits reach future sessions, never completed ones; partial sessions do not shrink the plan
    func testEditingTemplateUpdatesFutureSessionsOnly() {
        let s = store()
        var t = routine(press, updatedAt: Date().addingTimeInterval(-7200)); s.saveTemplate(t)
        let nt = strengthOn(s, nextTuesday)!
        _ = s.assign(template: t, to: nt)
        var done = session(daysAgo: 0, [ExerciseEntry(exercise: press, sets: sets([10, 10, 10], kg: 22))]); done.date = Date().addingTimeInterval(-3600); done.templateId = t.id
        XCTAssertTrue(s.addStrength(done))
        XCTAssertEqual(s.plannedEntries(for: s.plan.first { $0.id == nt.id }!)[0].sets[0].weightKg, 22, "last completed use carries its weights forward")
        // rename only: the edit time does not move, so last session's weights are kept
        let renamed = TemplateEditor.apply(name: "Renamed", focus: t.focus, entries: t.entries, minutes: nil, to: t)
        XCTAssertEqual(renamed.updatedAt, t.updatedAt)
        // a real edit (8 reps at 24 kg) wins for the future session
        var e = t.entries; e[0].sets = sets([8, 8, 8], kg: 24)
        t = TemplateEditor.apply(name: t.name, focus: t.focus, entries: e, minutes: nil, to: t)
        s.saveTemplate(t)
        let planned = s.plannedEntries(for: s.plan.first { $0.id == nt.id }!)
        XCTAssertEqual(planned[0].sets.map { $0.reps }, [8, 8, 8]); XCTAssertEqual(planned[0].sets[0].weightKg, 24)
        XCTAssertEqual(s.strength[0].exercises?[0].sets[0].reps, 10, "the completed log is never rewritten")
        XCTAssertEqual(s.strength[0].exercises?[0].sets[0].weightKg, 22)
        // a partial session (2 of 3 sets) does not shrink the next plan
        let t2 = routine(press, updatedAt: .distantPast)
        var partial = session(daysAgo: 1, [ExerciseEntry(exercise: press, sets: sets([10, 9], kg: 21))]); partial.templateId = t2.id
        let p = t2.prefilled(from: partial)
        XCTAssertEqual(p[0].sets.count, 3); XCTAssertEqual(p[0].sets[0].weightKg, 21); XCTAssertEqual(p[0].sets[2].weightKg, 20)
    }

    // MARK: deleting a template → "routine removed — choose another", never a crash or a silent generic session
    func testDeletedTemplateLeavesRoutineRemovedState() {
        let s = store()
        let t = routine(press); s.saveTemplate(t)
        let nt = strengthOn(s, nextTuesday)!
        _ = s.assign(template: t, to: nt); s.setWeekdayRoutine(t, weekday: 1)
        s.deleteTemplateEverywhere(t)
        let w = s.plan.first { $0.id == nt.id }!
        XCTAssertEqual(s.routineState(for: w), .removed); XCTAssertTrue(s.isRoutineRemoved(w))
        XCTAssertNil(s.routine(for: w)); XCTAssertTrue(s.plannedEntries(for: w).isEmpty); XCTAssertFalse(w.routineManual)
        XCTAssertTrue(s.weekdayRoutines.isEmpty)
        XCTAssertEqual(s.insight(for: w, entries: []).kind, .insufficient, "no crash, no invented advice")
        // choose another routine
        var t2 = routine(ex("goblet", "Goblet squat", .squat)); t2.name = "Legs"; s.saveTemplate(t2)
        _ = s.assign(template: t2, to: w)
        XCTAssertEqual(s.routineState(for: s.plan.first { $0.id == nt.id }!), .assigned(t2))
        // a template removed by sync (tombstone from another device) is the same state
        s.templates.removeAll { $0.id == t2.id }
        XCTAssertTrue(s.isRoutineRemoved(s.plan.first { $0.id == nt.id }!))
        // a dangling weekday default (as in the build-40 seed) is never applied
        s.weekdayRoutines[3] = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        _ = s.regenerate(weekOf: nextTuesday, replaceEdited: true)
        XCTAssertNil(strengthOn(s, cal.date(byAdding: .day, value: 2, to: nextTuesday)!)?.templateId)
    }

    // MARK: equipment and exclusions also filter the coverage ("consider adding …") suggestion
    func testCoverageSuggestionRespectsEquipmentAndExclusions() {
        var hist: [StrengthSession] = []
        for k in 0..<3 { hist.append(session(daysAgo: Double(2 + k * 5), [ExerciseEntry(exercise: ex("sq", "Squat", .squat), sets: sets([10])), ExerciseEntry(exercise: ex("lunge", "Lunge", .singleLeg), sets: sets([10])), ExerciseEntry(exercise: ex("plank", "Plank", .core, equipment: ["bodyweight"]), sets: sets([1], kg: nil)), ExerciseEntry(exercise: press, sets: sets([10])), ExerciseEntry(exercise: ex("row", "Row", .pull), sets: sets([10]))])) }
        let swing = ex("kb-swing", "Kettlebell swing", .hinge, equipment: ["kettlebell"]), rdl = ex("db-rdl", "Dumbbell RDL", .hinge)
        let excluded = InsightEngine.next(routine: nil, planned: [], sessions: hist, plan: [], equipment: EquipmentProfile(owned: ["kettlebell"], excluded: ["kb-swing"]), catalogue: [swing, rdl], on: today, now: today)
        XCTAssertEqual(excluded.kind, .coverage)
        XCTAssertFalse(excluded.text.contains("Kettlebell swing"), "excluded exercise never suggested: \(excluded.text)")
        XCTAssertFalse(excluded.text.contains("Dumbbell RDL"), "no dumbbell owned")
        XCTAssertTrue(excluded.text.contains("none in the list fits"))
        XCTAssertTrue(excluded.why.contains("cannot do"))
        let allowed = InsightEngine.next(routine: nil, planned: [], sessions: hist, plan: [], equipment: EquipmentProfile(owned: ["kettlebell"]), catalogue: [swing, rdl], on: today, now: today)
        XCTAssertTrue(allowed.text.contains("Kettlebell swing"))
        // older spellings of owned equipment still match the catalogue
        let plural = EquipmentProfile(owned: ["Dumbbells", "bench"])
        XCTAssertTrue(plural.canDo(rdl)); XCTAssertFalse(plural.canDo(swing))
    }

    // MARK: progression uses completed sets of the same exercise only and needs ≥ 2 sessions
    func testProgressionNeedsTwoCompletedSessionsOfTheSameExercise() {
        let t = routine(press)
        let p = t.entries
        let none = EquipmentProfile()
        // one session of the press + one of something else → not enough
        let a = [session(daysAgo: 5, [ExerciseEntry(exercise: press, sets: sets([10, 10, 10]))]), session(daysAgo: 2, [ExerciseEntry(exercise: ex("row", "Row", .pull), sets: sets([10, 10, 10]))])]
        XCTAssertEqual(InsightEngine.next(routine: t, planned: p, sessions: a, plan: [], equipment: none, catalogue: [press], on: today).kind, .insufficient)
        // the last session completed 1 of 3 planned sets → hold, never "+1 kg" (the old check counted it as all done)
        let partial = [session(daysAgo: 5, [ExerciseEntry(exercise: press, sets: sets([10, 10, 10]))]), session(daysAgo: 2, [ExerciseEntry(exercise: press, sets: sets([10, 10, 10], done: [true, false, false]))])]
        let h = InsightEngine.next(routine: t, planned: p, sessions: partial, plan: [], equipment: none, catalogue: [press], on: today)
        XCTAssertEqual(h.kind, .hold); XCTAssertNil(h.change); XCTAssertTrue(h.text.contains("set"))
        // planned = last performance (8s) but the routine asks for 10s → hold, not a circular "all hit"
        let low = [session(daysAgo: 5, [ExerciseEntry(exercise: press, sets: sets([8, 8, 8]))]), session(daysAgo: 2, [ExerciseEntry(exercise: press, sets: sets([8, 8, 8]))])]
        let h2 = InsightEngine.next(routine: t, planned: [ExerciseEntry(exercise: press, sets: sets([8, 8, 8]))], sessions: low, plan: [], equipment: none, catalogue: [press], on: today)
        XCTAssertEqual(h2.kind, .hold)
        // a session in progress is never evidence
        var running = session(daysAgo: 0, [ExerciseEntry(exercise: press, sets: sets([10, 10, 10], rpe: 10))]); running.startedAt = Date()
        let good = [session(daysAgo: 5, [ExerciseEntry(exercise: press, sets: sets([10, 10, 10], rpe: 7))]), session(daysAgo: 2, [ExerciseEntry(exercise: press, sets: sets([10, 10, 10], rpe: 7))])]
        XCTAssertEqual(InsightEngine.next(routine: t, planned: p, sessions: good + [running], plan: [], equipment: none, catalogue: [press], on: today).kind, .progression)
        // the whole session rated RPE 9 (no per-set RPE) → hold
        let hard = [good[0], session(daysAgo: 2, [ExerciseEntry(exercise: press, sets: sets([10, 10, 10]))], rpe: 9)]
        let h3 = InsightEngine.next(routine: t, planned: p, sessions: hard, plan: [], equipment: none, catalogue: [press], on: today)
        XCTAssertEqual(h3.kind, .hold); XCTAssertTrue(h3.text.contains("RPE 9"))
        // an exercise the rider excluded gets no advice
        let x = InsightEngine.next(routine: t, planned: p, sessions: good, plan: [], equipment: EquipmentProfile(excluded: ["db-press"]), catalogue: [press], on: today)
        XCTAssertNotEqual(x.kind, .progression)
    }

    // MARK: no load the equipment cannot provide; fixed weights are not modelled and the Why? says so; units
    func testProgressionLoadRespectsEquipmentAndUnits() {
        let t = routine(press)
        let good = [session(daysAgo: 5, [ExerciseEntry(exercise: press, sets: sets([10, 10, 10], rpe: 7))]), session(daysAgo: 2, [ExerciseEntry(exercise: press, sets: sets([10, 10, 10], rpe: 7))])]
        let kg = InsightEngine.next(routine: t, planned: t.entries, sessions: good, plan: [], equipment: EquipmentProfile(), catalogue: [press], on: today)
        XCTAssertEqual(kg.kind, .progression); XCTAssertEqual(kg.change?.weightDeltaKg, 1); XCTAssertTrue(kg.text.contains("1 kg per hand"))
        XCTAssertTrue(kg.why.contains("does not know which weights you own"), kg.why)
        XCTAssertTrue(kg.why.contains("Cyclift"))
        // dumbbell not in the equipment list → a rep, not more weight
        let noDb = InsightEngine.next(routine: t, planned: t.entries, sessions: good, plan: [], equipment: EquipmentProfile(owned: ["kettlebell"]), catalogue: [press], on: today)
        XCTAssertEqual(noDb.change?.repsDelta, 1); XCTAssertEqual(noDb.change?.weightDeltaKg, 0); XCTAssertTrue(noDb.why.contains("not in your equipment list"))
        // imperial: a 2.5 lb step, stored in kg; texts in lb
        let lb = InsightEngine.next(routine: t, planned: t.entries, sessions: good, plan: [], equipment: EquipmentProfile(), catalogue: [press], on: today, units: .imperial)
        XCTAssertEqual(lb.change!.weightDeltaKg, 2.5 / WeightFmt.lbPerKg, accuracy: 0.0001)
        XCTAssertTrue(lb.text.contains("2.5 lb")); XCTAssertTrue(lb.why.contains("44.1 lb")); XCTAssertFalse(lb.text.contains("kg"))
        // a barbell exercise steps 2.5 kg
        let bb = ex("bb-squat", "Back squat", .squat, equipment: ["barbell"])
        let tb = routine(bb)
        let bbHist = good.map { s -> StrengthSession in var x = s; x.exercises = [ExerciseEntry(exercise: bb, sets: sets([10, 10, 10], rpe: 7))]; return x }
        XCTAssertEqual(InsightEngine.next(routine: tb, planned: tb.entries, sessions: bbHist, plan: [], equipment: EquipmentProfile(), catalogue: [bb], on: today).change?.weightDeltaKg, 2.5)
    }

    // MARK: kg / lb display follows the units setting; storage stays metric
    func testWeightUnitsDisplayOnlyStorageMetric() {
        XCTAssertEqual(WeightFmt.text(20, .metric), "20 kg"); XCTAssertEqual(WeightFmt.text(22.5, .metric), "22.5 kg")
        XCTAssertEqual(WeightFmt.text(20, .imperial), "44.1 lb")
        let kg = WeightFmt.parse("50", .imperial)!
        XCTAssertEqual(kg, 22.6796, accuracy: 0.001); XCTAssertEqual(WeightFmt.number(kg, .imperial), "50", "round trip shows what was typed")
        XCTAssertEqual(WeightFmt.parse("22,5", .metric), 22.5); XCTAssertNil(WeightFmt.parse("", .metric)); XCTAssertNil(WeightFmt.parse("-3", .metric))
        XCTAssertEqual(SetEntry(reps: 8, weightKg: 50, rpe: 8).text(units: .imperial), "8 × 110.2 lb @8")
        XCTAssertEqual(SetEntry(reps: 8, weightKg: 50, rpe: 8).text, "8 × 50 kg @8", "metric default unchanged")
        let s = store()
        s.settings.units = .imperial
        let t = routine(press); s.saveTemplate(t)
        XCTAssertEqual(s.templates[0].entries[0].sets[0].weightKg, 20, "stored in kg whatever the display")
    }

    // MARK: centre button at midnight and with a session in progress across midnight
    func testCentreButtonAcrossMidnight() {
        let s = store()
        let wed = cal.date(byAdding: .day, value: 1, to: tuesday)!
        let lateTue = tuesday.addingTimeInterval(23 * 3600 + 59 * 60), earlyWed = wed.addingTimeInterval(60)
        if case .train = s.todayAction(now: lateTue) {} else { XCTFail("Tuesday 23:59 is still the strength day") }
        if case .ride = s.todayAction(now: earlyWed) {} else { XCTFail("00:01 Wednesday is the ride day") }
        // a session started 23:30 Tuesday is still "in progress" after midnight
        let tue = strengthOn(s, tuesday)!
        XCTAssertTrue(s.startStrengthSession(for: tue, template: nil, entries: [], now: tuesday.addingTimeInterval(23.5 * 3600)))
        if case .inProgress = s.todayAction(now: wed.addingTimeInterval(600)) {} else { XCTFail("in progress across midnight → resume") }
        let f = s.finishActiveSession(rpe: 6, notes: "", now: wed.addingTimeInterval(1200))
        XCTAssertEqual(f?.minutes, 50)
        XCTAssertTrue(cal.isDate(f!.date, inSameDayAs: tuesday), "the session belongs to the day it started")
        XCTAssertTrue(s.plan.first { $0.id == tue.id }!.done, "Tuesday's planned session is the one marked done")
        if case .ride(let r) = s.todayAction(now: wed.addingTimeInterval(1260)) { XCTAssertTrue(cal.isDate(r.date, inSameDayAs: wed)) } else { XCTFail("after finishing, Wednesday shows its ride") }
        if case .doneToday(let next) = s.todayAction(now: lateTue) { XCTAssertNotNil(next); XCTAssertNotEqual(next?.kind, .recoveryDay); XCTAssertTrue(next!.date >= wed) } else { XCTFail("Tuesday done → next step") }
    }

    // MARK: duplicate-log prevention
    func testDuplicateLogsArePrevented() {
        let s = store()
        let tue = strengthOn(s, tuesday)!
        let t9 = tuesday.addingTimeInterval(9 * 3600)
        XCTAssertTrue(s.startStrengthSession(for: tue, template: nil, entries: [ExerciseEntry(exercise: press, sets: sets([10, 10]))], now: t9))
        s.updateActiveSession { $0.exercises![0].sets[0].done = true }
        XCTAssertNotNil(s.finishActiveSession(rpe: 7, notes: "", now: t9.addingTimeInterval(1800)))
        XCTAssertNil(s.finishActiveSession(rpe: 7, notes: "", now: t9.addingTimeInterval(1860)), "finishing twice stores nothing")
        XCTAssertEqual(s.strength.count, 1)
        // a quick log for the same planned session is refused; the UI is told what is already logged
        XCTAssertFalse(s.addStrength(StrengthSession(date: t9.addingTimeInterval(3600), minutes: 30, focus: .fullBody, rpe: 6, workoutId: tue.id)))
        XCTAssertEqual(s.strength.count, 1)
        XCTAssertNotNil(s.existingLog(forWorkout: tue.id, on: tuesday))
        XCTAssertNotNil(s.existingLog(forWorkout: nil, on: tuesday), "a quick log from Home after the routine: warned")
        XCTAssertFalse(s.startStrengthSession(for: tue, template: nil, entries: []), "a completed session cannot be started again")
        // an explicit extra session (no planned workout) is still possible
        XCTAssertTrue(s.addStrength(StrengthSession(date: t9.addingTimeInterval(6 * 3600), minutes: 20, focus: .upper, rpe: 5)))
        // a detailed log replaces a quick log of the same planned session (never two logs for one session)
        let thu = strengthOn(s, cal.date(byAdding: .day, value: 2, to: tuesday)!)!
        let th9 = cal.startOfDay(for: thu.date).addingTimeInterval(9 * 3600)
        XCTAssertTrue(s.addStrength(StrengthSession(date: th9, minutes: 40, focus: .upper, rpe: 6, workoutId: thu.id)))
        XCTAssertTrue(s.addStrength(StrengthSession(date: th9, minutes: 40, focus: .upper, rpe: 6, exercises: [ExerciseEntry(exercise: press, sets: sets([10]))], workoutId: thu.id)))
        let thuLogs = s.strength.filter { $0.workoutId == thu.id }
        XCTAssertEqual(thuLogs.count, 1); XCTAssertTrue(thuLogs[0].isDetailed)
        XCTAssertNil(s.existingLog(forWorkout: nil, on: cal.date(byAdding: .day, value: -1, to: tuesday)!), "Monday (rest, nothing logged): no warning")
    }

    // MARK: weekday default: budget warning, hand-set durations and completed sessions untouched
    func testWeekdayDefaultWarnsOverBudgetAndKeepsHandEdits() {
        let s = store()
        let small = routine(press); s.saveTemplate(small)                      // ≈ 15 min
        let nt = strengthOn(s, nextTuesday)!
        var edited = nt; edited.minutes = 25; s.edit(edited)
        let note = s.setWeekdayRoutine(small, weekday: 1)
        let after = s.plan.first { $0.id == nt.id }!
        XCTAssertEqual(after.templateId, small.id); XCTAssertEqual(after.minutes, 25, "a hand-set duration is kept")
        XCTAssertNil(note, "15–30 + 40 + 40 min fits the 2 h budget")
        var t2 = routine(press); t2.minutesEstimate = 110; t2.name = "Long"; s.saveTemplate(t2)
        XCTAssertNotNil(s.setWeekdayRoutine(t2, weekday: 3), "Thursday 110 min pushes the week over the lifting budget")
        // completed sessions are never re-assigned
        if let i = s.plan.firstIndex(where: { $0.id == nt.id }) { s.plan[i].done = true }
        XCTAssertNil(s.assign(template: t2, to: s.plan.first { $0.id == nt.id }!))
        XCTAssertEqual(s.plan.first { $0.id == nt.id }!.templateId, small.id)
        XCTAssertTrue(s.strength.isEmpty, "templates and assignments never count as completed training")
    }

    // MARK: Accept → Undo follows the applied change; Ignore can be undone
    func testInsightAcceptUndoAndIgnoreUndo() {
        let s = store()
        let t = routine(press); s.saveTemplate(t)
        let nt = strengthOn(s, nextTuesday)!
        _ = s.assign(template: t, to: nt)
        let ins = WorkoutInsight(id: "prog-db-press", kind: .progression, label: .suggestion, text: "Suggestion: add 1 kg", why: "", evidence: "", change: .init(exerciseId: "db-press", repsDelta: 0, weightDeltaKg: 1))
        XCTAssertTrue(s.acceptInsight(ins, for: s.plan.first { $0.id == nt.id }!, alsoTemplate: false))
        XCTAssertNotNil(s.lastAcceptedInsight(for: nt.id)); XCTAssertNil(s.lastAcceptedInsight(for: UUID()))
        XCTAssertTrue(s.undoLastProposal()); XCTAssertNil(s.lastAcceptedInsight(for: nt.id))
        s.ignoreInsight(ins); XCTAssertTrue(s.ignoredInsights.contains(ins.id))
        s.unignoreInsight(ins.id); XCTAssertFalse(s.ignoredInsights.contains(ins.id))
    }
}
