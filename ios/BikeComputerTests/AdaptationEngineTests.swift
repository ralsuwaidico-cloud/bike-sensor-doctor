import XCTest
@testable import BikeComputer

/// Adaptive hybrid-athlete coach (docs/briefs/ADAPTIVE_COACH_BRIEF_2026-10-26.txt §G, ios/ADAPTIVE_COACH.md): one test
/// per item of the brief's list, plus migration (old stores decode, completed logs never mutated).
final class AdaptationEngineTests: XCTestCase {
    private let cal = Calendar.current
    /// Fixed "now" for the pure-engine tests: Wednesday 21 Oct 2026, 12:00 local time.
    private var now: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 21, hour: 12))! }
    private var nextMonday: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 26))! }
    private func day(_ offset: Int, hour: Int = 9, from base: Date? = nil) -> Date {
        let d0 = cal.startOfDay(for: base ?? now)
        return cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: offset, to: d0)!)!
    }

    // MARK: fixtures
    private func hybrid(cycH: Int = 6, liftH: Int = 3) -> RiderProfile {
        var p = RiderProfile(); p.trainingMode = .hybrid; p.priority = .balanced; p.hoursPerWeek = cycH; p.liftingHoursPerWeek = liftH
        p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 3; p.level = .intermediate; p.goal = .fitness
        return p
    }
    private let squat = Exercise(id: "t-squat", name: "Goblet squat", equipment: ["dumbbell"], pattern: .squat)
    private let press = Exercise(id: "t-press", name: "Dumbbell floor press", equipment: ["dumbbell"], pattern: .push)
    private let benchPress = Exercise(id: "t-bench", name: "Bench press", equipment: ["barbell", "bench"], pattern: .push)
    private let backSquat = Exercise(id: "t-bsquat", name: "Barbell back squat", equipment: ["barbell"], pattern: .squat)
    private let row = Exercise(id: "t-row", name: "Dumbbell row", equipment: ["dumbbell"], pattern: .pull)
    private let plank = Exercise(id: "t-plank", name: "Plank", equipment: ["bodyweight"], pattern: .core)
    private let splitSquat = Exercise(id: "t-split", name: "Split squat", equipment: ["bodyweight"], pattern: .singleLeg, unilateral: true)
    private let rdl = Exercise(id: "t-rdl", name: "Dumbbell Romanian deadlift", equipment: ["dumbbell"], pattern: .hinge)
    private var catalogue: [Exercise] { [squat, press, benchPress, backSquat, row, plank, splitSquat, rdl] }

    private func sets(_ n: Int, reps: Int = 10, kg: Double? = 20, rpe: Int? = nil, done: Bool = true) -> [SetEntry] {
        (0..<n).map { _ in SetEntry(reps: reps, weightKg: kg, bodyweight: kg == nil, rpe: rpe, done: done) }
    }
    private func entry(_ e: Exercise, _ n: Int = 3, reps: Int = 10, kg: Double? = 20, rpe: Int? = nil) -> ExerciseEntry {
        ExerciseEntry(exercise: e, sets: sets(n, reps: reps, kg: kg, rpe: rpe))
    }
    private func logged(_ offset: Int, _ entries: [ExerciseEntry], rpe: Int? = 7, checkIn: CheckIn? = nil, base: Date? = nil) -> StrengthSession {
        var s = StrengthSession(date: day(offset, hour: 18, from: base), minutes: 45, focus: .fullBody, rpe: rpe, exercises: entries)
        s.checkIn = checkIn
        return s
    }
    private func ride(_ offset: Int, minutes: Int = 60, hr: Int? = nil, power: Int? = nil, checkIn: CheckIn? = nil, base: Date? = nil) -> RideRecord {
        var r = RideRecord(start: day(offset, hour: 7, from: base), durationS: minutes * 60, distanceM: minutes * 450, recorder: .phone, sources: ["Phone GPS"])
        r.avgHR = hr; r.avgPower = power; r.checkIn = checkIn
        return r
    }
    /// A planned strength session whose exercises the coach built (adaptable).
    private func lift(_ offset: Int, _ entries: [ExerciseEntry], fixed: Bool = false, base: Date? = nil) -> Workout {
        var w = Workout(date: day(offset, hour: 8, from: base), kind: .strength, minutes: 45, strengthFocus: .fullBody, fixed: fixed)
        w.plannedEntries = entries; w.generatedEntries = true
        return w
    }
    private func planned(_ offset: Int, _ k: WorkoutKind, minutes: Int? = nil, fixed: Bool = false, done: Bool = false) -> Workout {
        Workout(date: day(offset, hour: 7), kind: k, minutes: minutes ?? k.defaultMinutes, done: done, fixed: fixed)
    }
    private func input(plan: [Workout], rides: [RideRecord] = [], strength: [StrengthSession] = [], profile: RiderProfile? = nil, equipment: EquipmentProfile = EquipmentProfile(), availability: WeeklyAvailability? = nil) -> AdaptationInput {
        var entries: [UUID: [ExerciseEntry]] = [:]
        for w in plan where w.kind == .strength { entries[w.id] = w.plannedEntries ?? [] }
        let p = profile ?? hybrid()
        return AdaptationInput(profile: p, plan: plan, rides: rides, strength: strength, availability: availability ?? WeeklyAvailability.suggested(for: p), equipment: equipment,
                               catalogue: catalogue, templates: [], originalEntries: entries, now: now, calendar: cal)
    }
    private func has(_ r: AdaptationResult, _ c: PlanAdjustment.Change) -> Bool { r.adjustments.contains { $0.change == c } }
    private func adjustments(_ r: AdaptationResult, for w: Workout) -> [PlanAdjustment] { r.adjustments.filter { $0.workoutId == w.id } }
    private var good: CheckIn { CheckIn(performance: 8, effort: 5, at: now) }
    private var spent: CheckIn { CheckIn(performance: 4, effort: 9, at: now) }

    // MARK: G1 — five training days with two cycling and three lifting sessions
    func testFiveTrainingDaysWithTwoRidesAndThreeLifts() {
        var p = hybrid(cycH: 4, liftH: 3); p.trainingDaysPerWeek = 5; p.cyclingDaysPerWeek = 2; p.liftDaysPerWeek = 3
        let a = WeeklyAvailability.suggested(for: p)
        XCTAssertEqual(a.days.filter { !$0.isRest }.count, 5, "exactly five training days")
        XCTAssertEqual(a.days.filter { $0.isRest }.count, 2, "the other two are rest days")
        XCTAssertEqual(a.cycleDays, 2); XCTAssertEqual(a.liftDays, 3)
        let w = PlanEngine.week(starting: nextMonday, profile: p, availability: a)
        XCTAssertEqual(w.filter { $0.kind.isRide }.count, 2)
        XCTAssertEqual(w.filter { $0.kind == .strength }.count, 3)
        XCTAssertLessThanOrEqual(PlanEngine.rideMinutes(w), 4 * 60, "cycling budget")
        XCTAssertLessThanOrEqual(PlanEngine.liftMinutes(w), 3 * 60, "lifting budget")
        // the rider's own training days are the only ones used
        p.preferredDays = [0, 1, 3, 4, 5]
        let b = WeeklyAvailability.suggested(for: p)
        XCTAssertEqual(Set(b.days.indices.filter { !b.days[$0].isRest }), [0, 1, 3, 4, 5])
        // session length caps the per-session minutes (budget still wins)
        p.strengthSessionMinutes = 40
        XCTAssertTrue(WeeklyAvailability.suggested(for: p).days.flatMap { $0.assignments }.filter { $0.sport == .strength }.allSatisfy { $0.minutes <= 40 })
    }

    // MARK: G2 — custom split: two full-body sessions and one core / joints session
    func testCustomSplitTwoFullBodyAndOneCoreJointsSession() {
        var p = hybrid(cycH: 3, liftH: 3); p.trainingDaysPerWeek = 4; p.cyclingDaysPerWeek = 2; p.liftDaysPerWeek = 3
        p.strengthSplit = .custom
        p.customSplit = [SplitSlot(focus: .fullBody, perWeek: 2), SplitSlot(focus: .custom, label: "Core / joints", perWeek: 1)]
        XCTAssertEqual(StrengthSplit.sessions(split: .custom, slots: p.customSplit, count: 3).map { $0.title }, ["Full body", "Core / joints", "Full body"], "interleaved, not stacked")
        let a = WeeklyAvailability.suggested(for: p)
        XCTAssertEqual(a.days.filter { !$0.isRest }.count, 4, "no day added: 5 sessions on 4 days")
        let w = PlanEngine.week(starting: nextMonday, profile: p, availability: a)
        let lifts = w.filter { $0.kind == .strength }
        XCTAssertEqual(lifts.count, 3)
        XCTAssertEqual(lifts.filter { $0.strengthFocus == .fullBody }.count, 2)
        let core = lifts.first { $0.strengthFocus == .custom }
        XCTAssertEqual(core?.displayTitle, "Strength · Core / joints")
        XCTAssertEqual(w.filter { $0.kind.isRide }.count, 2)
        // the coach builds the core / joints session from exercises the rider can do
        let eq = EquipmentProfile(owned: ["dumbbell"])
        let e = StrengthProgrammer.entries(focus: .custom, label: "Core / joints", templates: [], preserved: [], custom: [], catalogue: catalogue, equipment: eq)
        XCTAssertFalse(e.isEmpty)
        XCTAssertTrue(e.contains { $0.pattern == .core })
        XCTAssertTrue(e.allSatisfy { [.core, .singleLeg, .pull].contains($0.pattern) }, "trunk, balance and shoulder work only")
        // a slot can name one of the rider's routines: that session uses it
        let t = WorkoutTemplate(name: "My core routine", focus: .custom, entries: [entry(plank)])
        p.customSplit[1].templateId = t.id
        let w2 = PlanEngine.week(starting: nextMonday, profile: p, availability: a)
        XCTAssertEqual(w2.first { $0.strengthFocus == .custom }?.templateId, t.id)
    }

    // MARK: G3 — six-day Push / Pull / Legs with cycling overlap
    func testSixDayPushPullLegsWithCyclingOverlap() {
        var p = hybrid(cycH: 5, liftH: 4); p.trainingDaysPerWeek = 6; p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 6; p.strengthSplit = .pushPullLegs
        let a = WeeklyAvailability.suggested(for: p)
        XCTAssertEqual(a.days.filter { !$0.isRest }.count, 6, "six training days, one rest day")
        XCTAssertTrue(a.days.contains { $0.cycles && $0.lifts }, "more sessions than days: a ride and a lift share some days")
        let w = PlanEngine.week(starting: nextMonday, profile: p, availability: a)
        let lifts = w.filter { $0.kind == .strength }.sorted { $0.date < $1.date }
        XCTAssertEqual(lifts.count, 6)
        XCTAssertEqual(lifts.map { $0.strengthFocus }, [.push, .pull, .legs, .push, .pull, .legs], "the split rotation in day order")
        XCTAssertEqual(w.filter { $0.kind.isRide }.count, 3)
        XCTAssertEqual(Set(w.filter { $0.kind != .rest }.map { cal.startOfDay(for: $0.date) }).count, 6, "no seventh day")
        for l in lifts where l.strengthFocus == .legs {
            XCTAssertFalse(w.contains { $0.kind.isRide && $0.kind.zone >= 3 && cal.isDate($0.date, inSameDayAs: l.date) }, "no hard ride on a legs day")
        }
        XCTAssertLessThanOrEqual(PlanEngine.rideMinutes(w), 5 * 60); XCTAssertLessThanOrEqual(PlanEngine.liftMinutes(w), 4 * 60)
        // PPL does not imply six days: three sessions on three days is still Push / Pull / Legs
        p.trainingDaysPerWeek = 3; p.liftDaysPerWeek = 3; p.cyclingDaysPerWeek = 0; p.trainingMode = .strength
        let w3 = PlanEngine.week(starting: nextMonday, profile: p, availability: WeeklyAvailability.suggested(for: p))
        XCTAssertEqual(w3.filter { $0.kind == .strength }.sorted { $0.date < $1.date }.map { $0.strengthFocus }, [.push, .pull, .legs])
    }

    // MARK: G4 — limited equipment
    func testLimitedEquipmentNeverPrescribedAndNeverSilentlyReplaced() {
        let eq = EquipmentProfile(owned: ["dumbbell"])
        for f in [StrengthFocus.fullBody, .lower, .upper, .push, .pull] {
            let e = StrengthProgrammer.entries(focus: f, label: "", templates: [], preserved: [], custom: [], catalogue: catalogue, equipment: eq)
            XCTAssertFalse(e.isEmpty, "\(f) session built")
            XCTAssertTrue(e.allSatisfy { x in eq.canDo(catalogue.first { $0.id == x.exerciseId }!) }, "\(f): only equipment the rider owns")
        }
        // the rider's own exercises come first
        let mine = Exercise(id: "custom-1", name: "Kettlebell-free squat", equipment: ["bodyweight"], pattern: .squat, custom: true)
        XCTAssertEqual(StrengthProgrammer.entries(focus: .lower, label: "", templates: [], preserved: [], custom: [mine], catalogue: catalogue, equipment: eq).first?.exerciseId, mine.id)
        // a saved session with a barbell exercise: a proposal to replace it, never a silent swap, never more load on it
        let w = lift(2, [entry(backSquat, kg: 60), entry(row)])
        let hist = [logged(-2, [entry(backSquat, kg: 60), entry(row)]), logged(-5, [entry(backSquat, kg: 60), entry(row)])]
        let r = AdaptationEngine.run(input(plan: [w], strength: hist, equipment: eq))
        let prop = r.proposals.first { $0.reason == .replaceExercise }
        XCTAssertNotNil(prop, "replacement proposed")
        XCTAssertEqual(prop?.adjustments.first?.change, .replace(exerciseId: backSquat.id, withId: squat.id, name: squat.name, pattern: .squat), "same movement, equipment owned")
        XCTAssertFalse(r.adjustments.contains { if case .replace = $0.change { return true }; return false }, "not applied without approval")
        XCTAssertFalse(adjustments(r, for: w).contains { if case .weight(let id, _) = $0.change { return id == backSquat.id }; return false }, "no load for equipment not owned")
        XCTAssertTrue(has(r, .weight(exerciseId: row.id, deltaKg: 1)), "the doable exercise still progresses")
        // approved → applied, and applying it changes only that session's copy
        var inp = input(plan: [w], strength: hist, equipment: eq); inp.approved = Set(prop!.adjustments.map { $0.key })
        let r2 = AdaptationEngine.run(inp)
        let applied = AdaptiveRules.apply(adjustments(r2, for: w), to: w, entries: w.plannedEntries!)
        XCTAssertEqual(applied.plannedEntries?.first?.exerciseId, squat.id)
        XCTAssertEqual(w.plannedEntries?.first?.exerciseId, backSquat.id, "original untouched")
    }

    // MARK: G5 — repeated high-effort sessions
    func testRepeatedHighEffortSessionsEaseTheComingDays() {
        let hard = planned(2, .threshold, minutes: 70), easy = planned(3, .endurance, minutes: 60)
        let l = lift(4, [entry(squat), entry(press)])
        let rides = [ride(-1, checkIn: CheckIn(performance: 6, effort: 9, at: now)), ride(-3, checkIn: CheckIn(performance: 6, effort: 9, at: now))]
        let strength = [logged(-2, [entry(squat), entry(press)], rpe: 9)]
        let r = AdaptationEngine.run(input(plan: [hard, easy, l], rides: rides, strength: strength))
        XCTAssertGreaterThanOrEqual(r.analysis.fatigue.count, 2, "two rides at 9 + three sessions at 9 this week")
        XCTAssertTrue(has(r, .kind(to: .endurance)), "hard day swapped for an easy one in the same slot")
        XCTAssertEqual(adjustments(r, for: hard).first?.category, .recovery)
        XCTAssertTrue(has(r, .sets(exerciseId: squat.id, delta: -1))); XCTAssertTrue(has(r, .sets(exerciseId: press.id, delta: -1)))
        XCTAssertFalse(r.adjustments.contains { $0.category == .progression }, "no progression while fatigued")
        XCTAssertTrue(adjustments(r, for: hard).first?.why.contains("9") == true, "the why carries the numbers")
        for a in r.adjustments { if case .minutes(let d) = a.change { XCTAssertLessThanOrEqual(abs(d), 6, "duration change within 10 %") } }
        // ONE unusual workout never triggers a change
        let one = AdaptationEngine.run(input(plan: [hard, easy, l], rides: [ride(-1, checkIn: CheckIn(performance: 2, effort: 10, at: now)), ride(-3, checkIn: good)], strength: [logged(-2, [entry(squat)], rpe: 6)]))
        XCTAssertTrue(one.analysis.fatigue.isEmpty, "a single outlier is not a trend")
        XCTAssertTrue(adjustments(one, for: hard).isEmpty)
    }

    // MARK: G6 — improving strength performance
    func testImprovingStrengthPerformanceProgressesLoadConservatively() {
        // dumbbell 20 kg, every planned set done at RPE 7 twice → +1 kg (cap: 2.5 kg and 5 %)
        let next = lift(1, [entry(squat)])
        let hist = [logged(-2, [entry(squat)]), logged(-5, [entry(squat)])]
        let r = AdaptationEngine.run(input(plan: [next], strength: hist))
        let a = adjustments(r, for: next).first
        XCTAssertEqual(a?.change, .weight(exerciseId: squat.id, deltaKg: 1))
        XCTAssertEqual(a?.category, .progression)
        XCTAssertTrue(a?.summary.contains("20 kg → 21 kg") == true, a?.summary ?? "")
        XCTAssertTrue(a?.why.contains("RPE 7") == true)
        // barbell 60 kg → +2.5 kg; 40 kg → 2.5 kg would be over 5 % → one rep instead
        let b60 = lift(1, [entry(backSquat, kg: 60)])
        XCTAssertTrue(has(AdaptationEngine.run(input(plan: [b60], strength: [logged(-2, [entry(backSquat, kg: 60)]), logged(-5, [entry(backSquat, kg: 60)])])), .weight(exerciseId: backSquat.id, deltaKg: 2.5)))
        let b40 = lift(1, [entry(backSquat, kg: 40)])
        XCTAssertTrue(has(AdaptationEngine.run(input(plan: [b40], strength: [logged(-2, [entry(backSquat, kg: 40)]), logged(-5, [entry(backSquat, kg: 40)])])), .reps(exerciseId: backSquat.id, delta: 1)))
        // RPE 9 on one of the two → no progression; only one session → no progression
        XCTAssertTrue(adjustments(AdaptationEngine.run(input(plan: [next], strength: [logged(-2, [entry(squat)], rpe: 9), logged(-5, [entry(squat)])])), for: next).isEmpty)
        XCTAssertTrue(adjustments(AdaptationEngine.run(input(plan: [next], strength: [logged(-2, [entry(squat)]), logged(-5, [entry(press)])])), for: next).isEmpty)
        // a planned set not completed → hold
        var short = entry(squat); short.sets[2].done = false
        XCTAssertTrue(adjustments(AdaptationEngine.run(input(plan: [next], strength: [logged(-2, [short]), logged(-5, [entry(squat)])])), for: next).isEmpty)
        // applied to the session copy only; the bound holds
        let applied = AdaptiveRules.apply(adjustments(r, for: next), to: next, entries: next.plannedEntries!)
        XCTAssertEqual(applied.plannedEntries?.first?.sets.map { $0.weightKg }, [21, 21, 21])
    }

    // MARK: G7 — cycling fatigue affecting strength recommendations
    func testCyclingFatigueHoldsLiftingProgressionAndTrimsLegWork() {
        let next = lift(1, [entry(squat), entry(press)])
        let hist = [logged(-2, [entry(squat), entry(press)]), logged(-5, [entry(squat), entry(press)])]     // would progress
        let rides = [ride(-1, checkIn: spent), ride(-3, checkIn: spent)]
        let r = AdaptationEngine.run(input(plan: [next], rides: rides, strength: hist))
        XCTAssertTrue(r.analysis.cyclingFatigue)
        XCTAssertFalse(r.analysis.strengthFatigue)
        XCTAssertFalse(r.adjustments.contains { if case .weight = $0.change { return true }; return false }, "no load increase while the legs carry cycling fatigue")
        XCTAssertTrue(has(r, .sets(exerciseId: squat.id, delta: -1)), "leg exercise loses a set")
        XCTAssertFalse(has(r, .sets(exerciseId: press.id, delta: -1)), "upper-body work stays as planned")
        XCTAssertTrue(adjustments(r, for: next).first?.why.contains("cycling") == true)
    }

    // MARK: G8 — strength fatigue affecting cycling recommendations
    func testStrengthFatigueEasesTheNextHardRideButNeverAFixedOne() {
        let thr = planned(2, .threshold, minutes: 70)
        let strength = [logged(-1, [entry(squat)], rpe: 9, checkIn: spent), logged(-3, [entry(squat)], rpe: 9, checkIn: spent)]
        let r = AdaptationEngine.run(input(plan: [thr], strength: strength))
        XCTAssertTrue(r.analysis.strengthFatigue)
        XCTAssertEqual(adjustments(r, for: thr).first?.change, .kind(to: .tempo), "one zone step easier")
        XCTAssertTrue(adjustments(r, for: thr).first?.why.contains("lifting") == true)
        // the same ride on a FIXED day: untouched; a proposal asks first
        let fixed = planned(2, .threshold, minutes: 70, fixed: true)
        let rf = AdaptationEngine.run(input(plan: [fixed], strength: strength))
        XCTAssertTrue(adjustments(rf, for: fixed).isEmpty)
        XCTAssertEqual(rf.proposals.first?.reason, .fixedDay)
    }

    // MARK: G9 — missed workouts
    func testMissedWorkoutsKeepThePlanAndNeverCramSessions() {
        let past = [planned(-6, .endurance), planned(-4, .strength, minutes: 45), planned(-2, .tempo)]
        let next = lift(1, [entry(squat)])
        let hist = [logged(-9, [entry(squat)]), logged(-12, [entry(squat)])]        // would progress
        let plan = past + [next]
        let r = AdaptationEngine.run(input(plan: plan, strength: hist))
        XCTAssertEqual(r.analysis.missed.count, 3)
        XCTAssertTrue(r.adjustments.isEmpty, "nothing increased, nothing crammed in")
        XCTAssertTrue(r.summary.findings.contains { $0.contains("missed") })
        XCTAssertNotNil(r.summary.feedbackRequest)
        XCTAssertFalse(r.proposals.contains { $0.reason == .sessionCount }, "one bad week is not a pattern")
        // two bad weeks in a row → a proposal (the coach never removes a session on its own)
        let older = [planned(-13, .endurance), planned(-11, .threshold)]
        let r2 = AdaptationEngine.run(input(plan: older + plan, strength: hist))
        XCTAssertTrue(r2.proposals.contains { $0.reason == .sessionCount })
        XCTAssertTrue(r2.proposals.first { $0.reason == .sessionCount }?.adjustments.isEmpty == true)
    }

    // MARK: G10 — missing sensors
    func testMissingSensorsMeansLowConfidenceKeepPlanAndAskForFeedback() {
        let plan = [planned(2, .threshold, minutes: 70), planned(3, .endurance)]
        let r = AdaptationEngine.run(input(plan: plan, rides: [ride(-1), ride(-3), ride(-5)]))
        XCTAssertEqual(r.summary.confidence, .low)
        XCTAssertTrue(r.adjustments.isEmpty)
        XCTAssertTrue(r.summary.feedbackRequest?.contains("no check-in, no heart rate") == true)
        // high but UNVERIFIED power, no rating: never used — still nothing changes
        let pw = AdaptationEngine.run(input(plan: plan, rides: [ride(-1, power: 260), ride(-3, power: 255)]))
        XCTAssertEqual(pw.summary.confidence, .low); XCTAssertTrue(pw.adjustments.isEmpty)
        XCTAssertEqual(pw.analysis.unverifiedPowerOnly, 2)
        // heart rate only: load is estimated (labelled), but intensity is not progressed without ratings
        let hr = AdaptationEngine.run(input(plan: plan, rides: [ride(-1, hr: 140), ride(-3, hr: 138)]))
        XCTAssertNotEqual(hr.summary.confidence, .low)
        XCTAssertTrue(hr.analysis.sessions.allSatisfy { $0.loadSource == "average heart rate (estimate)" })
        XCTAssertFalse(hr.adjustments.contains { if case .intervalReps = $0.change { return true }; return false })
        // rated rides that went well → one more interval inside the same minutes
        let ok = AdaptationEngine.run(input(plan: plan, rides: [ride(-1, power: 250, checkIn: good), ride(-3, checkIn: good)]))
        XCTAssertTrue(has(ok, .intervalReps(delta: 1)))
        XCTAssertTrue(ok.adjustments.first?.why.contains("unverified power is not used") == true)
    }

    // MARK: G11 — pain reports
    func testConcerningPainStopsProgressionInThatAreaWithAdviceAndNoDiagnosis() {
        let next = lift(1, [entry(squat), entry(press)])
        let knees = CheckIn(performance: 7, effort: 6, pain: .concerning, painArea: .knees, at: now)
        let hist = [logged(-1, [entry(squat), entry(press)], checkIn: knees), logged(-5, [entry(squat), entry(press)])]
        let rides = [ride(-2, checkIn: good), ride(-4, checkIn: good)]
        let thr = planned(3, .threshold, minutes: 70)
        let r = AdaptationEngine.run(input(plan: [next, thr], rides: rides, strength: hist))
        XCTAssertEqual(r.analysis.painAreas, [.knees])
        XCTAssertFalse(adjustments(r, for: next).contains { a in if case .weight(let id, _) = a.change { return id == squat.id }; if case .reps(let id, _) = a.change { return id == squat.id }; return false }, "no progression for the knees")
        XCTAssertTrue(has(r, .weight(exerciseId: press.id, deltaKg: 1)), "upper body unaffected")
        XCTAssertTrue(adjustments(r, for: thr).isEmpty, "knees carry the riding load too: no cycling progression")
        let advice = r.summary.painAdvice ?? ""
        XCTAssertTrue(advice.contains("physiotherapist")); XCTAssertTrue(advice.contains("cannot tell"))
        XCTAssertFalse(advice.lowercased().contains("diagnos"), "never a diagnosis")
        // normal soreness changes nothing
        let sore = [logged(-1, [entry(squat), entry(press)], checkIn: CheckIn(performance: 7, effort: 6, pain: .soreness, at: now)), logged(-5, [entry(squat), entry(press)])]
        XCTAssertTrue(has(AdaptationEngine.run(input(plan: [next], strength: sore)), .weight(exerciseId: squat.id, deltaKg: 1)))
    }

    // MARK: G12 — preserving fixed days and time budgets
    func testFixedDaysAndTimeBudgetsArePreserved() {
        var p = hybrid(cycH: 1, liftH: 3); p.cyclingDaysPerWeek = 1
        let slot = DayAssignment(sport: .cycling, cyclingType: .zone2, minutes: 60)
        var days = Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7)
        days[Store.weekdayIndex(day(2))] = DayAvailability(assignments: [slot])
        var endurance = planned(2, .endurance, minutes: 60); endurance.assignmentId = slot.id
        let rides = [ride(-1, checkIn: good), ride(-3, checkIn: good)]
        let inp = input(plan: [endurance], rides: rides, profile: p, availability: WeeklyAvailability(days: days))
        let r = AdaptationEngine.run(inp)
        XCTAssertTrue(adjustments(r, for: endurance).isEmpty, "10 % longer would exceed the 1 h budget and that day's 60 min")
        let prop = r.proposals.first { $0.reason == .budget }
        XCTAssertNotNil(prop, "asks instead")
        var approved = inp; approved.approved = Set(prop!.adjustments.map { $0.key })
        XCTAssertEqual(adjustments(AdaptationEngine.run(approved), for: endurance).first?.change, .minutes(delta: 5), "applied once approved")
        // a fixed session is never auto-changed, whatever the signals
        let fixed = planned(2, .vo2, minutes: 60, fixed: true)
        let tired = [logged(-1, [entry(squat)], rpe: 9, checkIn: spent), logged(-2, [entry(squat)], rpe: 9, checkIn: spent)]
        let rf = AdaptationEngine.run(input(plan: [fixed], rides: [ride(-3, checkIn: spent)], strength: tired))
        XCTAssertTrue(adjustments(rf, for: fixed).isEmpty)
        XCTAssertTrue(rf.proposals.contains { $0.reason == .fixedDay })
        // a hand-edited session is never auto-changed either
        var edited = lift(1, [entry(squat)]); edited.edited = true
        XCTAssertTrue(adjustments(AdaptationEngine.run(input(plan: [edited], strength: [logged(-2, [entry(squat)]), logged(-5, [entry(squat)])])), for: edited).isEmpty)
    }

    // MARK: G13 — reverting automatic changes (Store: per-change Undo, Restore original plan, not re-applied)
    func testUndoAndRestoreOriginalPlanRevertAutomaticChanges() {
        let s = store()
        let t0 = wholeSecondNow()
        let a = lift(1, [entry(squat)], base: t0), b = lift(2, [entry(press)], base: t0)
        var done = lift(-1, [entry(squat)], base: t0); done.done = true
        s.customExercises = [squat, press, row]          // known exercises → the dumbbell load step (1 kg per hand)
        s.plan = [done, a, b]
        s.strength = [logged(-2, [entry(squat), entry(press)], base: t0), logged(-5, [entry(squat), entry(press)], base: t0)]
        s.runAdaptation(now: t0)
        XCTAssertEqual(s.activeAdaptations.count, 2)
        XCTAssertTrue(s.plan.first { $0.id == a.id }!.coachAdjusted)
        XCTAssertEqual(s.plan.first { $0.id == a.id }!.plannedEntries?.first?.sets.first?.weightKg, 21)
        XCTAssertNotNil(s.adjustmentLine)
        XCTAssertEqual(s.plan.first { $0.id == a.id }!.coachOriginal?.plannedEntries?.first?.sets.first?.weightKg, 20, "original values kept on the session")
        // per-change Undo
        let keyA = s.activeAdaptations.first { $0.workoutId == a.id }!.key
        s.undoAdaptation(keyA)
        XCTAssertEqual(s.plan.first { $0.id == a.id }!, a, "back to exactly the original")
        s.runAdaptation(now: t0)
        XCTAssertEqual(s.plan.first { $0.id == a.id }!, a, "an undone change is not made again")
        XCTAssertTrue(s.plan.first { $0.id == b.id }!.coachAdjusted)
        // Restore original plan
        s.restoreOriginalPlan()
        XCTAssertEqual(s.plan.first { $0.id == b.id }!, b)
        XCTAssertTrue(s.activeAdaptations.isEmpty); XCTAssertNil(s.adjustmentLine)
        s.runAdaptation(now: t0)
        XCTAssertEqual(s.plan.first { $0.id == b.id }!, b)
        XCTAssertEqual(s.plan.first { $0.id == done.id }!, done, "completed session untouched")
        // automatic changes off: nothing applied on its own
        s.settings.autoAdapt = false
        let c = lift(3, [entry(row)], base: t0); s.plan.append(c)
        s.strength += [logged(-3, [entry(row)], base: t0), logged(-6, [entry(row)], base: t0)]
        s.runAdaptation(now: t0)
        XCTAssertEqual(s.plan.first { $0.id == c.id }!, c)
    }

    // MARK: migration — old stores decode unchanged; the coach never mutates completed logs or ride history
    func testOldStoreFilesDecodeWithoutAdaptiveKeys() throws {
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let seeds = [
            // build 24 (0.4.0)
            """
            {"schema":1,"profile":{"name":"R","goal":"endurance","hoursPerWeek":6,"level":"intermediate","weightKg":82,"age":35,"ftpW":210,"ftpHow":"entered","birthYear":1988,"sports":["roadCycling"],"version":4,"updatedAt":"2026-10-24T20:00:00Z"},
             "settings":{"units":"metric","phoneOnlyMode":false,"hrPref":"watch","keepScreenOn":true,"autoConnectBoard":true,"enabledConnections":["board","watch"]},
             "plan":[{"id":"\(UUID().uuidString)","date":"2026-10-21T00:00:00Z","kind":"tempo","minutes":60,"done":false,"skipped":false,"note":""}],
             "rides":[{"id":"\(UUID().uuidString)","start":"2026-10-20T07:00:00Z","durationS":3600,"distanceM":25000,"avgPower":160,"zoneSeconds":[0,3600,0,0,0,0,0],"recorder":"phone","sources":["Phone GPS"],"demo":false,"samples":[]}],
             "tiles":["power"],"onboarded":true,"guest":true,"createdAt":"2026-10-24T10:00:00Z","boardSync":[],"onboardingStage":3}
            """,
            // build 33 (0.6.0): hybrid, legacy availability, quick strength log
            """
            {"schema":1,"profile":{"name":"R","goal":"fitness","hoursPerWeek":5,"level":"intermediate","weightKg":82,"age":35,"ftpW":210,"ftpHow":"entered","version":12,"updatedAt":"2026-10-25T10:00:00Z","trainingMode":"hybrid","priority":"balanced","cyclingDaysPerWeek":3,"liftDaysPerWeek":3,"liftingHoursPerWeek":2,"preferredDays":[1,3,5,6]},
             "settings":{"units":"metric"},"plan":[{"id":"\(UUID().uuidString)","date":"2026-10-22T07:00:00Z","kind":"strength","minutes":60,"done":false,"skipped":false,"note":"","edited":false,"strengthFocus":"lower","sequence":0}],
             "rides":[],"tiles":["power"],"onboarded":true,"guest":true,"createdAt":"2026-10-24T10:00:00Z",
             "availability":{"days":[{"activity":"rest","minutes":0},{"activity":"both","minutes":60,"liftMinutes":30},{"activity":"lift","minutes":45},{"activity":"cycle","minutes":75},{"activity":"rest","minutes":0},{"activity":"cycle","minutes":150},{"activity":"lift","minutes":40}]},
             "strength":[{"id":"\(UUID().uuidString)","date":"2026-10-20T18:00:00Z","minutes":40,"focus":"upper","customName":"","rpe":6,"notes":"","source":"manual"}]}
            """,
            // build 40 (0.8.0): routines, weekday defaults, equipment, insights
            """
            {"schema":1,"profile":{"name":"R","trainingMode":"hybrid","liftDaysPerWeek":3,"liftingHoursPerWeek":2,"updatedAt":"2026-10-25T19:00:00Z"},"settings":{"units":"metric","rideLayout":"coach"},
             "plan":[{"id":"\(UUID().uuidString)","date":"2026-10-22T07:00:00Z","kind":"strength","minutes":45,"done":false,"skipped":false,"note":"","edited":true,"templateId":"00000000-0000-0000-0000-000000000001","routineManual":true,"strengthFocus":"fullBody","sequence":0}],
             "rides":[],"onboarded":true,"guest":true,"createdAt":"2026-10-24T10:00:00Z","templates":[],"customExercises":[],"appliedProposals":[],
             "weekdayRoutines":{"1":"00000000-0000-0000-0000-000000000000"},"equipment":{"owned":["dumbbells","bench"],"excluded":[]},"activeSession":null,"ignoredInsights":[],
             "strength":[{"id":"\(UUID().uuidString)","date":"2026-10-20T18:00:00Z","minutes":35,"focus":"fullBody","rpe":7,"source":"manual","exercises":[{"id":"\(UUID().uuidString)","exerciseId":"ex-003","name":"Goblet squat","pattern":"squat","sets":[{"id":"\(UUID().uuidString)","reps":10,"weightKg":20,"done":true}]}]}]}
            """,
        ]
        for json in seeds {
            let f = try dec.decode(StoreFile.self, from: Data(json.utf8))
            XCTAssertTrue(f.onboarded)
            XCTAssertNil(f.profile.strengthSplit); XCTAssertTrue(f.profile.customSplit.isEmpty); XCTAssertNil(f.profile.trainingDaysPerWeek); XCTAssertNil(f.profile.hybridGoal)
            XCTAssertTrue(f.settings.autoAdapt, "automatic changes default on")
            XCTAssertTrue(f.adaptations.isEmpty); XCTAssertTrue(f.adaptiveProposals.isEmpty); XCTAssertNil(f.lastAdaptation)
            XCTAssertFalse(f.plan.isEmpty)
            XCTAssertTrue(f.plan.allSatisfy { $0.coachOriginal == nil && $0.intervalReps == nil && !$0.generatedEntries })
            XCTAssertTrue(f.rides.allSatisfy { $0.checkIn == nil && $0.powerVerified == nil })
            XCTAssertTrue(f.strength.allSatisfy { $0.checkIn == nil })
            // and the new keys round-trip
            let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
            let again = try dec.decode(StoreFile.self, from: try enc.encode(f))
            XCTAssertEqual(again, f)
        }
        // adaptive data itself round-trips
        var w = Workout(date: Date(timeIntervalSince1970: 1_761_000_000), kind: .threshold, minutes: 70)
        w.coachOriginal = w.planSnapshot; w.intervalReps = 4
        let wenc = JSONEncoder(); wenc.dateEncodingStrategy = .iso8601
        let back = try dec.decode(Workout.self, from: try wenc.encode(w))
        XCTAssertEqual(back.intervalReps, 4); XCTAssertEqual(back.coachOriginal?.kind, .threshold)
        XCTAssertEqual(back.steps(ftp: 200)[1].name, "4 × 8 min")
    }

    func testAdaptationNeverMutatesCompletedLogsOrRideHistory() {
        let s = store()
        let t0 = wholeSecondNow()
        s.rides = [ride(-1, hr: 150, checkIn: spent, base: t0), ride(-3, power: 200, checkIn: spent, base: t0)]
        s.strength = [logged(-2, [entry(squat)], rpe: 9, base: t0), logged(-4, [entry(squat)], base: t0)]
        var past = lift(-2, [entry(squat)], base: t0); past.done = true
        var hardPast = Workout(date: day(-1, from: t0), kind: .threshold, minutes: 70); hardPast.done = true
        s.plan = [past, hardPast, Workout(date: day(2, from: t0), kind: .threshold, minutes: 70), lift(3, [entry(squat)], base: t0)]
        let rides0 = s.rides, strength0 = s.strength
        s.runAdaptation(now: t0)
        XCTAssertFalse(s.activeAdaptations.isEmpty, "the coach did adapt the future")
        XCTAssertEqual(s.rides, rides0, "ride history untouched")
        XCTAssertEqual(s.strength, strength0, "completed logs untouched")
        XCTAssertEqual(s.plan.first { $0.id == past.id }, past); XCTAssertEqual(s.plan.first { $0.id == hardPast.id }, hardPast)
        // a check-in writes only the check-in field of its record, then the coach runs
        let c = CheckIn(performance: 9, effort: 4, at: t0)
        XCTAssertNotNil(s.recordCheckIn(c, strengthId: strength0[1].id, now: t0))
        var expected = strength0[1]; expected.checkIn = c
        XCTAssertEqual(s.strength.first { $0.id == expected.id }, expected)
        XCTAssertEqual(s.lastAdaptation?.label, "Coach (rules-based)")
        // persisted and reloaded
        let s2 = Store(directory: s.dir, generatePlan: false)
        XCTAssertEqual(s2.adaptations, s.adaptations); XCTAssertEqual(s2.plan, s.plan); XCTAssertEqual(s2.strength.first { $0.id == expected.id }?.checkIn, c)
    }

    /// Stored dates are whole seconds (ISO 8601), so store tests use a whole-second "now".
    private func wholeSecondNow() -> Date { Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)) }
    private func store() -> Store {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let s = Store(directory: dir, generatePlan: false)
        s.profile = hybrid()
        return s
    }
}
