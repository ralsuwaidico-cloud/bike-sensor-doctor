import XCTest
@testable import BikeComputer

/// Closes the tracker's untested items with data-level tests (owner 8 Nov 18:07, Phase 2):
/// GR-44 relaunch identity · GR-34 onboarding answers change the plan · GR-50 Normalized Power · APP-020 delete path.
final class DataIntegrityGapTests: XCTestCase {
    private func dir() -> URL { let d = FileManager.default.temporaryDirectory.appendingPathComponent("dig-\(UUID().uuidString)"); try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true); return d }
    private func day(_ sport: DayAssignment.Sport?, _ minutes: Int = 0) -> DayAvailability { sport.map { DayAvailability(assignments: [DayAssignment(sport: $0, minutes: minutes)]) } ?? DayAvailability(activity: .rest, minutes: 0) }
    private var monday: Date { Calendar.current.date(byAdding: .day, value: 7, to: TrainingLedger.monday(of: Date()))! }

    // GR-44: plan, logs, rides, profile, settings and recovery log are byte-identical after a relaunch
    func testRelaunchLeavesEveryRecordIdentical() {
        let d = dir(); let s = Store(directory: d, generatePlan: false)
        var p = RiderProfile.screened(); p.name = "Rashed"; p.trainingMode = .hybrid; p.hoursPerWeek = 4; p.liftingHoursPerWeek = 1; p.weekIsExplicit = true
        p.setFTP(252, source: .tested); s.profile = p
        s.availability = WeeklyAvailability(days: [day(.strength, 30), day(.cycling, 60), day(nil), day(.cycling, 60), day(nil), day(.cycling, 90), day(nil)])
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        var r = RideRecord(start: Date(), durationS: 3600, distanceM: 30_000, recorder: .phone, sources: ["Phone GPS"]); r.avgPower = 190; r.samples = (1...60).map { (t: Int) -> RideRecord.Sample in RideRecord.Sample(t: t, w: 180 + (t % 7)) }; _ = s.addRide(r)
        var st = StrengthSession(date: Date(), minutes: 35, focus: .fullBody); st.exercises = [ExerciseEntry(exercise: Exercise(id: "row", name: "Row", pattern: .pull), sets: [SetEntry(reps: 8, weightKg: 40)])]; _ = s.addStrength(st)
        s.settings.units = .imperial; s.settings.healthReads.sleep = true
        s.applyHealthSamples([HealthSample(kind: .sleep, value: 7.1, date: Date().addingTimeInterval(-3600), source: "Apple Watch")])
        // the store writes ISO-8601 seconds, so compare what was WRITTEN (one round trip) with what the relaunch holds
        func roundTrip(_ f: StoreFile) -> StoreFile { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; let dd = JSONDecoder(); dd.dateDecodingStrategy = .iso8601; return try! dd.decode(StoreFile.self, from: try! e.encode(f)) }
        let before = roundTrip(s.snapshot)
        let again = Store(directory: d, generatePlan: false)
        XCTAssertEqual(again.snapshot.plan, before.plan, "plan identical after relaunch")
        XCTAssertEqual(again.snapshot.rides, before.rides); XCTAssertEqual(again.snapshot.strength, before.strength)
        XCTAssertEqual(again.snapshot.profile, before.profile); XCTAssertEqual(again.snapshot.settings, before.settings)
        XCTAssertEqual(again.snapshot.recoveryLog, before.recoveryLog); XCTAssertEqual(again.snapshot.availability, before.availability)
        XCTAssertEqual(again.profile.ftpW, 252); XCTAssertEqual(again.profile.ftpHow, .tested, "a tested FTP survives a relaunch unchanged")
        XCTAssertEqual(again.snapshot.planVersions, before.planVersions)
        // and a third launch changes nothing either (no migration re-runs on current data)
        let third = Store(directory: d, generatePlan: false)
        XCTAssertEqual(third.snapshot.plan, before.plan); XCTAssertEqual(third.migrationLog, again.migrationLog)
    }

    // GR-34: the onboarding answers are saved into the one profile and the generated week follows them
    func testOnboardingAnswersAreSavedAndChangeThePlan() {
        let s = Store(directory: dir(), generatePlan: false)
        var p = RiderProfile.screened(); p.trainingMode = .hybrid; s.profile = p
        var a = OnboardingAnswers()
        a.name = "Rashed"; a.mode = .hybrid; a.priority = .cycling; a.cyclingLevel = .intermediate; a.strengthLevel = .intermediate
        a.week = [.lift, .ride, .rest, .ride, .rest, .ride, .rest]; a.rideMinutes = 75; a.liftMinutes = 40; a.equipment = .gym; a.supersets = true
        a.ftpWatts = 240; a.ftpSource = .entered
        var x = s.planInputs; a.apply(to: &x)
        s.updateProfile { $0 = x.profile }; s.availability = x.availability; s.equipment = x.equipment; s.strengthPrefs = x.strengthPrefs
        XCTAssertEqual(s.profile.name, "Rashed"); XCTAssertEqual(s.profile.priority, .cycling); XCTAssertEqual(s.profile.ftpW, 240); XCTAssertEqual(s.profile.ftpHow, .entered)
        XCTAssertEqual(s.profile.cyclingSessionMinutes, 75); XCTAssertEqual(s.profile.strengthSessionMinutes, 40); XCTAssertEqual(s.strengthPrefs.prefersSupersets, true)
        XCTAssertEqual(OnboardingWeek.kinds(of: s.availability, mode: .hybrid, twoADay: true), a.week, "the chosen week is what is stored")
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let week = s.plan.filter { $0.date >= monday && $0.date < Calendar.current.date(byAdding: .day, value: 7, to: monday)! && $0.kind != .rest && $0.kind != .recoveryDay }
        let cal = Calendar.current
        func weekday(_ w: Workout) -> Int { (cal.dateComponents([.day], from: monday, to: cal.startOfDay(for: w.date)).day ?? 0) }
        let rideDays = Set(week.filter { $0.kind.isRide }.map(weekday)), liftDays = Set(week.filter { $0.kind == .strength }.map(weekday))
        XCTAssertFalse(rideDays.isEmpty); XCTAssertTrue(rideDays.isSubset(of: [1, 3, 5]), "rides land only on the chosen ride days: \(rideDays)")
        XCTAssertFalse(liftDays.isEmpty); XCTAssertTrue(liftDays.isSubset(of: [0]), "the lift lands only on the chosen lift day: \(liftDays)")
        XCTAssertTrue(week.filter { $0.kind == .strength }.allSatisfy { $0.minutes <= 40 }, "lift sessions respect the chosen length")
        // changing one answer changes the plan: drop Saturday's ride
        var b = OnboardingAnswers(); b.week = [.lift, .ride, .rest, .ride, .rest, .rest, .rest]
        var y = s.planInputs; b.apply(to: &y); s.availability = y.availability
        _ = s.regenerate(weekOf: monday, replaceEdited: true)
        let week2 = s.plan.filter { $0.date >= monday && $0.date < cal.date(byAdding: .day, value: 7, to: monday)! && $0.kind.isRide }
        XCTAssertFalse(week2.map(weekday).contains(5), "removing Saturday removes its ride"); XCTAssertTrue(Set(week2.map(weekday)).isSubset(of: [1, 3]))
    }

    // GR-50: Normalized Power = 4th root of the mean 4th power of the 30 s rolling average; needs ≥ 30 s
    func testNormalizedPowerDefinition() {
        XCTAssertNil(RidePerformanceModel.normalizedPower(Array(repeating: 200, count: 29)), "under 30 s there is no NP")
        XCTAssertEqual(RidePerformanceModel.normalizedPower(Array(repeating: 200, count: 120)), 200, "steady power: NP = average")
        // 60 s at 300 W then 60 s at 100 W: average 200, NP must be higher because of the 4th power weighting
        let v = Array(repeating: 300, count: 60) + Array(repeating: 100, count: 60)
        let np = RidePerformanceModel.normalizedPower(v)!
        XCTAssertGreaterThan(np, 200); XCTAssertLessThan(np, 300)
        // reference value computed independently (rolling 30 s means, 4th-power mean, 4th root)
        var means: [Double] = []
        for i in 29..<v.count { let windowSum: Int = v[(i - 29)...i].reduce(0, +); means.append(Double(windowSum) / 30.0) }
        var fourth: Double = 0
        for m in means { fourth += m * m * m * m }
        let meanFourth: Double = fourth / Double(means.count)
        let ref: Int = Int(pow(meanFourth, 0.25).rounded())
        XCTAssertEqual(np, ref)
        XCTAssertEqual(RidePerformanceModel.normalizedPower([Int](repeating: 0, count: 40)), 0)
    }

    // APP-020: Delete all data removes every store, the recovery log, the loaded route and the Cyclift Watch acks, and a relaunch starts clean
    func testDeleteAllDataLeavesNothingBehind() {
        let d = dir(); let s = Store(directory: d, generatePlan: false)
        var p = RiderProfile.screened(); p.name = "Rashed"; s.profile = p; s.onboarded = true; s.guest = false
        _ = s.addRide(RideRecord(start: Date(), durationS: 600, distanceM: 5000, recorder: .phone, sources: ["Phone GPS"]))
        var st = StrengthSession(date: Date(), minutes: 30, focus: .fullBody); st.exercises = [ExerciseEntry(exercise: Exercise(id: "row", name: "Row"), sets: [SetEntry(reps: 8, weightKg: 40)])]; _ = s.addStrength(st)
        s.settings.healthReads.sleep = true; s.applyHealthSamples([HealthSample(kind: .sleep, value: 7, date: Date(), source: "Apple Watch")])
        UserDefaults.standard.set(["cyw-1": 9], forKey: "cyw.acked")
        XCTAssertFalse(s.recoveryLog.entries.isEmpty); XCTAssertEqual(s.strength.count, 1)
        s.resetAll()
        XCTAssertEqual(s.profile.name, ""); XCTAssertTrue(s.rides.isEmpty); XCTAssertTrue(s.strength.isEmpty); XCTAssertTrue(s.recoveryLog.entries.isEmpty)
        XCTAssertFalse(s.onboarded); XCTAssertTrue(s.guest); XCTAssertEqual(s.settings, AppSettings())
        XCTAssertNil(UserDefaults.standard.object(forKey: "cyw.acked"), "watch acknowledgement table removed")
        let again = Store(directory: d, generatePlan: false)
        XCTAssertEqual(again.profile.name, ""); XCTAssertTrue(again.rides.isEmpty); XCTAssertTrue(again.strength.isEmpty); XCTAssertTrue(again.recoveryLog.entries.isEmpty); XCTAssertFalse(again.onboarded)
    }
}
