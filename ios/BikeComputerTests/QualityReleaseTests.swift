import XCTest
@testable import BikeComputer

/// Quality release (ios/QUALITY_RELEASE.md): workout state model, one query layer, migration, undo, personalised
/// strength planner, swaps, FTP confidence and the weekly chart maths. Fixtures mirror the owner's report: a Full body
/// session planned for TOMORROW shown as "completed" after a workout finished with no set ticked (1 min log).
final class QualityReleaseTests: XCTestCase {
    private let cal = Calendar.current
    private var now: Date { cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())! }
    private var today: Date { cal.startOfDay(for: Date()) }
    private var tomorrow: Date { cal.date(byAdding: .day, value: 1, to: today)! }
    private var monday: Date { TrainingLedger.monday(of: today) }

    private func dir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("bc-quality-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    private func hybridProfile() -> RiderProfile {
        var p = RiderProfile(); p.name = "Test"; p.trainingMode = .hybrid; p.priority = .balanced; p.hoursPerWeek = 5; p.liftingHoursPerWeek = 2
        p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 3
        return p
    }
    private func store(_ d: URL? = nil) -> Store {
        let s = Store(directory: d ?? dir(), generatePlan: false)
        s.profile = hybridProfile()
        return s
    }
    private func strengthWorkout(_ day: Date, minutes: Int = 40, focus: StrengthFocus = .fullBody) -> Workout {
        Workout(date: day.addingTimeInterval(7 * 3600), kind: .strength, minutes: minutes, strengthFocus: focus)
    }
    private func ex(_ id: String, _ name: String, _ eq: [String], _ p: MovementPattern, _ muscles: [String] = [], unilateral: Bool = false) -> Exercise {
        Exercise(id: id, name: name, equipment: eq, pattern: p, muscles: muscles, unilateral: unilateral, custom: true)
    }
    /// A small explicit catalogue so planner tests do not depend on the bundled exercise list.
    private var catalogue: [Exercise] {
        [ex("q-bbsquat", "Back squat", ["barbell"], .squat, ["quads", "glutes"]),
         ex("q-goblet", "Goblet squat", ["dumbbell", "kettlebell"], .squat, ["quads", "glutes"]),
         ex("q-split", "Bulgarian split squat", ["dumbbell"], .singleLeg, ["quads", "glutes"], unilateral: true),
         ex("q-rdl", "Romanian deadlift", ["barbell"], .hinge, ["hamstrings", "glutes"]),
         ex("q-dbrdl", "Dumbbell Romanian deadlift", ["dumbbell"], .hinge, ["hamstrings", "glutes"]),
         ex("q-bridge", "Glute bridge", ["bodyweight"], .hinge, ["glutes", "hamstrings"]),
         ex("q-bench", "Bench press", ["barbell", "bench"], .push, ["chest", "triceps"]),
         ex("q-dbbench", "Dumbbell bench press", ["dumbbell", "bench"], .push, ["chest", "triceps"]),
         ex("q-pushup", "Push-up", ["bodyweight"], .push, ["chest", "triceps"]),
         ex("q-ohp", "Overhead press", ["barbell"], .push, ["shoulders", "triceps"]),
         ex("q-dbohp", "Dumbbell shoulder press", ["dumbbell"], .push, ["shoulders", "triceps"]),
         ex("q-row", "Barbell row", ["barbell"], .pull, ["back", "biceps"]),
         ex("q-dbrow", "Dumbbell row", ["dumbbell", "bench"], .pull, ["back", "biceps"]),
         ex("q-pullup", "Pull-up", ["pull-up bar"], .pull, ["back", "biceps"]),
         ex("q-plank", "Plank", ["bodyweight"], .core, ["core"]),
         ex("q-carry", "Farmer carry", ["dumbbell", "kettlebell"], .carry, ["grip", "core"])]
    }
    private func ctx(profile: RiderProfile? = nil, prefs: StrengthPrefs = StrengthPrefs(), owned: Set<String> = [], plan: [Workout] = [], logs: [StrengthSession] = [], pain: [PainArea] = []) -> PlannerContext {
        PlannerContext(profile: profile ?? hybridProfile(), prefs: prefs, equipment: EquipmentProfile(owned: owned), catalogue: catalogue, templates: [], logs: logs, rides: [], plan: plan, painAreas: pain, fatigue: false, units: .metric, now: now, calendar: cal)
    }
    private func sets(_ reps: [Int], kg: Double?, rpe: Int? = nil) -> [SetEntry] { reps.map { SetEntry(reps: $0, weightKg: kg, bodyweight: kg == nil, rpe: rpe, done: true) } }

    // MARK: - 1. State model: nothing is completed for a later day, by a date passing, or without evidence

    func testOwnerScenarioFinishingTomorrowsSessionWithNoSetsCompletesNothing() {
        let s = store()
        let tue = strengthWorkout(tomorrow)
        s.plan = [tue]
        // a planned session for a later day cannot be started …
        XCTAssertFalse(s.startStrengthSession(for: tue, template: nil, entries: [ExerciseEntry(exercise: catalogue[1], sets: sets([10, 10, 10], kg: 16))]))
        XCTAssertNil(s.activeSession)
        // … nor marked done
        XCTAssertFalse(s.markDone(tue.id))
        XCTAssertEqual(s.status(s.plan[0]), .planned)
        // a log saved today with the future session's id does not complete it (kept as today's session)
        let log = StrengthSession(date: now, minutes: 1, focus: .fullBody, workoutId: tue.id)
        XCTAssertTrue(s.addStrength(log))
        XCTAssertEqual(s.status(s.plan[0]), .planned)
        XCTAssertFalse(s.plan[0].done)
        XCTAssertNil(s.strength.first?.workoutId, "the link to a later day's session is dropped")
    }

    func testFinishWithNoTickedSetSavesNothingAndKeepsSessionOpen() {
        let s = store()
        let w = strengthWorkout(today)
        s.plan = [w]
        XCTAssertTrue(s.startStrengthSession(for: w, template: nil, entries: [ExerciseEntry(exercise: catalogue[1], sets: sets([10, 10], kg: 16))]))
        XCTAssertEqual(s.status(s.plan[0]), .started)
        XCTAssertNil(s.finishActiveSession(rpe: nil, notes: ""))
        XCTAssertNotNil(s.activeSession, "nothing saved: still active so the rider can tick sets, mark done or discard")
        XCTAssertTrue(s.strength.isEmpty)
        XCTAssertEqual(s.status(s.plan[0]), .started)
        // ticking one set → in progress → finish saves a detailed log; duration is measured, never a made-up minimum
        s.updateActiveSession { $0.exercises?[0].sets[0].done = true }
        XCTAssertEqual(s.status(s.plan[0]), .inProgress)
        let saved = s.finishActiveSession(rpe: 7, notes: "", now: (s.activeSession?.startedAt ?? Date()).addingTimeInterval(10))
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved?.minutes, 0)
        XCTAssertEqual(s.status(s.plan[0]), .completedLogged)
        XCTAssertEqual(s.strength.count, 1)
    }

    func testStatesManualLoggedImportedSkippedAndNoDateDrivenCompletion() {
        let s = store()
        let past = strengthWorkout(cal.date(byAdding: .day, value: -3, to: today)!)
        let manual = strengthWorkout(today)
        var skipped = strengthWorkout(cal.date(byAdding: .day, value: -1, to: today)!); skipped.skipped = true
        var ride = Workout(date: cal.date(byAdding: .day, value: -2, to: today)!.addingTimeInterval(7 * 3600), kind: .endurance, minutes: 60)
        ride.sequence = 0
        s.plan = [past, manual, skipped, ride]
        // a date passing never completes anything
        XCTAssertEqual(s.status(past), .planned)
        XCTAssertEqual(s.status(ride), .planned)
        XCTAssertEqual(s.status(skipped), .skipped)
        // mark done (no duration stated → none invented)
        XCTAssertTrue(s.markDone(manual.id))
        XCTAssertEqual(s.status(s.plan[1]), .completedManual)
        XCTAssertNil(s.plan[1].manualMinutes)
        XCTAssertEqual(s.ledger.lifting(weekOf: TrainingLedger.monday(of: today)).unknownDuration, 1)
        XCTAssertFalse(s.markDone(manual.id), "already completed: no second completion")
        // a recorded ride on its day → logged; an Apple Health strength import → importedHealth
        var r = RideRecord(start: ride.date, durationS: 3600, distanceM: 25_000, recorder: .phone, sources: ["test"]); r.demo = false
        XCTAssertTrue(s.addRide(r))
        XCTAssertEqual(s.status(ride), .completedLogged)
        let imp = StrengthSession(date: past.date.addingTimeInterval(3600), minutes: 35, focus: .fullBody, source: "Apple Health", healthUUID: "H1")
        XCTAssertTrue(s.addStrength(imp))
        XCTAssertEqual(s.status(s.plan.first { $0.id == past.id }!), .importedHealth)
    }

    // MARK: - 2. Edit / delete / undo / revert / convert — stable ids, no duplicates

    func testDeleteLogReopensSessionAndUndoRestoresBoth() {
        let s = store()
        let w = strengthWorkout(today)
        s.plan = [w]
        let log = StrengthSession(date: now, minutes: 40, focus: .fullBody, exercises: [ExerciseEntry(exercise: catalogue[1], sets: sets([10, 10, 10], kg: 16))], workoutId: w.id)
        XCTAssertTrue(s.addStrength(log))
        XCTAssertEqual(s.status(s.plan[0]), .completedLogged)
        s.deleteStrength(s.strength[0])
        XCTAssertTrue(s.strength.isEmpty)
        XCTAssertEqual(s.status(s.plan[0]), .planned)
        XCTAssertFalse(s.plan[0].done)
        guard let toast = s.undoToast else { return XCTFail("an Undo toast is offered") }
        XCTAssertTrue(s.undoDelete(toast.id))
        XCTAssertEqual(s.strength.map { $0.id }, [log.id], "same id back, exactly once")
        XCTAssertEqual(s.status(s.plan[0]), .completedLogged)
        XCTAssertFalse(s.undoDelete(toast.id), "undo twice does nothing")
        XCTAssertEqual(s.strength.count, 1)
        // deleted items older than 30 days are purged
        s.deleteStrength(s.strength[0])
        s.purgeTrash(now: Date().addingTimeInterval(31 * 86_400))
        XCTAssertTrue(s.trash.isEmpty)
    }

    func testDeleteWorkoutUndoAndRevertToPlanned() {
        let s = store()
        let w = strengthWorkout(today)
        s.plan = [w]
        XCTAssertTrue(s.addStrength(StrengthSession(date: now, minutes: 30, focus: .fullBody, workoutId: w.id)))
        // revert keeping the log: session planned, log stays as an extra session (counted once, not linked)
        XCTAssertTrue(s.revertToPlanned(w.id, deleteLinkedLogs: false))
        XCTAssertEqual(s.status(s.plan[0]), .planned)
        XCTAssertEqual(s.strength.count, 1)
        XCTAssertEqual(s.strength[0].unplanned, true)
        XCTAssertEqual(s.ledger.lifting(weekOf: monday).completed, 1, "the extra session still counts once")
        // reopen without duplicating: a new log completes it; the extra one stays separate
        XCTAssertTrue(s.addStrength(StrengthSession(date: now.addingTimeInterval(3600), minutes: 45, focus: .fullBody, exercises: [ExerciseEntry(exercise: catalogue[1], sets: sets([8], kg: 20))], workoutId: w.id)))
        XCTAssertEqual(s.status(s.plan[0]), .completedLogged)
        XCTAssertEqual(s.ledger.lifting(weekOf: monday).completed, 2)
        // delete the planned session itself → Undo brings it back with its id
        s.deleteWorkout(s.plan[0])
        XCTAssertTrue(s.plan.isEmpty)
        XCTAssertTrue(s.undoDelete(s.undoToast!.id))
        XCTAssertEqual(s.plan.map { $0.id }, [w.id])
        XCTAssertEqual(s.status(s.plan[0]), .completedLogged)
    }

    func testManualCompletionConvertsToDetailedLogWithoutDuplicate() {
        let s = store()
        let w = strengthWorkout(today)
        s.plan = [w]
        XCTAssertTrue(s.markDone(w.id, minutes: 35))
        XCTAssertEqual(s.ledger.lifting(weekOf: monday).completed, 1)
        XCTAssertEqual(s.ledger.lifting(weekOf: monday).minutes, 35)
        // Add details → a detailed log for the same session replaces the manual mark
        XCTAssertNil(s.existingLog(forWorkout: w.id, on: now), "no log to duplicate")
        XCTAssertTrue(s.addStrength(StrengthSession(date: now, minutes: 38, focus: .fullBody, exercises: [ExerciseEntry(exercise: catalogue[1], sets: sets([10, 10], kg: 16))], workoutId: w.id)))
        XCTAssertEqual(s.status(s.plan[0]), .completedLogged)
        let wk = s.ledger.lifting(weekOf: monday)
        XCTAssertEqual(wk.completed, 1, "manual mark + detailed log of the same session count once")
        XCTAssertEqual(wk.minutes, 38)
        // a quick log is edited into a detailed one (same id)
        var q = StrengthSession(date: now.addingTimeInterval(7200), minutes: 20, focus: .upper); q.unplanned = true
        XCTAssertTrue(s.addStrength(q))
        var edited = s.strength.first { $0.id == q.id }!
        edited.exercises = [ExerciseEntry(exercise: catalogue[7], sets: sets([8, 8], kg: 20))]
        s.updateStrength(edited)
        XCTAssertTrue(s.strength.first { $0.id == q.id }!.isDetailed)
        // edit / delete a set
        edited.exercises![0].sets.removeLast()
        s.updateStrength(edited)
        XCTAssertEqual(s.strength.first { $0.id == q.id }!.setCount, 1)
    }

    // MARK: - 3. Migration (owner-like fixture), idempotent, originals kept in notes

    private func ownerFixture() -> StoreFile {
        var f = StoreFile(schema: 1, profile: hybridProfile())
        var tue = strengthWorkout(tomorrow); tue.done = true
        var past = strengthWorkout(cal.date(byAdding: .day, value: -2, to: today)!); past.done = true      // no log behind it
        var pastRide = Workout(date: cal.date(byAdding: .day, value: -1, to: today)!.addingTimeInterval(7 * 3600), kind: .endurance, minutes: 60); pastRide.done = true
        f.plan = [past, pastRide, tue]
        var zero = StrengthSession(date: now, minutes: 1, focus: .fullBody, workoutId: tue.id)
        zero.startedAt = now.addingTimeInterval(-40); zero.finishedAt = now
        f.strength = [zero]
        f.rides = [RideRecord(start: pastRide.date, durationS: 3600, distanceM: 24_000, recorder: .phone, sources: ["test"])]
        f.profile.ftpW = 225; f.profile.ftpHow = .tested
        return f
    }

    func testMigrationV2FixesOwnerDataAndKeepsOriginals() {
        let f0 = ownerFixture()
        let f = StoreFile.migrate(f0, now: now, calendar: cal)
        XCTAssertEqual(f.schema, 2)
        let tue = f.plan.first { cal.isDate($0.date, inSameDayAs: tomorrow) }!
        XCTAssertFalse(tue.done, "M1: completed for a future date → planned")
        XCTAssertTrue(tue.migrationNote?.contains("original: done = true") == true)
        let past = f.plan.first { $0.kind == .strength && $0.date < today }!
        XCTAssertFalse(past.done, "M3: no log behind the mark → planned")
        let ride = f.plan.first { $0.kind == .endurance }!
        XCTAssertTrue(ride.done); XCTAssertEqual(ride.completion, .recorded, "M3: a recorded ride backs it")
        let log = f.strength[0]
        XCTAssertEqual(log.needsReview, true, "M2: zero-set workout-mode save waits for review")
        XCTAssertEqual(log.minutes, 0, "a 1-minute timer artefact becomes 'not recorded'")
        XCTAssertTrue(log.migrationNote?.contains("original: 1 min") == true)
        XCTAssertNil(log.workoutId); XCTAssertEqual(log.unplanned, true)
        XCTAssertEqual(f.strength.count, 1, "never deletes")
        XCTAssertEqual(f.profile.ftpW, 225)
        XCTAssertFalse(f.migrationLog.isEmpty)
        // idempotent: a second run (and loading a schema-2 file) changes nothing
        XCTAssertEqual(StoreFile.migrate(f, now: now, calendar: cal), f)
        XCTAssertEqual(StoreFile.migrate(f, now: now.addingTimeInterval(86_400 * 3), calendar: cal), f)
    }

    func testMigratedOwnerStoreCountsTheSameOnEveryScreen() throws {
        let d = dir()
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        try enc.encode(ownerFixture()).write(to: d.appendingPathComponent("store.json"))
        let s = Store(directory: d, generatePlan: false)
        XCTAssertEqual(s.profile.ftpConfidence, .unverified, "M4: 'tested' without a test ride is unverified")
        func counts() -> [Int] {
            let home = HybridCoach.assess(profile: s.profile, plan: s.plan, rides: s.rides, strength: s.strength, availability: s.effectiveAvailability).strength?.sessionsDone ?? -1
            let progress = s.strengthWeekTotals(weeks: 1).last?.sessions ?? -1
            let chart = TrendChartMath.buckets(s.ledger, riding: false, weeks: 1, now: Date()).last?.sessions ?? -1
            let plan = s.ledger.lifting(weekOf: TrainingLedger.monday(of: Date())).completed
            let end = cal.date(byAdding: .day, value: 7, to: TrainingLedger.monday(of: Date()))!
            let history = Timeline.build(rides: s.rides, plan: s.plan, ftp: s.profile.ftpW, strength: s.strength).filter { $0.isStrength && ($0.status == .completed || $0.status == .imported) && $0.date >= TrainingLedger.monday(of: Date()) && $0.date < end }.count
            return [home, progress, chart, plan, history]
        }
        XCTAssertEqual(counts(), [0, 0, 0, 0, 0], "a record waiting for review counts nowhere")
        XCTAssertEqual(s.status(s.plan.first { cal.isDate($0.date, inSameDayAs: tomorrow) }!), .planned)
        s.confirmReviewed(s.strength[0].id)
        XCTAssertEqual(counts(), [1, 1, 1, 1, 1], "confirmed → counted once, everywhere")
        XCTAssertEqual(s.status(s.plan.first { cal.isDate($0.date, inSameDayAs: tomorrow) }!), .planned, "and still never completes tomorrow's session")
        // reload: schema 2 on disk, nothing migrates twice
        let again = Store(directory: d, generatePlan: false)
        XCTAssertEqual(again.strength.count, 1); XCTAssertNil(again.strength[0].needsReview)
    }

    // MARK: - 4. Personalised planner

    func testDifferentProfilesGetDifferentPrograms() {
        var beginnerCyclist = hybridProfile(); beginnerCyclist.priority = .cycling
        var bp = StrengthPrefs(); bp.experience = .beginner; bp.goal = .enduranceSupport
        var lifter = hybridProfile(); lifter.trainingMode = .strength
        var lp = StrengthPrefs(); lp.experience = .advanced; lp.goal = .strength
        let w = strengthWorkout(today, minutes: 60)
        let a = StrengthPlanner.build(for: w, ctx: ctx(profile: beginnerCyclist, prefs: bp, plan: [w]))
        let b = StrengthPlanner.build(for: w, ctx: ctx(profile: lifter, prefs: lp, plan: [w]))
        XCTAssertFalse(a.entries.isEmpty); XCTAssertFalse(b.entries.isEmpty)
        func shape(_ e: [ExerciseEntry]) -> [String] { e.map { "\($0.exerciseId):\($0.sets.count)x\($0.sets.first?.reps ?? 0)" } }
        XCTAssertNotEqual(shape(a.entries), shape(b.entries))
        XCTAssertNotEqual(a.rationale.goal, b.rationale.goal)
        // strength goal: main lift in a low rep range; endurance-support beginner: not below 6 reps
        XCTAssertLessThanOrEqual(b.entries[0].sets.first!.reps, 6)
        XCTAssertGreaterThanOrEqual(a.entries[0].sets.first!.reps, 6)
        // every exercise has a "Why?" record
        XCTAssertEqual(Set(a.rationale.exercises.map { $0.exerciseId }), Set(a.entries.map { $0.exerciseId }))
    }

    func testEquipmentIsRespectedIncludingCustomItems() {
        let w = strengthWorkout(today, minutes: 60)
        let b = StrengthPlanner.build(for: w, ctx: ctx(owned: ["dumbbells", "bench"], plan: [w]))
        XCTAssertFalse(b.entries.isEmpty)
        let used = b.entries.map { e in catalogue.first { $0.id == e.exerciseId }! }
        XCTAssertTrue(used.allSatisfy { !$0.equipment.contains("barbell") && !$0.equipment.contains("pull-up bar") }, "\(used.map { $0.name })")
        // a custom item counts as owned for an exercise that needs it
        var c = ctx(owned: ["sandbag"], plan: [w]); c.catalogue.append(ex("q-sandbag", "Sandbag squat", ["sandbag"], .squat, ["quads", "glutes"]))
        XCTAssertTrue(StrengthPlanner.available(c.catalogue.last!, ctx: c))
        XCTAssertFalse(StrengthPlanner.available(catalogue[0], ctx: c), "barbell not owned")
    }

    func testFixedDaysSessionTypesAndOwnRoutinesAreKept() {
        let s = store()
        var p = hybridProfile(); p.strengthSplit = .fullBody
        s.profile = p
        s.customExercises = catalogue
        var fixed = strengthWorkout(tomorrow, focus: .upper); fixed.fixed = true; fixed.plannedEntries = nil
        var mine = strengthWorkout(cal.date(byAdding: .day, value: 2, to: today)!, focus: .lower)
        let own = [ExerciseEntry(exercise: catalogue[0], sets: sets([5, 5, 5], kg: 60))]
        mine.plannedEntries = own; mine.edited = true
        s.plan = [fixed, mine]
        s.refreshGeneratedSessions(now: now)
        let f = s.plan.first { $0.id == fixed.id }!
        XCTAssertEqual(f.date, fixed.date); XCTAssertEqual(f.strengthFocus, .upper); XCTAssertTrue(f.fixed)
        XCTAssertTrue(f.generatedEntries)
        XCTAssertTrue(f.plannedEntries?.allSatisfy { e in ExerciseLibrary.meta(s.allExercises.first { $0.id == e.exerciseId }!).slot.isLower == false } == true, "an upper session stays upper")
        XCTAssertTrue(f.rationale?.notes.contains { $0.contains("Fixed day") } == true)
        XCTAssertEqual(s.plan.first { $0.id == mine.id }!.plannedEntries, own, "the rider's own edits are never rebuilt")
    }

    func testInterferenceKeyRideNextDayAndHighCyclingLoad() {
        let w = strengthWorkout(today, minutes: 60, focus: .lower)
        var inter = StrengthPrefs(); inter.experience = .intermediate
        let calm = StrengthPlanner.build(for: w, ctx: ctx(prefs: inter, plan: [w]))
        let key = Workout(date: tomorrow.addingTimeInterval(7 * 3600), kind: .threshold, minutes: 70)
        let before = StrengthPlanner.build(for: w, ctx: ctx(prefs: inter, plan: [w, key]))
        func lowerSets(_ b: StrengthPlanner.Built) -> Int { b.entries.filter { e in ExerciseLibrary.meta(catalogue.first { $0.id == e.exerciseId }!).slot.isLower }.reduce(0) { $0 + $1.sets.count } }
        XCTAssertLessThan(lowerSets(before), lowerSets(calm), "no heavy lower body the day before a key ride")
        XCTAssertTrue(before.rationale.exercises.contains { ($0.cycling ?? "").contains("key ride") })
        XCTAssertTrue(before.rationale.exercises.filter { $0.cycling != nil }.allSatisfy { ($0.targetRPE ?? 10) <= 6 })
        // the day after a long ride (recorded) → light legs too
        var c = ctx(prefs: inter, plan: [w]); c.rides = [RideRecord(start: cal.date(byAdding: .day, value: -1, to: today)!.addingTimeInterval(8 * 3600), durationS: 3 * 3600, distanceM: 80_000, recorder: .phone, sources: ["t"])]
        let after = StrengthPlanner.build(for: w, ctx: c)
        XCTAssertLessThan(lowerSets(after), lowerSets(calm))
        // two hard rides planned this week → less lower-body volume (and said so)
        let wkStart = TrainingLedger.monday(of: today)
        let hard1 = Workout(date: wkStart.addingTimeInterval(7 * 3600), kind: .vo2, minutes: 60), hard2 = Workout(date: cal.date(byAdding: .day, value: 6, to: wkStart)!.addingTimeInterval(7 * 3600), kind: .tempo, minutes: 75)
        let wc = StrengthPlanner.weekContext(for: w, ctx: ctx(plan: [w, hard1, hard2]))
        XCTAssertTrue(wc.highCyclingLoad)
        let calmSets = StrengthPlanner.weeklySets(region: "lower", ctx: ctx(plan: [w]), week: StrengthPlanner.weekContext(for: w, ctx: ctx(plan: [w])))
        XCTAssertLessThan(StrengthPlanner.weeklySets(region: "lower", ctx: ctx(plan: [w, hard1, hard2]), week: wc), calmSets)
    }

    func testProgressionOnlyFromLoggedSetsOfTheSameExercise() {
        let goblet = catalogue[1], dbBench = catalogue[7], bench = catalogue[6]
        let old = cal.date(byAdding: .day, value: -3, to: now)!
        let logs = [StrengthSession(date: old, minutes: 40, focus: .fullBody, rpe: 7, exercises: [
            ExerciseEntry(exercise: goblet, sets: sets([10, 10, 10], kg: 24, rpe: 7)),
            ExerciseEntry(exercise: bench, sets: sets([8, 8, 8], kg: 60, rpe: 7))])]
        let c = ctx(logs: logs)
        let up = StrengthPlanner.prescribeLoad(goblet, meta: ExerciseLibrary.meta(goblet), reps: 6...10, sets: 3, painBlocked: false, ctx: c)
        XCTAssertEqual(up.weight, 25); XCTAssertEqual(up.reps, 6); XCTAssertTrue(up.progressed)
        // never transferred: dumbbell bench has no logs of its own even though the barbell bench has
        let fresh = StrengthPlanner.prescribeLoad(dbBench, meta: ExerciseLibrary.meta(dbBench), reps: 8...12, sets: 3, painBlocked: false, ctx: c)
        XCTAssertNil(fresh.weight); XCTAssertFalse(fresh.progressed)
        XCTAssertTrue(fresh.why.contains("No weight is copied"))
        // quick logs / marked sessions carry no sets → nothing to progress from
        let quick = ctx(logs: [StrengthSession(date: old, minutes: 40, focus: .fullBody, rpe: 6)])
        XCTAssertNil(StrengthPlanner.prescribeLoad(goblet, meta: ExerciseLibrary.meta(goblet), reps: 6...10, sets: 3, painBlocked: false, ctx: quick).weight)
        // pain → held, not progressed
        let held = StrengthPlanner.prescribeLoad(goblet, meta: ExerciseLibrary.meta(goblet), reps: 6...10, sets: 3, painBlocked: true, ctx: c)
        XCTAssertEqual(held.weight, 24); XCTAssertFalse(held.progressed)
    }

    func testPainRestrictionsExcludeLoadingPatterns() {
        let w = strengthWorkout(today, minutes: 60)
        let b = StrengthPlanner.build(for: w, ctx: ctx(plan: [w], pain: [.knees]))
        XCTAssertFalse(b.entries.isEmpty)
        for e in b.entries { XCTAssertFalse(ExerciseLibrary.meta(catalogue.first { $0.id == e.exerciseId }!).tags.contains(.kneeFlexion), e.name) }
        XCTAssertTrue(b.rationale.notes.contains { $0.contains("pain") })
    }

    // MARK: - 5. Swaps and persistent preferences

    func testSwapAlternativesUseAvailableEquipmentOnly() {
        let w = strengthWorkout(today, minutes: 60)
        let c = ctx(owned: ["dumbbell", "bench"], plan: [w])
        let entry = ExerciseEntry(exercise: catalogue[6], sets: sets([8, 8, 8], kg: 60))   // barbell bench
        let alts = StrengthPlanner.alternatives(for: entry, in: w, entries: [entry], ctx: c)
        XCTAssertFalse(alts.isEmpty)
        XCTAssertTrue(alts.allSatisfy { c.equipment.canDo($0.exercise) })
        XCTAssertEqual(alts.first?.exercise.id, "q-dbbench", "same movement, same muscles first")
        // the replacement keeps sets and reps, never the old exercise's weight
        let swapped = StrengthPlanner.swappedEntry(old: entry, to: alts[0].exercise, ctx: c)
        XCTAssertEqual(swapped.sets.count, 3); XCTAssertEqual(swapped.sets.map { $0.reps }, [8, 8, 8])
        XCTAssertTrue(swapped.sets.allSatisfy { $0.weightKg == nil })
    }

    func testSwapReasonsPersistAndShapeFuturePlans() {
        let d = dir()
        let s = store(d)
        var p = hybridProfile(); p.strengthSplit = .fullBody
        s.profile = p
        s.customExercises = catalogue
        let goblet = catalogue[1], split = catalogue[2]
        var w = strengthWorkout(today); w.plannedEntries = [ExerciseEntry(exercise: goblet, sets: sets([10, 10, 10], kg: 16))]
        s.plan = [w]
        let entryId = w.plannedEntries![0].id
        // always prefer
        XCTAssertNotNil(s.applySwap(workoutId: w.id, entryId: entryId, to: split, reason: .alwaysPrefer))
        XCTAssertEqual(s.strengthPrefs.alwaysPrefer[goblet.id], split.id)
        XCTAssertEqual(s.plan[0].plannedEntries?.first?.exerciseId, split.id)
        XCTAssertTrue(s.plan[0].edited, "the rider's choice for this session is kept")
        let reloaded = Store(directory: d, generatePlan: false)
        XCTAssertEqual(reloaded.strengthPrefs.alwaysPrefer[goblet.id], split.id, "persisted")
        // discomfort: excluded, similar movements flagged, never diagnosed
        let msg = s.applySwap(workoutId: w.id, entryId: s.plan[0].plannedEntries![0].id, to: catalogue[5], reason: .discomfort) ?? ""
        XCTAssertTrue(s.strengthPrefs.avoids(split.id))
        XCTAssertTrue(msg.contains("doctor or physiotherapist"))
        XCTAssertFalse(StrengthPlanner.available(split, ctx: s.plannerContext(now: now)))
        // temporarily unavailable: blocked for 3 sessions, then available again
        var w2 = strengthWorkout(today); w2.plannedEntries = [ExerciseEntry(exercise: catalogue[7], sets: sets([8], kg: 20))]
        s.plan.append(w2)
        _ = s.applySwap(workoutId: w2.id, entryId: w2.plannedEntries![0].id, to: catalogue[8], reason: .temporarilyUnavailable, sessions: 1)
        XCTAssertTrue(s.strengthPrefs.blocked(catalogue[7].id, now: now))
        s.consumeTemporaryBlocks(now: now)
        XCTAssertFalse(s.strengthPrefs.blocked(catalogue[7].id, now: now))
        // no equipment: removed from the equipment profile
        s.equipment = EquipmentProfile(owned: ["dumbbell", "barbell", "bench"])
        var w3 = strengthWorkout(today); w3.plannedEntries = [ExerciseEntry(exercise: catalogue[11], sets: sets([8], kg: 40))]
        s.plan.append(w3)
        _ = s.applySwap(workoutId: w3.id, entryId: w3.plannedEntries![0].id, to: catalogue[12], reason: .noEquipment)
        XCTAssertFalse(s.equipment.owned.contains("barbell"))
        XCTAssertTrue(s.equipment.owned.contains("dumbbell"))
    }

    func testAlwaysPreferChangesThePlannerPick() {
        let w = strengthWorkout(today, minutes: 60)
        let first = StrengthPlanner.build(for: w, ctx: ctx(plan: [w]))
        let x = first.entries[0].exerciseId
        let alt = StrengthPlanner.alternatives(for: first.entries[0], in: w, entries: first.entries, ctx: ctx(plan: [w]))[0].exercise.id
        var prefs = StrengthPrefs(); prefs.alwaysPrefer[x] = alt
        let second = StrengthPlanner.build(for: w, ctx: ctx(prefs: prefs, plan: [w]))
        XCTAssertTrue(second.entries.contains { $0.exerciseId == alt })
        XCTAssertFalse(second.entries.contains { $0.exerciseId == x })
    }

    // MARK: - 6. FTP confidence labels

    func testFTPConfidenceLabels() {
        var p = RiderProfile()
        XCTAssertEqual(p.ftpConfidence, .provisional); XCTAssertEqual(p.ftpLabel, "Provisional estimate")
        p.ftpHow = .tested
        XCTAssertEqual(p.ftpConfidence, .unverified, "'tested' without a recorded structured test is not verified")
        p.ftpVerifiedTest = true
        XCTAssertEqual(p.ftpConfidence, .verifiedTest); XCTAssertEqual(p.ftpLabel, "Verified test")
        p.ftpHow = .fromRides; p.ftpVerifiedTest = nil; p.ftpPowerVerified = false
        XCTAssertEqual(p.ftpConfidence, .unverified)
        XCTAssertFalse(p.ftpSourceText.lowercased().contains("tested"))
        p.ftpPowerVerified = true
        XCTAssertEqual(p.ftpConfidence, .estimatedVerified); XCTAssertEqual(p.ftpLabel, "Estimated from verified power data")
        XCTAssertTrue(p.ftpSourceText.contains("not a test"))
        // unverified power never drives confident prescriptions: conservative zones + a caution
        p.ftpW = 225; p.ftpPowerVerified = false
        XCTAssertEqual(p.prescriptionFTP, 214); XCTAssertNotNil(p.ftpCaution)
        XCTAssertLessThan(p.prescriptionZones[3].lo, p.powerZones[3].lo)
        p.ftpPowerVerified = true
        XCTAssertEqual(p.prescriptionFTP, 225); XCTAssertNil(p.ftpCaution)
    }

    func testAcceptingASuggestionIsOnlyVerifiedFromAVerifiedTestRide() {
        let s = store()
        s.ftpSuggestion = FTPSuggestion(watts: 240, best20: 253, best60: nil, rideId: UUID(), rideDate: now, previousFTP: 225)
        s.acceptFTPSuggestion()
        XCTAssertEqual(s.profile.ftpHow, .fromRides); XCTAssertEqual(s.profile.ftpConfidence, .unverified)
        var sug = FTPSuggestion(watts: 245, best20: 258, best60: nil, rideId: UUID(), rideDate: now, previousFTP: 240)
        sug.powerVerified = true; sug.testProtocol = true
        s.ftpSuggestion = sug
        s.acceptFTPSuggestion()
        XCTAssertEqual(s.profile.ftpConfidence, .verifiedTest)
    }

    // MARK: - 7. Weekly chart maths (bucketing, visible range, selection, labels)

    func testChartBucketsVisibleRangeAndSelection() {
        let s = store()
        let m0 = TrainingLedger.monday(of: Date())
        let m1 = cal.date(byAdding: .day, value: -7, to: m0)!
        s.rides = [RideRecord(start: m1.addingTimeInterval(9 * 3600), durationS: 3600, distanceM: 30_000, recorder: .phone, sources: ["t"]),
                   RideRecord(start: m1.addingTimeInterval(2 * 86_400 + 9 * 3600), durationS: 65 * 60, distanceM: 30_000, recorder: .phone, sources: ["t"]),
                   RideRecord(start: m0.addingTimeInterval(9 * 3600), durationS: 30 * 60, distanceM: 10_000, recorder: .phone, sources: ["t"])]
        let b = TrendChartMath.buckets(s.ledger, riding: true, weeks: 20, now: Date())
        XCTAssertEqual(b.count, 20)
        XCTAssertEqual(b.last?.start, m0)
        XCTAssertEqual(b[18].minutes, 125); XCTAssertEqual(b[18].sessions, 2); XCTAssertEqual(b[18].km, 60, accuracy: 0.01)
        XCTAssertEqual(b[19].minutes, 30)
        // opens on the most recent weeks; the header aggregates exactly the visible weeks
        let start = TrendChartMath.initialScrollStart(b, weeks: 8)
        let vis = TrendChartMath.visible(b, scrollStart: start, weeks: 8)
        XCTAssertEqual(vis.count, 8); XCTAssertEqual(vis.last?.start, m0)
        let sum = TrendChartMath.summary(vis)
        XCTAssertEqual(sum.totalMinutes, 155); XCTAssertEqual(sum.sessions, 3); XCTAssertEqual(sum.averageMinutes, 19)
        // scrolling back one week drops the newest week from the aggregate (mid-week positions snap to Mondays)
        let back = TrendChartMath.visible(b, scrollStart: cal.date(byAdding: .day, value: -7, to: start)!.addingTimeInterval(3600), weeks: 8)
        XCTAssertEqual(back.last?.start, m1); XCTAssertEqual(TrendChartMath.summary(back).totalMinutes, 125)
        // selection: any instant inside a week selects that week; the callout says exactly what it is
        let sel = TrendChartMath.bucket(at: m1.addingTimeInterval(3 * 86_400 + 5), in: b)
        XCTAssertEqual(sel?.start, m1)
        let text = TrendChartMath.callout(sel!, singular: "ride", plural: "rides")
        XCTAssertTrue(text.hasSuffix("· 2 h 05 min · 2 rides"), text)
        XCTAssertNil(TrendChartMath.bucket(at: cal.date(byAdding: .day, value: 400, to: m0), in: b))
    }

    func testChartLabelsNeverCrowd() {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_GB"); f.dateFormat = "yyyy-MM-dd"
        XCTAssertEqual(TrendChartMath.rangeText(f.date(from: "2026-10-12")!, f.date(from: "2026-10-18")!, now: f.date(from: "2026-10-26")!), "12–18 Oct")
        XCTAssertEqual(TrendChartMath.rangeText(f.date(from: "2026-09-28")!, f.date(from: "2026-10-04")!, now: f.date(from: "2026-10-26")!), "28 Sep – 4 Oct")
        XCTAssertEqual(TrendChartMath.rangeText(f.date(from: "2025-12-29")!, f.date(from: "2026-01-04")!, now: f.date(from: "2026-10-26")!), "29 Dec 2025 – 4 Jan 2026")
        XCTAssertEqual(TrendChartMath.clock(125), "2 h 05 min"); XCTAssertEqual(TrendChartMath.clock(45), "45 min")
        let b = (0..<104).map { WeekBucket(start: cal.date(byAdding: .day, value: -7 * (103 - $0), to: TrainingLedger.monday(of: Date()))!, minutes: 0, sessions: 0) }
        for r in ChartRange.allCases {
            for ax in [false, true] {
                let n = r.labelStride(accessibility: ax)
                let labels = TrendChartMath.labelDates(b, stride: n)
                XCTAssertEqual(labels.last, b.last?.start, "the newest week is always labelled")
                // at most 5 labels (6 at the 1-year range) in any visible window: "12 Oct" labels never overlap
                let perWindow = Int((Double(r.weeks) / Double(n)).rounded(.up))
                XCTAssertLessThanOrEqual(perWindow, ax ? 3 : 5, "\(r) ax=\(ax)")
                XCTAssertTrue(zip(labels, labels.dropFirst()).allSatisfy { cal.dateComponents([.day], from: $0, to: $1).day! >= 7 * n - 1 })
            }
        }
    }
}
