import XCTest

/// Cyclift Lab — FAST check of the Training Hub v1.4 cycling screen (design sheets 05a / 05b): Focus, Map, pause,
/// resume, lap, finish. Lab has no sensors and no GPS, so the ride is the labelled demonstration; the check asserts
/// that the screen SAYS so everywhere a figure could be taken for real, and that the Map view draws nothing in place of
/// a route. Required controls fail the check when absent.
final class LabFastCycling: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["LAYOUT_DIR"] ?? ""
        guard !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("fast-\(name).png"))
    }
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_FRESH_DEMO"] = "1"
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "required: Home with the demo athlete")
        return app
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func button(_ app: XCUIApplication, _ id: String, _ what: String) -> XCUIElement {
        let b = app.buttons[id].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: 8), "required: \(what) (\(id))")
        return b
    }
    /// Opens the simulated ride from the Train panel and returns once the cycling screen is shown.
    private func openRide() -> XCUIApplication {
        let app = launch()
        button(app, "centreButton", "the Train button").tap()
        button(app, "trainPanelRide", "the panel offers a ride").tap()
        XCTAssertTrue(el(app, "cyclingRecorderV14").waitForExistence(timeout: 10), "required: the ride opens the cycling screen")
        return app
    }

    /// The whole journey in one launch: Focus → Map → Focus → pause → resume → lap → finish → back → finish → close.
    func testFocusMapPauseResumeLapFinish() {
        let app = openRide()

        // — Focus, simulated —
        let strip = el(app, "cyclingSimulated")
        XCTAssertTrue(strip.exists && strip.label.contains("SIMULATED") && strip.label.contains("nothing is recorded or saved"), "required: the simulated strip (\(strip.label))")
        let source = el(app, "cyclingSource")
        XCTAssertTrue(source.exists, "required: the source line")
        XCTAssertTrue(source.label.contains("Simulated") && source.label.contains("no sensor"), "required: the source line names the figures as simulated, not as a sensor (\(source.label))")
        for id in ["cyclingState", "cyclingElapsed", "cyclingLap", "cyclingPowerLabel", "cyclingPower", "cyclingPowerLine", "cyclingTarget", "cyclingHR", "cyclingCadence", "cyclingSpeed", "cyclingDistance"] {
            XCTAssertTrue(el(app, id).exists, "required: Focus shows \(id)")
        }
        XCTAssertEqual(el(app, "cyclingState").label, "Cycling", "riding: the state line")
        XCTAssertTrue(el(app, "cyclingLap").label.contains("Moving") && el(app, "cyclingLap").label.contains("lap 1") && el(app, "cyclingLap").label.contains("interval"), "the time line: moving, lap, interval (\(el(app, "cyclingLap").label))")
        XCTAssertTrue(el(app, "cyclingTarget").label.contains("Target 220–240 W"), "the target band (\(el(app, "cyclingTarget").label))")
        XCTAssertTrue(el(app, "cyclingHR").label.contains("bpm"), "heart rate is a value with its unit (\(el(app, "cyclingHR").label))")
        let focusTab = button(app, "cyclingViewFocus", "the Focus tab"), mapTab = button(app, "cyclingViewMap", "the Map tab")
        XCTAssertTrue(focusTab.isSelected && !mapTab.isSelected, "Focus is the first view")
        XCTAssertTrue(app.buttons["cyclingLapButton"].firstMatch.exists && app.buttons["cyclingPause"].firstMatch.exists, "required: riding offers Lap and Pause")
        XCTAssertFalse(app.buttons["cyclingFinish"].firstMatch.exists || app.buttons["cyclingResume"].firstMatch.exists, "riding: no Finish, no Resume (rule RA-20)")
        XCTAssertFalse(app.buttons["cyclingStart"].firstMatch.exists || app.buttons["cyclingClose"].firstMatch.exists, "the demonstration has no Start and no Close while riding")
        app.settleForScreenshot(1); shot("cycling-1-focus")

        // — Map: Lab has no location, and says so; nothing is drawn in place of a route —
        mapTab.tap()
        let none = el(app, "cyclingMapUnavailable")
        XCTAssertTrue(none.waitForExistence(timeout: 5), "required: the Map view states that there is no map")
        XCTAssertTrue(none.label.contains("No map in this demonstration") && none.label.contains("Location is not used in Cyclift Lab"), "required: the honest no-location statement (\(none.label))")
        XCTAssertFalse(el(app, "cyclingMapLive").exists, "Lab draws no map")
        XCTAssertEqual(app.maps.count, 0, "Lab creates no map view")
        for t in ["TIME", "KM", "POWER"] { XCTAssertTrue(el(app, "cyclingMapTile-\(t)").exists, "required: the Map view keeps \(t)") }
        XCTAssertTrue(mapTab.isSelected, "Map is selected")
        XCTAssertTrue(el(app, "cyclingSource").exists && el(app, "cyclingSource").label.contains("Simulated"), "the Map view keeps the simulated source line")
        XCTAssertTrue(app.buttons["cyclingPause"].firstMatch.exists, "the controls stay in place on the Map view")
        app.settleForScreenshot(1); shot("cycling-2-map-no-location")
        focusTab.tap()
        XCTAssertTrue(el(app, "cyclingPower").waitForExistence(timeout: 5), "required: back on Focus")
        XCTAssertFalse(el(app, "cyclingMapUnavailable").exists, "the Map view is gone")

        // — Pause —
        button(app, "cyclingPause", "Pause").tap()
        let resume = button(app, "cyclingResume", "paused offers Resume"), finish = button(app, "cyclingFinish", "paused offers Finish")
        XCTAssertTrue(el(app, "cyclingState").label.contains("paused"), "paused is said in words (\(el(app, "cyclingState").label))")
        let paused = el(app, "cyclingPausedNotice")
        XCTAssertTrue(paused.exists && paused.label.contains("Time and distance are not counting"), "required: the pause statement (\(paused.label))")
        XCTAssertFalse(app.buttons["cyclingPause"].firstMatch.exists, "paused: no Pause")
        XCTAssertFalse(app.buttons["cyclingLapButton"].firstMatch.isEnabled, "paused: Lap is inactive")
        let frozen = el(app, "cyclingElapsed").label; app.settleForScreenshot(3)
        XCTAssertEqual(el(app, "cyclingElapsed").label, frozen, "the clock does not count while paused")
        XCTAssertTrue(el(app, "cyclingLap").label.contains("paused"), "the time line says how long the pause is (\(el(app, "cyclingLap").label))")
        shot("cycling-3-paused")

        // — Resume, then Lap —
        resume.tap()
        let pause = button(app, "cyclingPause", "resumed offers Pause")
        XCTAssertEqual(el(app, "cyclingState").label, "Cycling", "resumed: riding again")
        XCTAssertFalse(el(app, "cyclingPausedNotice").exists, "resumed: the pause statement is gone")
        XCTAssertFalse(finish.exists, "resumed: no Finish")
        shot("cycling-4-resumed")
        let lap = button(app, "cyclingLapButton", "Lap")
        XCTAssertTrue(lap.isEnabled, "riding: Lap is active"); lap.tap()
        XCTAssertTrue(el(app, "cyclingLap").label.contains("lap 2"), "Lap counts a lap (\(el(app, "cyclingLap").label))")
        app.settleForScreenshot(1); shot("cycling-5-lap")

        // — Finish: the page states what the demonstration was; Back to ride returns to the paused ride —
        pause.tap(); button(app, "cyclingFinish", "Finish").tap()
        let ended = el(app, "cyclingDemoEnded")
        XCTAssertTrue(ended.waitForExistence(timeout: 5), "required: finishing says the demonstration ended")
        XCTAssertTrue(ended.label.contains("nothing was recorded or saved") && ended.label.contains("1 lap"), "the finish page says nothing was saved (\(ended.label))")
        XCTAssertTrue(el(app, "cyclingSimulated").exists, "the finish page keeps the simulated strip")
        for id in ["cyclingFinishElapsed", "cyclingFinishDistance", "cyclingFinishPower", "cyclingFinishHR", "cyclingFinishOutcome"] { XCTAssertTrue(el(app, id).exists, "required: the finish page shows \(id)") }
        XCTAssertTrue(el(app, "cyclingFinishOutcome").label.contains("Nothing"), "saved: nothing (\(el(app, "cyclingFinishOutcome").label))")
        XCTAssertFalse(app.buttons["Save"].firstMatch.exists, "the demonstration offers no Save")
        app.settleForScreenshot(1); shot("cycling-6-ended")
        button(app, "cyclingFinishBack", "Back to ride").tap()
        XCTAssertTrue(app.buttons["cyclingResume"].firstMatch.waitForExistence(timeout: 5), "required: Back to ride returns to the paused ride")
        XCTAssertTrue(el(app, "cyclingLap").label.contains("lap 2"), "the ride is as it was left")
        button(app, "cyclingFinish", "Finish again").tap()
        XCTAssertTrue(el(app, "cyclingDemoEnded").waitForExistence(timeout: 5), "required: the finish page again")
        button(app, "cyclingDemoClose", "Close").tap()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 15), "required: closing returns to the app")
        XCTAssertFalse(el(app, "cyclingRecorderV14").exists, "the cycling screen is closed")
    }

    /// The sensor treatments of sheet 05a C3–C5, as the fixed script reaches them (ride seconds 30–72): a measured zero
    /// reads "Coasting", a stale meter keeps its last value with its age, a lost meter shows "—" and never a 0.
    func testSensorStatesAreShownTruthfully() {
        let app = openRide()
        func wait(_ what: String, _ timeout: TimeInterval, _ ok: @escaping () -> Bool) {
            let done = expectation(description: what)
            let t = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in if ok() { timer.invalidate(); done.fulfill() } }
            let r = XCTWaiter().wait(for: [done], timeout: timeout); t.invalidate()
            XCTAssertEqual(r, .completed, "required: \(what)")
        }
        let line = el(app, "cyclingPowerLine"), power = el(app, "cyclingPower"), label = el(app, "cyclingPowerLabel")
        wait("a measured zero is named Coasting", 60) { line.label == "Coasting" }
        XCTAssertEqual(power.label, "0", "coasting shows the measured 0"); shot("cycling-state-1-measured-zero")
        wait("a stale meter shows the age of its last reading", 40) { line.label.hasPrefix("Last reading") }
        XCTAssertEqual(power.label, "231", "stale keeps the last value"); XCTAssertEqual(label.label, "POWER · NO UPDATE")
        XCTAssertTrue(el(app, "cyclingWarning").exists && el(app, "cyclingWarning").label.contains("not updating"), "stale: the warning box"); shot("cycling-state-2-stale")
        wait("a lost meter shows no signal", 30) { line.label == "No signal" }
        XCTAssertEqual(power.label, "—", "a lost meter shows a dash, never 0")
        XCTAssertTrue(el(app, "cyclingCadence").label.contains("—") && el(app, "cyclingCadence").label.contains("No signal"), "cadence goes with the meter (\(el(app, "cyclingCadence").label))")
        XCTAssertTrue(el(app, "cyclingWarning").label.contains("not being recorded"), "lost: the warning says nothing is recorded (\(el(app, "cyclingWarning").label))")
        XCTAssertTrue(el(app, "cyclingSource").label.contains("Simulated"), "the source line still says simulated")
        shot("cycling-state-3-lost")
    }
}
