import XCTest
@testable import BikeComputer

/// Owner-approved repair (5 Nov 2026): the plan's own coach-built sessions — onboarding approval and missing-week
/// generation — go through the validated strength path, so the stored superset preference is honoured as a strong
/// preference (the existing pairing rule may decline), the validator's duration model applies, and a declined
/// preference is explained truthfully. Nothing here hard-codes exercises or pairings.
final class SupersetPipelineTests: XCTestCase {
    private let cal = Calendar.current
    private func store() -> Store {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("ss-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return Store(directory: d, generatePlan: false)
    }
    private func day(_ sport: DayAssignment.Sport?, _ minutes: Int = 0) -> DayAvailability {
        guard let s = sport else { return DayAvailability(activity: .rest, minutes: 0) }
        return DayAvailability(assignments: [DayAssignment(sport: s, minutes: minutes)])
    }
    /// The owner's situation: hybrid, intermediate lifter, gym, three 30-minute full-body sessions, supersets on.
    private func owner(_ s: Store, supersets: Bool?) {
        var p = RiderProfile.screened(); p.trainingMode = .hybrid; p.priority = .balanced; p.hoursPerWeek = 2; p.liftingHoursPerWeek = 1
        p.cyclingDaysPerWeek = 2; p.liftDaysPerWeek = 3; p.weekIsExplicit = true; p.goal = .endurance
        s.profile = p
        s.strengthPrefs.experience = .intermediate; s.strengthPrefs.prefersSupersets = supersets
        s.equipment = EquipmentPreset.gym.apply(to: s.equipment)
        s.availability = WeeklyAvailability(days: [day(.strength, 30), day(.cycling, 60), day(.strength, 30), day(nil), day(.strength, 30), day(.cycling, 60), day(nil)])
    }
    private var nextMonday: Date { cal.date(byAdding: .day, value: 7, to: TrainingLedger.monday(of: Date()))! }
    /// The real approval path: Store.regenerate → PlanEngine.week → applyWeekdayRoutines → programmedSession.
    private func approve(_ s: Store) -> [Workout] {
        _ = s.regenerate(weekOf: nextMonday, replaceEdited: true)
        return s.plan.filter { $0.kind == .strength && $0.date >= nextMonday }
    }
    private func isLower(_ e: ExerciseEntry, _ s: Store) -> Bool { PrescriptionRepair.isLowerEx(e, s.allExercises) }
    private func gripLimited(_ e: ExerciseEntry, _ s: Store) -> Bool { s.allExercises.first { $0.id == e.exerciseId }.map { ExerciseLibrary.gripLimited($0) } ?? false }
    private func groups(_ es: [ExerciseEntry]) -> [String: [ExerciseEntry]] { Dictionary(grouping: es.filter { $0.superset != nil }, by: { $0.superset! }) }
    /// Whether the existing pairing rule can pair anything in this list (the rule itself decides; the test only asks it).
    private func pairable(_ es: [ExerciseEntry], _ s: Store) -> Bool {
        var copy = es.map { e -> ExerciseEntry in var x = e; x.superset = nil; return x }
        var rats: [ExerciseRationale] = []
        return PrescriptionRepair.pairSupersets(&copy, rats: &rats, catalogue: s.allExercises)
    }

    // MARK: the approval path

    func testApprovalWithSupersetsOnPairsWhereTheRuleAllows() {
        let s = store(); owner(s, supersets: true)
        let lifts = approve(s)
        XCTAssertEqual(lifts.count, 3)
        var pairedSessions = 0
        for l in lifts {
            let es = s.plannedEntries(for: l)
            XCTAssertFalse(es.isEmpty, "a coach-built prescription")
            XCTAssertEqual(l.minutes, 30, "the athlete's duration is never increased")
            let g = groups(es)
            if pairable(es, s) {
                XCTAssertFalse(g.isEmpty, "the rule found a compatible pair, so the preference is honoured: \(es.map(\.exerciseId))")
            } else {
                XCTAssertTrue(l.rationale?.notes.contains { $0.hasPrefix("You prefer supersets") } == true, "declined preference is explained: \(l.rationale?.notes ?? [])")
            }
            if !g.isEmpty { pairedSessions += 1 }
            // every group is a safe pair: two members, lower with upper, never two grip-limited lifts
            for (letter, members) in g {
                XCTAssertEqual(members.count, 2, "superset \(letter) has two members")
                XCTAssertNotEqual(isLower(members[0], s), isLower(members[1], s), "superset \(letter) pairs lower with upper: \(members.map(\.exerciseId))")
                XCTAssertFalse(gripLimited(members[0], s) && gripLimited(members[1], s), "superset \(letter) never pairs two grip-limited lifts")
            }
            // the validated duration model holds for the athlete's own minutes (TIME-001), with its full warm-up
            let ctx = s.plannerContext()
            let report = WorkoutValidator.validate(l, entries: es, rationale: l.rationale, context: ValidationContext(planner: ctx, prefersSupersets: true))
            XCTAssertFalse(report.has("TIME-001"), "fits \(l.minutes) min by the validator's model: \(report.issues.map(\.ruleId))")
            XCTAssertLessThanOrEqual(DurationModel().minutes(es, catalogue: s.allExercises), Double(l.minutes) - 1 + 0.001)
            XCTAssertEqual(DurationModel().warmUp, 180, "the validator's warm-up is the one the session was fitted with")
            XCTAssertTrue(l.rationale?.notes.first?.hasPrefix("Planned by the coach:") == true, "the explanation names who planned it: \(l.rationale?.notes.first ?? "")")
        }
        XCTAssertGreaterThan(pairedSessions, 0, "with a gym and three full-body sessions at least one session pairs")
    }

    func testApprovalWithSupersetsOffPairsNothing() {
        let s = store(); owner(s, supersets: false)
        for l in approve(s) {
            let es = s.plannedEntries(for: l)
            XCTAssertFalse(es.isEmpty)
            XCTAssertTrue(es.allSatisfy { $0.superset == nil }, "no pairing when the athlete said no: \(es.compactMap(\.superset))")
            XCTAssertFalse(l.rationale?.notes.contains { $0.hasPrefix("You prefer supersets") } == true)
            let report = WorkoutValidator.validate(l, entries: es, rationale: l.rationale, context: ValidationContext(planner: s.plannerContext(), prefersSupersets: false))
            XCTAssertFalse(report.has("TIME-001"))
        }
    }

    func testPreferenceNotStatedPairsNothing() {
        let s = store(); owner(s, supersets: nil)
        for l in approve(s) { XCTAssertTrue(s.plannedEntries(for: l).allSatisfy { $0.superset == nil }, "supersets only when the athlete asks") }
    }

    // MARK: missing-week generation

    func testMissingWeekGenerationRespectsThePreference() {
        let s = store(); owner(s, supersets: true)
        // the week after next does not exist yet: ensurePlan at that time generates it through the same path
        let later = cal.date(byAdding: .day, value: 14, to: nextMonday)!
        s.ensurePlan(now: later)
        let lifts = s.plan.filter { $0.kind == .strength && $0.date >= later && $0.date < cal.date(byAdding: .day, value: 7, to: later)! }
        XCTAssertEqual(lifts.count, 3, "the missing week was generated")
        var paired = 0
        for l in lifts {
            let es = s.plannedEntries(for: l)
            if pairable(es, s) { XCTAssertFalse(groups(es).isEmpty); paired += 1 }
            else { XCTAssertTrue(l.rationale?.notes.contains { $0.hasPrefix("You prefer supersets") } == true) }
        }
        XCTAssertGreaterThan(paired, 0)
    }

    // MARK: preservation

    func testAthleteModifiedAndCompletedSessionsAreNeverRewritten() {
        let s = store(); owner(s, supersets: nil)
        var lifts = approve(s)
        XCTAssertEqual(lifts.count, 3)
        // one hand-edited, one done, one with a recorded choice — then the preference changes and the week is regenerated
        lifts[0].entriesHandEdited = true; lifts[0].edited = true; lifts[0].plannedEntries = [lifts[0].plannedEntries!.first!]
        lifts[1].done = true
        lifts[2].riderChoice = RiderChoice(focus: nil, minutes: 30, prefersSupersets: nil, at: Date(), origin: "athlete", fromFocus: nil, fromMinutes: nil)
        for l in lifts { s.update(l) }
        s.strengthPrefs.prefersSupersets = true
        s.refreshGeneratedSessions(now: Date())
        var after = s.plan.filter { $0.kind == .strength && $0.date >= nextMonday }
        XCTAssertEqual(after.first { $0.id == lifts[0].id }?.plannedEntries?.count, 1, "the hand-edited list is kept")
        XCTAssertEqual(after.first { $0.id == lifts[1].id }?.plannedEntries, lifts[1].plannedEntries, "the completed session is kept")
        XCTAssertEqual(after.first { $0.id == lifts[2].id }?.plannedEntries?.compactMap(\.superset).count, 0, "a recorded choice without supersets still wins (left for a separate review)")
        // a week regenerated without replacing edits keeps the hand-edited and completed sessions too
        _ = s.regenerate(weekOf: nextMonday, replaceEdited: false)
        after = s.plan.filter { $0.kind == .strength && $0.date >= nextMonday }
        XCTAssertEqual(after.first { $0.id == lifts[0].id }?.plannedEntries?.count, 1, "the hand-edited list survives regeneration")
        XCTAssertEqual(after.first { $0.id == lifts[1].id }?.plannedEntries, lifts[1].plannedEntries, "the completed session survives regeneration")
    }

    // MARK: explanations

    func testAbsenceReasonNamesTheActualRule() {
        let s = store(); owner(s, supersets: true)
        let cat = s.allExercises
        func entry(_ name: String) -> ExerciseEntry? { cat.first { $0.name.lowercased() == name }.map { ExerciseEntry(exercise: $0, sets: [SetEntry(reps: 5)]) } }
        guard let dl = entry("conventional deadlift") ?? cat.first(where: { $0.name.lowercased().contains("deadlift") }).map({ ExerciseEntry(exercise: $0, sets: [SetEntry(reps: 5)]) }),
              let row = cat.first(where: { ExerciseLibrary.meta($0).slot == .horizontalPull }).map({ ExerciseEntry(exercise: $0, sets: [SetEntry(reps: 8)]) }),
              let sq = cat.first(where: { ExerciseLibrary.meta($0).slot == .squat && !ExerciseLibrary.gripLimited($0) }).map({ ExerciseEntry(exercise: $0, sets: [SetEntry(reps: 5)]) }) else { return XCTFail("catalogue") }
        XCTAssertTrue(PrescriptionRepair.supersetAbsenceReason([dl, row], catalogue: cat).contains("grip-limited"))
        XCTAssertTrue(PrescriptionRepair.supersetAbsenceReason([sq], catalogue: cat).contains("two exercises"))
        XCTAssertTrue(PrescriptionRepair.supersetAbsenceReason([sq, dl], catalogue: cat).contains("only lower-body"))
    }

    func testWhyTextUsesTheStrengthGoalAndLiftingExperience() {
        let s = store(); owner(s, supersets: true)
        let lifts = approve(s)
        let why = Coach.why(lifts.first, store: s)
        XCTAssertTrue(why.contains("Strength goal:"), why)
        XCTAssertTrue(why.contains("lifting experience: some lifting experience"), why)
        XCTAssertFalse(why.contains("Goal: ride longer"), "the cycling goal and level are not used for a strength session: \(why)")
        let ride = s.plan.first { $0.kind.isRide }
        XCTAssertTrue(Coach.why(ride, store: s).contains("Goal: "), "rides keep their line: \(Coach.why(ride, store: s))")
    }
}
