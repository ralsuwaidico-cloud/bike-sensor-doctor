import XCTest
@testable import BikeComputer

final class ModelTests: XCTestCase {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("bc-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // MARK: PlanEngine
    func testWeekRespectsHoursAndLevel() {
        var p = RiderProfile(); p.hoursPerWeek = 5; p.level = .intermediate; p.goal = .endurance
        let monday = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let w = PlanEngine.week(starting: monday, profile: p)
        XCTAssertEqual(w.count, 7)
        XCTAssertEqual(w[0].kind, .rest)
        XCTAssertEqual(w[5].kind, .long); XCTAssertEqual(w[5].minutes, 100)        // 5 h × 20 min, clamped 60…180
        XCTAssertLessThanOrEqual(Double(PlanEngine.rideMinutes(w)) / 60, 6.0)
        p.hoursPerWeek = 3
        let small = PlanEngine.week(starting: monday, profile: p)
        XCTAssertEqual(small.filter { $0.kind.isRide }.count, 2)                   // hard day + long ride only
        p.level = .beginner; p.goal = .stronger
        XCTAssertEqual(PlanEngine.week(starting: monday, profile: p)[2].kind, .tempo)  // beginners never get threshold
        p.level = .advanced
        XCTAssertEqual(PlanEngine.week(starting: monday, profile: p)[2].kind, .threshold)
    }

    func testWorkoutStepsUseFTP() {
        let w = Workout(date: Date(), kind: .threshold, minutes: 70)
        let steps = w.steps(ftp: 200)
        XCTAssertEqual(steps.count, 3)
        XCTAssertTrue(steps[1].target.contains("186–204 W"))
        XCTAssertTrue(Workout(date: Date(), kind: .rest, minutes: 0).steps(ftp: 200).isEmpty)
    }

    // MARK: zones
    func testPowerZonesAndFTPAssumption() {
        var p = RiderProfile(); p.weightKg = 80; p.level = .intermediate; p.ftpHow = .assumed; p.refreshAssumption()
        XCTAssertEqual(p.ftpW, 240)
        XCTAssertEqual(p.zone(forWatts: 0), 1); XCTAssertEqual(p.zone(forWatts: 131), 1)
        XCTAssertEqual(p.zone(forWatts: 132), 2); XCTAssertEqual(p.zone(forWatts: 215), 3)
        XCTAssertEqual(p.zone(forWatts: 240), 4); XCTAssertEqual(p.zone(forWatts: 300), 6); XCTAssertEqual(p.zone(forWatts: 1000), 7)
        p.ftpHow = .entered; p.ftpW = 300; p.weightKg = 60; p.refreshAssumption()
        XCTAssertEqual(p.ftpW, 300, "an entered FTP is never overwritten by the assumption")
        p.age = 40; XCTAssertEqual(p.estimatedMaxHR, 180); p.maxHR = 190; XCTAssertEqual(p.estimatedMaxHR, 190)
    }

    // MARK: Store persistence
    func testStoreRoundTripSurvivesRelaunch() {
        let dir = tempDir()
        let s1 = Store(directory: dir, generatePlan: true)
        s1.profile.name = "Rashed"; s1.profile.ftpW = 231; s1.profile.ftpHow = .entered
        s1.settings.units = .imperial; s1.settings.phoneOnlyMode = true
        s1.onboarded = true; s1.guest = false; s1.appleUserId = "001.abc"
        var r = RideRecord(start: Date(timeIntervalSince1970: 1_761_300_000), durationS: 3600, distanceM: 25000, avgPower: 200, recorder: .board, sources: ["BikeComputer", "XDS"])
        r.boardRideId = 12; r.samples = [.init(t: 1, w: 200, cad: 90, hr: 140, speedCms: 800, lat: 25.2, lon: 55.3, alt: 10)]
        XCTAssertTrue(s1.addRide(r))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("store.json").path))

        let s2 = Store(directory: dir, generatePlan: false)
        XCTAssertEqual(s2.profile.name, "Rashed"); XCTAssertEqual(s2.profile.ftpW, 231); XCTAssertEqual(s2.profile.ftpHow, .entered)
        XCTAssertEqual(s2.settings.units, .imperial); XCTAssertTrue(s2.settings.phoneOnlyMode)
        XCTAssertTrue(s2.onboarded); XCTAssertFalse(s2.guest); XCTAssertEqual(s2.appleUserId, "001.abc")
        XCTAssertEqual(s2.rides.count, 1); XCTAssertEqual(s2.rides[0].samples.first?.lat, 25.2); XCTAssertEqual(s2.rides[0].boardRideId, 12)
        XCTAssertEqual(s2.plan.count, s1.plan.count)
        XCTAssertEqual(s2.snapshot.schema, StoreFile.currentSchema)
    }

    func testStoreImportsBuild14Layout() throws {
        let dir = tempDir()
        var p = RiderProfile(); p.name = "Legacy"; p.ftpW = 199
        try JSONEncoder().encode(p).write(to: dir.appendingPathComponent("profile.json"))
        let rides = [RideRecord(start: Date(), durationS: 600, distanceM: 3000, recorder: .phone, sources: ["Phone GPS"])]
        try JSONEncoder().encode(rides).write(to: dir.appendingPathComponent("rides.json"))
        let s = Store(directory: dir, generatePlan: false)
        XCTAssertEqual(s.profile.name, "Legacy"); XCTAssertEqual(s.profile.ftpW, 199); XCTAssertEqual(s.rides.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("store.json").path), "migrated into the single store file")
    }

    func testStoreFileDecodesV1JSONWithoutNewKeys() throws {
        // a v1 file written by an older build 15 without `settings` must still load (defaults fill in)
        let json = """
        {"schema":1,"profile":{"name":"A","goal":"endurance","hoursPerWeek":5,"level":"intermediate","weightKg":75,"age":35,"ftpW":225,"ftpHow":"assumed","hrPrefWatchFirst":false},
         "plan":[],"rides":[],"tiles":["power"],"onboarded":true,"guest":true,"createdAt":"2026-10-24T10:00:00Z"}
        """
        let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
        let f0 = try dec.decode(StoreFile.self, from: Data(json.utf8))
        XCTAssertEqual(f0.profile.name, "A"); XCTAssertEqual(f0.settings, AppSettings(), "missing settings → defaults, nothing lost")
        XCTAssertTrue(f0.onboarded); XCTAssertEqual(f0.tiles, ["power"])
        // migrate() repairs an empty tile list
        var f = StoreFile(); f.tiles = []
        XCTAssertEqual(StoreFile.migrate(f).tiles, Store.defaultTiles)
    }

    // MARK: ownership — one ride, one recorder
    func testNoDuplicateRidesAndSingleOwner() {
        let s = Store(directory: tempDir(), generatePlan: false)
        var a = RideRecord(start: Date(), durationS: 100, distanceM: 500, recorder: .board, sources: ["BikeComputer"]); a.boardRideId = 7
        XCTAssertTrue(s.addRide(a))
        var again = RideRecord(start: Date(), durationS: 100, distanceM: 500, recorder: .board, sources: ["BikeComputer"]); again.boardRideId = 7
        XCTAssertFalse(s.addRide(again), "the same board ride is never stored twice")
        XCTAssertFalse(s.addRide(a), "the same record is never stored twice")
        var demo = RideRecord(start: Date(), durationS: 100, distanceM: 500, recorder: .board, sources: ["DEMO"]); demo.demo = true
        XCTAssertFalse(s.addRide(demo), "demo rides never enter history")
        XCTAssertEqual(s.rides.count, 1)
        XCTAssertEqual(Set(s.rides.map { $0.recorder }).count, 1)
    }

    func testPhoneRideCannotStartOverBoardRideAndOwnerIsFixed() {
        let r = RideRecorder()
        XCTAssertEqual(r.owner, .none)
        XCTAssertTrue(r.start())                        // no board → phone owns the ride
        XCTAssertEqual(r.owner, .phone); XCTAssertEqual(r.state, .running)
        XCTAssertFalse(r.start(), "a second start while active does nothing")
        r.tick(); r.tick()
        XCTAssertEqual(r.elapsedS, 2)
        r.pause(); r.tick(); XCTAssertEqual(r.elapsedS, 2, "paused seconds are not counted")
        r.resume(); r.end()
        XCTAssertEqual(r.state, .ended)
        XCTAssertEqual(r.pendingResult?.recorder, .phone)
        XCTAssertNil(r.pendingResult?.avgPower, "no power is ever invented on a phone-only ride")
        r.finish()
        XCTAssertEqual(r.owner, .none); XCTAssertEqual(r.state, .idle)
        XCTAssertEqual(r.startMode(locationAuthorized: true), .phone)
    }

    func testDistanceRuleMatchesBoard() {
        // 1.8 km/h (50 cm/s) threshold and 50 m accuracy gate, exactly like bc_ride_add_speed on the board
        XCTAssertEqual(RideRecorder.distanceM(speedsCms: [833, 833, 40, nil, 833], haccM: [5, 5, 5, 5, 80]), 16)
        XCTAssertEqual(RideRecorder.normalized(Array(repeating: 200, count: 60)), 200)
        XCTAssertNil(RideRecorder.normalized(Array(repeating: 200, count: 10)))
    }

    func testWeekTotalsCountOnlyStoredRides() {
        let s = Store(directory: tempDir(), generatePlan: false)
        XCTAssertEqual(s.weekTotals(weeks: 4).count, 4)
        XCTAssertTrue(s.weekTotals(weeks: 4).allSatisfy { $0.rides == 0 })
        _ = s.addRide(RideRecord(start: Date(), durationS: 1800, distanceM: 12000, recorder: .phone, sources: ["Phone GPS"]))
        let last = s.weekTotals(weeks: 4).last!
        XCTAssertEqual(last.rides, 1); XCTAssertEqual(last.minutes, 30); XCTAssertEqual(last.km, 12, accuracy: 0.001)
    }

    func testResetRemovesEverything() {
        let dir = tempDir()
        let s = Store(directory: dir, generatePlan: false)
        s.profile.name = "X"; s.onboarded = true
        _ = s.addRide(RideRecord(start: Date(), durationS: 1, distanceM: 1, recorder: .phone, sources: []))
        s.resetAll()
        XCTAssertEqual(s.profile.name, ""); XCTAssertFalse(s.onboarded); XCTAssertTrue(s.rides.isEmpty); XCTAssertTrue(s.guest)
        XCTAssertFalse(s.plan.isEmpty, "a fresh plan is generated so the app is usable immediately")
    }
}
