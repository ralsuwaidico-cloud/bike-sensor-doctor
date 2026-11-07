import XCTest
@testable import BikeComputer

/// APP-035: a coach-built strength session with no eligible exercise explains why (neutral, counted from the same rules
/// the planner applies) and is never silently "filled"; a session the planner fills gets no warning.
final class EmptyStrengthSessionTests: XCTestCase {
    private let cal = Calendar.current
    private var now: Date { cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())! }
    private func ex(_ id: String, _ name: String, _ eq: [String], _ p: MovementPattern) -> Exercise {
        Exercise(id: id, name: name, equipment: eq, pattern: p, muscles: [], unilateral: false, custom: true)
    }
    private var catalogue: [Exercise] {
        [ex("squat", "Back squat", ["barbell"], .squat), ex("goblet", "Goblet squat", ["dumbbell", "kettlebell"], .squat),
         ex("rdl", "Romanian deadlift", ["barbell"], .hinge), ex("bench", "Bench press", ["barbell", "bench"], .push),
         ex("pushup", "Push-up", ["bodyweight"], .push), ex("row", "Barbell row", ["barbell"], .pull),
         ex("pullup", "Pull-up", ["pull-up bar"], .pull), ex("plank", "Plank", ["bodyweight"], .core)]
    }
    private func profile() -> RiderProfile {
        var p = RiderProfile.screened(); p.name = "Test"; p.trainingMode = .hybrid; p.priority = .balanced; p.hoursPerWeek = 5; p.liftingHoursPerWeek = 2
        p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 2
        return p
    }
    private func ctx(equipment: EquipmentProfile, prefs: StrengthPrefs = StrengthPrefs(), pain: [PainArea] = []) -> PlannerContext {
        PlannerContext(profile: profile(), prefs: prefs, equipment: equipment, catalogue: catalogue, painAreas: pain, now: now, calendar: cal)
    }
    private var session: Workout { Workout(date: now, kind: .strength, minutes: 45, strengthFocus: .fullBody) }

    func testFilledSessionHasNoWarning() {
        let c = ctx(equipment: EquipmentProfile(owned: ["barbell", "bench", "dumbbell", "pull-up bar"], confirmed: true))
        XCTAssertFalse(StrengthPlanner.build(for: session, ctx: c).entries.isEmpty, "fixture: the planner fills a full-body session")
        XCTAssertNil(EmptyStrengthCheck.check(session, ctx: c))
        XCTAssertTrue(EmptyStrengthCheck.warnings(for: [session], ctx: c).isEmpty)
    }

    func testEverythingAvoidedExplainsTheAvoidedList() {
        var prefs = StrengthPrefs()
        prefs.avoid = catalogue.map { AvoidEntry(exerciseId: $0.id, reason: .discomfort, at: now) }
        let c = ctx(equipment: EquipmentProfile(owned: ["barbell", "bench", "dumbbell", "pull-up bar"], confirmed: true), prefs: prefs)
        let f = EmptyStrengthCheck.check(session, ctx: c)
        XCTAssertNotNil(f)
        XCTAssertEqual(f?.avoided, 8); XCTAssertEqual(f?.eligible, 0)
        XCTAssertTrue(f?.suggestsAvoided ?? false); XCTAssertFalse(f?.suggestsEquipment ?? true)
        XCTAssertTrue(f?.text.contains("8 on your Avoided list") ?? false, f?.text ?? "")
        XCTAssertTrue(f?.text.contains("None is left") ?? false)
    }

    func testEquipmentNotSetLeavesBodyweightOnlyAndSaysSo() {
        // equipment never set → only bodyweight exercises are plannable (push-up, plank): the slots cannot all be filled
        let c = ctx(equipment: EquipmentProfile())
        let f = EmptyStrengthCheck.explain(focus: "full body", ctx: c)
        XCTAssertEqual(f.noEquipment, 6); XCTAssertEqual(f.eligible, 2); XCTAssertFalse(f.equipmentSet)
        XCTAssertTrue(f.text.contains("yours is not set, so only bodyweight"), f.text)
        XCTAssertTrue(f.suggestsEquipment)
    }

    func testOwnedEquipmentCountsOnlyWhatIsMissing() {
        let c = ctx(equipment: EquipmentProfile(owned: ["dumbbell"], confirmed: true))
        let f = EmptyStrengthCheck.explain(focus: "full body", ctx: c)
        XCTAssertEqual(f.noEquipment, 5, "barbell / bench / pull-up bar exercises")
        XCTAssertEqual(f.eligible, 3, "goblet squat, push-up, plank")
        XCTAssertTrue(f.text.contains("need equipment you do not own"), f.text)
    }

    func testTemporaryBlocksAndPainAreasAreCountedSeparately() {
        var prefs = StrengthPrefs()
        prefs.temporary = [TemporaryBlock(exerciseId: "squat", until: now.addingTimeInterval(86400 * 7), sessionsLeft: nil, at: now)]
        let c = ctx(equipment: EquipmentProfile(owned: ["barbell", "bench", "dumbbell", "pull-up bar"], confirmed: true), prefs: prefs, pain: [.knees])
        let f = EmptyStrengthCheck.explain(focus: "full body", ctx: c)
        XCTAssertEqual(f.paused, 1)
        XCTAssertGreaterThan(f.painHeld, 0, "knee pain holds the loaded leg patterns")
        XCTAssertEqual(f.total, 8)
        XCTAssertEqual(f.avoided + f.noEquipment + f.paused + f.painHeld + f.eligible, 8, "every exercise is counted exactly once")
    }

    func testFirstRemovingRuleIsTheOneCounted() {
        // an exercise that is both avoided and needs missing equipment counts as avoided (the list the rider sees first)
        var prefs = StrengthPrefs(); prefs.avoid = [AvoidEntry(exerciseId: "squat", reason: .discomfort, at: now)]
        let c = ctx(equipment: EquipmentProfile(owned: ["dumbbell"], confirmed: true), prefs: prefs)
        let f = EmptyStrengthCheck.explain(focus: "full body", ctx: c)
        XCTAssertEqual(f.avoided, 1); XCTAssertEqual(f.noEquipment, 4)
    }

    func testRoutineSessionsAndFilledSessionsAreOutOfScope() {
        let c = ctx(equipment: EquipmentProfile())
        var routine = session; routine.templateId = UUID()
        XCTAssertNil(EmptyStrengthCheck.check(routine, ctx: c), "a routine session is the rider's own, never 'empty'")
        var ride = session; ride.kind = .ride
        XCTAssertNil(EmptyStrengthCheck.check(ride, ctx: c))
        var hand = session; hand.plannedEntries = [ExerciseEntry(exercise: catalogue[4], sets: [SetEntry(reps: 10, weightKg: nil, bodyweight: true, rpe: nil, done: false)])]
        XCTAssertNil(EmptyStrengthCheck.check(hand, ctx: c), "hand-set exercises are kept")
    }

    func testEmptyCatalogueSaysSoWithoutCounts() {
        var c = ctx(equipment: EquipmentProfile()); c.catalogue = []
        let f = EmptyStrengthCheck.explain(focus: "upper body", ctx: c)
        XCTAssertEqual(f.total, 0); XCTAssertTrue(f.text.contains("catalogue is empty"))
    }

    func testProposalWarningsAreSortedByDateAndOnlyForEmptySessions() {
        var prefs = StrengthPrefs(); prefs.avoid = catalogue.map { AvoidEntry(exerciseId: $0.id, reason: .discomfort, at: now) }
        let c = ctx(equipment: EquipmentProfile(owned: ["barbell", "bench", "dumbbell", "pull-up bar"], confirmed: true), prefs: prefs)
        let later = Workout(date: now.addingTimeInterval(86400 * 3), kind: .strength, minutes: 45, strengthFocus: .upper)
        let ride = Workout(date: now.addingTimeInterval(86400), kind: .ride, minutes: 60)
        let w = EmptyStrengthCheck.warnings(for: [later, ride, session], ctx: c)
        XCTAssertEqual(w.map { $0.workout.id }, [session.id, later.id])
        XCTAssertTrue(w.allSatisfy { $0.finding.eligible == 0 })
        // the same proposal with the Avoided list cleared has nothing to warn about
        XCTAssertTrue(EmptyStrengthCheck.warnings(for: [later, ride, session], ctx: ctx(equipment: EquipmentProfile(owned: ["barbell", "bench", "dumbbell", "pull-up bar"], confirmed: true))).isEmpty)
    }
}
