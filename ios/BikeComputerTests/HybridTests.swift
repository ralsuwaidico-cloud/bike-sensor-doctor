import XCTest
@testable import BikeComputer

/// Hybrid Athlete Mode, phase 1: plan engine around a realistic hybrid week, separate hour budgets, the coach's
/// evidence-only findings, Apple Health deduplication and store compatibility.
final class HybridTests: XCTestCase {
    private let cal = Calendar.current
    private var monday: Date { cal.date(from: DateComponents(year: 2026, month: 10, day: 19))! }   // a Monday

    /// Mon rest · Tue ride 60 + lift 30 · Wed lift 45 · Thu ride 75 · Fri rest · Sat long ride 150 · Sun lift 40
    private func hybridWeek() -> WeeklyAvailability {
        var d = Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7)
        d[1] = DayAvailability(activity: .both, minutes: 60, liftMinutes: 30)
        d[2] = DayAvailability(activity: .lift, minutes: 45)
        d[3] = DayAvailability(activity: .cycle, minutes: 75)
        d[5] = DayAvailability(activity: .cycle, minutes: 150)
        d[6] = DayAvailability(activity: .lift, minutes: 40)
        return WeeklyAvailability(days: d)
    }
    private func hybridProfile() -> RiderProfile {
        var p = RiderProfile.screened(); p.trainingMode = .hybrid; p.priority = .balanced; p.hoursPerWeek = 5; p.liftingHoursPerWeek = 2
        p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 3; p.level = .intermediate; p.goal = .fitness
        return p
    }

    func testHybridWeekFollowsAvailabilityWithSeparateHours() {
        let a = hybridWeek()
        XCTAssertEqual(a.cycleDays, 3); XCTAssertEqual(a.liftDays, 3)
        XCTAssertEqual(a.cycleMinutes, 285); XCTAssertEqual(a.liftMinutes, 115)
        let w = PlanEngine.week(starting: monday, profile: hybridProfile(), availability: a)
        XCTAssertEqual(w.count, 8, "seven day entries plus the lift of the combined day")
        let tue = w.filter { cal.isDate($0.date, inSameDayAs: cal.date(byAdding: .day, value: 1, to: monday)!) }
        XCTAssertEqual(tue.count, 2); XCTAssertTrue(tue.contains { $0.kind.isRide && $0.minutes == 60 }); XCTAssertTrue(tue.contains { $0.kind == .strength && $0.minutes == 30 })
        XCTAssertEqual(tue.first { $0.kind.isRide }?.sequence, 0, "balanced priority: ride first on a shared day")
        XCTAssertEqual(tue.first { $0.kind == .strength }?.strengthFocus?.loadsLegs, false, "the lift on a ride day never loads the legs twice")
        XCTAssertEqual(w[0].kind, .rest); XCTAssertEqual(w[4].kind, .rest)
        XCTAssertEqual(w[5].kind, .long); XCTAssertEqual(w[5].minutes, 150)
        XCTAssertEqual(w[2].kind, .strength); XCTAssertEqual(w[2].minutes, 45)
        XCTAssertEqual(w[6].kind, .strength); XCTAssertEqual(w[6].minutes, 40)
        XCTAssertEqual(PlanEngine.rideMinutes(w), 285); XCTAssertEqual(PlanEngine.liftMinutes(w), 115)
        XCTAssertEqual(w.filter { $0.kind == .strength }.count, 3)
        XCTAssertEqual(w.filter { $0.kind.zone >= 3 }.count, 1, "one quality ride")
        // hard ride (Zone 3+) and the leg-loading lift are not on consecutive days
        let legDays = w.filter { $0.kind == .strength && ($0.strengthFocus?.loadsLegs ?? false) }.map { cal.component(.weekday, from: $0.date) }
        let hardDays = w.filter { $0.kind.zone >= 3 }.map { cal.component(.weekday, from: $0.date) }
        XCTAssertFalse(legDays.isEmpty, "with three lifts one of them is lower body")
        for l in legDays { for h in hardDays { XCTAssertNotEqual(min(abs(l - h), 7 - abs(l - h)), 1, "leg day \(l) next to hard ride \(h)") } }
        // budgets: 285 min riding is inside 5 h; 115 min lifting is inside 2 h → no suggestions
        XCTAssertTrue(PlanEngine.suggestions(for: w, hoursPerWeek: 5).isEmpty)
        XCTAssertTrue(PlanEngine.liftSuggestions(for: w, liftingHours: 2).isEmpty)
        // over the lifting budget → suggestions, nothing cut
        let s = PlanEngine.liftSuggestions(for: w, liftingHours: 1)
        XCTAssertFalse(s.isEmpty); XCTAssertTrue(s[0].contains("55 min over")); XCTAssertEqual(PlanEngine.liftMinutes(w), 115)
    }

    func testStrengthPriorityPutsLiftFirstOnSharedDay() {
        var p = hybridProfile(); p.priority = .strength
        let w = PlanEngine.week(starting: monday, profile: p, availability: hybridWeek())
        let tue = w.filter { cal.isDate($0.date, inSameDayAs: cal.date(byAdding: .day, value: 1, to: monday)!) }
        XCTAssertEqual(tue.first { $0.kind == .strength }?.sequence, 0)
        XCTAssertEqual(tue.first { $0.kind.isRide }?.sequence, 1)
        let grouped = PlanDay.group(w, weekOf: monday)
        XCTAssertEqual(grouped[1].items.first?.kind, .strength, "the day strip shows the priority session first")
    }

    func testSuggestedAvailabilityFromProfile() {
        var p = hybridProfile(); p.preferredDays = [1, 3, 5, 6]; p.cyclingDaysPerWeek = 3; p.liftDaysPerWeek = 2
        let a = WeeklyAvailability.suggested(for: p)
        XCTAssertEqual(a.cycleDays, 3); XCTAssertEqual(a.liftDays, 2)
        XCTAssertTrue(a.days[5].activity.cycles, "the long ride takes the first preferred weekend day")
        XCTAssertGreaterThanOrEqual(a.days[5].minutes, a.days[1].minutes)
        XCTAssertEqual(a.days.filter { $0.activity == .rest }.count, 2)
        // more sessions than days → combined days, never dropped sessions
        var q = hybridProfile(); q.preferredDays = [1, 3, 5]; q.cyclingDaysPerWeek = 3; q.liftDaysPerWeek = 3
        let b = WeeklyAvailability.suggested(for: q)
        XCTAssertEqual(b.cycleDays, 3); XCTAssertEqual(b.liftDays, 3)
        // cycling mode keeps the 0.5.0 suggestion
        var c = RiderProfile.screened(); c.trainingMode = .cycling; c.hoursPerWeek = 5
        XCTAssertEqual(WeeklyAvailability.suggested(for: c), WeeklyAvailability.suggested(hoursPerWeek: 5))
        // strength-only mode has no rides
        var s = hybridProfile(); s.trainingMode = .strength; s.liftDaysPerWeek = 3
        XCTAssertEqual(WeeklyAvailability.suggested(for: s).cycleDays, 0); XCTAssertEqual(WeeklyAvailability.suggested(for: s).liftDays, 3)
    }

    // MARK: coach evidence vectors
    private func ride(_ dayOffset: Int, minutes: Int, zoneHard: Bool = false) -> RideRecord {
        var r = RideRecord(start: cal.date(byAdding: .day, value: dayOffset, to: monday)!.addingTimeInterval(8 * 3600), durationS: minutes * 60, distanceM: minutes * 400, recorder: .phone, sources: ["Phone GPS"])
        r.zoneSeconds = zoneHard ? [0, 0, minutes * 40, minutes * 20, 0, 0, 0] : [0, minutes * 60, 0, 0, 0, 0, 0]
        return r
    }
    private func lift(_ dayOffset: Int, _ f: StrengthFocus, minutes: Int = 40, weekOffset: Int = 0) -> StrengthSession {
        StrengthSession(date: cal.date(byAdding: .day, value: dayOffset + 7 * weekOffset, to: monday)!.addingTimeInterval(18 * 3600), minutes: minutes, focus: f, rpe: 6)
    }

    func testCoachFindsUnderLifting() {
        let p = hybridProfile(), a = hybridWeek()
        let plan = PlanEngine.week(starting: monday, profile: p, availability: a)
        // it is Friday: 3 rides done, no lift logged, no lift left in the plan after today except Sunday
        let now = cal.date(byAdding: .day, value: 4, to: monday)!.addingTimeInterval(10 * 3600)
        let x = HybridCoach.assess(profile: p, plan: plan, rides: [ride(1, minutes: 60), ride(3, minutes: 75)], strength: [], availability: a, now: now, calendar: cal)
        XCTAssertEqual(x.strength?.sessionsDone, 0); XCTAssertEqual(x.strength?.sessionsTarget, 3)
        XCTAssertTrue(x.findings.contains { $0.id == "str-freq" && $0.severity == .gap }, "two lifts were missed, one is still planned → a lift is missing")
        XCTAssertEqual(x.combined, "strength behind")
        XCTAssertTrue(x.why.contains { $0.contains("not known from quick logs") == false } , "the why text exists")
        XCTAssertTrue(x.findings.contains { $0.id == "str-coverage" && $0.text.contains("not known from quick logs") }, "coverage is never inferred from labels")
    }

    func testCoachFindsUnderRiding() {
        let p = hybridProfile(), a = hybridWeek()
        let plan = PlanEngine.week(starting: monday, profile: p, availability: a)
        // Sunday evening: all three lifts logged, only one ride done, no ride left
        let now = cal.date(byAdding: .day, value: 6, to: monday)!.addingTimeInterval(20 * 3600)
        let x = HybridCoach.assess(profile: p, plan: plan, rides: [ride(1, minutes: 60)], strength: [lift(1, .upper, minutes: 30), lift(2, .push, minutes: 45), lift(6, .lower)], availability: a, now: now, calendar: cal)
        XCTAssertTrue(x.findings.contains { $0.id == "cyc-freq" && $0.severity == .gap })
        XCTAssertTrue(x.findings.contains { $0.id == "str-ok" })
        XCTAssertEqual(x.combined, "cycling behind")
        XCTAssertEqual(x.cycling?.minutesDone, 60); XCTAssertEqual(x.strength?.minutesDone, 115, "lifting minutes are counted apart from riding")
    }

    func testCoachBalancedWeek() {
        let p = hybridProfile(), a = hybridWeek()
        let plan = PlanEngine.week(starting: monday, profile: p, availability: a)
        let now = cal.date(byAdding: .day, value: 6, to: monday)!.addingTimeInterval(20 * 3600)
        let x = HybridCoach.assess(profile: p, plan: plan, rides: [ride(1, minutes: 60), ride(3, minutes: 75, zoneHard: true), ride(5, minutes: 150)], strength: [lift(1, .upper, minutes: 30), lift(2, .push, minutes: 45), lift(6, .lower)], availability: a, now: now, calendar: cal)
        XCTAssertEqual(x.combined, "on track")
        XCTAssertTrue(x.findings.contains { $0.id == "cyc-ok" }); XCTAssertTrue(x.findings.contains { $0.id == "str-ok" })
        XCTAssertFalse(x.findings.contains { $0.severity == .gap })
        XCTAssertTrue(x.why.contains { $0.contains("No sleep, HRV or recovery source") })
        XCTAssertTrue(x.cycling!.note.contains("% at Zone 3 or above"), "intensity mix only from real zone data")
    }

    func testCoachPushPullImbalanceOnlyFromLabels() {
        let p = hybridProfile(), a = hybridWeek()
        let plan = PlanEngine.week(starting: monday, profile: p, availability: a)
        let now = cal.date(byAdding: .day, value: 6, to: monday)!.addingTimeInterval(20 * 3600)
        let pushHeavy = [lift(1, .push, weekOffset: -1), lift(3, .push, weekOffset: -1), lift(1, .push, weekOffset: -2), lift(6, .pull, weekOffset: -2)]
        let x = HybridCoach.assess(profile: p, plan: plan, rides: [], strength: pushHeavy, availability: a, now: now, calendar: cal)
        XCTAssertTrue(x.findings.contains { $0.id == "str-pushpull" && $0.text.contains("add a pull session") })
        // full-body-only logs: nothing is claimed about push/pull or muscle coverage
        let fullOnly = [lift(1, .fullBody, weekOffset: -1), lift(3, .fullBody, weekOffset: -1), lift(1, .fullBody, weekOffset: -2)]
        let y = HybridCoach.assess(profile: p, plan: plan, rides: [], strength: fullOnly, availability: a, now: now, calendar: cal)
        XCTAssertFalse(y.findings.contains { $0.id.hasPrefix("str-pushpull") })
        XCTAssertFalse(y.findings.contains { $0.id == "str-lower" })
        XCTAssertTrue(y.findings.contains { $0.id == "str-coverage" })
        // Health imports carry no region
        let h = StrengthSession(date: monday, minutes: 40, focus: .custom, customName: "Strength training (Apple Health)", source: "Apple Health", healthUUID: "abc")
        XCTAssertFalse(h.regionKnown)
    }

    func testCyclingModeIgnoresStrength() {
        var p = hybridProfile(); p.trainingMode = .cycling
        let a = WeeklyAvailability.suggested(hoursPerWeek: 5)
        let plan = PlanEngine.week(starting: monday, profile: p, availability: a)
        let x = HybridCoach.assess(profile: p, plan: plan, rides: [], strength: [], availability: a, now: monday.addingTimeInterval(36_000), calendar: cal)
        XCTAssertNil(x.strength); XCTAssertNotNil(x.cycling)
    }

    // MARK: Apple Health import + dedupe
    private func tempStore() -> Store {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("bc-hyb-\(UUID().uuidString)", isDirectory: true)
        return Store(directory: u, generatePlan: false)
    }

    func testHealthImportDedupesRidesAndStrength() {
        let s = tempStore()
        let start = monday.addingTimeInterval(7 * 3600)
        // a phone ride already recorded
        XCTAssertTrue(s.addRide(RideRecord(start: start, durationS: 3600, distanceM: 25_000, recorder: .phone, sources: ["Phone GPS"])))
        // Health workout of the same ride, 90 s later and 3 % longer → skipped
        let r1 = HealthWorkoutMapper.apply(kind: .ride, start: start.addingTimeInterval(90), durationS: 3700, distanceM: 25_200, kj: 800, uuid: "h1", to: s)
        XCTAssertFalse(r1.ride); XCTAssertEqual(s.rides.count, 1)
        // a different ride → added, labelled Apple Health, no power invented
        let r2 = HealthWorkoutMapper.apply(kind: .ride, start: start.addingTimeInterval(86_400), durationS: 2400, distanceM: 15_000, kj: 500, uuid: "h2", to: s)
        XCTAssertTrue(r2.ride); XCTAssertEqual(s.rides.count, 2)
        let added = s.rides.first { $0.healthUUID == "h2" }!
        XCTAssertEqual(added.recorder, .health); XCTAssertNil(added.avgPower); XCTAssertEqual(added.sources, ["Apple Health"]); XCTAssertEqual(added.recordedBy, "Apple Health")
        // same UUID twice → skipped
        XCTAssertFalse(HealthWorkoutMapper.apply(kind: .ride, start: start.addingTimeInterval(86_400), durationS: 2400, distanceM: 15_000, kj: 500, uuid: "h2", to: s).ride)
        // strength: quick log first, then the Health copy (+60 s, same duration) → skipped; a new one → added without region
        XCTAssertTrue(s.addStrength(StrengthSession(date: start.addingTimeInterval(36_000), minutes: 45, focus: .lower, rpe: 7)))
        XCTAssertFalse(HealthWorkoutMapper.apply(kind: .strength, start: start.addingTimeInterval(36_060), durationS: 45 * 60, distanceM: nil, kj: 300, uuid: "s1", to: s).strength)
        XCTAssertTrue(HealthWorkoutMapper.apply(kind: .strength, start: start.addingTimeInterval(200_000), durationS: 30 * 60, distanceM: nil, kj: nil, uuid: "s2", to: s).strength)
        XCTAssertEqual(s.strength.count, 2)
        XCTAssertEqual(s.strength.first { $0.healthUUID == "s2" }?.regionKnown, false)
        XCTAssertEqual(s.strength.first { $0.healthUUID == "s2" }?.source, "Apple Health")
        // ignored kinds and sub-minute workouts add nothing
        XCTAssertEqual(HealthWorkoutMapper.apply(kind: .ignored, start: start, durationS: 600, distanceM: nil, kj: nil, uuid: "x", to: s).strength, false)
        XCTAssertEqual(HealthWorkoutMapper.apply(kind: .strength, start: start.addingTimeInterval(400_000), durationS: 30, distanceM: nil, kj: nil, uuid: "y", to: s).strength, false)
        XCTAssertEqual(HealthWorkoutMapper.kind(for: .cycling), .ride); XCTAssertEqual(HealthWorkoutMapper.kind(for: .functionalStrengthTraining), .strength); XCTAssertEqual(HealthWorkoutMapper.kind(for: .running), .ignored)
    }

    func testQuickLogMarksPlannedStrengthDoneAndTimelineShowsIt() {
        let s = tempStore()
        let today = cal.startOfDay(for: Date())
        s.plan = [Workout(date: today.addingTimeInterval(7 * 3600), kind: .strength, minutes: 40, strengthFocus: .lower)]
        XCTAssertTrue(s.addStrength(StrengthSession(date: Date(), minutes: 35, focus: .lower, rpe: 6)))
        XCTAssertTrue(s.plan[0].done)
        let t = Timeline.build(rides: [], plan: s.plan, ftp: 200, strength: s.strength, now: Date().addingTimeInterval(86_400), calendar: cal)
        XCTAssertEqual(t.count, 1, "the logged session represents the planned one; no duplicate entry")
        XCTAssertEqual(t[0].title, "Strength · Lower body"); XCTAssertEqual(t[0].status, .completed); XCTAssertNotNil(t[0].strengthId)
        XCTAssertTrue(s.strengthWeekTotals(weeks: 1).last!.minutes == 35)
    }

    // MARK: store compatibility
    func testBuild30StoreLoadsWithHybridDefaults() throws {
        let json = """
        {"schema":1,"profile":{"name":"Rashed","goal":"endurance","hoursPerWeek":6,"level":"intermediate","weightKg":82,"age":35,"ftpW":210,"ftpHow":"entered","version":9,"updatedAt":"2026-10-25T08:00:00Z","gender":null,"wheelMm":2096,"cadenceLow":85,"cadenceHigh":95,"hrZoneMethod":"maxHR"},
         "settings":{"units":"metric","appearance":"system","coachTalk":"normal"},
         "plan":[{"id":"\(UUID().uuidString)","date":"2026-10-20T07:00:00Z","kind":"strength","minutes":30,"done":false,"skipped":false,"note":"","edited":true}],
         "rides":[],"tiles":["power","cadence","hr","speed","time","dist"],"onboarded":true,"guest":true,"createdAt":"2026-10-24T10:00:00Z",
         "availability":{"days":[{"activity":"rest","minutes":0},{"activity":"cycle","minutes":60},{"activity":"lift","minutes":30},{"activity":"cycle","minutes":60},{"activity":"rest","minutes":0},{"activity":"cycle","minutes":120},{"activity":"other","minutes":45}]}}
        """
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let f = try dec.decode(StoreFile.self, from: Data(json.utf8))
        XCTAssertEqual(f.profile.trainingMode, .cycling); XCTAssertEqual(f.profile.liftDaysPerWeek, 0); XCTAssertEqual(f.profile.hoursPerWeek, 6)
        XCTAssertEqual(f.strength.count, 0)
        XCTAssertEqual(f.availability?.days.count, 7); XCTAssertNil(f.availability?.days[2].liftMinutes); XCTAssertEqual(f.availability?.days[2].liftingMinutes, 30)
        XCTAssertNil(f.plan[0].strengthFocus); XCTAssertEqual(f.plan[0].sequence, 0); XCTAssertTrue(f.plan[0].edited)
        XCTAssertEqual(f.settings.appleHealthImportWorkouts, false)
        // round trip with hybrid data
        var g = f; g.profile.trainingMode = .hybrid; g.profile.liftingHoursPerWeek = 2; g.strength = [StrengthSession(date: Date(), minutes: 40, focus: .push, rpe: 7)]
        g.availability?.days[1] = DayAvailability(activity: .both, minutes: 60, liftMinutes: 25)
        let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
        let back = try dec.decode(StoreFile.self, from: try enc.encode(g))
        XCTAssertEqual(back.profile.trainingMode, .hybrid); XCTAssertEqual(back.strength.first?.focus, .push); XCTAssertEqual(back.availability?.days[1].liftMinutes, 25); XCTAssertEqual(back.availability?.days[1].activity, .both)
    }
}
