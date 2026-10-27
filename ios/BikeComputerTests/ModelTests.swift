import XCTest
@testable import BikeComputer

final class ModelTests: XCTestCase {
    private func tempDir() -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("bc-test-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // MARK: PlanEngine
    func testWeekIsBuiltAroundAvailability() {
        var p = RiderProfile(); p.hoursPerWeek = 5; p.level = .intermediate; p.goal = .endurance
        let monday = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        let a = WeeklyAvailability.suggested(hoursPerWeek: 5)
        let w = PlanEngine.week(starting: monday, profile: p, availability: a)
        XCTAssertEqual(w.count, 7)
        XCTAssertEqual(w[0].kind, .rest)                                              // Monday rest stays rest
        XCTAssertEqual(w[5].kind, .long); XCTAssertEqual(w[5].minutes, 100)           // Saturday is the longest cycling day
        XCTAssertEqual(w[6].kind, .strength)                                          // lift day → strength
        XCTAssertEqual(w.filter { $0.kind.isRide }.count, a.cycleDays)                // every cycling day gets a ride, nothing else does
        for (i, d) in a.days.enumerated() where d.activity == .rest { XCTAssertEqual(w[i].kind, .rest); XCTAssertEqual(w[i].minutes, 0) }
        for (i, d) in a.days.enumerated() where d.activity == .cycle { XCTAssertEqual(w[i].minutes, max(20, d.minutes)) }   // per-day duration respected
        XCTAssertEqual(w.filter { $0.kind == .tempo || $0.kind == .threshold }.count, 1)   // one quality session
        p.level = .beginner; p.goal = .stronger
        XCTAssertEqual(PlanEngine.week(starting: monday, profile: p, availability: a).filter { $0.kind == .threshold }.count, 0)   // beginners never get threshold
        p.level = .advanced
        XCTAssertEqual(PlanEngine.week(starting: monday, profile: p, availability: a).filter { $0.kind == .threshold }.count, 1)
        // a custom schedule: cycle Mon/Wed/Fri 45 min, lift Tue, other Sun, rest the others
        var c = Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7)
        c[0] = DayAvailability(activity: .cycle, minutes: 45); c[2] = DayAvailability(activity: .cycle, minutes: 45); c[4] = DayAvailability(activity: .cycle, minutes: 45)
        c[1] = DayAvailability(activity: .lift, minutes: 40); c[6] = DayAvailability(activity: .other, minutes: 60)
        let w2 = PlanEngine.week(starting: monday, profile: p, availability: WeeklyAvailability(days: c))
        XCTAssertEqual(w2[1].kind, .strength); XCTAssertEqual(w2[1].minutes, 40)
        XCTAssertEqual(w2[6].kind, .other); XCTAssertEqual(w2[6].minutes, 60)
        XCTAssertEqual(w2[3].kind, .rest); XCTAssertEqual(w2[5].kind, .rest)
        XCTAssertTrue([0, 2, 4].allSatisfy { w2[$0].kind.isRide && w2[$0].minutes == 45 })
    }

    /// 0.7.0: the engine never generates over a budget; the over-hours is reported as a conflict with options and the
    /// flexible days are trimmed (shown, not silent). Suggestions still appear when the rider's own edits push a week over.
    func testOverHoursSuggestsAdjustmentsInsteadOfCutting() {
        var p = RiderProfile(); p.hoursPerWeek = 3
        let monday = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        var d = Array(repeating: DayAvailability(activity: .rest, minutes: 0), count: 7)
        for i in [1, 3, 5] { d[i] = DayAvailability(activity: .cycle, minutes: 90) }
        let a = WeeklyAvailability(days: d)
        let c = a.conflicts(profile: p)
        XCTAssertEqual(c.count, 1); XCTAssertEqual(c[0].overMinutes, 90); XCTAssertTrue(c[0].text.contains("1 h 30 min over"))
        XCTAssertGreaterThanOrEqual(c[0].options.count, 2)
        let fit = WeeklyAvailability.fit(a, profile: p)
        XCTAssertEqual(fit.availability.cycleMinutes, 180); XCTAssertEqual(fit.availability.cycleDays, 3, "no day dropped"); XCTAssertFalse(fit.trimmed.isEmpty, "the trim is explained")
        let w = PlanEngine.week(starting: monday, profile: p, availability: a)
        XCTAssertEqual(PlanEngine.rideMinutes(w), 180, "never over the 3 h budget")
        XCTAssertTrue(PlanEngine.suggestions(for: w, hoursPerWeek: 3).isEmpty)
        // the rider edits a session to 2 h by hand → the week is over → suggestions, nothing cut
        var edited = w; if let i = edited.firstIndex(where: { $0.kind.isRide }) { edited[i].minutes = 150; edited[i].edited = true }
        let s = PlanEngine.suggestions(for: edited, hoursPerWeek: 3)
        XCTAssertFalse(s.isEmpty); XCTAssertTrue(s[0].contains("1 h 30 min over"))
        XCTAssertEqual(PlanEngine.rideMinutes(edited), 270)
        XCTAssertTrue(PlanEngine.suggestions(for: edited, hoursPerWeek: 5).isEmpty)
    }

    func testDurationFormatter() {
        XCTAssertEqual(Fmt.duration(minutes: 100), "1 h 40 min")
        XCTAssertEqual(Fmt.duration(minutes: 45), "45 min")
        XCTAssertEqual(Fmt.duration(minutes: 120), "2 h")
        XCTAssertEqual(Fmt.duration(minutes: 0), "0 min")
        XCTAssertEqual(Fmt.duration(seconds: 5400), "1 h 30 min")
        XCTAssertEqual(Fmt.compact(minutes: 100), "1h40"); XCTAssertEqual(Fmt.compact(minutes: 45), "45′"); XCTAssertEqual(Fmt.compact(minutes: 0), "—")
    }

    func testEditedWorkoutsSurviveRegeneration() {
        let dir = tempDir()
        let store = Store(directory: dir, generatePlan: true)
        let cal = Calendar.current
        let nextWeek = cal.date(byAdding: .day, value: 7, to: Date())!
        guard let w = store.workouts(weekOf: nextWeek).first(where: { $0.kind.isRide }) else { return XCTFail("no ride next week") }
        var e = w; e.minutes = 33; store.edit(e)
        XCTAssertTrue(store.plan.first { $0.id == w.id }!.edited)
        store.regenerate(weekOf: nextWeek, replaceEdited: false)
        XCTAssertEqual(store.plan.first { $0.id == w.id }?.minutes, 33)              // kept
        XCTAssertEqual(store.editedCount(weekOf: nextWeek), 1)
        store.regenerate(weekOf: nextWeek, replaceEdited: true)
        XCTAssertNil(store.plan.first { $0.id == w.id })                                // replaced after confirmation
        XCTAssertEqual(store.workouts(weekOf: nextWeek).count, 7)
        // an older store.json without "edited"/"availability" still loads
        let reload = Store(directory: dir, generatePlan: false)
        XCTAssertEqual(reload.plan.count, store.plan.count)
    }

    func testTimelineDedupesAndComputesTSS() {
        XCTAssertEqual(Timeline.tss(normalizedPower: 200, durationS: 3600, ftp: 200), 100)
        XCTAssertNil(Timeline.tss(normalizedPower: nil, durationS: 3600, ftp: 200))
        XCTAssertNil(Timeline.tss(normalizedPower: 200, durationS: 3600, ftp: 0))
        let t0 = Date(timeIntervalSince1970: 1_761_300_000)
        var a = RideRecord(start: t0, durationS: 3600, distanceM: 30000, recorder: .board, sources: ["BikeComputer"]); a.boardRideId = 7; a.boardId = "aa"; a.avgPower = 180; a.normalizedPower = 190
        var b = RideRecord(start: t0.addingTimeInterval(20), durationS: 3590, distanceM: 29900, recorder: .board, sources: ["BikeComputer"]); b.boardRideId = 7
        var c = RideRecord(start: t0.addingTimeInterval(86400), durationS: 1800, distanceM: 12000, recorder: .phone, sources: ["Phone GPS"])
        c.samples = [RideRecord.Sample(t: 0, w: nil, cad: nil, hr: 120, speedCms: 500, lat: nil, lon: nil, alt: nil)]
        // quality release: a session is completed only by evidence or an explicit "Mark done" (completion = .marked);
        // a bare done flag without either is not shown as completed (StoreMigration rule M3 resets such flags)
        var marked = Workout(date: t0.addingTimeInterval(-86400 * 2), kind: .strength, minutes: 30, done: true); marked.completion = .marked
        let plan = [marked, Workout(date: t0.addingTimeInterval(-86400 * 3), kind: .endurance, minutes: 60), Workout(date: t0, kind: .endurance, minutes: 60)]
        let tl = Timeline.build(rides: [a, b, c], plan: plan, ftp: 200, now: t0.addingTimeInterval(86400 * 3))
        XCTAssertEqual(tl.filter { $0.rideId != nil }.count, 2)                        // the duplicate board ride is gone
        XCTAssertEqual(tl.first { $0.rideId == a.id }?.tss, 90)                         // 3600 × 190² / (200² × 3600) × 100
        XCTAssertNil(tl.first { $0.rideId == c.id }?.tss)
        XCTAssertEqual(tl.filter { $0.workoutId != nil }.count, 2)                      // the ride on t0 represents its workout
        XCTAssertEqual(tl.first { $0.title == "Endurance" }?.status, .missed)
        XCTAssertEqual(tl.first { $0.title == "Strength" }?.status, .completed)
        XCTAssertEqual(tl.first?.date, c.start)                                          // newest first
        XCTAssertNil(Timeline.trend(tl) { $0.avgPower })                                 // < 5 points → no sparkline
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
        let r = RideRecorder(autoTick: false)
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

    // MARK: FTP from rides
    private func powerRide(_ watts: [Int?], start: Date = Date(), recorder: RideRecord.Recorder = .phone) -> RideRecord {
        var r = RideRecord(start: start, durationS: watts.count, distanceM: 0, recorder: recorder, sources: ["test"])
        r.samples = watts.enumerated().map { RideRecord.Sample(t: $0.offset + 1, w: $0.element) }
        r.avgPower = watts.compactMap { $0 }.reduce(0, +) / max(1, watts.compactMap { $0 }.count)
        return r
    }

    func testBestMeanPowerOnSyntheticSeries() {
        // 10 min easy at 150 W, 20 min hard at 260 W, 10 min easy at 140 W → best 20 min = 260, best 60 impossible (40 min ride)
        let series: [Int?] = Array(repeating: 150, count: 600) + Array(repeating: 260, count: 1200) + Array(repeating: 140, count: 600)
        let r = powerRide(series)
        XCTAssertEqual(r.best20, 260)
        XCTAssertNil(r.best60)
        // a window with too many missing seconds (> 5 %) is never counted
        var holes = series; for i in 600..<700 { holes[i] = nil }
        XCTAssertLessThan(powerRide(holes).best20!, 260)
        XCTAssertNil(powerRide(Array(repeating: 200, count: 1199)).best20)      // 1 s short of 20 min
        XCTAssertEqual(Store.proposedFTP(best20: 260), 247)
    }

    func testFTPIsProposedNeverAutoApplied() {
        let s = Store(directory: tempDir(), generatePlan: false)
        s.profile.ftpW = 240; s.profile.ftpHow = .entered
        let series: [Int?] = Array(repeating: 280, count: 1200)
        XCTAssertTrue(s.addRide(powerRide(series)))
        XCTAssertEqual(s.profile.ftpW, 240, "a tested FTP is never overwritten without the rider")
        XCTAssertEqual(s.profile.ftpHow, .entered)
        XCTAssertEqual(s.ftpSuggestion?.watts, 266)
        XCTAssertEqual(s.ftpSuggestion?.best20, 280)
        s.acceptFTPSuggestion()
        XCTAssertEqual(s.profile.ftpW, 266); XCTAssertEqual(s.profile.ftpHow, .fromRides); XCTAssertNotNil(s.profile.ftpFromDate)
        XCTAssertNil(s.ftpSuggestion)
        // quality release: 95 % of a ride's best 20 min is an estimate, never "tested"; this ride's power was not verified
        XCTAssertEqual(s.profile.ftpConfidence, .unverified); XCTAssertEqual(s.profile.ftpLabel, "Unverified")
        // a ride within 2 % of the current FTP proposes nothing; a demo ride proposes nothing
        XCTAssertTrue(s.addRide(powerRide(Array(repeating: 282, count: 1200), start: Date().addingTimeInterval(60))))
        XCTAssertNil(s.ftpSuggestion)
        var demo = powerRide(Array(repeating: 400, count: 1200), start: Date().addingTimeInterval(120)); demo.demo = true
        XCTAssertFalse(s.addRide(demo), "demo rides are never stored"); XCTAssertNil(s.ftpSuggestion)
    }

    // MARK: board history import — the board owns its rides, nothing is duplicated
    func testImportBoardRideMergesMirrorAndDedupes() {
        let s = Store(directory: tempDir(), generatePlan: false)
        let start = Date(timeIntervalSince1970: 1_792_850_000)
        // the phone mirrored board ride 5 live (no boardId yet, approximate start)
        var mirror = RideRecord(boardRideId: 5, start: start.addingTimeInterval(20), durationS: 3500, distanceM: 30000, recorder: .board, sources: ["BikeComputer"])
        mirror.samples = [RideRecord.Sample(t: 1, w: 200, lat: 25.2, lon: 55.3)]
        XCTAssertTrue(s.addRide(mirror))
        var b = BCLink.RideSummary(); b.id = 5; b.durationS = 3600; b.distanceM = 30450; b.avgPower = 190; b.startEpochS = 1_792_850_000; b.best20 = 230
        XCTAssertTrue(s.importBoardRide(b, boardId: "aa:bb"))
        XCTAssertEqual(s.rides.count, 1, "the mirror and the board summary are one ride")
        XCTAssertEqual(s.rides[0].durationS, 3600, "board totals win"); XCTAssertEqual(s.rides[0].boardId, "aa:bb")
        XCTAssertTrue(s.rides[0].hasTrack, "the phone's GPS track is kept")
        XCTAssertEqual(s.rides[0].start, start)
        // the same summary again (next sync) changes nothing
        XCTAssertTrue(s.importBoardRide(b, boardId: "aa:bb")); XCTAssertEqual(s.rides.count, 1)
        // a ride the phone never saw is added once; a demo ride is dropped
        var c = BCLink.RideSummary(); c.id = 6; c.durationS = 1800; c.startEpochS = 1_792_900_000
        XCTAssertTrue(s.importBoardRide(c, boardId: "aa:bb")); XCTAssertTrue(s.importBoardRide(c, boardId: "aa:bb"))
        var d = BCLink.RideSummary(); d.id = 7; d.demo = true
        XCTAssertFalse(s.importBoardRide(d, boardId: "aa:bb"))
        XCTAssertEqual(s.rides.count, 2)
        XCTAssertEqual(s.highestBoardRideId(for: "aa:bb"), 6)
        XCTAssertEqual(s.highestBoardRideId(for: "other"), 0)
        XCTAssertTrue(s.rides.allSatisfy { $0.recorder == .board })
    }

    // MARK: phone recording survives a suspension as a marked gap
    func testSuspensionBecomesGapNotInterpolation() {
        let r = RideRecorder(autoTick: false)
        XCTAssertTrue(r.start())
        r.tick(); r.tick()
        XCTAssertEqual(r.elapsedS, 2); XCTAssertEqual(r.gapSeconds, 0)
        r.simulateSuspension(seconds: 30)          // last tick 30 s ago: 29 seconds were never observed, this tick is the 30th
        r.tick()
        XCTAssertEqual(r.gapSeconds, 29)
        XCTAssertEqual(r.elapsedS, 32)
        XCTAssertEqual(r.samples.filter { $0.gap == true }.count, 29)
        XCTAssertTrue(r.samples.filter { $0.gap == true }.allSatisfy { $0.w == nil && $0.speedCms == nil && $0.hr == nil })
        r.end()
        XCTAssertEqual(r.pendingResult?.gapSeconds, 29)
        XCTAssertEqual(r.pendingResult?.durationS, 32)
    }
}
