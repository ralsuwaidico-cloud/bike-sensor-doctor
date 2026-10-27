import XCTest
@testable import BikeComputer

/// Fixes for the independent coach audit of 2b2c104 (ios/QUALITY_RELEASE.md, "Audit findings addressed").
/// G-01 light loads progress, G-02 two-session evidence / unknown RPE, G-16 repeated failure, G-03 shared hold after
/// missed sessions, G-04 "Coach decides" gets exercises, G-05 unverified power, G-06 pain clearing per area,
/// G-07 split rotation across weeks, G-08 short sessions keep coverage, G-09 load ratio, G-11 live intervals.
final class AuditFixTests: XCTestCase {
    private let cal = Calendar.current
    private var now: Date { cal.date(bySettingHour: 12, minute: 0, second: 0, of: Date())! }
    private var today: Date { cal.startOfDay(for: Date()) }
    private func day(_ n: Int, hour: Int = 18) -> Date { cal.date(byAdding: .day, value: n, to: today)!.addingTimeInterval(TimeInterval(hour * 3600)) }

    private func ex(_ id: String, _ name: String, _ eq: [String], _ p: MovementPattern, _ muscles: [String] = []) -> Exercise {
        Exercise(id: id, name: name, equipment: eq, pattern: p, muscles: muscles, unilateral: false, custom: true)
    }
    private var squat: Exercise { ex("a-squat", "Back squat", ["barbell"], .squat, ["quads", "glutes"]) }
    private var goblet: Exercise { ex("a-goblet", "Goblet squat", ["dumbbell", "kettlebell"], .squat, ["quads", "glutes"]) }
    private var catalogue: [Exercise] {
        [squat, goblet,
         ex("a-rdl", "Romanian deadlift", ["barbell"], .hinge, ["hamstrings", "glutes"]),
         ex("a-bench", "Bench press", ["barbell", "bench"], .push, ["chest", "triceps"]),
         ex("a-ohp", "Overhead press", ["barbell"], .push, ["shoulders", "triceps"]),
         ex("a-row", "Barbell row", ["barbell"], .pull, ["back", "biceps"]),
         ex("a-pullup", "Pull-up", ["pull-up bar"], .pull, ["back", "biceps"]),
         ex("a-split", "Bulgarian split squat", ["dumbbell"], .singleLeg, ["quads", "glutes"]),
         ex("a-plank", "Plank", ["bodyweight"], .core, ["core"]),
         ex("a-carry", "Farmer carry", ["dumbbell"], .carry, ["grip", "core"])]
    }
    private func profile() -> RiderProfile {
        var p = RiderProfile(); p.name = "Test"; p.trainingMode = .hybrid; p.priority = .balanced; p.hoursPerWeek = 5; p.liftingHoursPerWeek = 2
        p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 2
        return p
    }
    private func ctx(_ logs: [StrengthSession], plan: [Workout] = [], hold: String? = nil) -> PlannerContext {
        PlannerContext(profile: profile(), equipment: EquipmentProfile(owned: ["barbell", "bench", "dumbbell", "kettlebell", "pull-up bar"]), catalogue: catalogue, logs: logs, plan: plan, progressionHold: hold, now: now, calendar: cal)
    }
    private func log(_ daysAgo: Int, _ e: Exercise, reps: [Int], kg: Double?, rpe: Int?) -> StrengthSession {
        StrengthSession(date: day(-daysAgo), minutes: 45, focus: .fullBody, rpe: rpe, exercises: [ExerciseEntry(exercise: e, sets: reps.map { SetEntry(reps: $0, weightKg: kg, bodyweight: kg == nil, rpe: rpe, done: true) })])
    }
    private func load(_ e: Exercise, _ logs: [StrengthSession], range: ClosedRange<Int> = 6...10, hold: String? = nil) -> StrengthPlanner.Load {
        StrengthPlanner.prescribeLoad(e, meta: ExerciseLibrary.meta(e), reps: range, sets: 3, painBlocked: false, ctx: ctx(logs, hold: hold))
    }

    // MARK: G-01 / G-02 / G-16 — planner progression

    func testLightBarbellAndDumbbellLoadsProgressWithTheSmallestStep() {
        // 40 kg barbell: 2.5 kg = 6 % (blocked by the old 5 % cap forever)
        let b = load(squat, [log(3, squat, reps: [10, 10, 10], kg: 40, rpe: 7), log(6, squat, reps: [10, 10, 10], kg: 40, rpe: 7)])
        XCTAssertEqual(b.weight, 42.5); XCTAssertEqual(b.reps, 6); XCTAssertTrue(b.progressed); XCTAssertTrue(b.why.contains("smallest step"), b.why)
        // 12 kg dumbbell: 1 kg = 8 %
        let d = load(goblet, [log(3, goblet, reps: [10, 10, 10], kg: 12, rpe: 7), log(6, goblet, reps: [10, 10, 10], kg: 12, rpe: 7)])
        XCTAssertEqual(d.weight, 13); XCTAssertTrue(d.progressed)
        // a very light dumbbell still moves, with the "big jump" caution
        let v = load(goblet, [log(3, goblet, reps: [10, 10, 10], kg: 6, rpe: 6), log(6, goblet, reps: [10, 10, 10], kg: 6, rpe: 6)])
        XCTAssertEqual(v.weight, 7); XCTAssertTrue(v.why.contains("big jump"), v.why)
    }

    func testOneGoodSessionDoesNotRaiseTheLoad() {
        let one = load(squat, [log(3, squat, reps: [10, 10, 10], kg: 60, rpe: 8)])
        XCTAssertEqual(one.weight, 60); XCTAssertFalse(one.progressed); XCTAssertTrue(one.why.contains("two sessions"), one.why)
        // the earlier session at a LOWER weight is not evidence for this weight
        let mixed = load(squat, [log(3, squat, reps: [10, 10, 10], kg: 60, rpe: 7), log(6, squat, reps: [10, 10, 10], kg: 57.5, rpe: 7)])
        XCTAssertEqual(mixed.weight, 60); XCTAssertFalse(mixed.progressed)
    }

    func testUnknownEffortIsNotEvidence() {
        let l = load(squat, [log(3, squat, reps: [10, 10, 10], kg: 80, rpe: nil), log(6, squat, reps: [10, 10, 10], kg: 80, rpe: nil)])
        XCTAssertEqual(l.weight, 80); XCTAssertFalse(l.progressed); XCTAssertTrue(l.why.contains("No effort (RPE) was logged"), l.why)
        // not even a rep is added without a known effort
        let r = load(squat, [log(3, squat, reps: [7, 7, 7], kg: 80, rpe: nil)])
        XCTAssertEqual(r.reps, 7); XCTAssertFalse(r.progressed)
        // bodyweight too
        let bw = StrengthPlanner.prescribeLoad(catalogue[8], meta: ExerciseLibrary.meta(catalogue[8]), reps: 6...10, sets: 3, painBlocked: false, ctx: ctx([log(3, catalogue[8], reps: [40, 40], kg: nil, rpe: nil)]))
        XCTAssertFalse(bw.progressed)
    }

    func testTwoFailedSessionsBringTheLoadDown() {
        let l = load(squat, [log(3, squat, reps: [4, 4, 4], kg: 60, rpe: 10), log(7, squat, reps: [4, 4, 4], kg: 60, rpe: 10)])
        XCTAssertNotNil(l.weight); XCTAssertLessThan(l.weight ?? 60, 60); XCTAssertEqual(l.reps, 6); XCTAssertFalse(l.progressed)
        // one failure only: same weight
        XCTAssertEqual(load(squat, [log(3, squat, reps: [4, 4, 4], kg: 60, rpe: 10)]).weight, 60)
    }

    // MARK: G-03 — one hold state for the coach and the planner

    func testHoldStopsEveryKindOfProgression() {
        let logs = [log(3, squat, reps: [10, 10, 10], kg: 60, rpe: 7), log(6, squat, reps: [10, 10, 10], kg: 60, rpe: 7)]
        let h = load(squat, logs, hold: "2 planned sessions were missed in the last 7 days")
        XCTAssertEqual(h.weight, 60); XCTAssertFalse(h.progressed); XCTAssertTrue(h.why.contains("missed"), h.why)
        let reps = load(squat, [log(3, squat, reps: [7, 7, 7], kg: 60, rpe: 7)], hold: "x")
        XCTAssertEqual(reps.reps, 7); XCTAssertFalse(reps.progressed)
    }

    func testMissedSessionsHoldThePlannerLikeTheCoach() {
        let s = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("bc-audit-\(UUID().uuidString)", isDirectory: true), generatePlan: false)
        s.profile = profile()
        s.plan = [Workout(date: day(-2, hour: 7), kind: .strength, minutes: 45, strengthFocus: .fullBody),
                  Workout(date: day(-4, hour: 7), kind: .endurance, minutes: 60)]
        let a = TrainingAnalyzer.analyze(s.adaptationInput(now: now))
        XCTAssertTrue(a.adherenceBlock)
        XCTAssertTrue(a.findings.contains { $0.contains("nothing is increased") })
        XCTAssertNotNil(s.plannerContext(now: now).progressionHold, "the planner holds when the coach says nothing is increased")
    }

    // MARK: G-04 — "Coach decides" split

    func testCoachDecidesSplitGetsRealExercises() {
        let s = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("bc-audit-\(UUID().uuidString)", isDirectory: true), generatePlan: false)
        var p = profile(); p.strengthSplit = nil; s.profile = p
        _ = s.regenerate(weekOf: cal.date(byAdding: .day, value: 7, to: now)!, replaceEdited: false)
        let lifts = s.plan.filter { $0.kind == .strength && $0.date > now }
        XCTAssertFalse(lifts.isEmpty)
        for w in lifts { XCTAssertFalse(s.plannedEntries(for: w).isEmpty, "\(w.date) \(w.displayTitle) has no exercises"); XCTAssertNotNil(w.rationale) }
    }

    // MARK: G-06 — pain clears only by pain-free exposure of the same area, or the rider's confirmation

    private func painInput(strength: [StrengthSession], rides: [RideRecord], clearances: [PainClearance] = []) -> AdaptationInput {
        AdaptationInput(profile: profile(), plan: [], rides: rides, strength: strength, availability: WeeklyAvailability.suggested(for: profile()), now: now, calendar: cal, painClearances: clearances)
    }
    private func ride(_ n: Int, pain: PainLevel = .noPain) -> RideRecord {
        var r = RideRecord(start: day(n, hour: 7), durationS: 3600, distanceM: 27000, recorder: .phone, sources: [])
        r.checkIn = CheckIn(performance: 7, effort: 6, pain: pain, at: r.start); return r
    }
    private func lift(_ n: Int, _ e: Exercise, pain: PainLevel = .noPain, area: PainArea? = nil) -> StrengthSession {
        var l = log(-n, e, reps: [8, 8, 8], kg: 40, rpe: 7)
        l.checkIn = CheckIn(performance: 6, effort: 6, pain: pain, painArea: area, at: l.date); return l
    }

    func testKneePainFromALiftIsNotClearedByRides() {
        let knee = lift(-3, squat, pain: .concerning, area: .knees)
        XCTAssertEqual(TrainingAnalyzer.analyze(painInput(strength: [knee], rides: [ride(-2), ride(-1)])).painAreas, [.knees])
        // upper-body lifts do not load the knees either
        XCTAssertEqual(TrainingAnalyzer.analyze(painInput(strength: [knee, lift(-2, catalogue[3]), lift(-1, catalogue[3])], rides: [])).painAreas, [.knees])
    }

    func testKneePainClearsAfterAWeekAndTwoPainFreeKneeLoadingLifts() {
        let early = lift(-10, squat, pain: .concerning, area: .knees)
        // two pain-free squat sessions but within a week of the report: still held
        let soon = lift(-5, squat, pain: .concerning, area: .knees)
        XCTAssertEqual(TrainingAnalyzer.analyze(painInput(strength: [soon, lift(-3, squat), lift(-1, squat)], rides: [])).painAreas, [.knees])
        // a week later and two pain-free squat sessions: released
        XCTAssertEqual(TrainingAnalyzer.analyze(painInput(strength: [early, lift(-3, squat), lift(-1, squat)], rides: [])).painAreas, [])
        // no date expiry: an old report with no exposure stays until confirmed
        let old = lift(-20, squat, pain: .concerning, area: .knees)
        XCTAssertEqual(TrainingAnalyzer.analyze(painInput(strength: [old], rides: [ride(-2), ride(-1)])).painAreas, [.knees])
        // the rider's confirmation releases it at once
        XCTAssertEqual(TrainingAnalyzer.analyze(painInput(strength: [old], rides: [], clearances: [PainClearance(area: .knees, at: day(-1))])).painAreas, [])
    }

    func testConfirmPainGoneIsStoredAndReleasesTheArea() {
        let s = Store(directory: FileManager.default.temporaryDirectory.appendingPathComponent("bc-audit-\(UUID().uuidString)", isDirectory: true), generatePlan: false)
        s.profile = profile()
        s.strength = [lift(-2, squat, pain: .concerning, area: .knees)]
        XCTAssertEqual(s.activePainAreas(now: now), [.knees])
        s.confirmPainGone(.knees, now: now)
        XCTAssertEqual(s.painClearances.count, 1)
        XCTAssertEqual(s.activePainAreas(now: now), [])
    }

    // MARK: G-05 — unverified power never drives zone coaching

    func testUnverifiedPowerFallsBackToRelativeCoaching() {
        XCTAssertFalse(PowerTrust.meterVerified)
        var p = profile(); p.ftpW = 250; p.ftpHow = .entered
        let c = RideCoach()
        c.configure(profile: p, settings: AppSettings(), workout: Workout(date: now, kind: .endurance, minutes: 60), powerTrusted: false)
        XCTAssertTrue(c.engine.config.ftpAssumed, "untrusted watts: own steady output, no zone claims")
        c.configure(profile: p, settings: AppSettings(), workout: Workout(date: now, kind: .endurance, minutes: 60), powerTrusted: true)
        XCTAssertFalse(c.engine.config.ftpAssumed)
    }

    // MARK: G-11 — the ride screen runs the planned structure

    func testLiveIntervalsMatchThePlan() {
        let th = Workout(date: now, kind: .threshold, minutes: 70)
        let iv = RideCoach.intervalPlan(for: th)
        XCTAssertEqual(iv?.repeats, 3); XCTAssertEqual(iv?.workSec, 480); XCTAssertEqual(iv?.restSec, 180)
        XCTAssertTrue(th.steps(ftp: 200).contains { $0.name == "3 × 8 min" && $0.target.contains("3 min easy") })
        var adj = th; adj.intervalReps = 4
        XCTAssertEqual(RideCoach.intervalPlan(for: adj)?.repeats, 4)
        let vo2 = RideCoach.intervalPlan(for: Workout(date: now, kind: .vo2, minutes: 60))
        XCTAssertEqual(vo2?.repeats, 5); XCTAssertEqual(vo2?.workSec, 180); XCTAssertEqual(vo2?.restSec, 180)
        XCTAssertNil(RideCoach.intervalPlan(for: Workout(date: now, kind: .endurance, minutes: 60)))
    }

    // MARK: G-07 — split rotation continues across weeks

    func testPushPullLegsTwiceAWeekReachesLegs() {
        let weeks = (0..<3).map { k in StrengthSplit.sessions(split: .pushPullLegs, slots: [], count: 2, offset: k * 2).map { $0.focus } }
        XCTAssertEqual(weeks[0], [.push, .pull]); XCTAssertEqual(weeks[1], [.legs, .push]); XCTAssertEqual(weeks[2], [.pull, .legs])
        // through the week builder: two consecutive weeks differ and legs appear
        var p = profile(); p.strengthSplit = .pushPullLegs
        let a = WeeklyAvailability.suggested(for: p)
        let m = TrainingLedger.monday(of: today)
        let w1 = PlanEngine.week(starting: m, profile: p, availability: a).filter { $0.kind == .strength }.map { $0.strengthFocus }
        let w2 = PlanEngine.week(starting: cal.date(byAdding: .day, value: 7, to: m)!, profile: p, availability: a).filter { $0.kind == .strength }.map { $0.strengthFocus }
        XCTAssertNotEqual(w1, w2)
        XCTAssertTrue((w1 + w2).contains(.legs), "\(w1) \(w2)")
    }

    // MARK: G-08 — a short session keeps the main patterns; the week keeps all four

    func testThirtyMinuteSessionsKeepPulling() {
        let m = TrainingLedger.monday(of: cal.date(byAdding: .day, value: 7, to: today)!)
        let ws = [0, 2, 4].map { Workout(date: cal.date(byAdding: .day, value: $0, to: m)!.addingTimeInterval(17 * 3600), kind: .strength, minutes: 30, strengthFocus: .fullBody) }
        var fam = Set<MovementPattern>()
        for w in ws {
            let b = StrengthPlanner.build(for: w, ctx: ctx([], plan: ws))
            let est = 6 + zip(b.entries, b.rationale.exercises).reduce(0.0) { $0 + Double($1.0.sets.count) * ($1.1.role == "main lift" ? 3 : $1.1.role == "secondary lift" ? 2.5 : 2) }
            XCTAssertLessThanOrEqual(est, 30)
            for e in b.entries { if let x = catalogue.first(where: { $0.id == e.exerciseId }) { fam.insert(ExerciseLibrary.meta(x).slot.family) } }
        }
        for f in [MovementPattern.squat, .hinge, .push, .pull] { XCTAssertTrue(fam.contains(f), "missing \(f) in \(fam)") }
        // even 20-minute sessions cover all four across the week
        let short = ws.map { var x = $0; x.minutes = 20; return x }
        var fam2 = Set<MovementPattern>()
        for w in short { for e in StrengthPlanner.build(for: w, ctx: ctx([], plan: short)).entries { if let x = catalogue.first(where: { $0.id == e.exerciseId }) { fam2.insert(ExerciseLibrary.meta(x).slot.family) } } }
        for f in [MovementPattern.squat, .hinge, .push, .pull] { XCTAssertTrue(fam2.contains(f), "20 min: missing \(f) in \(fam2)") }
    }

    // MARK: G-09 — acute:chronic ratio without the new-rider artefact

    func testConstantLoadReadsAboutOneAndNewRidersHaveNoRatio() {
        func analysis(days n: Int) -> TrainingAnalysis {
            var p = profile(); p.trainingMode = .cycling
            let rides = (1...n).map { ride(-$0) }
            return TrainingAnalyzer.analyze(AdaptationInput(profile: p, plan: [], rides: rides, strength: [], availability: WeeklyAvailability.suggested(for: p), now: now, calendar: cal))
        }
        XCTAssertNil(analysis(days: 22).acwr, "fewer than 28 days: no ratio")
        for n in [28, 30, 35] {
            let a = analysis(days: n)
            XCTAssertNotNil(a.acwr)
            XCTAssertEqual(a.acwr ?? 0, 1.0, accuracy: 0.1, "\(n) days")
            XCTAssertFalse(a.fatigue.contains { $0.id == "load-spike" })
        }
    }
}
