import XCTest

/// App Store screenshots of the real app UI. Runs ONLY when the test runner has SCREENSHOT_DIR set (the asc-listing
/// workflow passes TEST_RUNNER_SCREENSHOT_DIR to xcodebuild); in normal CI it is skipped and changes nothing.
/// The seeded data is one rider's own training ("Alex"): a weekly hybrid plan, a home dumbbell routine, two rides
/// recorded with the BikeComputer + Apple Watch, one phone-only ride and two strength sessions. No other people.
final class StoreScreenshots: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = true }

    private var outDir: String? {
        let v = ProcessInfo.processInfo.environment["SCREENSHOT_DIR"] ?? ""
        return v.isEmpty ? nil : v
    }

    private func shot(_ app: XCUIApplication, _ name: String) {
        guard let dir = outDir else { return }
        sleep(2)   // let animations and charts settle
        let png = XCUIScreen.main.screenshot().pngRepresentation
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name).png")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        do { try png.write(to: url) } catch { XCTFail("could not write \(url.path): \(error)") }
        let a = XCTAttachment(data: png, uniformTypeIdentifier: "public.png"); a.name = name; a.lifetime = .keepAlways; add(a)
    }

    private func launch(todayKind: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = Self.alexStore(todayKind: todayKind)
        app.launch()
        XCTAssertTrue(app.navigationBars["Hi Alex"].waitForExistence(timeout: 25) || app.staticTexts["Hi Alex"].waitForExistence(timeout: 5), "Home did not appear")
        return app
    }

    private func dismissSheet(_ app: XCUIApplication) {
        for name in ["Done", "Close", "Cancel"] {
            let b = app.buttons[name].firstMatch
            if b.exists && b.isHittable { b.tap(); sleep(1); return }
        }
    }

    /// Strength day: Home (coach + today's routine), the scheduled strength workout, Plan, Progress.
    func test1StrengthDay() throws {
        guard outDir != nil else { throw XCTSkip("SCREENSHOT_DIR not set — store screenshots are only taken by the asc-listing workflow") }
        let app = launch(todayKind: "strength")
        shot(app, "01-home")
        let centre = app.buttons["centreButton"].firstMatch
        if centre.waitForExistence(timeout: 10) {
            centre.tap()
            if app.buttons["startWorkout"].firstMatch.waitForExistence(timeout: 10) { shot(app, "02-strength-workout") }
            dismissSheet(app)
        }
        app.buttons["Plan"].firstMatch.tap()
        shot(app, "03-plan")
        app.buttons["Progress"].firstMatch.tap()
        shot(app, "04-progress")
    }

    /// Ride day: the Ride dashboard (phone-only, idle — no live values are faked).
    func test2RideDay() throws {
        guard outDir != nil else { throw XCTSkip("SCREENSHOT_DIR not set — store screenshots are only taken by the asc-listing workflow") }
        let app = launch(todayKind: "endurance")
        let centre = app.buttons["centreButton"].firstMatch
        XCTAssertTrue(centre.waitForExistence(timeout: 10))
        centre.tap()
        sleep(2)
        shot(app, "05-ride")
    }

    // MARK: seed

    static func alexStore(todayKind: String) -> String {
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: today)!
        let tid = UUID().uuidString
        // Mon rest, Tue ride, Wed lift, Thu ride, Fri rest, Sat long ride, Sun lift — today forced to `todayKind`
        var kinds = ["rest", "endurance", "strength", "tempo", "rest", "long", "strength"]
        kinds[wd] = todayKind
        var plan: [String] = []
        for i in 0..<7 {
            let d = cal.date(byAdding: .day, value: i, to: monday)!.addingTimeInterval(7 * 3600)
            let k = kinds[i]
            let minutes = k == "rest" ? 0 : (k == "long" ? 120 : (k == "strength" ? 40 : 60))
            let tpl = k == "strength" ? "\"templateId\":\"\(tid)\",\"routineManual\":true," : ""
            let focus = k == "strength" ? "\"fullBody\"" : "null"
            plan.append("{\"id\":\"\(UUID().uuidString)\",\"date\":\"\(iso.string(from: d))\",\"kind\":\"\(k)\",\"minutes\":\(minutes),\"done\":\(i < wd && k != "rest"),\"skipped\":false,\"note\":\"\",\"edited\":false,\(tpl)\"strengthFocus\":\(focus),\"sequence\":0}")
        }
        func sets(_ reps: Int, _ kg: Double) -> String {
            (0..<3).map { _ in "{\"id\":\"\(UUID().uuidString)\",\"reps\":\(reps),\"weightKg\":\(kg),\"bodyweight\":false,\"unilateral\":false,\"done\":true}" }.joined(separator: ",")
        }
        let entries = """
        {"id":"\(UUID().uuidString)","exerciseId":"ex-003","name":"Goblet squat","pattern":"squat","sets":[\(sets(10, 16))],"notes":""},\
        {"id":"\(UUID().uuidString)","exerciseId":"ex-088","name":"Dumbbell row","pattern":"pull","sets":[\(sets(10, 14))],"superset":"A","notes":""},\
        {"id":"\(UUID().uuidString)","exerciseId":"ex-059","name":"Dumbbell bench press","pattern":"push","sets":[\(sets(8, 16))],"superset":"A","notes":""}
        """
        func strength(_ daysAgo: Int, _ rpe: Int) -> String {
            let d = cal.date(byAdding: .day, value: -daysAgo, to: today)!.addingTimeInterval(18 * 3600)
            return "{\"id\":\"\(UUID().uuidString)\",\"date\":\"\(iso.string(from: d))\",\"minutes\":38,\"focus\":\"fullBody\",\"customName\":\"\",\"rpe\":\(rpe),\"notes\":\"\",\"source\":\"manual\",\"templateId\":\"\(tid)\",\"exercises\":[\(entries)]}"
        }
        // rides: samples every 10 s (graphs only need the shape); board rides carry power, the phone-only ride does not
        func ride(_ daysAgo: Int, minutes: Int, board: Bool, basePower: Int) -> String {
            let start = cal.date(byAdding: .day, value: -daysAgo, to: today)!.addingTimeInterval(6 * 3600)
            var samples: [String] = []
            for t in stride(from: 0, to: minutes * 60, by: 10) {
                let wave = Int(12 * sin(Double(t) / 180))
                let hr = 128 + wave / 2 + min(t / 120, 14)
                let spd = 820 + wave * 4
                samples.append(board ? "{\"t\":\(t),\"w\":\(basePower + wave),\"cad\":\(88 + wave / 4),\"hr\":\(hr),\"speedCms\":\(spd)}"
                                     : "{\"t\":\(t),\"hr\":\(hr),\"speedCms\":\(spd)}")
            }
            let km = minutes * 60 * 82 / 10
            let zones = board ? "[\(minutes * 6),\(minutes * 42),\(minutes * 12),0,0,0,0]" : "[0,0,0,0,0,0,0]"
            let power = board ? "\"avgPower\":\(basePower),\"maxPower\":\(basePower + 140),\"normalizedPower\":\(basePower + 8),\"avgCadence\":88,\"kj\":\(basePower * minutes * 60 / 1000)," : ""
            return "{\"id\":\"\(UUID().uuidString)\",\"start\":\"\(iso.string(from: start))\",\"durationS\":\(minutes * 60),\"distanceM\":\(km),\(power)\"avgHR\":134,\"maxHR\":158,\"zoneSeconds\":\(zones),\"recorder\":\"\(board ? "board" : "phone")\",\"sources\":\(board ? "[\"BikeComputer\",\"Apple Watch\"]" : "[\"Phone GPS\",\"Apple Watch\"]"),\"demo\":false,\"samples\":[\(samples.joined(separator: ","))]}"
        }
        let rides = [ride(2, minutes: 60, board: true, basePower: 172), ride(5, minutes: 95, board: true, basePower: 160), ride(9, minutes: 45, board: false, basePower: 0)]
        return """
        {"schema":1,
         "profile":{"name":"Alex","goal":"fitness","hoursPerWeek":5,"level":"intermediate","weightKg":76,"age":34,"ftpW":230,"ftpHow":"entered","birthYear":1992,
                    "sports":["roadCycling","strength"],"version":3,"updatedAt":"2026-10-25T20:00:00Z","wheelMm":2096,"cadenceLow":85,"cadenceHigh":95,"hrZoneMethod":"maxHR",
                    "trainingMode":"hybrid","priority":"balanced","cyclingDaysPerWeek":3,"liftDaysPerWeek":2,"liftingHoursPerWeek":2,"preferredDays":[1,2,3,5,6]},
         "settings":{"units":"metric","phoneOnlyMode":false,"hrPref":"watch","keepScreenOn":true,"autoConnectBoard":false,"enabledConnections":["watch"],"appearance":"light","backgroundNotice":true,"coachTalk":"normal","coachEnabled":true,"appleHealthImportWorkouts":false},
         "plan":[\(plan.joined(separator: ","))],
         "rides":[\(rides.joined(separator: ","))],"tiles":["power","cadence","hr","speed","time","dist"],"onboarded":true,"guest":true,"createdAt":"2026-10-01T10:00:00Z","boardSync":[],"onboardingStage":0,
         "templates":[{"id":"\(tid)","name":"Home Dumbbell Session","focus":"fullBody","entries":[\(entries)],"updatedAt":"2026-10-20T19:00:00Z"}],
         "customExercises":[],"appliedProposals":[],
         "equipment":{"owned":["dumbbells","bench"],"excluded":[]},"activeSession":null,"ignoredInsights":[],
         "strength":[\(strength(4, 7)),\(strength(11, 8))]}
        """
    }
}
