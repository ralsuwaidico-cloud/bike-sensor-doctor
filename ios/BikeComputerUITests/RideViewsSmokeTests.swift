import XCTest

/// Ride views smoke test (Checkpoint F): a phone updated from build 40 with a RIDE scheduled today opens the Ride screen
/// from the centre button and switches through the three adaptive views (Cockpit → Map → Performance → Cockpit); every
/// view keeps the coach panel and the app stays in the foreground (RA-15). The seed follows LaunchSmokeTests.build40Store.
final class RideViewsSmokeTests: XCTestCase {

    override func setUpWithError() throws { continueAfterFailure = false }
    /// Screenshots land next to the other CI evidence (ci-logs ios/run-N) when LAYOUT_DIR is set by the workflow (same folder as the layout audit).
    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["LAYOUT_DIR"], !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("ride-\(name).png"))
    }

    func testSwitchThroughTheThreeRideViews() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = Self.rideDayStore()
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Rashed", timeout: 25), "seeded rider lands on Home")

        let centre = app.buttons["centreButton"].firstMatch
        XCTAssertTrue(centre.waitForExistence(timeout: 10))
        centre.tap()
        // Checkpoint C: the hub's Start opens the Ride screen; close a sheet if the plan offered a choice
        _ = app.openFromHub()
        for name in ["Done", "Cancel"] { let c = app.buttons[name].firstMatch; if c.exists && c.isHittable { c.tap(); break } }

        let cockpit = app.buttons["rideView.cockpit"].firstMatch
        XCTAssertTrue(cockpit.waitForExistence(timeout: 15), "view switcher on the live screen")
        // rc3: today's planned ride shows its current step with a target (entered FTP 210 W → watts allowed)
        let strip = app.descendants(matching: .any)["rideStepStrip"].firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 10), "current ride step shown")
        XCTAssertTrue(strip.label.contains("RPE"), "step target names the effort: \(strip.label)")
        XCTAssertTrue(app.otherElements["coachPanel"].firstMatch.exists, "coach panel embedded")
        XCTAssertTrue(app.buttons["rideMiniMap"].firstMatch.exists, "Cockpit carries the mini map")

        // Cockpit → Map → Performance → Cockpit; the coach panel stays, the app stays alive (RA-15)
        shot("night-cockpit")
        for (id, check) in [("rideView.map", "rideMapView"), ("rideView.performance", ""), ("rideView.cockpit", "rideMiniMap")] {
            let b = app.buttons[id].firstMatch
            XCTAssertTrue(b.waitForExistence(timeout: 5)); b.tap()
            if !check.isEmpty { XCTAssertTrue(app.descendants(matching: .any)[check].firstMatch.waitForExistence(timeout: 10), "\(id) shows \(check)") }
            XCTAssertTrue(app.otherElements["coachPanel"].firstMatch.exists, "coach panel kept in \(id)")
            XCTAssertEqual(app.state, .runningForeground, "app alive after switching to \(id)")
            shot("night-\(id.replacingOccurrences(of: "rideView.", with: ""))")
        }
        // the mini map opens the Map view
        app.buttons["rideMiniMap"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["rideMapView"].firstMatch.waitForExistence(timeout: 10), "mini map expands to the Map view")
        app.buttons["rideView.cockpit"].firstMatch.tap()

        // Why? opens the explanation in place; Ride settings and Details stay reachable
        let why = app.buttons["coachWhy"].firstMatch
        if why.exists && why.isEnabled { why.tap(); sleep(1); why.tap() }
        app.buttons["rideSettings"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Ride views"].firstMatch.waitForExistence(timeout: 10) || app.buttons["Done"].firstMatch.waitForExistence(timeout: 10), "Ride settings opens")
        // Checkpoint F acceptance: the Daylight display keeps every view, the coach panel and the controls on screen
        let daylight = app.segmentedControls["rideDisplayPicker"].buttons["Daylight"].firstMatch
        XCTAssertTrue(daylight.waitForExistence(timeout: 5), "Display picker offers Daylight"); daylight.tap()
        app.buttons["Done"].firstMatch.tap()
        for (id, check) in [("rideView.map", "rideMapView"), ("rideView.performance", ""), ("rideView.cockpit", "rideMiniMap")] {
            app.buttons[id].firstMatch.tap()
            if !check.isEmpty { XCTAssertTrue(app.descendants(matching: .any)[check].firstMatch.waitForExistence(timeout: 10), "daylight \(id) shows \(check)") }
            XCTAssertTrue(app.otherElements["coachPanel"].firstMatch.exists, "daylight: coach panel kept in \(id)")
            shot("daylight-\(id.replacingOccurrences(of: "rideView.", with: ""))")
        }
        XCTAssertTrue(app.descendants(matching: .any)["rideStepStrip"].firstMatch.exists, "daylight: step target shown")
        app.buttons["rideSettings"].firstMatch.tap()
        let night = app.segmentedControls["rideDisplayPicker"].buttons["Night"].firstMatch
        XCTAssertTrue(night.waitForExistence(timeout: 5)); night.tap()
        app.buttons["Done"].firstMatch.tap()
        app.buttons["rideDetails"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Ride details"].waitForExistence(timeout: 10))
        app.buttons["Done"].firstMatch.tap()
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// rc3 / ENG-E1: with an Unknown FTP (the build-121 starting assumption) the ride shows effort targets and no watts.
    func testUnknownFTPRideShowsNoWatts() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = Self.rideDayStore().replacingOccurrences(of: "\"ftpHow\":\"entered\"", with: "\"ftpHow\":\"assumed\"")
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Rashed", timeout: 25), "seeded rider lands on Home")
        let centre = app.buttons["centreButton"].firstMatch
        XCTAssertTrue(centre.waitForExistence(timeout: 10))
        centre.tap()
        _ = app.openFromHub()
        for name in ["Done", "Cancel"] { let c = app.buttons[name].firstMatch; if c.exists && c.isHittable { c.tap(); break } }
        let strip = app.descendants(matching: .any)["rideStepStrip"].firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 15), "current ride step shown")
        XCTAssertTrue(strip.label.contains("RPE"), strip.label)
        XCTAssertFalse(strip.label.contains(" W ·") || strip.label.contains(" W,"), "no watt target from an unknown FTP: \(strip.label)")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Checkpoint F slice 3 (RA-20…RA-24, owner regression item 3): START · PHONE → Pause → End → confirm → results page
    /// (route, headline, analysis, zones, records, coach) → Save → the ride is in Ride history and reopens its results.
    func testPauseEndReviewSaveThenHistory() {
        let app = XCUIApplication()
        app.launchEnvironment["BC_UITEST_SEED_JSON"] = Self.rideDayStore()
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Rashed", timeout: 25), "seeded rider lands on Home")
        let centre = app.buttons["centreButton"].firstMatch
        XCTAssertTrue(centre.waitForExistence(timeout: 10)); centre.tap()
        _ = app.openFromHub()
        for name in ["Done", "Cancel"] { let c = app.buttons[name].firstMatch; if c.exists && c.isHittable { c.tap(); break } }
        XCTAssertTrue(app.buttons["rideView.cockpit"].firstMatch.waitForExistence(timeout: 15), "ride screen")

        // history is reachable before a ride and says there is nothing yet
        let hist = app.buttons["rideHistoryButton"].firstMatch
        XCTAssertTrue(hist.waitForExistence(timeout: 5), "history button on the idle ride screen"); hist.tap()
        XCTAssertTrue(app.descendants(matching: .any)["rideHistoryEmpty"].firstMatch.waitForExistence(timeout: 10), "empty history explains itself")
        app.buttons["Done"].firstMatch.tap()

        let start = app.buttons["START · PHONE"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10), "phone start (no board in the simulator)"); start.tap()
        let pause = app.buttons["PAUSE"].firstMatch
        XCTAssertTrue(pause.waitForExistence(timeout: 10), "recording: Pause is offered")
        XCTAssertFalse(app.buttons["rideHistoryButton"].firstMatch.exists, "history is not offered during a ride")
        sleep(3)
        // switching views never interrupts the recording (item 1)
        app.buttons["rideView.performance"].firstMatch.tap(); app.buttons["rideView.map"].firstMatch.tap(); app.buttons["rideView.cockpit"].firstMatch.tap()
        XCTAssertTrue(app.buttons["PAUSE"].firstMatch.exists, "still recording after switching views")
        pause.tap()
        let end = app.buttons["END"].firstMatch
        XCTAssertTrue(end.waitForExistence(timeout: 5), "paused: End is offered (never disabled)"); end.tap()
        // the End confirmation
        let confirm = app.alerts.buttons.allElementsBoundByIndex.first { $0.label.lowercased().hasPrefix("end") } ?? app.buttons["End ride"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "End asks for confirmation"); confirm.tap()

        let headline = app.descendants(matching: .any)["rideResultHeadline"].firstMatch
        XCTAssertTrue(headline.waitForExistence(timeout: 15), "results page opens for review")
        for id in ["rideResultAnalysis", "rideResultZones", "rideResultRecords", "rideCoachSummary"] {
            XCTAssertTrue(app.descendants(matching: .any)[id].firstMatch.exists || app.descendants(matching: .any)[id].firstMatch.waitForExistence(timeout: 3), "\(id) on the results page")
        }
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'simulated'")).firstMatch.exists, "nothing simulated on a real recording")
        let save = app.buttons["rideSave"].firstMatch
        XCTAssertTrue(save.exists, "Save offered"); XCTAssertTrue(app.buttons["rideDiscard"].firstMatch.exists, "Discard offered")
        save.tap()
        // the post-ride check-in may follow; skip or close it whichever way it offers
        for name in ["Skip", "Not now", "Done", "Close", "Save"] { let c = app.buttons[name].firstMatch; if c.waitForExistence(timeout: 3) && c.isHittable { c.tap(); break } }
        XCTAssertTrue(app.buttons["rideHistoryButton"].firstMatch.waitForExistence(timeout: 15), "back on the idle ride screen")
        app.buttons["rideHistoryButton"].firstMatch.tap()
        let row = app.descendants(matching: .any)["rideHistoryRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the saved ride is listed"); row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["rideResultHeadline"].firstMatch.waitForExistence(timeout: 10), "the saved ride reopens its results page")
        XCTAssertEqual(app.state, .runningForeground)
    }

    /// Build-40 shaped store.json with an endurance ride scheduled TODAY (so the centre button reads "Ride now").
    static func rideDayStore() -> String {
        let iso = ISO8601DateFormatter()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: today) + 5) % 7
        let monday = cal.date(byAdding: .day, value: -wd, to: today)!
        let tid = UUID().uuidString
        var plan: [String] = []
        for i in 0..<7 {
            let d = cal.date(byAdding: .day, value: i, to: monday)!.addingTimeInterval(7 * 3600)
            let kind = i == wd ? "endurance" : (i % 2 == 0 ? "rest" : "strength")
            plan.append("{\"id\":\"\(UUID().uuidString)\",\"date\":\"\(iso.string(from: d))\",\"kind\":\"\(kind)\",\"minutes\":\(kind == "rest" ? 0 : 60),\"done\":false,\"skipped\":false,\"note\":\"\",\"edited\":false,\"strengthFocus\":\(kind == "strength" ? "\"fullBody\"" : "null"),\"sequence\":0}")
        }
        let set = "{\"id\":\"\(UUID().uuidString)\",\"reps\":10,\"weightKg\":20,\"bodyweight\":false,\"unilateral\":false,\"done\":true}"
        return """
        {"schema":1,
         "profile":{"name":"Rashed","goal":"fitness","hoursPerWeek":5,"level":"intermediate","weightKg":82,"age":35,"ftpW":210,"ftpHow":"entered","birthYear":1988,
                    "sports":["roadCycling","strength"],"version":14,"updatedAt":"2026-10-25T20:00:00Z","wheelMm":2096,"cadenceLow":85,"cadenceHigh":95,"hrZoneMethod":"maxHR",
                    "trainingMode":"hybrid","priority":"balanced","cyclingDaysPerWeek":3,"liftDaysPerWeek":3,"liftingHoursPerWeek":2,"preferredDays":[1,3,5,6]},
         "settings":{"units":"metric","phoneOnlyMode":false,"hrPref":"watch","keepScreenOn":true,"autoConnectBoard":true,"enabledConnections":["board","watch"],"appearance":"system","backgroundNotice":true,"coachTalk":"normal","coachEnabled":true,"appleHealthImportWorkouts":false},
         "plan":[\(plan.joined(separator: ","))],
         "rides":[],"tiles":["power","cadence","hr","speed","time","dist"],"onboarded":true,"guest":true,"createdAt":"2026-10-24T10:00:00Z","boardSync":[],"onboardingStage":0,
         "templates":[{"id":"\(tid)","name":"Short Full Body Workout","focus":"fullBody","entries":[{"id":"\(UUID().uuidString)","exerciseId":"ex-003","name":"Goblet squat","pattern":"squat","sets":[\(set),\(set)],"notes":""}],"updatedAt":"2026-10-25T19:00:00Z"}],
         "customExercises":[],"appliedProposals":[],"weekdayRoutines":{},"equipment":{"owned":["dumbbells","bench"],"excluded":[]},"activeSession":null,"ignoredInsights":[],
         "strength":[]}
        """
    }
}
