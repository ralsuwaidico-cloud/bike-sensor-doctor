import XCTest

/// Cyclift Lab — focused checks for the Train ball (Navigation v1.2, sheet F4), minimise / restore, the session that
/// survives the app ending (Training Hub v1.4, sheet 08), the superset round flow (04b), correcting a logged set and
/// the compact panel's shortcuts (06b). Each check launches from a fresh demo athlete in one theme. Required controls
/// fail the check when absent. Screenshots: fast-train-*.png in LAYOUT_DIR.
final class LabFastTrain: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = true }

    private func shot(_ name: String) {
        let dir = ProcessInfo.processInfo.environment["LAYOUT_DIR"] ?? ""
        guard !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("fast-train-\(name).png"))
    }
    private func launch(_ extra: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["LAB_FRESH_DEMO"] = "1"
        app.launchEnvironment["LAB_THEME"] = "obsidian"
        for (k, v) in extra { app.launchEnvironment[k] = v }
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "required: Home with the demo athlete")
        return app
    }
    private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private func first(_ app: XCUIApplication, prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }
    private func ball(_ app: XCUIApplication) -> XCUIElement { app.buttons["centreButton"].firstMatch }
    private func ballValue(_ app: XCUIApplication) -> String { (ball(app).value as? String) ?? "" }
    /// The ball is on screen and can be tapped (a page that was covering it has finished closing).
    private func ballReady(_ app: XCUIApplication, timeout: TimeInterval = 10) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if ball(app).exists && ball(app).isHittable { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }
    private func isClock(_ s: String) -> Bool { s.range(of: "^[0-9]{2}:[0-9]{2}$", options: .regularExpression) != nil }

    /// Train panel → today's session → preparation → Start: the recorder is on screen.
    private func startTodaysWorkout(_ app: XCUIApplication) {
        XCTAssertTrue(ball(app).waitForExistence(timeout: 8), "required: the Train ball")
        XCTAssertEqual(ball(app).label, "Train, no active session", "idle ball")
        XCTAssertEqual(ballValue(app), "", "idle: no timer in the ball")
        ball(app).tap()
        let primary = app.buttons["trainPanelPrimary"].firstMatch
        XCTAssertTrue(primary.waitForExistence(timeout: 8), "required: the panel offers today's session"); primary.tap()
        let start = app.buttons["startWorkout"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10), "required: Start on the preparation screen"); start.tap()
        XCTAssertTrue(el(app, "strengthRecorderV14").waitForExistence(timeout: 10), "required: the v1.4 recorder")
    }
    /// Minimise. When the recorder was opened from the preparation screen, that screen is underneath (existing,
    /// checked behaviour); its Back returns to the app, where the ball is.
    private func minimiseToBall(_ app: XCUIApplication) {
        let m = app.buttons["recorderMinimise"].firstMatch
        XCTAssertTrue(m.waitForExistence(timeout: 5), "required: Minimise"); m.tap()
        let back = app.buttons["prepareBack"].firstMatch
        if back.waitForExistence(timeout: 3) { back.tap() }
        XCTAssertTrue(ballReady(app), "required: after Minimise the Train ball is on screen")
        XCTAssertFalse(el(app, "strengthRecorderV14").exists, "the recorder is closed")
    }

    /// (a) Recording → minimised (segmented ring, time in the ball, the time moves) → the ball restores the recorder at
    /// the same exercise and set → paused (the time stands still) → all sets logged (completion pending).
    func testBallShowsRecordingPausedAndRestoresTheRecorder() {
        let app = launch()
        startTodaysWorkout(app)
        let log = el(app, "logSet")
        XCTAssertTrue(log.waitForExistence(timeout: 5), "required: Log set"); log.tap()
        XCTAssertTrue(el(app, "recorderLogged").waitForExistence(timeout: 5), "required: the logged set is named")
        let exercise = el(app, "recorderExercise").label, set = el(app, "recorderSet").label, logged = el(app, "recorderLogged").label
        shot("a1-recorder-one-set")
        minimiseToBall(app)
        XCTAssertTrue(ball(app).label.hasPrefix("Strength workout recording"), "required: the ball says a strength workout is recording (\(ball(app).label))")
        let v1 = ballValue(app)
        XCTAssertTrue(isClock(v1), "required: the ball carries the elapsed time as MM:SS (\(v1))")
        shot("a2-ball-recording")
        app.settleForScreenshot(3)
        let v2 = ballValue(app)
        XCTAssertTrue(isClock(v2) && v2 != v1, "required: the workout keeps running while minimised — the time moved (\(v1) → \(v2))")
        // the ball restores the recorder: same exercise, same set, the logged set and Undo still there
        ball(app).tap()
        XCTAssertTrue(el(app, "strengthRecorderV14").waitForExistence(timeout: 10), "required: the ball opens the recorder, not the panel")
        XCTAssertFalse(el(app, "trainPanel").exists, "one session at a time: the panel is not shown instead")
        XCTAssertEqual(el(app, "recorderExercise").label, exercise, "same exercise after restoring")
        XCTAssertEqual(el(app, "recorderSet").label, set, "same set after restoring")
        XCTAssertEqual(el(app, "recorderLogged").label, logged, "the logged set is still shown")
        XCTAssertEqual(el(app, "recorderState").label, "Recording", "minimising did not pause the workout")
        shot("a3-restored-recorder")
        // paused → minimised: split ring, pause bars, the time stands still
        app.buttons["recorderPause"].firstMatch.tap()
        XCTAssertTrue(el(app, "recorderState").label.hasPrefix("Paused"), "paused is said in words")
        minimiseToBall(app)
        XCTAssertTrue(ball(app).label.hasPrefix("Workout paused"), "required: the ball says the workout is paused (\(ball(app).label))")
        let p1 = ballValue(app); XCTAssertTrue(isClock(p1), "paused: the time is still shown (\(p1))")
        app.settleForScreenshot(3)
        XCTAssertEqual(ballValue(app), p1, "required: while paused the time in the ball stands still")
        shot("a4-ball-paused")
        ball(app).tap()
        XCTAssertTrue(el(app, "strengthRecorderV14").waitForExistence(timeout: 10), "the ball opens the paused workout")
        XCTAssertTrue(el(app, "recorderState").label.hasPrefix("Paused"), "still paused: opening it resumed nothing")
        XCTAssertEqual(el(app, "recorderSet").label, set, "same set")
        app.buttons["recorderPause"].firstMatch.tap()
        XCTAssertEqual(el(app, "recorderState").label, "Recording")
        // every remaining set → completion pending on the ball (three-quarter ring, "…", no time)
        let finish = el(app, "nextSetFinish")
        var taps = 0
        while !finish.exists && taps < 80 {
            let skip = app.buttons["restSkip"].firstMatch; if skip.exists { skip.tap() }
            if log.exists { log.tap() }; taps += 1
        }
        XCTAssertTrue(finish.waitForExistence(timeout: 5), "required: after the last set the recorder offers Finish (\(taps) more sets)")
        minimiseToBall(app)
        XCTAssertEqual(ball(app).label, "All sets logged, workout not saved yet", "required: completion pending on the ball")
        XCTAssertEqual(ballValue(app), "", "completion pending: no timer in the ball")
        shot("a5-ball-completion-pending")
        ball(app).tap()
        XCTAssertTrue(finish.waitForExistence(timeout: 10), "the ball returns to the workout, Finish still offered")
        print("LAB-NOTE train ball: recording \(v1) → \(v2); paused at \(p1); completion pending after \(taps) more sets")
    }

    /// (b) The app ends mid-workout. After a relaunch the ball shows "restored, paused"; the ball opens the same set
    /// with the logged set intact, and Resume continues the same session.
    func testSessionSurvivesTheAppEndingAndIsRestoredFromTheBall() {
        let app = launch()
        startTodaysWorkout(app)
        let log = el(app, "logSet")
        XCTAssertTrue(log.waitForExistence(timeout: 5), "required: Log set"); log.tap()
        XCTAssertTrue(el(app, "recorderLogged").waitForExistence(timeout: 5))
        let exercise = el(app, "recorderExercise").label, set = el(app, "recorderSet").label
        app.terminate()
        app.launchEnvironment["LAB_FRESH_DEMO"] = nil
        app.launch()
        XCTAssertTrue(app.waitForHome(name: "Demo", timeout: 30), "required: Home after the relaunch")
        XCTAssertTrue(ball(app).waitForExistence(timeout: 8), "required: the Train ball")
        let restored = NSPredicate(format: "label BEGINSWITH 'Workout restored, paused'")
        expectation(for: restored, evaluatedWith: ball(app)); waitForExpectations(timeout: 8)
        XCTAssertTrue(ball(app).label.hasPrefix("Workout restored, paused"), "required: the ball says the workout was restored and is paused (\(ball(app).label))")
        let r1 = ballValue(app); XCTAssertTrue(isClock(r1), "restored: the time is shown (\(r1))")
        app.settleForScreenshot(3)
        XCTAssertEqual(ballValue(app), r1, "restored: the time stands still until the athlete resumes")
        shot("b1-ball-restored")
        ball(app).tap()
        XCTAssertTrue(el(app, "strengthRecorderV14").waitForExistence(timeout: 10), "required: the ball opens the restored workout")
        XCTAssertEqual(el(app, "recorderExercise").label, exercise, "same exercise after the relaunch")
        XCTAssertEqual(el(app, "recorderSet").label, set, "same set after the relaunch")
        XCTAssertTrue(el(app, "recorderState").label.hasPrefix("Paused"), "restored as paused (\(el(app, "recorderState").label))")
        shot("b2-restored-recorder")
        app.buttons["recorderPause"].firstMatch.tap()
        XCTAssertEqual(el(app, "recorderState").label, "Recording", "Resume continues the same session")
        // the set logged before the app ended is still logged
        app.buttons["finishWorkout"].firstMatch.tap()
        XCTAssertTrue(el(app, "finishCount").waitForExistence(timeout: 8), "required: the Finish page counts the sets")
        XCTAssertTrue(el(app, "finishCount").label.hasPrefix("Partial · 1 of "), "required: the logged set survived the relaunch (\(el(app, "finishCount").label))")
        shot("b3-finish-after-restore")
        app.buttons["finishBackToWorkout"].firstMatch.tap()
        // resumed: the ball no longer says "restored"
        let m = app.buttons["recorderMinimise"].firstMatch
        XCTAssertTrue(m.waitForExistence(timeout: 8), "back in the recorder"); m.tap()
        XCTAssertTrue(ballReady(app), "required: the Train ball after Minimise")
        XCTAssertTrue(ball(app).label.hasPrefix("Strength workout recording"), "after Resume the ball says recording (\(ball(app).label))")
        shot("b4-ball-recording-again")
    }

    /// (c) One full superset round (sheet 04b): A1 → A2 with no rest inside the round, then the next round.
    func testSupersetRoundGoesA1A2ThenNextRound() {
        let app = launch(["LAB_DEMO_SUPERSETS": "1"])
        startTodaysWorkout(app)
        let log = el(app, "logSet")
        XCTAssertTrue(log.waitForExistence(timeout: 5), "required: Log set")
        var n = 0
        while !el(app, "recorderOverline").label.hasPrefix("SUPERSET") && n < 14 {
            let skip = app.buttons["restSkip"].firstMatch; if skip.exists { skip.tap() }
            if log.exists { log.tap() }; n += 1
        }
        let overline1 = el(app, "recorderOverline").label
        XCTAssertTrue(overline1.hasPrefix("SUPERSET") && overline1.contains("ROUND 1 OF"), "required: the recorder reaches round 1 of the superset (\(overline1))")
        let skip0 = app.buttons["restSkip"].firstMatch; if skip0.exists { skip0.tap() }
        let member = el(app, "recorderMember")
        XCTAssertTrue(member.exists, "required: the member mark before the exercise name")
        let first = member.label
        XCTAssertTrue(first.hasSuffix("1"), "the round starts with the first member (\(first))")
        XCTAssertEqual(log.label, "Log \(first)", "the button names the member")
        XCTAssertTrue(el(app, "recorderSet").label.hasPrefix("Round 1 of "), "the round is said under the name (\(el(app, "recorderSet").label))")
        if el(app, "restPlanned").exists { XCTAssertTrue(el(app, "restPlanned").label.hasPrefix("No rest before "), "no rest inside the round (\(el(app, "restPlanned").label))") }
        else { print("LAB-NOTE superset: the rest of the exercise before the superset was still shown, so the 'No rest before' line was not on screen") }
        XCTAssertTrue(el(app, "recorderNext").label.contains("same round"), "the partner is next, same round (\(el(app, "recorderNext").label))")
        let a1Exercise = el(app, "recorderExercise").label
        shot("c1-superset-a1")
        log.tap()
        // second member, same round, no rest started
        XCTAssertNotEqual(member.label, first, "required: the next member follows at once (\(member.label))")
        XCTAssertTrue(member.label.hasSuffix("2"), "A2 follows A1 (\(member.label))")
        XCTAssertNotEqual(el(app, "recorderExercise").label, a1Exercise, "the partner exercise is on screen")
        XCTAssertEqual(el(app, "recorderOverline").label, overline1, "still round 1 (\(el(app, "recorderOverline").label))")
        XCTAssertFalse(el(app, "restTimer").exists, "required: no rest runs between the members of a round")
        XCTAssertTrue(el(app, "recorderLogged").label.hasPrefix(first), "the logged line names the member (\(el(app, "recorderLogged").label))")
        let second = member.label
        shot("c2-superset-a2")
        // log through the remaining members of round 1 (two in the demo; any further member is logged the same way)
        var guardCount = 0
        while el(app, "recorderOverline").label == overline1 && guardCount < 4 { log.tap(); guardCount += 1 }
        let overline2 = el(app, "recorderOverline").label
        XCTAssertTrue(overline2.hasPrefix("SUPERSET") && overline2.contains("ROUND 2 OF"), "required: after the round the next round begins (\(overline2))")
        XCTAssertEqual(member.label, first, "round 2 starts with the first member again (\(member.label))")
        XCTAssertEqual(el(app, "recorderExercise").label, a1Exercise)
        XCTAssertTrue(el(app, "recorderSet").label.hasPrefix("Round 2 of "), el(app, "recorderSet").label)
        let rest = el(app, "restTimer")
        if rest.exists { XCTAssertEqual(el(app, "restWord").label, "rest after round", "the rest after a round is named") }
        print("LAB-NOTE superset round: \(first) → \(second) → \(overline2); rest after the round \(rest.exists ? "runs (\(rest.label))" : "is not prescribed for this pair")")
        shot("c3-superset-round-2")
    }

    /// (d) Correct a logged set. The Finish page (sheet 06e) shows counts, not set values, so the corrected value is
    /// checked where the app shows it — the correction page and the recorder's "Logged" line — and the Finish page is
    /// checked for the unchanged count. "Not done" returns the set to the workout.
    func testCorrectingALoggedSet() {
        let app = launch()
        startTodaysWorkout(app)
        let log = el(app, "logSet")
        XCTAssertTrue(log.waitForExistence(timeout: 5), "required: Log set")
        let firstSet = el(app, "recorderSet").label
        log.tap()
        XCTAssertTrue(el(app, "recorderLogged").waitForExistence(timeout: 5))
        let before = el(app, "recorderLogged").label
        func openCorrection() {
            let options = app.buttons["recorderOptions"].firstMatch
            XCTAssertTrue(options.waitForExistence(timeout: 5), "required: the ··· options"); options.tap()
            // Fast checks 15 and 17: "Correct a logged set" was a row of a pull-down menu and could not be pressed on the
            // simulator ("failed to compute hit point"), also after waiting for the menu. The options are now plain
            // buttons on a page; the row is found by its identifier and must still carry the same wording.
            let item = app.buttons["recorderOptCorrect"].firstMatch
            XCTAssertTrue(item.waitForExistence(timeout: 5), "required: 'Correct a logged set' under ···")
            XCTAssertEqual(item.label, "Correct a logged set", "required: the option keeps its wording")
            var w = 0; while !item.isHittable && w < 10 { app.settleForScreenshot(0.3); w += 1 }
            XCTAssertTrue(item.isHittable, "required: the option can be pressed"); item.tap()
            XCTAssertTrue(el(app, "correctTitle").waitForExistence(timeout: 8), "required: the correction page")
        }
        openCorrection()
        let value = first(app, prefix: "correctValue-")
        XCTAssertTrue(value.exists, "required: the logged set is listed with its value")
        let v0 = value.label
        XCTAssertTrue(before.contains(v0), "the page shows the set as it was logged (\(before) / \(v0))")
        let plus = first(app, prefix: "correctRepsPlus-")
        XCTAssertTrue(plus.exists, "required: the + step"); plus.tap()
        let v1 = value.label
        XCTAssertNotEqual(v1, v0, "required: + changes the logged value (\(v0) → \(v1))")
        shot("d1-correct-set")
        app.buttons["correctDone"].firstMatch.tap(); app.settleForScreenshot(1)
        XCTAssertTrue(el(app, "recorderLogged").waitForExistence(timeout: 8), "back in the recorder")
        XCTAssertTrue(el(app, "recorderLogged").label.contains(v1), "required: the recorder shows the corrected value (\(el(app, "recorderLogged").label))")
        // the corrected value is what the session holds: it is there when the page is opened again
        openCorrection()
        XCTAssertEqual(first(app, prefix: "correctValue-").label, v1, "required: the corrected value is stored in the session")
        app.buttons["correctDone"].firstMatch.tap(); app.settleForScreenshot(1)
        // Finish: one set, as before the correction (the page shows no set values)
        app.buttons["finishWorkout"].firstMatch.tap()
        XCTAssertTrue(el(app, "finishCount").waitForExistence(timeout: 8), "required: the Finish page")
        XCTAssertTrue(el(app, "finishCount").label.hasPrefix("Partial · 1 of "), "the correction did not add or remove a set (\(el(app, "finishCount").label))")
        shot("d2-finish-after-correction")
        app.buttons["finishBackToWorkout"].firstMatch.tap()
        // "Not done": the set goes back to the workout as a set still to do
        XCTAssertTrue(log.waitForExistence(timeout: 8), "back in the recorder")
        openCorrection()
        let unlog = first(app, prefix: "correctUnlog-")
        XCTAssertTrue(unlog.exists, "required: Not done"); unlog.tap()
        XCTAssertTrue(el(app, "correctEmpty").waitForExistence(timeout: 5), "required: no logged set is left")
        app.buttons["correctDone"].firstMatch.tap(); app.settleForScreenshot(1)
        XCTAssertTrue(log.waitForExistence(timeout: 8))
        XCTAssertFalse(el(app, "recorderLogged").exists, "the Logged line is gone")
        XCTAssertEqual(el(app, "recorderSet").label, firstSet, "required: the recorder is back at the first set")
        shot("d3-set-not-done")
        print("LAB-NOTE correction: '\(v0)' → '\(v1)'; recorder line: was '\(before)'")
    }

    /// The compact panel (06b): the ball becomes "panel open"; Cycling and Strength shortcuts; Strength opens the
    /// chooser with today's session, which opens the preparation screen. Mobility and Stretch are not offered.
    func testPanelShortcutsAndPanelOpenBall() {
        let app = launch()
        XCTAssertTrue(ball(app).waitForExistence(timeout: 8), "required: the Train ball")
        ball(app).tap()
        XCTAssertTrue(el(app, "trainPanel").waitForExistence(timeout: 8), "required: the compact panel")
        XCTAssertEqual(ball(app).label, "Train, panel open", "required: the ball says the panel is open")
        XCTAssertTrue(app.buttons["trainPanelRide"].firstMatch.exists, "required: the Cycling shortcut")
        XCTAssertEqual(app.buttons["trainPanelRide"].firstMatch.label, "Cycling")
        let strength = app.buttons["trainPanelStrength"].firstMatch
        XCTAssertTrue(strength.exists, "required: the Strength shortcut"); XCTAssertEqual(strength.label, "Strength")
        XCTAssertFalse(app.buttons["Mobility"].firstMatch.exists || app.buttons["Stretch"].firstMatch.exists, "no shortcut without a real destination")
        shot("e1-panel")
        strength.tap()
        XCTAssertTrue(el(app, "strengthPickerTitle").waitForExistence(timeout: 8), "required: the strength chooser")
        let today = app.buttons["strengthPickerToday"].firstMatch
        XCTAssertTrue(today.exists, "required: today's strength session is offered")
        XCTAssertTrue(app.buttons["strengthPickerLog"].firstMatch.exists, "required: logging a session is offered")
        shot("e2-strength-chooser")
        today.tap()
        XCTAssertTrue(el(app, "strengthPrepareV14").waitForExistence(timeout: 10), "required: the session opens on the preparation screen")
        XCTAssertEqual(app.buttons["startWorkout"].firstMatch.label, "Start", "nothing was started by choosing")
    }

    /// Save not confirmed (06f X7) → the page is closed → the ball says so ("!"), never "saved"; the ball reopens the
    /// page, and Check again confirms the one workout.
    func testUnconfirmedSaveIsShownOnTheBall() {
        let app = launch(["BC_UITEST_SAVE_UNCONFIRMED": "1"])
        startTodaysWorkout(app)
        let log = el(app, "logSet")
        XCTAssertTrue(log.waitForExistence(timeout: 5), "required: Log set"); log.tap()
        app.buttons["finishWorkout"].firstMatch.tap()
        let save = app.buttons["saveWorkout"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 8), "required: Save"); save.tap()
        XCTAssertTrue(el(app, "saveUnconfirmed").waitForExistence(timeout: 10), "required: 'Save not confirmed'")
        app.buttons["unconfirmedClose"].firstMatch.tap()
        // the page underneath (the session's own page) is closed by its own Back or Done
        let back = app.buttons["prepareBack"].firstMatch, done = app.buttons["Done"].firstMatch
        if done.waitForExistence(timeout: 6) { done.tap() } else if back.exists { back.tap() }
        XCTAssertTrue(ballReady(app), "required: the Train ball")
        XCTAssertEqual(ball(app).label, "Workout not confirmed saved", "required: the ball says the save is not confirmed")
        XCTAssertEqual(ballValue(app), "", "no timer")
        shot("f1-ball-save-uncertain")
        ball(app).tap()
        XCTAssertTrue(el(app, "saveUnconfirmed").waitForExistence(timeout: 10), "required: the ball reopens 'Save not confirmed'")
        XCTAssertFalse(el(app, "saveConfirmed").exists, "not shown as saved")
        app.buttons["saveCheckAgain"].firstMatch.tap()
        XCTAssertTrue(el(app, "saveConfirmed").waitForExistence(timeout: 10), "required: Saved once the check finds the workout")
        shot("f2-saved-after-check")
        app.buttons["saveDone"].firstMatch.tap()
        XCTAssertTrue(ballReady(app), "required: the Train ball")
        XCTAssertEqual(ball(app).label, "Train, no active session", "the ball is idle again once the save is confirmed")
    }
}
